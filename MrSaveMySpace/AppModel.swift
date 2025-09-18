import Foundation
import Photos
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var libraryStatus: PHAuthorizationStatus = .notDetermined

    let scanViewModel: ScanViewModel
    let resultsViewModel: ResultsViewModel
    let swipeDeletionViewModel: SwipeDeletionViewModel

    private let photoLibrary: PhotoLibraryManager

    init(photoLibrary: PhotoLibraryManager = PhotoLibraryManager(),
         duplicateDetector: DuplicateDetector = DuplicateDetector(),
         storageEstimator: StorageEstimator = StorageEstimator(),
         deletionManager: DeletionManager? = nil,
         scanner: PhotoScanner? = nil) {
        self.photoLibrary = photoLibrary

        let scannerInstance = scanner ?? PhotoScanner(library: photoLibrary)
        self.scanViewModel = ScanViewModel(scanner: scannerInstance)

        let deleterInstance = deletionManager ?? DeletionManager(library: photoLibrary)
        self.resultsViewModel = ResultsViewModel(photoLibrary: photoLibrary,
                                                 detector: duplicateDetector,
                                                 estimator: storageEstimator,
                                                 deleter: deleterInstance,
                                                 supportedIndexVersion: scannerInstance.indexFormatVersion)
        self.swipeDeletionViewModel = SwipeDeletionViewModel(photoLibrary: photoLibrary,
                                                             deleter: deleterInstance)

        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        libraryStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestPhotoAuthorization() {
        PhotoLibraryManager.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.libraryStatus = status
            }
        }
    }
}

public struct Fingerprint: Codable, Hashable, Sendable {
    public let localIdentifier: String
    public let creationTime: TimeInterval?
    public let width: Int
    public let height: Int
    public let dHash64: UInt64

    public init(localIdentifier: String,
                creationTime: TimeInterval?,
                width: Int,
                height: Int,
                dHash64: UInt64) {
        self.localIdentifier = localIdentifier
        self.creationTime = creationTime
        self.width = width
        self.height = height
        self.dHash64 = dHash64
    }
}

public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let representative: Fingerprint
    public var duplicates: [Fingerprint]
    public var estimatedBytes: Int64?
    public var perAssetEstimates: [String: Int64]

    public init(representative: Fingerprint,
                duplicates: [Fingerprint],
                estimatedBytes: Int64? = nil,
                perAssetEstimates: [String: Int64] = [:]) {
        self.id = UUID()
        self.representative = representative
        self.duplicates = duplicates
        self.estimatedBytes = estimatedBytes
        self.perAssetEstimates = perAssetEstimates
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: DuplicateGroup, rhs: DuplicateGroup) -> Bool {
        lhs.id == rhs.id
    }
}

struct FingerprintIndex: Codable, Sendable {
    let formatVersion: Int
    let generatedAt: Date
    let fingerprints: [Fingerprint]
}

public struct PhotoStats: Identifiable, Codable, Sendable {
    public let id = UUID()
    public let monthKey: String
    public let photoCount: Int
    public let videoCount: Int
    public let totalBytes: Int64

    public init(monthKey: String,
                photoCount: Int,
                videoCount: Int,
                totalBytes: Int64) {
        self.monthKey = monthKey
        self.photoCount = photoCount
        self.videoCount = videoCount
        self.totalBytes = totalBytes
    }
}

struct SwipeAsset: Identifiable, Hashable, Sendable {
    let id: String
    let creationDate: Date?

    init(localIdentifier: String, creationDate: Date?) {
        self.id = localIdentifier
        self.creationDate = creationDate
    }
}

struct SwipeMonth: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    var assets: [SwipeAsset]

    init(id: String, title: String, assets: [SwipeAsset]) {
        self.id = id
        self.title = title
        self.assets = assets
    }
}

enum Paths {
    static func documentsDir() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func fingerprintsURL() -> URL {
        documentsDir().appendingPathComponent("photo_fingerprints.json")
    }
}

enum JSONStore {
    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    static func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
}

enum PhotoLibError: Error {
    case fetchFailed
    case imageRequestNil
    case assetNotFound
}

final class PhotoLibraryManager {
    // MARK: Authorization
    static func requestAuthorization(_ completion: @escaping (PHAuthorizationStatus) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            completion(status)
        }
    }

    // MARK: Fetch
    func fetchAllImageAssets() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        return PHAsset.fetchAssets(with: options)
    }

    func fetchAssets(withLocalIdentifiers ids: [String]) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        return PHAsset.fetchAssets(withLocalIdentifiers: ids, options: options)
    }

    // MARK: Images
    func requestSmallImage(for asset: PHAsset,
                           targetSize: CGSize,
                           allowNetwork: Bool) async throws -> UIImage {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = allowNetwork
            options.isSynchronous = false

            PHImageManager.default().requestImage(for: asset,
                                                  targetSize: targetSize,
                                                  contentMode: .aspectFit,
                                                  options: options) { image, info in
                if let cancelled = (info?[PHImageCancelledKey] as? NSNumber)?.boolValue, cancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue, isDegraded {
                    return
                }
                if let error = info?[PHImageErrorKey] as? NSError {
                    continuation.resume(throwing: error)
                    return
                }
                guard let image else {
                    continuation.resume(throwing: PhotoLibError.imageRequestNil)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: Metadata
    func resourceSizes(for asset: PHAsset) async -> Int64? {
        let resources = PHAssetResource.assetResources(for: asset)
        var total: Int64 = 0
        var found = false
        for resource in resources {
            if let size = resource.value(forKey: "fileSize") as? Int64 {
                total += size
                found = true
            }
        }
        return found ? total : nil
    }

    func localizedCreationDate(for asset: PHAsset) -> TimeInterval? {
        asset.creationDate?.timeIntervalSince1970
    }

    // MARK: Deletion
    func performDeletion(localIdentifiers: [String]) async throws {
        guard !localIdentifiers.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
                PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoLibError.fetchFailed)
                }
            }
        }
    }
}

struct ScanResult: Sendable {
    let total: Int
    let indexed: Int
    let savedURL: URL
}

final class PhotoScanner {
    private let lib: PhotoLibraryManager
    private let targetSize: CGSize
    private let thumbnailAllowNetwork = false
    private let formatVersion = 1

    init(library: PhotoLibraryManager = PhotoLibraryManager(), targetSize: CGSize = CGSize(width: 18, height: 18)) {
        self.lib = library
        self.targetSize = targetSize
    }

    var indexFormatVersion: Int {
        formatVersion
    }

    func buildIndex(progress: @escaping (_ done: Int, _ total: Int) -> Void) async throws -> ScanResult {
        let fetchResult = lib.fetchAllImageAssets()
        let totalCount = fetchResult.count
        var processed = 0
        var stored: [Fingerprint] = []
        stored.reserveCapacity(totalCount)

        for index in 0..<totalCount {
            let asset = fetchResult.object(at: index)
            defer {
                processed += 1
                progress(processed, totalCount)
            }

            do {
                let image = try await lib.requestSmallImage(for: asset,
                                                            targetSize: targetSize,
                                                            allowNetwork: thumbnailAllowNetwork)
                let hash = ImageHasher.dHash64(from: image)
                let fingerprint = Fingerprint(
                    localIdentifier: asset.localIdentifier,
                    creationTime: lib.localizedCreationDate(for: asset),
                    width: asset.pixelWidth,
                    height: asset.pixelHeight,
                    dHash64: hash
                )
                stored.append(fingerprint)
            } catch {
                // Skip assets that fail to produce a thumbnail hash
                continue
            }
        }

        let indexFile = FingerprintIndex(
            formatVersion: formatVersion,
            generatedAt: Date(),
            fingerprints: stored
        )
        let url = Paths.fingerprintsURL()
        try JSONStore.save(indexFile, to: url)
        return ScanResult(total: totalCount, indexed: stored.count, savedURL: url)
    }
}

enum ImageHasher {
    static func dHash64(from image: UIImage) -> UInt64 {
        guard let cgImage = image.cgImage else {
            return 0
        }

        let hashWidth = 9
        let hashHeight = 8
        let bytesPerRow = hashWidth
        var pixels = [UInt8](repeating: 0, count: hashWidth * hashHeight)
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard let context = CGContext(data: &pixels,
                                      width: hashWidth,
                                      height: hashHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return 0
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: hashWidth, height: hashHeight))

        var hash: UInt64 = 0
        var bit: UInt64 = 1

        for row in 0..<hashHeight {
            for col in 0..<(hashWidth - 1) {
                let left = pixels[row * hashWidth + col]
                let right = pixels[row * hashWidth + col + 1]
                if left > right {
                    hash |= bit
                }
                bit <<= 1
            }
        }

        return hash
    }

    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}

@MainActor
final class ScanViewModel: ObservableObject {
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0
    @Published var totalCount: Int = 0
    @Published var indexedCount: Int = 0
    @Published var statusMessage: String = ""

    private let scanner: PhotoScanner

    init(scanner: PhotoScanner) {
        self.scanner = scanner
    }

    func startScan(authorizationStatus: PHAuthorizationStatus) {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            statusMessage = "Photo access not authorized."
            return
        }
        guard !isScanning else { return }

        isScanning = true
        scanProgress = 0
        totalCount = 0
        indexedCount = 0
        statusMessage = "Starting scan…"

        Task {
            do {
                let result = try await scanner.buildIndex { [weak self] done, total in
                    Task { [weak self] in
                        await MainActor.run {
                            guard let self else { return }
                            self.indexedCount = done
                            self.totalCount = total
                            self.scanProgress = total == 0 ? 0 : Double(done) / Double(total)
                        }
                    }
                }
                await completeScan(message: "Indexed \(result.indexed) / \(result.total) assets")
            } catch {
                await completeScan(message: "Scan failed: \(error.localizedDescription)")
            }
        }
    }

    private func completeScan(message: String) async {
        isScanning = false
        statusMessage = message
    }
}

final class DuplicateDetector {
    private let creationWindow: TimeInterval

    init(creationWindow: TimeInterval = 5 * 60) {
        self.creationWindow = creationWindow
    }

    func groupExactDuplicates(_ items: [Fingerprint],
                              requireSameDimensions: Bool = true) -> [DuplicateGroup] {
        guard !items.isEmpty else { return [] }

        var buckets: [UInt64: [Fingerprint]] = [:]
        for item in items {
            buckets[item.dHash64, default: []].append(item)
        }

        var groups: [DuplicateGroup] = []
        groups.reserveCapacity(buckets.count)

        for (_, candidates) in buckets {
            let dimensionBuckets: [[Fingerprint]]
            if requireSameDimensions {
                var byDimension: [String: [Fingerprint]] = [:]
                for candidate in candidates {
                    let key = "\(candidate.width)x\(candidate.height)"
                    byDimension[key, default: []].append(candidate)
                }
                dimensionBuckets = Array(byDimension.values)
            } else {
                dimensionBuckets = [candidates]
            }

            for subset in dimensionBuckets {
                let clusters = clusterByCreationTime(subset)
                for cluster in clusters where cluster.count >= 2 {
                    let sortedCluster = cluster.sorted(by: betterForKeeping(_:than:))
                    guard let representative = sortedCluster.first else { continue }
                    let duplicates = Array(sortedCluster.dropFirst())
                    groups.append(DuplicateGroup(representative: representative, duplicates: duplicates))
                }
            }
        }

        return groups
    }

    private func clusterByCreationTime(_ items: [Fingerprint]) -> [[Fingerprint]] {
        guard !items.isEmpty else { return [] }

        let sorted = items.sorted { lhs, rhs in
            switch (lhs.creationTime, rhs.creationTime) {
            case let (l?, r?):
                if l == r { return lhs.localIdentifier < rhs.localIdentifier }
                return l < r
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.localIdentifier < rhs.localIdentifier
            }
        }

        var clusters: [[Fingerprint]] = []
        var current: [Fingerprint] = []

        for candidate in sorted {
            guard let last = current.last else {
                current = [candidate]
                continue
            }
            if creationTimesClose(last, candidate) {
                current.append(candidate)
            } else {
                if current.count >= 2 {
                    clusters.append(current)
                }
                current = [candidate]
            }
        }

        if current.count >= 2 {
            clusters.append(current)
        }

        return clusters
    }

    private func creationTimesClose(_ lhs: Fingerprint, _ rhs: Fingerprint) -> Bool {
        switch (lhs.creationTime, rhs.creationTime) {
        case let (l?, r?):
            return abs(l - r) <= creationWindow
        case (.none, .none):
            return true
        default:
            return false
        }
    }

    private func betterForKeeping(_ lhs: Fingerprint, than rhs: Fingerprint) -> Bool {
        let lhsArea = lhs.width * lhs.height
        let rhsArea = rhs.width * rhs.height
        if lhsArea != rhsArea {
            return lhsArea > rhsArea
        }
        switch (lhs.creationTime, rhs.creationTime) {
        case let (l?, r?):
            return l < r
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return lhs.localIdentifier < rhs.localIdentifier
        }
    }
}

final class StorageEstimator {
    func estimateGroups(_ groups: [DuplicateGroup],
                        using lib: PhotoLibraryManager) async throws -> [DuplicateGroup] {
        guard !groups.isEmpty else { return [] }
        var enriched: [DuplicateGroup] = []
        enriched.reserveCapacity(groups.count)

        for var group in groups {
            var totalBytes: Int64 = 0
            var perAsset: [String: Int64] = [:]

            for fingerprint in group.duplicates {
                let size = await resolveSize(for: fingerprint, using: lib)
                perAsset[fingerprint.localIdentifier] = size
                totalBytes += size
            }

            group.estimatedBytes = totalBytes
            group.perAssetEstimates = perAsset
            enriched.append(group)
        }

        return enriched
    }

    private func resolveSize(for fingerprint: Fingerprint,
                             using lib: PhotoLibraryManager) async -> Int64 {
        let fetch = lib.fetchAssets(withLocalIdentifiers: [fingerprint.localIdentifier])
        guard let asset = fetch.firstObject else {
            return estimateBytesFromResolution(width: fingerprint.width, height: fingerprint.height)
        }
        if let size = await lib.resourceSizes(for: asset) {
            return size
        }
        return estimateBytesFromResolution(width: fingerprint.width, height: fingerprint.height)
    }

    func estimateBytesFromResolution(width: Int, height: Int, jpegFactor: Double = 0.25) -> Int64 {
        let pixels = max(width, 1) * max(height, 1)
        let estimated = Double(pixels) * jpegFactor
        return Int64(estimated)
    }
}

@MainActor
final class ResultsViewModel: ObservableObject {
    @Published private(set) var duplicateGroups: [DuplicateGroup] = []
    @Published private(set) var totalEstimatedBytes: Int64 = 0
    @Published var statusMessage: String = ""
    @Published var isLoading: Bool = false
    @Published private var selectedIdentifiers: Set<String> = []

    private let photoLibrary: PhotoLibraryManager
    private let detector: DuplicateDetector
    private let estimator: StorageEstimator
    private let deleter: DeletionManager
    private let supportedIndexVersion: Int
    private let thumbnailSize = CGSize(width: 120, height: 120)
    private var thumbnailCache: [String: UIImage] = [:]

    init(photoLibrary: PhotoLibraryManager,
         detector: DuplicateDetector,
         estimator: StorageEstimator,
         deleter: DeletionManager,
         supportedIndexVersion: Int) {
        self.photoLibrary = photoLibrary
        self.detector = detector
        self.estimator = estimator
        self.deleter = deleter
        self.supportedIndexVersion = supportedIndexVersion
    }

    var selectedCount: Int {
        selectedIdentifiers.count
    }

    func isSelected(_ identifier: String) -> Bool {
        selectedIdentifiers.contains(identifier)
    }

    func setSelection(_ isSelected: Bool, for identifier: String) {
        if isSelected {
            selectedIdentifiers.insert(identifier)
        } else {
            selectedIdentifiers.remove(identifier)
        }
    }

    func estimatedBytes(for identifier: String) -> Int64? {
        for group in duplicateGroups {
            if let value = group.perAssetEstimates[identifier] {
                return value
            }
        }
        return nil
    }

    func loadDuplicates() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let url = Paths.fingerprintsURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                duplicateGroups = []
                totalEstimatedBytes = 0
                statusMessage = "No fingerprint index found. Run a scan first."
                return
            }

            let index = try JSONStore.load(FingerprintIndex.self, from: url)
            guard index.formatVersion == supportedIndexVersion else {
                duplicateGroups = []
                totalEstimatedBytes = 0
                statusMessage = "Fingerprint index is outdated. Run a new scan."
                return
            }

            let groups = detector.groupExactDuplicates(index.fingerprints)
            let enriched = try await estimator.estimateGroups(groups, using: photoLibrary)
            duplicateGroups = enriched
            totalEstimatedBytes = enriched.compactMap(\.estimatedBytes).reduce(0, +)
            selectedIdentifiers.removeAll()
            thumbnailCache.removeAll()
            statusMessage = enriched.isEmpty ? "No exact duplicates detected." : "Found \(enriched.count) duplicate groups."
        } catch {
            duplicateGroups = []
            totalEstimatedBytes = 0
            statusMessage = "Detection failed: \(error.localizedDescription)"
        }
    }

    func deleteSelected() async {
        let ids = Array(selectedIdentifiers)
        guard !ids.isEmpty else { return }
        do {
            try await deleter.deleteAssets(withLocalIdentifiers: ids)
            selectedIdentifiers.removeAll()
            let deletionMessage = "Requested deletion for \(ids.count) assets."
            await loadDuplicates()
            let detectionMessage = statusMessage
            if detectionMessage.isEmpty {
                statusMessage = deletionMessage
            } else {
                statusMessage = "\(deletionMessage)\n\(detectionMessage)"
            }
        } catch {
            statusMessage = "Deletion failed: \(error.localizedDescription)"
        }
    }

    func thumbnail(for fingerprint: Fingerprint) async -> UIImage? {
        if let cached = thumbnailCache[fingerprint.localIdentifier] {
            return cached
        }

        let fetch = photoLibrary.fetchAssets(withLocalIdentifiers: [fingerprint.localIdentifier])
        guard let asset = fetch.firstObject else {
            return nil
        }

        do {
            let image = try await photoLibrary.requestSmallImage(for: asset,
                                                                   targetSize: thumbnailSize,
                                                                   allowNetwork: true)
            thumbnailCache[fingerprint.localIdentifier] = image
            return image
        } catch {
            return nil
        }
    }

    func formattedBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

final class DeletionManager {
    private let lib: PhotoLibraryManager

    init(library: PhotoLibraryManager = PhotoLibraryManager()) {
        self.lib = library
    }

    func deleteAssets(withLocalIdentifiers ids: [String]) async throws {
        try await lib.performDeletion(localIdentifiers: ids)
    }
}

@MainActor
final class SwipeDeletionViewModel: ObservableObject {
    struct MonthSummary: Identifiable, Hashable {
        let id: String
        let title: String
        let totalCount: Int
        let pendingDeletionCount: Int
    }

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var months: [MonthSummary] = []

    private let photoLibrary: PhotoLibraryManager
    private let deleter: DeletionManager
    private var monthsStorage: [String: SwipeMonth] = [:]

    init(photoLibrary: PhotoLibraryManager,
         deleter: DeletionManager) {
        self.photoLibrary = photoLibrary
        self.deleter = deleter
    }

    func loadMonths() {
        guard !isLoading else { return }
        isLoading = true
        statusMessage = "Fetching photos…"

        Task {
            defer { isLoading = false }
            do {
                try await fetchMonths()
                statusMessage = months.isEmpty ? "No photos available." : ""
            } catch {
                statusMessage = "Failed to fetch photos: \(error.localizedDescription)"
            }
        }
    }

    func detailViewModel(forMonthID id: String) -> SwipeMonthDetailViewModel? {
        guard let month = monthsStorage[id] else { return nil }
        let detail = SwipeMonthDetailViewModel(month: month,
                                               photoLibrary: photoLibrary,
                                               deleter: deleter)
        detail.onStateChange = { [weak self] state in
            self?.updateSummary(id: id, pending: state.pendingDeletionCount, total: state.totalCount)
        }
        detail.onMonthMutated = { [weak self] updatedMonth in
            self?.storeMonth(updatedMonth)
        }
        return detail
    }

    private func fetchMonths() async throws {
        let fetchResult = photoLibrary.fetchAllImageAssets()
        guard fetchResult.count > 0 else {
            monthsStorage = [:]
            months = []
            return
        }

        var grouped: [String: [SwipeAsset]] = [:]
        let calendar = Calendar.current

        for index in stride(from: fetchResult.count - 1, through: 0, by: -1) {
            let asset = fetchResult.object(at: index)
            let creationDate = asset.creationDate
            let components = calendar.dateComponents([.year, .month], from: creationDate ?? Date())
            let monthKey: String
            if let year = components.year, let month = components.month {
                monthKey = String(format: "%04d-%02d", year, month)
            } else {
                monthKey = "unknown"
            }
            let assetModel = SwipeAsset(localIdentifier: asset.localIdentifier, creationDate: creationDate)
            grouped[monthKey, default: []].append(assetModel)
        }

        var storage: [String: SwipeMonth] = [:]
        var summaries: [MonthSummary] = []

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let displayFormatter = DateFormatter()
        displayFormatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")

        let sortedKeys = grouped.keys.sorted(by: >)
        for key in sortedKeys {
            let assets = grouped[key, default: []].sorted { lhs, rhs in
                (lhs.creationDate ?? Date.distantPast) > (rhs.creationDate ?? Date.distantPast)
            }
            let title: String
            if key == "unknown" {
                title = "Unknown"
            } else if let date = formatter.date(from: key) {
                title = displayFormatter.string(from: date)
            } else {
                title = key
            }
            let month = SwipeMonth(id: key, title: title, assets: assets)
            storage[key] = month
            summaries.append(MonthSummary(id: key,
                                          title: title,
                                          totalCount: assets.count,
                                          pendingDeletionCount: 0))
        }

        monthsStorage = storage
        months = summaries
    }

    private func storeMonth(_ month: SwipeMonth) {
        monthsStorage[month.id] = month
        updateSummary(id: month.id, pending: 0, total: month.assets.count)
    }

    private func updateSummary(id: String, pending: Int, total: Int) {
        months = months.map { summary in
            guard summary.id == id else { return summary }
            return MonthSummary(id: summary.id,
                                title: summary.title,
                                totalCount: total,
                                pendingDeletionCount: pending)
        }
    }
}

@MainActor
final class SwipeMonthDetailViewModel: ObservableObject {
    enum SwipeDecision {
        case keep
        case delete
    }

    struct State {
        let totalCount: Int
        let pendingDeletionCount: Int
    }

    @Published private(set) var month: SwipeMonth
    @Published private(set) var currentAsset: SwipeAsset?
    @Published private(set) var currentImage: UIImage?
    @Published private(set) var previewAssets: [SwipeAsset] = []
    @Published private(set) var isPerformingDeletion: Bool = false
    @Published var statusMessage: String = ""

    var onStateChange: ((State) -> Void)?
    var onMonthMutated: ((SwipeMonth) -> Void)?

    private let photoLibrary: PhotoLibraryManager
    private let deleter: DeletionManager
    private var decisions: [String: SwipeDecision] = [:]
    private var decisionHistory: [String] = []
    private var imageCache: [String: UIImage] = [:]
    private var currentIndex: Int = 0

    init(month: SwipeMonth,
         photoLibrary: PhotoLibraryManager,
         deleter: DeletionManager) {
        self.month = month
        self.photoLibrary = photoLibrary
        self.deleter = deleter
        prepareInitialState()
    }

    func refresh() {
        prepareInitialState()
    }

    func handleSwipe(to decision: SwipeDecision) {
        guard let asset = currentAsset else { return }
        decisions[asset.id] = decision
        decisionHistory.append(asset.id)
        advanceToNextAsset()
        notifyStateChange()
    }

    func undoLastDecision() {
        guard let last = decisionHistory.popLast() else { return }
        decisions.removeValue(forKey: last)
        if let index = month.assets.firstIndex(where: { $0.id == last }) {
            currentIndex = index
            Task { await loadCurrentAsset() }
        }
        notifyStateChange()
    }

    func deletePending() {
        let ids = pendingDeletionIdentifiers
        guard !ids.isEmpty else {
            statusMessage = "No photos marked for deletion."
            return
        }
        isPerformingDeletion = true
        statusMessage = "Deleting \(ids.count) photos…"

        Task {
            do {
                try await deleter.deleteAssets(withLocalIdentifiers: ids)
                applyDeletion(for: ids)
                statusMessage = "Deleted \(ids.count) photos."
            } catch {
                statusMessage = "Deletion failed: \(error.localizedDescription)"
            }
            isPerformingDeletion = false
            notifyStateChange()
        }
    }

    var pendingDeletionIdentifiers: [String] {
        decisions.compactMap { key, value in
            value == .delete ? key : nil
        }
    }

    var pendingDeletionCount: Int {
        pendingDeletionIdentifiers.count
    }

    var undecidedCount: Int {
        month.assets.filter { decisions[$0.id] == nil }.count
    }

    var hasPhotos: Bool {
        !month.assets.isEmpty
    }

    var canUndo: Bool {
        !decisionHistory.isEmpty
    }

    private func prepareInitialState() {
        currentIndex = 0
        decisions = [:]
        decisionHistory = []
        statusMessage = ""
        Task {
            await loadCurrentAsset()
            notifyStateChange()
        }
    }

    private func advanceToNextAsset() {
        let total = month.assets.count
        var index = currentIndex + 1
        while index < total {
            let candidate = month.assets[index]
            if decisions[candidate.id] == nil {
                currentIndex = index
                Task { await loadCurrentAsset() }
                return
            }
            index += 1
        }
        currentAsset = nil
        currentImage = nil
        previewAssets = []
    }

    private func loadCurrentAsset() async {
        let undecidedIndices = month.assets.enumerated()
            .filter { decisions[$0.element.id] == nil }
        if undecidedIndices.isEmpty {
            currentAsset = nil
            currentImage = nil
            previewAssets = []
            return
        }

        if let explicitIndex = month.assets.indices.first(where: { decisions[month.assets[$0].id] == nil && $0 >= currentIndex }) {
            currentIndex = explicitIndex
        } else if let firstUndecided = undecidedIndices.first?.offset {
            currentIndex = firstUndecided
        }

        let asset = month.assets[currentIndex]
        currentAsset = asset
        currentImage = await fetchImage(for: asset, targetSize: CGSize(width: 900, height: 900))

        let previews = month.assets.enumerated()
            .filter { index, element in
                index > currentIndex && decisions[element.id] == nil
            }
            .map(\.element)
        previewAssets = Array(previews.prefix(8))
    }

    private func fetchImage(for asset: SwipeAsset, targetSize: CGSize) async -> UIImage? {
        if let cached = imageCache[asset.id] {
            return cached
        }
        let fetch = photoLibrary.fetchAssets(withLocalIdentifiers: [asset.id])
        guard let phAsset = fetch.firstObject else {
            return nil
        }
        do {
            let image = try await photoLibrary.requestSmallImage(for: phAsset,
                                                                  targetSize: targetSize,
                                                                  allowNetwork: true)
            imageCache[asset.id] = image
            return image
        } catch {
            return nil
        }
    }

    private func applyDeletion(for ids: [String]) {
        month.assets.removeAll { asset in ids.contains(asset.id) }
        decisionHistory.removeAll { ids.contains($0) }
        decisions = decisions.filter { !ids.contains($0.key) }
        onMonthMutated?(month)
        if currentIndex >= month.assets.count {
            currentIndex = max(0, month.assets.count - 1)
        }
    }

    func thumbnail(for asset: SwipeAsset, targetSize: CGSize) async -> UIImage? {
        await fetchImage(for: asset, targetSize: targetSize)
    }

    private func notifyStateChange() {
        let pending = decisions.values.filter { $0 == .delete }.count
        onStateChange?(State(totalCount: month.assets.count, pendingDeletionCount: pending))
    }
}

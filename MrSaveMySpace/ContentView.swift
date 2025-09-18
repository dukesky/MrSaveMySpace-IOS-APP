import Photos
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        NavigationView {
            List {
                AuthorizationSectionView(app: app)
                ToolsSectionView(app: app)
                StatusSectionView(scanViewModel: app.scanViewModel,
                                   resultsViewModel: app.resultsViewModel)
            }
            .navigationTitle("MrSaveMySpace")
            .onAppear { app.refreshAuthorizationStatus() }
        }
    }
}

private struct AuthorizationSectionView: View {
    @ObservedObject var app: AppModel

    var body: some View {
        Section("Authorization") {
            switch app.libraryStatus {
            case .notDetermined:
                Button {
                    app.requestPhotoAuthorization()
                } label: {
                    Label("Grant Photo Access", systemImage: "photo.on.rectangle")
                }
                Text("Required to scan and clean your library.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .denied, .restricted:
                Text("Photo access denied or restricted. Enable in Settings > Privacy & Security > Photos.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .limited:
                Text("Limited access: only selected photos will be scanned.")
                Button("Request Again") {
                    app.requestPhotoAuthorization()
                }
            case .authorized:
                Label("Access granted", systemImage: "checkmark.seal.fill")
            @unknown default:
                Text("Unknown authorization status")
            }
        }
    }
}

private struct ToolsSectionView: View {
    @ObservedObject var app: AppModel

    var body: some View {
        Section("Tools") {
            NavigationLink("Fast Detection") {
                ScanView(viewModel: app.scanViewModel)
                    .environmentObject(app)
            }
            NavigationLink("Exact Duplicates") {
                ResultsView(viewModel: app.resultsViewModel)
            }
            NavigationLink("Swipe Deletion") {
                SwipeDeletionListView(viewModel: app.swipeDeletionViewModel)
            }
            NavigationLink("Similar Photos") { Text("Coming soon") }
            NavigationLink("Photo Analysis") { Text("Coming soon") }
        }
    }
}

private struct StatusSectionView: View {
    @ObservedObject var scanViewModel: ScanViewModel
    @ObservedObject var resultsViewModel: ResultsViewModel

    var body: some View {
        Section("Status") {
            if !scanViewModel.statusMessage.isEmpty {
                Text(scanViewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !resultsViewModel.statusMessage.isEmpty {
                Text(resultsViewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if scanViewModel.statusMessage.isEmpty && resultsViewModel.statusMessage.isEmpty {
                Text("No updates yet. Run a scan to get started.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ScanView: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var viewModel: ScanViewModel

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: viewModel.scanProgress, total: 1)
                .progressViewStyle(.linear)
            Text("Indexed \(viewModel.indexedCount) / \(viewModel.totalCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(viewModel.isScanning ? "Scanning…" : "Scan Photos") {
                viewModel.startScan(authorizationStatus: app.libraryStatus)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isScanning)
            Text(viewModel.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("Fast Detection")
    }
}

struct ResultsView: View {
    @ObservedObject var viewModel: ResultsViewModel
    @State private var showConfirmation = false

    var body: some View {
        List {
            summarySection

            if viewModel.isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading duplicates…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(viewModel.duplicateGroups) { group in
                    DuplicateGroupSection(group: group, viewModel: viewModel)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Exact Duplicates")
        .safeAreaInset(edge: .bottom) {
            deleteInset
        }
        .confirmationDialog("Delete selected photos?", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button("Delete \(viewModel.selectedCount) items", role: .destructive) {
                Task {
                    await viewModel.deleteSelected()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will move to Recently Deleted, where you can recover them for 30 days.")
        }
        .task {
            await viewModel.loadDuplicates()
        }
    }

    private var summarySection: some View {
        Section("Summary") {
            Text("Estimated savings: \(viewModel.formattedBytes(viewModel.totalEstimatedBytes))")
                .font(.subheadline)
            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deleteInset: some View {
        VStack {
            Button("Delete Selected (\(viewModel.selectedCount))") {
                showConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedCount == 0)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
    }
}

private struct DuplicateGroupSection: View {
    let group: DuplicateGroup
    @ObservedObject var viewModel: ResultsViewModel

    var body: some View {
        Section(header: Text("Group \(group.id.uuidString.prefix(6))")) {
            Label {
                Text("Keeping \(group.representative.localIdentifier)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }

            if let estimate = group.estimatedBytes, estimate > 0 {
                Text("Group savings: \(viewModel.formattedBytes(estimate))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(group.duplicates, id: \.localIdentifier) { fingerprint in
                DuplicateAssetRow(fingerprint: fingerprint,
                                  viewModel: viewModel,
                                  toggle: binding(for: fingerprint.localIdentifier, in: viewModel))
            }
        }
    }

    private func binding(for identifier: String, in viewModel: ResultsViewModel) -> Binding<Bool> {
        Binding(get: {
            viewModel.isSelected(identifier)
        }, set: { newValue in
            viewModel.setSelection(newValue, for: identifier)
        })
    }
}

private struct DuplicateAssetRow: View {
    let fingerprint: Fingerprint
    @ObservedObject var viewModel: ResultsViewModel
    let toggle: Binding<Bool>
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView
            VStack(alignment: .leading, spacing: 4) {
                Text(fingerprint.localIdentifier)
                    .font(.body)
                    .lineLimit(1)
                if let bytes = viewModel.estimatedBytes(for: fingerprint.localIdentifier) {
                    Text(viewModel.formattedBytes(bytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("Delete", isOn: toggle)
                .labelsHidden()
        }
        .task {
            thumbnail = await viewModel.thumbnail(for: fingerprint)
        }
    }

    private var thumbnailView: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SwipeDeletionListView: View {
        @ObservedObject var viewModel: SwipeDeletionViewModel

    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView("Loading…")
            }

            ForEach(viewModel.months) { month in
                NavigationLink {
                    if let detailViewModel = viewModel.detailViewModel(forMonthID: month.id) {
                        SwipeMonthDetailContainer(viewModel: detailViewModel)
                    } else {
                        Text("Unable to load month")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(month.title)
                            .font(.headline)
                        Text("Photos: \(month.totalCount)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if month.pendingDeletionCount > 0 {
                            Text("Pending deletion: \(month.pendingDeletionCount)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Swipe Deletion")
        .onAppear {
            viewModel.loadMonths()
        }
    }
}

private struct SwipeMonthDetailContainer: View {
    @StateObject var viewModel: SwipeMonthDetailViewModel

    init(viewModel: SwipeMonthDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SwipeMonthDetailView(viewModel: viewModel)
    }
}

struct SwipeMonthDetailView: View {
    @ObservedObject var viewModel: SwipeMonthDetailViewModel
    @State private var dragOffset: CGSize = .zero
    @State private var isDeciding: Bool = false

    private let swipeThreshold: CGFloat = 120

    var body: some View {
        VStack(spacing: 24) {
            swipeCard
                .frame(maxWidth: .infinity, maxHeight: 420)

            if !viewModel.previewAssets.isEmpty {
                previewStrip
            }

            infoSection

            controls
        }
        .padding()
        .navigationTitle(viewModel.month.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.deletePending()
                } label: {
                    if viewModel.isPerformingDeletion {
                        ProgressView()
                    } else {
                        Text("Delete Pending")
                    }
                }
                .disabled(viewModel.isPerformingDeletion || viewModel.pendingDeletionCount == 0)
            }
        }
    }

    private var swipeCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(radius: 8)

            if let image = viewModel.currentImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(decisionOverlay)
                    .offset(dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                    .gesture(dragGesture)
                    .animation(.spring(), value: dragOffset)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(viewModel.hasPhotos ? "All photos reviewed" : "No photos available")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var decisionOverlay: some View {
        Group {
            if dragOffset.width > 40 {
                overlayLabel(text: "KEEP", color: .green)
            } else if dragOffset.width < -40 {
                overlayLabel(text: "DELETE", color: .red)
            }
        }
    }

    private func overlayLabel(text: String, color: Color) -> some View {
        Text(text)
            .font(.headline.weight(.bold))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(color.opacity(0.75))
            .foregroundColor(.white)
            .clipShape(Capsule())
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var previewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.previewAssets) { asset in
                    SwipePreviewThumbnail(asset: asset, viewModel: viewModel)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 90)
    }

    private var infoSection: some View {
        VStack(spacing: 8) {
            Text("Pending deletion: \(viewModel.pendingDeletionCount)")
                .font(.subheadline)
            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.undoLastDecision()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canUndo)

            Button {
                viewModel.handleSwipe(to: .keep)
            } label: {
                Label("Keep", systemImage: "hand.thumbsup")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(viewModel.currentAsset == nil)

            Button {
                viewModel.handleSwipe(to: .delete)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(viewModel.currentAsset == nil)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
                isDeciding = true
            }
            .onEnded { value in
                let translation = value.translation
                if abs(translation.width) > swipeThreshold {
                    let decision: SwipeMonthDetailViewModel.SwipeDecision = translation.width > 0 ? .keep : .delete
                    viewModel.handleSwipe(to: decision)
                }
                withAnimation(.spring()) {
                    dragOffset = .zero
                    isDeciding = false
                }
            }
    }
}

private struct SwipePreviewThumbnail: View {
    let asset: SwipeAsset
    @ObservedObject var viewModel: SwipeMonthDetailViewModel
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        ProgressView()
                            .progressViewStyle(.circular)
                    )
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task {
            image = await viewModel.thumbnail(for: asset, targetSize: CGSize(width: 200, height: 200))
        }
    }
}

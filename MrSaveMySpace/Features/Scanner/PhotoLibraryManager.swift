import Foundation
import Photos

/// Thin wrapper for interacting with Photo Library: authorization, fetching assets (more later)
enum PhotoLibraryManager {
    static func requestAuthorization(_ completion: @escaping (PHAuthorizationStatus) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            completion(status)
        }
    }
}

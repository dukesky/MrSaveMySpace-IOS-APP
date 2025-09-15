import Foundation
import Photos
import SwiftUI

final class AppModel: ObservableObject {
    // Photo library authorization status (observed by UI)
    @Published var libraryStatus: PHAuthorizationStatus = .notDetermined
    
    // (Reserved) scan progress/statistics (will be used in Step 3)
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0
    @Published var totalCount: Int = 0
    @Published var indexedCount: Int = 0
    @Published var lastMessage: String = ""
    
    // Request photo authorization from system
    func requestPhotoAuthorization() {
        PhotoLibraryManager.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.libraryStatus = status
            }
        }
    }
    
    // Refresh current authorization status at app start or view appear
    func refreshAuthorizationStatus() {
        libraryStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
}

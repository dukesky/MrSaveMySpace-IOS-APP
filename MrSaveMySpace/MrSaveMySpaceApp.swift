import SwiftUI

@main
struct MrSaveMySpaceApp: App {
    @StateObject private var appModel = AppModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .onAppear {
                    // Sync current authorization status when app launches
                    appModel.refreshAuthorizationStatus()
                }
        }
    }
}

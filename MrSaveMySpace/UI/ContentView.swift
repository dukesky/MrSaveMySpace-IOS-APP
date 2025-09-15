//import SwiftUI
import Photos

struct ContentView: View {
    @EnvironmentObject var app: AppModel
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("MrSaveMySpace")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Group {
                    switch app.libraryStatus {
                    case .notDetermined:
                        Text("To analyze and clean duplicate/similar photos to free up space, access to your photo library is required.")
                            .multilineTextAlignment(.center)
                        Button {
                            app.requestPhotoAuthorization()
                        } label: {
                            Label("Grant Photo Access", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(.borderedProminent)
                        
                    case .denied, .restricted:
                        VStack(spacing: 8) {
                            Text("Photo access is denied or restricted")
                                .font(.headline)
                            Text("Go to Settings > Privacy & Security > Photos > MrSaveMySpace to allow access.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                    case .limited:
                        VStack(spacing: 8) {
                            Text("Currently in Limited Photo Access mode")
                                .font(.headline)
                            Text("Only the photos you selected are available for scanning. You can change to 'All Photos' in system settings.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Button("Request Authorization Again") {
                            app.requestPhotoAuthorization()
                        }
                        
                    case .authorized:
                        VStack(spacing: 8) {
                            Label("Photo library access granted", systemImage: "checkmark.seal.fill")
                                .font(.headline)
                            Text("Next: add scanning entry and progress view (Step 3)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        
                    @unknown default:
                        Text("Unknown authorization status")
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Storage Arrange")
        }
    }
}

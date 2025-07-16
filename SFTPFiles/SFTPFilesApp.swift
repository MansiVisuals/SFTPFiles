import SwiftUI
import FileProvider

@main
struct SFTPFilesApp: App {
    @StateObject private var viewModel = SFTPConnectionViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
    
    init() {
        // Remove all background task registration
        // All sync will be handled by NATS real-time events
        NSLog("SFTPFiles: App initialized with real-time sync")
    }
}

// Remove all background task related code
// The app now relies on NATS for real-time updates instead of background polling

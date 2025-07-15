import SwiftUI
import BackgroundTasks
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
        registerBackgroundTasks()
    }
    
    private func registerBackgroundTasks() {
        let bgTaskIdentifier = "com.mansivisuals.sftpfiles.refresh"
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskIdentifier, using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }
    
    private func handleAppRefresh(task: BGAppRefreshTask) {
        NSLog("SFTPFiles: Background task started")
        
        // Create a task to handle the background work
        let backgroundTask = Task {
            await performBackgroundSync()
        }
        
        // Set up task completion
        task.expirationHandler = {
            NSLog("SFTPFiles: Background task expired")
            backgroundTask.cancel()
            task.setTaskCompleted(success: false)
        }
        
        // Wait for completion
        Task {
            await backgroundTask.value
            NSLog("SFTPFiles: Background task completed successfully")
            task.setTaskCompleted(success: true)
        }
    }
    
    private func performBackgroundSync() async {
        NSLog("SFTPFiles: Performing background sync")
        
        // Just trigger a manual sync - let the polling manager handle it
        await MainActor.run {
            viewModel.pollingManager.manualSync()
        }
        
        NSLog("SFTPFiles: Background sync completed")
    }
}
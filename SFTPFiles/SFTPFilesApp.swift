import SwiftUI
import BackgroundTasks

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
        // Schedule next refresh
        viewModel.pollingManager.scheduleBackgroundRefresh()
        
        // Perform connection checks
        for connection in viewModel.connections {
            if connection.isPollingEnabled {
                viewModel.pollingManager.checkConnection(connection)
            }
        }
        
        // Complete task
        task.setTaskCompleted(success: true)
    }
}
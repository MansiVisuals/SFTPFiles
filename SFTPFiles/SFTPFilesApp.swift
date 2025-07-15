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
        
        // Schedule next refresh
        viewModel.pollingManager.scheduleBackgroundRefresh()
        
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
        
        let group = DispatchGroup()
        
        // Check connections that have polling enabled
        for connection in viewModel.connections {
            if connection.isPollingEnabled {
                group.enter()
                
                viewModel.pollingManager.checkConnection(connection) {
                    group.leave()
                }
            }
        }
        
        // Wait for all connection checks to complete
        group.wait()
        
        // Trigger Files app sync if enabled and not using NATS
        if viewModel.pollingManager.isFilesSyncEnabled && !viewModel.pollingManager.isNATSEnabled {
            NSLog("SFTPFiles: Triggering Files app sync")
            await syncFilesApp()
        }
        
        // Update last sync time
        await MainActor.run {
            viewModel.pollingManager.lastSyncDate = Date()
        }
        
        NSLog("SFTPFiles: Background sync completed")
    }
    
    private func syncFilesApp() async {
        return await withCheckedContinuation { continuation in
            NSFileProviderManager.getDomainsWithCompletionHandler { domains, error in
                guard error == nil else {
                    NSLog("SFTPFiles: Failed to get domains: \(error!.localizedDescription)")
                    continuation.resume()
                    return
                }
                
                let syncGroup = DispatchGroup()
                
                for connection in viewModel.connections {
                    let domainIdentifier = NSFileProviderDomainIdentifier(rawValue: connection.id.uuidString)
                    
                    // Find the domain that matches our connection
                    if let domain = domains.first(where: { $0.identifier == domainIdentifier }) {
                        syncGroup.enter()
                        
                        NSFileProviderManager(for: domain)?.signalEnumerator(for: NSFileProviderItemIdentifier.rootContainer) { error in
                            if let error = error {
                                NSLog("SFTPFiles: Background sync failed for \(connection.name): \(error.localizedDescription)")
                            } else {
                                NSLog("SFTPFiles: Background sync completed for \(connection.name)")
                            }
                            syncGroup.leave()
                        }
                    } else {
                        NSLog("SFTPFiles: Domain not found for connection: \(connection.name)")
                    }
                }
                
                syncGroup.notify(queue: .main) {
                    continuation.resume()
                }
            }
        }
    }
}
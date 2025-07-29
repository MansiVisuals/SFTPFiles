//
//  PollingService.swift
//  SFTPFilesFileProvider (File Provider Extension)
//
//  Created by Maikel Mansi on 28/07/2025.
//

import Foundation
import FileProvider

protocol PollingServiceDelegate: AnyObject {
    func pollingServiceDidDetectChanges(_ changes: [String])
}

class PollingService {
    weak var delegate: PollingServiceDelegate?
    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 300 // 5 minutes
    
    // Create instances directly - will work regardless of singleton availability
    private lazy var persistenceService = ExtensionPersistenceService()
    private lazy var keychainService = ExtensionKeychainService()
    private var lastKnownState: [String: [String: Any]] = [:]
    
    func startPolling() {
        guard pollingTimer == nil else { return }
        
        print("Starting polling service with \(pollingInterval) second interval")
        
        // Initial poll after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            self.pollForChanges()
        }
        
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { _ in
            self.pollForChanges()
        }
    }
    
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        print("Stopped polling for file changes")
    }
    
    private func pollForChanges() {
        print("Polling for file changes...")
        
        Task {
            let connections = persistenceService.loadConnections()
            guard !connections.isEmpty else {
                print("No connections to poll")
                return
            }
            
            var changedPaths: [String] = []
            
            for connection in connections {
                // Only poll connected or auto-connect connections
                if connection.autoConnect || persistenceService.getConnectionState(for: connection.id) == .connected {
                    if let changes = await checkConnectionForChanges(connection) {
                        changedPaths.append(contentsOf: changes)
                    }
                }
            }
            
            // Capture the final state before passing to MainActor
            let finalChangedPaths = changedPaths
            
            if !finalChangedPaths.isEmpty {
                await MainActor.run {
                    delegate?.pollingServiceDidDetectChanges(finalChangedPaths)
                }
            } else {
                print("No changes detected during polling")
            }
        }
    }
    
    private func checkConnectionForChanges(_ connection: SFTPConnection) async -> [String]? {
        guard let password = keychainService.getPassword(for: connection.id) else {
            print("No password available for connection: \(connection.name)")
            return nil
        }
        
        do {
            let sftp = try SharedSFTPService.shared.connect(to: connection, password: password)
            defer { sftp.disconnect() }
            
            // Check root directory for changes
            let rootPath = "/"
            let items = try SharedSFTPService.shared.listDirectory(sftp: sftp, path: rootPath)
            
            let connectionKey = connection.id.uuidString
            var currentState: [String: Any] = [:]
            
            // Create a snapshot of current directory state
            for item in items {
                let filename = item.filename
                if !filename.hasPrefix(".") && filename != "." && filename != ".." {
                    currentState[filename] = [
                        "size": item.size,
                        "mtime": item.mtime.timeIntervalSince1970,
                        "isDirectory": item.isDirectory
                    ]
                }
            }
            
            // Compare with last known state
            if let lastState = lastKnownState[connectionKey] {
                // Check for differences
                let hasChanges = !NSDictionary(dictionary: currentState).isEqual(to: lastState)
                if hasChanges {
                    print("Changes detected in connection: \(connection.name)")
                    lastKnownState[connectionKey] = currentState
                    return [rootPath]
                }
            } else {
                // First time checking this connection
                lastKnownState[connectionKey] = currentState
                return [rootPath] // Signal initial state
            }
            
            return nil
        } catch {
            print("Failed to poll connection \(connection.name): \(error)")
            // Reset connection state on error
            persistenceService.setConnectionState(.error, for: connection.id)
            return nil
        }
    }
    
    // MARK: - Background Task Support
    
    func scheduleBackgroundRefresh() {
        // Reduce polling when in background
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval * 2, repeats: true) { _ in
            self.pollForChanges()
        }
        print("Switched to background polling mode")
    }
    
    func resumeForegroundPolling() {
        // Resume normal polling when returning to foreground
        stopPolling()
        startPolling()
        print("Resumed foreground polling mode")
    }
}
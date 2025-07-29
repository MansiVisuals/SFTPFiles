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
    private let pollingInterval: TimeInterval = 300 // 5 minutes - more reasonable for battery life
    
    private let persistenceService = SharedPersistenceService()
    private let keychainService = SharedKeychainService()
    private var lastKnownState: [String: Date] = [:]
    
    func startPolling() {
        guard pollingTimer == nil else { return }
        
        print("Starting polling service with \(pollingInterval) second interval")
        
        // Initial poll
        pollForChanges()
        
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
            var allChangedPaths: [String] = []
            for connection in connections {
                if let changes = await checkConnectionForChanges(connection) {
                    allChangedPaths.append(contentsOf: changes)
                }
            }
            let changedPathsCopy = allChangedPaths
            if !changedPathsCopy.isEmpty {
                await MainActor.run {
                    delegate?.pollingServiceDidDetectChanges(changedPathsCopy)
                }
            } else {
                print("No changes detected during polling")
            }
        }
    }
    
    private func checkConnectionForChanges(_ connection: SFTPConnection) async -> [String]? {
        // Only poll connected connections or auto-connect connections
        guard connection.autoConnect else { return nil }
        
        guard let password = keychainService.getPassword(for: connection.id) else {
            print("No password available for connection: \(connection.name)")
            return nil
        }
        
        do {
            let sftp = try SharedSFTPService.shared.connect(to: connection, password: password)
            defer { sftp.disconnect() }
            // Check root directory for changes
            let rootPath = "/"
            _ = try SharedSFTPService.shared.listDirectory(sftp: sftp, path: rootPath)
            let connectionKey = connection.id.uuidString
            let currentTime = Date()
            // For now, we'll use a simple approach - if we haven't polled this connection
            // in the last interval, consider it changed
            if lastKnownState[connectionKey] == nil {
                lastKnownState[connectionKey] = currentTime
                return [rootPath] // Signal initial change
            }
            // Check if enough time has passed to consider checking for changes
            if let lastCheck = lastKnownState[connectionKey],
               currentTime.timeIntervalSince(lastCheck) > pollingInterval {
                lastKnownState[connectionKey] = currentTime
                return [rootPath] // Signal potential changes
            }
            return nil
        } catch {
            print("Failed to poll connection \(connection.name): \(error)")
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
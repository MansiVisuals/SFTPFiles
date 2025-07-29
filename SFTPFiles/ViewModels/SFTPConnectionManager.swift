//
//  SFTPConnectionManager.swift
//  SFTPFiles
//
//  Created by Maikel Mansi on 28/07/2025.
//

import Foundation
import Combine
import FileProvider

@MainActor
class SFTPConnectionManager: ObservableObject {
    @Published var connections: [SFTPConnection] = []
    private let persistenceService = PersistenceService()
    private let keychainService = KeychainService()
    
    func loadConnections() {
        print("Loading connections from persistence...")
        connections = persistenceService.loadConnections()
        print("Loaded \(connections.count) connections")
        
        // Sync connection states from shared storage
        let sharedService = SharedPersistenceService.shared
        for i in connections.indices {
            let currentState = sharedService.getConnectionState(for: connections[i].id)
            connections[i].state = currentState
            print("Synced state for \(connections[i].name): \(currentState)")
        }
        
        // Save to both storages to ensure sync
        saveConnections()
        notifyFileProvider()
    }
    
    func addConnection(_ connection: SFTPConnection, password: String?) {
        var newConnection = connection
        newConnection.state = .disconnected
        newConnection.createdDate = Date()
        
        connections.append(newConnection)
        saveConnections()
        
        // Store password securely
        if let password = password, !password.isEmpty {
            keychainService.store(password: password, for: connection.id)
            print("Stored password for connection: \(connection.name)")
        }
        
        // Test connection immediately after adding
        Task {
            await testAndUpdateConnection(newConnection, password: password)
        }
        
        // Notify File Provider extension
        notifyFileProvider()
    }
    
    func deleteConnections(at offsets: IndexSet) {
        for index in offsets {
            let connection = connections[index]
            keychainService.deletePassword(for: connection.id)
            keychainService.deletePrivateKey(for: connection.id)
            print("Deleted connection: \(connection.name)")
        }
        connections.remove(atOffsets: offsets)
        saveConnections()
        notifyFileProvider()
    }
    
    func updateConnection(_ connection: SFTPConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
            saveConnections()
            
            // Update shared storage
            let sharedService = SharedPersistenceService.shared
            sharedService.setConnectionState(connection.state, for: connection.id)
            
            notifyFileProvider()
        }
    }
    
    func testAndUpdateConnection(_ connection: SFTPConnection, password: String?) async {
        print("Testing connection: \(connection.name)")
        
        // Update state to connecting
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index].state = .connecting
            print("Set connection state to connecting for: \(connection.name)")
            
            // Update shared storage immediately
            let sharedService = SharedPersistenceService.shared
            sharedService.setConnectionState(.connecting, for: connection.id)
        }
        
        // Test the connection
        let success = await SFTPService.shared.testConnection(
            connection: connection,
            password: password
        )
        
        print("Connection test result for \(connection.name): \(success ? "SUCCESS" : "FAILED")")
        
        // Update state based on result
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index].state = success ? .connected : .error
            if success {
                connections[index].lastConnected = Date()
                print("Updated last connected time for: \(connection.name)")
            }
            print("Updated connection state to: \(connections[index].state) for: \(connection.name)")
            
            // Update shared storage
            let sharedService = SharedPersistenceService.shared
            sharedService.setConnectionState(connections[index].state, for: connection.id)
            print("Updated shared storage state for: \(connection.name)")
        }
        
        saveConnections()
        notifyFileProvider()
    }
    
    func reconnectAllConnections() async {
        print("Reconnecting all connections...")
        
        for connection in connections {
            let password = keychainService.getPassword(for: connection.id)
            await testAndUpdateConnection(connection, password: password)
        }
    }
    
    private func saveConnections() {
        persistenceService.saveConnections(connections)
        
        // Also save to shared storage
        let sharedService = SharedPersistenceService.shared
        sharedService.saveConnections(connections)
        
        print("Saved \(connections.count) connections to persistence")
    }
    
    private func notifyFileProvider() {
        // Notify the File Provider extension about connection changes
        NotificationCenter.default.post(
            name: Notification.Name("SFTPConnectionsChanged"),
            object: nil
        )
        
        // Signal the Files app to refresh after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.signalFileProviderRefresh()
        }
    }
    
    private func signalFileProviderRefresh() {
        let domainIdentifier = NSFileProviderDomainIdentifier(rawValue: "com.mansi.sftpfiles.provider")
        let domain = NSFileProviderDomain(identifier: domainIdentifier, displayName: "SFTP Files")
        
        guard let manager = NSFileProviderManager(for: domain) else {
            print("Failed to create NSFileProviderManager for domain")
            return
        }
        
        // Signal enumeration refresh for root container
        manager.signalEnumerator(for: .rootContainer) { error in
            if let error = error {
                print("Failed to signal Files app refresh: \(error)")
            } else {
                print("Successfully signaled Files app refresh")
            }
        }
        
        // Signal working set enumeration as well
        manager.signalEnumerator(for: .workingSet) { error in
            if let error = error {
                print("Failed to signal working set refresh: \(error)")
            } else {
                print("Successfully signaled working set refresh")
            }
        }
    }
}
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
    private let sharedService = SharedPersistenceService.shared
    private let sharedKeychainService = SharedKeychainService()
    
    func loadConnections() {
        print("Loading connections from persistence...")
        connections = persistenceService.loadConnections()
        print("Loaded \(connections.count) connections")
        
        // Sync connection states from shared storage
        for i in connections.indices {
            let currentState = sharedService.getConnectionState(for: connections[i].id)
            connections[i].state = currentState
        }
        
        saveConnections()
    }
    
    func addConnection(_ connection: SFTPConnection, password: String?) {
        var newConnection = connection
        newConnection.state = .disconnected
        newConnection.createdDate = Date()
        
        connections.append(newConnection)
        saveConnections()
        
        // Store password securely in both keychain services
        if let password = password, !password.isEmpty {
            keychainService.store(password: password, for: connection.id)
            sharedKeychainService.store(password: password, for: connection.id)
            print("Stored password for connection: \(connection.name)")
        }
        
        // Debug: Verify the connection was saved properly
        print("DEBUG: Added connection \(connection.name) with ID \(connection.id)")
        let savedConnections = sharedService.loadConnections()
        print("DEBUG: SharedService now has \(savedConnections.count) connections")
        for savedConnection in savedConnections {
            print("DEBUG: - \(savedConnection.name) [\(savedConnection.id)]")
        }
        
        // Test connection immediately after adding
        Task {
            await testAndUpdateConnection(newConnection, password: password)
        }
        
        signalFileProviderRefresh()
    }
    
    func deleteConnections(at offsets: IndexSet) {
        for index in offsets {
            let connection = connections[index]
            keychainService.deletePassword(for: connection.id)
            keychainService.deletePrivateKey(for: connection.id)
            sharedKeychainService.deletePassword(for: connection.id)
            print("Deleted connection: \(connection.name)")
        }
        connections.remove(atOffsets: offsets)
        saveConnections()
        signalFileProviderRefresh()
    }
    
    func updateConnection(_ connection: SFTPConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
            saveConnections()
            sharedService.setConnectionState(connection.state, for: connection.id)
            signalFileProviderRefresh()
        }
    }
    
    func testAndUpdateConnection(_ connection: SFTPConnection, password: String?) async {
        print("Testing connection: \(connection.name)")
        
        // Update state to connecting
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index].state = .connecting
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
            }
            
            sharedService.setConnectionState(connections[index].state, for: connection.id)
        }
        
        saveConnections()
        signalFileProviderRefresh()
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
        sharedService.saveConnections(connections)
        print("Saved \(connections.count) connections to persistence")
    }
    
    private func signalFileProviderRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let domainIdentifier = NSFileProviderDomainIdentifier(rawValue: "group.com.mansi.sftpfiles")
            let domain = NSFileProviderDomain(identifier: domainIdentifier, displayName: "SFTP Files")
            
            guard let manager = NSFileProviderManager(for: domain) else {
                print("Failed to create NSFileProviderManager for refresh")
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
            
            // Also signal working set
            manager.signalEnumerator(for: .workingSet) { error in
                if let error = error {
                    print("Failed to signal working set refresh: \(error)")
                } else {
                    print("Successfully signaled working set refresh")
                }
            }
        }
    }
}
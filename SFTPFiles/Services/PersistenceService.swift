//
//  PersistenceService.swift
//  SFTPFiles
//
//  Created by Maikel Mansi on 28/07/2025.
//

import Foundation

class PersistenceService {
    private let userDefaults: UserDefaults?
    private let connectionsKey = "SavedSFTPConnections"
    
    init() {
        if let sharedDefaults = UserDefaults(suiteName: "group.com.mansi.sftpfiles") {
            self.userDefaults = sharedDefaults
            print("[PersistenceService] Using shared UserDefaults")
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.mansi.sftpfiles") {
                print("[DEBUG] Shared UserDefaults path: \(url.path)")
            } else {
                print("[DEBUG] Shared UserDefaults path: nil")
            }
        } else {
            print("[PersistenceService] Using standard UserDefaults")
            self.userDefaults = UserDefaults.standard
        }
    }
    
    func saveConnections(_ connections: [SFTPConnection]) {
        do {
            let data = try JSONEncoder().encode(connections)
            userDefaults?.set(data, forKey: connectionsKey)
            userDefaults?.synchronize()
            print("Successfully saved \(connections.count) connections")
        } catch {
            print("Failed to save connections: \(error)")
        }
    }
    
    func loadConnections() -> [SFTPConnection] {
        guard let data = userDefaults?.data(forKey: connectionsKey) else {
            print("No saved connections found")
            return []
        }
        
        do {
            let connections = try JSONDecoder().decode([SFTPConnection].self, from: data)
            print("Successfully loaded \(connections.count) connections")
            return connections
        } catch {
            print("Failed to load connections: \(error)")
            userDefaults?.removeObject(forKey: connectionsKey)
            return []
        }
    }
    
    func deleteAllConnections() {
        userDefaults?.removeObject(forKey: connectionsKey)
        userDefaults?.synchronize()
        print("Deleted all saved connections")
    }
    
    func updateConnection(_ connection: SFTPConnection) {
        var connections = loadConnections()
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
            saveConnections(connections)
        }
    }
    
    func deleteConnection(withId id: UUID) {
        var connections = loadConnections()
        connections.removeAll { $0.id == id }
        saveConnections(connections)
    }
    
    func getConnection(withId id: UUID) -> SFTPConnection? {
        return loadConnections().first { $0.id == id }
    }
}
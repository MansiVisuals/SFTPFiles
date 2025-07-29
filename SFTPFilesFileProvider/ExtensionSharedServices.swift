//
//  ExtensionSharedServices.swift
//  SFTPFilesFileProvider (File Provider Extension Only)
//
//  Created by Maikel Mansi on 28/07/2025.
//
//  This file provides simple instances of shared services for the File Provider extension
//  when the singleton pattern is not available.

import Foundation
import Security

// MARK: - Extension Persistence Service

class ExtensionPersistenceService {
    private let userDefaults: UserDefaults?
    private let connectionsKey = "SavedSFTPConnections"
    private let connectionStatePrefix = "SFTPConnectionState_"

    init() {
        // Try to access shared storage
        if let sharedDefaults = UserDefaults(suiteName: "group.com.mansi.sftpfiles") {
            self.userDefaults = sharedDefaults
            print("[ExtensionPersistenceService] Successfully created shared UserDefaults")
        } else {
            print("[ExtensionPersistenceService] Failed to create shared UserDefaults, falling back to standard")
            self.userDefaults = UserDefaults.standard
        }
    }

    func loadConnections() -> [SFTPConnection] {
        guard let userDefaults = userDefaults else {
            print("[ExtensionPersistenceService] No UserDefaults available")
            return []
        }
        
        guard let data = userDefaults.data(forKey: connectionsKey) else {
            print("[ExtensionPersistenceService] No saved connections found")
            return []
        }

        do {
            let connections = try JSONDecoder().decode([SFTPConnection].self, from: data)
            print("[ExtensionPersistenceService] Loaded \(connections.count) connections")
            return connections
        } catch {
            print("[ExtensionPersistenceService] Failed to load connections: \(error)")
            return []
        }
    }

    func getConnection(withId id: UUID) -> SFTPConnection? {
        let connection = loadConnections().first { $0.id == id }
        if let connection = connection {
            print("[ExtensionPersistenceService] Found connection: \(connection.name)")
        } else {
            print("[ExtensionPersistenceService] No connection found for ID: \(id)")
        }
        return connection
    }

    func setConnectionState(_ state: ConnectionState, for id: UUID) {
        guard let userDefaults = userDefaults else {
            print("[ExtensionPersistenceService] No UserDefaults available for setting state")
            return
        }
        
        let key = connectionStatePrefix + id.uuidString
        userDefaults.set(state.rawValue, forKey: key)
        userDefaults.synchronize()
        print("[ExtensionPersistenceService] Set connection state for \(id): \(state.rawValue)")
    }

    func getConnectionState(for id: UUID) -> ConnectionState {
        guard let userDefaults = userDefaults else {
            print("[ExtensionPersistenceService] No UserDefaults available for getting state")
            return .disconnected
        }
        
        let key = connectionStatePrefix + id.uuidString
        guard let value = userDefaults.string(forKey: key), let state = ConnectionState(rawValue: value) else {
            return .disconnected
        }
        return state
    }
}

// MARK: - Extension Keychain Service

class ExtensionKeychainService {
    private let service = "com.mansi.sftpfiles"
    
    // Use app identifier as keychain access group
    private var accessGroup: String {
        if let teamIdentifier = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
           let bundleIdentifier = Bundle.main.bundleIdentifier {
            return "\(teamIdentifier)\(bundleIdentifier.components(separatedBy: ".").prefix(3).joined(separator: "."))"
        }
        return "com.mansi.sftpfiles"
    }
    
    func getPassword(for connectionId: UUID) -> String? {
        let account = connectionId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                let errorMessage = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
                print("[ExtensionKeychainService] Failed to retrieve password: \(status) - \(errorMessage)")
            }
            return nil
        }
        
        return password
    }
}

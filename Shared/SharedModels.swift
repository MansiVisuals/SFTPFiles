//
//  SharedModels.swift
//  SFTPFiles & SFTPFilesFileProvider
//  ADD THIS FILE TO BOTH TARGETS
//
//  Created by Maikel Mansi on 28/07/2025.
//

import mft

// MARK: - Shared Models

enum ConnectionState: String, Codable, CaseIterable {
    case connected
    case connecting
    case disconnected
    case error

    var displayName: String {
        switch self {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .disconnected: return "Disconnected"
        case .error: return "Error"
        }
    }
}

struct SFTPConnection: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var hostname: String
    var port: Int
    var username: String
    var useKeyAuth: Bool
    var privateKeyPath: String?
    var autoConnect: Bool
    var remotePath: String?
    var createdDate: Date
    var lastConnected: Date?
    var state: ConnectionState

    init(
        id: UUID = UUID(),
        name: String,
        hostname: String,
        port: Int = 22,
        username: String,
        useKeyAuth: Bool = false,
        privateKeyPath: String? = nil,
        autoConnect: Bool = true,
        remotePath: String? = nil,
        createdDate: Date = Date(),
        lastConnected: Date? = nil,
        state: ConnectionState = .disconnected
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.useKeyAuth = useKeyAuth
        self.privateKeyPath = privateKeyPath
        self.autoConnect = autoConnect
        self.remotePath = remotePath
        self.createdDate = createdDate
        self.lastConnected = lastConnected
        self.state = state
    }
}

// MARK: - Shared Services

class SharedPersistenceService {
    static let shared = SharedPersistenceService()
    
    private let userDefaults: UserDefaults?
    private let connectionsKey = "SavedSFTPConnections"
    private let connectionStatePrefix = "SFTPConnectionState_"

    private init() {
        // Try shared storage first, fall back to standard if it fails
        if let sharedDefaults = UserDefaults(suiteName: "group.com.mansi.sftpfiles") {
            self.userDefaults = sharedDefaults
            print("[SharedPersistenceService] Using shared UserDefaults")
        } else {
            print("[SharedPersistenceService] Shared UserDefaults failed, using standard")
            self.userDefaults = UserDefaults.standard
        }
    }

    func loadConnections() -> [SFTPConnection] {
        guard let userDefaults = userDefaults else {
            return []
        }
        
        guard let data = userDefaults.data(forKey: connectionsKey) else {
            return []
        }

        do {
            let connections = try JSONDecoder().decode([SFTPConnection].self, from: data)
            return connections
        } catch {
            print("[SharedPersistenceService] Failed to decode connections: \(error)")
            return []
        }
    }

    func saveConnections(_ connections: [SFTPConnection]) {
        guard let userDefaults = userDefaults else { return }
        
        do {
            let data = try JSONEncoder().encode(connections)
            userDefaults.set(data, forKey: connectionsKey)
            userDefaults.synchronize()
        } catch {
            print("[SharedPersistenceService] Failed to encode connections: \(error)")
        }
    }

    func getConnection(withId id: UUID) -> SFTPConnection? {
        return loadConnections().first { $0.id == id }
    }

    func setConnectionState(_ state: ConnectionState, for id: UUID) {
        guard let userDefaults = userDefaults else { return }
        
        let key = connectionStatePrefix + id.uuidString
        userDefaults.set(state.rawValue, forKey: key)
        userDefaults.synchronize()
        
        // Update connection in saved array
        var connections = loadConnections()
        if let index = connections.firstIndex(where: { $0.id == id }) {
            connections[index].state = state
            if state == .connected {
                connections[index].lastConnected = Date()
            }
            saveConnections(connections)
        }
    }

    func getConnectionState(for id: UUID) -> ConnectionState {
        guard let userDefaults = userDefaults else { return .disconnected }
        
        let key = connectionStatePrefix + id.uuidString
        guard let value = userDefaults.string(forKey: key), 
              let state = ConnectionState(rawValue: value) else {
            return .disconnected
        }
        return state
    }
}

class SharedKeychainService {
    private let service = "com.mansi.sftpfiles"
    
    private var accessGroup: String {
        return "group.com.mansi.sftpfiles"
    }
    
    func getPassword(for connectionId: UUID) -> String? {
        let account = connectionId.uuidString
        
        // Try multiple query configurations for maximum compatibility
        let queries: [[String: Any]] = [
            // Standard query with access group
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecAttrAccessGroup as String: accessGroup
            ],
            // Fallback without access group
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
        ]
        
        for query in queries {
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            
            if status == errSecSuccess,
               let data = result as? Data,
               let password = String(data: data, encoding: .utf8) {
                return password
            }
        }
        
        return nil
    }
    
    func store(password: String, for connectionId: UUID) {
        let data = password.data(using: .utf8)!
        let account = connectionId.uuidString
        
        // Delete existing items first
        let deleteQueries: [[String: Any]] = [
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrAccessGroup as String: accessGroup
            ],
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
        ]
        
        for deleteQuery in deleteQueries {
            SecItemDelete(deleteQuery as CFDictionary)
        }
        
        // Try to add with access group first
        let addQueries: [[String: Any]] = [
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessGroup as String: accessGroup
            ],
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data
            ]
        ]
        
        for addQuery in addQueries {
            let status = SecItemAdd(addQuery as CFDictionary, nil)
            if status == errSecSuccess {
                break
            }
        }
    }
    
    func deletePassword(for connectionId: UUID) {
        let account = connectionId.uuidString
        
        let queries: [[String: Any]] = [
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrAccessGroup as String: accessGroup
            ],
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
        ]
        
        for query in queries {
            SecItemDelete(query as CFDictionary)
        }
    }
}

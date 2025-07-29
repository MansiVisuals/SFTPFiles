//
//  SharedModels.swift
//  SFTPFiles & SFTPFilesFileProvider
//  ADD THIS FILE TO BOTH TARGETS
//
//  Created by Maikel Mansi on 28/07/2025.
//

import Foundation
import FileProvider
import UniformTypeIdentifiers

// MARK: - Connection Models

struct SFTPConnection: Identifiable, Codable, Hashable, Equatable {
    var id = UUID()
    var name: String
    var hostname: String
    var port: Int
    var username: String
    var useKeyAuth: Bool
    var privateKeyPath: String?
    var remotePath: String? // Optional remote path for this connection
    var state: ConnectionState = .disconnected
    var lastConnected: Date?
    var autoConnect: Bool = true
    var createdDate: Date = Date()
    
    enum CodingKeys: String, CodingKey {
        case id, name, hostname, port, username, useKeyAuth, privateKeyPath, remotePath, autoConnect, lastConnected, createdDate
    }
    
    init(name: String, hostname: String, port: Int, username: String, useKeyAuth: Bool, privateKeyPath: String?, remotePath: String? = nil) {
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.useKeyAuth = useKeyAuth
        self.privateKeyPath = privateKeyPath
        self.remotePath = remotePath
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        hostname = try container.decode(String.self, forKey: .hostname)
        port = try container.decode(Int.self, forKey: .port)
        username = try container.decode(String.self, forKey: .username)
        useKeyAuth = try container.decode(Bool.self, forKey: .useKeyAuth)
        privateKeyPath = try container.decodeIfPresent(String.self, forKey: .privateKeyPath)
        remotePath = try container.decodeIfPresent(String.self, forKey: .remotePath)
        autoConnect = try container.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? true
        lastConnected = try container.decodeIfPresent(Date.self, forKey: .lastConnected)
        createdDate = try container.decodeIfPresent(Date.self, forKey: .createdDate) ?? Date()
        if let uuidString = try container.decodeIfPresent(String.self, forKey: .id),
           let uuid = UUID(uuidString: uuidString) {
            id = uuid
        } else {
            id = UUID()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(hostname, forKey: .hostname)
        try container.encode(port, forKey: .port)
        try container.encode(username, forKey: .username)
        try container.encode(useKeyAuth, forKey: .useKeyAuth)
        try container.encodeIfPresent(privateKeyPath, forKey: .privateKeyPath)
        try container.encodeIfPresent(remotePath, forKey: .remotePath)
        try container.encode(autoConnect, forKey: .autoConnect)
        try container.encodeIfPresent(lastConnected, forKey: .lastConnected)
        try container.encode(createdDate, forKey: .createdDate)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: SFTPConnection, rhs: SFTPConnection) -> Bool {
        return lhs.id == rhs.id
    }
}

enum ConnectionState: String, Codable, CaseIterable {
    case disconnected
    case connecting
    case connected
    case error
    
    var displayName: String {
        switch self {
        case .disconnected: return "Not Connected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error: return "Connection Error"
        }
    }
}

// MARK: - File Provider Item

class FileProviderItem: NSObject, NSFileProviderItem {
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let filename: String
    let typeIdentifier: String
    let capabilities: NSFileProviderItemCapabilities
    let remotePath: String
    let connectionId: UUID
    let isDirectory: Bool
    
    private let _documentSize: NSNumber?
    private let _contentModificationDate: Date?
    private let _creationDate: Date?
    private let _isSymlink: Bool
    
    init(
        identifier: NSFileProviderItemIdentifier,
        filename: String,
        typeIdentifier: String,
        isDirectory: Bool,
        remotePath: String,
        connectionId: UUID,
        fileSize: Int64? = nil,
        modificationDate: Date? = nil,
        creationDate: Date? = nil,
        isSymlink: Bool = false,
        parentIdentifier: NSFileProviderItemIdentifier = .rootContainer
    ) {
        self.itemIdentifier = identifier
        self.parentItemIdentifier = parentIdentifier
        self.filename = filename
        self.typeIdentifier = typeIdentifier
        self.isDirectory = isDirectory
        self.remotePath = remotePath
        self.connectionId = connectionId
        self._isSymlink = isSymlink
        
        // Set appropriate capabilities based on item type
        if isDirectory {
            self.capabilities = [.allowsReading, .allowsContentEnumerating]
        } else {
            self.capabilities = [.allowsReading]
        }
        
        self._documentSize = fileSize != nil ? NSNumber(value: fileSize!) : nil
        self._contentModificationDate = modificationDate ?? Date()
        self._creationDate = creationDate ?? modificationDate ?? Date()
        
        super.init()
    }
    
    // MARK: - NSFileProviderItem Protocol
    
    var documentSize: NSNumber? {
        return isDirectory ? nil : (_documentSize ?? NSNumber(value: 0))
    }
    
    var contentModificationDate: Date? {
        return _contentModificationDate
    }
    
    var creationDate: Date? {
        return _creationDate
    }
    
    var childItemCount: NSNumber? {
        return isDirectory ? NSNumber(value: 0) : nil
    }
    
    var downloadingError: Error? { return nil }
    var uploadingError: Error? { return nil }
    var isDownloaded: Bool { return !isDirectory }
    var isDownloading: Bool { return false }
    var isUploaded: Bool { return true }
    var isUploading: Bool { return false }
    var isMostRecentVersionDownloaded: Bool { return isDownloaded }
    var isShared: Bool { return false }
    var isSharedByCurrentUser: Bool { return false }
    var ownerNameComponents: PersonNameComponents? { return nil }
    var mostRecentEditorNameComponents: PersonNameComponents? { return nil }
    
    var versionIdentifier: Data? {
        let timestamp = _contentModificationDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        return String(timestamp).data(using: .utf8)
    }
    
    var userInfo: [AnyHashable: Any]? {
        return [
            "remotePath": remotePath,
            "connectionId": connectionId.uuidString,
            "isDirectory": isDirectory,
            "isSymlink": _isSymlink
        ]
    }
    
    var tagData: Data? { return nil }
    var favoriteRank: NSNumber? { return nil }
    var isTrashed: Bool { return false }
    var symlinkTargetPath: String? { 
        return _isSymlink ? remotePath : nil 
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
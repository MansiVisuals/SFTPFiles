//
//  SharedModels.swift
//  SFTPFiles & SFTPFilesFileProvider
//  ⚠️ ADD THIS FILE TO BOTH TARGETS ⚠️
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
    var state: ConnectionState = .disconnected
    var lastConnected: Date?
    var autoConnect: Bool = true
    var createdDate: Date = Date()
    
    enum CodingKeys: String, CodingKey {
        case id, name, hostname, port, username, useKeyAuth, privateKeyPath, autoConnect, lastConnected, createdDate
    }
    
    init(name: String, hostname: String, port: Int, username: String, useKeyAuth: Bool, privateKeyPath: String?) {
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.useKeyAuth = useKeyAuth
        self.privateKeyPath = privateKeyPath
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decode(String.self, forKey: .name)
        hostname = try container.decode(String.self, forKey: .hostname)
        port = try container.decode(Int.self, forKey: .port)
        username = try container.decode(String.self, forKey: .username)
        useKeyAuth = try container.decode(Bool.self, forKey: .useKeyAuth)
        
        privateKeyPath = try container.decodeIfPresent(String.self, forKey: .privateKeyPath)
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
        try container.encode(autoConnect, forKey: .autoConnect)
        try container.encodeIfPresent(lastConnected, forKey: .lastConnected)
        try container.encode(createdDate, forKey: .createdDate)
    }
    
    // MARK: - Protocol Conformance
    
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
        parentIdentifier: NSFileProviderItemIdentifier = .rootContainer
    ) {
        self.itemIdentifier = identifier
        self.parentItemIdentifier = parentIdentifier
        self.filename = filename
        self.typeIdentifier = typeIdentifier
        self.isDirectory = isDirectory
        self.remotePath = remotePath
        self.connectionId = connectionId
        
        if isDirectory {
            self.capabilities = [.allowsReading, .allowsContentEnumerating]
        } else {
            self.capabilities = [.allowsReading]
        }
        
        self._documentSize = fileSize != nil ? NSNumber(value: fileSize!) : nil
        self._contentModificationDate = modificationDate
        self._creationDate = creationDate ?? modificationDate ?? Date()
        
        super.init()
    }
    
    // MARK: - NSFileProviderItem
    
    var documentSize: NSNumber? {
        return isDirectory ? nil : _documentSize
    }
    
    var contentModificationDate: Date? {
        return _contentModificationDate
    }
    
    var creationDate: Date? {
        return _creationDate
    }
    
    var childItemCount: NSNumber? {
        return isDirectory ? nil : NSNumber(value: 0)
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
        guard let modDate = _contentModificationDate else { 
            return String(Date().timeIntervalSince1970).data(using: .utf8)
        }
        return String(modDate.timeIntervalSince1970).data(using: .utf8)
    }
    
    var userInfo: [AnyHashable: Any]? {
        return [
            "remotePath": remotePath,
            "connectionId": connectionId.uuidString,
            "isDirectory": isDirectory
        ]
    }
    
    var tagData: Data? { return nil }
    var favoriteRank: NSNumber? { return nil }
    var isTrashed: Bool { return false }
    var symlinkTargetPath: String? { return nil }
}

// MARK: - Shared Services

class SharedPersistenceService {
    private let userDefaults: UserDefaults?
    private let connectionsKey = "SavedSFTPConnections"
    
    init() {
        self.userDefaults = UserDefaults(suiteName: "group.mansi.SFTPFiles")
        if userDefaults == nil {
            print("Warning: Could not access shared UserDefaults for group.mansi.SFTPFiles")
        }
    }
    
    func loadConnections() -> [SFTPConnection] {
        guard let data = userDefaults?.data(forKey: connectionsKey) else {
            print("No saved connections found in shared storage")
            return []
        }
        
        do {
            let connections = try JSONDecoder().decode([SFTPConnection].self, from: data)
            print("Loaded \(connections.count) connections from shared storage")
            return connections
        } catch {
            print("Failed to load connections from shared storage: \(error)")
            return []
        }
    }
    
    func saveConnections(_ connections: [SFTPConnection]) {
        do {
            let data = try JSONEncoder().encode(connections)
            userDefaults?.set(data, forKey: connectionsKey)
            userDefaults?.synchronize()
            print("Saved \(connections.count) connections to shared storage")
        } catch {
            print("Failed to save connections to shared storage: \(error)")
        }
    }
    
    func getConnection(withId id: UUID) -> SFTPConnection? {
        return loadConnections().first { $0.id == id }
    }
}

class SharedKeychainService {
    private let service = "com.mansi.sftpfiles"
    
    // Use dynamic team identifier instead of hardcoded access group
    private var accessGroup: String {
        guard let teamIdentifier = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String else {
            // Fallback for development
            return "group.mansi.SFTPFiles"
        }
        return "\(teamIdentifier)group.mansi.SFTPFiles"
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
                print("Failed to retrieve password from keychain: \(status) - \(errorMessage)")
            }
            return nil
        }
        
        return password
    }
    
    func store(password: String, for connectionId: UUID) {
        let data = password.data(using: .utf8)!
        let account = connectionId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("Successfully stored password for connection: \(account)")
        } else {
            let errorMessage = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            print("Failed to store password in keychain: \(status) - \(errorMessage)")
        }
    }
    
    func deletePassword(for connectionId: UUID) {
        let account = connectionId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess {
            print("Successfully deleted password for connection: \(account)")
        } else if status != errSecItemNotFound {
            let errorMessage = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            print("Failed to delete password from keychain: \(status) - \(errorMessage)")
        }
    }
}
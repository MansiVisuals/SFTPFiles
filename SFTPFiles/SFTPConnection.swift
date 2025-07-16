import Foundation

// MARK: - Enhanced Authentication Methods
enum SFTPAuthMethod: String, Codable, CaseIterable {
    case password = "password"
    case publicKey = "publicKey"
    case passwordAndKey = "passwordAndKey"
    
    var displayName: String {
        switch self {
        case .password: return "Password"
        case .publicKey: return "SSH Key"
        case .passwordAndKey: return "Password + SSH Key"
        }
    }
}

// MARK: - SSH Key Pair Model
struct SSHKeyPair: Identifiable, Codable {
    let id: UUID
    let name: String
    let publicKey: String
    let privateKey: String // Will be stored in keychain
    let passphrase: String? // Will be stored in keychain
    let createdAt: Date
    
    init(id: UUID = UUID(), name: String, publicKey: String, privateKey: String, passphrase: String? = nil) {
        self.id = id
        self.name = name
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.passphrase = passphrase
        self.createdAt = Date()
    }
}

// MARK: - NATS Configuration
struct NATSConfig: Codable, Equatable {
    let servers: [String]
    let subject: String
    let credentials: String?
    let tlsEnabled: Bool
    
    init(servers: [String], subject: String, credentials: String? = nil, tlsEnabled: Bool = true) {
        self.servers = servers
        self.subject = subject
        self.credentials = credentials
        self.tlsEnabled = tlsEnabled
    }
}

// MARK: - Enhanced SFTPConnection
struct SFTPConnection: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var host: String
    var port: Int?
    var username: String
    var authMethod: SFTPAuthMethod
    var password: String
    var keyPairId: UUID?
    var remotePath: String
    var status: ConnectionStatus
    var lastChecked: Date?
    var isNATSEnabled: Bool
    var natsConfig: NATSConfig?
    
    init(id: UUID = UUID(), name: String, host: String, port: Int? = nil, username: String, 
         authMethod: SFTPAuthMethod = .password, password: String = "", keyPairId: UUID? = nil,
         remotePath: String = "/", isNATSEnabled: Bool = false, natsConfig: NATSConfig? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.password = password
        self.keyPairId = keyPairId
        self.remotePath = remotePath
        self.status = .unknown
        self.isNATSEnabled = isNATSEnabled
        self.natsConfig = natsConfig
    }
}

// MARK: - Enhanced Connection Status
enum ConnectionStatus: String, Codable, CaseIterable, Equatable {
    case unknown = "unknown"
    case connecting = "connecting"
    case connected = "connected"
    case disconnected = "disconnected"
    case error = "error"
    case authFailed = "authFailed"
    case syncError = "syncError"
    
    // Legacy support for existing code
    case checking = "checking"
    case valid = "valid"
    case invalid = "invalid"
    case timeout = "timeout"
    
    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .connecting, .checking: return "Connecting..."
        case .connected, .valid: return "Connected"
        case .disconnected, .invalid: return "Disconnected"
        case .error: return "Connection Error"
        case .authFailed: return "Authentication Failed"
        case .syncError: return "Sync Error"
        case .timeout: return "Connection Timeout"
        }
    }
    
    var isHealthy: Bool {
        return self == .connected || self == .valid
    }
}

// MARK: - Enhanced Connection Store
class SFTPConnectionStore {
    private static let storageKey = "SFTPConnections"
    private static let appGroupID = "group.mansivisuals.SFTPFiles"
    
    static func loadConnections() -> [SFTPConnection] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: storageKey),
              let connections = try? JSONDecoder().decode([SFTPConnection].self, from: data) else {
            return []
        }
        return connections
    }
    
    static func saveConnections(_ connections: [SFTPConnection]) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(connections) else { return }
        defaults.set(data, forKey: storageKey)
        defaults.synchronize()
    }
}
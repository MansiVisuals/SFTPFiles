import Foundation

struct SFTPConnection: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var host: String
    var port: Int?
    var username: String
    var password: String
    var remotePath: String
    var status: ConnectionStatus = .unknown
    var lastChecked: Date?
    var isPollingEnabled: Bool = true
    
    init(id: UUID = UUID(), name: String, host: String, port: Int? = nil, username: String, password: String, remotePath: String = "/") {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.remotePath = remotePath
    }
}

enum ConnectionStatus: String, Codable, CaseIterable {
    case unknown = "Not checked"
    case checking = "Checking..."
    case connected = "Connected"
    case disconnected = "Disconnected"
    case error = "Connection Error"
    case timeout = "Connection Timeout"
    
    // Legacy support
    case valid = "Valid"
    case invalid = "Invalid"
    
    var displayName: String {
        switch self {
        case .unknown: return "Not Checked"
        case .checking: return "Checking..."
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .error: return "Connection Error"
        case .timeout: return "Connection Timeout"
        case .valid: return "Connected"
        case .invalid: return "Connection Error"
        }
    }
    
    var isHealthy: Bool {
        return self == .connected || self == .valid
    }
}

// Simple connection storage
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
              let data = try? JSONEncoder().encode(connections) else {
            return
        }
        defaults.set(data, forKey: storageKey)
        defaults.synchronize()
    }
}
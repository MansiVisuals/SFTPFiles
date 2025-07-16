//
//  NATSSyncManager.swift
//  SFTPFiles
//
//  Created by Maikel Mansi on 16/07/2025.
//

import Foundation
import FileProvider
import Nats

// MARK: - File Event Models
struct FileEvent: Codable {
    let id: String
    let type: FileEventType
    let path: String
    let oldPath: String?
    let timestamp: Date
    let size: Int64?
    let checksum: String?
    let metadata: [String: String]
    
    init(type: FileEventType, path: String, oldPath: String? = nil, size: Int64? = nil, checksum: String? = nil, metadata: [String: String] = [:]) {
        self.id = UUID().uuidString
        self.type = type
        self.path = path
        self.oldPath = oldPath
        self.timestamp = Date()
        self.size = size
        self.checksum = checksum
        self.metadata = metadata
    }
}

enum FileEventType: String, Codable {
    case created
    case modified
    case deleted
    case moved
}

// MARK: - NATS Sync Manager
class NATSSyncManager: ObservableObject {
    @Published var connectionStatus: NATSConnectionStatus = .disconnected
    @Published var lastSyncEvent: Date?
    @Published var syncErrors: [String] = []
    
    private var natsClient: NatsClient?
    private var subscriptions: [NatsSubscription] = []
    private weak var fileProviderManager: FileProviderSyncManager?
    
    init(fileProviderManager: FileProviderSyncManager) {
        self.fileProviderManager = fileProviderManager
    }
    
    func connect(to config: NATSConfig) async {
        connectionStatus = .connecting
        NSLog("NATS: Attempting to connect to servers: \(config.servers)")
        do {
            guard let url = config.servers.first, let natsUrl = URL(string: url) else {
                self.connectionStatus = .error
                NSLog("NATS: Invalid server URL (config.servers: \(config.servers))")
                return
            }
            NSLog("NATS: Using URL: \(natsUrl)")
            let nats = NatsClientOptions().url(natsUrl).build()
            try await nats.connect()
            self.natsClient = nats
            self.connectionStatus = .connected
            NSLog("NATS: Connected to \(config.servers)")
        } catch {
            self.connectionStatus = .error
            NSLog("NATS: Failed to connect: \(error)")
        }
    }
    
    func disconnect() async {
        do {
            try await natsClient?.close()
        } catch {
            NSLog("NATS: Error closing connection: \(error)")
        }
        natsClient = nil
        subscriptions.removeAll()
        connectionStatus = .disconnected
        NSLog("NATS: Disconnected")
    }
    
    func publishFileEvent(_ event: FileEvent, to subject: String) async {
        guard let nats = natsClient else {
            NSLog("NATS: No connection available to publish event")
            return
        }
        do {
            let data = try JSONEncoder().encode(event)
            try await nats.publish(data, subject: subject)
            NSLog("NATS: Published event - Type: \(event.type), Path: \(event.path)")
        } catch {
            NSLog("NATS: Failed to publish event: \(error)")
        }
    }

    // List all active subscriptions (for debugging or UI)
    func listSubscriptions() -> [NatsSubscription] {
        return subscriptions
    }

    // Subscribe to a subject and handle remote file events for real-time sync
    func subscribe(to subject: String) async {
        guard let nats = natsClient else {
            NSLog("NATS: subscribe() called but natsClient is nil")
            return
        }
        NSLog("NATS: Attempting to subscribe to subject: \(subject)")
        do {
            let sub = try await nats.subscribe(subject: subject, queue: nil)
            Task { [weak self] in
                for try await msg in sub {
                    NSLog("NATS: Received message on subject \(subject): \(msg)")
                    if let payload = msg.payload,
                       let event = try? JSONDecoder().decode(FileEvent.self, from: payload),
                       let self = self {
                        await self.fileProviderManager?.handleFileEvent(event)
                    } else {
                        NSLog("NATS: Failed to decode FileEvent from message data")
                    }
                }
            }
            subscriptions.append(sub)
            NSLog("NATS: Subscribed to \(subject)")
        } catch {
            NSLog("NATS: Failed to subscribe to \(subject): \(error)")
        }
    }

    // Unsubscribe from all subjects
    func unsubscribeAll() async {
        for sub in subscriptions {
            do {
                try await sub.unsubscribe()
            } catch {
                NSLog("NATS: Failed to unsubscribe: \(error)")
            }
        }
        subscriptions.removeAll()
        NSLog("NATS: Unsubscribed from all subjects")
    }
}

// MARK: - File Provider Sync Manager
class FileProviderSyncManager: ObservableObject {
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var syncProgress: Double = 0.0
    
    private var connections: [SFTPConnection] = []
    private var natsManager: NATSSyncManager?
    
    init() {
        loadConnections()
    }
    
    func loadConnections() {
        connections = SFTPConnectionStore.loadConnections()
    }
    
    func handleFileEvent(_ event: FileEvent) async {
        NSLog("FileProvider: Handling file event - Type: \(event.type), Path: \(event.path)")
        // Always signal the .workingSet enumerator for real-time sync (Apple best practice)
        let domains = await getFileProviderDomains()
        for domain in domains {
            if shouldHandleEvent(event, for: domain) {
                await signalFileProviderWorkingSet(domain: domain)
            }
        }
    }

    private func shouldHandleEvent(_ event: FileEvent, for domain: NSFileProviderDomain) -> Bool {
        guard let connection = connections.first(where: { $0.id.uuidString == domain.identifier.rawValue }) else {
            return false
        }
        let remotePath = connection.remotePath.isEmpty ? "/" : connection.remotePath
        return event.path.hasPrefix(remotePath)
    }

    // Always signal .workingSet for remote changes
    private func signalFileProviderWorkingSet(domain: NSFileProviderDomain) async {
        if let manager = NSFileProviderManager(for: domain) {
            do {
                try await manager.signalEnumerator(for: .workingSet)
                NSLog("FileProvider: Successfully signaled .workingSet enumerator for domain \(domain.displayName)")
            } catch {
                NSLog("FileProvider: Failed to signal .workingSet enumerator: \(error)")
            }
        }
    }
    
    private func getFileProviderDomains() async -> [NSFileProviderDomain] {
        return await withCheckedContinuation { continuation in
            NSFileProviderManager.getDomainsWithCompletionHandler { domains, _ in
                continuation.resume(returning: domains)
            }
        }
    }
    
    func triggerManualSync(for connection: SFTPConnection) async {
        syncStatus = .syncing
        lastSyncDate = Date()
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: connection.id.uuidString),
            displayName: connection.name
        )
        let manager = NSFileProviderManager(for: domain)
        if let manager = manager {
            do {
                try await manager.signalEnumerator(for: .rootContainer)
                DispatchQueue.main.async { [weak self] in
                    self?.syncStatus = .idle
                    NSLog("FileProvider: Manual sync completed")
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.syncStatus = .error
                    NSLog("FileProvider: Manual sync failed: \(error)")
                }
            }
        }
    }
    
    func publishLocalChange(_ event: FileEvent, for connection: SFTPConnection) async {
        guard connection.isNATSEnabled,
              let natsConfig = connection.natsConfig else { return }
        
        await natsManager?.publishFileEvent(event, to: natsConfig.subject)
    }
}

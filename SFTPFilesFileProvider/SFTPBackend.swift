//
//  SFTPBackend.swift
//  SFTPFilesFileProvider
//
//  Created by Maikel Mansi on 28/07/2025.
//

import Foundation
import FileProvider
import mft

// MARK: - SFTP Service for File Provider

class SharedSFTPService {
    static let shared = SharedSFTPService()
    private init() {}
    
    func connect(to connection: SFTPConnection, password: String) throws -> MFTSftpConnection {
        print("Attempting to connect to \(connection.hostname):\(connection.port)")
        let sftp = MFTSftpConnection(
            hostname: connection.hostname,
            port: Int(connection.port),
            username: connection.username,
            password: password
        )
        try sftp.connect()
        try sftp.authenticate()
        print("Successfully connected to \(connection.hostname)")
        return sftp
    }
    
    func testConnection(connection: SFTPConnection, password: String?) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let sftp = MFTSftpConnection(
                        hostname: connection.hostname,
                        port: Int(connection.port),
                        username: connection.username,
                        password: password ?? ""
                    )
                    
                    try sftp.connect()
                    try sftp.authenticate()
                    
                    // Test basic directory listing
                    let _ = try sftp.contentsOfDirectory(atPath: "/", maxItems: 1)
                    
                    sftp.disconnect()
                    continuation.resume(returning: true)
                } catch {
                    print("SFTP test connection error: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    func listDirectory(sftp: MFTSftpConnection, path: String) throws -> [MFTSftpItem] {
        print("Listing directory: \(path)")
        let items = try sftp.contentsOfDirectory(atPath: path, maxItems: 0)
        print("Found \(items.count) items in \(path)")
        return items
    }
    
    func downloadFile(sftp: MFTSftpConnection, remotePath: String, to localURL: URL, progressHandler: @escaping (UInt64, UInt64) -> Bool) throws {
        print("Downloading: \(remotePath) to \(localURL.lastPathComponent)")
        // Ensure parent directory exists
        let parentDir = localURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
        try sftp.downloadFile(atPath: remotePath, toFileAtPath: localURL.path, progress: progressHandler)
        print("Download completed: \(localURL.lastPathComponent)")
    }
}

// MARK: - SFTP Backend

class SFTPBackend {
    private var connections: [UUID: MFTSftpConnection] = [:]
    private var items: [NSFileProviderItemIdentifier: FileProviderItem] = [:]
    
    // Create instances directly - will work regardless of singleton availability
    private lazy var persistenceService = ExtensionPersistenceService()
    private lazy var keychainService = ExtensionKeychainService()
    
    private var syncAnchors: [NSFileProviderItemIdentifier: NSFileProviderSyncAnchor] = [:]
    private let connectionQueue = DispatchQueue(label: "com.mansi.sftpfiles.connections", qos: .userInitiated)
    
    init() {
        print("Initializing SFTP Backend")
        loadConnections()
        setupConnectionObserver()
    }
    
    /// Returns a live SFTP connection for the given connection, reconnecting if needed.
    private func getOrConnectSFTP(for connection: SFTPConnection) -> MFTSftpConnection? {
        if let sftp = connections[connection.id] {
            // Check if connection is still alive - for now assume it is
            return sftp
        }
        
        guard let password = keychainService.getPassword(for: connection.id) else {
            print("No password found for connection: \(connection.name)")
            persistenceService.setConnectionState(.disconnected, for: connection.id)
            return nil
        }
        
        do {
            let sftp = try SharedSFTPService.shared.connect(to: connection, password: password)
            connectionQueue.sync {
                connections[connection.id] = sftp
            }
            print("Backend: Successfully connected to \(connection.name)")
            persistenceService.setConnectionState(.connected, for: connection.id)
            return sftp
        } catch {
            print("Backend: Failed to connect to \(connection.name): \(error)")
            persistenceService.setConnectionState(.error, for: connection.id)
            return nil
        }
    }
    
    private func loadConnections() {
        print("Backend: Loading connections...")
        let savedConnections = persistenceService.loadConnections()
        print("Backend: Found \(savedConnections.count) saved connections")
        
        // Create root items for each connection
        for connection in savedConnections {
            print("Backend: Creating root item for connection: \(connection.name)")
            createRootItem(for: connection)
        }
        
        print("Backend: Created \(items.count) root items")
        
        // Try to auto-connect in background
        connectionQueue.async {
            for connection in savedConnections {
                print("Backend: Processing connection: \(connection.name), autoConnect: \(connection.autoConnect)")
                if connection.autoConnect {
                    self.connectToServer(connection)
                } else {
                    // If not autoConnect, mark as disconnected
                    self.persistenceService.setConnectionState(.disconnected, for: connection.id)
                }
            }
        }
    }
    
    private func createRootItem(for connection: SFTPConnection) {
        let rootIdentifier = NSFileProviderItemIdentifier("connection_\(connection.id.uuidString)")
        
        let rootItem = FileProviderItem(
            identifier: rootIdentifier,
            filename: connection.name,
            typeIdentifier: "public.folder",
            isDirectory: true,
            remotePath: "/",
            connectionId: connection.id,
            parentIdentifier: .rootContainer
        )
        
        items[rootIdentifier] = rootItem
        print("Created root item for connection: \(connection.name)")
    }
    
    private func setupConnectionObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectionsChanged),
            name: Notification.Name("SFTPConnectionsChanged"),
            object: nil
        )
    }
    
    @objc private func connectionsChanged() {
        print("Backend: Connections changed notification received")
        loadConnections()
    }
    
    private func connectToServer(_ connection: SFTPConnection) {
        print("Backend: Attempting to connect to \(connection.name)")
        
        guard let password = keychainService.getPassword(for: connection.id) else {
            print("No password found for connection: \(connection.name)")
            persistenceService.setConnectionState(.disconnected, for: connection.id)
            return
        }
        
        do {
            let sftp = try SharedSFTPService.shared.connect(to: connection, password: password)
            connectionQueue.sync {
                connections[connection.id] = sftp
            }
            print("Backend: Successfully connected to \(connection.name)")
            persistenceService.setConnectionState(.connected, for: connection.id)
        } catch {
            print("Backend: Failed to connect to \(connection.name): \(error)")
            persistenceService.setConnectionState(.error, for: connection.id)
        }
    }
    
    func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem {
        print("Requesting item for identifier: \(identifier.rawValue)")
        
        guard let item = items[identifier] else {
            print("No item found for identifier: \(identifier.rawValue)")
            throw NSFileProviderError(.noSuchItem)
        }
        
        print("Returning item: \(item.filename)")
        return item
    }
    
    func urlForItem(withIdentifier identifier: NSFileProviderItemIdentifier) -> URL? {
        guard let item = items[identifier] else { 
            print("No item found for URL request: \(identifier.rawValue)")
            return nil 
        }
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileProviderDir = documentsURL.appendingPathComponent("FileProvider")
        let url = fileProviderDir.appendingPathComponent(item.filename)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: fileProviderDir, withIntermediateDirectories: true, attributes: nil)
        
        print("URL for item \(item.filename): \(url)")
        return url
    }
    
    func persistentIdentifier(for url: URL) -> NSFileProviderItemIdentifier? {
        for (identifier, item) in items {
            if url.lastPathComponent == item.filename {
                return identifier
            }
        }
        return nil
    }
    
    func persistentIdentifier(forPath path: String) -> NSFileProviderItemIdentifier? {
        for (identifier, item) in items {
            if item.remotePath == path {
                return identifier
            }
        }
        return nil
    }
    
    func providePlaceholder(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        print("Providing placeholder at: \(url)")
        
        connectionQueue.async {
            do {
                let placeholderContent = ""
                try placeholderContent.write(to: url, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    completionHandler(nil)
                }
            } catch {
                print("Failed to create placeholder: \(error)")
                DispatchQueue.main.async {
                    completionHandler(error)
                }
            }
        }
    }
    
    func startProvidingItem(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        print("Start providing item at: \(url)")
        
        guard let identifier = persistentIdentifier(for: url),
              let item = items[identifier] else {
            print("Cannot provide item - missing identifier or item")
            completionHandler(NSFileProviderError(.noSuchItem))
            return
        }
        
        connectionQueue.async {
            guard let connection = self.persistenceService.getConnection(withId: item.connectionId),
                  let sftp = self.getOrConnectSFTP(for: connection) else {
                print("Cannot provide item - missing SFTP connection")
                DispatchQueue.main.async {
                    completionHandler(NSFileProviderError(.serverUnreachable))
                }
                return
            }
            
            do {
                try SharedSFTPService.shared.downloadFile(
                    sftp: sftp,
                    remotePath: item.remotePath,
                    to: url
                ) { downloaded, total in
                    print("Download progress: \(downloaded)/\(total)")
                    return true
                }
                DispatchQueue.main.async {
                    completionHandler(nil)
                }
            } catch {
                print("Failed to download file: \(error)")
                DispatchQueue.main.async {
                    completionHandler(error)
                }
            }
        }
    }
    
    func itemChanged(at url: URL) {
        guard let identifier = persistentIdentifier(for: url) else { return }
        
        NSFileProviderManager.default.signalEnumerator(for: identifier) { error in
            if let error = error {
                print("Failed to signal item change: \(error)")
            } else {
                print("Signaled item change for: \(url.lastPathComponent)")
            }
        }
    }
    
    func stopProvidingItem(at url: URL) {
        print("Stop providing item at: \(url)")
        // Clean up any temporary files if needed
    }
    
    // MARK: - Enumeration Methods - Disabled for now
    
    func enumerateItems(
        for containerIdentifier: NSFileProviderItemIdentifier,
        observer: NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) {
        print("Backend: Enumeration disabled - using minimal extension instead")
        observer.didEnumerate([])
        observer.finishEnumerating(upTo: nil)
    }
    
    func enumerateChanges(
        for containerIdentifier: NSFileProviderItemIdentifier,
        observer: NSFileProviderChangeObserver,
        from anchor: NSFileProviderSyncAnchor
    ) {
        print("Enumerating changes for: \(containerIdentifier.rawValue)")
        let currentAnchor = NSFileProviderSyncAnchor(Data())
        observer.finishEnumeratingChanges(upTo: currentAnchor, moreComing: false)
    }
    
    func currentSyncAnchor(for containerIdentifier: NSFileProviderItemIdentifier, completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let anchor = syncAnchors[containerIdentifier] ?? NSFileProviderSyncAnchor(Data())
        completionHandler(anchor)
    }
}
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
                        port: Int(Int32(connection.port)),
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
    /// Returns a live SFTP connection for the given connection, reconnecting if needed.
    private func getOrConnectSFTP(for connection: SFTPConnection) -> MFTSftpConnection? {
        if let sftp = connections[connection.id] {
            // Optionally, check if sftp.isConnected if your library supports it
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
    private var connections: [UUID: MFTSftpConnection] = [:]
    private var items: [NSFileProviderItemIdentifier: FileProviderItem] = [:]
    private let persistenceService = SharedPersistenceService()
    private let keychainService = SharedKeychainService()
    private var syncAnchors: [NSFileProviderItemIdentifier: NSFileProviderSyncAnchor] = [:]
    private let connectionQueue = DispatchQueue(label: "com.mansi.sftpfiles.connections", qos: .userInitiated)
    
    init() {
        print("Initializing SFTP Backend")
        loadConnections()
        setupConnectionObserver()
    }
    
    private func loadConnections() {
        print("Backend: Loading connections...")
        let savedConnections = persistenceService.loadConnections()
        print("Backend: Found \(savedConnections.count) saved connections")
        // Create root items for each connection on main queue
        DispatchQueue.main.async {
            for connection in savedConnections {
                self.createRootItem(for: connection)
            }
        }
        // Try to auto-connect in background
        connectionQueue.async {
            for connection in savedConnections {
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
        // Always fetch the latest password from the keychain
        let password = keychainService.getPassword(for: connection.id)
        if password == nil {
            print("No password found for connection: \(connection.name)")
            persistenceService.setConnectionState(.disconnected, for: connection.id)
            return
        }
        do {
            let sftp = try SharedSFTPService.shared.connect(to: connection, password: password!)
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
            guard let sftp = self.connections[item.connectionId] else {
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
    
    // MARK: - Enumeration Methods
    
    func enumerateItems(
        for containerIdentifier: NSFileProviderItemIdentifier,
        observer: NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) {
        print("Enumerating items for container: \(containerIdentifier.rawValue)")
        connectionQueue.async {
            do {
                if containerIdentifier == .rootContainer {
                    print("Enumerating root container")
                    let rootItems = Array(self.items.values.filter { $0.parentItemIdentifier == .rootContainer })
                    print("Found \(rootItems.count) root items")
                    DispatchQueue.main.async {
                        observer.didEnumerate(rootItems)
                        observer.finishEnumerating(upTo: nil)
                    }
                    return
                }
                guard let containerItem = self.items[containerIdentifier] else {
                    print("Container item not found: \(containerIdentifier.rawValue)")
                    DispatchQueue.main.async {
                        observer.finishEnumeratingWithError(NSFileProviderError(.noSuchItem))
                    }
                    return
                }
                guard let sftp = self.getOrConnectSFTP(for: SFTPConnection(
                    name: containerItem.filename,
                    hostname: "",
                    port: 22,
                    username: "",
                    useKeyAuth: false,
                    privateKeyPath: nil,
                    state: .disconnected,
                    lastConnected: nil,
                    autoConnect: true,
                    createdDate: Date(),
                    id: containerItem.connectionId
                )) else {
                    print("No SFTP connection for container: \(containerItem.filename)")
                    DispatchQueue.main.async {
                        observer.finishEnumeratingWithError(NSFileProviderError(.serverUnreachable))
                    }
                    return
                }
                print("Enumerating directory: \(containerItem.remotePath)")
                let directoryItems = try SharedSFTPService.shared.listDirectory(
                    sftp: sftp,
                    path: containerItem.remotePath
                )
                var providerItems: [NSFileProviderItem] = []
                for item in directoryItems {
                    let filename = item.filename
                    let isDirectory = item.isDirectory
                    let modDate = item.mtime
                    let fileSize = Int64(item.size)
                    if filename.hasPrefix(".") || filename == "." || filename == ".." {
                        continue
                    }
                    let itemPath = "\(containerItem.remotePath)/\(filename)".replacingOccurrences(of: "//", with: "/")
                    let itemIdentifier = NSFileProviderItemIdentifier("item_\(containerItem.connectionId.uuidString)_\(abs(itemPath.hashValue))")
                    let providerItem = FileProviderItem(
                        identifier: itemIdentifier,
                        filename: filename,
                        typeIdentifier: isDirectory ? "public.folder" : "public.data",
                        isDirectory: isDirectory,
                        remotePath: itemPath,
                        connectionId: containerItem.connectionId,
                        fileSize: fileSize,
                        modificationDate: modDate,
                        parentIdentifier: containerIdentifier
                    )
                    self.items[itemIdentifier] = providerItem
                    providerItems.append(providerItem)
                }
                print("Enumerated \(providerItems.count) items in \(containerItem.remotePath)")
                DispatchQueue.main.async {
                    observer.didEnumerate(providerItems)
                    observer.finishEnumerating(upTo: nil)
                }
            } catch {
                print("Enumeration failed: \(error)")
                DispatchQueue.main.async {
                    observer.finishEnumeratingWithError(error)
                }
            }
        }
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
    
    // MARK: - Helper Methods for MFT Item Parsing
    
    private func extractFilename(from item: Any, fallback: String) -> String {
        // Try different approaches to extract filename based on MFT structure
        if let dict = item as? [String: Any] {
            if let filename = dict["filename"] as? String { return filename }
            if let name = dict["name"] as? String { return name }
        }
        
        let mirror = Mirror(reflecting: item)
        for child in mirror.children {
            if let label = child.label {
                if label == "filename" || label == "name" || label.contains("name") {
                    let value = String(describing: child.value)
                    // Clean up the value string
                    if !value.isEmpty && value != "nil" && !value.contains("Optional") {
                        return value.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        
        // If all else fails, try to extract from string description
        let description = String(describing: item)
        if let range = description.range(of: #"filename[^"]*"([^"]+)""#, options: .regularExpression) {
            let match = description[range]
            if let nameRange = match.range(of: #""([^"]+)""#, options: .regularExpression) {
                let nameMatch = match[nameRange]
                return String(nameMatch.dropFirst().dropLast())
            }
        }
        
        return fallback
    }
    
    private func extractIsDirectory(from item: Any) -> Bool {
        if let dict = item as? [String: Any] {
            if let isDir = dict["isDirectory"] as? Bool { return isDir }
            if let isDir = dict["directory"] as? Bool { return isDir }
            if let type = dict["type"] as? String { return type.contains("directory") }
        }
        
        let mirror = Mirror(reflecting: item)
        for child in mirror.children {
            if let label = child.label {
                if label.lowercased().contains("dir") || label.lowercased().contains("folder") {
                    if let isDir = child.value as? Bool {
                        return isDir
                    }
                    let value = String(describing: child.value)
                    return value.lowercased().contains("true") || value.lowercased().contains("directory")
                }
                if label == "type" {
                    let typeStr = String(describing: child.value).lowercased()
                    return typeStr.contains("directory") || typeStr.contains("folder")
                }
            }
        }
        
        // Check string description as fallback
        let description = String(describing: item).lowercased()
        return description.contains("directory") || description.contains("folder")
    }
    
    private func extractModificationDate(from item: Any) -> Date? {
        if let dict = item as? [String: Any] {
            if let timestamp = dict["modTime"] as? TimeInterval {
                return Date(timeIntervalSince1970: timestamp)
            }
            if let date = dict["modificationDate"] as? Date {
                return date
            }
            if let timestamp = dict["mtime"] as? TimeInterval {
                return Date(timeIntervalSince1970: timestamp)
            }
        }
        
        let mirror = Mirror(reflecting: item)
        for child in mirror.children {
            if let label = child.label {
                if label.lowercased().contains("mod") || label.lowercased().contains("time") || label.lowercased().contains("date") {
                    if let date = child.value as? Date {
                        return date
                    } else if let timestamp = child.value as? TimeInterval {
                        return Date(timeIntervalSince1970: timestamp)
                    } else if let timestamp = child.value as? Int64 {
                        return Date(timeIntervalSince1970: TimeInterval(timestamp))
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractFileSize(from item: Any) -> Int64? {
        if let dict = item as? [String: Any] {
            if let size = dict["size"] as? Int64 { return size }
            if let size = dict["fileSize"] as? Int64 { return size }
            if let size = dict["size"] as? Int { return Int64(size) }
            if let size = dict["length"] as? Int64 { return size }
        }
        
        let mirror = Mirror(reflecting: item)
        for child in mirror.children {
            if let label = child.label {
                if label.lowercased().contains("size") || label.lowercased().contains("length") {
                    if let size = child.value as? Int64 {
                        return size
                    } else if let size = child.value as? Int {
                        return Int64(size)
                    } else if let size = child.value as? UInt64 {
                        return Int64(size)
                    }
                }
            }
        }
        
        return nil
    }
}
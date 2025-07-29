//
//  FileProviderExtension.swift
//  SFTPFilesFileProvider
//
//  Created by Maikel Mansi on 28/07/2025.
//

import FileProvider
import os.log
import mft

class FileProviderExtension: NSFileProviderExtension {
    
    private let logger = Logger(subsystem: "com.mansi.sftpfiles", category: "FileProvider")
    private let persistenceService = SharedPersistenceService.shared
    private let keychainService = SharedKeychainService()
    
    override init() {
        // Use NSLog to ensure this appears in device console
        NSLog("🔥🔥🔥 FILEPROVIDER EXTENSION LOADING 🔥🔥🔥")
        NSLog("Bundle ID: %@", Bundle.main.bundleIdentifier ?? "unknown")
        
        super.init()
        
        // Use print AND logger to ensure we see output everywhere
        print("=== CRITICAL: FileProviderExtension initialized ===")
        print("=== Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown") ===")
        print("=== Bundle Path: \(Bundle.main.bundlePath) ===")
        
        logger.info("=== FileProviderExtension initialized ===")
        
        // Force immediate connection check
        print("=== CHECKING CONNECTIONS IMMEDIATELY ===")
        let connections = persistenceService.loadConnections()
        NSLog("🔥 FileProvider found %d connections", connections.count)
        print("=== FileProvider: Found \(connections.count) connections during init ===")
        
        for connection in connections {
            NSLog("🔥 Connection: %@ [%@]", connection.name, connection.id.uuidString)
            print("=== FileProvider: - Connection: \(connection.name) [\(connection.id)] ===")
            logger.info("- Connection: \(connection.name) [\(connection.id)]")
        }
        
        // Test if we can access shared storage
        if let sharedDefaults = UserDefaults(suiteName: "group.com.mansi.sftpfiles") {
            NSLog("🔥 FileProvider: Can access shared UserDefaults")
            print("=== FileProvider: Can access shared UserDefaults ===")
            let allKeys = sharedDefaults.dictionaryRepresentation().keys
            print("=== FileProvider: Shared keys: \(Array(allKeys)) ===")
        } else {
            NSLog("🔥 CRITICAL ERROR: Cannot access shared UserDefaults")
            print("=== CRITICAL ERROR: Cannot access shared UserDefaults ===")
        }
        
        // Write a test file with timestamp
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let testFile = documentsURL.appendingPathComponent("fileprovider_init_\(Date().timeIntervalSince1970).txt")
            do {
                try "FileProvider Extension initialized at \(Date())".write(to: testFile, atomically: true, encoding: .utf8)
                NSLog("🔥 FileProvider: Test file written successfully")
                print("=== FileProvider: Test file written to: \(testFile.path) ===")
            } catch {
                NSLog("🔥 CRITICAL ERROR: Cannot write test file: %@", error.localizedDescription)
                print("=== CRITICAL ERROR: Cannot write test file: \(error) ===")
            }
        }
        
        NSLog("🔥🔥🔥 FILEPROVIDER EXTENSION INIT COMPLETE 🔥🔥🔥")
        print("=== FileProviderExtension initialization complete ===")
    }
    
    // MARK: - Item Methods
    
    override func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem {
        NSLog("🔥 item(for:) called with identifier: %@", identifier.rawValue)
        print("FileProvider: item(for:) called with identifier: \(identifier.rawValue)")
        logger.info("Requesting item for identifier: \(identifier.rawValue)")

        if identifier == .rootContainer {
            NSLog("🔥 Returning root container item")
            print("FileProvider: Returning root container item")
            return FileProviderItem(
                identifier: .rootContainer,
                filename: "SFTP Files",
                typeIdentifier: "public.folder",
                isDirectory: true,
                remotePath: "/",
                connectionId: UUID(),
                parentIdentifier: .rootContainer
            )
        }

        // Parse identifier: connection_<uuid>[_<encodedPath>]
        let idPrefix = "connection_"
        guard identifier.rawValue.hasPrefix(idPrefix) else {
            print("FileProvider: Invalid identifier format: \(identifier.rawValue)")
            logger.error("Invalid identifier format: \(identifier.rawValue)")
            throw NSFileProviderError(.noSuchItem)
        }

        let rest = identifier.rawValue.dropFirst(idPrefix.count)
        let components = rest.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
        let uuidString = String(components[0])
        
        guard let uuid = UUID(uuidString: uuidString),
              let connection = persistenceService.getConnection(withId: uuid) else {
            print("FileProvider: No connection found for identifier: \(identifier.rawValue)")
            logger.error("No connection found for identifier: \(identifier.rawValue)")
            throw NSFileProviderError(.noSuchItem)
        }

        var remotePath = "/"
        var parentIdentifier = NSFileProviderItemIdentifier.rootContainer
        
        if components.count == 2 {
            let pathComponent = String(components[1])
            remotePath = pathComponent.replacingOccurrences(of: "__SLASH__", with: "/")
            
            // Calculate parent identifier
            let parentPath = (remotePath as NSString).deletingLastPathComponent
            if parentPath == "/" || parentPath.isEmpty {
                parentIdentifier = NSFileProviderItemIdentifier("connection_\(connection.id.uuidString)")
            } else {
                let encodedParentPath = parentPath.replacingOccurrences(of: "/", with: "__SLASH__")
                parentIdentifier = NSFileProviderItemIdentifier("connection_\(connection.id.uuidString)_\(encodedParentPath)")
            }
        } else {
            // This is the connection root
            parentIdentifier = .rootContainer
        }

        let filename = remotePath == "/" ? connection.name : (remotePath as NSString).lastPathComponent
        let typeIdentifier = remotePath == "/" ? "public.folder" : "public.data"
        
        print("FileProvider: Returning item: \(filename) for connection: \(connection.name)")
        
        return FileProviderItem(
            identifier: identifier,
            filename: filename,
            typeIdentifier: typeIdentifier,
            isDirectory: remotePath == "/" || typeIdentifier == "public.folder",
            remotePath: remotePath,
            connectionId: connection.id,
            parentIdentifier: parentIdentifier
        )
    }
    
    override func urlForItem(withPersistentIdentifier identifier: NSFileProviderItemIdentifier) -> URL? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileProviderDir = documentsURL.appendingPathComponent("FileProvider")
        let url = fileProviderDir.appendingPathComponent(identifier.rawValue)
        
        try? FileManager.default.createDirectory(at: fileProviderDir, withIntermediateDirectories: true, attributes: nil)
        
        return url
    }
    
    override func persistentIdentifierForItem(at url: URL) -> NSFileProviderItemIdentifier? {
        return NSFileProviderItemIdentifier(url.lastPathComponent)
    }
    
    override func providePlaceholder(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        guard let identifier = persistentIdentifierForItem(at: url) else {
            completionHandler(NSFileProviderError(.noSuchItem))
            return
        }
        
        do {
            let fileProviderItem = try item(for: identifier)
            let placeholderURL = NSFileProviderManager.placeholderURL(for: url)
            try NSFileProviderManager.writePlaceholder(at: placeholderURL, withMetadata: fileProviderItem)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
    
    override func startProvidingItem(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        logger.info("startProvidingItem at: \(url.path)")
        
        guard let identifier = persistentIdentifierForItem(at: url) else {
            completionHandler(NSFileProviderError(.noSuchItem))
            return
        }
        
        // Parse the identifier to get connection and path info
        let idPrefix = "connection_"
        guard identifier.rawValue.hasPrefix(idPrefix) else {
            logger.error("Invalid identifier for file download: \(identifier.rawValue)")
            completionHandler(NSFileProviderError(.noSuchItem))
            return
        }
        
        let rest = identifier.rawValue.dropFirst(idPrefix.count)
        let components = rest.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
        let uuidString = String(components[0])
        
        guard let uuid = UUID(uuidString: uuidString),
              let connection = persistenceService.getConnection(withId: uuid),
              let password = keychainService.getPassword(for: connection.id) else {
            logger.error("Cannot get connection info for download: \(identifier.rawValue)")
            completionHandler(NSFileProviderError(.notAuthenticated))
            return
        }
        
        var remotePath = "/"
        if components.count == 2 {
            let pathComponent = String(components[1])
            remotePath = pathComponent.replacingOccurrences(of: "__SLASH__", with: "/")
        }
        
        // Download the file in background
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let sftp = try SFTPService.shared.connect(to: connection, password: password)
                defer { sftp.disconnect() }
                
                // Download file
                try SFTPService.shared.downloadFile(
                    sftp: sftp, 
                    remotePath: remotePath, 
                    to: url
                ) { bytesDownloaded, totalBytes in
                    // Progress callback - return true to continue
                    return true
                }
                
                self.logger.info("Successfully downloaded file: \(remotePath)")
                DispatchQueue.main.async {
                    completionHandler(nil)
                }
            } catch {
                self.logger.error("Failed to download file: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completionHandler(NSFileProviderError(.serverUnreachable))
                }
            }
        }
    }
    
    override func itemChanged(at url: URL) {
        logger.info("itemChanged at: \(url.path)")
    }
    
    override func stopProvidingItem(at url: URL) {
        logger.info("stopProvidingItem at: \(url.path)")
        // Remove the local file
        try? FileManager.default.removeItem(at: url)
    }
    
    // MARK: - Enumeration
    
    override func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier) throws -> NSFileProviderEnumerator {
        NSLog("🔥 enumerator(for:) called with identifier: %@", containerItemIdentifier.rawValue)
        print("FileProvider: enumerator(for:) called with identifier: \(containerItemIdentifier.rawValue)")
        logger.info("Creating enumerator for: \(containerItemIdentifier.rawValue)")
        return FileProviderEnumerator(enumeratedItemIdentifier: containerItemIdentifier)
    }
}

// MARK: - File Provider Enumerator

class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    
    private let enumeratedItemIdentifier: NSFileProviderItemIdentifier
    private let logger = Logger(subsystem: "com.mansi.sftpfiles", category: "Enumerator")
    private let persistenceService = SharedPersistenceService.shared
    private let keychainService = SharedKeychainService()
    
    init(enumeratedItemIdentifier: NSFileProviderItemIdentifier) {
        self.enumeratedItemIdentifier = enumeratedItemIdentifier
        super.init()
        logger.info("Created enumerator for: \(enumeratedItemIdentifier.rawValue)")
    }
    
    func invalidate() {
        logger.info("Enumerator invalidated")
    }
    
    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        NSLog("🔥 enumerateItems called for: %@", self.enumeratedItemIdentifier.rawValue)
        print("FileProvider: enumerateItems called for: \(self.enumeratedItemIdentifier.rawValue)")
        logger.info("Enumerating items for: \(self.enumeratedItemIdentifier.rawValue)")

        // If root, enumerate all connections
        if enumeratedItemIdentifier == .rootContainer {
            NSLog("🔥 Enumerating root container")
            print("FileProvider: Enumerating root container")
            let connections = persistenceService.loadConnections()
            NSLog("🔥 Found %d connections to enumerate", connections.count)
            print("FileProvider: Found \(connections.count) connections to enumerate")
            logger.info("Found \(connections.count) connections to enumerate")
            
            if connections.isEmpty {
                NSLog("🔥 No connections found - returning empty enumeration")
                print("FileProvider: No connections found - returning empty enumeration")
                logger.warning("No connections found - returning empty enumeration")
                observer.didEnumerate([])
                observer.finishEnumerating(upTo: nil)
                return
            }
            
            let items: [NSFileProviderItem] = connections.map { connection in
                let connectionIdentifier = NSFileProviderItemIdentifier("connection_\(connection.id.uuidString)")
                NSLog("🔥 Adding connection item: %@ [%@]", connection.name, connection.id.uuidString)
                print("FileProvider: Adding connection item: \(connection.name) [\(connection.id)]")
                logger.info("Adding connection item: \(connection.name) [\(connection.id)]")
                return FileProviderItem(
                    identifier: connectionIdentifier,
                    filename: connection.name,
                    typeIdentifier: "public.folder", 
                    isDirectory: true,
                    remotePath: "/",
                    connectionId: connection.id,
                    parentIdentifier: .rootContainer
                )
            }
            
            NSLog("🔥 Returning %d connection items", items.count)
            print("FileProvider: Returning \(items.count) connection items")
            logger.info("Returning \(items.count) connection items")
            observer.didEnumerate(items)
            observer.finishEnumerating(upTo: nil)
            return
        }

        // Parse connection identifier
        let idPrefix = "connection_"
        guard enumeratedItemIdentifier.rawValue.hasPrefix(idPrefix) else {
            logger.error("Unknown container identifier: \(self.enumeratedItemIdentifier.rawValue)")
            observer.didEnumerate([])
            observer.finishEnumerating(upTo: nil)
            return
        }

        let rest = enumeratedItemIdentifier.rawValue.dropFirst(idPrefix.count)
        let components = rest.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
        let uuidString = String(components[0])
        
        guard let uuid = UUID(uuidString: uuidString),
              let connection = persistenceService.getConnection(withId: uuid),
              let password = keychainService.getPassword(for: connection.id) else {
            logger.error("No connection found for identifier: \(self.enumeratedItemIdentifier.rawValue)")
            observer.didEnumerate([])
            observer.finishEnumerating(upTo: nil)
            return
        }

        var remotePath = "/"
        if components.count == 2 {
            let pathComponent = String(components[1])
            remotePath = pathComponent.replacingOccurrences(of: "__SLASH__", with: "/")
        }

        // SFTP enumeration in background
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                self.logger.info("Connecting to SFTP for \(connection.name) at path: \(remotePath)")
                let sftp = try SFTPService.shared.connect(to: connection, password: password)
                defer { sftp.disconnect() }
                
                self.logger.info("Listing directory: \(remotePath)")
                let entries = try SFTPService.shared.listDirectory(sftp: sftp, path: remotePath)
                self.logger.info("Directory listing returned \(entries.count) entries")
                
                let items: [NSFileProviderItem] = entries.map { entry in
                    let fullPath = (remotePath as NSString).appendingPathComponent(entry.filename)
                    let encodedPath = fullPath.replacingOccurrences(of: "/", with: "__SLASH__")
                    let itemIdentifier = NSFileProviderItemIdentifier("connection_\(connection.id.uuidString)_\(encodedPath)")
                    
                    self.logger.info("Item: \(entry.filename) [\(entry.isDirectory ? "dir" : "file")] size=\(entry.size) path=\(fullPath)")
                    
                    // Determine the appropriate type identifier based on file extension
                    let typeIdentifier: String
                    if entry.isDirectory {
                        typeIdentifier = "public.folder"
                    } else if entry.isSymlink {
                        typeIdentifier = "public.symlink"
                    } else {
                        // Use file extension to determine type
                        let fileExtension = (entry.filename as NSString).pathExtension.lowercased()
                        switch fileExtension {
                        case "txt", "md", "readme":
                            typeIdentifier = "public.plain-text"
                        case "jpg", "jpeg", "png", "gif", "bmp":
                            typeIdentifier = "public.image"
                        case "pdf":
                            typeIdentifier = "com.adobe.pdf"
                        case "mp4", "mov", "avi":
                            typeIdentifier = "public.movie"
                        case "mp3", "wav", "m4a":
                            typeIdentifier = "public.audio"
                        case "zip", "tar", "gz":
                            typeIdentifier = "public.archive"
                        default:
                            typeIdentifier = "public.data"
                        }
                    }
                    
                    return FileProviderItem(
                        identifier: itemIdentifier,
                        filename: entry.filename,
                        typeIdentifier: typeIdentifier,
                        isDirectory: entry.isDirectory,
                        remotePath: fullPath,
                        connectionId: connection.id,
                        fileSize: entry.isDirectory ? nil : Int64(entry.size),
                        modificationDate: entry.mtime,
                        creationDate: entry.createTime,
                        parentIdentifier: self.enumeratedItemIdentifier
                    )
                }
                
                DispatchQueue.main.async {
                    observer.didEnumerate(items)
                    observer.finishEnumerating(upTo: nil)
                }
                
            } catch {
                self.logger.error("Failed to list SFTP directory: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    let nsError: NSFileProviderError
                    let msg = error.localizedDescription.lowercased()
                    if msg.contains("not found") || msg.contains("no such file") {
                        nsError = NSFileProviderError(.noSuchItem)
                    } else if msg.contains("permission") || msg.contains("denied") {
                        nsError = NSFileProviderError(.notAuthenticated)
                    } else if msg.contains("timeout") || msg.contains("connection") {
                        nsError = NSFileProviderError(.serverUnreachable)
                    } else {
                        nsError = NSFileProviderError(.serverUnreachable)
                    }
                    observer.finishEnumeratingWithError(nsError)
                }
            }
        }
    }
    
    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        logger.info("Enumerating changes from anchor")
        
        let newAnchor = NSFileProviderSyncAnchor(Data())
        observer.finishEnumeratingChanges(upTo: newAnchor, moreComing: false)
    }
    
    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        logger.info("Returning current sync anchor")
        
        let anchor = NSFileProviderSyncAnchor(Data())
        completionHandler(anchor)
    }
}
//
//  FileProviderExtension.swift


import FileProvider
import os.log
import mft
import UniformTypeIdentifiers

class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    
    private let persistenceService = SharedPersistenceService.shared
    private let keychainService = SharedKeychainService()
    
    required init(domain: NSFileProviderDomain) {
        super.init()
        print("[FileProviderExtension] Initialized with domain: \(domain.identifier.rawValue)")
    }
    
    func invalidate() {
        print("[FileProviderExtension] Extension invalidated")
    }
    
    // MARK: - NSFileProviderReplicatedExtension
    
    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        print("[FileProviderExtension] item(for:) called with identifier: \(identifier.rawValue)")
        
        let progress = Progress(totalUnitCount: 1)
        
        if identifier == .rootContainer {
            // Create a virtual root item
            let rootItem = VirtualRootItem()
            completionHandler(rootItem, nil)
            progress.completedUnitCount = 1
            return progress
        }
        
        // Handle connection items
        if identifier.rawValue.hasPrefix("connection_") {
            if let item = createFileProviderItem(for: identifier) {
                completionHandler(item, nil)
            } else {
                completionHandler(nil, NSFileProviderError(.noSuchItem))
            }
            progress.completedUnitCount = 1
            return progress
        }
        
        completionHandler(nil, NSFileProviderError(.noSuchItem))
        progress.completedUnitCount = 1
        return progress
    }
    
    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version: NSFileProviderItemVersion?, request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        print("[FileProviderExtension] fetchContents called for: \(itemIdentifier.rawValue)")
        
        let progress = Progress(totalUnitCount: 100)
        
        guard itemIdentifier != .rootContainer else {
            completionHandler(nil, nil, NSFileProviderError(.noSuchItem))
            return progress
        }
        
        // Parse the identifier to get connection and path info
        guard let (connection, remotePath) = parseItemIdentifier(itemIdentifier) else {
            completionHandler(nil, nil, NSFileProviderError(.noSuchItem))
            return progress
        }
        
        guard let password = keychainService.getPassword(for: connection.id) else {
            completionHandler(nil, nil, NSFileProviderError(.notAuthenticated))
            return progress
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let sftp = try SFTPService.shared.connect(to: connection, password: password)
                defer { sftp.disconnect() }
                
                // Create temporary file
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                
                try SFTPService.shared.downloadFile(
                    sftp: sftp,
                    remotePath: remotePath,
                    to: tempURL,
                    progressHandler: { downloaded, total in
                        DispatchQueue.main.async {
                            progress.totalUnitCount = Int64(total)
                            progress.completedUnitCount = Int64(downloaded)
                        }
                        return !progress.isCancelled
                    }
                )
                
                let item = self.createFileProviderItem(for: itemIdentifier)
                
                DispatchQueue.main.async {
                    completionHandler(tempURL, item, nil)
                }
                
            } catch {
                print("[FileProviderExtension] Failed to fetch contents: \(error)")
                DispatchQueue.main.async {
                    completionHandler(nil, nil, error)
                }
            }
        }
        
        return progress
    }
    
    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents: URL?, options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        completionHandler(nil, [], false, CocoaError(.featureUnsupported))
        return Progress()
    }
    
    func modifyItem(_ item: NSFileProviderItem, baseVersion: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields, contents: URL?, options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        completionHandler(nil, [], false, CocoaError(.featureUnsupported))
        return Progress()
    }
    
    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion: NSFileProviderItemVersion, options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (Error?) -> Void) -> Progress {
        completionHandler(CocoaError(.featureUnsupported))
        return Progress()
    }
    
    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        print("[FileProviderExtension] Creating enumerator for: \(containerItemIdentifier.rawValue)")
        return FileProviderEnumerator(enumeratedItemIdentifier: containerItemIdentifier)
    }
    
    // MARK: - Helper Methods
    
    private func createFileProviderItem(for identifier: NSFileProviderItemIdentifier) -> NSFileProviderItem? {
        guard let (connection, remotePath) = parseItemIdentifier(identifier) else {
            return nil
        }
        
        guard let password = keychainService.getPassword(for: connection.id) else {
            return nil
        }
        
        do {
            let sftp = try SFTPService.shared.connect(to: connection, password: password)
            defer { sftp.disconnect() }
            
            let parentPath = (remotePath as NSString).deletingLastPathComponent
            let filename = (remotePath as NSString).lastPathComponent
            
            let entries = try SFTPService.shared.listDirectory(sftp: sftp, path: parentPath.isEmpty ? "/" : parentPath)
            
            if let sftpItem = entries.first(where: { $0.filename == filename }) {
                let parentIdentifier: NSFileProviderItemIdentifier
                if parentPath == "/" || parentPath.isEmpty {
                    parentIdentifier = NSFileProviderItemIdentifier("connection_\(connection.id.uuidString)")
                } else {
                    let encodedParentPath = parentPath.replacingOccurrences(of: "/", with: "__SLASH__")
                    parentIdentifier = NSFileProviderItemIdentifier("connection_\(connection.id.uuidString)_\(encodedParentPath)")
                }
                
                return FileProviderItem(
                    itemIdentifier: identifier,
                    parentItemIdentifier: parentIdentifier,
                    sftpItem: sftpItem
                )
            }
        } catch {
            print("[FileProviderExtension] Error creating item: \(error)")
        }
        
        return nil
    }
    
    private func parseItemIdentifier(_ identifier: NSFileProviderItemIdentifier) -> (SFTPConnection, String)? {
        let idPrefix = "connection_"
        guard identifier.rawValue.hasPrefix(idPrefix) else { return nil }
        
        let rest = identifier.rawValue.dropFirst(idPrefix.count)
        let components = rest.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
        let uuidString = String(components[0])
        
        guard let uuid = UUID(uuidString: uuidString),
              let connection = persistenceService.getConnection(withId: uuid) else {
            return nil
        }
        
        var remotePath = "/"
        if components.count == 2 {
            let pathComponent = String(components[1])
            remotePath = pathComponent.replacingOccurrences(of: "__SLASH__", with: "/")
        }
        
        return (connection, remotePath)
    }
}

// MARK: - Virtual Root Item

class VirtualRootItem: NSObject, NSFileProviderItem {
    var itemIdentifier: NSFileProviderItemIdentifier { .rootContainer }
    var parentItemIdentifier: NSFileProviderItemIdentifier { .rootContainer }
    var filename: String { "SFTP Files" }
    var typeIdentifier: String { UTType.folder.identifier }
    var contentType: UTType { .folder }
    
    var capabilities: NSFileProviderItemCapabilities {
        return [.allowsReading, .allowsContentEnumerating]
    }
    
    var fileSystemFlags: NSFileProviderFileSystemFlags {
        return [.userReadable]
    }
}

// MARK: - File Provider Enumerator (Updated)

class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    
    private let enumeratedItemIdentifier: NSFileProviderItemIdentifier
    private let persistenceService = SharedPersistenceService.shared
    private let keychainService = SharedKeychainService()
    
    init(enumeratedItemIdentifier: NSFileProviderItemIdentifier) {
        self.enumeratedItemIdentifier = enumeratedItemIdentifier
        super.init()
        print("[FileProviderEnumerator] Created for identifier: \(enumeratedItemIdentifier.rawValue)")
    }
    
    func invalidate() {
        print("[FileProviderEnumerator] Invalidated")
    }
    
    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        print("[FileProviderEnumerator] enumerateItems called for: \(enumeratedItemIdentifier.rawValue)")
        
        if enumeratedItemIdentifier == .rootContainer {
            enumerateRootContainer(observer: observer)
            return
        }
        
        enumerateConnectionContainer(observer: observer)
    }
    
    private func enumerateRootContainer(observer: NSFileProviderEnumerationObserver) {
        print("[FileProviderEnumerator] Enumerating root container")
        
        let connections = persistenceService.loadConnections()
        print("[FileProviderEnumerator] Found \(connections.count) connections")
        
        let items: [NSFileProviderItem] = connections.compactMap { connection in
            let itemIdentifier = NSFileProviderItemIdentifier("connection_\(connection.id.uuidString)")
            return ConnectionRootItem(
                itemIdentifier: itemIdentifier,
                parentItemIdentifier: .rootContainer,
                connection: connection
            )
        }
        
        print("[FileProviderEnumerator] Returning \(items.count) root items")
        observer.didEnumerate(items)
        observer.finishEnumerating(upTo: nil)
    }
    
    private func enumerateConnectionContainer(observer: NSFileProviderEnumerationObserver) {
        // Parse connection identifier
        let idPrefix = "connection_"
        guard enumeratedItemIdentifier.rawValue.hasPrefix(idPrefix) else {
            print("[FileProviderEnumerator] Invalid identifier format: \(enumeratedItemIdentifier.rawValue)")
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
            print("[FileProviderEnumerator] Connection not found or no password: \(uuidString)")
            observer.didEnumerate([])
            observer.finishEnumerating(upTo: nil)
            return
        }
        
        var remotePath = "/"
        if components.count == 2 {
            let pathComponent = String(components[1])
            remotePath = pathComponent.replacingOccurrences(of: "__SLASH__", with: "/")
        }
        
        print("[FileProviderEnumerator] Enumerating path: \(remotePath) for connection: \(connection.name)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let sftp = try SFTPService.shared.connect(to: connection, password: password)
                defer { sftp.disconnect() }
                
                let entries = try SFTPService.shared.listDirectory(sftp: sftp, path: remotePath)
                print("[FileProviderEnumerator] Found \(entries.count) entries in \(remotePath)")
                
                let items: [NSFileProviderItem] = entries.map { entry in
                    let fullPath = (remotePath as NSString).appendingPathComponent(entry.filename)
                    let encodedPath = fullPath.replacingOccurrences(of: "/", with: "__SLASH__")
                    let itemIdentifier = NSFileProviderItemIdentifier("connection_\(connection.id.uuidString)_\(encodedPath)")
                    
                    return FileProviderItem(
                        itemIdentifier: itemIdentifier,
                        parentItemIdentifier: self.enumeratedItemIdentifier,
                        sftpItem: entry
                    )
                }
                
                DispatchQueue.main.async {
                    print("[FileProviderEnumerator] Returning \(items.count) items for \(remotePath)")
                    observer.didEnumerate(items)
                    observer.finishEnumerating(upTo: nil)
                }
                
            } catch {
                print("[FileProviderEnumerator] Error enumerating \(remotePath): \(error)")
                DispatchQueue.main.async {
                    observer.didEnumerate([])
                    observer.finishEnumerating(upTo: nil)
                }
            }
        }
    }
    
    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        print("[FileProviderEnumerator] enumerateChanges called")
        let newAnchor = NSFileProviderSyncAnchor(Data())
        observer.finishEnumeratingChanges(upTo: newAnchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let anchor = NSFileProviderSyncAnchor(Data())
        completionHandler(anchor)
    }
}

// MARK: - Connection Root Item

class ConnectionRootItem: NSObject, NSFileProviderItem {
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let connection: SFTPConnection
    
    init(itemIdentifier: NSFileProviderItemIdentifier, parentItemIdentifier: NSFileProviderItemIdentifier, connection: SFTPConnection) {
        self.itemIdentifier = itemIdentifier
        self.parentItemIdentifier = parentItemIdentifier
        self.connection = connection
    }
    
    var filename: String { connection.name }
    var typeIdentifier: String { UTType.folder.identifier }
    var contentType: UTType { .folder }
    
    var capabilities: NSFileProviderItemCapabilities {
        return [.allowsReading, .allowsContentEnumerating]
    }
    
    var fileSystemFlags: NSFileProviderFileSystemFlags {
        return [.userReadable]
    }
}
import FileProvider
import Foundation
import mft

class SFTPFileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let domain: NSFileProviderDomain
    private var connection: SFTPConnection?
    private var sftp: MFTSftpConnection?
    private let downloadManager = DownloadManager()
    private var lastSyncAnchor: NSFileProviderSyncAnchor?
    
    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
        setupConnection()
        downloadManager.cleanupOrphanedDownloads()
        loadLastSyncAnchor()
        
        NSLog("SFTPFiles: FileProviderExtension initialized for domain: \(domain.displayName)")
    }
    
    private func setupConnection() {
        let connections = SFTPConnectionStore.loadConnections()
        connection = connections.first { $0.id.uuidString == domain.identifier.rawValue }
        
        if let conn = connection {
            NSLog("SFTPFiles: Setup connection - Host: \(conn.host), Remote Path: '\(conn.remotePath)'")
        } else {
            NSLog("SFTPFiles: No connection found for domain: \(domain.identifier.rawValue)")
        }
    }
    
    private func loadLastSyncAnchor() {
        let defaults = UserDefaults(suiteName: "group.mansivisuals.SFTPFiles")
        let key = "lastSyncAnchor_\(domain.identifier.rawValue)"
        
        if let data = defaults?.data(forKey: key) {
            lastSyncAnchor = NSFileProviderSyncAnchor(data)
        }
    }
    
    private func saveLastSyncAnchor(_ anchor: NSFileProviderSyncAnchor) {
        let defaults = UserDefaults(suiteName: "group.mansivisuals.SFTPFiles")
        let key = "lastSyncAnchor_\(domain.identifier.rawValue)"
        defaults?.set(anchor.rawValue, forKey: key)
        defaults?.synchronize()
        lastSyncAnchor = anchor
    }
    
    private func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "/" : "/\(trimmed)"
    }
    
    private func combinePaths(_ basePath: String, _ subPath: String) -> String {
        let normalizedBase = normalizedPath(basePath)
        let normalizedSub = subPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        if normalizedBase == "/" {
            return "/\(normalizedSub)"
        } else {
            return "\(normalizedBase)/\(normalizedSub)"
        }
    }
    
    // MARK: - Remote Path Handling
    private func getEffectiveRemotePath() -> String {
        return connection?.remotePath.isEmpty == false ? connection!.remotePath : "/"
    }
    
    private func pathRelativeToRemote(_ path: String) -> String {
        let remotePath = getEffectiveRemotePath()
        if remotePath == "/" {
            return path
        }
        
        // If path starts with remote path, return the relative part
        if path.hasPrefix(remotePath) {
            let relativePath = String(path.dropFirst(remotePath.count))
            return relativePath.isEmpty ? "/" : relativePath
        }
        
        // Otherwise, combine them
        return combinePaths(remotePath, path)
    }
    
    private func absolutePathFromRelative(_ relativePath: String) -> String {
        let remotePath = getEffectiveRemotePath()
        if remotePath == "/" {
            return relativePath
        }
        return combinePaths(remotePath, relativePath)
    }
    
    private func performWithRetry<T>(operation: @escaping () throws -> T, retries: Int = 2) throws -> T {
        var lastError: Error?
        
        for attempt in 0...retries {
            do {
                if attempt > 0 {
                    NSLog("SFTPFiles: Retry attempt \(attempt)")
                    sftp?.disconnect()
                    sftp = nil
                    Thread.sleep(forTimeInterval: 1.0) // Wait before retry
                }
                
                try ensureConnection()
                return try operation()
            } catch {
                lastError = error
                NSLog("SFTPFiles: Operation failed (attempt \(attempt + 1)): \(error.localizedDescription)")
                
                if attempt == retries {
                    break
                }
            }
        }
        
        throw lastError ?? NSFileProviderError(.serverUnreachable)
    }
    
    func invalidate() {
        NSLog("SFTPFiles: FileProviderExtension invalidated")
        sftp?.disconnect()
        sftp = nil
    }
    
    private func ensureConnection() throws {
        guard let connection = connection else {
            NSLog("SFTPFiles: No connection available")
            throw NSFileProviderError(.notAuthenticated)
        }
        
        // Always create fresh connection for reliability
        if sftp != nil {
            sftp?.disconnect()
            sftp = nil
        }
        
        sftp = MFTSftpConnection(
            hostname: connection.host,
            port: connection.port ?? 22,
            username: connection.username,
            password: connection.password
        )
        
        do {
            NSLog("SFTPFiles: Connecting to \(connection.host):\(connection.port ?? 22)")
            try sftp!.connect()
            try sftp!.authenticate()
            NSLog("SFTPFiles: Connection established successfully")
        } catch {
            NSLog("SFTPFiles: Connection failed: \(error.localizedDescription)")
            sftp?.disconnect()
            sftp = nil
            throw error
        }
    }
    
    // MARK: - Enumeration with Proper Remote Path Support
    
    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        guard let connection = connection else {
            NSLog("SFTPFiles: Cannot create enumerator - no connection")
            throw NSFileProviderError(.notAuthenticated)
        }
        
        NSLog("SFTPFiles: Creating enumerator for container: \(containerItemIdentifier.rawValue)")
        
        return SFTPFileProviderEnumerator(
            containerIdentifier: containerItemIdentifier,
            connection: connection
        )
    }
    
    // MARK: - Item Retrieval
    
    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        
        NSLog("SFTPFiles: Getting item for identifier: \(identifier.rawValue)")
        
        if identifier == .rootContainer {
            let remotePath = getEffectiveRemotePath()
            let rootItem = SFTPFileProviderItem(rootPath: remotePath)
            NSLog("SFTPFiles: Returning root item with path: '\(remotePath)'")
            completionHandler(rootItem, nil)
            progress.completedUnitCount = 1
            return progress
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.performWithRetry {
                    let absolutePath = identifier.rawValue
                    NSLog("SFTPFiles: Getting file info for absolute path: '\(absolutePath)'")
                    let fileInfo = try self.sftp!.infoForFile(atPath: absolutePath)
                    let item = SFTPFileProviderItem(
                        fileInfo: fileInfo,
                        path: absolutePath,
                        downloadManager: self.downloadManager
                    )
                    DispatchQueue.main.async {
                        completionHandler(item, nil)
                        progress.completedUnitCount = 1
                    }
                }
            } catch {
                NSLog("SFTPFiles: Error getting item info for \(identifier.rawValue): \(error.localizedDescription)")
                DispatchQueue.main.async {
                    // Use the correct error constructor for missing items
                    let providerError = NSError.fileProviderErrorForNonExistentItem(withIdentifier: identifier)
                    completionHandler(nil, providerError)
                    progress.completedUnitCount = 1
                }
            }
        }
        return progress
    }
    
    // MARK: - File Operations with Proper Remote Path Handling
    
    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version: NSFileProviderItemVersion?, request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 100)
        
        NSLog("SFTPFiles: fetchContents for path: \(itemIdentifier.rawValue)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.performWithRetry {
                    let absolutePath = itemIdentifier.rawValue
                    let fileInfo = try self.sftp!.infoForFile(atPath: absolutePath)
                    let serverFilename = fileInfo.filename
                    let cleanFilename = serverFilename.components(separatedBy: "/").last ?? serverFilename
                    
                    NSLog("SFTPFiles: Downloading file: '\(cleanFilename)' from '\(absolutePath)'")
                    
                    let downloadID = UUID().uuidString
                    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SFTPDownloads").appendingPathComponent(downloadID)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
                    
                    let tempURL = tempDir.appendingPathComponent(cleanFilename)
                    let outputStream = OutputStream(url: tempURL, append: false)!
                    
                    try self.sftp!.contents(atPath: absolutePath, toStream: outputStream, fromPosition: 0) { downloaded, total in
                        DispatchQueue.main.async {
                            if total > 0 {
                                progress.completedUnitCount = Int64((Double(downloaded) / Double(total)) * 100)
                            }
                        }
                        return !progress.isCancelled
                    }
                    
                    let item = SFTPFileProviderItem(
                        fileInfo: fileInfo, 
                        path: absolutePath,
                        downloadManager: self.downloadManager
                    )
                    
                    self.downloadManager.registerDownload(for: itemIdentifier, at: tempURL)
                    
                    DispatchQueue.main.async {
                        progress.completedUnitCount = 100
                        completionHandler(tempURL, item, nil)
                    }
                }
            } catch {
                NSLog("SFTPFiles: fetchContents error for \(itemIdentifier.rawValue): \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completionHandler(nil, nil, NSFileProviderError(.serverUnreachable))
                }
            }
        }
        
        return progress
    }
    
    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents: URL?, options: NSFileProviderCreateItemOptions, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 100)
        
        // Determine the parent path
        let parentPath: String
        if itemTemplate.parentItemIdentifier == .rootContainer {
            parentPath = getEffectiveRemotePath()
        } else {
            parentPath = itemTemplate.parentItemIdentifier.rawValue
        }
        
        let newPath = combinePaths(parentPath, itemTemplate.filename)
        
        NSLog("SFTPFiles: Creating item - Parent: '\(parentPath)', Filename: '\(itemTemplate.filename)', Full path: '\(newPath)'")
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.performWithRetry {
                    if itemTemplate.contentType == .folder {
                        NSLog("SFTPFiles: Creating directory at: '\(newPath)'")
                        try self.sftp!.createDirectory(atPath: newPath)
                        progress.completedUnitCount = 100
                    } else if let contents = contents {
                        NSLog("SFTPFiles: Uploading file to: '\(newPath)'")
                        
                        let attributes = try FileManager.default.attributesOfItem(atPath: contents.path)
                        let fileSize = attributes[.size] as? Int64 ?? 0
                        progress.totalUnitCount = max(fileSize, 100)
                        
                        var uploadedBytes: Int64 = 0
                        let inputStream = InputStream(url: contents)!
                        
                        try self.sftp!.write(stream: inputStream, toFileAtPath: newPath, append: false) { uploaded in
                            uploadedBytes = Int64(uploaded)
                            DispatchQueue.main.async {
                                progress.completedUnitCount = uploadedBytes
                            }
                            return !progress.isCancelled
                        }
                        
                        NSLog("SFTPFiles: Upload completed - \(uploadedBytes) bytes")
                    }
                    
                    let fileInfo = try self.sftp!.infoForFile(atPath: newPath)
                    let item = SFTPFileProviderItem(
                        fileInfo: fileInfo, 
                        path: newPath,
                        downloadManager: self.downloadManager
                    )
                    
                    NSLog("SFTPFiles: Item created successfully - Name: '\(item.filename)', Path: '\(newPath)'")
                    
                    DispatchQueue.main.async {
                        progress.completedUnitCount = progress.totalUnitCount
                        completionHandler(item, [], false, nil)
                        
                        // Signal that the parent container has changed
                        self.signalEnumeratorForContainer(parentPath)
                    }
                }
            } catch {
                NSLog("SFTPFiles: Create item error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completionHandler(nil, [], false, NSFileProviderError(.serverUnreachable))
                }
            }
        }
        
        return progress
    }
    
    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion: NSFileProviderItemVersion, options: NSFileProviderDeleteItemOptions, request: NSFileProviderRequest, completionHandler: @escaping (Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        
        NSLog("SFTPFiles: Deleting item: \(identifier.rawValue)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.performWithRetry {
                    let absolutePath = identifier.rawValue
                    let fileInfo = try self.sftp!.infoForFile(atPath: absolutePath)
                    let parentPath = (absolutePath as NSString).deletingLastPathComponent
                    
                    if fileInfo.isDirectory {
                        try self.sftp!.removeDirectory(atPath: absolutePath)
                    } else {
                        try self.sftp!.removeFile(atPath: absolutePath)
                    }
                    
                    self.downloadManager.removeDownload(for: identifier)
                    
                    DispatchQueue.main.async {
                        progress.completedUnitCount = 1
                        completionHandler(nil)
                        
                        // Signal that the parent container has changed
                        self.signalEnumeratorForContainer(parentPath)
                    }
                }
            } catch {
                NSLog("SFTPFiles: Delete item error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    progress.completedUnitCount = 1
                    completionHandler(NSFileProviderError(.serverUnreachable))
                }
            }
        }
        
        return progress
    }
    
    func modifyItem(_ item: NSFileProviderItem, baseVersion: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields, contents: URL?, options: NSFileProviderModifyItemOptions, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 100)
        let originalPath = item.itemIdentifier.rawValue
        
        NSLog("SFTPFiles: Modifying item - Original path: '\(originalPath)', Changed fields: \(changedFields)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.performWithRetry {
                    var finalPath = originalPath
                    var itemMoved = false
                    if changedFields.contains(.contents), let contents = contents {
                        NSLog("SFTPFiles: Updating file contents at: '\(originalPath)'")
                        let attributes = try FileManager.default.attributesOfItem(atPath: contents.path)
                        let fileSize = attributes[.size] as? Int64 ?? 0
                        progress.totalUnitCount = fileSize + 10
                        var uploadedBytes: Int64 = 0
                        let inputStream = InputStream(url: contents)!
                        try self.sftp!.write(stream: inputStream, toFileAtPath: originalPath, append: false) { uploaded in
                            uploadedBytes = Int64(uploaded)
                            DispatchQueue.main.async {
                                progress.completedUnitCount = uploadedBytes
                            }
                            return !progress.isCancelled
                        }
                        NSLog("SFTPFiles: Content update completed - \(uploadedBytes) bytes")
                    }
                    if changedFields.contains(.filename) || changedFields.contains(.parentItemIdentifier) {
                        let newParentPath: String
                        if item.parentItemIdentifier == .rootContainer {
                            newParentPath = self.getEffectiveRemotePath()
                        } else {
                            newParentPath = item.parentItemIdentifier.rawValue
                        }
                        let newPath = self.combinePaths(newParentPath, item.filename)
                        NSLog("SFTPFiles: Moving/renaming - From: '\(originalPath)' To: '\(newPath)'")
                        if newPath != originalPath {
                            try self.sftp!.moveItem(atPath: originalPath, toPath: newPath)
                            finalPath = newPath
                            itemMoved = true
                            self.downloadManager.updatePath(from: NSFileProviderItemIdentifier(originalPath), 
                                                           to: NSFileProviderItemIdentifier(finalPath))
                            // Signal both old and new parent containers
                            let oldParentPath = (originalPath as NSString).deletingLastPathComponent
                            self.signalEnumeratorForContainer(oldParentPath)
                            self.signalEnumeratorForContainer(newParentPath)
                            NSLog("SFTPFiles: Move/rename completed successfully")
                        }
                    }
                    let fileInfo = try self.sftp!.infoForFile(atPath: finalPath)
                    let updatedItem = SFTPFileProviderItem(
                        fileInfo: fileInfo,
                        path: finalPath,
                        downloadManager: self.downloadManager
                    )
                    NSLog("SFTPFiles: Modify completed - Final path: '\(finalPath)', Filename: '\(updatedItem.filename)'")
                    DispatchQueue.main.async {
                        progress.completedUnitCount = progress.totalUnitCount
                        completionHandler(updatedItem, [], itemMoved, nil)
                    }
                }
            } catch {
                NSLog("SFTPFiles: Modify item error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    // Use the correct error constructor for missing items
                    let providerError = NSError.fileProviderErrorForNonExistentItem(withIdentifier: item.itemIdentifier)
                    completionHandler(nil, [], false, providerError)
                }
            }
        }
        return progress
    }
    
    // MARK: - Download Management
    
    func evictItem(identifier: NSFileProviderItemIdentifier, completionHandler: @escaping (Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        
        NSLog("SFTPFiles: Evicting item: \(identifier.rawValue)")
        downloadManager.removeDownload(for: identifier)
        
        DispatchQueue.main.async {
            progress.completedUnitCount = 1
            completionHandler(nil)
        }
        
        return progress
    }
    
    // MARK: - Sync Support
    
    private func signalEnumeratorForContainer(_ containerPath: String) {
        let containerIdentifier: NSFileProviderItemIdentifier
        
        let remotePath = getEffectiveRemotePath()
        if containerPath.isEmpty || containerPath == "/" || containerPath == remotePath {
            containerIdentifier = .rootContainer
        } else {
            containerIdentifier = NSFileProviderItemIdentifier(containerPath)
        }
        
        NSLog("SFTPFiles: Signaling enumerator for container: \(containerPath) (identifier: \(containerIdentifier.rawValue))")
        
        // Use the domain directly since we already have it
        let manager = NSFileProviderManager(for: domain)
        
        manager?.signalEnumerator(for: containerIdentifier) { error in
            if let error = error {
                NSLog("SFTPFiles: Failed to signal enumerator for container \(containerPath): \(error.localizedDescription)")
            } else {
                NSLog("SFTPFiles: Successfully signaled enumerator for container: \(containerPath)")
            }
        }
    }
    
    // MARK: - Public sync methods for polling manager
    
    func triggerSync() {
        NSLog("SFTPFiles: Sync triggered by polling manager")
        
        // Signal root container
        signalEnumeratorForContainer(getEffectiveRemotePath())
        
        // Update sync anchor
        let newAnchor = NSFileProviderSyncAnchor("sync_\(Date().timeIntervalSince1970)".data(using: .utf8)!)
        saveLastSyncAnchor(newAnchor)
    }
    
    // MARK: - Material Change Notifications
    
    func materializedItemsDidChange(completionHandler: @escaping () -> Void) {
        NSLog("SFTPFiles: Materialized items changed")
        completionHandler()
    }
    
    func pendingItemsDidChange(completionHandler: @escaping () -> Void) {
        NSLog("SFTPFiles: Pending items changed")
        completionHandler()
    }
}

// MARK: - Download Manager (unchanged)

class DownloadManager {
    private var downloads: [NSFileProviderItemIdentifier: URL] = [:]
    private let queue = DispatchQueue(label: "download.manager", attributes: .concurrent)
    
    func registerDownload(for identifier: NSFileProviderItemIdentifier, at url: URL) {
        queue.async(flags: .barrier) {
            self.downloads[identifier] = url
            NSLog("SFTPFiles: Registered download for \(identifier.rawValue) at \(url.path)")
        }
    }
    
    func removeDownload(for identifier: NSFileProviderItemIdentifier) {
        queue.async(flags: .barrier) {
            if let url = self.downloads[identifier] {
                let downloadDir = url.deletingLastPathComponent()
                do {
                    try FileManager.default.removeItem(at: downloadDir)
                    NSLog("SFTPFiles: Removed download directory for \(identifier.rawValue)")
                } catch {
                    NSLog("SFTPFiles: Failed to remove download directory: \(error.localizedDescription)")
                }
                self.downloads.removeValue(forKey: identifier)
            }
        }
    }
    
    func updatePath(from oldIdentifier: NSFileProviderItemIdentifier, to newIdentifier: NSFileProviderItemIdentifier) {
        queue.async(flags: .barrier) {
            if let url = self.downloads[oldIdentifier] {
                self.downloads[newIdentifier] = url
                self.downloads.removeValue(forKey: oldIdentifier)
                NSLog("SFTPFiles: Updated download path from \(oldIdentifier.rawValue) to \(newIdentifier.rawValue)")
            }
        }
    }
    
    func isDownloaded(identifier: NSFileProviderItemIdentifier) -> Bool {
        return queue.sync {
            if let url = downloads[identifier] {
                return FileManager.default.fileExists(atPath: url.path)
            }
            return false
        }
    }
    
    func downloadURL(for identifier: NSFileProviderItemIdentifier) -> URL? {
        return queue.sync {
            downloads[identifier]
        }
    }
    
    func cleanupOrphanedDownloads() {
        queue.async(flags: .barrier) {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SFTPDownloads")
            do {
                try FileManager.default.removeItem(at: tempDir)
                NSLog("SFTPFiles: Cleaned up orphaned downloads")
            } catch {
                // Directory might not exist, which is fine
                NSLog("SFTPFiles: No orphaned downloads to clean up")
            }
        }
    }
}
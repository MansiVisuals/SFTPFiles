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
    }
    
    private func setupConnection() {
        let connections = SFTPConnectionStore.loadConnections()
        connection = connections.first { $0.id.uuidString == domain.identifier.rawValue }
        
        if let conn = connection {
            NSLog("SFTPFiles: Setup connection - Host: \(conn.host), Remote Path: '\(conn.remotePath)'")
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
    
    private func performWithRetry<T>(operation: @escaping () throws -> T, retries: Int = 2) throws -> T {
        var lastError: Error?
        
        for attempt in 0...retries {
            do {
                if attempt > 0 {
                    NSLog("SFTPFiles: Retry attempt \(attempt)")
                    sftp?.disconnect()
                    sftp = nil
                }
                
                try ensureConnection()
                return try operation()
            } catch {
                lastError = error
                NSLog("SFTPFiles: Operation failed (attempt \(attempt + 1)): \(error)")
                
                if attempt == retries {
                    break
                }
                
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        
        throw lastError ?? NSFileProviderError(.serverUnreachable)
    }
    
    func invalidate() {
        sftp?.disconnect()
        sftp = nil
    }
    
    private func ensureConnection() throws {
        guard let connection = connection else {
            throw NSFileProviderError(.notAuthenticated)
        }
        
        if let sftp = sftp, !sftp.connected {
            NSLog("SFTPFiles: Connection lost, attempting to reconnect...")
            sftp.disconnect()
            self.sftp = nil
        }
        
        guard sftp == nil || !sftp!.connected else { return }
        
        sftp?.disconnect()
        sftp = MFTSftpConnection(
            hostname: connection.host,
            port: connection.port ?? 22,
            username: connection.username,
            password: connection.password
        )
        
        do {
            try sftp!.connect()
            try sftp!.authenticate()
            NSLog("SFTPFiles: Connection established successfully")
        } catch {
            NSLog("SFTPFiles: Connection failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Enumeration with Sync Support
    
    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        guard let connection = connection else {
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
        
        if identifier == .rootContainer {
            let remotePath = connection?.remotePath ?? "/"
            let rootItem = SFTPFileProviderItem(rootPath: remotePath)
            NSLog("SFTPFiles: Returning root item with path: '\(remotePath)'")
            completionHandler(rootItem, nil)
            progress.completedUnitCount = 1
            return progress
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.ensureConnection()
                NSLog("SFTPFiles: Getting item info for: '\(identifier.rawValue)'")
                
                let fileInfo = try self.sftp!.infoForFile(atPath: identifier.rawValue)
                let item = SFTPFileProviderItem(
                    fileInfo: fileInfo, 
                    path: identifier.rawValue,
                    downloadManager: self.downloadManager
                )
                
                DispatchQueue.main.async {
                    completionHandler(item, nil)
                    progress.completedUnitCount = 1
                }
            } catch {
                NSLog("SFTPFiles: Error getting item info: \(error)")
                DispatchQueue.main.async {
                    completionHandler(nil, NSFileProviderError(.noSuchItem))
                    progress.completedUnitCount = 1
                }
            }
        }
        
        return progress
    }
    
    // MARK: - File Operations
    
    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version: NSFileProviderItemVersion?, request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 100)
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.ensureConnection()
                
                NSLog("SFTPFiles: fetchContents for path: \(itemIdentifier.rawValue)")
                
                let fileInfo = try self.sftp!.infoForFile(atPath: itemIdentifier.rawValue)
                let serverFilename = fileInfo.filename
                let cleanFilename = serverFilename.components(separatedBy: "/").last ?? serverFilename
                
                NSLog("SFTPFiles: Server filename: '\(serverFilename)'")
                NSLog("SFTPFiles: Clean filename: '\(cleanFilename)'")
                NSLog("SFTPFiles: Full server path: '\(itemIdentifier.rawValue)'")
                
                let downloadID = UUID().uuidString
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SFTPDownloads").appendingPathComponent(downloadID)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
                
                let tempURL = tempDir.appendingPathComponent(cleanFilename)
                
                NSLog("SFTPFiles: Creating temp file at: \(tempURL.path)")
                NSLog("SFTPFiles: Temp file name: \(tempURL.lastPathComponent)")
                
                let outputStream = OutputStream(url: tempURL, append: false)!
                
                try self.sftp!.contents(atPath: itemIdentifier.rawValue, toStream: outputStream, fromPosition: 0) { downloaded, total in
                    DispatchQueue.main.async {
                        if total > 0 {
                            progress.completedUnitCount = Int64((Double(downloaded) / Double(total)) * 100)
                        }
                    }
                    return !progress.isCancelled
                }
                
                let item = SFTPFileProviderItem(
                    fileInfo: fileInfo, 
                    path: itemIdentifier.rawValue,
                    downloadManager: self.downloadManager
                )
                
                NSLog("SFTPFiles: Item filename property: '\(item.filename)'")
                
                self.downloadManager.registerDownload(for: itemIdentifier, at: tempURL)
                
                DispatchQueue.main.async {
                    progress.completedUnitCount = 100
                    completionHandler(tempURL, item, nil)
                }
            } catch {
                NSLog("SFTPFiles: fetchContents error: \(error)")
                DispatchQueue.main.async {
                    completionHandler(nil, nil, NSFileProviderError(.serverUnreachable))
                }
            }
        }
        
        return progress
    }
    
    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents: URL?, options: NSFileProviderCreateItemOptions, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 100)
        
        let parentPath: String
        if itemTemplate.parentItemIdentifier == .rootContainer {
            parentPath = connection?.remotePath ?? "/"
        } else {
            parentPath = itemTemplate.parentItemIdentifier.rawValue
        }
        
        let newPath = combinePaths(parentPath, itemTemplate.filename)
        
        NSLog("SFTPFiles: Creating item - Parent: '\(parentPath)', Filename: '\(itemTemplate.filename)', Full path: '\(newPath)'")
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.ensureConnection()
                
                if itemTemplate.contentType == .folder {
                    NSLog("SFTPFiles: Creating directory at: '\(newPath)'")
                    try self.performWithRetry {
                        try self.sftp!.createDirectory(atPath: newPath)
                    }
                    progress.completedUnitCount = 100
                } else if let contents = contents {
                    NSLog("SFTPFiles: Uploading file to: '\(newPath)'")
                    
                    let attributes = try FileManager.default.attributesOfItem(atPath: contents.path)
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    progress.totalUnitCount = max(fileSize, 100)
                    
                    var uploadedBytes: Int64 = 0
                    
                    try self.performWithRetry {
                        let inputStream = InputStream(url: contents)!
                        try self.sftp!.write(stream: inputStream, toFileAtPath: newPath, append: false) { uploaded in
                            uploadedBytes = Int64(uploaded)
                            DispatchQueue.main.async {
                                progress.completedUnitCount = uploadedBytes
                            }
                            return !progress.isCancelled
                        }
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
                
                // Signal that the container has changed for sync
                self.signalEnumeratorForContainer(parentPath)
                
                DispatchQueue.main.async {
                    progress.completedUnitCount = progress.totalUnitCount
                    completionHandler(item, [], false, nil)
                }
            } catch {
                NSLog("SFTPFiles: Create item error: \(error)")
                DispatchQueue.main.async {
                    completionHandler(nil, [], false, NSFileProviderError(.serverUnreachable))
                }
            }
        }
        
        return progress
    }
    
    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion: NSFileProviderItemVersion, options: NSFileProviderDeleteItemOptions, request: NSFileProviderRequest, completionHandler: @escaping (Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.ensureConnection()
                
                let fileInfo = try self.sftp!.infoForFile(atPath: identifier.rawValue)
                let parentPath = (identifier.rawValue as NSString).deletingLastPathComponent
                
                if fileInfo.isDirectory {
                    try self.sftp!.removeDirectory(atPath: identifier.rawValue)
                } else {
                    try self.sftp!.removeFile(atPath: identifier.rawValue)
                }
                
                self.downloadManager.removeDownload(for: identifier)
                
                // Signal that the parent container has changed
                self.signalEnumeratorForContainer(parentPath)
                
                DispatchQueue.main.async {
                    progress.completedUnitCount = 1
                    completionHandler(nil)
                }
            } catch {
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
                try self.ensureConnection()
                var finalPath = originalPath
                var itemMoved = false
                var progressCompleted: Int64 = 0
                
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
                    
                    progressCompleted = uploadedBytes
                    NSLog("SFTPFiles: Content update completed - \(uploadedBytes) bytes")
                }
                
                if changedFields.contains(.filename) || changedFields.contains(.parentItemIdentifier) {
                    let newParentPath: String
                    if item.parentItemIdentifier == .rootContainer {
                        newParentPath = self.connection?.remotePath ?? "/"
                    } else {
                        newParentPath = item.parentItemIdentifier.rawValue
                    }
                    
                    let newPath = self.combinePaths(newParentPath, item.filename)
                    
                    NSLog("SFTPFiles: Moving/renaming - From: '\(originalPath)' To: '\(newPath)'")
                    
                    if newPath != originalPath {
                        let _ = try self.sftp!.infoForFile(atPath: originalPath)
                        
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
            } catch {
                NSLog("SFTPFiles: Modify item error: \(error)")
                DispatchQueue.main.async {
                    let providerError: NSFileProviderError
                    if error.localizedDescription.contains("not found") || error.localizedDescription.contains("No such file") {
                        providerError = NSFileProviderError(.noSuchItem)
                    } else if error.localizedDescription.contains("permission") || error.localizedDescription.contains("denied") {
                        providerError = NSFileProviderError(.insufficientQuota)
                    } else {
                        providerError = NSFileProviderError(.serverUnreachable)
                    }
                    completionHandler(nil, [], false, providerError)
                }
            }
        }
        
        return progress
    }
    
    // MARK: - Download Management
    
    func evictItem(identifier: NSFileProviderItemIdentifier, completionHandler: @escaping (Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        
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
    
    if containerPath.isEmpty || containerPath == "/" || containerPath == connection?.remotePath {
        containerIdentifier = .rootContainer
    } else {
        containerIdentifier = NSFileProviderItemIdentifier(containerPath)
    }
    
    // Use the domain directly since we already have it
    NSFileProviderManager(for: domain)?.signalEnumerator(for: containerIdentifier) { error in
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
        signalEnumeratorForContainer(connection?.remotePath ?? "/")
        
        // Update sync anchor
        let newAnchor = NSFileProviderSyncAnchor("sync_\(Date().timeIntervalSince1970)".data(using: .utf8)!)
        saveLastSyncAnchor(newAnchor)
    }
}

// MARK: - Download Manager

class DownloadManager {
    private var downloads: [NSFileProviderItemIdentifier: URL] = [:]
    private let queue = DispatchQueue(label: "download.manager", attributes: .concurrent)
    
    func registerDownload(for identifier: NSFileProviderItemIdentifier, at url: URL) {
        queue.async(flags: .barrier) {
            self.downloads[identifier] = url
        }
    }
    
    func removeDownload(for identifier: NSFileProviderItemIdentifier) {
        queue.async(flags: .barrier) {
            if let url = self.downloads[identifier] {
                let downloadDir = url.deletingLastPathComponent()
                try? FileManager.default.removeItem(at: downloadDir)
                self.downloads.removeValue(forKey: identifier)
            }
        }
    }
    
    func updatePath(from oldIdentifier: NSFileProviderItemIdentifier, to newIdentifier: NSFileProviderItemIdentifier) {
        queue.async(flags: .barrier) {
            if let url = self.downloads[oldIdentifier] {
                self.downloads[newIdentifier] = url
                self.downloads.removeValue(forKey: oldIdentifier)
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
            try? FileManager.default.removeItem(at: tempDir)
        }
    }
}
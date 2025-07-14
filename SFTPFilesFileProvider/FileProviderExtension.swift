import FileProvider
import Foundation
import mft

class SFTPFileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let domain: NSFileProviderDomain
    private var connection: SFTPConnection?
    private var sftp: MFTSftpConnection?
    private let downloadManager = DownloadManager()
    
    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
        setupConnection()
        downloadManager.cleanupOrphanedDownloads()
    }
    
    private func setupConnection() {
        let connections = SFTPConnectionStore.loadConnections()
        connection = connections.first { $0.id.uuidString == domain.identifier.rawValue }
    }
    
    func invalidate() {
        sftp?.disconnect()
        sftp = nil
    }
    
    private func ensureConnection() throws {
        guard let connection = connection else {
            throw NSFileProviderError(.notAuthenticated)
        }
        
        guard sftp == nil || !sftp!.connected else { return }
        
        sftp?.disconnect()
        sftp = MFTSftpConnection(
            hostname: connection.host,
            port: connection.port ?? 22,
            username: connection.username,
            password: connection.password
        )
        
        try sftp!.connect()
        try sftp!.authenticate()
    }
    
    // MARK: - Enumeration
    
    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        guard let connection = connection else {
            throw NSFileProviderError(.notAuthenticated)
        }
        
        return SFTPFileProviderEnumerator(
            containerIdentifier: containerItemIdentifier,
            connection: connection
        )
    }
    
    // MARK: - Item Retrieval
    
    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        
        if identifier == .rootContainer {
            let rootItem = SFTPFileProviderItem(rootPath: connection?.remotePath ?? "/")
            completionHandler(rootItem, nil)
            progress.completedUnitCount = 1
            return progress
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.ensureConnection()
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
                
                // Debug logging
                NSLog("SFTPFiles: fetchContents for path: \(itemIdentifier.rawValue)")
                
                // Get the file info first to get the actual filename
                let fileInfo = try self.sftp!.infoForFile(atPath: itemIdentifier.rawValue)
                let filename = fileInfo.filename
                
                // Debug logging
                NSLog("SFTPFiles: Server filename: '\(filename)'")
                NSLog("SFTPFiles: Full path: '\(itemIdentifier.rawValue)'")
                
                // Create a unique temporary directory for this download to avoid conflicts
                let downloadID = UUID().uuidString
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SFTPDownloads").appendingPathComponent(downloadID)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
                
                let tempURL = tempDir.appendingPathComponent(filename)
                
                NSLog("SFTPFiles: Creating temp file at: \(tempURL.path)")
                
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
                
                // Register download with manager
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
        
        let parentPath = itemTemplate.parentItemIdentifier == .rootContainer ? 
            (connection?.remotePath ?? "/") : itemTemplate.parentItemIdentifier.rawValue
        let newPath = parentPath == "/" ? "/\(itemTemplate.filename)" : "\(parentPath)/\(itemTemplate.filename)"
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.ensureConnection()
                
                if itemTemplate.contentType == .folder {
                    try self.sftp!.createDirectory(atPath: newPath)
                    progress.completedUnitCount = 100
                } else if let contents = contents {
                    let fileSize = try FileManager.default.attributesOfItem(atPath: contents.path)[.size] as? Int64 ?? 0
                    progress.totalUnitCount = max(fileSize, 1)
                    
                    let inputStream = InputStream(url: contents)!
                    try self.sftp!.write(stream: inputStream, toFileAtPath: newPath, append: false) { uploaded in
                        DispatchQueue.main.async {
                            progress.completedUnitCount = Int64(uploaded)
                        }
                        return !progress.isCancelled
                    }
                }
                
                let fileInfo = try self.sftp!.infoForFile(atPath: newPath)
                let item = SFTPFileProviderItem(
                    fileInfo: fileInfo, 
                    path: newPath,
                    downloadManager: self.downloadManager
                )
                
                DispatchQueue.main.async {
                    progress.completedUnitCount = progress.totalUnitCount
                    completionHandler(item, [], false, nil)
                }
            } catch {
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
                if fileInfo.isDirectory {
                    try self.sftp!.removeDirectory(atPath: identifier.rawValue)
                } else {
                    try self.sftp!.removeFile(atPath: identifier.rawValue)
                }
                
                // Clean up any local downloads
                self.downloadManager.removeDownload(for: identifier)
                
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
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.ensureConnection()
                var finalPath = originalPath
                var needsMove = false
                
                // Handle content changes first
                if changedFields.contains(.contents), let contents = contents {
                    let fileSize = try FileManager.default.attributesOfItem(atPath: contents.path)[.size] as? Int64 ?? 0
                    progress.totalUnitCount = max(fileSize + 10, 100) // +10 for move operation if needed
                    
                    let inputStream = InputStream(url: contents)!
                    try self.sftp!.write(stream: inputStream, toFileAtPath: originalPath, append: false) { uploaded in
                        DispatchQueue.main.async {
                            progress.completedUnitCount = Int64(uploaded)
                        }
                        return !progress.isCancelled
                    }
                }
                
                // Handle rename/move
                if changedFields.contains(.filename) || changedFields.contains(.parentItemIdentifier) {
                    needsMove = true
                    let newParentPath = item.parentItemIdentifier == .rootContainer ? 
                        (self.connection?.remotePath ?? "/") : item.parentItemIdentifier.rawValue
                    finalPath = newParentPath == "/" ? "/\(item.filename)" : "\(newParentPath)/\(item.filename)"
                    
                    // Only move if the path actually changed
                    if finalPath != originalPath {
                        try self.sftp!.moveItem(atPath: originalPath, toPath: finalPath)
                        
                        // Update download manager with new path
                        self.downloadManager.updatePath(from: NSFileProviderItemIdentifier(originalPath), 
                                                       to: NSFileProviderItemIdentifier(finalPath))
                    }
                }
                
                // Get updated file info from the final path
                let fileInfo = try self.sftp!.infoForFile(atPath: finalPath)
                let updatedItem = SFTPFileProviderItem(
                    fileInfo: fileInfo, 
                    path: finalPath,
                    downloadManager: self.downloadManager
                )
                
                DispatchQueue.main.async {
                    progress.completedUnitCount = progress.totalUnitCount
                    completionHandler(updatedItem, [], needsMove, nil)
                }
            } catch {
                DispatchQueue.main.async {
                    completionHandler(nil, [], false, NSFileProviderError(.serverUnreachable))
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
                // Remove the entire download directory (including the unique subdirectory)
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
    
    // Clean up orphaned downloads on startup
    func cleanupOrphanedDownloads() {
        queue.async(flags: .barrier) {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SFTPDownloads")
            
            // Remove any existing downloads directory on startup to clean up orphaned files
            try? FileManager.default.removeItem(at: tempDir)
        }
    }
}

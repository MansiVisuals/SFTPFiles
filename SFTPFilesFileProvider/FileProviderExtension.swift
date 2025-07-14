import FileProvider
import Foundation
import mft

class SFTPFileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let domain: NSFileProviderDomain
    private var connection: SFTPConnection?
    private var sftp: MFTSftpConnection?
    
    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
        setupConnection()
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
                let item = SFTPFileProviderItem(fileInfo: fileInfo, path: identifier.rawValue)
                
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
                
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                let outputStream = OutputStream(url: tempURL, append: false)!
                
                try self.sftp!.contents(atPath: itemIdentifier.rawValue, toStream: outputStream, fromPosition: 0) { downloaded, total in
                    DispatchQueue.main.async {
                        progress.completedUnitCount = Int64((Double(downloaded) / Double(total)) * 100)
                    }
                    return !progress.isCancelled
                }
                
                let fileInfo = try self.sftp!.infoForFile(atPath: itemIdentifier.rawValue)
                let item = SFTPFileProviderItem(fileInfo: fileInfo, path: itemIdentifier.rawValue)
                
                DispatchQueue.main.async {
                    progress.completedUnitCount = 100
                    completionHandler(tempURL, item, nil)
                }
            } catch {
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
                } else if let contents = contents {
                    let inputStream = InputStream(url: contents)!
                    try self.sftp!.write(stream: inputStream, toFileAtPath: newPath, append: false) { uploaded in
                        DispatchQueue.main.async {
                            progress.completedUnitCount = Int64(uploaded)
                        }
                        return !progress.isCancelled
                    }
                }
                
                let fileInfo = try self.sftp!.infoForFile(atPath: newPath)
                let item = SFTPFileProviderItem(fileInfo: fileInfo, path: newPath)
                
                DispatchQueue.main.async {
                    progress.completedUnitCount = 100
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
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.ensureConnection()
                
                // Handle content changes
                if changedFields.contains(.contents), let contents = contents {
                    let inputStream = InputStream(url: contents)!
                    try self.sftp!.write(stream: inputStream, toFileAtPath: item.itemIdentifier.rawValue, append: false) { uploaded in
                        DispatchQueue.main.async {
                            progress.completedUnitCount = Int64(uploaded)
                        }
                        return !progress.isCancelled
                    }
                }
                
                // Handle rename/move
                if changedFields.contains(.filename) || changedFields.contains(.parentItemIdentifier) {
                    let newParentPath = item.parentItemIdentifier == .rootContainer ? 
                        (self.connection?.remotePath ?? "/") : item.parentItemIdentifier.rawValue
                    let newPath = newParentPath == "/" ? "/\(item.filename)" : "\(newParentPath)/\(item.filename)"
                    
                    try self.sftp!.moveItem(atPath: item.itemIdentifier.rawValue, toPath: newPath)
                }
                
                let fileInfo = try self.sftp!.infoForFile(atPath: item.itemIdentifier.rawValue)
                let updatedItem = SFTPFileProviderItem(fileInfo: fileInfo, path: item.itemIdentifier.rawValue)
                
                DispatchQueue.main.async {
                    progress.completedUnitCount = 100
                    completionHandler(updatedItem, [], false, nil)
                }
            } catch {
                DispatchQueue.main.async {
                    completionHandler(nil, [], false, NSFileProviderError(.serverUnreachable))
                }
            }
        }
        
        return progress
    }
}
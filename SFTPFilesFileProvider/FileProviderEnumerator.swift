import FileProvider
import Foundation
import mft

class SFTPFileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    private let containerIdentifier: NSFileProviderItemIdentifier
    private let connection: SFTPConnection
    private var sftp: MFTSftpConnection?
    
    init(containerIdentifier: NSFileProviderItemIdentifier, connection: SFTPConnection) {
        self.containerIdentifier = containerIdentifier
        self.connection = connection
        super.init()
    }
    
    func invalidate() {
        sftp?.disconnect()
        sftp = nil
    }
    
    private func ensureConnection() throws {
        // Always create a fresh connection for enumeration
        sftp?.disconnect()
        sftp = nil
        
        sftp = MFTSftpConnection(
            hostname: connection.host,
            port: connection.port ?? 22,
            username: connection.username,
            password: connection.password
        )
        
        NSLog("SFTPFiles: Connecting to \(connection.host):\(connection.port ?? 22)")
        try sftp!.connect()
        try sftp!.authenticate()
        NSLog("SFTPFiles: Connected and authenticated successfully")
    }
    
    private func pathForContainer(_ identifier: NSFileProviderItemIdentifier) -> String {
        if identifier == .rootContainer {
            let remotePath = connection.remotePath.isEmpty ? "/" : connection.remotePath
            NSLog("SFTPFiles: Root container path: '\(remotePath)'")
            return remotePath
        }
        
        // For regular paths, use the identifier as-is (it should be an absolute path)
        let path = identifier.rawValue
        NSLog("SFTPFiles: Container path: '\(path)'")
        return path
    }
    
    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        let path = pathForContainer(containerIdentifier)
        
        NSLog("SFTPFiles: Starting enumeration for path: '\(path)'")
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Always establish fresh connection for enumeration
                try self.ensureConnection()
                
                NSLog("SFTPFiles: Listing directory contents for: '\(path)'")
                let items = try self.sftp!.contentsOfDirectory(atPath: path, maxItems: 0)
                
                let providerItems = items.map { item in
                    let itemPath = path == "/" ? "/\(item.filename)" : "\(path)/\(item.filename)"
                    NSLog("SFTPFiles: Creating provider item for: '\(itemPath)' (filename: '\(item.filename)')")
                    return SFTPFileProviderItem(fileInfo: item, path: itemPath)
                }
                
                NSLog("SFTPFiles: Successfully enumerated \(providerItems.count) items for path: '\(path)'")
                
                DispatchQueue.main.async {
                    observer.didEnumerate(providerItems)
                    observer.finishEnumerating(upTo: nil)
                }
                
                // Clean up connection after enumeration
                self.sftp?.disconnect()
                self.sftp = nil
                
            } catch {
                NSLog("SFTPFiles: Enumeration failed for path '\(path)': \(error.localizedDescription)")
                
                // Clean up connection on error
                self.sftp?.disconnect()
                self.sftp = nil
                
                DispatchQueue.main.async {
                    let providerError: NSFileProviderError
                    
                    if error.localizedDescription.contains("not found") || error.localizedDescription.contains("No such file") {
                        providerError = NSFileProviderError(.noSuchItem)
                    } else if error.localizedDescription.contains("permission") || error.localizedDescription.contains("denied") {
                        providerError = NSFileProviderError(.notAuthenticated)
                    } else if error.localizedDescription.contains("timeout") || error.localizedDescription.contains("connection") {
                        providerError = NSFileProviderError(.serverUnreachable)
                    } else {
                        providerError = NSFileProviderError(.serverUnreachable)
                    }
                    
                    observer.finishEnumeratingWithError(providerError)
                }
            }
        }
    }
    
    func enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
        NSLog("SFTPFiles: Enumerating changes from sync anchor for path: '\(pathForContainer(containerIdentifier))'")
        
        // Since SFTP doesn't support incremental change tracking, we need to do a full enumeration
        // and report all items as updates to force the Files app to refresh
        
        let path = pathForContainer(containerIdentifier)
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.ensureConnection()
                
                NSLog("SFTPFiles: Getting current directory contents for change detection")
                let items = try self.sftp!.contentsOfDirectory(atPath: path, maxItems: 0)
                
                let providerItems = items.map { item in
                    let itemPath = path == "/" ? "/\(item.filename)" : "\(path)/\(item.filename)"
                    return SFTPFileProviderItem(fileInfo: item, path: itemPath)
                }
                
                // Create new sync anchor with current timestamp
                let newAnchor = NSFileProviderSyncAnchor("change_\(Date().timeIntervalSince1970)".data(using: .utf8)!)
                
                NSLog("SFTPFiles: Reporting \(providerItems.count) items as changed")
                
                DispatchQueue.main.async {
                    // Report all items as updates (since we can't track individual changes)
                    observer.didUpdate(providerItems)
                    
                    observer.finishEnumeratingChanges(upTo: newAnchor, moreComing: false)
                }
                
                self.sftp?.disconnect()
                self.sftp = nil
                
            } catch {
                NSLog("SFTPFiles: Change enumeration failed for path '\(path)': \(error.localizedDescription)")
                
                self.sftp?.disconnect()
                self.sftp = nil
                
                DispatchQueue.main.async {
                    let providerError: NSFileProviderError
                    
                    if error.localizedDescription.contains("not found") || error.localizedDescription.contains("No such file") {
                        providerError = NSFileProviderError(.noSuchItem)
                    } else if error.localizedDescription.contains("permission") || error.localizedDescription.contains("denied") {
                        providerError = NSFileProviderError(.notAuthenticated)
                    } else if error.localizedDescription.contains("timeout") || error.localizedDescription.contains("connection") {
                        providerError = NSFileProviderError(.serverUnreachable)
                    } else {
                        providerError = NSFileProviderError(.serverUnreachable)
                    }
                    
                    observer.finishEnumeratingWithError(providerError)
                }
            }
        }
    }
    
    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        // Always return a new sync anchor based on current time
        NSLog("SFTPFiles: Creating new sync anchor")
        let anchor = NSFileProviderSyncAnchor("sync_\(Date().timeIntervalSince1970)".data(using: .utf8)!)
        completionHandler(anchor)
    }
}
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
    
    private func pathForContainer(_ identifier: NSFileProviderItemIdentifier) -> String {
        if identifier == .rootContainer {
            return connection.remotePath.isEmpty ? "/" : connection.remotePath
        }
        return identifier.rawValue
    }
    
    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        let path = pathForContainer(containerIdentifier)
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.ensureConnection()
                
                let items = try self.sftp!.contentsOfDirectory(atPath: path, maxItems: 0)
                let providerItems = items.map { item in
                    let itemPath = path == "/" ? "/\(item.filename)" : "\(path)/\(item.filename)"
                    return SFTPFileProviderItem(fileInfo: item, path: itemPath)
                }
                
                DispatchQueue.main.async {
                    observer.didEnumerate(providerItems)
                    observer.finishEnumerating(upTo: nil)
                }
            } catch {
                DispatchQueue.main.async {
                    observer.finishEnumeratingWithError(NSFileProviderError(.serverUnreachable))
                }
            }
        }
    }
    
    func enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
        // Simple implementation - report no changes for now
        let currentAnchor = NSFileProviderSyncAnchor("anchor_\(Date().timeIntervalSince1970)".data(using: .utf8)!)
        observer.finishEnumeratingChanges(upTo: currentAnchor, moreComing: false)
    }
    
    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let anchor = NSFileProviderSyncAnchor("anchor_\(Date().timeIntervalSince1970)".data(using: .utf8)!)
        completionHandler(anchor)
    }
}
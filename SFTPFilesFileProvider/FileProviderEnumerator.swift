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
    
    // Helper: encode/decode sync anchor as [String: String] (path: version)
    private func encodeSyncAnchor(_ dict: [String: String]) -> NSFileProviderSyncAnchor {
        let data = try? JSONSerialization.data(withJSONObject: dict, options: [])
        return NSFileProviderSyncAnchor(data ?? Data())
    }

    private func decodeSyncAnchor(_ anchor: NSFileProviderSyncAnchor) -> [String: String] {
        let data = anchor.rawValue
        guard !data.isEmpty else { return [:] }
        if let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String] {
            return dict
        }
        return [:]
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
        let path = pathForContainer(containerIdentifier)
        NSLog("SFTPFiles: Enumerating changes from sync anchor for path: '\(path)'")

        // Decode previous state from sync anchor
        let previousState = decodeSyncAnchor(syncAnchor)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.ensureConnection()
                let items = try self.sftp!.contentsOfDirectory(atPath: path, maxItems: 0)
                var currentState: [String: String] = [:]
                var currentItems: [String: SFTPFileProviderItem] = [:]
                for item in items {
                    let itemPath = path == "/" ? "/\(item.filename)" : "\(path)/\(item.filename)"
                    let providerItem = SFTPFileProviderItem(fileInfo: item, path: itemPath)
                    // Use mtime_size as version string
                    let version = "\(item.mtime.timeIntervalSince1970)_\(item.size)"
                    currentState[itemPath] = version
                    currentItems[itemPath] = providerItem
                }

                // Compute diffs
                let previousPaths = Set(previousState.keys)
                let currentPaths = Set(currentState.keys)
                let added = currentPaths.subtracting(previousPaths)
                let removed = previousPaths.subtracting(currentPaths)
                let common = previousPaths.intersection(currentPaths)

                var changed: [SFTPFileProviderItem] = []
                var addedItems: [SFTPFileProviderItem] = []
                var removedIds: [NSFileProviderItemIdentifier] = []

                // Added
                for path in added {
                    if let item = currentItems[path] {
                        addedItems.append(item)
                    }
                }
                // Removed
                for path in removed {
                    removedIds.append(NSFileProviderItemIdentifier(path))
                }
                // Changed
                for path in common {
                    let prevVersion = previousState[path]
                    let currVersion = currentState[path]
                    if prevVersion != currVersion, let item = currentItems[path] {
                        changed.append(item)
                    }
                }

                // Conflict detection: if a file changed both locally and remotely, report as conflict (basic: just treat as update)
                // For a real implementation, you would compare local pending changes and remote changes, and create a conflict copy if both changed.

                let newAnchor = self.encodeSyncAnchor(currentState)

                DispatchQueue.main.async {
                    // For NSFileProviderChangeObserver, use didUpdate for both added and changed items
                    let allUpdated = addedItems + changed
                    if !allUpdated.isEmpty {
                        observer.didUpdate(allUpdated)
                    }
                    // didDelete is not available on NSFileProviderChangeObserver (iOS). Skipping explicit delete reporting.
                    observer.finishEnumeratingChanges(upTo: newAnchor, moreComing: false)
                }

                self.sftp?.disconnect()
                self.sftp = nil
            } catch {
                NSLog("SFTPFiles: Change enumeration failed for path '\(path)': \(error.localizedDescription)")
                self.sftp?.disconnect()
                self.sftp = nil
                DispatchQueue.main.async {
                    let providerError: Error
                    if error.localizedDescription.contains("not found") || error.localizedDescription.contains("No such file") {
                        providerError = NSError.fileProviderErrorForNonExistentItem(withIdentifier: NSFileProviderItemIdentifier(path)) as NSError
                    } else if error.localizedDescription.contains("permission") || error.localizedDescription.contains("denied") {
                        providerError = NSFileProviderError(.notAuthenticated) as NSError
                    } else if error.localizedDescription.contains("timeout") || error.localizedDescription.contains("connection") {
                        providerError = NSFileProviderError(.serverUnreachable) as NSError
                    } else {
                        providerError = NSFileProviderError(.serverUnreachable) as NSError
                    }
                    observer.finishEnumeratingWithError(providerError)
                }
            }
        }
    }
    
    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        // Return a sync anchor representing the current state of the directory
        let path = pathForContainer(containerIdentifier)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.ensureConnection()
                let items = try self.sftp!.contentsOfDirectory(atPath: path, maxItems: 0)
                var state: [String: String] = [:]
                for item in items {
                    let itemPath = path == "/" ? "/\(item.filename)" : "\(path)/\(item.filename)"
                    let version = "\(item.mtime.timeIntervalSince1970)_\(item.size)"
                    state[itemPath] = version
                }
                let anchor = self.encodeSyncAnchor(state)
                DispatchQueue.main.async {
                    completionHandler(anchor)
                }
                self.sftp?.disconnect()
                self.sftp = nil
            } catch {
                NSLog("SFTPFiles: currentSyncAnchor failed for path '\(path)': \(error.localizedDescription)")
                self.sftp?.disconnect()
                self.sftp = nil
                DispatchQueue.main.async {
                    completionHandler(nil)
                }
            }
        }
    }
}
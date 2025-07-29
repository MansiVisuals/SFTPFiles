//
//  FileProviderExtension.swift


import FileProvider
import os.log
import mft
import UniformTypeIdentifiers



// MARK: - File Provider Enumerator

class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    
    private let enumeratedItemIdentifier: NSFileProviderItemIdentifier
    private let persistenceService = SharedPersistenceService.shared
    private let keychainService = SharedKeychainService()
    
    init(enumeratedItemIdentifier: NSFileProviderItemIdentifier) {
        self.enumeratedItemIdentifier = enumeratedItemIdentifier
        super.init()
    }
    
    func invalidate() {}
    
    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        if enumeratedItemIdentifier == .rootContainer {
            // For the root container, enumerate nothing or a placeholder if needed, since we cannot construct MFTSftpItem directly.
            observer.didEnumerate([])
            observer.finishEnumerating(upTo: nil)
            return
        }

        // Parse connection identifier
        let idPrefix = "connection_"
        guard enumeratedItemIdentifier.rawValue.hasPrefix(idPrefix) else {
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
            observer.didEnumerate([])
            observer.finishEnumerating(upTo: nil)
            return
        }
        var remotePath = "/"
        if components.count == 2 {
            let pathComponent = String(components[1])
            remotePath = pathComponent.replacingOccurrences(of: "__SLASH__", with: "/")
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let sftp = try SFTPService.shared.connect(to: connection, password: password)
                defer { sftp.disconnect() }
                let entries = try SFTPService.shared.listDirectory(sftp: sftp, path: remotePath)
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
                    observer.didEnumerate(items)
                    observer.finishEnumerating(upTo: nil)
                }
            } catch {
                DispatchQueue.main.async {
                    observer.didEnumerate([])
                    observer.finishEnumerating(upTo: nil)
                }
            }
        }
    }
    
    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        let newAnchor = NSFileProviderSyncAnchor(Data())
        observer.finishEnumeratingChanges(upTo: newAnchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let anchor = NSFileProviderSyncAnchor(Data())
        completionHandler(anchor)
    }
}

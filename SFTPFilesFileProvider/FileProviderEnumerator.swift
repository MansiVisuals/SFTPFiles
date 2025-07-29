//
//  FileProviderEnumerator.swift
//  SFTPFilesFileProvider
//
//  Created by Maikel Mansi on 28/07/2025.
//

import FileProvider

class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    private let enumeratedItemIdentifier: NSFileProviderItemIdentifier
    private let sftpBackend: SFTPBackend
    
    init(enumeratedItemIdentifier: NSFileProviderItemIdentifier, sftpBackend: SFTPBackend) {
        self.enumeratedItemIdentifier = enumeratedItemIdentifier
        self.sftpBackend = sftpBackend
        super.init()
    }
    
    func invalidate() {
        // Clean up resources
    }
    
    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        sftpBackend.enumerateItems(
            for: enumeratedItemIdentifier,
            observer: observer,
            startingAt: page
        )
    }
    
    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        sftpBackend.enumerateChanges(
            for: enumeratedItemIdentifier,
            observer: observer,
            from: anchor
        )
    }
    
    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        sftpBackend.currentSyncAnchor(for: enumeratedItemIdentifier, completionHandler: completionHandler)
    }
}

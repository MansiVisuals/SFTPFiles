//
//  FileProviderExtension.swift
//  SFTPFilesFileProvider
//
//  Created by Maikel Mansi on 28/07/2025.
//

import FileProvider
import os.log

class FileProviderExtension: NSFileProviderExtension {
    
    private let logger = Logger(subsystem: "com.mansi.sftpfiles", category: "FileProvider")
    
    override init() {
        super.init()
        
        // Multiple logging approaches to ensure visibility
        print("🔥🔥🔥 FileProviderExtension: INITIALIZING")
        NSLog("🔥🔥🔥 FileProviderExtension: INITIALIZING")
        logger.info("🔥🔥🔥 FileProviderExtension: INITIALIZING")
        
        if let domain = self.domain {
            print("🔥🔥🔥 FileProviderExtension: Domain: \(domain.identifier.rawValue)")
            logger.info("🔥🔥🔥 FileProviderExtension: Domain: \(domain.identifier.rawValue)")
        }
        
        print("🔥🔥🔥 FileProviderExtension: Initialization COMPLETE")
        logger.info("🔥🔥🔥 FileProviderExtension: Initialization COMPLETE")
    }
    
    // MARK: - Item Methods
    
    override func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem {
        print("🔥🔥🔥 FileProviderExtension: item(for:) \(identifier.rawValue)")
        logger.info("🔥🔥🔥 FileProviderExtension: item(for:) \(identifier.rawValue)")
        
        if identifier == .rootContainer {
            return FileProviderItem(
                identifier: .rootContainer,
                filename: "SFTP Files",
                typeIdentifier: "public.folder",
                isDirectory: true,
                remotePath: "/",
                connectionId: UUID(), // Dummy for root
                parentIdentifier: .rootContainer
            )
        }
        
        print("🔥🔥🔥 FileProviderExtension: No item found for \(identifier.rawValue)")
        throw NSFileProviderError(.noSuchItem)
    }
    
    override func urlForItem(withPersistentIdentifier identifier: NSFileProviderItemIdentifier) -> URL? {
        print("🔥🔥🔥 FileProviderExtension: urlForItem \(identifier.rawValue)")
        logger.info("🔥🔥🔥 FileProviderExtension: urlForItem \(identifier.rawValue)")
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileProviderDir = documentsURL.appendingPathComponent("FileProvider")
        let url = fileProviderDir.appendingPathComponent(identifier.rawValue)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: fileProviderDir, withIntermediateDirectories: true, attributes: nil)
        
        print("🔥🔥🔥 FileProviderExtension: URL for \(identifier.rawValue): \(url)")
        return url
    }
    
    override func persistentIdentifierForItem(at url: URL) -> NSFileProviderItemIdentifier? {
        print("🔥🔥🔥 FileProviderExtension: persistentIdentifierForItem at \(url)")
        logger.info("🔥🔥🔥 FileProviderExtension: persistentIdentifierForItem at \(url.path)")
        
        let identifier = NSFileProviderItemIdentifier(url.lastPathComponent)
        print("🔥🔥🔥 FileProviderExtension: Extracted identifier: \(identifier.rawValue)")
        return identifier
    }
    
    override func providePlaceholder(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        print("🔥🔥🔥 FileProviderExtension: providePlaceholder at \(url)")
        logger.info("🔥🔥🔥 FileProviderExtension: providePlaceholder at \(url.path)")
        
        guard let identifier = persistentIdentifierForItem(at: url) else {
            print("🔥🔥🔥 FileProviderExtension: No identifier for placeholder")
            completionHandler(NSFileProviderError(.noSuchItem))
            return
        }
        
        do {
            let fileProviderItem = try item(for: identifier)
            let placeholderURL = NSFileProviderManager.placeholderURL(for: url)
            try NSFileProviderManager.writePlaceholder(at: placeholderURL, withMetadata: fileProviderItem)
            print("🔥🔥🔥 FileProviderExtension: Created placeholder at \(placeholderURL)")
            completionHandler(nil)
        } catch {
            print("🔥🔥🔥 FileProviderExtension: Failed to create placeholder: \(error)")
            completionHandler(error)
        }
    }
    
    override func startProvidingItem(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        print("🔥🔥🔥 FileProviderExtension: startProvidingItem at \(url)")
        logger.info("🔥🔥🔥 FileProviderExtension: startProvidingItem at \(url.path)")
        
        // For now, just create an empty file to test the mechanism
        do {
            try "Hello from SFTP Files!".write(to: url, atomically: true, encoding: .utf8)
            print("🔥🔥🔥 FileProviderExtension: Successfully provided item")
            completionHandler(nil)
        } catch {
            print("🔥🔥🔥 FileProviderExtension: Failed to provide item: \(error)")
            completionHandler(error)
        }
    }
    
    override func itemChanged(at url: URL) {
        print("🔥🔥🔥 FileProviderExtension: itemChanged at \(url)")
        logger.info("🔥🔥🔥 FileProviderExtension: itemChanged at \(url.path)")
    }
    
    override func stopProvidingItem(at url: URL) {
        print("🔥🔥🔥 FileProviderExtension: stopProvidingItem at \(url)")
        logger.info("🔥🔥🔥 FileProviderExtension: stopProvidingItem at \(url.path)")
    }
    
    // MARK: - Enumeration
    
    override func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier) throws -> NSFileProviderEnumerator {
        print("🔥🔥🔥 FileProviderExtension: enumerator(for:) \(containerItemIdentifier.rawValue)")
        logger.info("🔥🔥🔥 FileProviderExtension: enumerator(for:) \(containerItemIdentifier.rawValue)")
        
        return MinimalFileProviderEnumerator(enumeratedItemIdentifier: containerItemIdentifier)
    }
}

// MARK: - Minimal File Provider Enumerator

class MinimalFileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    private let enumeratedItemIdentifier: NSFileProviderItemIdentifier
    private let logger = Logger(subsystem: "com.mansi.sftpfiles", category: "Enumerator")
    
    init(enumeratedItemIdentifier: NSFileProviderItemIdentifier) {
        self.enumeratedItemIdentifier = enumeratedItemIdentifier
        super.init()
        
        print("🔥🔥🔥 MinimalFileProviderEnumerator: Created for \(enumeratedItemIdentifier.rawValue)")
        logger.info("🔥🔥🔥 MinimalFileProviderEnumerator: Created for \(enumeratedItemIdentifier.rawValue)")
    }
    
    func invalidate() {
        print("🔥🔥🔥 MinimalFileProviderEnumerator: invalidate")
        logger.info("🔥🔥🔥 MinimalFileProviderEnumerator: invalidate")
    }
    
    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        print("🔥🔥🔥 MinimalFileProviderEnumerator: enumerateItems for \(self.enumeratedItemIdentifier.rawValue)")
        logger.info("🔥🔥🔥 MinimalFileProviderEnumerator: enumerateItems for \(self.enumeratedItemIdentifier.rawValue)")
        
        if self.enumeratedItemIdentifier == .rootContainer {
            // Return a test item
            let testItem = FileProviderItem(
                identifier: NSFileProviderItemIdentifier("test_connection"),
                filename: "Test SFTP Connection",
                typeIdentifier: "public.folder",
                isDirectory: true,
                remotePath: "/",
                connectionId: UUID(),
                parentIdentifier: .rootContainer
            )
            
            print("🔥🔥🔥 MinimalFileProviderEnumerator: Returning 1 test item")
            observer.didEnumerate([testItem])
            observer.finishEnumerating(upTo: nil)
            return
        }
        
        // For other containers, return empty
        print("🔥🔥🔥 MinimalFileProviderEnumerator: Returning empty for non-root container")
        observer.didEnumerate([])
        observer.finishEnumerating(upTo: nil)
    }
    
    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        print("🔥🔥🔥 MinimalFileProviderEnumerator: enumerateChanges")
        logger.info("🔥🔥🔥 MinimalFileProviderEnumerator: enumerateChanges")
        
        let newAnchor = NSFileProviderSyncAnchor(Data())
        observer.finishEnumeratingChanges(upTo: newAnchor, moreComing: false)
    }
    
    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        print("🔥🔥🔥 MinimalFileProviderEnumerator: currentSyncAnchor")
        logger.info("🔥🔥🔥 MinimalFileProviderEnumerator: currentSyncAnchor")
        
        let anchor = NSFileProviderSyncAnchor(Data())
        completionHandler(anchor)
    }
}

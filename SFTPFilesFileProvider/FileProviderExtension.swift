//
//  FileProviderExtension.swift
//  SFTPFilesFileProvider
//
//  Created by Maikel Mansi on 28/07/2025.
//

import FileProvider
import mft

class FileProviderExtension: NSFileProviderExtension {
    private let sftpBackend = SFTPBackend()
    private let pollingService = PollingService()
    
    override init() {
        super.init()
        print("FileProviderExtension initialized")
        
        // Set up polling service with reduced frequency for better battery life
        pollingService.delegate = self
        
        // Delay polling start to avoid startup conflicts
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.pollingService.startPolling()
        }
        
        // Log domain information for debugging
        if let domain = self.domain {
            print("File Provider domain: \(domain.identifier.rawValue)")
            print("File Provider display name: \(domain.displayName)")
        }
    }
    
    deinit {
        pollingService.stopPolling()
        print("FileProviderExtension deinitialized")
    }
    
    override func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem {
        print("FileProvider: Requesting item for \(identifier.rawValue)")
        return try sftpBackend.item(for: identifier)
    }
    
    override func urlForItem(withPersistentIdentifier identifier: NSFileProviderItemIdentifier) -> URL? {
        print("FileProvider: URL request for \(identifier.rawValue)")
        return sftpBackend.urlForItem(withIdentifier: identifier)
    }
    
    override func persistentIdentifierForItem(at url: URL) -> NSFileProviderItemIdentifier? {
        print("FileProvider: Persistent identifier for \(url)")
        return sftpBackend.persistentIdentifier(for: url)
    }
    
    override func providePlaceholder(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        print("FileProvider: Providing placeholder at \(url)")
        sftpBackend.providePlaceholder(at: url, completionHandler: completionHandler)
    }
    
    override func startProvidingItem(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        print("FileProvider: Start providing item at \(url)")
        sftpBackend.startProvidingItem(at: url, completionHandler: completionHandler)
    }
    
    override func itemChanged(at url: URL) {
        print("FileProvider: Item changed at \(url)")
        sftpBackend.itemChanged(at: url)
    }
    
    override func stopProvidingItem(at url: URL) {
        print("FileProvider: Stop providing item at \(url)")
        sftpBackend.stopProvidingItem(at: url)
    }
}

// MARK: - Enumeration
extension FileProviderExtension {
    override func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier) throws -> NSFileProviderEnumerator {
        print("FileProvider: Creating enumerator for \(containerItemIdentifier.rawValue)")
        return FileProviderEnumerator(
            enumeratedItemIdentifier: containerItemIdentifier,
            sftpBackend: sftpBackend
        )
    }
}

// MARK: - Polling Service Delegate
extension FileProviderExtension: PollingServiceDelegate {
    func pollingServiceDidDetectChanges(_ changes: [String]) {
        print("FileProvider: Detected \(changes.count) changes from polling")
        
        // Signal changes to the system with rate limiting
        for path in changes {
            if let identifier = sftpBackend.persistentIdentifier(forPath: path) {
                NSFileProviderManager.default.signalEnumerator(for: identifier) { error in
                    if let error = error {
                        print("Failed to signal enumerator for \(path): \(error)")
                    } else {
                        print("Signaled enumerator for changed path: \(path)")
                    }
                }
            }
        }
        
        // Always signal root container to ensure Files app refreshes
        NSFileProviderManager.default.signalEnumerator(for: .rootContainer) { error in
            if let error = error {
                print("Failed to signal root enumerator: \(error)")
            } else {
                print("Signaled root enumerator for changes")
            }
        }
    }
}
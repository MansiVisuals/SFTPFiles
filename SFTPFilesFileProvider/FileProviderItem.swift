import Foundation
import FileProvider
import UniformTypeIdentifiers
import mft

class SFTPFileProviderItem: NSObject, NSFileProviderItem {
    private let fileInfo: MFTSftpItem?
    private let path: String
    private let parentPath: String
    private let isRootItem: Bool
    private weak var downloadManager: DownloadManager?
    
    // MARK: - Initialization
    
    init(fileInfo: MFTSftpItem, path: String, downloadManager: DownloadManager? = nil) {
        self.fileInfo = fileInfo
        self.path = path
        self.parentPath = (path as NSString).deletingLastPathComponent
        self.isRootItem = false
        self.downloadManager = downloadManager
        super.init()
        
        // Debug logging
        NSLog("SFTPFiles: Creating item - Path: '\(path)', Filename: '\(fileInfo.filename)'")
    }
    
    init(rootPath: String, downloadManager: DownloadManager? = nil) {
        self.fileInfo = nil
        self.path = rootPath
        self.parentPath = ""
        self.isRootItem = true
        self.downloadManager = downloadManager
        super.init()
    }
    
    // MARK: - NSFileProviderItem
    
    var itemIdentifier: NSFileProviderItemIdentifier {
        if isRootItem {
            return .rootContainer
        }
        return NSFileProviderItemIdentifier(path)
    }
    
    var parentItemIdentifier: NSFileProviderItemIdentifier {
        if isRootItem || parentPath.isEmpty || parentPath == "/" {
            return .rootContainer
        }
        return NSFileProviderItemIdentifier(parentPath)
    }
    
    var filename: String {
        if isRootItem {
            return "SFTP Server"
        }
        
        // Always use the actual filename from the server, never the path
        if let serverFilename = fileInfo?.filename, !serverFilename.isEmpty {
            // Additional safety: ensure no path components are included
            let cleanFilename = serverFilename.components(separatedBy: "/").last ?? serverFilename
            NSLog("SFTPFiles: Item filename - Server: '\(serverFilename)', Clean: '\(cleanFilename)'")
            return cleanFilename
        }
        
        // Fallback: extract filename from path as last resort
        let pathComponents = path.components(separatedBy: "/")
        let fallbackFilename = pathComponents.last ?? "Unknown"
        NSLog("SFTPFiles: Item filename fallback: '\(fallbackFilename)'")
        return fallbackFilename
    }
    
    var contentType: UTType {
        if isRootItem || fileInfo?.isDirectory == true {
            return .folder
        }
        
        let ext = (filename as NSString).pathExtension.lowercased()
        return UTType(filenameExtension: ext) ?? .data
    }
    
    var capabilities: NSFileProviderItemCapabilities {
        var caps: NSFileProviderItemCapabilities = [
            .allowsReading,
            .allowsWriting,
            .allowsRenaming,
            .allowsDeleting,
            .allowsReparenting
        ]
        
        if isRootItem || fileInfo?.isDirectory == true {
            caps.insert(.allowsAddingSubItems)
            caps.insert(.allowsContentEnumerating)
        } else {
            // Files can be evicted (removed from local storage)
            caps.insert(.allowsEvicting)
        }
        
        if isRootItem {
            caps.remove(.allowsDeleting)
            caps.remove(.allowsRenaming)
            caps.remove(.allowsReparenting)
            caps.remove(.allowsEvicting)
        }
        
        return caps
    }
    
    var documentSize: NSNumber? {
        if isRootItem || fileInfo?.isDirectory == true {
            return nil
        }
        return NSNumber(value: fileInfo?.size ?? 0)
    }
    
    var contentModificationDate: Date? {
        if isRootItem {
            // Use now for root, never epoch
            return Date()
        }
        // Use mtime if available, else fallback to atime, else createTime, else now
        return fileInfo?.mtime != Date(timeIntervalSince1970: 0) ? fileInfo?.mtime : (fileInfo?.atime != Date(timeIntervalSince1970: 0) ? fileInfo?.atime : (fileInfo?.createTime != Date(timeIntervalSince1970: 0) ? fileInfo?.createTime : Date()))
    }

    var creationDate: Date? {
        if isRootItem {
            // Use now for root, never epoch
            return Date()
        }
        // Use createTime if available, else mtime, else atime, else now
        return fileInfo?.createTime != Date(timeIntervalSince1970: 0) ? fileInfo?.createTime : (fileInfo?.mtime != Date(timeIntervalSince1970: 0) ? fileInfo?.mtime : (fileInfo?.atime != Date(timeIntervalSince1970: 0) ? fileInfo?.atime : Date()))
    }
    
    var itemVersion: NSFileProviderItemVersion {
        let modTime = fileInfo?.mtime.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        let size = fileInfo?.size ?? 0
        
        let version = "\(modTime)_\(size)".data(using: .utf8) ?? Data()
        return NSFileProviderItemVersion(contentVersion: version, metadataVersion: version)
    }
    
    var isDownloaded: Bool {
        if isRootItem || fileInfo?.isDirectory == true {
            return true
        }
        
        return downloadManager?.isDownloaded(identifier: itemIdentifier) ?? false
    }
    
    var isDownloading: Bool {
        return false
    }
    
    var isUploaded: Bool {
        return true
    }
    
    var isUploading: Bool {
        return false
    }
    
    var downloadingError: Error? {
        return nil
    }
    
    var uploadingError: Error? {
        return nil
    }
    
    // MARK: - File Provider Progress
    
    var isMostRecentVersionDownloaded: Bool {
        return isDownloaded
    }
    
    var isShared: Bool {
        return false
    }
    
    var isSharedByCurrentUser: Bool {
        return false
    }
    
    var ownerNameComponents: PersonNameComponents? {
        return nil
    }
    
    var mostRecentEditorNameComponents: PersonNameComponents? {
        return nil
    }
    
    var versionIdentifier: Data? {
        return itemVersion.contentVersion
    }
    
    // MARK: - Additional Properties for Better File Handling
    
    var typeIdentifier: String {
        return contentType.identifier
    }
    
    var childItemCount: NSNumber? {
        if fileInfo?.isDirectory == true {
            // Could potentially enumerate and count, but expensive
            return nil
        }
        return nil
    }
    
    var favoriteRank: NSNumber? {
        return nil
    }
    
    var tagData: Data? {
        return nil
    }
    
    var fileSystemFlags: NSFileProviderFileSystemFlags {
        var flags: NSFileProviderFileSystemFlags = []
        
        if fileInfo?.isDirectory == true {
            flags.insert(.userReadable)
            flags.insert(.userWritable)
            flags.insert(.userExecutable)
        } else {
            flags.insert(.userReadable)
            flags.insert(.userWritable)
        }
        
        return flags
    }
    
    var extendedAttributes: [String : Data] {
        return [:]
    }
}
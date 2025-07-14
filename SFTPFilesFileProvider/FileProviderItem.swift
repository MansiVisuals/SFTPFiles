import Foundation
import FileProvider
import UniformTypeIdentifiers
import mft

class SFTPFileProviderItem: NSObject, NSFileProviderItem {
    private let fileInfo: MFTSftpItem?
    private let path: String
    private let parentPath: String
    private let isRootItem: Bool
    
    // MARK: - Initialization
    
    init(fileInfo: MFTSftpItem, path: String) {
        self.fileInfo = fileInfo
        self.path = path
        self.parentPath = (path as NSString).deletingLastPathComponent
        self.isRootItem = false
        super.init()
    }
    
    init(rootPath: String) {
        self.fileInfo = nil
        self.path = rootPath
        self.parentPath = ""
        self.isRootItem = true
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
        return fileInfo?.filename ?? "Unknown"
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
        }
        
        if isRootItem {
            caps.remove(.allowsDeleting)
            caps.remove(.allowsRenaming)
            caps.remove(.allowsReparenting)
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
        return fileInfo?.mtime ?? Date()
    }
    
    var creationDate: Date? {
        return fileInfo?.mtime ?? Date()
    }
    
    var itemVersion: NSFileProviderItemVersion {
        let modTime = fileInfo?.mtime.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        let size = fileInfo?.size ?? 0
        
        let version = "\(modTime)_\(size)".data(using: .utf8) ?? Data()
        return NSFileProviderItemVersion(contentVersion: version, metadataVersion: version)
    }
    
    var isDownloaded: Bool {
        return fileInfo?.isDirectory == true || isRootItem
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
}
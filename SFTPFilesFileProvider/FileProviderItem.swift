import FileProvider
import UniformTypeIdentifiers
import mft

class FileProviderItem: NSObject, NSFileProviderItem {
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let sftpItem: MFTSftpItem

    init(itemIdentifier: NSFileProviderItemIdentifier, parentItemIdentifier: NSFileProviderItemIdentifier, sftpItem: MFTSftpItem) {
        self.itemIdentifier = itemIdentifier
        self.parentItemIdentifier = parentItemIdentifier
        self.sftpItem = sftpItem
    }

    // MARK: - NSFileProviderItem
    var filename: String { sftpItem.filename }
    var typeIdentifier: String {
        if sftpItem.isDirectory {
            return UTType.folder.identifier
        } else if sftpItem.isSymlink {
            return "public.symlink"
        } else {
            let ext = (sftpItem.filename as NSString).pathExtension.lowercased()
            switch ext {
            case "txt", "md", "readme": return UTType.plainText.identifier
            case "jpg", "jpeg", "png", "gif", "bmp": return UTType.image.identifier
            case "pdf": return "com.adobe.pdf"
            case "mp4", "mov", "avi": return UTType.movie.identifier
            case "mp3", "wav", "m4a": return UTType.audio.identifier
            case "zip", "tar", "gz": return "public.archive"
            default: return UTType.data.identifier
            }
        }
    }
    var contentType: UTType {
        UTType(typeIdentifier) ?? .data
    }
    var capabilities: NSFileProviderItemCapabilities {
        if sftpItem.isDirectory {
            return [.allowsReading, .allowsAddingSubItems, .allowsContentEnumerating, .allowsRenaming, .allowsTrashing]
        } else {
            return [.allowsReading, .allowsWriting, .allowsRenaming, .allowsTrashing]
        }
    }
    var fileSystemFlags: NSFileProviderFileSystemFlags {
        var flags: NSFileProviderFileSystemFlags = []
        flags.insert(.userReadable)
        if !sftpItem.isDirectory {
            flags.insert(.userWritable)
        }
        // .userExecutable is not set, as you want it to be false
        return flags
    }
    var documentSize: NSNumber? { sftpItem.isDirectory ? nil : NSNumber(value: sftpItem.size) }
    var contentModificationDate: Date? { sftpItem.mtime }
    var creationDate: Date? { sftpItem.createTime }
    var isSymbolicLink: Bool { sftpItem.isSymlink }
}


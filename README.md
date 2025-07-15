


# SFTPFiles – iOS SFTP File Provider & Connection Manager
# [![Support me on Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/surebeat)

![Platform](https://img.shields.io/badge/platform-iOS-blue)
![Swift](https://img.shields.io/badge/language-Swift-orange)
![FileProvider](https://img.shields.io/badge/framework-FileProvider-green)



SFTPFiles is a native iOS app and File Provider extension that lets users connect to SFTP servers and manage files directly from the iOS Files app. It uses Apple's FileProvider framework and the [MFT library](https://github.com/mplpl/mft) for SFTP operations. Tested with [SFTPGo](https://github.com/drakkan/sftpgo). Planned: NATS integration for real-time events and advanced sync using [sftpgo-plugin-pubsub](https://github.com/sftpgo/sftpgo-plugin-pubsub) and [nats.swift](https://github.com/nats-io/nats.swift).

---

## Table of Contents

- [Main Features](#main-features)
- [Architecture Overview](#architecture-overview)
- [Data Sharing & Security](#data-sharing--security)
- [Planned Enhancements](#planned-enhancements)
- [Usage](#usage)
- [File Operations](#file-operations)
- [Technical Details](#technical-details)
- [Security](#security)
- [Development Notes](#development-notes)
- [Key Components](#key-components)
- [Acknowledgments](#acknowledgments)




## Main Features

- **SwiftUI Connection Manager**: Add, edit, delete, and test SFTP connections in a modern, intuitive UI
- **Files App Integration**: Browse, upload, download, rename, and delete files/folders from SFTP servers in the Files app
- **Secure Storage**: Credentials stored securely using App Groups and UserDefaults suite
- **Async SFTP Operations**: All file operations are async, using completion handlers for smooth UX
- **Beautiful Empty State**: Modern UI for empty and error states
- **Tested with SFTPGo**: Full compatibility with SFTPGo server
- **Planned: NATS + SFTPGo**: Real-time file events, notifications, and advanced sync via NATS ([sftpgo-plugin-pubsub](https://github.com/sftpgo/sftpgo-plugin-pubsub), [nats.swift](https://github.com/nats-io/nats.swift))

## Architecture Overview

### Main App (`SFTPFiles`)
- SwiftUI-based connection management
- Secure credential storage (App Groups)
- Connection testing and validation
- Automatic File Provider domain registration

### File Provider Extension (`SFTPFilesFileProvider`)
- Implements `NSFileProviderReplicatedExtension` for robust file operations
- Handles file/folder enumeration, download/upload, rename, delete, and metadata
- Uses `SFTPProviderLogic` for all SFTP actions

### FileProvider UI Extension (`SFTPFilesFileProviderUI`)
- Custom UI for document actions in the Files app

### Core Logic
- **SFTPProviderLogic**: Wraps MFT library, provides connect/list/upload/download/delete/rename
- **SFTPFileProviderItem**: Implements `NSFileProviderItem`, provides metadata and permissions

## Data Sharing & Security

- App Groups for secure data sharing between app and extension
- Credentials stored in UserDefaults suite (App Groups)
- All SFTP traffic encrypted
- No file content stored locally (streaming operations)

## Planned Enhancements

- **NATS Integration**: Real-time sync/events with SFTPGo
- SSH key authentication
- File preview and offline caching
- Favorites, recent files, and multi-server improvements

## Usage

1. Launch the app to manage SFTP connections
2. Add a connection (+), enter host/port/username/password
3. Test connection before saving
4. Open Files app, access SFTP server under "Locations"

## File Operations

- Browse files/folders
- Download/upload files
- Rename/delete files/folders
- Create new folders



## Technical Details

- **iOS Version**: 11.0+
- **Language**: Swift
- **UI**: SwiftUI
- **Architecture**: MVVM
- **SFTP Library**: [MFT](https://github.com/mplpl/mft)
- **SFTP Server**: [SFTPGo](https://github.com/drakkan/sftpgo)
- **NATS Integration**: [sftpgo-plugin-pubsub](https://github.com/sftpgo/sftpgo-plugin-pubsub), [nats.swift](https://github.com/nats-io/nats.swift) (planned)
- **Data Storage**: App Groups + UserDefaults

---

## Acknowledgments


SFTPFiles would not be possible without the following open source projects:

- [MFT](https://github.com/mplpl/mft) – Swift SFTP client library powering all SFTP operations
- [SFTPGo](https://github.com/drakkan/sftpgo) – Powerful SFTP server used for testing and integration
- [sftpgo-plugin-pubsub](https://github.com/sftpgo/sftpgo-plugin-pubsub) – NATS pub/sub plugin for SFTPGo
- [nats.swift](https://github.com/nats-io/nats.swift) – Swift client for NATS messaging

Special thanks to the maintainers and contributors of these projects for their work and support to the open source community.

Thanks to [Claudio Cambra](https://claudiocambra.com/posts/build-file-provider-sync/) for his extensive guide on implementing FileProvider logic.

---

## Security

- Passwords stored securely (App Groups)
- All SFTP communication encrypted
- No local file content storage
- Follows Apple's File Provider security guidelines

## Development Notes

- Uses modern `NSFileProviderReplicatedExtension` for reliability and performance
- Planned: NATS messaging for SFTPGo integration

### 1. Main App (`SFTPFiles`)
- **Purpose**: Manage SFTP connections
- **UI**: SwiftUI-based interface for creating and managing connections
- **Features**:
  - Add/Edit SFTP connections
  - Test connection validity
  - Beautiful empty state and modern UI
  - Secure credential storage

### 2. File Provider Extension (`FileProvider`)
- **Purpose**: Handle file operations for the Files app
- **Implementation**: Uses `NSFileProviderReplicatedExtension` (modern approach)
- **Features**:
  - File/folder enumeration
  - Download/upload operations
  - Rename and delete operations
  - Metadata provision

## Key Components

### FileProviderExtension
- Implements `NSFileProviderReplicatedExtension`
- Manages SFTP operations through the MFT library
- Handles file provider domains for each connection

### SFTPFileProviderItem
- Implements `NSFileProviderItem`
- Provides file/folder metadata to the Files app
- Handles permissions and capabilities

### SFTPProviderLogic
- Wrapper around MFT library
- Handles all SFTP operations (connect, list, upload, download, delete, rename)
- Provides async completion handlers

### Connection Management
- Uses iOS App Groups for data sharing
- Secure storage with UserDefaults suite
- Automatic File Provider domain registration

## Usage

1. **Launch the app** to see the connection management interface
2. **Add a connection** by tapping the "+" button
3. **Fill in SFTP details** (host, port, username, password)
4. **Test the connection** before saving
5. **Open the Files app** to access your SFTP server under "Locations"

## File Operations

Once connected, users can:
- Browse files and folders
- Download files by tapping
- Upload files using the Files app's share sheet
- Rename files and folders
- Delete files and folders
- Create new folders

## Technical Details

- **iOS Version**: Requires iOS 11.0+ (FileProvider framework)
- **Language**: Swift
- **UI Framework**: SwiftUI
- **Architecture**: MVVM pattern
- **SFTP Library**: MFT framework
- **Data Storage**: App Groups with UserDefaults

## Security

- Passwords are stored securely using iOS App Groups
- All SFTP communication is encrypted
- No file content is stored locally (streaming operations)
- Follows Apple's security guidelines for File Provider extensions

## Future Enhancements

- SSH key authentication
- Connection favorites and recent files
- File preview capabilities
- Offline file caching
- Multiple server support improvements

## Development Notes

The project uses Apple's modern `NSFileProviderReplicatedExtension` instead of the deprecated `NSFileProviderExtension`. This provides better performance and reliability for file operations.

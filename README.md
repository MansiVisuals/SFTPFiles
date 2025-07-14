# SFTP Files - iOS File Provider Extension

A native iOS app that integrates SFTP servers directly into the iOS Files app using Apple's FileProvider framework and the MFT library for SFTP operations.

## Features

- **Native Files App Integration**: Access SFTP servers directly through the iOS Files app under "Locations"
- **Modern UI**: Clean, SwiftUI-based interface for managing SFTP connections
- **Connection Management**: Add, edit, delete, and test SFTP connections
- **Secure Storage**: Uses iOS App Groups for secure data sharing between main app and File Provider extension
- **Full SFTP Support**: Upload, download, rename, delete files and folders
- **iCloud-like Experience**: Seamless file operations without leaving the Files app

## Architecture

The app consists of two main components:

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

## Setup Requirements

1. **App Groups**: Configure `group.mansivisuals.SFTPFiles` in both targets
2. **MFT Framework**: Add the MFT.xcframework to your project
3. **Entitlements**: Ensure proper entitlements are set for both targets

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

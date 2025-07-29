//
//  SFTPService.swift
//  SFTPFiles
//
//  Created by Maikel Mansi on 28/07/2025.
//

import Foundation
import mft

class SFTPService {
    static let shared = SFTPService()
    private init() {}
    
    func testConnection(connection: SFTPConnection, password: String?) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var sftp: MFTSftpConnection? = nil
                do {
                    sftp = MFTSftpConnection(
                        hostname: connection.hostname,
                        port: Int(connection.port),
                        username: connection.username,
                        password: password ?? ""
                    )
                    
                    try sftp?.connect()
                    try sftp?.authenticate()
                    
                    // Test basic directory listing to ensure we can actually read files
                    let _ = try sftp?.contentsOfDirectory(atPath: "/", maxItems: 1)
                    
                    print("Successfully tested connection to \(connection.hostname)")
                    continuation.resume(returning: true)
                } catch {
                    print("SFTP test connection failed for \(connection.hostname): \(error)")
                    continuation.resume(returning: false)
                }
                
                // Cleanup connection
                sftp?.disconnect()
            }
        }
    }
    
    func connect(to connection: SFTPConnection, password: String) throws -> MFTSftpConnection {
        let sftp = MFTSftpConnection(
            hostname: connection.hostname,
            port: Int(connection.port),
            username: connection.username,
            password: password
        )
        
        try sftp.connect()
        try sftp.authenticate()
        
        print("Successfully connected to \(connection.hostname)")
        return sftp
    }
    
    func listDirectory(sftp: MFTSftpConnection, path: String) throws -> [MFTSftpItem] {
        return try sftp.contentsOfDirectory(atPath: path, maxItems: 0)
    }

    func downloadFile(sftp: MFTSftpConnection, remotePath: String, to localURL: URL, progressHandler: @escaping (UInt64, UInt64) -> Bool = { _, _ in true }) throws {
        let parentDir = localURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
        
        // Check if it's a directory first
        let items = try sftp.contentsOfDirectory(atPath: (remotePath as NSString).deletingLastPathComponent, maxItems: 0)
        let filename = (remotePath as NSString).lastPathComponent
        
        guard let item = items.first(where: { $0.filename == filename }) else {
            throw NSError(domain: "SFTPService", code: 404, userInfo: [NSLocalizedDescriptionKey: "File not found: \(remotePath)"])
        }
        
        if item.isDirectory {
            throw NSError(domain: "SFTPService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Cannot download directory as file: \(remotePath)"])
        }
        
        try sftp.downloadFile(atPath: remotePath, toFileAtPath: localURL.path, progress: progressHandler)
    }

    func uploadFile(sftp: MFTSftpConnection, from localURL: URL, to remotePath: String, progressHandler: @escaping (UInt64) -> Bool = { _ in true }) throws {
        try sftp.uploadFile(atPath: localURL.path, toFileAtPath: remotePath, progress: progressHandler)
    }
    
    func validateConnection(_ connection: SFTPConnection, password: String) async -> ConnectionState {
        var sftp: MFTSftpConnection? = nil
        defer {
            sftp?.disconnect()
        }
        
        do {
            sftp = try connect(to: connection, password: password)
            let _ = try listDirectory(sftp: sftp!, path: "/")
            return .connected
        } catch {
            print("Connection validation failed for \(connection.hostname): \(error)")
            return .error
        }
    }
}
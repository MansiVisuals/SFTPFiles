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
                do {
                    let sftp = MFTSftpConnection(
                        hostname: connection.hostname,
                        port: Int(Int32(connection.port)),
                        username: connection.username,
                        password: password ?? ""
                    )
                    
                    try sftp.connect()
                    try sftp.authenticate()
                    
                    // Test basic directory listing to ensure we can access files
                    let _ = try sftp.contentsOfDirectory(atPath: "/", maxItems: 1)
                    
                    sftp.disconnect()
                    print("Successfully tested connection to \(connection.hostname)")
                    continuation.resume(returning: true)
                } catch {
                    print("SFTP test connection failed for \(connection.hostname): \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    func connect(to connection: SFTPConnection, password: String) throws -> MFTSftpConnection {
        let sftp = MFTSftpConnection(
            hostname: connection.hostname,
            port: Int(Int32(connection.port)),
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

    func downloadFile(sftp: MFTSftpConnection, remotePath: String, to localURL: URL, progressHandler: @escaping (UInt64, UInt64) -> Bool) throws {
        // Ensure parent directory exists
        let parentDir = localURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
        try sftp.downloadFile(atPath: remotePath, toFileAtPath: localURL.path, progress: progressHandler)
    }

    func uploadFile(sftp: MFTSftpConnection, from localURL: URL, to remotePath: String, progressHandler: @escaping (UInt64) -> Bool) throws {
        try sftp.uploadFile(atPath: localURL.path, toFileAtPath: remotePath, progress: progressHandler)
    }
    
    // MARK: - Connection Status Management
    
    func validateConnection(_ connection: SFTPConnection, password: String) async -> ConnectionState {
        do {
            let sftp = try connect(to: connection, password: password)
            
            // Test directory listing
            let _ = try listDirectory(sftp: sftp, path: "/")
            
            sftp.disconnect()
            return .connected
        } catch {
            print("Connection validation failed for \(connection.hostname): \(error)")
            return .error
        }
    }
}
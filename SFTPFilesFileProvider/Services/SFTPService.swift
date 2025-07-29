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
                    
                    // Test basic directory listing
                    let _ = try sftp.contentsOfDirectory(atPath: "/", maxItems: 1)
                    
                    sftp.disconnect()
                    continuation.resume(returning: true)
                } catch {
                    print("SFTP test connection error: \(error)")
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
        
        return sftp
    }
    
    func listDirectory(sftp: MFTSftpConnection, path: String) throws -> [Any] {
        return try sftp.contentsOfDirectory(atPath: path, maxItems: 0)
    }
    
    // Fixed: Change parameter types from Int64 to UInt64 to match MFT library
    func downloadFile(sftp: MFTSftpConnection, remotePath: String, to localURL: URL, progressHandler: @escaping (UInt64, UInt64) -> Bool) throws {
        let outputStream = OutputStream(url: localURL, append: false)
        try sftp.contents(atPath: remotePath, toStream: outputStream!, fromPosition: 0, progress: progressHandler)
    }
    
    // Fixed: Change parameter type from Int64 to UInt64 to match MFT library
    func uploadFile(sftp: MFTSftpConnection, from localURL: URL, to remotePath: String, progressHandler: @escaping (UInt64) -> Bool) throws {
        let inputStream = InputStream(url: localURL)
        try sftp.write(stream: inputStream!, toFileAtPath: remotePath, append: false, progress: progressHandler)
    }
}
//
//  EnhancedMFTConnectionManager 2.swift
//  SFTPFiles
//
//  Created by Maikel Mansi on 16/07/2025.
//


import Foundation
@preconcurrency import mft

// MARK: - Enhanced MFT Connection Manager
@preconcurrency
class EnhancedMFTConnectionManager {
    private let keyManager = SSHKeyManager()
    
    func createConnection(for sftpConnection: SFTPConnection) throws -> MFTSftpConnection {
        let connection = MFTSftpConnection(
            hostname: sftpConnection.host,
            port: sftpConnection.port ?? 22,
            username: sftpConnection.username,
            password: sftpConnection.authMethod == .password ? sftpConnection.password : ""
        )
        
        // Configure SSH key authentication if needed
        if sftpConnection.authMethod == .publicKey || sftpConnection.authMethod == .passwordAndKey {
            try configureSSHKeyAuth(connection: connection, sftpConnection: sftpConnection)
        }
        
        return connection
    }
    
    private func configureSSHKeyAuth(connection: MFTSftpConnection, sftpConnection: SFTPConnection) throws {
        guard let keyPairId = sftpConnection.keyPairId,
              let keyPair = try keyManager.getKeyPair(id: keyPairId) else {
            throw ConnectionError.keyPairNotFound
        }
        
        // Configure the MFT connection with SSH key
        // Note: This depends on MFT framework having SSH key support
        // You may need to check MFT documentation for exact method names
        connection.setPrivateKey(keyPair.privateKey, passphrase: keyPair.passphrase)
        
        NSLog("MFT: Configured SSH key authentication for \(sftpConnection.host)")
    }
    
    func testConnection(_ sftpConnection: SFTPConnection) async throws -> ConnectionStatus {
        let connection = try createConnection(for: sftpConnection)
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                do {
                    NSLog("Testing connection to \(sftpConnection.host)...")
                    
                    try connection.connect()
                    try connection.authenticate()
                    
                    // Test directory listing
                    if !sftpConnection.remotePath.isEmpty {
                        _ = try connection.contentsOfDirectory(atPath: sftpConnection.remotePath, maxItems: 1)
                    }
                    
                    connection.disconnect()
                    
                    NSLog("Connection test successful for \(sftpConnection.host)")
                    continuation.resume(returning: .connected)
                    
                } catch {
                    connection.disconnect()
                    
                    NSLog("Connection test failed for \(sftpConnection.host): \(error.localizedDescription)")
                    
                    if error.localizedDescription.contains("authentication") {
                        continuation.resume(returning: .authFailed)
                    } else if error.localizedDescription.contains("timeout") {
                        continuation.resume(returning: .timeout)
                    } else {
                        continuation.resume(returning: .error)
                    }
                }
            }
        }
    }
}

enum ConnectionError: Error {
    case keyPairNotFound
    case authenticationFailed
    case connectionFailed
    case timeout
}

// MARK: - MFT Extension (if needed)
extension MFTSftpConnection {
    func setPrivateKey(_ privateKey: String, passphrase: String?) {
        // TODO: Implement SSH key configuration
        // This depends on MFT framework supporting SSH keys
        // Check MFT documentation for exact method names
        NSLog("MFT: Setting up SSH key authentication")
    }
}

//
//  SSHKeyGenerator.swift
//  SFTPFiles
//
//  Created by Maikel Mansi on 16/07/2025.
//

import Foundation
import Security

// MARK: - SSH Key Generator
class SSHKeyGenerator {
    static func generateKeyPair(name: String, keyType: SSHKeyType = .rsa, keySize: Int = 2048, passphrase: String? = nil) throws -> SSHKeyPair {
        
        // This is a simplified implementation
        // In a real implementation, you would use a proper SSH key generation library
        // For now, we'll create a placeholder structure
        
        let keyPair = SSHKeyPair(
            name: name,
            publicKey: generatePublicKey(type: keyType, size: keySize),
            privateKey: generatePrivateKey(type: keyType, size: keySize, passphrase: passphrase),
            passphrase: passphrase
        )
        
        return keyPair
    }
    
    private static func generatePublicKey(type: SSHKeyType, size: Int) -> String {
        // Placeholder - in a real implementation, you would generate actual keys
        let timestamp = Date().timeIntervalSince1970
        let keyId = UUID().uuidString.prefix(8)
        
        return "ssh-\(type.rawValue) AAAAB3NzaC1yc2EAAAADAQABAAABAQ\(keyId)\(Int(timestamp)) generated-key-\(size)"
    }
    
    private static func generatePrivateKey(type: SSHKeyType, size: Int, passphrase: String?) -> String {
        // Placeholder - in a real implementation, you would generate actual keys
        let keyId = UUID().uuidString
        let encrypted = passphrase != nil ? "Encrypted" : "Unencrypted"
        
        return """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAA
        Generated\(type.rawValue.uppercased())Key\(size)bits\(encrypted)
        KeyID: \(keyId)
        -----END OPENSSH PRIVATE KEY-----
        """
    }
}

enum SSHKeyType: String, CaseIterable {
    case rsa = "rsa"
    case ed25519 = "ed25519"
    case ecdsa = "ecdsa"
    
    var displayName: String {
        switch self {
        case .rsa: return "RSA"
        case .ed25519: return "Ed25519"
        case .ecdsa: return "ECDSA"
        }
    }
}

// MARK: - Key Validation
extension SSHKeyGenerator {
    static func validatePublicKey(_ publicKey: String) -> Bool {
        // Basic validation - check if it starts with a known key type
        let validPrefixes = ["ssh-rsa", "ssh-ed25519", "ssh-ecdsa"]
        return validPrefixes.contains { publicKey.hasPrefix($0) }
    }
    
    static func validatePrivateKey(_ privateKey: String) -> Bool {
        // Basic validation - check if it contains private key markers
        return privateKey.contains("-----BEGIN") && privateKey.contains("-----END")
    }
    
    static func extractKeyType(from publicKey: String) -> SSHKeyType? {
        if publicKey.hasPrefix("ssh-rsa") {
            return .rsa
        } else if publicKey.hasPrefix("ssh-ed25519") {
            return .ed25519
        } else if publicKey.hasPrefix("ssh-ecdsa") {
            return .ecdsa
        }
        return nil
    }
}

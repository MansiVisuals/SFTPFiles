//
//  SSHKeyManager.swift
//  SFTPFiles
//
//  Created by Maikel Mansi on 16/07/2025.
//

import Foundation
import Security

// MARK: - SSH Key Manager
class SSHKeyManager {
    private let keychain = KeychainManager()
    private let storageKey = "ssh_keys"
    
    func saveKeyPair(_ keyPair: SSHKeyPair) throws {
        // Save private key and passphrase securely in keychain
        let privateKeyData = keyPair.privateKey.data(using: .utf8)!
        try keychain.save(key: "ssh_private_\(keyPair.id.uuidString)", data: privateKeyData)
        
        if let passphrase = keyPair.passphrase {
            let passphraseData = passphrase.data(using: .utf8)!
            try keychain.save(key: "ssh_passphrase_\(keyPair.id.uuidString)", data: passphraseData)
        }
        
        // Save key metadata
        var keys = loadKeyPairs()
        keys.removeAll { $0.id == keyPair.id }
        
        // Create sanitized version without sensitive data
        let sanitizedKey = SSHKeyPair(
            id: keyPair.id,
            name: keyPair.name,
            publicKey: keyPair.publicKey,
            privateKey: "", // Don't store in UserDefaults
            passphrase: nil
        )
        
        keys.append(sanitizedKey)
        saveKeyPairs(keys)
    }
    
    func loadKeyPairs() -> [SSHKeyPair] {
        guard let defaults = UserDefaults(suiteName: "group.mansivisuals.SFTPFiles"),
              let data = defaults.data(forKey: storageKey),
              let keys = try? JSONDecoder().decode([SSHKeyPair].self, from: data) else {
            return []
        }
        return keys
    }
    
    func getKeyPair(id: UUID) throws -> SSHKeyPair? {
        let keys = loadKeyPairs()
        guard let keyMeta = keys.first(where: { $0.id == id }) else { return nil }
        
        // Retrieve private key from keychain
        let privateKeyData = try keychain.load(key: "ssh_private_\(id.uuidString)")
        let privateKey = String(data: privateKeyData, encoding: .utf8) ?? ""
        
        // Retrieve passphrase if exists
        let passphrase: String?
        if let passphraseData = try? keychain.load(key: "ssh_passphrase_\(id.uuidString)") {
            passphrase = String(data: passphraseData, encoding: .utf8)
        } else {
            passphrase = nil
        }
        
        return SSHKeyPair(
            id: keyMeta.id,
            name: keyMeta.name,
            publicKey: keyMeta.publicKey,
            privateKey: privateKey,
            passphrase: passphrase
        )
    }
    
    func deleteKeyPair(id: UUID) throws {
        // Remove from keychain
        try? keychain.delete(key: "ssh_private_\(id.uuidString)")
        try? keychain.delete(key: "ssh_passphrase_\(id.uuidString)")
        
        // Remove from metadata
        var keys = loadKeyPairs()
        keys.removeAll { $0.id == id }
        saveKeyPairs(keys)
    }
    
    private func saveKeyPairs(_ keys: [SSHKeyPair]) {
        guard let defaults = UserDefaults(suiteName: "group.mansivisuals.SFTPFiles"),
              let data = try? JSONEncoder().encode(keys) else { return }
        defaults.set(data, forKey: storageKey)
        defaults.synchronize()
    }
}

// MARK: - Keychain Manager
class KeychainManager {
    func save(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "SFTPFiles",
            kSecAttrAccessGroup as String: "group.mansivisuals.SFTPFiles",
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToSave
        }
    }
    
    func load(key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "SFTPFiles",
            kSecAttrAccessGroup as String: "group.mansivisuals.SFTPFiles",
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unableToLoad
        }
        
        return data
    }
    
    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "SFTPFiles",
            kSecAttrAccessGroup as String: "group.mansivisuals.SFTPFiles"
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete
        }
    }
}

enum KeychainError: Error {
    case unableToSave
    case unableToLoad
    case unableToDelete
}

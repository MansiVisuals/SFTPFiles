//
//  KeychainService.swift
//  SFTPFiles
//
//  Created by Maikel Mansi on 28/07/2025.
//

import Foundation
import Security

class KeychainService {
    private let service = "com.mansi.sftpfiles"
    
    func store(password: String, for connectionId: UUID) {
        let data = password.data(using: .utf8)!
        let account = connectionId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessGroup as String: "group.mansi.SFTPFiles"
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("Successfully stored password for connection: \(account)")
        } else {
            print("Failed to store password in keychain: \(status) (\(SecCopyErrorMessageString(status, nil) ?? "Unknown error" as CFString))")
        }
    }
    
    func getPassword(for connectionId: UUID) -> String? {
        let account = connectionId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessGroup as String: "group.mansi.SFTPFiles"
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                print("Failed to retrieve password from keychain: \(status)")
            }
            return nil
        }
        
        return password
    }
    
    func deletePassword(for connectionId: UUID) {
        let account = connectionId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: "group.mansi.SFTPFiles"
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess {
            print("Successfully deleted password for connection: \(account)")
        } else if status != errSecItemNotFound {
            print("Failed to delete password from keychain: \(status)")
        }
    }
    
    func updatePassword(_ password: String, for connectionId: UUID) {
        // For keychain, it's simpler to delete and re-add
        deletePassword(for: connectionId)
        store(password: password, for: connectionId)
    }
    
    // MARK: - Private Key Storage (for SSH keys)
    
    func storePrivateKey(_ keyData: Data, for connectionId: UUID) {
        let account = "\(connectionId.uuidString)_key"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessGroup as String: "group.mansi.SFTPFiles"
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("Successfully stored private key for connection: \(connectionId)")
        } else {
            print("Failed to store private key in keychain: \(status)")
        }
    }
    
    func getPrivateKey(for connectionId: UUID) -> Data? {
        let account = "\(connectionId.uuidString)_key"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessGroup as String: "group.mansi.SFTPFiles"
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        
        return data
    }
    
    func deletePrivateKey(for connectionId: UUID) {
        let account = "\(connectionId.uuidString)_key"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: "group.mansi.SFTPFiles"
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
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
    
    // Use dynamic team identifier instead of hardcoded access group
    private var accessGroup: String {
        guard let teamIdentifier = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String else {
            // Fallback for development
            return "group.mansi.SFTPFiles"
        }
        return "\(teamIdentifier)group.mansi.SFTPFiles"
    }
    
    func store(password: String, for connectionId: UUID) {
        let data = password.data(using: .utf8)!
        let account = connectionId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("Successfully stored password for connection: \(account)")
        } else {
            let errorMessage = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            print("Failed to store password in keychain: \(status) - \(errorMessage)")
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
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                let errorMessage = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
                print("Failed to retrieve password from keychain: \(status) - \(errorMessage)")
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
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess {
            print("Successfully deleted password for connection: \(account)")
        } else if status != errSecItemNotFound {
            let errorMessage = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            print("Failed to delete password from keychain: \(status) - \(errorMessage)")
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
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("Successfully stored private key for connection: \(connectionId)")
        } else {
            let errorMessage = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            print("Failed to store private key in keychain: \(status) - \(errorMessage)")
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
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            if status != errSecItemNotFound {
                let errorMessage = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
                print("Failed to retrieve private key from keychain: \(status) - \(errorMessage)")
            }
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
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
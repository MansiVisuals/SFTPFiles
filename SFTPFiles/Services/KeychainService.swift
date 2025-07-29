//
//  KeychainService.swift
//  SFTPFiles
//
//  Created by Maikel Mansi on 28/07/2025.
//

import Foundation
import Security

class KeychainService {
    private let service = "group.com.mansi.sftpfiles"
    
    private var accessGroup: String {
        // Use the bundle identifier approach for keychain access group
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            let components = bundleIdentifier.components(separatedBy: ".")
            if components.count >= 3 {
                return "\(components[0]).\(components[1]).\(components[2])"
            }
        }
        return "group.com.mansi.sftpfiles"
    }
    
    func store(password: String, for connectionId: UUID) {
        let data = password.data(using: .utf8)!
        let account = connectionId.uuidString
        
        // Try without access group first (for simulator/development)
        let queryWithoutGroup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        
        // Delete existing items
        SecItemDelete(queryWithoutGroup as CFDictionary)
        
        let queryWithGroup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessGroup as String: accessGroup
        ]
        SecItemDelete(queryWithGroup as CFDictionary)
        
        // Try to add without access group first
        var status = SecItemAdd(queryWithoutGroup as CFDictionary, nil)
        
        if status != errSecSuccess {
            // If that fails, try with access group
            status = SecItemAdd(queryWithGroup as CFDictionary, nil)
        }
        
        if status == errSecSuccess {
            print("Successfully stored password for connection: \(account)")
        } else {
            print("Failed to store password in keychain: \(status)")
        }
    }
    
    func getPassword(for connectionId: UUID) -> String? {
        let account = connectionId.uuidString
        
        // Try without access group first (for simulator/development)
        let queryWithoutGroup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        var status = SecItemCopyMatching(queryWithoutGroup as CFDictionary, &result)
        
        // If that fails, try with access group
        if status != errSecSuccess {
            let queryWithGroup: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecAttrAccessGroup as String: accessGroup
            ]
            
            status = SecItemCopyMatching(queryWithGroup as CFDictionary, &result)
        }
        
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
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess {
            print("Successfully deleted password for connection: \(account)")
        } else if status != errSecItemNotFound {
            print("Failed to delete password from keychain: \(status)")
        }
    }
    
    func updatePassword(_ password: String, for connectionId: UUID) {
        deletePassword(for: connectionId)
        store(password: password, for: connectionId)
    }
    
    // MARK: - Private Key Storage
    
    func storePrivateKey(_ keyData: Data, for connectionId: UUID) {
        let account = "\(connectionId.uuidString)_key"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        SecItemDelete(query as CFDictionary)
        
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
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            if status != errSecItemNotFound {
                print("Failed to retrieve private key from keychain: \(status)")
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
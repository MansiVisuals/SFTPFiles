//
//  ExtensionSharedServices.swift
//  SFTPFilesFileProvider (File Provider Extension Only)
//
//  Created by Maikel Mansi on 28/07/2025.
//

import Foundation
import Security

// MARK: - Extension Persistence Service (Legacy - use SharedPersistenceService instead)

class ExtensionPersistenceService {
    private let userDefaults: UserDefaults?
    private let connectionsKey = "SavedSFTPConnections"
    private let connectionStatePrefix = "SFTPConnectionState_"

    init() {
        if let sharedDefaults = UserDefaults(suiteName: "group.com.mansi.sftpfiles") {
            self.userDefaults = sharedDefaults
            print("[ExtensionPersistenceService] Using shared UserDefaults")
        } else {
            print("[ExtensionPersistenceService] Fallback to standard UserDefaults")
            self.userDefaults = UserDefaults.standard
        }
    }

    func loadConnections() -> [SFTPConnection] {
        // Delegate to SharedPersistenceService for consistency
        return SharedPersistenceService.shared.loadConnections()
    }

    func getConnection(withId id: UUID) -> SFTPConnection? {
        return SharedPersistenceService.shared.getConnection(withId: id)
    }

    func setConnectionState(_ state: ConnectionState, for id: UUID) {
        SharedPersistenceService.shared.setConnectionState(state, for: id)
    }

    func getConnectionState(for id: UUID) -> ConnectionState {
        return SharedPersistenceService.shared.getConnectionState(for: id)
    }
}

// MARK: - Extension Keychain Service (Legacy - use SharedKeychainService instead)

class ExtensionKeychainService {
    private let service = "group.com.mansi.sftpfiles"
    
    private var accessGroup: String {
        return "group.com.mansi.sftpfiles"
    }
    
    func getPassword(for connectionId: UUID) -> String? {
        // Delegate to SharedKeychainService for consistency
        return SharedKeychainService().getPassword(for: connectionId)
    }
}
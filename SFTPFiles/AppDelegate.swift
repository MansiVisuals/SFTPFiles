//
//  AppDelegate.swift
//  SFTPFiles
//
//  Created by Maikel Mansi on 29/07/2025.
//

import UIKit
import FileProvider

class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Register the correct File Provider domain only
        registerFileProviderDomain()
        return true
    }
    
    // MARK: UISceneSession Lifecycle
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    
    private func registerFileProviderDomain() {
        // Use a domain identifier that matches the app group pattern
        let domainIdentifier = NSFileProviderDomainIdentifier(rawValue: "group.com.mansi.sftpfiles")
        let domain = NSFileProviderDomain(
            identifier: domainIdentifier,
            displayName: "SFTP Files"
        )
        
        print("Registering File Provider domain with identifier: \(domainIdentifier.rawValue)")
        
        NSFileProviderManager.getDomainsWithCompletionHandler { domains, error in
            if let error = error {
                print("Error getting domains: \(error)")
                return
            }
            
            print("Current domains after cleanup: \(domains.map { "\($0.displayName) (\($0.identifier.rawValue))" })")
            
            let existingDomain = domains.first { $0.identifier == domainIdentifier }
            if existingDomain != nil {
                print("Correct File provider domain already exists")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.signalEnumeration()
                }
                return
            }
            
            NSFileProviderManager.add(domain) { error in
                if let error = error {
                    print("Failed to add file provider domain: \(error)")
                } else {
                    print("Successfully registered file provider domain")
                }
                
                // Always try to signal enumeration after domain registration
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.signalEnumeration()
                }
            }
        }
    }
    
    private func signalEnumeration() {
        let domainIdentifier = NSFileProviderDomainIdentifier(rawValue: "group.com.mansi.sftpfiles")
        let domain = NSFileProviderDomain(identifier: domainIdentifier, displayName: "SFTP Files")
        
        guard let manager = NSFileProviderManager(for: domain) else {
            print("CRITICAL ERROR: Failed to create NSFileProviderManager")
            return
        }
        
        print("Signaling enumeration for root container")
        
        // Test if we can get the domain back
        NSFileProviderManager.getDomainsWithCompletionHandler { domains, error in
            if let error = error {
                print("Error getting domains during signal: \(error)")
            } else {
                print("Available domains during signal: \(domains.map { $0.displayName })")
                let ourDomain = domains.first { $0.identifier.rawValue == "group.com.mansi.sftpfiles" }
                if let ourDomain = ourDomain {
                    print("Found our domain: \(ourDomain.displayName)")
                } else {
                    print("CRITICAL ERROR: Our domain not found in available domains!")
                }
            }
            
            // Try to get extension info
            print("=== DIAGNOSTIC: Checking extension configuration ===")
            if let mainBundle = Bundle.main.bundleIdentifier {
                print("Main app bundle ID: \(mainBundle)")
                
                // Expected extension bundle ID
                let expectedExtensionBundleId = "\(mainBundle).SFTPFilesFileProvider"
                print("Expected extension bundle ID: \(expectedExtensionBundleId)")
                
                // Check if extension bundle exists
                if let extensionURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent("SFTPFilesFileProvider.appex") {
                    print("Extension URL: \(extensionURL)")
                    let extensionExists = FileManager.default.fileExists(atPath: extensionURL.path)
                    print("Extension exists: \(extensionExists)")
                    
                    if extensionExists {
                        if let extensionBundle = Bundle(url: extensionURL) {
                            print("Extension bundle ID: \(extensionBundle.bundleIdentifier ?? "unknown")")
                            if let infoPlist = extensionBundle.infoDictionary {
                                print("Extension Info.plist keys: \(infoPlist.keys)")
                                if let nsExtension = infoPlist["NSExtension"] as? [String: Any] {
                                    print("NSExtension config: \(nsExtension)")
                                }
                            }
                        } else {
                            print("CRITICAL ERROR: Cannot load extension bundle")
                        }
                    }
                }
            }
        }
        
        manager.signalEnumerator(for: .rootContainer) { error in
            if let error = error {
                print("Failed to signal enumeration: \(error)")
            } else {
                print("Successfully signaled enumeration")
            }
        }
        
        manager.signalEnumerator(for: .workingSet) { error in
            if let error = error {
                print("Failed to signal working set: \(error)")
            } else {
                print("Successfully signaled working set")
            }
        }
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.signalEnumeration()
        }
    }
    
    // MARK: - Manual Domain Management (for debugging)
    
    func clearAllAppData() {
        let alert = UIAlertController(
            title: "Clear All Data",
            message: "This will remove all File Provider domains, delete all SFTP connections, and clear all app data. This cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear All", style: .destructive) { _ in
            self.performClearAllData()
        })
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func performClearAllData() {
        print("=== Starting complete app data cleanup ===")
        
        let group = DispatchGroup()
        
        // 1. Remove all File Provider domains
        group.enter()
        NSFileProviderManager.getDomainsWithCompletionHandler { domains, error in
            if let error = error {
                print("Error getting domains for complete removal: \(error)")
                group.leave()
                return
            }
            
            print("Removing all \(domains.count) File Provider domains...")
            
            if domains.isEmpty {
                print("No domains to remove")
                group.leave()
                return
            }
            
            let domainGroup = DispatchGroup()
            
            for domain in domains {
                domainGroup.enter()
                print("Removing domain: \(domain.displayName) (\(domain.identifier.rawValue))")
                NSFileProviderManager.remove(domain) { removeError in
                    if let removeError = removeError {
                        print("Error removing domain \(domain.identifier.rawValue): \(removeError)")
                    } else {
                        print("Successfully removed domain: \(domain.identifier.rawValue)")
                    }
                    domainGroup.leave()
                }
            }
            
            domainGroup.notify(queue: .main) {
                print("All File Provider domains removed")
                group.leave()
            }
        }
        
        // 2. Clear all UserDefaults data
        group.enter()
        DispatchQueue.global(qos: .background).async {
            print("Clearing UserDefaults data...")
            
            // Clear standard UserDefaults
            if let bundleId = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleId)
                UserDefaults.standard.synchronize()
                print("Cleared standard UserDefaults")
            }
            
            // Clear shared UserDefaults
            if let sharedDefaults = UserDefaults(suiteName: "group.com.mansi.sftpfiles") {
                sharedDefaults.dictionaryRepresentation().keys.forEach { key in
                    sharedDefaults.removeObject(forKey: key)
                }
                sharedDefaults.synchronize()
                print("Cleared shared UserDefaults")
            }
            
            group.leave()
        }
        
        // 3. Clear all Keychain data
        group.enter()
        DispatchQueue.global(qos: .background).async {
            print("Clearing Keychain data...")
            
            // Clear all keychain items for our service
            let service = "group.com.mansi.sftpfiles"
            let accessGroup = "group.com.mansi.sftpfiles"
            
            let queries: [[String: Any]] = [
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccessGroup as String: accessGroup
                ],
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service
                ]
            ]
            
            for query in queries {
                let status = SecItemDelete(query as CFDictionary)
                if status == errSecSuccess {
                    print("Successfully cleared keychain items")
                } else if status == errSecItemNotFound {
                    print("No keychain items found to clear")
                } else {
                    print("Error clearing keychain: \(status)")
                }
            }
            
            group.leave()
        }
        
        // 4. Clear app cache and temporary files
        group.enter()
        DispatchQueue.global(qos: .background).async {
            print("Clearing cache and temporary files...")
            
            let fileManager = FileManager.default
            
            // Clear caches directory
            if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
                do {
                    let cacheContents = try fileManager.contentsOfDirectory(at: cachesURL, includingPropertiesForKeys: nil)
                    for fileURL in cacheContents {
                        try fileManager.removeItem(at: fileURL)
                    }
                    print("Cleared cache directory")
                } catch {
                    print("Error clearing cache: \(error)")
                }
            }
            
            // Clear FileProvider working directory
            if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fileProviderDir = documentsURL.appendingPathComponent("FileProvider")
                if fileManager.fileExists(atPath: fileProviderDir.path) {
                    do {
                        try fileManager.removeItem(at: fileProviderDir)
                        print("Cleared FileProvider directory")
                    } catch {
                        print("Error clearing FileProvider directory: \(error)")
                    }
                }
            }
            
            group.leave()
        }
        
        // 5. Show completion and restart suggestion
        group.notify(queue: .main) {
            print("=== Complete app data cleanup finished ===")
            
            let completionAlert = UIAlertController(
                title: "Cleanup Complete",
                message: "All app data has been cleared. For best results, please force-quit and restart the app.",
                preferredStyle: .alert
            )
            
            completionAlert.addAction(UIAlertAction(title: "OK", style: .default))
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {
                rootViewController.present(completionAlert, animated: true)
            }
        }
    }
    
    func removeAllFileProviderDomains() {
        NSFileProviderManager.getDomainsWithCompletionHandler { domains, error in
            if let error = error {
                print("Error getting domains for removal: \(error)")
                return
            }
            
            print("Removing all \(domains.count) File Provider domains...")
            let group = DispatchGroup()
            
            for domain in domains {
                group.enter()
                print("Removing domain: \(domain.displayName) (\(domain.identifier.rawValue))")
                NSFileProviderManager.remove(domain) { removeError in
                    if let removeError = removeError {
                        print("Error removing domain \(domain.identifier.rawValue): \(removeError)")
                    } else {
                        print("Successfully removed domain: \(domain.identifier.rawValue)")
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                print("All File Provider domains have been removed")
            }
        }
    }
}
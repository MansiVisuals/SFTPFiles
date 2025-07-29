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
        
        // Register the main File Provider domain
        registerFileProviderDomain()
        
        return true
    }
    
    // MARK: UISceneSession Lifecycle
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    // MARK: - File Provider Domain Management
    
    private func registerFileProviderDomain() {
        let domainIdentifier = NSFileProviderDomainIdentifier(rawValue: "com.mansi.sftpfiles.provider")
        let domain = NSFileProviderDomain(
            identifier: domainIdentifier,
            displayName: "SFTP Files"
        )
        
        // Check if domain already exists
        NSFileProviderManager.getDomainsWithCompletionHandler { domains, error in
            if let error = error {
                print("Error getting domains: \(error)")
                return
            }
            
            let existingDomain = domains.first { $0.identifier == domainIdentifier }
            if existingDomain != nil {
                print("File provider domain already exists")
                // Signal initial enumeration for existing domain
                self.signalInitialEnumeration(for: domain)
                return
            }
            
            // Add the domain
            NSFileProviderManager.add(domain) { error in
                if let error = error {
                    print("Failed to add file provider domain: \(error)")
                } else {
                    print("Successfully registered file provider domain")
                    
                    // Signal initial enumeration after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.signalInitialEnumeration(for: domain)
                    }
                }
            }
        }
    }
    
    private func signalInitialEnumeration(for domain: NSFileProviderDomain) {
        guard let manager = NSFileProviderManager(for: domain) else {
            print("Failed to create NSFileProviderManager for initial enumeration")
            return
        }
        
        print("Signaling initial enumeration for domain: \(domain.identifier.rawValue)")
        
        manager.signalEnumerator(for: .rootContainer) { error in
            if let error = error {
                print("Failed to signal initial enumeration: \(error)")
            } else {
                print("Successfully signaled initial enumeration")
            }
        }
        
        // Also signal working set to ensure Files app sees the provider
        manager.signalEnumerator(for: .workingSet) { error in
            if let error = error {
                print("Failed to signal working set enumeration: \(error)")
            } else {
                print("Successfully signaled working set enumeration")
            }
        }
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Refresh the file provider when app comes to foreground
        refreshFileProvider()
    }
    
    private func refreshFileProvider() {
        let domainIdentifier = NSFileProviderDomainIdentifier(rawValue: "com.mansi.sftpfiles.provider")
        let domain = NSFileProviderDomain(identifier: domainIdentifier, displayName: "SFTP Files")
        
        guard let manager = NSFileProviderManager(for: domain) else { return }
        
        manager.signalEnumerator(for: .rootContainer) { error in
            if let error = error {
                print("Failed to refresh file provider: \(error)")
            } else {
                print("Successfully refreshed file provider")
            }
        }
    }
}

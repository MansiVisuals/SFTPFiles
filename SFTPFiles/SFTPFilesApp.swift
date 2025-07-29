//
//  SFTPFilesApp.swift
//  SFTPFiles
//
//  Created by Maikel Mansi on 29/07/2025.
//

import SwiftUI
import FileProvider

@main
struct SFTPFilesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    registerFileProviderDomain()
                }
        }
    }
    
    // MARK: - File Provider Domain Registration
    
    private func registerFileProviderDomain() {
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: "com.mansi.sftpfiles.provider"),
            displayName: "SFTP Files"
        )
        
        NSFileProviderManager.add(domain) { error in
            if let error = error {
                print("Failed to add file provider domain: \(error)")
            } else {
                print("Successfully registered file provider domain")
            }
        }
    }
}
//
//  SettingsView.swift
//  SFTPFiles
//
//  Created by Maikel Mansi on 29/07/2025.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("autoConnectEnabled") private var autoConnectEnabled = true
    @AppStorage("pollingInterval") private var pollingInterval = 30.0
    @AppStorage("downloadCacheSize") private var downloadCacheSize = 100.0
    @AppStorage("enableNotifications") private var enableNotifications = true
    
    var body: some View {
        Form {
            Section("Connection") {
                Toggle("Auto-connect on startup", isOn: $autoConnectEnabled)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Polling Interval: \(Int(pollingInterval)) seconds")
                    Slider(value: $pollingInterval, in: 10...300, step: 10) {
                        Text("Polling Interval")
                    }
                    Text("How often to check for remote file changes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Storage") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Download Cache: \(Int(downloadCacheSize)) MB")
                    Slider(value: $downloadCacheSize, in: 50...1000, step: 50) {
                        Text("Cache Size")
                    }
                    Text("Maximum size for cached downloaded files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button("Clear Cache") {
                    clearCache()
                }
                .foregroundColor(.red)
            }
            
            Section("Notifications") {
                Toggle("Enable notifications", isOn: $enableNotifications)
                Text("Get notified about sync errors and connection issues")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Build")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func clearCache() {
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let cacheDir = cacheDirectory else { return }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
            for fileURL in contents {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            print("Failed to clear cache: \(error)")
        }
    }
}

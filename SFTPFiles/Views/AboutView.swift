//
//  AboutView.swift
//  SFTPFiles
//
//  Created by Maikel Mansi on 29/07/2025.
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                Image(systemName: "server.rack")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("SFTP Files")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Seamless SFTP integration with iOS Files")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "folder", title: "Native Integration", description: "Works directly with iOS Files app")
                FeatureRow(icon: "lock.shield", title: "Secure", description: "Passwords stored in Keychain")
                FeatureRow(icon: "arrow.clockwise", title: "Auto-sync", description: "Background polling for changes")
                FeatureRow(icon: "gear", title: "Easy Setup", description: "Simple connection management")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            Spacer()
            
            VStack(spacing: 8) {
                Text("Built with MFT SFTP Framework")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Link("GitHub Repository", destination: URL(string: "https://github.com/mplpl/mft")!)
                    .font(.caption)
            }
        }
        .padding()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

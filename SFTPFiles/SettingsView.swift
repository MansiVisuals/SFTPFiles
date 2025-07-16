
import SwiftUI
import UIKit


// Enhanced Settings View - This replaces your existing SettingsView
struct EnhancedSettingsView: View {
    @ObservedObject var viewModel: SFTPConnectionViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var showingClearAlert = false
    @State private var isClearing = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background consistent with main view
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemBackground),
                        Color(.systemBackground).opacity(0.95),
                        Color.accentColor.opacity(0.03)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // App Information Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "info.circle")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 32, height: 32)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("App Information")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text("About SFTPFiles")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            
                            VStack(spacing: 16) {
                                // App Icon and Name
                                HStack(spacing: 16) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.accentColor.opacity(0.1))
                                            .frame(width: 60, height: 60)
                                        
                                        Image(systemName: "externaldrive.badge.plus")
                                            .font(.title)
                                            .foregroundColor(.accentColor)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("SFTPFiles")
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.primary)
                                        
                                        Text("SFTP File Provider for Files App")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                
                                // Statistics
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Connection Status")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    
                                    // Precompute statistics to help the compiler
                                    let totalConnections = viewModel.connections.count
                                    let connectedCount = viewModel.connections.filter { $0.status.isHealthy }.count
                                    let disconnectedCount = viewModel.connections.filter { !$0.status.isHealthy && $0.status != .unknown && $0.status != .checking }.count
                                    let checkingCount = viewModel.connections.filter { $0.status == .checking }.count

                                    HStack(spacing: 20) {
                                        VStack(spacing: 4) {
                                            Text("\(totalConnections)")
                                                .font(.title2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.primary)
                                            Text("Total")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        VStack(spacing: 4) {
                                            Text("\(connectedCount)")
                                                .font(.title2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.green)
                                            Text("Connected")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        VStack(spacing: 4) {
                                            Text("\(disconnectedCount)")
                                                .font(.title2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.red)
                                            Text("Disconnected")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        VStack(spacing: 4) {
                                            Text("\(checkingCount)")
                                                .font(.title2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.blue)
                                            Text("Checking")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 2)
                        )
                        .padding(.horizontal, 16)
                        
                        
                        // Data Management Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "externaldrive.badge.xmark")
                                    .font(.title2)
                                    .foregroundColor(.red)
                                    .frame(width: 32, height: 32)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Data Management")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text("Manage your app data")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            
                            VStack(spacing: 16) {
                                // Clear Data Info
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle")
                                            .font(.title3)
                                            .foregroundColor(.orange)
                                        
                                        Text("Clear All Data")
                                            .font(.body)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                    }
                                    
                                    Text("This will permanently remove all SFTP connections and clear all app data. Your connections will be removed from the Files app and this action cannot be undone.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.horizontal, 20)
                                
                                // Clear Button
                                Button(action: {
                                    if !isClearing {
                                        showingClearAlert = true
                                    }
                                }) {
                                    HStack(spacing: 12) {
                                        if isClearing {
                                            ProgressView()
                                                .scaleEffect(0.9)
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        } else {
                                            Image(systemName: "trash.fill")
                                                .font(.system(size: 16, weight: .semibold))
                                        }
                                        
                                        Text(isClearing ? "Clearing Data..." : "Clear All Data")
                                            .font(.body)
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(isClearing ? Color.red.opacity(0.5) : Color.red)
                                    )
                                    .shadow(color: Color.red.opacity(0.3), radius: 4, x: 0, y: 2)
                                }
                                .disabled(isClearing)
                                .buttonStyle(BorderlessButtonStyle())
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 2)
                        )
                        .padding(.horizontal, 16)
                        
                        // Help Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "questionmark.circle")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 32, height: 32)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Help & Support")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text("Tips for using SFTPFiles")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            
                            // Help tips removed (InfoRow not defined)
                        }
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 2)
                        )
                        .padding(.horizontal, 16)
                        
                        // Bottom padding
                        Color.clear.frame(height: 20)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Clear All Data", isPresented: $showingClearAlert) {
                Button("Cancel", role: .cancel) { 
                    showingClearAlert = false
                }
                Button("Clear All", role: .destructive) {
                    showingClearAlert = false
                    clearAllData()
                }
            } message: {
                Text("This will permanently remove all SFTP connections and clear all app data. This action cannot be undone.")
            }
        }
    }
    private func clearAllData() {
        isClearing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Task {
                await viewModel.clearAllConfigurations()
                DispatchQueue.main.async {
                    self.isClearing = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

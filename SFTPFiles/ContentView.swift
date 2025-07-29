//
//  ContentView.swift
//  SFTPFiles
//
//  Created by Maikel Mansi on 28/07/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var connectionManager = SFTPConnectionManager()
    @State private var showingAddConnection = false
    
    var body: some View {
        NavigationView {
            List {
                // Header Section
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "externaldrive.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                        
                        Text("SFTP Files")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Connect to SFTP servers and access your files in the Files app")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .listRowBackground(Color(.systemGroupedBackground))
                .listRowInsets(EdgeInsets())
                
                // Connections Section
                if !connectionManager.connections.isEmpty {
                    Section("Connections") {
                        ForEach(connectionManager.connections) { connection in
                            NavigationLink(destination: ConnectionDetailView(connection: connection, connectionManager: connectionManager)) {
                                SettingsConnectionRow(connection: connection)
                            }
                        }
                        .onDelete(perform: deleteConnections)
                    }
                }
                
                // Add Connection Section
                Section {
                    Button(action: {
                        showingAddConnection = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                            
                            Text("Add SFTP Connection")
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                // Empty State
                if connectionManager.connections.isEmpty {
                    Section {
                        VStack(spacing: 16) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            
                            Text("No Connections")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Add your first SFTP server connection to get started. Connections will appear in the Files app.")  
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                    .listRowBackground(Color(.systemGroupedBackground))
                    .listRowInsets(EdgeInsets())
                }
                
                // Settings Section
                Section {
                    NavigationLink(destination: SettingsView()) {
                        HStack {
                            Image(systemName: "gear")
                                .foregroundColor(.gray)
                                .font(.title3)
                                .frame(width: 24)
                            
                            Text("Settings")
                        }
                    }
                    
                    NavigationLink(destination: AboutView()) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.gray)
                                .font(.title3)
                                .frame(width: 24)
                            
                            Text("About")
                        }
                    }
                }
                
                // Instructions Section
                Section(footer: footerView) {
                    // Empty section for footer only
                }
            }
            .navigationTitle("SFTP Files")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await connectionManager.reconnectAllConnections()
            }
        }
        .sheet(isPresented: $showingAddConnection) {
            AddConnectionView()
                .environmentObject(connectionManager)
        }
        .onAppear {
            connectionManager.loadConnections()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Refresh connections when app becomes active
            connectionManager.loadConnections() // Sync states first
            Task {
                await connectionManager.reconnectAllConnections()
            }
        }
        // Add a timer to periodically sync connection states from shared storage
        .onReceive(Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()) { _ in
            // Sync connection states without reconnecting - use singleton to avoid spam
            let sharedService = SharedPersistenceService.shared
            for i in connectionManager.connections.indices {
                let currentState = sharedService.getConnectionState(for: connectionManager.connections[i].id)
                if connectionManager.connections[i].state != currentState {
                    print("UI: Syncing state for \(connectionManager.connections[i].name): \(connectionManager.connections[i].state) -> \(currentState)")
                    connectionManager.connections[i].state = currentState
                }
            }
        }
    }
    
    private var footerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to Access Your Files:")
                .font(.footnote)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                instructionRow(number: "1", text: "Add your SFTP server connections above")
                instructionRow(number: "2", text: "Open the Files app on your device")
                instructionRow(number: "3", text: "Look for 'SFTP Files' in the Browse section")
                instructionRow(number: "4", text: "Your servers will appear as folders")
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.blue))
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func deleteConnections(offsets: IndexSet) {
        connectionManager.deleteConnections(at: offsets)
    }
}

struct SettingsConnectionRow: View {
    let connection: SFTPConnection
    
    var body: some View {
        HStack {
            // Icon
            Image(systemName: connectionIcon)
                .foregroundColor(iconColor)
                .font(.title3)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Text("\(connection.username)@\(connection.hostname)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                // Status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    
                    Text(connection.state.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if connection.useKeyAuth {
                    Text("Key Auth")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    private var connectionIcon: String {
        switch connection.state {
        case .connected:
            return "externaldrive.fill.badge.checkmark"
        case .connecting:
            return "externaldrive.badge.timemachine"
        case .error:
            return "externaldrive.badge.xmark"
        case .disconnected:
            return "externaldrive"
        }
    }
    
    private var iconColor: Color {
        switch connection.state {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .error:
            return .red
        case .disconnected:
            return .blue
        }
    }
    
    private var statusColor: Color {
        switch connection.state {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .error:
            return .red
        case .disconnected:
            return .gray
        }
    }
}

#Preview {
    ContentView()
}
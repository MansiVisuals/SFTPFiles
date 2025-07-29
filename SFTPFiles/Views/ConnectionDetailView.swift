//
//  ConnectionDetailView.swift
//  SFTPFiles
//
//  Created by Maikel Mansi on 28/07/2025.
//

import SwiftUI

struct ConnectionDetailView: View {
    let connection: SFTPConnection
    @ObservedObject var connectionManager: SFTPConnectionManager
    @State private var showingDeleteAlert = false
    @State private var isTestingConnection = false
    @State private var testResult: TestResult?
    
    enum TestResult {
        case success
        case failure(String)
    }
    
    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    // Status indicator with icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(statusColor.opacity(0.1))
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: statusIcon)
                            .font(.title2)
                            .foregroundColor(statusColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(connection.state.displayName)
                            .font(.headline)
                            .foregroundColor(statusColor)
                        
                        if connection.useKeyAuth {
                            Label("Key Authentication", systemImage: "key.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Label("Password Authentication", systemImage: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            
            Section("Server Information") {
                DetailRow(label: "Name", value: connection.name, icon: "server.rack")
                DetailRow(label: "Hostname", value: connection.hostname, icon: "globe")
                DetailRow(label: "Port", value: String(connection.port), icon: "number")
                DetailRow(label: "Username", value: connection.username, icon: "person.circle")
                
                if connection.useKeyAuth, let keyPath = connection.privateKeyPath {
                    DetailRow(label: "Private Key", value: keyPath, icon: "key")
                }
            }
            
            Section("Connection Settings") {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    
                    Text("Auto Connect")
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(connection.autoConnect ? "Enabled" : "Disabled")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }
            
            Section("Connection History") {
                if let lastConnected = connection.lastConnected {
                    DetailRow(
                        label: "Last Connected", 
                        value: lastConnected.timeAgoDisplay(), 
                        icon: "clock"
                    )
                } else {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        
                        Text("Last Connected")
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("Never")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                
                DetailRow(
                    label: "Created", 
                    value: DateFormatter.medium.string(from: connection.createdDate), 
                    icon: "calendar"
                )
            }
            
            Section("Actions") {
                Button(action: testConnection) {
                    HStack {
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Testing Connection...")
                        } else {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.blue)
                            Text("Test Connection")
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                        
                        if let result = testResult {
                            switch result {
                            case .success:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            case .failure:
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                .disabled(isTestingConnection)
                
                if case .failure(let error) = testResult {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }
            }
            
            Section {
                Button(action: {
                    showingDeleteAlert = true
                }) {
                    HStack {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                        
                        Text("Delete Connection")
                            .foregroundColor(.red)
                        
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle(connection.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Connection", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteConnection()
            }
        } message: {
            Text("Are you sure you want to delete this connection? This action cannot be undone and will remove all associated data.")
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
    
    private var statusIcon: String {
        switch connection.state {
        case .connected:
            return "checkmark.circle.fill"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .error:
            return "exclamationmark.triangle.fill"
        case .disconnected:
            return "circle"
        }
    }
    
    private func testConnection() {
        isTestingConnection = true
        testResult = nil
        
        Task {
            // Get the password from keychain for testing
            let keychainService = KeychainService()
            let password = keychainService.getPassword(for: connection.id)
            
            let success = await SFTPService.shared.testConnection(
                connection: connection,
                password: password
            )
            
            await MainActor.run {
                isTestingConnection = false
                testResult = success ? .success : .failure("Failed to connect to server. Please check your credentials and network connection.")
                
                // Update the connection state in the manager
                if let index = connectionManager.connections.firstIndex(where: { $0.id == connection.id }) {
                    connectionManager.connections[index].state = success ? .connected : .error
                    if success {
                        connectionManager.connections[index].lastConnected = Date()
                    }
                }
            }
        }
    }
    
    private func deleteConnection() {
        if let index = connectionManager.connections.firstIndex(where: { $0.id == connection.id }) {
            connectionManager.deleteConnections(at: IndexSet(integer: index))
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            Text(label)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }
}

extension DateFormatter {
    static let medium: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

#Preview {
    NavigationView {
        ConnectionDetailView(
            connection: SFTPConnection(
                name: "My Server",
                hostname: "example.com",
                port: 22,
                username: "user",
                useKeyAuth: false,
                privateKeyPath: nil
            ),
            connectionManager: SFTPConnectionManager()
        )
    }
}
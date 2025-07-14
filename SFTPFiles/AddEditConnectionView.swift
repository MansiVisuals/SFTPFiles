import SwiftUI
import mft

struct AddEditConnectionView: View {
    @ObservedObject var viewModel: SFTPConnectionViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var remotePath: String = ""
    @State private var status: ConnectionStatus = .unknown
    @State private var isTesting = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isMonitoringEnabled = true
    
    var connection: SFTPConnection? = nil
    var isEditing: Bool { connection != nil }

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
                        // Connection Details Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "externaldrive.badge.plus")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 32, height: 32)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Connection Details")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text("Configure your SFTP server connection")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            
                            VStack(spacing: 16) {
                                // Connection Name
                                CustomInputField(
                                    title: "Connection Name",
                                    text: $name,
                                    placeholder: "My SFTP Server",
                                    icon: "tag"
                                )
                                
                                // Host and Port Row
                                HStack(spacing: 12) {
                                    CustomInputField(
                                        title: "Host",
                                        text: $host,
                                        placeholder: "server.example.com",
                                        icon: "server.rack",
                                        isRequired: true
                                    )
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    
                                    CustomInputField(
                                        title: "Port",
                                        text: $port,
                                        placeholder: "22",
                                        icon: "number",
                                        keyboardType: .numberPad
                                    )
                                    .frame(maxWidth: 100)
                                }
                                
                                // Username
                                CustomInputField(
                                    title: "Username",
                                    text: $username,
                                    placeholder: "username",
                                    icon: "person.circle",
                                    isRequired: true
                                )
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                
                                // Password
                                CustomSecureField(
                                    title: "Password",
                                    text: $password,
                                    placeholder: "••••••••",
                                    icon: "lock"
                                )
                                
                                // Remote Path
                                CustomInputField(
                                    title: "Remote Path",
                                    text: $remotePath,
                                    placeholder: "/home/user",
                                    icon: "folder"
                                )
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                
                                // Monitoring Toggle
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Connection Monitoring")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    HStack {
                                        HStack(spacing: 12) {
                                            Image(systemName: "wifi.circle")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(.secondary)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Enable automatic monitoring")
                                                    .font(.subheadline)
                                                    .foregroundColor(.primary)
                                                Text("Periodically check connection status")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Toggle("", isOn: $isMonitoringEnabled)
                                            .labelsHidden()
                                            .disabled(viewModel.pollingManager.backgroundRefreshStatus != .available)
                                            .opacity(viewModel.pollingManager.backgroundRefreshStatus != .available ? 0.5 : 1.0)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.systemGray6))
                                    )
                                    if viewModel.pollingManager.backgroundRefreshStatus != .available {
                                        Text("Background App Refresh is disabled. Monitoring cannot be enabled.")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                            .padding(.top, 4)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 2)
                        )
                        .padding(.horizontal, 16)
                        
                        // Connection Status Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "wifi.circle")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 32, height: 32)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Connection Status")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text(isEditing ? "Test your connection before saving" : "Test connection to add (required)")
                                        .font(.subheadline)
                                        .foregroundColor(isEditing ? .secondary : .orange)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            
                            VStack(spacing: 16) {
                                // Status Display
                                HStack(spacing: 12) {
                                    Image(systemName: statusIcon)
                                        .font(.title2)
                                        .foregroundColor(statusColor)
                                        .frame(width: 32, height: 32)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Status")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.secondary)
                                        
                                        Text(status.displayName)
                                            .font(.body)
                                            .fontWeight(.semibold)
                                            .foregroundColor(statusColor)
                                    }
                                    
                                    Spacer()
                                    
                                    // Show required indicator for new connections
                                    if !isEditing && !status.isHealthy {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("Required")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.orange)
                                            
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                
                                // Test Button
                                Button(action: testConnection) {
                                    HStack(spacing: 12) {
                                        if isTesting {
                                            ProgressView()
                                                .scaleEffect(0.9)
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        } else {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                                .font(.system(size: 16, weight: .semibold))
                                        }
                                        
                                        Text(isTesting ? "Testing Connection..." : "Test Connection")
                                            .font(.body)
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(host.isEmpty || username.isEmpty || isTesting ? 
                                                  Color.accentColor.opacity(0.5) : Color.accentColor)
                                    )
                                    .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
                                }
                                .disabled(host.isEmpty || username.isEmpty || isTesting)
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
                        
                        // Info Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "info.circle")
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                                
                                Text("How it works")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                InfoRow(
                                    icon: "folder.badge.plus",
                                    title: "Files App Integration",
                                    description: "Your SFTP server will appear under 'Locations' in the Files app"
                                )
                                
                                InfoRow(
                                    icon: "arrow.up.right.square",
                                    title: "Remote Path",
                                    description: "Specify the initial directory to browse (optional)"
                                )
                                
                                InfoRow(
                                    icon: "checkmark.shield",
                                    title: "Test Connection",
                                    description: "Always test your connection before saving"
                                )
                            }
                        }
                        .padding(.horizontal, 20)
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
            .navigationTitle(isEditing ? "Edit Connection" : "Add Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        saveConnection()
                    }
                    .disabled(host.isEmpty || username.isEmpty || (!isEditing && !status.isHealthy))
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert("Connection Test", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
        .onAppear {
            if let connection = connection {
                name = connection.name
                host = connection.host
                port = connection.port != nil ? String(connection.port!) : ""
                username = connection.username
                password = connection.password
                remotePath = connection.remotePath
                status = connection.status
                isMonitoringEnabled = connection.isPollingEnabled
            }
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .connected, .valid: return .green
        case .disconnected, .invalid, .error: return .red
        case .checking: return .blue
        case .timeout: return .orange
        case .unknown: return .gray
        }
    }
    
    private var statusIcon: String {
        switch status {
        case .connected, .valid: return "checkmark.circle.fill"
        case .disconnected, .invalid, .error: return "xmark.octagon.fill"
        case .checking: return "arrow.triangle.2.circlepath"
        case .timeout: return "clock.badge.exclamationmark"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private func testConnection() {
        isTesting = true
        status = .checking
        
        let portInt = port.isEmpty ? nil : Int(port)
        let testConn = SFTPConnection(
            name: name.isEmpty ? host : name,
            host: host,
            port: portInt,
            username: username,
            password: password,
            remotePath: remotePath
        )
        
        viewModel.testConnection(testConn) { result in
            status = result
            isTesting = false
            
            switch result {
            case .connected, .valid:
                alertMessage = "Connection successful! You can now add this connection."
            case .disconnected, .invalid, .error:
                alertMessage = "Connection failed. Please check your credentials and try again."
            case .timeout:
                alertMessage = "Connection timed out. Please check your server address and try again."
            case .unknown:
                alertMessage = "Unknown error occurred during connection test."
            case .checking:
                alertMessage = "Still checking connection..."
            }
            showingAlert = true
        }
    }
    
    private func saveConnection() {
        guard !host.isEmpty, !username.isEmpty else { return }
        
        // For new connections, require a valid test
        if !isEditing && !status.isHealthy {
            alertMessage = "Please test the connection and ensure it's valid before adding."
            showingAlert = true
            return
        }
        
        let portInt = port.isEmpty ? nil : Int(port)
        var newConnection = SFTPConnection(
            id: connection?.id ?? UUID(),
            name: name.isEmpty ? host : name,
            host: host,
            port: portInt,
            username: username,
            password: password,
            remotePath: remotePath
        )
        newConnection.isPollingEnabled = isMonitoringEnabled
        newConnection.status = status
        
        if isEditing {
            viewModel.updateConnection(newConnection)
        } else {
            viewModel.addConnection(newConnection)
        }
        
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - Custom Input Components

struct CustomInputField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let icon: String
    var isRequired: Bool = false
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                if isRequired {
                    Text("*")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
            }
            
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 20, height: 20)
                
                TextField(placeholder, text: $text)
                    .font(.body)
                    .textFieldStyle(PlainTextFieldStyle())
                    .keyboardType(keyboardType)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(text.isEmpty && isRequired ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
    }
}

struct CustomSecureField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let icon: String
    var isRequired: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                if isRequired {
                    Text("*")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
            }
            
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 20, height: 20)
                
                SecureField(placeholder, text: $text)
                    .font(.body)
                    .textFieldStyle(PlainTextFieldStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(text.isEmpty && isRequired ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}
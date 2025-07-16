import SwiftUI
import mft

struct AddEditConnectionView: View {
    @ObservedObject var viewModel: SFTPConnectionViewModel
    @Environment(\.presentationMode) var presentationMode
    
    // Basic connection fields
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = ""
    @State private var username: String = ""
    @State private var remotePath: String = ""
    
    // Authentication
    @State private var authMethod: SFTPAuthMethod = .password
    @State private var password: String = ""
    @State private var selectedKeyPair: SSHKeyPair?
    @State private var showingKeyPairPicker = false
    @State private var showingKeyGenerator = false
    
    // NATS configuration
    @State private var isNATSEnabled: Bool = false
    @State private var natsServers: String = ""
    @State private var natsSubject: String = ""
    @State private var natsCredentials: String = ""
    @State private var natsTLSEnabled: Bool = true
    
    // State
    @State private var status: ConnectionStatus = .unknown
    @State private var isTesting = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var connection: SFTPConnection? = nil
    var isEditing: Bool { connection != nil }
    
    private let keyManager = SSHKeyManager()
    private let connectionManager = EnhancedMFTConnectionManager()
    
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
                                
                                // Remote Path
                                CustomInputField(
                                    title: "Remote Path",
                                    text: $remotePath,
                                    placeholder: "/home/user",
                                    icon: "folder"
                                )
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
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
                        
                        // Authentication Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "key.fill")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 32, height: 32)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Authentication")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text("Choose your authentication method")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            
                            VStack(spacing: 16) {
                                // Authentication Method Picker
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Authentication Method")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    
                                    Picker("Authentication Method", selection: $authMethod) {
                                        ForEach(SFTPAuthMethod.allCases, id: \.self) { method in
                                            Text(method.displayName).tag(method)
                                        }
                                    }
                                    .pickerStyle(SegmentedPickerStyle())
                                }
                                .padding(.horizontal, 20)
                                
                                // Password Field (shown for password and passwordAndKey)
                                if authMethod == .password || authMethod == .passwordAndKey {
                                    CustomSecureField(
                                        title: "Password",
                                        text: $password,
                                        placeholder: "••••••••",
                                        icon: "lock",
                                        isRequired: true
                                    )
                                    .padding(.horizontal, 20)
                                }
                                
                                // SSH Key Selection (shown for publicKey and passwordAndKey)
                                if authMethod == .publicKey || authMethod == .passwordAndKey {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("SSH Key Pair")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary)
                                            
                                            Text("*")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.red)
                                        }
                                        
                                        HStack(spacing: 12) {
                                            Image(systemName: "key")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(.accentColor)
                                                .frame(width: 20, height: 20)
                                            
                                            if let keyPair = selectedKeyPair {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(keyPair.name)
                                                        .font(.body)
                                                        .foregroundColor(.primary)
                                                    
                                                    Text("Created: \(keyPair.createdAt, formatter: dateFormatter)")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            } else {
                                                Text("No key pair selected")
                                                    .font(.body)
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            Spacer()
                                            
                                            HStack(spacing: 8) {
                                                Button("Select") {
                                                    showingKeyPairPicker = true
                                                }
                                                .font(.caption)
                                                .foregroundColor(.accentColor)
                                                
                                                Button("Generate") {
                                                    showingKeyGenerator = true
                                                }
                                                .font(.caption)
                                                .foregroundColor(.accentColor)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color(.systemGray6))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(selectedKeyPair == nil ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
                                                )
                                        )
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 2)
                        )
                        .padding(.horizontal, 16)
                        
                        // NATS Configuration Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "bolt.circle")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 32, height: 32)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Real-time Sync")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text("NATS integration for instant file updates")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: $isNATSEnabled)
                                    .labelsHidden()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            
                            if isNATSEnabled {
                                VStack(spacing: 16) {
                                    CustomInputField(
                                        title: "NATS Servers",
                                        text: $natsServers,
                                        placeholder: "nats://localhost:4222",
                                        icon: "server.rack",
                                        isRequired: true
                                    )
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    
                                    CustomInputField(
                                        title: "Subject",
                                        text: $natsSubject,
                                        placeholder: "sftpgo.events",
                                        icon: "tag",
                                        isRequired: true
                                    )
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    
                                    CustomInputField(
                                        title: "Credentials (Optional)",
                                        text: $natsCredentials,
                                        placeholder: "JWT token or credentials file",
                                        icon: "key"
                                    )
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    
                                    HStack {
                                        HStack(spacing: 12) {
                                            Image(systemName: "lock.shield")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(.accentColor)
                                                .frame(width: 20, height: 20)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Enable TLS")
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(.primary)
                                                
                                                Text("Secure connection to NATS server")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Toggle("", isOn: $natsTLSEnabled)
                                            .labelsHidden()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.systemGray6))
                                    )
                                }
                                .padding(.horizontal, 20)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 2)
                        )
                        .padding(.horizontal, 16)
                        .animation(.easeInOut(duration: 0.3), value: isNATSEnabled)
                        
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
                                            .fill(canTestConnection ? Color.accentColor : Color.accentColor.opacity(0.5))
                                    )
                                    .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
                                }
                                .disabled(!canTestConnection)
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
                                
                                Text("Features")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                InfoRow(
                                    icon: "key.fill",
                                    title: "SSH Key Authentication",
                                    description: "Support for password, SSH keys, or both"
                                )
                                
                                InfoRow(
                                    icon: "bolt.circle.fill",
                                    title: "Real-time Sync",
                                    description: "NATS integration for instant file updates"
                                )
                                
                                InfoRow(
                                    icon: "folder.badge.plus",
                                    title: "Files App Integration",
                                    description: "Access files directly from the Files app"
                                )
                                
                                InfoRow(
                                    icon: "icloud.fill",
                                    title: "iCloud-like Experience",
                                    description: "Seamless sync and conflict resolution"
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
                    .disabled(!canSaveConnection)
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
            .sheet(isPresented: $showingKeyPairPicker) {
                SSHKeyPairPickerView(selectedKeyPair: $selectedKeyPair)
            }
            .sheet(isPresented: $showingKeyGenerator) {
                SSHKeyGeneratorView { keyPair in
                    selectedKeyPair = keyPair
                }
            }
        }
        .onAppear {
            loadConnectionData()
        }
    }
    
    // MARK: - Computed Properties
    private var canTestConnection: Bool {
        !host.isEmpty && !username.isEmpty && !isTesting && hasValidAuth
    }
    
    private var canSaveConnection: Bool {
        !host.isEmpty && !username.isEmpty && hasValidAuth && (!isEditing || status.isHealthy)
    }
    
    private var hasValidAuth: Bool {
        switch authMethod {
        case .password:
            return !password.isEmpty
        case .publicKey:
            return selectedKeyPair != nil
        case .passwordAndKey:
            return !password.isEmpty && selectedKeyPair != nil
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .connected, .valid: return .green
        case .connecting, .checking: return .blue
        case .disconnected, .invalid, .error, .authFailed, .syncError: return .red
        case .timeout: return .orange
        case .unknown: return .gray
        }
    }
    
    private var statusIcon: String {
        switch status {
        case .connected, .valid: return "checkmark.circle.fill"
        case .connecting, .checking: return "arrow.triangle.2.circlepath"
        case .disconnected, .invalid, .error, .authFailed, .syncError: return "xmark.octagon.fill"
        case .timeout: return "clock.badge.exclamationmark"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }
    
    // MARK: - Methods
    private func loadConnectionData() {
        guard let connection = connection else { return }
        
        name = connection.name
        host = connection.host
        port = connection.port != nil ? String(connection.port!) : ""
        username = connection.username
        remotePath = connection.remotePath
        authMethod = connection.authMethod
        password = connection.password
        status = connection.status
        
        if let keyPairId = connection.keyPairId {
            selectedKeyPair = try? keyManager.getKeyPair(id: keyPairId)
        }
        
        if let natsConfig = connection.natsConfig {
            isNATSEnabled = connection.isNATSEnabled
            natsServers = natsConfig.servers.joined(separator: ",")
            natsSubject = natsConfig.subject
            natsCredentials = natsConfig.credentials ?? ""
            natsTLSEnabled = natsConfig.tlsEnabled
        }
    }
    
    private func testConnection() {
        isTesting = true
        status = .connecting
        
        let testConnection = createSFTPConnection()
        
        viewModel.testConnection(testConnection) { result in
            status = result
            isTesting = false
            
            switch result {
            case .connected, .valid:
                alertMessage = "Connection successful! You can now save this connection."
            case .authFailed:
                alertMessage = "Authentication failed. Please check your credentials."
            case .disconnected, .invalid, .error:
                alertMessage = "Connection failed. Please check your server settings."
            case .timeout:
                alertMessage = "Connection timed out. Please check your server address."
            default:
                alertMessage = "Connection test completed with status: \(result.displayName)"
            }
            showingAlert = true
        }
    }
    
    private func saveConnection() {
        guard hasValidAuth else { return }
        
        if !isEditing && !status.isHealthy {
            alertMessage = "Please test the connection and ensure it's valid before saving."
            showingAlert = true
            return
        }
        
        let newConnection = createSFTPConnection()
        
        if isEditing {
            viewModel.updateConnection(newConnection)
        } else {
            viewModel.addConnection(newConnection)
        }
        
        presentationMode.wrappedValue.dismiss()
    }
    
    private func createSFTPConnection() -> SFTPConnection {
        let portInt = Int(port) ?? 22
        let keyPairId = selectedKeyPair?.id
        
        let natsConfig = isNATSEnabled ? NATSConfig(
            servers: natsServers.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) },
            subject: natsSubject,
            credentials: natsCredentials.isEmpty ? nil : natsCredentials,
            tlsEnabled: natsTLSEnabled
        ) : nil
        
        return SFTPConnection(
            id: connection?.id ?? UUID(),
            name: name.isEmpty ? host : name,
            host: host,
            port: portInt,
            username: username,
            authMethod: authMethod,
            password: password,
            keyPairId: keyPairId,
            remotePath: remotePath,
            isNATSEnabled: isNATSEnabled,
            natsConfig: natsConfig
        )
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
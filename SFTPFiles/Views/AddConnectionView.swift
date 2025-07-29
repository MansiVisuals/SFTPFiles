//
//  AddConnectionView.swift
//  SFTPFiles
//
//  Created by Maikel Mansi on 28/07/2025.
//

import SwiftUI

struct AddConnectionView: View {
    @EnvironmentObject var connectionManager: SFTPConnectionManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var hostname = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var password = ""
    @State private var useKeyAuth = false
    @State private var privateKeyPath = ""
    @State private var autoConnect = true
    @State private var testingConnection = false
    @State private var testResult: TestResult?
    @State private var showValidationErrors = false
    
    enum TestResult {
        case success
        case failure(String)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Server Information") {
                    SettingsTextField(
                        title: "Name",
                        text: $name,
                        placeholder: "My Server"
                    )
                    
                    SettingsTextField(
                        title: "Hostname",
                        text: $hostname,
                        placeholder: "example.com or 192.168.1.100"
                    )
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                    
                    SettingsTextField(
                        title: "Port",
                        text: $port,
                        placeholder: "22"
                    )
                    .keyboardType(.numberPad)
                }
                
                Section("Authentication") {
                    SettingsTextField(
                        title: "Username",
                        text: $username,
                        placeholder: "username"
                    )
                    .autocapitalization(.none)
                    
                    Toggle("Use Private Key Authentication", isOn: $useKeyAuth)
                    
                    if useKeyAuth {
                        SettingsTextField(
                            title: "Private Key Path",
                            text: $privateKeyPath,
                            placeholder: "/path/to/private/key"
                        )
                    } else {
                        SettingsSecureField(
                            title: "Password",
                            text: $password,
                            placeholder: "Enter password"
                        )
                    }
                }
                
                Section("Options") {
                    Toggle("Auto-connect on startup", isOn: $autoConnect)
                }
                
                Section {
                    Button(action: testConnection) {
                        HStack {
                            if testingConnection {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(.blue)
                            }
                            
                            Text("Test Connection")
                                .foregroundColor(testingConnection ? .secondary : .blue)
                            
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
                    .disabled(testingConnection || !isFormValid)
                    
                    if case .failure(let error) = testResult {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } footer: {
                    if showValidationErrors {
                        VStack(alignment: .leading, spacing: 4) {
                            if name.isEmpty {
                                Text("• Connection name is required")
                            }
                            if hostname.isEmpty {
                                Text("• Hostname is required")
                            }
                            if username.isEmpty {
                                Text("• Username is required")
                            }
                            if !useKeyAuth && password.isEmpty {
                                Text("• Password is required")
                            }
                            if useKeyAuth && privateKeyPath.isEmpty {
                                Text("• Private key path is required")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveConnection()
                    }
                    .disabled(!isFormValid)
                    .fontWeight(.semibold)
                }
            }
        }
        .onChange(of: name) {
            showValidationErrors = false
        }
        .onChange(of: hostname) {
            showValidationErrors = false
        }
        .onChange(of: username) {
            showValidationErrors = false
        }
        .onChange(of: password) {
            showValidationErrors = false
        }
        .onChange(of: privateKeyPath) {
            showValidationErrors = false
        }
    }
    
    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
        !hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
        hostname.isValidHostname() &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        port.isValidPort() &&
        (useKeyAuth ? !privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : !password.isEmpty)
    }
    
    private func testConnection() {
        guard isFormValid else {
            showValidationErrors = true
            return
        }
        
        testingConnection = true
        testResult = nil
        
        Task {
            let connection = SFTPConnection(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                hostname: hostname.trimmingCharacters(in: .whitespacesAndNewlines),
                port: Int(port) ?? 22,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                useKeyAuth: useKeyAuth,
                privateKeyPath: useKeyAuth ? privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            )
            
            let success = await SFTPService.shared.testConnection(
                connection: connection,
                password: useKeyAuth ? nil : password
            )
            
            await MainActor.run {
                testingConnection = false
                testResult = success ? .success : .failure("Unable to connect to server. Please check your credentials and network connection.")
            }
        }
    }
    
    private func saveConnection() {
        guard isFormValid else {
            showValidationErrors = true
            return
        }
        
        var connection = SFTPConnection(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            hostname: hostname.trimmingCharacters(in: .whitespacesAndNewlines),
            port: Int(port) ?? 22,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            useKeyAuth: useKeyAuth,
            privateKeyPath: useKeyAuth ? privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        )
        
        connection.autoConnect = autoConnect
        
        connectionManager.addConnection(connection, password: useKeyAuth ? nil : password)
        dismiss()
    }
}

// MARK: - Custom Input Components

struct SettingsTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Text(title)
                .frame(width: 80, alignment: .leading)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .multilineTextAlignment(.trailing)
        }
    }
}

struct SettingsSecureField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Text(title)
                .frame(width: 80, alignment: .leading)
            
            SecureField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    AddConnectionView()
        .environmentObject(SFTPConnectionManager())
}
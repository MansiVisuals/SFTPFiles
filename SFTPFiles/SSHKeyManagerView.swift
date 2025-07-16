import SwiftUI

// MARK: - SSH Key Manager View
struct SSHKeyManagerView: View {
    @ObservedObject var viewModel: SFTPConnectionViewModel
    @Environment(\.presentationMode) var presentationMode
    
    @State private var keyPairs: [SSHKeyPair] = []
    @State private var showingKeyGenerator = false
    @State private var showingKeyImporter = false
    
    var body: some View {
        NavigationView {
            ZStack {
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
                
                if keyPairs.isEmpty {
                    VStack(spacing: 24) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.1))
                                .frame(width: 120, height: 120)
                            
                            Image(systemName: "key.badge.plus")
                                .font(.system(size: 48))
                                .foregroundColor(.accentColor)
                        }
                        
                        VStack(spacing: 8) {
                            Text("No SSH Keys")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Generate or import SSH key pairs for secure authentication")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        
                        HStack(spacing: 16) {
                            Button("Generate") {
                                showingKeyGenerator = true
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            
                            Button("Import") {
                                showingKeyImporter = true
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(keyPairs) { keyPair in
                                SSHKeyRow(keyPair: keyPair) {
                                    try? viewModel.deleteKeyPair(keyPair)
                                    loadKeyPairs()
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    }
                }
            }
            .navigationTitle("SSH Keys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Generate Key Pair") {
                            showingKeyGenerator = true
                        }
                        
                        Button("Import Key Pair") {
                            showingKeyImporter = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.accentColor)
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showingKeyGenerator) {
            SSHKeyGeneratorView { _ in
                loadKeyPairs()
            }
        }
        .sheet(isPresented: $showingKeyImporter) {
            SSHKeyImportView { _ in
                loadKeyPairs()
            }
        }
        .onAppear {
            loadKeyPairs()
        }
    }
    
    private func loadKeyPairs() {
        keyPairs = viewModel.getAvailableKeyPairs()
    }
}

// MARK: - SSH Key Row
struct SSHKeyRow: View {
    let keyPair: SSHKeyPair
    let onDelete: () -> Void
    
    @State private var showingDeleteAlert = false
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 56, height: 56)
                
                Image(systemName: "key.fill")
                    .foregroundColor(.accentColor)
                    .font(.title2)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(keyPair.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Created: \(keyPair.createdAt, formatter: dateFormatter)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Text(keyTypeFromPublicKey(keyPair.publicKey))
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                    
                    if keyPair.passphrase != nil {
                        Text("Protected")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            Button(action: { showingDeleteAlert = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.red)
                    .cornerRadius(8)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .alert("Delete SSH Key", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete '\(keyPair.name)'? This action cannot be undone.")
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
    
    private func keyTypeFromPublicKey(_ publicKey: String) -> String {
        if publicKey.contains("ssh-rsa") {
            return "RSA"
        } else if publicKey.contains("ssh-ed25519") {
            return "Ed25519"
        } else if publicKey.contains("ecdsa") {
            return "ECDSA"
        } else {
            return "Unknown"
        }
    }
}

// MARK: - SSH Key Pair Picker View
struct SSHKeyPairPickerView: View {
    @Binding var selectedKeyPair: SSHKeyPair?
    @Environment(\.presentationMode) var presentationMode
    
    @State private var keyPairs: [SSHKeyPair] = []
    private let keyManager = SSHKeyManager()
    
    var body: some View {
        NavigationView {
            List(keyPairs) { keyPair in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(keyPair.name)
                            .font(.headline)
                        
                        Text("Created: \(keyPair.createdAt, formatter: dateFormatter)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if selectedKeyPair?.id == keyPair.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedKeyPair = keyPair
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .navigationTitle("Select SSH Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .onAppear {
            keyPairs = keyManager.loadKeyPairs()
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }
}

// MARK: - SSH Key Generator View (Simplified)
struct SSHKeyGeneratorView: View {
    let onKeyGenerated: (SSHKeyPair) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    @State private var keyName: String = ""
    @State private var isGenerating: Bool = false
    @State private var showingAlert: Bool = false
    @State private var alertMessage: String = ""
    
    private let keyManager = SSHKeyManager()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "key.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    
                    Text("Generate SSH Key Pair")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                CustomInputField(
                    title: "Key Name",
                    text: $keyName,
                    placeholder: "My SSH Key",
                    icon: "tag",
                    isRequired: true
                )
                
                Button(action: generateKeyPair) {
                    HStack(spacing: 12) {
                        if isGenerating {
                            ProgressView()
                                .scaleEffect(0.9)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "key.badge.plus")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        
                        Text(isGenerating ? "Generating..." : "Generate Key Pair")
                            .font(.body)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(!keyName.isEmpty && !isGenerating ? Color.accentColor : Color.accentColor.opacity(0.5))
                    )
                }
                .disabled(keyName.isEmpty || isGenerating)
                .buttonStyle(BorderlessButtonStyle())
                
                Spacer()
            }
            .padding()
            .navigationTitle("Generate SSH Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(isGenerating)
                }
            }
            .alert("Key Generation", isPresented: $showingAlert) {
                Button("OK") {
                    if alertMessage.contains("successfully") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func generateKeyPair() {
        isGenerating = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let keyPair = try SSHKeyGenerator.generateKeyPair(name: keyName)
                try keyManager.saveKeyPair(keyPair)
                
                DispatchQueue.main.async {
                    isGenerating = false
                    alertMessage = "SSH key pair '\(keyName)' generated successfully!"
                    showingAlert = true
                    onKeyGenerated(keyPair)
                }
            } catch {
                DispatchQueue.main.async {
                    isGenerating = false
                    alertMessage = "Failed to generate key pair: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }
}

// MARK: - SSH Key Import View (Simplified)
struct SSHKeyImportView: View {
    let onKeyImported: (SSHKeyPair) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    @State private var keyName: String = ""
    @State private var publicKey: String = ""
    @State private var privateKey: String = ""
    @State private var isImporting: Bool = false
    @State private var showingAlert: Bool = false
    @State private var alertMessage: String = ""
    
    private let keyManager = SSHKeyManager()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                        
                        Text("Import SSH Key Pair")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    
                    CustomInputField(
                        title: "Key Name",
                        text: $keyName,
                        placeholder: "My Imported Key",
                        icon: "tag",
                        isRequired: true
                    )
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Public Key")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        TextEditor(text: $publicKey)
                            .frame(minHeight: 100)
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .font(.system(.caption, design: .monospaced))
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Private Key")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        TextEditor(text: $privateKey)
                            .frame(minHeight: 120)
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .font(.system(.caption, design: .monospaced))
                    }
                    
                    Button(action: importKeyPair) {
                        HStack(spacing: 12) {
                            if isImporting {
                                ProgressView()
                                    .scaleEffect(0.9)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            
                            Text(isImporting ? "Importing..." : "Import Key Pair")
                                .font(.body)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(canImport ? Color.accentColor : Color.accentColor.opacity(0.5))
                        )
                    }
                    .disabled(!canImport)
                    .buttonStyle(BorderlessButtonStyle())
                }
                .padding()
            }
            .navigationTitle("Import SSH Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(isImporting)
                }
            }
            .alert("Key Import", isPresented: $showingAlert) {
                Button("OK") {
                    if alertMessage.contains("successfully") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private var canImport: Bool {
        !keyName.isEmpty && !publicKey.isEmpty && !privateKey.isEmpty && !isImporting
    }
    
    private func importKeyPair() {
        isImporting = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let keyPair = SSHKeyPair(
                    name: keyName,
                    publicKey: publicKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    privateKey: privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                
                try keyManager.saveKeyPair(keyPair)
                
                DispatchQueue.main.async {
                    isImporting = false
                    alertMessage = "SSH key pair '\(keyName)' imported successfully!"
                    showingAlert = true
                    onKeyImported(keyPair)
                }
            } catch {
                DispatchQueue.main.async {
                    isImporting = false
                    alertMessage = "Failed to import key pair: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }
}

// MARK: - Enhanced Settings View (Simplified)
struct EnhancedSettingsView: View {
    @ObservedObject var viewModel: SFTPConnectionViewModel
    @Environment(\.presentationMode) var presentationMode
    
    @State private var showingClearAlert = false
    @State private var isClearing = false
    
    var body: some View {
        NavigationView {
            List {
                Section("App Information") {
                    HStack {
                        Text("Total Connections")
                        Spacer()
                        Text("\(viewModel.connections.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Connected")
                        Spacer()
                        Text("\(viewModel.connections.filter { $0.status.isHealthy }.count)")
                            .foregroundColor(.green)
                    }
                    
                    HStack {
                        Text("Real-time Enabled")
                        Spacer()
                        Text("\(viewModel.connections.filter { $0.isNATSEnabled }.count)")
                            .foregroundColor(.blue)
                    }
                }
                
                Section("SSH Keys") {
                    HStack {
                        Text("Key Pairs")
                        Spacer()
                        Text("\(viewModel.getAvailableKeyPairs().count)")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Data Management") {
                    Button("Clear All Data") {
                        showingClearAlert = true
                    }
                    .foregroundColor(.red)
                    .disabled(isClearing)
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
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    clearAllData()
                }
            } message: {
                Text("This will permanently remove all SFTP connections and SSH keys. This action cannot be undone.")
            }
        }
    }
    
    private func clearAllData() {
        isClearing = true
        Task {
            await viewModel.clearAllConfigurations()
            // Clear SSH keys
            let keyPairs = viewModel.getAvailableKeyPairs()
            for keyPair in keyPairs {
                try? viewModel.deleteKeyPair(keyPair)
            }
            isClearing = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
}

// MARK: - Button Styles
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.accentColor)
            .cornerRadius(12)
            .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .fontWeight(.semibold)
            .foregroundColor(.accentColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

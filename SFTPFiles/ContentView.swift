// MARK: - Background Refresh Status Enum for Polling
enum BackgroundRefreshStatus: String, CaseIterable {
    case available
    case restricted
    case denied
}
import SwiftUI
import Combine
import BackgroundTasks
import FileProvider
import mft
import UIKit

// MARK: - Enhanced Connection View Model
class SFTPConnectionViewModel: ObservableObject {
    @Published var connections: [SFTPConnection] = []
    @Published var showAddSheet = false
    @Published var editingConnection: SFTPConnection? = nil
    @Published var syncStatus: SyncStatus = .idle
    @Published var natsConnectionStatus: NATSConnectionStatus = .disconnected
    @Published var lastSyncDate: Date?
    @Published var pollingManager: PollingManager!

    // ...existing code...
    
    private let connectionManager = EnhancedMFTConnectionManager()
    private let keyManager = SSHKeyManager()
    private var syncManager: FileProviderSyncManager?
    private var natsManager: NATSSyncManager?
    private var natsStatusCancellable: AnyCancellable?
    
    init() {
        loadConnections()
        setupSyncManager()
        setupNATSConnections()
        pollingManager = PollingManager(viewModel: self)
    }
    
    private func setupSyncManager() {
        syncManager = FileProviderSyncManager()
        natsManager = NATSSyncManager(fileProviderManager: syncManager!)
        // Bind NATS connection status to view model
        natsStatusCancellable = natsManager?.$connectionStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.natsConnectionStatus = status
            }
    }
    
    private func setupNATSConnections() {
        for connection in connections {
            if connection.isNATSEnabled, let natsConfig = connection.natsConfig {
                Task {
                    await natsManager?.connect(to: natsConfig)
                }
            }
        }
    }
    
    func addConnection(_ connection: SFTPConnection) {
        connections.append(connection)
        saveConnections()
        addFileProviderDomain(for: connection)
        
        if connection.isNATSEnabled, let natsConfig = connection.natsConfig {
            Task {
                await natsManager?.connect(to: natsConfig)
            }
        }
    }
    
    func updateConnection(_ connection: SFTPConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
            saveConnections()
            updateFileProviderDomain(for: connection)
        }
    }
    
    func deleteConnection(_ connection: SFTPConnection) {
        removeFileProviderDomain(for: connection)
        connections.removeAll { $0.id == connection.id }
        saveConnections()
    }
    
    func loadConnections() {
        connections = SFTPConnectionStore.loadConnections()
    }
    
    func saveConnections() {
        SFTPConnectionStore.saveConnections(connections)
    }
    
    func testConnection(_ connection: SFTPConnection, completion: @escaping (ConnectionStatus) -> Void) {
        Task {
            do {
                let status = try await connectionManager.testConnection(connection)
                await MainActor.run {
                    completion(status)
                }
            } catch {
                await MainActor.run {
                    completion(.error)
                }
            }
        }
    }
    
    func updateStatus(for connection: SFTPConnection, status: ConnectionStatus) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index].status = status
            saveConnections()
        }
    }
    
    func updateLastChecked(for connection: SFTPConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index].lastChecked = Date()
            saveConnections()
        }
    }
    
    func triggerManualSync(for connection: SFTPConnection) {
        Task {
            await syncManager?.triggerManualSync(for: connection)
        }
    }
    
    func triggerManualSyncAll() {
        for connection in connections {
            Task {
                await syncManager?.triggerManualSync(for: connection)
            }
        }
    }
    
    func clearAllConfigurations() async {
        for connection in connections {
            removeFileProviderDomain(for: connection)
        }
        
        await withCheckedContinuation { continuation in
            NSFileProviderManager.getDomainsWithCompletionHandler { domains, error in
                guard error == nil else {
                    continuation.resume()
                    return
                }
                let group = DispatchGroup()
                for domain in domains {
                    group.enter()
                    NSFileProviderManager.remove(domain) { error in
                        if let error = error {
                            print("Failed to remove domain \(domain.displayName): \(error.localizedDescription)")
                        }
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    continuation.resume()
                }
            }
        }
        if let natsManager = natsManager {
            await natsManager.disconnect()
        }
        connections.removeAll()
        SFTPConnectionStore.saveConnections([])
    }
    
    func getAvailableKeyPairs() -> [SSHKeyPair] {
        return keyManager.loadKeyPairs()
    }
    
    func deleteKeyPair(_ keyPair: SSHKeyPair) throws {
        try keyManager.deleteKeyPair(id: keyPair.id)
        
        // Update any connections using this key
        for i in 0..<connections.count {
            if connections[i].keyPairId == keyPair.id {
                connections[i].keyPairId = nil
                connections[i].authMethod = .password
            }
        }
        saveConnections()
    }
    
    // MARK: - File Provider Domain Management
    private func addFileProviderDomain(for connection: SFTPConnection) {
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: connection.id.uuidString),
            displayName: connection.name
        )
        
        NSFileProviderManager.add(domain) { error in
            DispatchQueue.main.async {
                if let error = error {
                    let nsError = error as NSError
                    if !nsError.localizedDescription.contains("already exists") {
                        NSLog("Failed to add domain: \(error.localizedDescription)")
                    }
                } else {
                    NSLog("Successfully added domain for \(connection.name)")
                }
            }
        }
    }
    
    private func updateFileProviderDomain(for connection: SFTPConnection) {
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: connection.id.uuidString),
            displayName: connection.name
        )
        
        NSFileProviderManager.remove(domain) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSFileProviderManager.add(domain) { error in
                    if let error = error {
                        NSLog("Failed to update domain: \(error.localizedDescription)")
                    } else {
                        NSLog("Successfully updated domain for \(connection.name)")
                    }
                }
            }
        }
    }
    
    private func removeFileProviderDomain(for connection: SFTPConnection) {
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: connection.id.uuidString),
            displayName: connection.name
        )
        
        NSFileProviderManager.remove(domain) { error in
            if let error = error {
                let nsError = error as NSError
                if nsError.code != NSFileProviderError.providerDomainNotFound.rawValue {
                    NSLog("Failed to remove domain: \(error.localizedDescription)")
                }
            } else {
                NSLog("Successfully removed domain for \(connection.name)")
            }
        }
    }
}

// MARK: - Enhanced Content View
struct ContentView: View {
    @StateObject private var viewModel = SFTPConnectionViewModel()
    @State private var showingSettings = false
    @State private var showingSSHKeys = false

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

                if viewModel.connections.isEmpty {
                    VStack(spacing: 24) {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.1))
                                .frame(width: 120, height: 120)
                            Image(systemName: "externaldrive.badge.plus")
                                .font(.system(size: 48))
                                .foregroundColor(.accentColor)
                                .fontWeight(.medium)
                        }
                        VStack(spacing: 8) {
                            Text("No SFTP Connections")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            Text("Add your first SFTP connection to access files through the Files app with real-time sync")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .lineLimit(3)
                        }
                        Button(action: { viewModel.showAddSheet = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16, weight: .medium))
                                Text("Add Connection")
                                    .fontWeight(.semibold)
                            }
                            .font(.body)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .cornerRadius(12)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        Spacer()
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.connections) { connection in
                                FoldableConnectionRow(
                                    connection: connection,
                                    onEdit: { viewModel.editingConnection = connection },
                                    onDelete: { viewModel.deleteConnection(connection) },
                                    onManualSync: { viewModel.triggerManualSync(for: connection) }
                                )
                            }
                            VStack(spacing: 16) {
                                Divider().padding(.horizontal, 16)
                                Button(action: { viewModel.showAddSheet = true }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 16, weight: .medium))
                                        Text("Add Connection").fontWeight(.semibold)
                                    }
                                    .font(.body)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.accentColor)
                                    .cornerRadius(12)
                                    .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                    .refreshable { viewModel.triggerManualSyncAll() }
                }
            }
            .navigationTitle("SFTPFiles")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: { showingSSHKeys = true }) {
                            Image(systemName: "key").foregroundColor(.accentColor)
                        }
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape").foregroundColor(.accentColor)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { viewModel.triggerManualSyncAll() }) {
                        Image(systemName: "arrow.clockwise").foregroundColor(.accentColor)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showAddSheet) {
                AddEditConnectionView(viewModel: viewModel)
            }
            .sheet(item: $viewModel.editingConnection) { connection in
                AddEditConnectionView(viewModel: viewModel, connection: connection)
            }
            .sheet(isPresented: $showingSettings) {
                EnhancedSettingsView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingSSHKeys) {
                SSHKeyManagerView(viewModel: viewModel)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
// MARK: - Foldable Connection Row (Old App Style)
struct FoldableConnectionRow: View {
    let connection: SFTPConnection
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onManualSync: () -> Void
    @State private var isExpanded = false
    @State private var showingDeleteAlert = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(connection.status == .connected || connection.status == .valid ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: connection.status == .connected || connection.status == .valid ? "externaldrive.connected.to.line.below" : "externaldrive.badge.xmark")
                        .foregroundColor(connection.status == .connected || connection.status == .valid ? .green : .gray)
                        .font(.title2)
                }
                Text(connection.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.accentColor)
                        .padding(8)
                }
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundColor(.accentColor)
                        .padding(8)
                }
                Button(action: { showingDeleteAlert = true }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .padding(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: isExpanded ? 0 : 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
            .alert("Delete Connection", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { onDelete() }
            } message: {
                Text("Are you sure you want to delete '\(connection.name)'? This will remove the connection from the Files app and cannot be undone.")
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider().padding(.horizontal, 8)
                    HStack {
                        Text("Status:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(connection.status.displayName)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    HStack {
                        Text("Host:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(connection.username)@\(connection.host):\(connection.port ?? 22)")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    if !connection.remotePath.isEmpty {
                        HStack {
                            Text("Remote Path:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(connection.remotePath)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }
                    HStack {
                        Text("Auth:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(connection.authMethod.displayName)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    if connection.isNATSEnabled {
                        HStack {
                            Text("Real-time Sync:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Enabled")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        }
                        Button(action: onManualSync) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                Text("Manual Sync")
                            }
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(Color.accentColor.opacity(0.08))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color(.systemGray6))
                )
            }
        }
        .cornerRadius(12)
        .padding(.vertical, 2)
    }
}
}

// MARK: - Supporting Views that work with existing structure
struct SyncStatusHeader: View {
    let syncStatus: SyncStatus
    let natsStatus: NATSConnectionStatus
    let lastSyncDate: Date?
    let onManualSync: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Real-time Sync")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 12) {
                        // NATS Status
                        HStack(spacing: 4) {
                            Circle()
                                .fill(natsStatusColor)
                                .frame(width: 8, height: 8)
                            
                            Text(natsStatus.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let lastSync = lastSyncDate {
                            Text("Last sync: \(lastSync, formatter: relativeDateFormatter)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Button(action: onManualSync) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
    
    private var natsStatusColor: Color {
        switch natsStatus {
        case .disconnected: return .gray
        case .connecting: return .blue
        case .connected: return .green
        case .error: return .red
        }
    }
    
    private var relativeDateFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }
}

struct EnhancedConnectionRow: View {
    let connection: SFTPConnection
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onManualSync: () -> Void
    
    @State private var showingDeleteAlert = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Connection Icon with Status
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                
                Image(systemName: connectionIcon)
                    .foregroundColor(statusColor)
                    .font(.title2)
                    .fontWeight(.medium)
                
                // NATS indicator
                if connection.isNATSEnabled {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.white)
                        )
                        .offset(x: 20, y: -20)
                }
            }
            
            // Connection Info
            VStack(alignment: .leading, spacing: 6) {
                Text(connection.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(connection.username)@\(connection.host)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    // Auth method badge
                    Text(connection.authMethod.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                    
                    // NATS badge
                    if connection.isNATSEnabled {
                        Text("Real-time")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    // Status badge
                    Text(connection.status.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.1))
                        .foregroundColor(statusColor)
                        .cornerRadius(4)
                }
            }
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 8) {
                if connection.isNATSEnabled {
                    Button(action: onManualSync) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
                .buttonStyle(BorderlessButtonStyle())
                
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .alert("Delete Connection", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete '\(connection.name)'? This will remove the connection from the Files app and cannot be undone.")
        }
    }
    
    private var statusColor: Color {
        switch connection.status {
        case .connected, .valid: return .green
        case .connecting, .checking: return .blue
        case .disconnected, .invalid, .error, .authFailed, .syncError: return .red
        case .timeout: return .orange
        case .unknown: return .gray
        }
    }
    
    private var connectionIcon: String {
        switch connection.status {
        case .connected, .valid: return "externaldrive.connected.to.line.below"
        case .connecting, .checking: return "arrow.triangle.2.circlepath"
        case .disconnected, .invalid, .error, .authFailed, .syncError: return "externaldrive.badge.xmark"
        case .timeout: return "externaldrive.badge.timemachine"
        case .unknown: return "externaldrive.badge.questionmark"
        }
    }
}

// MARK: - Supporting Enums
enum SyncStatus {
    case idle
    case syncing
    case error
    
    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .syncing: return "Syncing..."
        case .error: return "Error"
        }
    }
}

enum NATSConnectionStatus {
    case disconnected
    case connecting
    case connected
    case error
    
    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error: return "Error"
        }
    }
}

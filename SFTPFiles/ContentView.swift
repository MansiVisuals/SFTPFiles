import SwiftUI
import BackgroundTasks
import FileProvider
import mft
import UIKit

// MARK: - Polling Manager
class ConnectionPollingManager: ObservableObject {
    @Published var pollingInterval: TimeInterval = 30.0
    @Published var isPollingEnabled: Bool = true
    @Published var backgroundRefreshStatus: UIBackgroundRefreshStatus = .available
    @Published var showBackgroundRefreshAlert: Bool = false
    
    private var timer: Timer?
    private weak var viewModel: SFTPConnectionViewModel?
    private let appGroupID = "group.mansivisuals.SFTPFiles"
    private let bgTaskIdentifier = "com.mansivisuals.sftpfiles.refresh"
    
    init(viewModel: SFTPConnectionViewModel) {
        self.viewModel = viewModel
        loadSettings()
        checkBackgroundRefreshStatus()
        startPolling()
        setupBackgroundRefreshObserver()
    }
    
    deinit {
        stopPolling()
        NotificationCenter.default.removeObserver(self)
    }
    
    func startPolling() {
        stopPolling()
        guard isPollingEnabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.checkAllConnections()
        }
        checkAllConnections()
        scheduleBackgroundRefresh()
    }
    
    func stopPolling() {
        timer?.invalidate()
        timer = nil
        cancelBackgroundRefresh()
    }
    
    func updatePollingInterval(_ interval: TimeInterval) {
        pollingInterval = interval
        saveSettings()
        startPolling()
        scheduleBackgroundRefresh()
    }
    
    func togglePolling(_ enabled: Bool) {
        isPollingEnabled = enabled
        saveSettings()
        if enabled {
            startPolling()
        } else {
            stopPolling()
        }
        if enabled {
            scheduleBackgroundRefresh()
        } else {
            cancelBackgroundRefresh()
        }
    }
    
    private func checkAllConnections() {
        guard let viewModel = viewModel else { return }
        
        for connection in viewModel.connections {
            if connection.isPollingEnabled {
                checkConnection(connection)
            }
        }
    }
    
    func checkConnection(_ connection: SFTPConnection) {
        viewModel?.updateStatus(for: connection, status: .checking)
        viewModel?.testConnection(connection) { [weak self] status in
            let detailedStatus: ConnectionStatus
            switch status {
            case .valid:
                detailedStatus = .connected
            case .invalid:
                detailedStatus = .error
            default:
                detailedStatus = status
            }
            self?.viewModel?.updateStatus(for: connection, status: detailedStatus)
            self?.viewModel?.updateLastChecked(for: connection)
        }
    }
    
    private func loadSettings() {
        if let defaults = UserDefaults(suiteName: appGroupID) {
            pollingInterval = defaults.double(forKey: "pollingInterval")
            if pollingInterval == 0 {
                pollingInterval = 30.0
            }
            isPollingEnabled = defaults.bool(forKey: "isPollingEnabled")
            if defaults.object(forKey: "isPollingEnabled") == nil {
                isPollingEnabled = true
            }
        }
    }
    
    private func saveSettings() {
        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.set(pollingInterval, forKey: "pollingInterval")
            defaults.set(isPollingEnabled, forKey: "isPollingEnabled")
        }
    }
    
    func checkBackgroundRefreshStatus() {
        self.backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
        if self.backgroundRefreshStatus != .available && self.isPollingEnabled {
            self.showBackgroundRefreshAlert = true
        }
    }
    
    private func setupBackgroundRefreshObserver() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.backgroundRefreshStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkBackgroundRefreshStatus()
        }
    }
    
    func handleBackgroundRefreshStatusChange() {
        checkBackgroundRefreshStatus()
        
        if backgroundRefreshStatus != .available && isPollingEnabled {
            print("Background App Refresh is disabled - connection monitoring will not work in background")
            showBackgroundRefreshAlert = true
        }
    }
    
    func scheduleBackgroundRefresh() {
        guard isPollingEnabled else { return }
        
        guard backgroundRefreshStatus == .available else {
            print("Background App Refresh is disabled - cannot schedule background tasks")
            return
        }
        
        let request = BGAppRefreshTaskRequest(identifier: bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: pollingInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background refresh: \(error)")
        }
    }

    private func cancelBackgroundRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: bgTaskIdentifier)
    }
}

// MARK: - View Model
class SFTPConnectionViewModel: ObservableObject {
    @Published var connections: [SFTPConnection] = []
    @Published var showAddSheet = false
    @Published var editingConnection: SFTPConnection? = nil
    
    lazy var pollingManager = ConnectionPollingManager(viewModel: self)

    init() {
        loadConnections()
    }

    func addConnection(_ connection: SFTPConnection) {
        connections.append(connection)
        saveConnections()
        addFileProviderDomain(for: connection)
    }

    func updateConnection(_ connection: SFTPConnection) {
        if let idx = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[idx] = connection
            saveConnections()
            updateFileProviderDomain(for: connection)
        }
    }

    func updateStatus(for connection: SFTPConnection, status: ConnectionStatus) {
        if let idx = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[idx].status = status
            DispatchQueue.main.async {
                self.saveConnections()
            }
        }
    }
    
    func updateLastChecked(for connection: SFTPConnection) {
        if let idx = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[idx].lastChecked = Date()
            DispatchQueue.main.async {
                self.saveConnections()
            }
        }
    }
    
    func togglePolling(for connection: SFTPConnection, enabled: Bool) {
        if let idx = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[idx].isPollingEnabled = enabled
            DispatchQueue.main.async {
                self.saveConnections()
            }
        }
    }

    func deleteConnection(_ connection: SFTPConnection) {
        removeFileProviderDomain(for: connection)
        connections.removeAll { $0.id == connection.id }
        saveConnections()
        print("Successfully deleted connection: \(connection.name)")
    }
    
    func clearAllConfigurations() {
        for connection in connections {
            removeFileProviderDomain(for: connection)
        }
        
        NSFileProviderManager.getDomainsWithCompletionHandler { domains, error in
            guard error == nil else {
                print("Failed to get domains: \(error!.localizedDescription)")
                return
            }
            
            for domain in domains {
                NSFileProviderManager.remove(domain) { error in
                    if let error = error {
                        print("Failed to remove domain \(domain.displayName): \(error.localizedDescription)")
                    } else {
                        print("Successfully removed domain \(domain.displayName)")
                    }
                }
            }
        }
        
        connections.removeAll()
        SFTPConnectionStore.saveConnections([])
        print("Successfully cleared all configurations")
    }

    func loadConnections() {
        connections = SFTPConnectionStore.loadConnections()
    }

    func saveConnections() {
        SFTPConnectionStore.saveConnections(connections)
    }

    func testConnection(_ connection: SFTPConnection, completion: @escaping (ConnectionStatus) -> Void) {
        let sftp = MFTSftpConnection(
            hostname: connection.host,
            port: connection.port ?? 22,
            username: connection.username,
            password: connection.password
        )
        
        let timeoutTask = DispatchWorkItem {
            sftp.disconnect()
            DispatchQueue.main.async {
                completion(.timeout)
            }
        }
        
        DispatchQueue.global(qos: .background).async {
            do {
                print("Testing connection to \(connection.host)...")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 15.0, execute: timeoutTask)
                
                try sftp.connect()
                try sftp.authenticate()
                
                if !connection.remotePath.isEmpty {
                    _ = try sftp.contentsOfDirectory(atPath: connection.remotePath, maxItems: 1)
                }
                
                timeoutTask.cancel()
                sftp.disconnect()
                
                print("Connection test successful for \(connection.host)")
                
                DispatchQueue.main.async {
                    completion(.connected)
                }
            } catch {
                timeoutTask.cancel()
                sftp.disconnect()
                
                print("Connection test failed for \(connection.host): \(error.localizedDescription)")
                
                DispatchQueue.main.async {
                    completion(.error)
                }
            }
        }
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
                    if nsError.localizedDescription.contains("already exists") ||
                       nsError.localizedDescription.contains("duplicate") {
                        NSLog("Domain '\(connection.name)' already exists, which is fine")
                        return
                    }
                    NSLog("Failed to add domain: \(error.localizedDescription)")
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
            NSFileProviderManager.add(domain) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        let nsError = error as NSError
                        if nsError.localizedDescription.contains("already exists") ||
                           nsError.localizedDescription.contains("duplicate") {
                            NSLog("Domain '\(connection.name)' already exists after update")
                            return
                        }
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
            DispatchQueue.main.async {
                if let error = error {
                    let nsError = error as NSError
                    if !nsError.localizedDescription.contains("not found") &&
                       nsError.code != NSFileProviderError.providerDomainNotFound.rawValue {
                        NSLog("Failed to remove domain '\(connection.name)': \(error.localizedDescription)")
                    }
                } else {
                    NSLog("Successfully removed domain '\(connection.name)' from Files app")
                }
            }
        }
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @EnvironmentObject private var viewModel: SFTPConnectionViewModel
    @State private var showingSettings = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
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
                    // Empty state
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
                            
                            Text("Add your first SFTP connection to access files through the Files app")
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
                                ConnectionRow(
                                    connection: connection,
                                    onEdit: {
                                        viewModel.editingConnection = connection
                                    },
                                    onDelete: {
                                        viewModel.deleteConnection(connection)
                                    }
                                )
                            }
                            
                            // Add Connection button below all connections
                            VStack(spacing: 16) {
                                Divider()
                                    .padding(.horizontal, 16)
                                
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
                            }
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                    .refreshable {
                        refreshAllConnections()
                    }
                }
            }
            .navigationTitle("SFTPFiles")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.accentColor)
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
                SettingsView(viewModel: viewModel)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func refreshAllConnections() {
        if viewModel.pollingManager.backgroundRefreshStatus != .available {
            for connection in viewModel.connections {
                if connection.isPollingEnabled {
                    viewModel.togglePolling(for: connection, enabled: false)
                }
            }
        }
        for connection in viewModel.connections {
            viewModel.updateStatus(for: connection, status: .checking)
            viewModel.testConnection(connection) { status in
                let mappedStatus: ConnectionStatus
                switch status {
                case .valid:
                    mappedStatus = .connected
                case .invalid:
                    mappedStatus = .error
                default:
                    mappedStatus = status
                }
                viewModel.updateStatus(for: connection, status: mappedStatus)
                viewModel.updateLastChecked(for: connection)
            }
        }
    }
}

// MARK: - Connection Row View
struct ConnectionRow: View {
    let connection: SFTPConnection
    let onEdit: () -> Void
    let onDelete: (() -> Void)?
    @State private var showingDeleteAlert = false
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var now = Date()
    @EnvironmentObject private var viewModel: SFTPConnectionViewModel
    
    var body: some View {
        HStack(spacing: 16) {
            // Connection Icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                
                Image(systemName: connection.status == .checking ? "arrow.triangle.2.circlepath" : "externaldrive.connected.to.line.below")
                    .foregroundColor(statusColor)
                    .font(.title2)
                    .fontWeight(.medium)
                    .rotationEffect(connection.status == .checking ? .degrees(0) : .degrees(0))
                    .animation(connection.status == .checking ? 
                        Animation.linear(duration: 1.0).repeatForever(autoreverses: false) : 
                        .default, value: connection.status)
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
                
                HStack(spacing: 12) {
                    if !connection.remotePath.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(connection.remotePath)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    // Status Badge
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: statusIcon)
                                .font(.caption)
                                .foregroundColor(statusColor)
                            Text(connection.status.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(statusColor)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor)
                        .cornerRadius(10)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(BorderlessButtonStyle())
                
                if onDelete != nil {
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.red)
                            .cornerRadius(10)
                            .shadow(color: Color.red.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
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
                onDelete?()
            }
        } message: {
            Text("Are you sure you want to delete '\(connection.name)'? This will remove the connection from the Files app and cannot be undone.")
        }
    }
    
    private var statusColor: Color {
        switch connection.status {
        case .connected, .valid: return .green
        case .disconnected, .invalid, .error: return .red
        case .checking: return .blue
        case .timeout: return .orange
        case .unknown: return .gray
        }
    }
    
    private var statusIcon: String {
        switch connection.status {
        case .connected, .valid: return "checkmark.circle.fill"
        case .disconnected, .invalid, .error: return "xmark.octagon.fill"
        case .checking: return "arrow.triangle.2.circlepath"
        case .timeout: return "clock.badge.exclamationmark"
        case .unknown: return "questionmark.circle"
        }
    }
}
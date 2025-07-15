import SwiftUI
import BackgroundTasks
import FileProvider
import mft
import UIKit

// MARK: - Polling Manager
class ConnectionPollingManager: ObservableObject {
    @Published var pollingInterval: TimeInterval = 86400.0  // Default to once daily
    @Published var isPollingEnabled: Bool = true
    @Published var isFilesSyncEnabled: Bool = true
    @Published var backgroundRefreshStatus: UIBackgroundRefreshStatus = .available
    @Published var showBackgroundRefreshAlert: Bool = false
    @Published var isNATSEnabled: Bool = false
    @Published var lastSyncDate: Date?
    
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
        
        NSLog("SFTPFiles: Starting polling with interval: \(pollingInterval) seconds")
        
        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.performPollingCycle()
        }
        
        performPollingCycle()
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
    }
    
    func togglePolling(_ enabled: Bool) {
        isPollingEnabled = enabled
        saveSettings()
        if enabled {
            startPolling()
        } else {
            stopPolling()
        }
    }
    
    func toggleFilesSync(_ enabled: Bool) {
        isFilesSyncEnabled = enabled
        saveSettings()
    }
    
    func manualSync() {
        NSLog("SFTPFiles: Manual sync initiated")
        performPollingCycle()
    }
    
    private func performPollingCycle() {
        guard let viewModel = self.viewModel else { return }
        
        NSLog("SFTPFiles: Starting polling cycle")
        lastSyncDate = Date()
        
        let group = DispatchGroup()
        
        // Check all enabled connections
        for connection in viewModel.connections {
            if connection.isPollingEnabled {
                group.enter()
                checkConnection(connection) {
                    group.leave()
                }
            }
        }
        
        // After connection checks, sync Files app if enabled
        group.notify(queue: .main) {
            if self.isFilesSyncEnabled {
                self.syncFilesApp()
            }
            NSLog("SFTPFiles: Polling cycle completed")
        }
    }
    
    func checkConnection(_ connection: SFTPConnection, completion: @escaping () -> Void) {
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
            completion()
        }
    }
    
    private func syncFilesApp() {
        guard let viewModel = self.viewModel else { return }
        
        NSLog("SFTPFiles: Starting Files app sync")
        
        // First, get all domains
        NSFileProviderManager.getDomainsWithCompletionHandler { [weak self] domains, error in
            guard let self = self else { return }
            
            if let error = error {
                NSLog("SFTPFiles: Failed to get domains: \(error.localizedDescription)")
                return
            }
            
            let syncGroup = DispatchGroup()
            
            // For each connection, trigger sync
            for connection in viewModel.connections {
                let domainIdentifier = NSFileProviderDomainIdentifier(rawValue: connection.id.uuidString)
                
                if let domain = domains.first(where: { $0.identifier == domainIdentifier }) {
                    syncGroup.enter()
                    
                    let manager = NSFileProviderManager(for: domain)
                    
                    // Signal root container for re-enumeration
                    manager?.signalEnumerator(for: .rootContainer) { error in
                        if let error = error {
                            NSLog("SFTPFiles: Failed to signal root enumerator for \(connection.name): \(error.localizedDescription)")
                        } else {
                            NSLog("SFTPFiles: Successfully signaled root enumerator for \(connection.name)")
                        }
                        syncGroup.leave()
                    }
                    
                    // Also signal any cached working sets
                    syncGroup.enter()
                    manager?.signalEnumerator(for: .workingSet) { error in
                        if let error = error {
                            NSLog("SFTPFiles: Failed to signal working set for \(connection.name): \(error.localizedDescription)")
                        } else {
                            NSLog("SFTPFiles: Successfully signaled working set for \(connection.name)")
                        }
                        syncGroup.leave()
                    }
                    
                } else {
                    NSLog("SFTPFiles: Domain not found for connection: \(connection.name)")
                }
            }
            
            syncGroup.notify(queue: .main) {
                NSLog("SFTPFiles: Files app sync completed")
            }
        }
    }
    
    // Add force refresh method (Fixed: Remove disconnect/reconnect calls)
    func forceRefreshAllConnections() {
        NSLog("SFTPFiles: Force refreshing all connections")
        
        NSFileProviderManager.getDomainsWithCompletionHandler { domains, error in
            guard error == nil else {
                NSLog("SFTPFiles: Failed to get domains for force refresh: \(error!.localizedDescription)")
                return
            }
            
            for domain in domains {
                let manager = NSFileProviderManager(for: domain)
                
                // Signal enumerators for refresh instead of disconnect/reconnect
                manager?.signalEnumerator(for: .rootContainer) { error in
                    if let error = error {
                        NSLog("SFTPFiles: Failed to signal root enumerator for \(domain.displayName): \(error.localizedDescription)")
                    } else {
                        NSLog("SFTPFiles: Successfully signaled root enumerator for \(domain.displayName)")
                    }
                }
                
                manager?.signalEnumerator(for: .workingSet) { error in
                    if let error = error {
                        NSLog("SFTPFiles: Failed to signal working set for \(domain.displayName): \(error.localizedDescription)")
                    } else {
                        NSLog("SFTPFiles: Successfully signaled working set for \(domain.displayName)")
                    }
                }
            }
        }
    }
    
    private func loadSettings() {
        if let defaults = UserDefaults(suiteName: appGroupID) {
            let intervalValue = defaults.double(forKey: "pollingInterval")
            if intervalValue > 0 {
                pollingInterval = intervalValue
            }
            
            isPollingEnabled = defaults.object(forKey: "isPollingEnabled") == nil ? true : defaults.bool(forKey: "isPollingEnabled")
            isFilesSyncEnabled = defaults.object(forKey: "isFilesSyncEnabled") == nil ? true : defaults.bool(forKey: "isFilesSyncEnabled")
            isNATSEnabled = defaults.bool(forKey: "isNATSEnabled")
            
            if let lastSyncData = defaults.object(forKey: "lastSyncDate") as? Date {
                lastSyncDate = lastSyncData
            }
        }
    }
    
    private func saveSettings() {
        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.set(pollingInterval, forKey: "pollingInterval")
            defaults.set(isPollingEnabled, forKey: "isPollingEnabled")
            defaults.set(isFilesSyncEnabled, forKey: "isFilesSyncEnabled")
            defaults.set(isNATSEnabled, forKey: "isNATSEnabled")
            
            if let lastSync = lastSyncDate {
                defaults.set(lastSync, forKey: "lastSyncDate")
            }
            
            defaults.synchronize()
        }
    }
    
    func checkBackgroundRefreshStatus() {
        backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
        if backgroundRefreshStatus != .available && isPollingEnabled {
            showBackgroundRefreshAlert = true
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
            NSLog("SFTPFiles: Background App Refresh is disabled - connection monitoring will not work in background")
            showBackgroundRefreshAlert = true
        }
    }
    
    func scheduleBackgroundRefresh() {
        guard isPollingEnabled else { return }
        
        guard backgroundRefreshStatus == .available else {
            NSLog("SFTPFiles: Background App Refresh is disabled - cannot schedule background tasks")
            return
        }
        
        let request = BGAppRefreshTaskRequest(identifier: bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: pollingInterval)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            NSLog("SFTPFiles: Background refresh scheduled for \(pollingInterval) seconds")
        } catch {
            NSLog("SFTPFiles: Failed to schedule background refresh: \(error)")
        }
    }
    
    private func cancelBackgroundRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: bgTaskIdentifier)
    }
    
    func enableNATS(_ enabled: Bool) {
        isNATSEnabled = enabled
        saveSettings()
        
        if enabled {
            NSLog("SFTPFiles: NATS enabled - Files sync will be handled by NATS")
        } else {
            NSLog("SFTPFiles: NATS disabled - Files sync will use polling")
        }
        
        if isPollingEnabled {
            startPolling()
        }
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
        
        // Force refresh the domain
        NSFileProviderManager.remove(domain) { _ in
            // Small delay to ensure clean removal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
                            
                            // Trigger immediate sync after domain update
                            let manager = NSFileProviderManager(for: domain)
                            manager?.signalEnumerator(for: .rootContainer) { error in
                                if let error = error {
                                    NSLog("Failed to signal enumerator after update: \(error.localizedDescription)")
                                } else {
                                    NSLog("Successfully signaled enumerator after domain update")
                                }
                            }
                        }
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
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { 
                        viewModel.pollingManager.forceRefreshAllConnections()
                    }) {
                        Image(systemName: "arrow.clockwise")
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
                EnhancedSettingsView(viewModel: viewModel)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func refreshAllConnections() {
        NSLog("SFTPFiles: Manual refresh triggered")
        
        // Check if background refresh is available and disable polling for connections if not
        if viewModel.pollingManager.backgroundRefreshStatus != .available {
            for connection in viewModel.connections {
                if connection.isPollingEnabled {
                    viewModel.togglePolling(for: connection, enabled: false)
                }
            }
        }
        
        // Use the polling manager's manual sync
        viewModel.pollingManager.manualSync()
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
                
                // Add individual refresh button
                Button(action: {
                    refreshConnection()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.blue)
                        .cornerRadius(10)
                        .shadow(color: Color.blue.opacity(0.3), radius: 2, x: 0, y: 1)
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
    
    // Fixed: Add missing statusColor computed property
    private var statusColor: Color {
        switch connection.status {
        case .connected, .valid: return .green
        case .disconnected, .invalid, .error: return .red
        case .checking: return .blue
        case .timeout: return .orange
        case .unknown: return .gray
        }
    }
    
    // Fixed: Add missing statusIcon computed property
    private var statusIcon: String {
        switch connection.status {
        case .connected, .valid: return "checkmark.circle.fill"
        case .disconnected, .invalid, .error: return "xmark.octagon.fill"
        case .checking: return "arrow.triangle.2.circlepath"
        case .timeout: return "clock.badge.exclamationmark"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private func refreshConnection() {
        NSLog("SFTPFiles: Refreshing individual connection: \(connection.name)")
        
        // Test connection and update status
        viewModel.pollingManager.checkConnection(connection) {
            // After connection check, refresh the Files app for this connection
            refreshFilesAppForConnection()
        }
    }
    
    private func refreshFilesAppForConnection() {
        let domainIdentifier = NSFileProviderDomainIdentifier(rawValue: connection.id.uuidString)
        
        NSFileProviderManager.getDomainsWithCompletionHandler { domains, error in
            guard error == nil else {
                NSLog("SFTPFiles: Failed to get domains for individual refresh: \(error!.localizedDescription)")
                return
            }
            
            if let domain = domains.first(where: { $0.identifier == domainIdentifier }) {
                let manager = NSFileProviderManager(for: domain)
                
                // Use signaling instead of disconnect/reconnect for iOS compatibility
                manager?.signalEnumerator(for: .rootContainer) { error in
                    if let error = error {
                        NSLog("SFTPFiles: Failed to signal root enumerator for refresh: \(error.localizedDescription)")
                    } else {
                        NSLog("SFTPFiles: Successfully refreshed connection: \(connection.name)")
                    }
                }
                
                manager?.signalEnumerator(for: .workingSet) { error in
                    if let error = error {
                        NSLog("SFTPFiles: Failed to signal working set for refresh: \(error.localizedDescription)")
                    } else {
                        NSLog("SFTPFiles: Successfully signaled working set for refresh")
                    }
                }
            }
        }
    }
}
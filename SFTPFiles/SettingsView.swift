import SwiftUI
import UIKit

// MARK: - Polling Interval Options
enum PollingInterval: TimeInterval, CaseIterable, Identifiable {
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case oneHour = 3600
    case sixHours = 21600
    case twelveHours = 43200
    case onceDaily = 86400
    
    var id: TimeInterval { rawValue }
    
    var displayName: String {
        switch self {
        case .thirtySeconds: return "30 seconds"
        case .oneMinute: return "1 minute" 
        case .fiveMinutes: return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .sixHours: return "6 hours"
        case .twelveHours: return "12 hours"
        case .onceDaily: return "Once daily"
        }
    }
    
    var description: String {
        switch self {
        case .thirtySeconds, .oneMinute, .fiveMinutes:
            return "High frequency - may impact battery life"
        case .fifteenMinutes, .thirtyMinutes:
            return "Moderate frequency - balanced usage"
        case .oneHour, .sixHours:
            return "Low frequency - battery friendly"
        case .twelveHours, .onceDaily:
            return "Minimal frequency - maximum battery life"
        }
    }
    
    var batteryImpact: BatteryImpact {
        switch self {
        case .thirtySeconds, .oneMinute: return .high
        case .fiveMinutes, .fifteenMinutes: return .moderate
        case .thirtyMinutes, .oneHour: return .low
        case .sixHours, .twelveHours, .onceDaily: return .minimal
        }
    }
}

enum BatteryImpact {
    case high, moderate, low, minimal
    
    var color: Color {
        switch self {
        case .high: return .red
        case .moderate: return .orange
        case .low: return .yellow
        case .minimal: return .green
        }
    }
    
    var iconName: String {
        switch self {
        case .high: return "battery.25"
        case .moderate: return "battery.50"
        case .low: return "battery.75"
        case .minimal: return "battery.100"
        }
    }
}

struct PollingSettingsView: View {
    @ObservedObject var pollingManager: ConnectionPollingManager
    @State private var showingIntervalPicker = false
    @State private var isForceRefreshing = false
    
    private var currentInterval: PollingInterval {
        return PollingInterval(rawValue: pollingManager.pollingInterval) ?? .onceDaily
    }
    
    private var timeSinceLastSync: String {
        guard let lastSync = pollingManager.lastSyncDate else {
            return "Never"
        }
        
        let now = Date()
        let interval = now.timeIntervalSince(lastSync)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection Monitoring")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Automatic connection status checking")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            
            VStack(spacing: 16) {
                // Background App Refresh Warning
                if pollingManager.backgroundRefreshStatus != .available {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.orange)
                            
                            Text("Background App Refresh Required")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                        }
                        
                        Text("Connection monitoring will not work when the app is in the background. Enable Background App Refresh in Settings.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Button("Open Settings") {
                            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsUrl)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                }
                
                // Enable/Disable Polling Toggle
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Monitoring")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("Automatically check connection status in background")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { pollingManager.isPollingEnabled },
                        set: { pollingManager.togglePolling($0) }
                    ))
                    .labelsHidden()
                    .disabled(pollingManager.backgroundRefreshStatus != .available)
                    .opacity(pollingManager.backgroundRefreshStatus != .available ? 0.5 : 1.0)
                }
                .padding(.horizontal, 20)
                
                if pollingManager.isPollingEnabled {
                    Divider()
                        .padding(.horizontal, 20)
                    
                    // Polling Interval Selection
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Check Frequency")
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Button(action: { showingIntervalPicker = true }) {
                                HStack(spacing: 8) {
                                    Text(currentInterval.displayName)
                                        .font(.subheadline)
                                        .foregroundColor(.accentColor)
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        
                        // Battery Impact Indicator
                        HStack(spacing: 8) {
                            Image(systemName: currentInterval.batteryImpact.iconName)
                                .font(.system(size: 14))
                                .foregroundColor(currentInterval.batteryImpact.color)
                            
                            Text(currentInterval.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Divider()
                        .padding(.horizontal, 20)
                    
                    // Files App Sync Toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sync Files App")
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Text(pollingManager.isNATSEnabled ? 
                                 "Files sync handled by NATS" : 
                                 "Refresh file listings during monitoring")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { pollingManager.isFilesSyncEnabled },
                            set: { pollingManager.toggleFilesSync($0) }
                        ))
                        .labelsHidden()
                        .disabled(pollingManager.isNATSEnabled)
                        .opacity(pollingManager.isNATSEnabled ? 0.5 : 1.0)
                    }
                    .padding(.horizontal, 20)
                    
                    // Last Sync Information & Manual Controls
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Last Check")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text(timeSinceLastSync)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        
                        // Manual sync buttons
                        HStack(spacing: 12) {
                            Button(action: { pollingManager.manualSync() }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14, weight: .medium))
                                    
                                    Text("Check Now")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.accentColor)
                            }
                            
                            Spacer()
                            
                            Button(action: { forceRefreshAll() }) {
                                HStack(spacing: 8) {
                                    if isForceRefreshing {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    
                                    Text(isForceRefreshing ? "Refreshing..." : "Force Refresh")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isForceRefreshing ? Color.blue.opacity(0.5) : Color.blue)
                                )
                            }
                            .disabled(isForceRefreshing)
                        }
                        
                        // Force refresh explanation
                        if isForceRefreshing {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                
                                Text("Force refresh disconnects and reconnects all domains to clear cached data")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
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
        .sheet(isPresented: $showingIntervalPicker) {
            PollingIntervalPickerView(
                selectedInterval: currentInterval,
                onIntervalSelected: { interval in
                    pollingManager.updatePollingInterval(interval.rawValue)
                    showingIntervalPicker = false
                }
            )
        }
    }
    
    private func forceRefreshAll() {
        isForceRefreshing = true
        
        NSLog("SFTPFiles: Force refresh initiated from settings")
        pollingManager.forceRefreshAllConnections()
        
        // Reset the state after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            isForceRefreshing = false
        }
    }
}

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
                                    
                                    HStack(spacing: 20) {
                                        VStack(spacing: 4) {
                                            Text("\(viewModel.connections.count)")
                                                .font(.title2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.primary)
                                            
                                            Text("Total")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        VStack(spacing: 4) {
                                            Text("\(viewModel.connections.filter { $0.status.isHealthy }.count)")
                                                .font(.title2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.green)
                                            
                                            Text("Connected")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        VStack(spacing: 4) {
                                            Text("\(viewModel.connections.filter { !$0.status.isHealthy && $0.status != .unknown && $0.status != .checking }.count)")
                                                .font(.title2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.red)
                                            
                                            Text("Disconnected")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        VStack(spacing: 4) {
                                            Text("\(viewModel.connections.filter { $0.status == .checking }.count)")
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
                        
                        // Enhanced Polling Settings Section
                        PollingSettingsView(pollingManager: viewModel.pollingManager)
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
                            
                            VStack(alignment: .leading, spacing: 12) {
                                InfoRow(
                                    icon: "folder.badge.plus",
                                    title: "Finding Your Connections",
                                    description: "Look for your SFTP servers under 'Locations' in the Files app"
                                )
                                
                                InfoRow(
                                    icon: "wifi.exclamationmark",
                                    title: "Connection Issues",
                                    description: "Make sure your server is reachable and credentials are correct"
                                )
                                
                                InfoRow(
                                    icon: "arrow.clockwise",
                                    title: "Refresh Connections",
                                    description: "Pull down to refresh file listings in the Files app"
                                )
                                
                                InfoRow(
                                    icon: "battery.100",
                                    title: "Battery Optimization",
                                    description: "Use longer check intervals for better battery life"
                                )
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
            viewModel.clearAllConfigurations()

            DispatchQueue.main.async {
                self.isClearing = false

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }
}
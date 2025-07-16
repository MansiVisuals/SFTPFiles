import Foundation
import Combine

/// Polls SFTP connections at a regular interval and updates their status.
class PollingManager: ObservableObject {
    @Published var backgroundRefreshStatus: BackgroundRefreshStatus = .available
    private var timer: Timer?
    private let interval: TimeInterval
    private weak var viewModel: SFTPConnectionViewModel?
    
    init(viewModel: SFTPConnectionViewModel, interval: TimeInterval = 60) {
        self.viewModel = viewModel
        self.interval = interval
        startPolling()
    }
    
    func startPolling() {
        stopPolling()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollConnections()
        }
    }
    
    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
    
    private func pollConnections() {
        guard let viewModel = viewModel else { return }
        for connection in viewModel.connections where connection.isPollingEnabled {
            viewModel.testConnection(connection) { status in
                viewModel.updateStatus(for: connection, status: status)
            }
        }
    }
    
    deinit {
        stopPolling()
    }
}

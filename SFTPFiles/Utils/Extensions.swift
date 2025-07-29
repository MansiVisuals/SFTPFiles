//
//  Extensions.swift
//  SFTPFiles
//
//  Created by Maikel Mansi on 28/07/2025.
//

import Foundation
import SwiftUI

extension Date {
    func timeAgoDisplay() -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(self)
        
        if timeInterval < 60 {
            return "Just now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(timeInterval / 86400)
            if days < 7 {
                return "\(days) day\(days == 1 ? "" : "s") ago"
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return formatter.string(from: self)
            }
        }
    }
}

extension String {
    func isValidHostname() -> Bool {
        let hostnameRegex = "^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*|(?:[0-9]{1,3}\\.){3}[0-9]{1,3})$"
        return range(of: hostnameRegex, options: .regularExpression) != nil
    }
    
    func isValidPort() -> Bool {
        guard let port = Int(self) else { return false }
        return port > 0 && port <= 65535
    }
}

extension View {
    func settingsRowStyle() -> some View {
        self
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(Color(.systemBackground))
    }
}

extension Color {
    static let connectionGreen = Color.green
    static let connectionOrange = Color.orange
    static let connectionRed = Color.red
    static let connectionGray = Color.gray
}

//
//  ConnectionListView.swift
//  SFTPFiles
//
//  Created by Maikel Mansi on 28/07/2025.
//

import SwiftUI

struct ConnectionListView: View {
    @EnvironmentObject var connectionManager: SFTPConnectionManager
    @State private var showingAddConnection = false
    
    var body: some View {
        List {
            if !connectionManager.connections.isEmpty {
                Section {
                    ForEach(connectionManager.connections) { connection in
                        NavigationLink(destination: ConnectionDetailView(connection: connection, connectionManager: connectionManager)) {
                            SettingsConnectionRow(connection: connection)
                        }
                    }
                    .onDelete(perform: deleteConnections)
                } header: {
                    Text("SFTP Connections")
                } footer: {
                    Text("Connections will appear in the iOS Files app under 'Locations'")
                }
            }
            
            Section {
                Button(action: {
                    showingAddConnection = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                        
                        Text("Add SFTP Connection")
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
            
            if connectionManager.connections.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        
                        Text("No Connections")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Add your first SFTP server connection to get started. Connections will appear in the Files app.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
                .listRowBackground(Color(.systemGroupedBackground))
                .listRowInsets(EdgeInsets())
            }
            
            Section {
                NavigationLink("Settings") {
                    SettingsView()
                }
                
                NavigationLink("About") {
                    AboutView()
                }
            }
        }
        .navigationTitle("SFTP Files")
        .sheet(isPresented: $showingAddConnection) {
            AddConnectionView()
                .environmentObject(connectionManager)
        }
        .onAppear {
            connectionManager.loadConnections()
        }
    }
    
    private func deleteConnections(offsets: IndexSet) {
        connectionManager.deleteConnections(at: offsets)
    }
}

#Preview {
    NavigationView {
        ConnectionListView()
            .environmentObject(SFTPConnectionManager())
    }
}
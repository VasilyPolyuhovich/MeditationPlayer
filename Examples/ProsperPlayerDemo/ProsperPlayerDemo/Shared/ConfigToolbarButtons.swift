//
//  ConfigToolbarButtons.swift
//  ProsperPlayerDemo
//
//  Toolbar buttons for config info/editing in old-style demos
//  Works with AudioPlayerService directly (no DemoPlayerModel)
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

/// Toolbar buttons for configuration display/editing
/// Use in old-style demos that don't use DemoContainerView
struct ConfigToolbarButtons: View {
    let service: AudioPlayerService?
    let mode: ConfigDisplayMode
    
    @State private var currentConfig: PlayerConfiguration
    @State private var showingInfo = false
    @State private var showingEditor = false
    
    enum ConfigDisplayMode {
        case readOnly
        case editable
    }
    
    init(service: AudioPlayerService?, mode: ConfigDisplayMode = .readOnly) {
        self.service = service
        self.mode = mode
        // Initialize with default, will update in task
        _currentConfig = State(initialValue: .default)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Info button (read-only view)
            Button(action: { showingInfo = true }) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            .sheet(isPresented: $showingInfo) {
                NavigationStack {
                    ScrollView {
                        ConfigInfoView(config: currentConfig)
                            .padding()
                    }
                    .navigationTitle("Configuration")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingInfo = false }
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            
            // Settings button (editable view) - only for editable mode
            if mode == .editable {
                Button(action: { showingEditor = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .sheet(isPresented: $showingEditor) {
                    NavigationStack {
                        ScrollView {
                            ConfigEditorView(
                                config: $currentConfig,
                                onApply: { newConfig in
                                    try await applyConfiguration(newConfig)
                                }
                            )
                            .padding()
                        }
                        .navigationTitle("Settings")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { showingEditor = false }
                            }
                        }
                        .presentationDetents([.large])
                    }
                }
            }
        }
        .task {
            await updateCurrentConfig()
        }
    }
    
    private func updateCurrentConfig() async {
        guard let service = service else { return }
        // Get current config from service
        // Note: AudioPlayerService doesn't expose configuration publicly yet
        // For now, we'll use default and let user see it via info button
        // TODO: Add public API to get current configuration
        currentConfig = .default
    }
    
    private func applyConfiguration(_ newConfig: PlayerConfiguration) async throws {
        guard let service = service else { return }
        try await service.updateConfiguration(newConfig)
        currentConfig = newConfig
        showingEditor = false
    }
}

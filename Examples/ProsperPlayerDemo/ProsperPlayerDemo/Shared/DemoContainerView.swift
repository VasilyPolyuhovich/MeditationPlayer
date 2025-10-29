//
//  DemoContainerView.swift
//  ProsperPlayerDemo
//
//  Container view for demo screens - eliminates duplicate UI structure
//

import SwiftUI
import AudioServiceCore
import AudioServiceKit

/// Configuration display mode for demo views
enum ConfigMode {
    /// No configuration UI (default)
    case none
    
    /// Read-only info button showing current configuration
    case readOnly
    
    /// Settings button allowing configuration changes
    case editable
}

/// Container view providing standard layout for all demo screens
///
/// Provides:
/// - NavigationStack with title
/// - ScrollView with standard padding
/// - DemoHeader with icon and description
/// - StateInfoCard showing track and player state
/// - Error display
/// - Optional configuration buttons (info or settings)
/// - Custom content area for demo-specific controls
///
/// Eliminates ~150 LOC of duplicate structure per demo view.
struct DemoContainerView<Content: View>: View {
    
    // MARK: - Properties
    
    let title: String
    let icon: String
    let description: String
    let configMode: ConfigMode
    
    @Bindable var model: DemoPlayerModel
    
    @ViewBuilder let content: () -> Content
    
    // MARK: - Initialization
    
    init(
        title: String,
        icon: String,
        description: String,
        configMode: ConfigMode = .none,
        model: DemoPlayerModel,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.description = description
        self.configMode = configMode
        self.model = model
        self.content = content
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header with icon and description
                    DemoHeader(
                        icon: icon,
                        description: description
                    )
                    
                    // Track info and state
                    StateInfoCard(
                        trackName: model.currentTrack?.title,
                        state: model.state
                    )
                    
                    // Demo-specific controls
                    content()
                    
                    // Error display
                    if let error = model.error {
                        ErrorCard(message: error)
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    configToolbarButtons
                }
            }
            .task {
                // Update config when view appears and service is ready
                await updateCurrentConfig()
            }
        }
    }
    
    // MARK: - Toolbar Buttons
    
    @ViewBuilder
    private var configToolbarButtons: some View {
        switch configMode {
        case .none:
            EmptyView()
            
        case .readOnly:
            ConfigInfoButton(config: model.currentConfig)
            
        case .editable:
            HStack(spacing: 12) {
                ConfigInfoButton(config: model.currentConfig)
                ConfigEditorButton(config: Binding(
                    get: { model.currentConfig },
                    set: { _ in } // Binding is write-through via applyConfiguration
                ), onApply: applyConfiguration)
            }
        }
    }
    
    // MARK: - Configuration Management
    
    private func updateCurrentConfig() async {
        // Configuration is managed by DemoPlayerModel
        // Nothing to do here - model.currentConfig is always up to date
    }
    
    private func applyConfiguration(_ newConfig: PlayerConfiguration) async throws {
        // Delegate to model which handles service update and state tracking
        try await model.updateConfiguration(newConfig)
    }
}

// MARK: - Preview

#Preview("Simple Demo") {
    struct PreviewDemo: View {
        @State private var model: DemoPlayerModel?
        
        var body: some View {
            if let model = model {
                DemoContainerView(
                    title: "Simple Playback",
                    icon: "play.circle.fill",
                    description: "Load and play a single track",
                    model: model
                ) {
                    ControlsCard(title: "Controls", icon: "slider.horizontal.3") {
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                PlayButton(
                                    disabled: model.state == .playing
                                ) {
                                    print("Play tapped")
                                }
                                
                                PauseButton(
                                    disabled: model.state != .playing
                                ) {
                                    print("Pause tapped")
                                }
                            }
                            
                            StopButton(
                                disabled: model.state == .finished
                            ) {
                                print("Stop tapped")
                            }
                        }
                    }
                }
            } else {
                ProgressView()
                    .task {
                        model = try? await DemoPlayerModel()
                    }
            }
        }
    }
    
    return PreviewDemo()
}

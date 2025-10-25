//
//  DemoContainerView.swift
//  ProsperPlayerDemo
//
//  Container view for demo screens - eliminates duplicate UI structure
//

import SwiftUI
import AudioServiceCore

/// Container view providing standard layout for all demo screens
///
/// Provides:
/// - NavigationStack with title
/// - ScrollView with standard padding
/// - DemoHeader with icon and description
/// - StateInfoCard showing track and player state
/// - Error display
/// - Custom content area for demo-specific controls
///
/// Eliminates ~150 LOC of duplicate structure per demo view.
struct DemoContainerView<Content: View>: View {
    
    // MARK: - Properties
    
    let title: String
    let icon: String
    let description: String
    
    @Bindable var model: DemoPlayerModel
    
    @ViewBuilder let content: () -> Content
    
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
        }
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

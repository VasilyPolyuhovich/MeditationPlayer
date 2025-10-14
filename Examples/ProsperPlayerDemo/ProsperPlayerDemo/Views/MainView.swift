import SwiftUI
import AudioServiceCore

/// Main demonstration view - SDK showcase
struct MainView: View {
    @Bindable var viewModel: PlayerViewModel
    
    @State private var showPlaylists = false
    @State private var showSettings = false
    @State private var showOverlay = false
    @State private var showError = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // State & Position Display
                    StatusCard(viewModel: viewModel)
                    
                    // Crossfade Visualizer
                    if viewModel.isCrossfading {
                        CrossfadeVisualizer(progress: viewModel.crossfadeProgress)
                    }
                    
                    // Player Controls
                    PlayerControls(viewModel: viewModel)
                    
                    // Position Tracker
                    PositionTracker(position: viewModel.position)
                    
                    // Quick Actions
                    QuickActions(
                        onNextPlaylist: {
                            Task {
                                try? await viewModel.nextPlaylist()
                            }
                        },
                        onShowPlaylists: { showPlaylists = true },
                        onShowOverlay: { showOverlay = true },
                        onShowSettings: { showSettings = true }
                    )
                    
                    Spacer()
                    
                    // Version only
                    Text("Version 4.0.0")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            }
            .frame(maxWidth: .infinity)
            .navigationTitle("ProsperPlayer SDK")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPlaylists) {
                PlaylistsView(viewModel: viewModel)
            }
            .sheet(isPresented: $showOverlay) {
                OverlayView(viewModel: viewModel)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
            }
            .alert("Error", isPresented: $showError, presenting: viewModel.errorMessage) { _ in
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: { message in
                Text(message)
            }
            .onChange(of: viewModel.errorMessage) { _, newValue in
                showError = newValue != nil
            }
        }
    }
}

// MARK: - Status Card

struct StatusCard: View {
    let viewModel: PlayerViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            // State Badge
            HStack {
                Circle()
                    .fill(stateColor)
                    .frame(width: 12, height: 12)
                
                Text(viewModel.state.displayName)
                    .font(.headline)
                    .foregroundStyle(stateColor)
                
                Spacer()
                
                // Track Index
                if viewModel.currentTrackIndex >= 0 {
                    Text("Track \(viewModel.currentTrackIndex + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            
            // Position
            Text(viewModel.formattedPosition)
                .font(.title2)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var stateColor: Color {
        switch viewModel.state {
        case .playing: return .green
        case .paused: return .orange
        case .fadingOut, .preparing: return .blue
        case .failed: return .red
        case .finished: return .gray
        }
    }
}

// MARK: - Quick Actions

struct QuickActions: View {
    let onNextPlaylist: () -> Void
    let onShowPlaylists: () -> Void
    let onShowOverlay: () -> Void
    let onShowSettings: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Main actions
            HStack(spacing: 12) {
                Button {
                    onNextPlaylist()
                } label: {
                    Label("Next Playlist", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    onShowPlaylists()
                } label: {
                    Label("Playlists", systemImage: "music.note.list")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            
            // Secondary actions
            HStack(spacing: 12) {
                Button {
                    onShowOverlay()
                } label: {
                    Label("Overlay", systemImage: "waveform.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button {
                    onShowSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

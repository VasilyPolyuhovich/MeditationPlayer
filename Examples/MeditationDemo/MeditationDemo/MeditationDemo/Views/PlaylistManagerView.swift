import SwiftUI
import AudioServiceCore
import AudioServiceKit

/// Playlist management view with preset playlists and hot swap functionality
struct PlaylistManagerView: View {
    let viewModel: AudioPlayerViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedPreset: String = "Sample 1+2"
    @State private var customCrossfadeDuration: TimeInterval = 5.0
    @State private var isSwapping: Bool = false
    @State private var swapError: String?
    @State private var currentPlaylistTracks: [String] = []
    
    var body: some View {
        NavigationStack {
            Form {
                // Current Playlist Section
                Section {
                    currentPlaylistView
                } header: {
                    Text("Current Playlist")
                } footer: {
                    Text("Currently loaded tracks in playback order")
                }
                
                // Preset Playlists Section
                Section {
                    presetPlaylistsView
                } header: {
                    Text("Preset Playlists")
                } footer: {
                    Text("Quick access to predefined track combinations")
                }
                
                // Swap Configuration Section
                Section {
                    swapConfigurationView
                } header: {
                    Text("Swap Settings")
                } footer: {
                    Text("Crossfade duration applies only when playing. Paused state switches silently.")
                }
                
                // Swap Action Section
                Section {
                    swapActionView
                }
                
                // Error Display
                if let error = swapError {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Playlist Manager")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .disabled(isSwapping)
            .task {
                // Load current playlist on appear
                await loadCurrentPlaylist()
            }
        }
    }
    
    // MARK: - Current Playlist View
    
    private var currentPlaylistView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if currentPlaylistTracks.isEmpty {
                HStack {
                    Image(systemName: "music.note.list")
                        .foregroundStyle(.secondary)
                    Text("No playlist loaded")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(currentPlaylistTracks.enumerated()), id: \.offset) { index, track in
                    HStack {
                        // Track number badge
                        Text("\(index + 1)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(index == viewModel.currentTrackIndex ? Color.blue : Color.gray)
                            )
                        
                        // Track name
                        Text(track.uppercased())
                            .font(.subheadline)
                            .fontWeight(index == viewModel.currentTrackIndex ? .semibold : .regular)
                        
                        Spacer()
                        
                        // Currently playing indicator
                        if index == viewModel.currentTrackIndex && viewModel.isPlaying {
                            Image(systemName: "waveform")
                                .foregroundStyle(.blue)
                                .symbolEffect(.variableColor.iterative)
                        }
                    }
                }
            }
            
            // Playlist stats
            if !currentPlaylistTracks.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                
                HStack {
                    Label("\(currentPlaylistTracks.count) tracks", systemImage: "music.note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if viewModel.repeatMode != .off {
                        Label(
                            viewModel.repeatMode == .singleTrack ? "Single Loop" : "Playlist Loop",
                            systemImage: "repeat"
                        )
                        .font(.caption)
                        .foregroundStyle(.green)
                    }
                }
            }
        }
    }
    
    // MARK: - Preset Playlists View
    
    private var presetPlaylistsView: some View {
        VStack(spacing: 12) {
            ForEach(Array(AudioPlayerViewModel.presetPlaylists.keys.sorted()), id: \.self) { presetName in
                Button {
                    selectedPreset = presetName
                } label: {
                    HStack {
                        // Icon
                        Image(systemName: iconForPreset(presetName))
                            .foregroundStyle(selectedPreset == presetName ? .blue : .secondary)
                        
                        // Preset info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(presetName)
                                .fontWeight(selectedPreset == presetName ? .semibold : .regular)
                            
                            if let tracks = AudioPlayerViewModel.presetPlaylists[presetName] {
                                Text(tracks.map { $0.uppercased() }.joined(separator: " → "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Selection indicator
                        if selectedPreset == presetName {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedPreset == presetName ? Color.blue.opacity(0.1) : Color.clear)
                )
            }
        }
    }
    
    // MARK: - Swap Configuration View
    
    private var swapConfigurationView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Crossfade duration slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Crossfade Duration")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.1fs", customCrossfadeDuration))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                
                Slider(value: $customCrossfadeDuration, in: 1.0...30.0, step: 0.5)
            }
            
            // State-aware swap behavior
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
                
                Text(swapBehaviorText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Swap Action View
    
    private var swapActionView: some View {
        Button {
            Task {
                await performSwap()
            }
        } label: {
            HStack {
                if isSwapping {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                
                Text(isSwapping ? "Swapping..." : "Swap to \(selectedPreset)")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(canSwap ? Color.blue : Color.gray)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!canSwap || isSwapping)
    }
    
    // MARK: - Helpers
    
    private var swapBehaviorText: String {
        if viewModel.isPlaying {
            return "Currently playing: Smooth crossfade to new playlist"
        } else if viewModel.isPaused {
            return "Currently paused: Silent switch (no playback starts)"
        } else {
            return "Not playing: Swap will load new playlist"
        }
    }
    
    private var canSwap: Bool {
        guard let selectedTracks = AudioPlayerViewModel.presetPlaylists[selectedPreset] else {
            return false
        }
        
        // Can't swap to identical playlist
        return selectedTracks != currentPlaylistTracks
    }
    
    private func iconForPreset(_ presetName: String) -> String {
        switch presetName {
        case "Sample 1+2":
            return "1.circle.fill"
        case "Sample 3+4":
            return "3.circle.fill"
        case "Single Track":
            return "1.square.fill"
        case "All 4 Tracks":
            return "square.grid.2x2.fill"
        default:
            return "music.note"
        }
    }
    
    private func loadCurrentPlaylist() async {
        currentPlaylistTracks = await viewModel.getCurrentPlaylistNames()
    }
    
    private func performSwap() async {
        guard let selectedTracks = AudioPlayerViewModel.presetPlaylists[selectedPreset] else {
            swapError = "Invalid preset selection"
            return
        }
        
        // Clear previous error
        swapError = nil
        isSwapping = true
        
        do {
            // Call ViewModel's swap method
            try await viewModel.swapPlaylist(
                tracks: selectedTracks,
                crossfadeDuration: customCrossfadeDuration
            )
            
            // Reload playlist after swap
            await loadCurrentPlaylist()
            
            // Success - dismiss after brief delay
            try await Task.sleep(for: .milliseconds(500))
            dismiss()
        } catch {
            swapError = "Swap failed: \(error.localizedDescription)"
            isSwapping = false
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var viewModel = AudioPlayerViewModel(
        audioService: AudioPlayerService(
            configuration: PlayerConfiguration()
        )
    )
    
    PlaylistManagerView(viewModel: viewModel)
}

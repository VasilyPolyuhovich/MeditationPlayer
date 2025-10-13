import SwiftUI

/// Playlists management view - demonstrate hot swap functionality
struct PlaylistsView: View {
    @Bindable var viewModel: PlayerViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedPreset: String = "Two Tracks"
    @State private var isReplacing = false
    
    var body: some View {
        NavigationStack {
            List {
                // Current Playlist Section
                Section {
                    currentPlaylistInfo
                } header: {
                    Text("Current State")
                }
                
                // Preset Playlists Section
                Section {
                    ForEach(Array(PlayerViewModel.presets.keys.sorted()), id: \.self) { preset in
                        PresetRow(
                            name: preset,
                            tracks: PlayerViewModel.presets[preset] ?? [],
                            isSelected: selectedPreset == preset,
                            onSelect: { selectedPreset = preset }
                        )
                    }
                } header: {
                    Text("Preset Playlists")
                } footer: {
                    Text("Select a preset and tap Replace to swap playlist")
                }
                
                // Replace Action Section
                Section {
                    replaceButton
                } footer: {
                    Text(replaceBehaviorText)
                        .font(.caption)
                }
            }
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .disabled(isReplacing)
        }
    }
    
    // MARK: - Current Playlist Info
    
    private var currentPlaylistInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            // State
            HStack {
                Circle()
                    .fill(stateColor)
                    .frame(width: 10, height: 10)
                
                Text(viewModel.state.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            // Track Info
            if viewModel.position != nil {
                HStack {
                    Text("Track \(viewModel.currentTrackIndex + 1)")
                        .font(.caption)
                    
                    Spacer()
                    
                    Text(viewModel.formattedPosition)
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
            } else {
                Text("No playlist loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
    
    // MARK: - Replace Button
    
    private var replaceButton: some View {
        Button {
            Task {
                await performReplace()
            }
        } label: {
            HStack {
                if isReplacing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                
                Text(isReplacing ? "Replacing..." : "Replace Playlist")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(isReplacing)
    }
    
    // MARK: - Helpers
    
    private var replaceBehaviorText: String {
        if viewModel.isPlaying {
            return "🎵 Playing: Will crossfade to new playlist (\(String(format: "%.1fs", viewModel.crossfadeDuration)))"
        } else if viewModel.isPaused {
            return "⏸ Paused: Will switch silently (no playback starts)"
        } else {
            return "⏹ Stopped: Will load new playlist"
        }
    }
    
    private func performReplace() async {
        guard let tracks = PlayerViewModel.presets[selectedPreset] else { return }
        
        isReplacing = true
        defer { isReplacing = false }
        
        do {
            if viewModel.position == nil {
                // First load
                try await viewModel.loadPlaylist(tracks)
            } else {
                // Replace existing
                try await viewModel.replacePlaylist(tracks)
            }
            
            // Success - dismiss after brief delay
            try await Task.sleep(for: .milliseconds(500))
            dismiss()
        } catch {
            print("Replace failed: \(error)")
        }
    }
}

// MARK: - Preset Row

struct PresetRow: View {
    let name: String
    let tracks: [String]
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                    
                    Text(tracks.joined(separator: " → "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var viewModel = await PlayerViewModel(
        audioService: AudioPlayerService()
    )
    
    PlaylistsView(viewModel: viewModel)
}

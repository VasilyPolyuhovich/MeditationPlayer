//
//  CrossfadeBasicView.swift
//  ProsperPlayerDemo
//
//  Basic crossfade demo - seamless transitions between tracks
//  Core SDK functionality: dual-player architecture with automatic crossfades
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct CrossfadeBasicView: View {

    // MARK: - State (MV pattern)

    @State private var playerState: PlayerState = .finished
    @State private var currentTrack: String = "No track"
    @State private var nextTrack: String = "No track"
    @State private var errorMessage: String?
    @State private var audioService: AudioPlayerService?
    @State private var tracks: [Track] = []
    @State private var crossfadeDuration: Double = 5.0
    @State private var volume: Double = 0.8

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // Header
                    headerSection

                    // Track Info
                    trackInfoSection

                    // Configuration
                    ConfigurationView(
                        crossfadeDuration: $crossfadeDuration,
                        volume: $volume
                    )

                    // Controls
                    controlsSection

                    // Info
                    infoSection

                    // Error
                    if let error = errorMessage {
                        errorSection(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Basic Crossfade")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadResources()
                
                // AsyncStream: Reactive state updates (v3.1+)
                // Start AFTER loadResources completes to avoid race condition
                guard let service = audioService else { return }
                for await state in await service.stateUpdates {
                    playerState = state
                }
            }
            .onChange(of: crossfadeDuration) { _, newValue in
                Task {
                    await updateConfiguration()
                }
            }
            .onChange(of: volume) { _, newValue in
                Task {
                    await updateConfiguration()
                }
            }
        }
    }

    // MARK: - View Components

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Seamless transitions between tracks")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var trackInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Playback Info", systemImage: "music.note.list")
                .font(.headline)
                .foregroundStyle(.purple)

            HStack {
                Text("Current:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(currentTrack)
                    .fontWeight(.medium)
            }

            HStack {
                Text("Next:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(nextTrack)
                    .fontWeight(.medium)
                    .foregroundStyle(.purple.opacity(0.8))
            }

            HStack {
                Text("State:")
                    .foregroundStyle(.secondary)
                Spacer()
                stateLabel
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4)
        )
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch playerState {
        case .preparing:
            Label("Preparing", systemImage: "hourglass")
                .foregroundStyle(.orange)
        case .playing:
            Label("Playing", systemImage: "play.fill")
                .foregroundStyle(.green)
        case .paused:
            Label("Paused", systemImage: "pause.fill")
                .foregroundStyle(.orange)
        case .fadingOut:
            Label("Fading Out", systemImage: "speaker.wave.1")
                .foregroundStyle(.orange)
        case .finished:
            Label("Finished", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var controlsSection: some View {
        VStack(spacing: 12) {
            Label("Controls", systemImage: "play.circle")
                .font(.headline)
                .foregroundStyle(.purple)

            Button(action: { Task { await play() } }) {
                Label("Play Playlist (3 tracks)", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(playerState == .playing || audioService == nil || tracks.isEmpty)

            Button(action: { Task { await stop() } }) {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(playerState == .finished)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4)
        )
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How it works", systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.blue)

            Text("Dual-player crossfade architecture:")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("• Two AVAudioPlayers working together")
                Text("• Track 1 fades out while Track 2 fades in")
                Text("• Seamless gapless transitions")
                Text("• Adjust crossfade duration with slider")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.blue.opacity(0.1))
        )
    }

    private func errorSection(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
        )
    }

    // MARK: - Business Logic

    private func loadResources() async {
        // Load audio files
        let fileNames = ["stage1_intro_music", "stage2_practice_music", "stage3_closing_music"]

        for fileName in fileNames {
            guard let url = Bundle.main.url(forResource: fileName, withExtension: "mp3") else {
                continue
            }

            if let track = Track(url: url) {
                tracks.append(track)
            }
        }

        guard !tracks.isEmpty else {
            errorMessage = "Audio files not found"
            return
        }

        // Initialize audio service
        do {
            let config = PlayerConfiguration(
                crossfadeDuration: crossfadeDuration,
                repeatCount: nil,
                volume: Float(volume)
            )
            audioService = try await AudioPlayerService(configuration: config)
        } catch {
            errorMessage = "Failed to initialize service: \(error.localizedDescription)"
        }
    }

    private func updateConfiguration() async {
        guard let service = audioService else { return }

        let config = PlayerConfiguration(
            crossfadeDuration: crossfadeDuration,
            repeatCount: nil,
            volume: Float(volume)
        )

        do {
            try await service.updateConfiguration(config)
        } catch {
            errorMessage = "Failed to update config: \(error.localizedDescription)"
        }
    }

    private func play() async {
        guard let service = audioService, !tracks.isEmpty else { return }

        do {
            try await service.loadPlaylist(tracks)
            try await service.startPlaying(fadeDuration: 2.0)
            // ✅ State updates via AsyncStream (no manual polling needed)
            await updateTrackInfo()
            errorMessage = nil
        } catch {
            errorMessage = "Play error: \(error.localizedDescription)"
        }
    }

    private func stop() async {
        guard let service = audioService else { return }

        await service.stop()
        // ✅ State updates via AsyncStream (no manual polling needed)
        currentTrack = "No track"
        nextTrack = "No track"
    }

    private func updateTrackInfo() async {
        guard let service = audioService else { return }

        if let metadata = await service.currentTrack {
            if let title = metadata.title {
                currentTrack = title
            } else {
                currentTrack = "Track"
            }
        }

        // Note: nextTrack відображається автоматично під час crossfade
        // Це демонстраційний код, в реальності SDK не надає API для "next track"
        // але можна показати що завантажено в playlist
        if tracks.count > 1 {
            nextTrack = "Next track in playlist"
        }
    }
}

#Preview {
    CrossfadeBasicView()
}

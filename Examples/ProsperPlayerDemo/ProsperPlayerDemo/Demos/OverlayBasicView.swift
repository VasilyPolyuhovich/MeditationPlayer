//
//  OverlayBasicView.swift
//  ProsperPlayerDemo
//
//  Basic voice overlay demo - play voice guidance over background music
//  Shows playOverlay() API for guided meditation or coaching scenarios
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct OverlayBasicView: View {

    // MARK: - State (MV pattern)

    @State private var playerState: PlayerState = .finished
    @State private var currentTrack: String = "No track"
    @State private var overlayPlaying: Bool = false
    @State private var errorMessage: String?
    @State private var audioService: AudioPlayerService?
    @State private var backgroundTrack: Track?
    @State private var overlayTrack: Track?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection

                    // Progress
                    ProgressCard(service: audioService)
                        .id(audioService != nil ? "service-\(ObjectIdentifier(audioService!))" : "no-service")

                    trackInfoSection
                    controlsSection
                    infoSection

                    if let error = errorMessage {
                        errorSection(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Basic Overlay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    ConfigToolbarButtons(service: audioService, mode: .readOnly)
                }
            }
            .task {
                await loadResources()
                
                // AsyncStream: Reactive state updates (v3.1+)
                // Start AFTER loadResources completes to avoid race condition
                guard let service = audioService else { return }
                
                // Launch concurrent tasks for state and track updates
                async let stateTask: Void = {
                    for await state in await service.stateUpdates {
                        await MainActor.run {
                            playerState = state
                        }
                    }
                }()
                
                async let trackTask: Void = {
                    for await metadata in await service.trackUpdates {
                        await MainActor.run {
                            if let metadata = metadata {
                                currentTrack = metadata.title ?? "Track"
                            } else {
                                currentTrack = "No track"
                            }
                        }
                    }
                }()
                
                _ = await (stateTask, trackTask)
            }
        }
    }

    // MARK: - View Components

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 60))
                .foregroundStyle(.mint)

            Text("Voice guidance over background music")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var trackInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Playback Info", systemImage: "music.note")
                .font(.headline)
                .foregroundStyle(.mint)

            HStack {
                Text("Background:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(currentTrack)
                    .fontWeight(.medium)
            }

            HStack {
                Text("Overlay:")
                    .foregroundStyle(.secondary)
                Spacer()
                Label(
                    overlayPlaying ? "Playing" : "Silent",
                    systemImage: overlayPlaying ? "mic.fill" : "mic.slash.fill"
                )
                .foregroundStyle(overlayPlaying ? .mint : .secondary)
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
            Label("Controls", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.mint)

            Button(action: { Task { await playBackground() } }) {
                Label("Play Background Music", systemImage: "music.note")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(playerState == .playing || audioService == nil || backgroundTrack == nil)

            Button(action: { Task { await playOverlay() } }) {
                Label("Play Voice Overlay", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.mint)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(playerState != .playing || overlayPlaying || overlayTrack == nil)

            Button(action: { Task { await stopOverlay() } }) {
                Label("Stop Overlay", systemImage: "mic.slash.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!overlayPlaying)

            Button(action: { Task { await stop() } }) {
                Label("Stop All", systemImage: "stop.fill")
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

            Text("Voice overlay functionality:")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("1. Start background music")
                Text("2. Play voice overlay on top")
                Text("3. Both play simultaneously (no ducking)")
                Text("4. Stop overlay independently")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("Perfect for guided meditation or coaching!")
                .font(.caption2)
                .foregroundStyle(.mint)
                .padding(.top, 4)
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
        // Load background music
        guard let bgURL = Bundle.main.url(forResource: "stage2_practice_music", withExtension: "mp3"),
              let track = Track(url: bgURL) else {
            errorMessage = "Background music not found"
            return
        }
        backgroundTrack = track

        // Load voice overlay (Track, not SoundEffect!)
        guard let voiceURL = Bundle.main.url(forResource: "stage1_intro_music", withExtension: "mp3"),
              let track = Track(url: voiceURL) else {
            errorMessage = "Voice file not found"
            return
        }
        overlayTrack = track

        // Initialize audio service
        do {
            let config = PlayerConfiguration(
                crossfadeDuration: 0.0,
                repeatCount: nil,
                volume: 0.8
            )
            audioService = try await AudioPlayerService(configuration: config)
        } catch {
            errorMessage = "Failed to initialize service: \(error.localizedDescription)"
        }
    }

    private func playBackground() async {
        guard let service = audioService, let track = backgroundTrack else { return }

        do {
            try await service.loadPlaylist([track])
            try await service.startPlaying(fadeDuration: 2.0)
            // ✅ State updates via AsyncStream (no manual polling needed)
            currentTrack = "Background Music"
            errorMessage = nil
        } catch {
            errorMessage = "Play error: \(error.localizedDescription)"
        }
    }

    private func playOverlay() async {
        guard let service = audioService, let track = overlayTrack else { return }

        do {
            // ✅ Correct: playOverlay() for long voice guidance (Overlay Player)
            // ❌ Wrong: playSoundEffect() is for short sounds (Sound Effects Player)
            try await service.playOverlay(track)
            overlayPlaying = true
            errorMessage = nil
        } catch {
            errorMessage = "Overlay error: \(error.localizedDescription)"
        }
    }

    private func stopOverlay() async {
        guard let service = audioService else { return }

        await service.stopOverlay()
        overlayPlaying = false
    }

    private func stop() async {
        guard let service = audioService else { return }

        await service.stop()
        await service.stopOverlay()
        // ✅ State updates via AsyncStream (no manual polling needed)
        currentTrack = "No track"
        overlayPlaying = false
    }
}

#Preview {
    OverlayBasicView()
}

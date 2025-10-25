//
//  OverlaySwitchingView.swift
//  ProsperPlayerDemo
//
//  Multiple overlays demo - switch between different voice overlays
//  Shows playOverlay() with multiple Tracks for guided stages
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct OverlaySwitchingView: View {

    // MARK: - State (MV pattern)

    @State private var playerState: PlayerState = .finished
    @State private var currentTrack: String = "No track"
    @State private var currentOverlay: String = "None"
    @State private var overlayPlaying: Bool = false
    @State private var errorMessage: String?
    @State private var audioService: AudioPlayerService?
    @State private var backgroundTrack: Track?
    @State private var overlays: [String: Track] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    trackInfoSection
                    controlsSection
                    overlayButtons
                    infoSection

                    if let error = errorMessage {
                        errorSection(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Overlay Switching")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadResources()
            }
            .task {
                // AsyncStream: Reactive state updates (v3.1+)
                guard let service = audioService else { return }
                for await state in service.stateUpdates {
                    playerState = state
                }
            }
        }
    }

    // MARK: - View Components

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "shuffle.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.cyan)

            Text("Switch between multiple voice overlays")
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
                .foregroundStyle(.cyan)

            HStack {
                Text("Background:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(currentTrack)
                    .fontWeight(.medium)
            }

            HStack {
                Text("Active Overlay:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(currentOverlay)
                    .fontWeight(.medium)
                    .foregroundStyle(overlayPlaying ? .cyan : .secondary)
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
            Label("Background Controls", systemImage: "music.note")
                .font(.headline)
                .foregroundStyle(.cyan)

            Button(action: { Task { await playBackground() } }) {
                Label("Start Background Music", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(playerState == .playing || audioService == nil || backgroundTrack == nil)

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

    private var overlayButtons: some View {
        VStack(spacing: 12) {
            Label("Voice Overlays", systemImage: "person.wave.2.fill")
                .font(.headline)
                .foregroundStyle(.cyan)

            Button(action: { Task { await switchOverlay("Intro") } }) {
                Label("Intro Voice", systemImage: "1.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyan)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(playerState != .playing || overlays["Intro"] == nil)

            Button(action: { Task { await switchOverlay("Practice") } }) {
                Label("Practice Voice", systemImage: "2.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.mint)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(playerState != .playing || overlays["Practice"] == nil)

            Button(action: { Task { await switchOverlay("Closing") } }) {
                Label("Closing Voice", systemImage: "3.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.teal)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(playerState != .playing || overlays["Closing"] == nil)

            Button(action: { Task { await stopOverlay() } }) {
                Label("Stop Overlay", systemImage: "mic.slash.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!overlayPlaying)
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

            Text("Switch between multiple voice overlays:")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("1. Start background music")
                Text("2. Play any voice overlay")
                Text("3. Switch to different overlay instantly")
                Text("4. Previous overlay stops automatically")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("Perfect for multi-stage guided experiences!")
                .font(.caption2)
                .foregroundStyle(.cyan)
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

        // Load voice overlays
        let overlayFiles = [
            "Intro": "stage1_intro_music",
            "Practice": "stage2_practice_music",
            "Closing": "stage3_closing_music"
        ]

        for (name, fileName) in overlayFiles {
            guard let url = Bundle.main.url(forResource: fileName, withExtension: "mp3") else {
                continue
            }

            guard let track = Track(url: url) else {
                errorMessage = "Failed to load \(name): invalid audio file"
                continue
            }
            overlays[name] = track
        }

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

    private func switchOverlay(_ name: String) async {
        guard let service = audioService, let track = overlays[name] else { return }

        // Stop current overlay if playing
        if overlayPlaying {
            await service.stopOverlay()
        }

        // Play new overlay
        do {
            // ✅ Correct: playOverlay(track) for voice guidance (Overlay Player)
            // ❌ Wrong: playSoundEffect() is for short sounds (Sound Effects Player)
            try await service.playOverlay(track)
            overlayPlaying = true
            currentOverlay = name
            errorMessage = nil
        } catch {
            errorMessage = "Overlay error: \(error.localizedDescription)"
            overlayPlaying = false
            currentOverlay = "None"
        }
    }

    private func stopOverlay() async {
        guard let service = audioService else { return }

        await service.stopOverlay()
        overlayPlaying = false
        currentOverlay = "None"
    }

    private func stop() async {
        guard let service = audioService else { return }

        await service.stop()
        await service.stopOverlay()
        // ✅ State updates via AsyncStream (no manual polling needed)
        currentTrack = "No track"
        overlayPlaying = false
        currentOverlay = "None"
    }
}

#Preview {
    OverlaySwitchingView()
}

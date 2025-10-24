//
//  PauseResumeView.swift
//  ProsperPlayerDemo
//
//  Pause and resume demo - pause at any moment and resume
//  Shows critical functionality: pause during normal playback and crossfade
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct PauseResumeView: View {

    // MARK: - State (MV pattern)

    @State private var playerState: PlayerState = .finished
    @State private var currentTrack: String = "No track"
    @State private var errorMessage: String?
    @State private var audioService: AudioPlayerService?
    @State private var tracks: [Track] = []
    @State private var crossfadeDuration: Double = 5.0

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
                        volume: .constant(0.8)
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
            .navigationTitle("Pause & Resume")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadResources()
            }
            .onChange(of: crossfadeDuration) { _, newValue in
                Task {
                    await updateConfiguration(crossfadeDuration: newValue)
                }
            }
        }
    }

    // MARK: - View Components

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Pause at any moment and resume")
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
                .foregroundStyle(.orange)

            HStack {
                Text("Current:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(currentTrack)
                    .fontWeight(.medium)
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
                .foregroundStyle(.orange)

            Button(action: { Task { await play() } }) {
                Label("Start Playing (3 tracks)", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(playerState == .playing || audioService == nil || tracks.isEmpty)

            HStack(spacing: 12) {
                Button(action: { Task { await pause() } }) {
                    Label("Pause", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(playerState != .playing)

                Button(action: { Task { await resume() } }) {
                    Label("Resume", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(playerState != .paused)
            }

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

            Text("This demo plays 3 tracks with crossfade transitions. You can pause at any moment:")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("• During normal playback")
                Text("• During crossfade transition")
                Text("• Resume preserves exact position")
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
                volume: 0.8
            )
            audioService = try await AudioPlayerService(configuration: config)
        } catch {
            errorMessage = "Failed to initialize service: \(error.localizedDescription)"
        }
    }

    private func updateConfiguration(crossfadeDuration: Double) async {
        guard let service = audioService else { return }

        let config = PlayerConfiguration(
            crossfadeDuration: crossfadeDuration,
            repeatCount: nil,
            volume: 0.8
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
            playerState = await service.state
            await updateCurrentTrack()
            errorMessage = nil
        } catch {
            errorMessage = "Play error: \(error.localizedDescription)"
        }
    }

    private func pause() async {
        guard let service = audioService else { return }

        do {
            try await service.pause()
            playerState = await service.state
            errorMessage = nil
        } catch {
            errorMessage = "Pause error: \(error.localizedDescription)"
        }
    }

    private func resume() async {
        guard let service = audioService else { return }

        do {
            try await service.resume()
            playerState = await service.state
            await updateCurrentTrack()
            errorMessage = nil
        } catch {
            errorMessage = "Resume error: \(error.localizedDescription)"
        }
    }

    private func stop() async {
        guard let service = audioService else { return }

        await service.stop()
        playerState = await service.state
        currentTrack = "No track"
    }

    private func updateCurrentTrack() async {
        guard let service = audioService else { return }

        if let metadata = await service.currentTrack {
            if let title = metadata.title {
                currentTrack = title
            } else {
                currentTrack = "Track"
            }
        }
    }
}

#Preview {
    PauseResumeView()
}

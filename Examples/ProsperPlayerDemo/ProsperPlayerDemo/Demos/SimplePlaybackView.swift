//
//  SimplePlaybackView.swift
//  ProsperPlayerDemo
//
//  Basic playback demo - load and play single track
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct SimplePlaybackView: View {

    // MARK: - State (MV pattern - no ViewModels)

    @State private var playerState: PlayerState = .finished
    @State private var currentTrack: String = "No track"
    @State private var errorMessage: String?
    @State private var audioService: AudioPlayerService?
    @State private var track: Track?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // Header
                    headerSection

                    // Track Info
                    trackInfoSection

                    // Controls
                    controlsSection

                    // Error
                    if let error = errorMessage {
                        errorSection(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Simple Playback")
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
        }
    }

    // MARK: - View Components

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Load and play a single track")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var trackInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Track Info", systemImage: "music.note")
                .font(.headline)
                .foregroundStyle(.blue)

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
                .foregroundStyle(.blue)

            HStack(spacing: 12) {
                Button(action: { Task { await play() } }) {
                    Label("Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(playerState == .playing || audioService == nil || track == nil)

                Button(action: { Task { await pause() } }) {
                    Label("Pause", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(playerState != .playing)
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

    // MARK: - Business Logic (in view, MV pattern)

    private func loadResources() async {
        // Load audio file
        guard let url = Bundle.main.url(forResource: "stage1_intro_music", withExtension: "mp3") else {
            errorMessage = "Audio file not found"
            return
        }

        guard let loadedTrack = Track(url: url) else {
            errorMessage = "Failed to create track"
            return
        }

        track = loadedTrack
        currentTrack = "stage1_intro_music.mp3"

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

    private func play() async {
        guard let service = audioService, let track = track else { return }

        do {
            try await service.loadPlaylist([track])
            try await service.startPlaying(fadeDuration: 0.0)
            // ✅ State updates via AsyncStream (no manual polling needed)
            errorMessage = nil
        } catch {
            errorMessage = "Play error: \(error.localizedDescription)"
        }
    }

    private func pause() async {
        guard let service = audioService else { return }

        do {
            try await service.pause()
            // ✅ State updates via AsyncStream (no manual polling needed)
            errorMessage = nil
        } catch {
            errorMessage = "Pause error: \(error.localizedDescription)"
        }
    }

    private func stop() async {
        guard let service = audioService else { return }

        await service.stop()
        // ✅ State updates via AsyncStream (no manual polling needed)
        currentTrack = "No track"
    }
}

#Preview {
    SimplePlaybackView()
}

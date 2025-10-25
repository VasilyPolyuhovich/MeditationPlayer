//
//  FadeStartStopView.swift
//  ProsperPlayerDemo
//
//  Fade in/out demo - smooth fade in/out on start/stop
//  Critical functionality: startPlaying(fadeDuration:) and finish(fadeDuration:)
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct FadeStartStopView: View {

    // MARK: - State (MV pattern)

    @State private var playerState: PlayerState = .finished
    @State private var currentTrack: String = "No track"
    @State private var errorMessage: String?
    @State private var audioService: AudioPlayerService?
    @State private var track: Track?
    @State private var fadeInDuration: Double = 3.0
    @State private var fadeOutDuration: Double = 3.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // Header
                    headerSection

                    // Track Info
                    trackInfoSection

                    // Fade Configuration
                    fadeConfigSection

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
            .navigationTitle("Fade In/Out")
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
            Image(systemName: "waveform.path")
                .font(.system(size: 60))
                .foregroundStyle(.purple)

            Text("Smooth fade in/out on start/stop")
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
                .foregroundStyle(.purple)

            HStack {
                Text("Track:")
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

    private var fadeConfigSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Fade Configuration", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.purple)

            // Fade In
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Fade In Duration")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(fadeInDuration))s")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: $fadeInDuration, in: 0...10, step: 1)
                    .tint(.purple)

                Text("Volume gradually increases on start")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Fade Out
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Fade Out Duration")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(fadeOutDuration))s")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: $fadeOutDuration, in: 0...10, step: 1)
                    .tint(.purple)

                Text("Volume gradually decreases before stop")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4)
        )
    }

    private var controlsSection: some View {
        VStack(spacing: 12) {
            Label("Controls", systemImage: "play.circle")
                .font(.headline)
                .foregroundStyle(.purple)

            Button(action: { Task { await playWithFadeIn() } }) {
                Label("Play with Fade In", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(playerState == .playing || audioService == nil || track == nil)

            Button(action: { Task { await stopWithFadeOut() } }) {
                Label("Stop with Fade Out", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(playerState != .playing)
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

            Text("Demonstrates smooth volume transitions:")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("• Fade In: volume 0% → 100%")
                Text("• Fade Out: volume 100% → 0%")
                Text("• Adjust durations with sliders")
                Text("• Try 0s for instant start/stop")
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
        // Load audio file
        guard let url = Bundle.main.url(forResource: "stage2_practice_music", withExtension: "mp3") else {
            errorMessage = "Audio file not found"
            return
        }

        guard let loadedTrack = Track(url: url) else {
            errorMessage = "Failed to create track"
            return
        }

        track = loadedTrack
        currentTrack = "stage2_practice_music.mp3"

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

    private func playWithFadeIn() async {
        guard let service = audioService, let track = track else { return }

        do {
            try await service.loadPlaylist([track])
            try await service.startPlaying(fadeDuration: fadeInDuration)
            // ✅ State updates via AsyncStream (no manual polling needed)
            errorMessage = nil
        } catch {
            errorMessage = "Play error: \(error.localizedDescription)"
        }
    }

    private func stopWithFadeOut() async {
        guard let service = audioService else { return }

        do {
            try await service.finish(fadeDuration: fadeOutDuration)
            // ✅ State updates via AsyncStream (no manual polling needed)
            currentTrack = "Stopped"
        } catch {
            errorMessage = "Stop error: \(error.localizedDescription)"
        }
    }
}

#Preview {
    FadeStartStopView()
}

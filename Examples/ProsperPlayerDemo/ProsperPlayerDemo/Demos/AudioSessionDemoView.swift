//
//  AudioSessionDemoView.swift
//  ProsperPlayerDemo
//
//  Audio session compatibility demo - test with phone calls and other audio sources
//  Shows how SDK handles AVAudioSession interruptions and route changes
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct AudioSessionDemoView: View {

    // MARK: - State (MV pattern)

    @State private var playerState: PlayerState = .finished
    @State private var currentTrack: String = "No track"
    @State private var errorMessage: String?
    @State private var audioService: AudioPlayerService?
    @State private var track: Track?
    @State private var sessionInfo: String = "Not playing"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    trackInfoSection
                    sessionSection
                    controlsSection
                    infoSection

                    if let error = errorMessage {
                        errorSection(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Audio Session Test")
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
            Image(systemName: "speaker.wave.3")
                .font(.system(size: 60))
                .foregroundStyle(.brown)

            Text("Test audio session handling and interruptions")
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
                .foregroundStyle(.brown)

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

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Audio Session Status", systemImage: "waveform.circle")
                .font(.headline)
                .foregroundStyle(.brown)

            Text(sessionInfo)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Try these tests while playing:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("• Call yourself from another phone")
                Text("• Play music from another app")
                Text("• Connect/disconnect headphones")
                Text("• Switch to speaker/headphones")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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
                .foregroundStyle(.brown)

            Button(action: { Task { await play() } }) {
                Label("Start Playing", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(playerState == .playing || audioService == nil || track == nil)

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
            Label("Test Scenarios", systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.blue)

            Text("Audio session compatibility tests:")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("1. Start playback")
                Text("2. Trigger interruption (call, etc.)")
                Text("3. SDK should handle gracefully")
                Text("4. Resume should work correctly")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("The SDK uses AVAudioSession properly and handles all interruptions!")
                .font(.caption2)
                .foregroundStyle(.brown)
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
        // Load a long track for testing interruptions
        guard let url = Bundle.main.url(forResource: "stage2_practice_music", withExtension: "mp3"),
              let loadedTrack = Track(url: url) else {
            errorMessage = "Audio file not found"
            return
        }
        track = loadedTrack
        currentTrack = "Practice Music (long track)"

        // Initialize audio service
        do {
            let config = PlayerConfiguration(
                crossfadeDuration: 0.0,
                repeatCount: nil,
                volume: 0.8
            )
            audioService = try await AudioPlayerService(configuration: config)
            sessionInfo = "AudioService initialized - AVAudioSession configured"
        } catch {
            errorMessage = "Failed to initialize: \(error.localizedDescription)"
            sessionInfo = "Failed to configure audio session"
        }
    }

    private func play() async {
        guard let service = audioService, let track = track else { return }

        do {
            try await service.loadPlaylist([track])
            try await service.startPlaying(fadeDuration: 2.0)
            // ✅ State updates via AsyncStream (no manual polling needed)
            sessionInfo = "Playing - audio session active. Try interruptions!"
            errorMessage = nil
        } catch {
            errorMessage = "Play error: \(error.localizedDescription)"
            sessionInfo = "Playback failed"
        }
    }

    private func stop() async {
        guard let service = audioService else { return }

        await service.stop()
        // ✅ State updates via AsyncStream (no manual polling needed)
        currentTrack = "Practice Music (long track)"
        sessionInfo = "Stopped - audio session released"
    }
}

#Preview {
    AudioSessionDemoView()
}

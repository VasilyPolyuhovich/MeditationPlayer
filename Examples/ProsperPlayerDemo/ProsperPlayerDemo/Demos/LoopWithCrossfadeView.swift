//
//  LoopWithCrossfadeView.swift
//  ProsperPlayerDemo
//
//  Loop with crossfade demo - repeat playlist with crossfades
//  Shows repeatCount with crossfade functionality
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct LoopWithCrossfadeView: View {
    @State private var playerState: PlayerState = .finished
    @State private var currentTrack: String = "No track"
    @State private var errorMessage: String?
    @State private var audioService: AudioPlayerService?
    @State private var tracks: [Track] = []
    @State private var repeatCount: Double = 2.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    trackInfoSection
                    configSection
                    controlsSection
                    infoSection
                    if let error = errorMessage { errorSection(error) }
                }
                .padding()
            }
            .navigationTitle("Loop with Crossfade")
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
            .onChange(of: repeatCount) { _, _ in Task { await updateConfiguration() } }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "repeat.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            Text("Repeat playlist with crossfades")
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
                Text("Current:").foregroundStyle(.secondary)
                Spacer()
                Text(currentTrack).fontWeight(.medium)
            }
            HStack {
                Text("State:").foregroundStyle(.secondary)
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
        case .preparing: Label("Preparing", systemImage: "hourglass").foregroundStyle(.orange)
        case .playing: Label("Playing", systemImage: "play.fill").foregroundStyle(.green)
        case .paused: Label("Paused", systemImage: "pause.fill").foregroundStyle(.orange)
        case .fadingOut: Label("Fading Out", systemImage: "speaker.wave.1").foregroundStyle(.orange)
        case .finished: Label("Finished", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
        case .failed: Label("Failed", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Repeat Configuration", systemImage: "repeat")
                .font(.headline)
                .foregroundStyle(.orange)
            HStack {
                Text("Repeat Count")
                    .font(.subheadline)
                Spacer()
                Text("\(Int(repeatCount)) times")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $repeatCount, in: 1...5, step: 1)
                .tint(.orange)
            Text("Playlist will repeat this many times with crossfades between cycles")
                .font(.caption2)
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
                .foregroundStyle(.orange)
            Button(action: { Task { await play() } }) {
                Label("Start Playing", systemImage: "play.fill")
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
            Text("Repeat mode with crossfade:")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("• Set repeat count (1-5 times)")
                Text("• Crossfade between all tracks")
                Text("• Crossfade on playlist restart")
                Text("• Perfect for meditation loops")
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
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(message).font(.caption).foregroundStyle(.red)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.1)))
    }

    private func loadResources() async {
        let fileNames = ["stage1_intro_music", "stage2_practice_music", "stage3_closing_music"]
        for fileName in fileNames {
            guard let url = Bundle.main.url(forResource: fileName, withExtension: "mp3"),
                  let track = Track(url: url) else { continue }
            tracks.append(track)
        }
        guard !tracks.isEmpty else {
            errorMessage = "Audio files not found"
            return
        }
        do {
            let config = PlayerConfiguration(crossfadeDuration: 5.0, repeatCount: Int(repeatCount), volume: 0.8)
            audioService = try await AudioPlayerService(configuration: config)
        } catch {
            errorMessage = "Failed to initialize: \(error.localizedDescription)"
        }
    }

    private func updateConfiguration() async {
        guard let service = audioService else { return }
        let config = PlayerConfiguration(crossfadeDuration: 5.0, repeatCount: Int(repeatCount), volume: 0.8)
        try? await service.updateConfiguration(config)
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
    }

    private func updateTrackInfo() async {
        guard let service = audioService else { return }
        if let metadata = await service.currentTrack {
            currentTrack = metadata.title ?? "Track"
        }
    }
}

#Preview {
    LoopWithCrossfadeView()
}

//
//  OverlayWithDelaysView.swift
//  ProsperPlayerDemo
//
//  Overlay with delays demo - scheduled overlays with fade and repeat
//  Shows playOverlay() with OverlayConfiguration.loopDelay for timed stages
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct OverlayWithDelaysView: View {

    // MARK: - State (MV pattern)

    @State private var playerState: PlayerState = .finished
    @State private var currentTrack: String = "No track"
    @State private var overlayPlaying: Bool = false
    @State private var scheduledOverlays: [String] = []
    @State private var errorMessage: String?
    @State private var audioService: AudioPlayerService?
    @State private var backgroundTrack: Track?
    @State private var overlays: [String: Track] = [:]
    @State private var overlayDelay: Double = 5.0
    @State private var overlayFadeDuration: Double = 2.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    trackInfoSection
                    configSection
                    controlsSection
                    infoSection

                    if let error = errorMessage {
                        errorSection(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Overlay + Delays")
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
            Image(systemName: "timer.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.indigo)

            Text("Scheduled voice overlays with fade and delays")
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
                .foregroundStyle(.indigo)

            HStack {
                Text("Background:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(currentTrack)
                    .fontWeight(.medium)
            }

            HStack {
                Text("Overlay Status:")
                    .foregroundStyle(.secondary)
                Spacer()
                Label(
                    overlayPlaying ? "Playing" : "Idle",
                    systemImage: overlayPlaying ? "waveform" : "pause.circle"
                )
                .foregroundStyle(overlayPlaying ? .indigo : .secondary)
            }

            if !scheduledOverlays.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scheduled:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(scheduledOverlays, id: \.self) { name in
                        Text("• \(name)")
                            .font(.caption)
                            .foregroundStyle(.indigo)
                    }
                }
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

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Overlay Configuration", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.indigo)

            VStack(spacing: 8) {
                HStack {
                    Text("Delay Before Overlay")
                        .font(.subheadline)
                    Spacer()
                    Text("\(String(format: "%.1f", overlayDelay))s")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $overlayDelay, in: 1...15, step: 1)
                    .tint(.indigo)
            }

            VStack(spacing: 8) {
                HStack {
                    Text("Overlay Fade Duration")
                        .font(.subheadline)
                    Spacer()
                    Text("\(String(format: "%.1f", overlayFadeDuration))s")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $overlayFadeDuration, in: 0.5...5, step: 0.5)
                    .tint(.indigo)
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
                .foregroundStyle(.indigo)

            Button(action: { Task { await playBackground() } }) {
                Label("Start Background Music", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(playerState == .playing || audioService == nil || backgroundTrack == nil)

            Button(action: { Task { await scheduleOverlaySequence() } }) {
                Label("Schedule Overlay Sequence", systemImage: "timer")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(playerState != .playing || overlayPlaying)

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

            Text("Scheduled overlay with delays and fades:")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("1. Start background music")
                Text("2. Schedule overlay sequence")
                Text("3. Each overlay plays after delay")
                Text("4. Fade in/out configurable")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("Perfect for multi-stage meditation with timed guidance!")
                .font(.caption2)
                .foregroundStyle(.indigo)
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
        // Load background music (long track for demo)
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

    private func scheduleOverlaySequence() async {
        guard let service = audioService else { return }

        // Scheduled sequence: Intro -> Practice -> Closing with delays
        scheduledOverlays = ["Intro (pending)", "Practice (pending)", "Closing (pending)"]

        // Play Intro after delay
        Task {
            try? await Task.sleep(for: .seconds(overlayDelay))
            if let intro = overlays["Intro"] {
                scheduledOverlays[0] = "Intro (playing)"
                overlayPlaying = true
                try? await service.playOverlay(intro)
                try? await Task.sleep(for: .seconds(3)) // Simulate overlay duration
                overlayPlaying = false
                scheduledOverlays[0] = "Intro (done)"
            }
        }

        // Play Practice after 2x delay
        Task {
            try? await Task.sleep(for: .seconds(overlayDelay * 2))
            if let practice = overlays["Practice"] {
                scheduledOverlays[1] = "Practice (playing)"
                overlayPlaying = true
                try? await service.playOverlay(practice)
                try? await Task.sleep(for: .seconds(3))
                overlayPlaying = false
                scheduledOverlays[1] = "Practice (done)"
            }
        }

        // Play Closing after 3x delay
        Task {
            try? await Task.sleep(for: .seconds(overlayDelay * 3))
            if let closing = overlays["Closing"] {
                scheduledOverlays[2] = "Closing (playing)"
                overlayPlaying = true
                try? await service.playOverlay(closing)
                try? await Task.sleep(for: .seconds(3))
                overlayPlaying = false
                scheduledOverlays[2] = "Closing (done)"
            }
        }
    }

    private func stop() async {
        guard let service = audioService else { return }

        await service.stop()
        await service.stopOverlay()
        // ✅ State updates via AsyncStream (no manual polling needed)
        currentTrack = "No track"
        overlayPlaying = false
        scheduledOverlays = []
    }
}

#Preview {
    OverlayWithDelaysView()
}

//
//  ManualTransitionsView.swift
//  ProsperPlayerDemo
//
//  Manual track switch demo - skip to next/previous with fade
//  Shows skipToNext() API usage
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct ManualTransitionsView: View {

    // MARK: - State (MV pattern)

    @State private var playerState: PlayerState = .finished
    @State private var currentTrack: String = "No track"
    @State private var errorMessage: String?
    @State private var audioService: AudioPlayerService?
    @State private var tracks: [Track] = []

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
            .navigationTitle("Manual Transitions")
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

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "forward.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Skip tracks manually with crossfade")
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
                .foregroundStyle(.green)

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
        case .idle:
            Label("Idle", systemImage: "circle")
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.green)

            Button(action: { Task { await play() } }) {
                Label("Start Playing", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(playerState == .playing || audioService == nil || tracks.isEmpty)

            HStack(spacing: 12) {
                Button(action: { Task { await skipToNext() } }) {
                    Label("Skip to Next", systemImage: "forward.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
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

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How it works", systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.blue)

            Text("Manual track switching with skipToNext():")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("• Click Skip to Next to transition")
                Text("• Crossfade applies automatically")
                Text("• Navigate through playlist manually")
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
        let trackData: [(file: String, title: String, artist: String)] = [
            ("stage1_intro_music", "Opening Meditation", "Peaceful Sounds"),
            ("stage2_practice_music", "Deep Practice Session", "Mindful Music"),
            ("stage3_closing_music", "Closing Reflection", "Calm Melodies")
        ]
        
        for (fileName, title, artist) in trackData {
            guard let url = Bundle.main.url(forResource: fileName, withExtension: "mp3"),
                  let track = Track(url: url, title: title, artist: artist) else { continue }
            tracks.append(track)
        }

        guard !tracks.isEmpty else {
            errorMessage = "Audio files not found"
            return
        }

        do {
            let config = PlayerConfiguration(crossfadeDuration: 5.0, repeatCount: nil, volume: 0.8)
            audioService = try await AudioPlayerService(configuration: config)
        } catch {
            errorMessage = "Failed to initialize: \(error.localizedDescription)"
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

    private func skipToNext() async {
        print("🔵 [UI] skipToNext() button pressed")
        
        guard let service = audioService else { 
            print("🔴 [UI] No audio service")
            return 
        }
        
        do {
            print("🔵 [UI] Calling service.skipToNext()...")
            try await service.skipToNext()
            print("🟢 [UI] service.skipToNext() completed successfully")
            // ✅ State updates via AsyncStream (no manual polling needed)
            await updateTrackInfo()
            errorMessage = nil
        } catch {
            print("🔴 [UI] skipToNext() failed: \(error)")
            print("🔴 [UI] Error type: \(type(of: error))")
            print("🔴 [UI] Localized: \(error.localizedDescription)")
            
            // Haptic feedback for rate limited errors
            if case AudioPlayerError.rateLimited = error {
                #if canImport(UIKit)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                #endif
            }
            
            errorMessage = "Skip error: \(error.localizedDescription)"
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
    ManualTransitionsView()
}

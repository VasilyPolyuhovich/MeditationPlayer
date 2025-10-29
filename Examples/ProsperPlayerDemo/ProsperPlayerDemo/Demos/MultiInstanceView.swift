//
//  MultiInstanceView.swift
//  ProsperPlayerDemo
//
//  Multiple players demo - run 2+ AudioPlayerService instances simultaneously
//  Shows that SDK supports multiple independent players
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct MultiInstanceView: View {

    // MARK: - State (MV pattern)

    @State private var player1State: PlayerState = .finished
    @State private var player2State: PlayerState = .finished
    @State private var player1Track: String = "No track"
    @State private var player2Track: String = "No track"
    @State private var errorMessage: String?
    @State private var audioService1: AudioPlayerService?
    @State private var audioService2: AudioPlayerService?
    @State private var track1: Track?
    @State private var track2: Track?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection

                    // Player 1 Progress
                    ProgressCard(service: audioService1)
                        .id(audioService1 != nil ? "service1-\(ObjectIdentifier(audioService1!))" : "no-service1")

                    player1Section

                    // Player 2 Progress
                    ProgressCard(service: audioService2)
                        .id(audioService2 != nil ? "service2-\(ObjectIdentifier(audioService2!))" : "no-service2")

                    player2Section
                    infoSection

                    if let error = errorMessage {
                        errorSection(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Multiple Players")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    ConfigToolbarButtons(service: nil, mode: .readOnly)
                }
            }
            .task {
                await loadResources()
                
                // AsyncStream: Start both players AFTER loadResources completes
                // to avoid race condition. Use Task group for concurrent streams.
                await withTaskGroup(of: Void.self) { group in
                    // Player 1 state stream
                    group.addTask { @MainActor in
                        guard let service = audioService1 else { return }
                        for await state in await service.stateUpdates {
                            player1State = state
                        }
                    }
                    
                    // Player 1 track stream
                    group.addTask { @MainActor in
                        guard let service = audioService1 else { return }
                        for await metadata in await service.trackUpdates {
                            if let metadata = metadata {
                                player1Track = metadata.title ?? "Track"
                            } else {
                                player1Track = "No track"
                            }
                        }
                    }
                    
                    // Player 2 state stream
                    group.addTask { @MainActor in
                        guard let service = audioService2 else { return }
                        for await state in await service.stateUpdates {
                            player2State = state
                        }
                    }
                    
                    // Player 2 track stream
                    group.addTask { @MainActor in
                        guard let service = audioService2 else { return }
                        for await metadata in await service.trackUpdates {
                            if let metadata = metadata {
                                player2Track = metadata.title ?? "Track"
                            } else {
                                player2Track = "No track"
                            }
                        }
                    }
                    
                    // Wait for all tasks
                    await group.waitForAll()
                }
            }
        }
    }

    // MARK: - View Components

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "squares.leading.rectangle")
                .font(.system(size: 60))
                .foregroundStyle(.pink)

            Text("Run two AudioPlayerService instances simultaneously")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var player1Section: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Player 1", systemImage: "1.circle.fill")
                .font(.headline)
                .foregroundStyle(.pink)

            HStack {
                Text("Track:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(player1Track)
                    .fontWeight(.medium)
            }

            HStack {
                Text("State:")
                    .foregroundStyle(.secondary)
                Spacer()
                stateLabel(for: player1State)
            }

            HStack(spacing: 12) {
                Button(action: { Task { await playPlayer1() } }) {
                    Label("Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.pink)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(player1State == .playing || audioService1 == nil || track1 == nil)

                Button(action: { Task { await stopPlayer1() } }) {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(player1State == .finished)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4)
        )
    }

    private var player2Section: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Player 2", systemImage: "2.circle.fill")
                .font(.headline)
                .foregroundStyle(.purple)

            HStack {
                Text("Track:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(player2Track)
                    .fontWeight(.medium)
            }

            HStack {
                Text("State:")
                    .foregroundStyle(.secondary)
                Spacer()
                stateLabel(for: player2State)
            }

            HStack(spacing: 12) {
                Button(action: { Task { await playPlayer2() } }) {
                    Label("Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(player2State == .playing || audioService2 == nil || track2 == nil)

                Button(action: { Task { await stopPlayer2() } }) {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(player2State == .finished)
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
    private func stateLabel(for state: PlayerState) -> some View {
        switch state {
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

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How it works", systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.blue)

            Text("Multiple independent AudioPlayerService instances:")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("• Each player has own state")
                Text("• Play both simultaneously")
                Text("• Independent controls")
                Text("• No interference between players")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("Perfect for complex audio scenarios like games or multi-track apps!")
                .font(.caption2)
                .foregroundStyle(.pink)
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
        // Load track 1
        guard let url1 = Bundle.main.url(forResource: "stage1_intro_music", withExtension: "mp3"),
              let t1 = Track(url: url1) else {
            errorMessage = "Track 1 not found"
            return
        }
        track1 = t1
        player1Track = "Intro Music"

        // Load track 2
        guard let url2 = Bundle.main.url(forResource: "stage2_practice_music", withExtension: "mp3"),
              let t2 = Track(url: url2) else {
            errorMessage = "Track 2 not found"
            return
        }
        track2 = t2
        player2Track = "Practice Music"

        // Initialize player 1
        do {
            let config1 = PlayerConfiguration(
                crossfadeDuration: 0.0,
                repeatCount: nil,
                volume: 0.7
            )
            audioService1 = try await AudioPlayerService(configuration: config1)
        } catch {
            errorMessage = "Failed to init player 1: \(error.localizedDescription)"
        }

        // Initialize player 2
        do {
            let config2 = PlayerConfiguration(
                crossfadeDuration: 0.0,
                repeatCount: nil,
                volume: 0.7
            )
            audioService2 = try await AudioPlayerService(configuration: config2)
        } catch {
            errorMessage = "Failed to init player 2: \(error.localizedDescription)"
        }
    }

    private func playPlayer1() async {
        guard let service = audioService1, let track = track1 else { return }

        do {
            try await service.loadPlaylist([track])
            try await service.startPlaying(fadeDuration: 1.0)
            // ✅ State updates via AsyncStream (no manual polling needed)
            errorMessage = nil
        } catch {
            errorMessage = "Player 1 error: \(error.localizedDescription)"
        }
    }

    private func stopPlayer1() async {
        guard let service = audioService1 else { return }

        await service.stop()
        // ✅ State updates via AsyncStream (no manual polling needed)
    }

    private func playPlayer2() async {
        guard let service = audioService2, let track = track2 else { return }

        do {
            try await service.loadPlaylist([track])
            try await service.startPlaying(fadeDuration: 1.0)
            // ✅ State updates via AsyncStream (no manual polling needed)
            errorMessage = nil
        } catch {
            errorMessage = "Player 2 error: \(error.localizedDescription)"
        }
    }

    private func stopPlayer2() async {
        guard let service = audioService2 else { return }

        await service.stop()
        // ✅ State updates via AsyncStream (no manual polling needed)
    }
}

#Preview {
    MultiInstanceView()
}

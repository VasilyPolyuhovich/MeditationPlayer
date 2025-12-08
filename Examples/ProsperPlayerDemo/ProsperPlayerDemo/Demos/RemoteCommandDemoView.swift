//
//  RemoteCommandDemoView.swift
//  ProsperPlayerDemo
//
//  Demonstrates customizing lock screen and Control Center controls
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore
import MediaPlayer

// MARK: - Custom Remote Command Delegate

/// Example delegate that customizes lock screen behavior
@MainActor
final class CustomRemoteCommandDelegate: RemoteCommandDelegate {
    
    // Callback to update UI when commands are triggered
    var onCommandReceived: ((String) -> Void)?
    
    // Track chapter navigation (example use case)
    private var currentChapter = 0
    private let totalChapters = 5
    
    // MARK: - Configuration
    
    func remoteCommandEnabledCommands() -> RemoteCommandOptions {
        // Only enable play, pause, and track navigation
        // Skip forward/backward will act as chapter navigation
        [.play, .pause, .togglePlayPause, .skipForward, .skipBackward]
    }
    
    func remoteCommandSkipIntervals() -> (forward: TimeInterval, backward: TimeInterval) {
        // 30 second intervals instead of default 15
        (forward: 30.0, backward: 30.0)
    }
    
    // MARK: - Custom Now Playing Info
    
    func remoteCommandNowPlayingInfo(
        for track: Track.Metadata,
        position: PlaybackPosition
    ) -> [String: Any]? {
        // Provide completely custom Now Playing info
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "Meditation Session",
            MPMediaItemPropertyArtist: "ProsperPlayer Demo",
            MPMediaItemPropertyAlbumTitle: "Chapter \(currentChapter + 1) of \(totalChapters)"
        ]
        
        // Include duration and elapsed time
        info[MPMediaItemPropertyPlaybackDuration] = position.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position.currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        
        return info
    }
    
    // MARK: - Command Handlers
    
    func remoteCommandShouldHandlePlay() async -> Bool {
        onCommandReceived?("Play command received")
        return true // Use SDK default behavior
    }
    
    func remoteCommandShouldHandlePause() async -> Bool {
        onCommandReceived?("Pause command received")
        return true // Use SDK default behavior
    }
    
    func remoteCommandShouldHandleSkipForward(_ interval: TimeInterval) async -> Bool {
        // Custom behavior: next chapter instead of skip
        currentChapter = min(currentChapter + 1, totalChapters - 1)
        onCommandReceived?("Next chapter: \(currentChapter + 1)")
        
        // Return false = we handled it, skip SDK default
        // In real app, you might load next chapter here
        return true // For demo, still do the time skip
    }
    
    func remoteCommandShouldHandleSkipBackward(_ interval: TimeInterval) async -> Bool {
        // Custom behavior: previous chapter instead of skip
        currentChapter = max(currentChapter - 1, 0)
        onCommandReceived?("Previous chapter: \(currentChapter + 1)")
        
        return true // For demo, still do the time skip
    }
}

// MARK: - Demo View

struct RemoteCommandDemoView: View {
    
    // MARK: - State
    
    @State private var playerState: PlayerState = .finished
    @State private var audioService: AudioPlayerService?
    @State private var track: Track?
    @State private var errorMessage: String?
    @State private var lastCommand: String = "No commands yet"
    @State private var delegateEnabled = false
    
    // Keep delegate alive
    @State private var customDelegate: CustomRemoteCommandDelegate?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // Header
                    headerSection
                    
                    // Progress
                    ProgressCard(service: audioService)
                        .id(audioService != nil ? "service-\(ObjectIdentifier(audioService!))" : "no-service")
                    
                    // Delegate Toggle
                    delegateToggleSection
                    
                    // Last Command
                    lastCommandSection
                    
                    // Controls
                    controlsSection
                    
                    // Instructions
                    instructionsSection
                    
                    // Error
                    if let error = errorMessage {
                        errorSection(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Remote Commands")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadResources()
                await setupStateObserver()
            }
        }
    }
    
    // MARK: - View Sections
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.rectangle.on.rectangle")
                .font(.system(size: 60))
                .foregroundStyle(.pink)
            
            Text("Lock Screen & Control Center")
                .font(.headline)
            
            Text("Customize remote control behavior")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
    
    private var delegateToggleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Remote Command Delegate", systemImage: "gearshape.2")
                .font(.headline)
                .foregroundStyle(.pink)
            
            Toggle(isOn: $delegateEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom Delegate")
                        .fontWeight(.medium)
                    Text(delegateEnabled ? "30s skip intervals, custom Now Playing" : "SDK defaults (15s skip)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: delegateEnabled) { _, newValue in
                Task {
                    await toggleDelegate(enabled: newValue)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4)
        )
    }
    
    private var lastCommandSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Last Command", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
                .foregroundStyle(.blue)
            
            Text(lastCommand)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(lastCommand == "No commands yet" ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
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
                .disabled(playerState == .playing || audioService == nil)
                
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
    
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("How to Test", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(.green)
            
            VStack(alignment: .leading, spacing: 8) {
                instructionRow(number: 1, text: "Start playback")
                instructionRow(number: 2, text: "Lock the device or open Control Center")
                instructionRow(number: 3, text: "Toggle delegate ON/OFF to see differences")
                instructionRow(number: 4, text: "With delegate: 30s skip, custom metadata")
                instructionRow(number: 5, text: "Without delegate: 15s skip, track metadata")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.green.opacity(0.1))
        )
    }
    
    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .fontWeight(.bold)
                .foregroundStyle(.green)
            Text(text)
                .font(.subheadline)
        }
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
    
    // MARK: - Logic
    
    private func loadResources() async {
        guard let url = Bundle.main.url(forResource: "stage2_practice_music", withExtension: "mp3") else {
            errorMessage = "Audio file not found"
            return
        }
        
        guard let loadedTrack = Track(
            url: url,
            title: "Meditation Music",
            artist: "ProsperPlayer"
        ) else {
            errorMessage = "Failed to create track"
            return
        }
        
        track = loadedTrack
        
        do {
            let config = PlayerConfiguration(
                crossfadeDuration: 0.0,
                volume: 0.8
            )
            audioService = try await AudioPlayerService(configuration: config)
        } catch {
            errorMessage = "Failed to initialize: \(error.localizedDescription)"
        }
    }
    
    private func setupStateObserver() async {
        guard let service = audioService else { return }
        
        for await state in await service.stateUpdates {
            await MainActor.run {
                playerState = state
            }
        }
    }
    
    private func toggleDelegate(enabled: Bool) async {
        guard let service = audioService else { return }
        
        if enabled {
            let delegate = CustomRemoteCommandDelegate()
            delegate.onCommandReceived = { command in
                lastCommand = command
            }
            customDelegate = delegate
            await service.setRemoteCommandDelegate(delegate)
            lastCommand = "Custom delegate enabled"
        } else {
            customDelegate = nil
            await service.setRemoteCommandDelegate(nil)
            lastCommand = "Using SDK defaults"
        }
    }
    
    private func play() async {
        guard let service = audioService, let track = track else { return }
        
        do {
            try await service.loadPlaylist([track])
            try await service.startPlaying(fadeDuration: 0.5)
            errorMessage = nil
        } catch {
            errorMessage = "Play error: \(error.localizedDescription)"
        }
    }
    
    private func pause() async {
        guard let service = audioService else { return }
        
        do {
            try await service.pause()
        } catch {
            errorMessage = "Pause error: \(error.localizedDescription)"
        }
    }
    
    private func stop() async {
        guard let service = audioService else { return }
        await service.stop()
    }
}

#Preview {
    RemoteCommandDemoView()
}

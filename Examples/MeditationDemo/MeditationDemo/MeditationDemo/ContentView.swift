import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct ContentView: View {
    @Environment(\.audioService) private var audioService
    @State private var playerState: PlayerState = .finished
    @State private var playbackPosition: PlaybackPosition?
    @State private var currentTrack: TrackInfo?
    @State private var volume: Float = 1.0
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Status Display
                VStack(spacing: 10) {
                    Text("Prosper Player")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text(stateText)
                        .font(.title3)
                        .foregroundColor(stateColor)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(stateColor.opacity(0.2))
                        .cornerRadius(10)
                }
                
                // Track Info
                if let track = currentTrack {
                    VStack(spacing: 8) {
                        Text(track.title ?? "Unknown Track")
                            .font(.headline)
                        
                        if let artist = track.artist {
                            Text(artist)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("Duration: \(formatTime(track.duration))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(15)
                }
                
                // Playback Progress
                if let position = playbackPosition {
                    VStack(spacing: 10) {
                        ProgressView(value: position.progress)
                            .progressViewStyle(LinearProgressViewStyle())
                        
                        HStack {
                            Text(formatTime(position.currentTime))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text(formatTime(position.duration))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Control Buttons
                VStack(spacing: 20) {
                    // Play/Pause/Resume
                    HStack(spacing: 30) {
                        Button(action: skipBackward) {
                            Image(systemName: "gobackward.15")
                                .font(.system(size: 30))
                        }
                        .disabled(!canSkip)
                        
                        Button(action: togglePlayPause) {
                            Image(systemName: playPauseIcon)
                                .font(.system(size: 50))
                        }
                        .disabled(!canTogglePlay)
                        
                        Button(action: skipForward) {
                            Image(systemName: "goforward.15")
                                .font(.system(size: 30))
                        }
                        .disabled(!canSkip)
                    }
                    
                    // Start/Stop buttons
                    HStack(spacing: 20) {
                        Button("Start Demo") {
                            startPlayback()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(playerState == .playing || playerState == .preparing)
                        
                        Button("Stop") {
                            stopPlayback()
                        }
                        .buttonStyle(.bordered)
                        .disabled(playerState == .finished || playerState == .failed(.unknown(reason: "")))
                    }
                }
                .padding()
                
                // Volume Control
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "speaker.fill")
                        Slider(value: $volume, in: 0...1)
                            .onChange(of: volume) { _, newValue in
                                Task {
                                    await audioService.setVolume(newValue)
                                }
                            }
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    .padding(.horizontal)
                    
                    Text("Volume: \(Int(volume * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Audio Player Demo")
            .alert("Error", isPresented: $showError) {
                Button("OK") { showError = false }
            } message: {
                Text(errorMessage)
            }
            .task {
                await observePlayerState()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var stateText: String {
        switch playerState {
        case .preparing:
            return "Preparing..."
        case .playing:
            return "▶ Playing"
        case .paused:
            return "⏸ Paused"
        case .fadingOut:
            return "Fading Out..."
        case .finished:
            return "Ready"
        case .failed(let error):
            return "Error: \(error.localizedDescription)"
        }
    }
    
    private var stateColor: Color {
        switch playerState {
        case .preparing:
            return .orange
        case .playing:
            return .green
        case .paused:
            return .blue
        case .fadingOut:
            return .orange
        case .finished:
            return .gray
        case .failed:
            return .red
        }
    }
    
    private var playPauseIcon: String {
        switch playerState {
        case .playing:
            return "pause.circle.fill"
        case .paused:
            return "play.circle.fill"
        default:
            return "play.circle"
        }
    }
    
    private var canTogglePlay: Bool {
        playerState == .playing || playerState == .paused
    }
    
    private var canSkip: Bool {
        playerState == .playing
    }
    
    // MARK: - Actions
    
    private func startPlayback() {
        Task {
            do {
                // For demo purposes, use a sample audio file
                // In a real app, you would select a file from the bundle or document picker
                guard let audioURL = Bundle.main.url(forResource: "sample", withExtension: "mp3") else {
                    errorMessage = "Sample audio file not found. Please add 'sample.mp3' to the app bundle."
                    showError = true
                    return
                }
                
                let config = AudioConfiguration(
                    crossfadeDuration: 10.0,
                    fadeInDuration: 3.0,
                    fadeOutDuration: 6.0,
                    volume: volume,
                    repeatCount: nil,
                    enableLooping: true
                )
                
                try await audioService.startPlaying(url: audioURL, configuration: config)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func togglePlayPause() {
        Task {
            do {
                if playerState == .playing {
                    try await audioService.pause()
                } else if playerState == .paused {
                    try await audioService.resume()
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func stopPlayback() {
        Task {
            await audioService.stop()
        }
    }
    
    private func skipForward() {
        Task {
            do {
                try await audioService.skipForward(by: 15.0)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func skipBackward() {
        Task {
            do {
                try await audioService.skipBackward(by: 15.0)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func observePlayerState() async {
        // Poll player state periodically
        while true {
            playerState = await audioService.state
            playbackPosition = await audioService.playbackPosition
            currentTrack = await audioService.currentTrack
            
            try? await Task.sleep(nanoseconds: 250_000_000) // Update 4 times per second
        }
    }
}

#Preview {
    ContentView()
        .environment(\.audioService, AudioPlayerService())
}

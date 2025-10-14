import SwiftUI

/// Player controls component - play/pause/skip/next/previous
struct PlayerControls: View {
    let viewModel: PlayerViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            // Primary Controls
            HStack(spacing: 40) {
                // Skip Backward (15s)
                Button {
                    Task {
                        try? await viewModel.skipBackward()
                    }
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title)
                        .foregroundStyle(viewModel.canSkip ? .primary : .secondary)
                }
                .disabled(!viewModel.canSkip)
                
                // Previous Track
                Button {
                    Task {
                        try? await viewModel.previousTrack()
                    }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                        .foregroundStyle(viewModel.canSkip ? .primary : .secondary)
                }
                .disabled(!viewModel.canSkip)
                
                // Play/Pause
                Button {
                    Task {
                        do {
                            if viewModel.isPlaying {
                                // ✅ FIX: pause() throws
                                try await viewModel.pause()
                            } else if viewModel.isPaused {
                                // ✅ FIX: resume() throws
                                try await viewModel.resume()
                            } else {
                                // Load default playlist if nothing loaded
                                if viewModel.position == nil {
                                    try await viewModel.loadPlaylist(["voiceover1", "voiceover2"])
                                }
                                try await viewModel.play()
                            }
                        } catch {
                            print("Playback error: \(error)")
                        }
                    }
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.blue)
                }
                
                // Next Track
                Button {
                    Task {
                        try? await viewModel.nextTrack()
                    }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundStyle(viewModel.canSkip ? .primary : .secondary)
                }
                .disabled(!viewModel.canSkip)
                
                // Skip Forward (15s)
                Button {
                    Task {
                        try? await viewModel.skipForward()
                    }
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title)
                        .foregroundStyle(viewModel.canSkip ? .primary : .secondary)
                }
                .disabled(!viewModel.canSkip)
            }
            
            // Secondary Controls
            HStack(spacing: 12) {
                // Stop
                Button {
                    Task {
                        await viewModel.stop()
                    }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canStop)
                
                Spacer()
                
                // Volume Label
                HStack(spacing: 8) {
                    Image(systemName: volumeIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("\(Int(viewModel.volume * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            
            // Volume Slider
            Slider(
                value: Binding(
                    get: { Double(viewModel.volume) },
                    set: { newValue in
                        Task {
                            await viewModel.setVolume(Float(newValue))
                        }
                    }
                ),
                in: 0.0...1.0,
                step: 0.01
            )
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var volumeIcon: String {
        if viewModel.volume == 0 {
            return "speaker.slash.fill"
        } else if viewModel.volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if viewModel.volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
}

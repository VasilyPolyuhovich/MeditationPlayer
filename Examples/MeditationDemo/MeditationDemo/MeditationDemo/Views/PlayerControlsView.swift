import SwiftUI

/// Playback controls including play/stop, skip, track navigation, and volume
struct PlayerControlsView: View {
    let viewModel: AudioPlayerViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            // Track Navigation (Playlist)
            HStack(spacing: 32) {
                // Previous Track
                Button {
                    Task { await viewModel.previousTrack() }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                        .foregroundStyle(viewModel.canSkip ? .primary : .secondary)
                }
                .disabled(!viewModel.canSkip)
                
                Spacer()
                
                // Next Track
                Button {
                    Task { await viewModel.nextTrack() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundStyle(viewModel.canSkip ? .primary : .secondary)
                }
                .disabled(!viewModel.canSkip)
            }
            
            // Primary Controls
            HStack(spacing: 32) {
                // Skip Backward (15s)
                Button {
                    Task { await viewModel.skipBackward() }
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title)
                        .foregroundStyle(viewModel.canSkip ? .primary : .secondary)
                }
                .disabled(!viewModel.canSkip)
                
                // Play/Pause with position preservation
                Button {
                    Task {
                        if viewModel.isPlaying {
                            // Playing → Pause (preserves position)
                            await viewModel.pause()
                        } else if viewModel.isPaused {
                            // Paused → Resume from saved position
                            await viewModel.resume()
                        } else {
                            // Finished/Other → Fresh start
                            await viewModel.play()
                        }
                    }
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.blue)
                }
                
                // Skip Forward (15s)
                Button {
                    Task { await viewModel.skipForward() }
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title)
                        .foregroundStyle(viewModel.canSkip ? .primary : .secondary)
                }
                .disabled(!viewModel.canSkip)
            }
            
            // Secondary Controls
            HStack(spacing: 12) {
                // Stop (full reset to beginning)
                Button {
                    Task { await viewModel.stop() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canStop)
                
                Spacer()
                
                // Reset (clear everything)
                Button("Reset All") {
                    Task { await viewModel.reset() }
                }
                .buttonStyle(.borderedProminent)
            }
            
            // Volume Control (0-100)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                    
                    Text("Volume: \(viewModel.volume)%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "speaker.wave.1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Slider(value: Binding(
                        get: { Double(viewModel.volume) },
                        set: { newValue in
                            let intValue = Int(newValue)
                            Task { await viewModel.setVolume(intValue) }
                        }
                    ), in: 0...100, step: 1)
                    
                    Image(systemName: "speaker.wave.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 2)
    }
}

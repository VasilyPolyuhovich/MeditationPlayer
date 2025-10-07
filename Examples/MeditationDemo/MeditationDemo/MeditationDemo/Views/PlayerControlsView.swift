import SwiftUI
import AudioServiceCore
import AudioServiceKit

/// Playback controls including play/stop, skip, and track navigation
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
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 2)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var viewModel = AudioPlayerViewModel(
        audioService: AudioPlayerService(
            configuration: AudioConfiguration()
        )
    )
    
    PlayerControlsView(viewModel: viewModel)
        .padding()
}

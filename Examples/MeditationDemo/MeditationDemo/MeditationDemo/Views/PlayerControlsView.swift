import SwiftUI
import AudioServiceCore

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
            
            // Repeat Mode Control (Feature #1)
            VStack(alignment: .leading, spacing: 12) {
                Text("Repeat Mode")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                Picker("Repeat Mode", selection: Binding(
                    get: { viewModel.repeatMode },
                    set: { newMode in
                        Task { await viewModel.updateRepeatMode(newMode) }
                    }
                )) {
                    Text("Off").tag(RepeatMode.off)
                    Text("Single Track").tag(RepeatMode.singleTrack)
                    Text("Playlist").tag(RepeatMode.playlist)
                }
                .pickerStyle(.segmented)
                
                // Single Track Fade Durations (conditional)
                if viewModel.repeatMode == .singleTrack {
                    VStack(spacing: 16) {
                        // Fade In Slider
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Fade In: ")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1fs", viewModel.singleTrackFadeIn))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            }
                            
                            Slider(value: Binding(
                                get: { viewModel.singleTrackFadeIn },
                                set: { newValue in
                                    viewModel.singleTrackFadeIn = newValue
                                    // Debounced update
                                    Task {
                                        try? await Task.sleep(for: .milliseconds(500))
                                        await viewModel.updateSingleTrackFadeDurations()
                                    }
                                }
                            ), in: 0.5...10.0, step: 0.5)
                        }
                        
                        // Fade Out Slider
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Fade Out: ")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1fs", viewModel.singleTrackFadeOut))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            }
                            
                            Slider(value: Binding(
                                get: { viewModel.singleTrackFadeOut },
                                set: { newValue in
                                    viewModel.singleTrackFadeOut = newValue
                                    // Debounced update
                                    Task {
                                        try? await Task.sleep(for: .milliseconds(500))
                                        await viewModel.updateSingleTrackFadeDurations()
                                    }
                                }
                            ), in: 0.5...10.0, step: 0.5)
                        }
                        
                        // Repeat Count Display
                        if viewModel.currentRepeatCount > 0 {
                            HStack {
                                Image(systemName: "repeat")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                                Text("Repeat count: \(viewModel.currentRepeatCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.top, 8)
                    .transition(.opacity)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
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

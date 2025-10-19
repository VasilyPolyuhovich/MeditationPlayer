import SwiftUI

/// Sound Effects demonstration view
struct SoundEffectsView: View {
    @Bindable var viewModel: PlayerViewModel

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Sound Effects")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Quick sound triggers with auto-preload")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Current Effect Status
                if viewModel.isSoundEffectPlaying, let effect = viewModel.currentEffect {
                    HStack {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)

                        Text("Playing: \(effect.track.url.deletingPathExtension().lastPathComponent)")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.top)

            Divider()
            
            // Volume Control
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.blue)
                    
                    Text("Effect Volume")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(Int(viewModel.soundEffectVolume * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                
                Slider(
                    value: $viewModel.soundEffectVolume,
                    in: 0.0...1.0,
                    step: 0.05
                ) {
                    Text("Volume")
                } minimumValueLabel: {
                    Image(systemName: "speaker.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .onChange(of: viewModel.soundEffectVolume) { _, newValue in
                    Task {
                        await viewModel.setSoundEffectVolume(newValue)
                    }
                }
                
                Text("Master volume - applies to all effects instantly")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            // Sound Effect Buttons
            VStack(spacing: 16) {
                SoundEffectButton(
                    icon: "bell.fill",
                    title: "Bell",
                    subtitle: "Meditation timer",
                    isPlaying: viewModel.isSoundEffectPlaying && viewModel.currentEffect?.track.url.lastPathComponent.contains("bell") == true
                ) {
                    Task {
                        try? await viewModel.playSoundEffect(named: "bell")
                    }
                }

                SoundEffectButton(
                    icon: "circle.hexagonpath.fill",
                    title: "Gong",
                    subtitle: "Session start/end",
                    isPlaying: viewModel.isSoundEffectPlaying && viewModel.currentEffect?.track.url.lastPathComponent.contains("gong") == true
                ) {
                    Task {
                        try? await viewModel.playSoundEffect(named: "gong")
                    }
                }

                SoundEffectButton(
                    icon: "timer",
                    title: "Count Down",
                    subtitle: "3-2-1 countdown",
                    isPlaying: viewModel.isSoundEffectPlaying && viewModel.currentEffect?.track.url.lastPathComponent.contains("count_down") == true
                ) {
                    Task {
                        try? await viewModel.playSoundEffect(named: "count_down")
                    }
                }
            }
            .padding(.horizontal)

            // Stop Button
            if viewModel.isSoundEffectPlaying {
                Button {
                    Task {
                        await viewModel.stopSoundEffect()
                    }
                } label: {
                    Label("Stop Sound Effect", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.horizontal)
            }

            Spacer()

            // Info Section
            VStack(spacing: 12) {
                InfoCard(
                    title: "LRU Cache",
                    description: "Sound effects are auto-preloaded with LRU cache (10 effects max)",
                    icon: "memorychip.fill"
                )

                InfoCard(
                    title: "Instant Playback",
                    description: "Preloaded buffers in RAM for zero-latency triggers",
                    icon: "bolt.fill"
                )

                InfoCard(
                    title: "Auto-Cleanup",
                    description: "Oldest effects auto-evicted when cache limit reached",
                    icon: "arrow.3.trianglepath"
                )
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Sound Effect Button

struct SoundEffectButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isPlaying ? .green.opacity(0.2) : .blue.opacity(0.1))
                        .frame(width: 60, height: 60)

                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(isPlaying ? .green : .blue)
                }

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Playing Indicator
                if isPlaying {
                    HStack(spacing: 3) {
                        ForEach(0..<3) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.green)
                                .frame(width: 3, height: 12)
                                .animation(
                                    .easeInOut(duration: 0.5)
                                    .repeatForever()
                                    .delay(Double(index) * 0.15),
                                    value: isPlaying
                                )
                        }
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Info Card

struct InfoCard: View {
    let title: String
    let description: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

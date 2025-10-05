import SwiftUI
import AudioServiceCore

/// Status display showing player state, position, and progress with crossfade zone
struct StatusView: View {
    let viewModel: AudioPlayerViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            // State Badge
            HStack {
                Circle()
                    .fill(viewModel.state.color)
                    .frame(width: 12, height: 12)
                
                Text(viewModel.state.displayName)
                    .font(.headline)
                    .foregroundStyle(viewModel.state.color)
            }
            
            // Track Info
            if !viewModel.currentTrack.isEmpty {
                if viewModel.isCrossfading {
                    // Show crossfade indicator instead of track name
                    HStack(spacing: 8) {
                        Text(viewModel.currentTrack.uppercased())
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                        
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.blue)
                            .symbolEffect(.pulse)
                        
                        Text("NEXT TRACK")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                    }
                } else {
                    Text(viewModel.currentTrack.uppercased())
                        .font(.title2)
                        .fontWeight(.bold)
                }
            }
            
            // Position
            Text(viewModel.formattedPosition)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            
            // Progress Bar with Crossfade Zone
            if let _ = viewModel.position {
                VStack(spacing: 8) {
                    // Progress Bar with Zone Overlay
                    ZStack(alignment: .leading) {
                        // Background track
                        GeometryReader { geometry in
                            // Base progress bar
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 8)
                            
                            // Crossfade Zone (green/yellow overlay at end)
                            if viewModel.crossfadeZoneStart < 1.0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            colors: [.green.opacity(0.3), .yellow.opacity(0.4)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(
                                        width: geometry.size.width * (1.0 - viewModel.crossfadeZoneStart),
                                        height: 8
                                    )
                                    .offset(x: geometry.size.width * viewModel.crossfadeZoneStart)
                            }
                            
                            // Current progress (blue)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    viewModel.isInCrossfadeZone
                                        ? Color.orange
                                        : Color.blue
                                )
                                .frame(
                                    width: geometry.size.width * viewModel.progressValue,
                                    height: 8
                                )
                        }
                        .frame(height: 8)
                    }
                    
                    // Crossfade Indicator
                    if let phase = viewModel.crossfadePhase {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.circle.fill")
                                .foregroundStyle(.orange)
                                .symbolEffect(.pulse)
                            
                            Text(phase)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else if viewModel.isInCrossfadeZone && viewModel.isPlaying {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.circle.fill")
                                .foregroundStyle(.orange)
                                .symbolEffect(.pulse)
                            
                            Text("Entering crossfade zone...")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    // Zone Legend
                    HStack(spacing: 16) {
                        Label {
                            Text("Progress")
                                .font(.caption2)
                        } icon: {
                            Circle()
                                .fill(.blue)
                                .frame(width: 8, height: 8)
                        }
                        
                        Label {
                            Text("Crossfade Zone")
                                .font(.caption2)
                        } icon: {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                        }
                        
                        if viewModel.isInCrossfadeZone {
                            Label {
                                Text("Active")
                                    .font(.caption2)
                            } icon: {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 2)
    }
}

// MARK: - PlayerState Extensions

extension PlayerState {
    var displayName: String {
        switch self {
        case .preparing: return "Preparing"
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .fadingOut: return "Fading Out"
        case .finished: return "Finished"
        case .failed: return "Failed"
        }
    }
    
    var color: Color {
        switch self {
        case .playing: return .green
        case .paused: return .orange
        case .fadingOut, .preparing: return .blue
        case .failed: return .red
        case .finished: return .gray
        }
    }
}

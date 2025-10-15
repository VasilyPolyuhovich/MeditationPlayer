import SwiftUI
import AudioServiceCore

/// Live crossfade visualizer - shows real-time crossfade progress
struct CrossfadeVisualizer: View {
    let progress: CrossfadeProgress?
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with pulsing icon
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse)
                
                Text("CROSSFADE ACTIVE")
                    .font(.headline)
                    .foregroundStyle(.orange)
                
                Spacer()
            }
            
            if let progress {
                // ✅ FIX: Use actual Phase cases
                // Phase Indicator
                HStack(spacing: 4) {
                    PhaseIndicatorDot(
                        isActive: {
                            if case .preparing = progress.phase {
                                return true
                            }
                            return false
                        }(),
                        color: .blue,
                        label: "Preparing"
                    )
                    
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    PhaseIndicatorDot(
                        isActive: {
                            if case .fading = progress.phase {
                                return true
                            }
                            return false
                        }(),
                        color: .orange,
                        label: "Fading"
                    )
                    
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    PhaseIndicatorDot(
                        isActive: {
                            if case .switching = progress.phase {
                                return true
                            }
                            return false
                        }(),
                        color: .green,
                        label: "Switching"
                    )
                    
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    PhaseIndicatorDot(
                        isActive: {
                            if case .cleanup = progress.phase {
                                return true
                            }
                            return false
                        }(),
                        color: .purple,
                        label: "Cleanup"
                    )
                }
                
                // ✅ FIX: Show fading progress if in .fading phase
                if case .fading(let fadeProgress) = progress.phase {
                    // Visual Representation of fade
                    HStack(spacing: 12) {
                        // Outgoing Track Volume (decreasing)
                        VStack(spacing: 4) {
                            Text("Outgoing")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            VolumeBar(
                                value: Float(1.0 - fadeProgress),
                                color: .red
                            )
                            
                            Text("\(Int((1.0 - fadeProgress) * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        
                        Image(systemName: "arrow.left.arrow.right")
                            .foregroundStyle(.orange)
                        
                        // Incoming Track Volume (increasing)
                        VStack(spacing: 4) {
                            Text("Incoming")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            VolumeBar(
                                value: Float(fadeProgress),
                                color: .green
                            )
                            
                            Text("\(Int(fadeProgress * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                
                // Progress Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.secondary.opacity(0.2))
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.orange)
                            .frame(
                                width: geometry.size.width * progress.progress,
                                height: 6
                            )
                    }
                }
                .frame(height: 6)
                
                // Timing Info
                HStack {
                    Text("\(formatTime(progress.elapsed))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    
                    Spacer()
                    
                    Text("\(formatTime(progress.duration))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.orange.opacity(0.3), lineWidth: 2)
                )
        )
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        String(format: "%.1fs", time)
    }
}

// MARK: - Phase Indicator Dot

struct PhaseIndicatorDot: View {
    let isActive: Bool
    let color: Color
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(isActive ? color : .secondary.opacity(0.3))
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(isActive ? color : .clear, lineWidth: 2)
                        .scaleEffect(isActive ? 1.5 : 1.0)
                        .opacity(isActive ? 0.3 : 0)
                )
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(isActive ? color : .secondary)
                .fontWeight(isActive ? .semibold : .regular)
        }
    }
}

// MARK: - Volume Bar

struct VolumeBar: View {
    let value: Float
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(.secondary.opacity(0.2))
                
                // Fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.6), color],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: geometry.size.height * CGFloat(value))
            }
        }
        .frame(width: 40, height: 80)
    }
}

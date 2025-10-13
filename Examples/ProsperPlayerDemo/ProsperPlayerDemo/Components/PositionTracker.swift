import SwiftUI

/// Position tracker with visual progress bar
struct PositionTracker: View {
    let viewModel: PlayerViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "waveform")
                    .foregroundStyle(.blue)
                Text("Playback Position")
                    .font(.headline)
                Spacer()
            }
            
            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.secondary.opacity(0.2))
                        .frame(height: 8)
                    
                    // Progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geometry.size.width * viewModel.progressValue,
                            height: 8
                        )
                        .animation(.linear(duration: 0.1), value: viewModel.progressValue)
                }
            }
            .frame(height: 8)
            
            // Time Labels
            if let position = viewModel.position {
                HStack {
                    Text(formatTime(position.current))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    
                    Spacer()
                    
                    Text("-\(formatTime(position.duration - position.current))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            
            // Progress Percentage
            Text("\(Int(viewModel.progressValue * 100))%")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

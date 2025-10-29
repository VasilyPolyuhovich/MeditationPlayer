//
//  ProgressIndicatorView.swift
//  ProsperPlayerDemo
//
//  Minimal progress indicator showing elapsed/remaining time
//  Updates via AudioPlayerService.positionUpdates AsyncStream
//

import SwiftUI
import AudioServiceKit

/// Minimal progress indicator for playback
/// Shows: elapsed time / total duration + progress bar
struct ProgressIndicatorView: View {
    let service: AudioPlayerService?
    
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    
    var body: some View {
        VStack(spacing: 8) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                        .cornerRadius(2)
                    
                    if duration > 0 {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(
                                width: geometry.size.width * CGFloat(currentTime / duration),
                                height: 4
                            )
                            .cornerRadius(2)
                    }
                }
            }
            .frame(height: 4)
            
            // Time labels
            HStack {
                Text(formatTime(currentTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                
                Spacer()
                
                if duration > 0 {
                    Text("-\(formatTime(duration - currentTime))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .task {
            await startPositionUpdates()
        }
    }
    
    private func startPositionUpdates() async {
        guard let service = service else { return }
        
        for await position in await service.positionUpdates {
            await MainActor.run {
                currentTime = position.currentTime
                duration = position.duration
            }
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

/// Card wrapper for progress indicator
struct ProgressCard: View {
    let service: AudioPlayerService?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Progress", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            ProgressIndicatorView(service: service)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 2)
        )
    }
}

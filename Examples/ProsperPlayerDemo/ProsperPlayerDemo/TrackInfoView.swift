//
//  TrackInfoView.swift
//  ProsperPlayerDemo
//
//  Track information display component
//

import SwiftUI

struct TrackInfoView: View {
    let stageName: String
    let trackName: String
    let isPlaying: Bool

    var body: some View {
        VStack(spacing: 12) {
            // Waveform animation
            HStack(spacing: 4) {
                ForEach(0..<5) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isPlaying ? Color.blue : Color.gray)
                        .frame(width: 4, height: waveHeight(for: index))
                        .animation(
                            isPlaying ?
                                .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.1) :
                                .default,
                            value: isPlaying
                        )
                }
            }
            .frame(height: 40)

            // Stage name
            Text(stageName)
                .font(.headline)
                .foregroundStyle(.primary)

            // Track name
            Text(trackName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
    }

    private func waveHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 10
        let maxHeight: CGFloat = 40

        if !isPlaying {
            return baseHeight
        }

        // Create wave pattern
        let heights: [CGFloat] = [20, 35, 40, 30, 25]
        return heights[index % heights.count]
    }
}

#Preview {
    VStack(spacing: 20) {
        TrackInfoView(
            stageName: "Stage 1: Introduction",
            trackName: "stage1_intro_music.mp3",
            isPlaying: false
        )

        TrackInfoView(
            stageName: "Stage 2: Practice",
            trackName: "stage2_practice_music.mp3",
            isPlaying: true
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

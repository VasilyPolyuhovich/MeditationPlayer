//
//  OverlayControlsView.swift
//  ProsperPlayerDemo
//
//  Overlay player controls component
//

import SwiftUI

struct OverlayControlsView: View {
    let isOverlayPlaying: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "waveform")
                    .foregroundStyle(.secondary)

                Text("Voice Overlay")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onToggle) {
                    Image(systemName: isOverlayPlaying ? "speaker.wave.3.fill" : "speaker.fill")
                        .font(.title3)
                        .foregroundStyle(isOverlayPlaying ? .green : .gray)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(isOverlayPlaying ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                        )
                }
            }

            if isOverlayPlaying {
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .scaleEffect(scale(for: index))
                            .animation(
                                .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                                value: isOverlayPlaying
                            )
                    }
                    Text("Playing...")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func scale(for index: Int) -> CGFloat {
        isOverlayPlaying ? [1.0, 1.5, 1.0][index] : 1.0
    }
}

#Preview {
    VStack(spacing: 20) {
        OverlayControlsView(
            isOverlayPlaying: false,
            onToggle: {}
        )

        OverlayControlsView(
            isOverlayPlaying: true,
            onToggle: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

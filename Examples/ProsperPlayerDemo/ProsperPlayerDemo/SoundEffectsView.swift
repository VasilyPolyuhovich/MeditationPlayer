//
//  SoundEffectsView.swift
//  ProsperPlayerDemo
//
//  Sound effects demonstration component
//

import SwiftUI

struct SoundEffectsView: View {
    let onPlayGong: () -> Void
    let onPlayBeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sound Effects", systemImage: "speaker.wave.2.fill")
                .font(.headline)
                .foregroundStyle(.purple)

            Text("Play effects independently during meditation")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                // Gong button
                Button(action: onPlayGong) {
                    VStack(spacing: 4) {
                        Image(systemName: "bell.fill")
                            .font(.title2)
                        Text("Gong")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.purple.opacity(0.1))
                    )
                    .foregroundStyle(.purple)
                }

                // Beep button
                Button(action: onPlayBeep) {
                    VStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.title2)
                        Text("Beep")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.purple.opacity(0.1))
                    )
                    .foregroundStyle(.purple)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4)
        )
    }
}

#Preview {
    SoundEffectsView(
        onPlayGong: {},
        onPlayBeep: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

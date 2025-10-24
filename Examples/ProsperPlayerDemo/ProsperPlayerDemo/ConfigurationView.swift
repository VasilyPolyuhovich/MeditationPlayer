//
//  ConfigurationView.swift
//  ProsperPlayerDemo
//
//  Configuration controls for demonstrating different settings
//

import SwiftUI

struct ConfigurationView: View {
    @Binding var crossfadeDuration: Double
    @Binding var volume: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Configuration")
            } icon: {
                Image(systemName: "slider.horizontal.3")
            }
                .font(.headline)
                .foregroundStyle(.orange)

            // Crossfade Duration
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Crossfade Duration")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(crossfadeDuration))s")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: $crossfadeDuration, in: 1...15, step: 1)
                    .tint(.orange)

                Text("Transition smoothness between tracks")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Volume
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Volume")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(volume * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: $volume, in: 0...1, step: 0.1)
                    .tint(.orange)

                Text("Main player volume level")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
    ConfigurationView(
        crossfadeDuration: .constant(5.0),
        volume: .constant(0.8)
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

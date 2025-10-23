//
//  MeditationSessionView.swift
//  ProsperPlayerDemo
//
//  Simple placeholder demo for AudioServiceKit
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

/// **Simple Demo View**
///
/// TODO: Add real implementation after audio files are added
public struct MeditationSessionView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)

                    Text("ProsperPlayer Demo")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("AudioServiceKit Integration")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()

                Spacer()

                // Status
                VStack(alignment: .leading, spacing: 12) {
                    StatusRow(title: "SDK", value: "AudioServiceKit", color: .green)
                    StatusRow(title: "Integration Tests", value: "9 critical scenarios", color: .blue)
                    StatusRow(title: "Status", value: "Ready for testing", color: .orange)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
                .padding()

                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Label("Next Steps", systemImage: "list.bullet.clipboard")
                        .font(.headline)

                    Text("""
                    1. Add test audio files to TestResources/
                    2. Run integration tests
                    3. Implement 3-stage meditation UI
                    4. Manual testing (30-min session)
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
                .padding()

                Spacer()

                Text("See Tests/AudioServiceKitIntegrationTests/README.md")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .navigationTitle("Demo")
        }
    }
}

struct StatusRow: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            Spacer()

            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    MeditationSessionView()
}

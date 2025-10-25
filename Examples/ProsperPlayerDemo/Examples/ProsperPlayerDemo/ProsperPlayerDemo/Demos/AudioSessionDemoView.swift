//
//  AudioSessionDemoView.swift
//  ProsperPlayerDemo
//
//  Audio session compatibility demo - test with phone calls and other audio sources
//  Shows how SDK handles AVAudioSession interruptions and route changes
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct AudioSessionDemoView: View {

    // MARK: - State

    @State private var model: DemoPlayerModel?
    @State private var track: Track?
    @State private var sessionInfo: String = "Not playing"

    // MARK: - Body

    var body: some View {
        if let model = model {
            DemoContainerView(
                title: "Audio Session Test",
                icon: "ear.trianglebadge.exclamationmark",
                description: "Test with phone calls and other audio sources",
                model: model
            ) {
                sessionInfoSection
                controlsSection
                instructionsSection
            }
            .task {
                await loadResources()
            }
        } else {
            ProgressView("Initializing...")
                .task {
                    model = try? await DemoPlayerModel()
                }
        }
    }

    // MARK: - Sections

    private var sessionInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Session Status", systemImage: "waveform.circle.fill")
                .font(.headline)
                .foregroundStyle(.blue)

            Text(sessionInfo)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4)
        )
    }

    private var controlsSection: some View {
        ControlsCard(title: "Controls", icon: "slider.horizontal.3") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    PlayButton(
                        disabled: model?.state == .playing || track == nil
                    ) {
                        await play()
                    }

                    PauseButton(
                        disabled: model?.state != .playing
                    ) {
                        try? await model?.pause()
                    }
                }

                StopButton(
                    disabled: model?.state == .finished
                ) {
                    await model?.stop()
                }
            }
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Test Scenarios", systemImage: "checklist")
                .font(.headline)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 6) {
                Text("• Start playback")
                Text("• Receive a phone call (use another device)")
                Text("• Check if playback resumes after call")
                Text("• Try switching to speaker/headphones")
                Text("• Open another audio app")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.blue.opacity(0.1))
        )
    }

    // MARK: - Business Logic

    private func loadResources() async {
        guard let url = Bundle.main.url(forResource: "stage1_intro_music", withExtension: "mp3"),
              let loadedTrack = Track(url: url) else {
            model?.error = "Audio file not found"
            return
        }

        track = loadedTrack
        sessionInfo = "Ready for testing"
    }

    private func play() async {
        guard let track = track else { return }
        sessionInfo = "Playing - try interruptions"
        try? await model?.loadAndPlay([track], fadeDuration: 0.0)
    }
}

#Preview {
    AudioSessionDemoView()
}

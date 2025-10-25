//
//  FadeStartStopView.swift
//  ProsperPlayerDemo
//
//  Fade in/out demo - smooth fade in/out on start/stop
//  Critical functionality: startPlaying(fadeDuration:) and finish(fadeDuration:)
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct FadeStartStopView: View {

    // MARK: - State

    @State private var model: DemoPlayerModel?
    @State private var track: Track?
    @State private var fadeInDuration: Double = 3.0
    @State private var fadeOutDuration: Double = 3.0

    // MARK: - Body

    var body: some View {
        if let model = model {
            DemoContainerView(
                title: "Fade In/Out",
                icon: "waveform.path",
                description: "Smooth fade in/out on start/stop",
                model: model
            ) {
                fadeConfigSection
                controlsSection
                infoSection
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

    private var fadeConfigSection: some View {
        VStack(spacing: 16) {
            Label("Fade Configuration", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.blue)

            VStack(spacing: 12) {
                HStack {
                    Text("Fade In: \(Int(fadeInDuration))s")
                        .frame(width: 100, alignment: .leading)
                    Slider(value: $fadeInDuration, in: 0...10)
                }

                HStack {
                    Text("Fade Out: \(Int(fadeOutDuration))s")
                        .frame(width: 100, alignment: .leading)
                    Slider(value: $fadeOutDuration, in: 0...10)
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

    private var controlsSection: some View {
        ControlsCard(title: "Controls", icon: "play.circle") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    PlayButton(
                        disabled: model?.state == .playing || track == nil
                    ) {
                        await play()
                    }

                    StopButton(
                        disabled: model?.state == .finished
                    ) {
                        await stop()
                    }
                }
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Expected Behavior", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(.blue)

            Text("• Play: Volume gradually increases over fade-in duration")
            Text("• Stop: Volume gradually decreases to silence")
            Text("• No abrupt audio cuts")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
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
    }

    private func play() async {
        guard let track = track else { return }
        try? await model?.loadAndPlay([track], fadeDuration: fadeInDuration)
    }

    private func stop() async {
        await model?.stop(fadeDuration: fadeOutDuration)
    }
}

#Preview {
    FadeStartStopView()
}

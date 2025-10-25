//
//  SimplePlaybackView.swift
//  ProsperPlayerDemo
//
//  Basic playback demo - load and play single track
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct SimplePlaybackView: View {

    // MARK: - State

    @State private var model: DemoPlayerModel?
    @State private var track: Track?

    // MARK: - Body

    var body: some View {
        if let model = model {
            DemoContainerView(
                title: "Simple Playback",
                icon: "play.circle.fill",
                description: "Load and play a single track",
                model: model
            ) {
                controlsSection
            }
            .task {
                await loadResources()
            }
        } else {
            ProgressView("Initializing...")
                .task {
                    await initializeModel()
                }
        }
    }

    // MARK: - Controls Section

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

    // MARK: - Business Logic

    private func initializeModel() async {
        do {
            let config = PlayerConfiguration(
                crossfadeDuration: 0.0,
                repeatCount: nil,
                volume: 0.8
            )
            model = try await DemoPlayerModel(config: config)
        } catch {
            // Model will show error in its error property
            print("Failed to initialize model: \(error)")
        }
    }

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
        try? await model?.loadAndPlay([track], fadeDuration: 0.0)
    }
}

#Preview {
    SimplePlaybackView()
}

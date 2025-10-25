//
//  CrossfadeBasicView.swift
//  ProsperPlayerDemo
//
//  Basic crossfade demo - smooth transitions between tracks
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct CrossfadeBasicView: View {

    // MARK: - State

    @State private var model: DemoPlayerModel?
    @State private var tracks: [Track] = []

    // MARK: - Body

    var body: some View {
        if let model = model {
            DemoContainerView(
                title: "Basic Crossfade",
                icon: "waveform.path.ecg",
                description: "Smooth transitions between tracks with 5s crossfade",
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

    // MARK: - Sections

    private var controlsSection: some View {
        ControlsCard(title: "Controls", icon: "slider.horizontal.3") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    PlayButton(
                        disabled: model?.state == .playing || tracks.isEmpty
                    ) {
                        await play()
                    }

                    StopButton(
                        disabled: model?.state == .finished
                    ) {
                        await model?.stop()
                    }
                }

                Button(action: { Task { try? await model?.audioService.skipToNext() } }) {
                    Label("Skip to Next", systemImage: "forward.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(model?.state != .playing)

                Text("Crossfade duration: 5 seconds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Business Logic

    private func initializeModel() async {
        let config = PlayerConfiguration(
            crossfadeDuration: 5.0,
            repeatCount: nil,
            volume: 0.8
        )
        model = try? await DemoPlayerModel(config: config)
    }

    private func loadResources() async {
        let trackFiles = ["stage1_intro_music", "stage2_practice_music", "stage3_closing_music"]
        let loadedTracks = trackFiles.compactMap { filename -> Track? in
            guard let url = Bundle.main.url(forResource: filename, withExtension: "mp3") else { return nil }
            return Track(url: url)
        }

        guard !loadedTracks.isEmpty else {
            model?.error = "Audio files not found"
            return
        }

        tracks = loadedTracks
    }

    private func play() async {
        guard !tracks.isEmpty else { return }
        try? await model?.loadAndPlay(tracks, fadeDuration: 0.0)
    }
}

#Preview {
    CrossfadeBasicView()
}

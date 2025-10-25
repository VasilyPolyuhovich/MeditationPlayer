//
//  LoopWithCrossfadeView.swift
//  ProsperPlayerDemo
//
//  Seamless looping with crossfade demo
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct LoopWithCrossfadeView: View {

    // MARK: - State

    @State private var model: DemoPlayerModel?
    @State private var tracks: [Track] = []

    // MARK: - Body

    var body: some View {
        if let model = model {
            DemoContainerView(
                title: "Loop with Crossfade",
                icon: "repeat.circle.fill",
                description: "Seamless looping playlist with crossfade transitions",
                model: model
            ) {
                controlsSection
                infoSection
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
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Loop Configuration", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(.blue)

            Text("• Playlist loops 2 times")
            Text("• Crossfade: 5 seconds")
            Text("• Smooth transitions between tracks and loops")

            Text("Expected: Seamless audio loop without gaps")
                .font(.caption)
                .foregroundStyle(.blue)
                .padding(.top, 4)
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

    private func initializeModel() async {
        let config = PlayerConfiguration(
            crossfadeDuration: 5.0,
            repeatCount: 2,
            volume: 0.8
        )
        model = try? await DemoPlayerModel(config: config)
    }

    private func loadResources() async {
        let trackFiles = ["stage1_intro_music", "stage2_practice_music"]
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
    LoopWithCrossfadeView()
}

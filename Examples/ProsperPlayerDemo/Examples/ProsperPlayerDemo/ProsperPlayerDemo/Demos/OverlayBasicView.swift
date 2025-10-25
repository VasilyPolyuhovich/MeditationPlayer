//
//  OverlayBasicView.swift
//  ProsperPlayerDemo
//
//  Basic overlay demo - play background music + voice overlay simultaneously
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct OverlayBasicView: View {

    // MARK: - State

    @State private var model: DemoPlayerModel?
    @State private var mainTrack: Track?
    @State private var overlayTrack: Track?
    @State private var overlayPlaying: Bool = false

    // MARK: - Body

    var body: some View {
        if let model = model {
            DemoContainerView(
                title: "Basic Overlay",
                icon: "speaker.wave.2.circle.fill",
                description: "Play background music with voice overlay",
                model: model
            ) {
                controlsSection
                overlayControlsSection
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

    private var controlsSection: some View {
        ControlsCard(title: "Main Track", icon: "music.note") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    PlayButton(
                        disabled: model?.state == .playing || mainTrack == nil
                    ) {
                        await playMain()
                    }

                    StopButton(
                        disabled: model?.state == .finished
                    ) {
                        await model?.stop()
                        overlayPlaying = false
                    }
                }
            }
        }
    }

    private var overlayControlsSection: some View {
        ControlsCard(title: "Overlay Track", icon: "waveform.circle") {
            VStack(spacing: 12) {
                Button(action: { Task { await toggleOverlay() } }) {
                    Label(overlayPlaying ? "Stop Overlay" : "Play Overlay",
                          systemImage: overlayPlaying ? "stop.circle" : "play.circle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(overlayPlaying ? Color.red.opacity(0.8) : Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(model?.state != .playing)

                Text("Overlay plays independently from main track")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Business Logic

    private func loadResources() async {
        guard let mainUrl = Bundle.main.url(forResource: "stage1_intro_music", withExtension: "mp3"),
              let overlayUrl = Bundle.main.url(forResource: "breathing_exercise", withExtension: "mp3"),
              let main = Track(url: mainUrl),
              let overlay = Track(url: overlayUrl) else {
            model?.error = "Audio files not found"
            return
        }

        mainTrack = main
        overlayTrack = overlay
    }

    private func playMain() async {
        guard let mainTrack = mainTrack else { return }
        try? await model?.loadAndPlay([mainTrack], fadeDuration: 0.0)
    }

    private func toggleOverlay() async {
        guard let service = model?.audioService, let overlayTrack = overlayTrack else { return }

        if overlayPlaying {
            await service.stopOverlay()
            overlayPlaying = false
        } else {
            try? await service.playOverlay(overlayTrack)
            overlayPlaying = true
        }
    }
}

#Preview {
    OverlayBasicView()
}

//
//  OverlayWithDelaysView.swift
//  ProsperPlayerDemo
//
//  Overlay with loop delay demo - overlay loops with configurable delay between iterations
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct OverlayWithDelaysView: View {

    // MARK: - State

    @State private var model: DemoPlayerModel?
    @State private var mainTrack: Track?
    @State private var overlayTrack: Track?
    @State private var overlayPlaying: Bool = false
    @State private var loopDelay: Double = 3.0

    // MARK: - Body

    var body: some View {
        if let model = model {
            DemoContainerView(
                title: "Overlay with Delays",
                icon: "timer.circle.fill",
                description: "Overlay loops with configurable delay between iterations",
                model: model
            ) {
                configSection
                controlsSection
                overlayControlsSection
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

    private var configSection: some View {
        VStack(spacing: 12) {
            Label("Overlay Loop Configuration", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
                .foregroundStyle(.blue)

            HStack {
                Text("Loop Delay: \(Int(loopDelay))s")
                    .frame(width: 120, alignment: .leading)
                Slider(value: $loopDelay, in: 0...10)
            }
            .onChange(of: loopDelay) { _, newValue in
                Task {
                    guard let service = model?.audioService else { return }
                    await service.setOverlayLoopDelay(newValue)
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
                        await stopAll()
                    }
                }
            }
        }
    }

    private var overlayControlsSection: some View {
        ControlsCard(title: "Looping Overlay", icon: "repeat.circle") {
            VStack(spacing: 12) {
                Button(action: { Task { await toggleOverlay() } }) {
                    Label(overlayPlaying ? "Stop Overlay" : "Start Overlay Loop",
                          systemImage: overlayPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(overlayPlaying ? Color.red.opacity(0.8) : Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(model?.state != .playing)

                if overlayPlaying {
                    Text("Overlay is looping with \(Int(loopDelay))s delay")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Expected Behavior", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(.blue)

            Text("• Overlay plays, then waits for delay duration")
            Text("• After delay, overlay plays again")
            Text("• Continues looping with delay between each iteration")
            Text("• Main music plays continuously throughout")

            Text("Adjust delay slider to test different intervals")
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

    private func loadResources() async {
        guard let mainUrl = Bundle.main.url(forResource: "stage2_practice_music", withExtension: "mp3"),
              let overlayUrl = Bundle.main.url(forResource: "gong", withExtension: "mp3"),
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
            await service.setOverlayLoopMode(.infinite)
            await service.setOverlayLoopDelay(loopDelay)
            try? await service.playOverlay(overlayTrack)
            overlayPlaying = true
        }
    }

    private func stopAll() async {
        if overlayPlaying {
            await model?.audioService.stopOverlay()
            overlayPlaying = false
        }
        await model?.stop()
    }
}

#Preview {
    OverlayWithDelaysView()
}

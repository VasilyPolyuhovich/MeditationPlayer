//
//  PauseResumeView.swift
//  ProsperPlayerDemo
//
//  Pause/Resume demo - test pause and resume functionality
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct PauseResumeView: View {

    // MARK: - State

    @State private var model: DemoPlayerModel?
    @State private var track: Track?
    @State private var crossfadeDuration: Double = 5.0

    // MARK: - Body

    var body: some View {
        if let model = model {
            DemoContainerView(
                title: "Pause/Resume",
                icon: "pause.circle.fill",
                description: "Test pause and resume functionality",
                model: model
            ) {
                configSection
                controlsSection
                infoSection
            }
            .task {
                await loadResources()
            }
            .onChange(of: crossfadeDuration) { _, newValue in
                Task {
                    let config = PlayerConfiguration(
                        crossfadeDuration: newValue,
                        repeatCount: nil,
                        volume: 0.8
                    )
                    try? await model.updateConfiguration(config)
                }
            }
        } else {
            ProgressView("Initializing...")
                .task {
                    await initializeModel()
                }
        }
    }

    // MARK: - Sections

    private var configSection: some View {
        VStack(spacing: 12) {
            Label("Configuration", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.blue)

            HStack {
                Text("Crossfade: \(Int(crossfadeDuration))s")
                    .frame(width: 120, alignment: .leading)
                Slider(value: $crossfadeDuration, in: 0...15)
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

                    PauseButton(
                        disabled: model?.state != .playing
                    ) {
                        try? await model?.pause()
                    }
                }

                Button(action: { Task { try? await model?.resume() } }) {
                    Label("Resume", systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(model?.state != .paused)

                StopButton(
                    disabled: model?.state == .finished
                ) {
                    await model?.stop()
                }
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Test Scenario", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(.blue)

            Text("1. Start playback")
            Text("2. Pause (playback stops)")
            Text("3. Resume (playback continues from same position)")
            Text("4. Repeat multiple times")

            Text("Expected: Smooth pause/resume without gaps")
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
            crossfadeDuration: crossfadeDuration,
            repeatCount: nil,
            volume: 0.8
        )
        model = try? await DemoPlayerModel(config: config)
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
    PauseResumeView()
}

//
//  CrossfadeWithPauseView.swift
//  ProsperPlayerDemo
//
//  Crossfade + Pause demo - critical scenario: pause during crossfade
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct CrossfadeWithPauseView: View {

    // MARK: - State

    @State private var model: DemoPlayerModel?
    @State private var tracks: [Track] = []
    @State private var crossfadeDuration: Double = 5.0

    // MARK: - Body

    var body: some View {
        if let model = model {
            DemoContainerView(
                title: "Crossfade + Pause",
                icon: "waveform.path.ecg.rectangle.fill",
                description: "Critical test: Pause during crossfade transition",
                model: model
            ) {
                configSection
                controlsSection
                testScenarioSection
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
            Label("Crossfade Duration", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.blue)

            HStack {
                Text("\(Int(crossfadeDuration))s")
                    .frame(width: 40, alignment: .leading)
                Slider(value: $crossfadeDuration, in: 3...15)
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
                        disabled: model?.state == .playing || tracks.isEmpty
                    ) {
                        await play()
                    }

                    PauseButton(
                        disabled: model?.state != .playing
                    ) {
                        try? await model?.pause()
                    }
                }

                HStack(spacing: 12) {
                    Button(action: { Task { try? await model?.resume() } }) {
                        Label("Resume", systemImage: "play.circle")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(model?.state != .paused)

                    Button(action: { Task { try? await model?.audioService.skipToNext() } }) {
                        Label("Skip", systemImage: "forward.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(model?.state != .playing)
                }
            }
        }
    }

    private var testScenarioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Critical Test Scenario", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text("**This is the high-probability scenario!**")
                .fontWeight(.bold)

            Text("1. Start playing (Track 1)")
            Text("2. Wait ~10s, then skip to Track 2")
            Text("3. IMMEDIATELY pause during crossfade")
            Text("4. Resume - should continue crossfade smoothly")

            Text("Expected: Crossfade pauses mid-transition, resumes from same point")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 4)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.1))
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
    CrossfadeWithPauseView()
}

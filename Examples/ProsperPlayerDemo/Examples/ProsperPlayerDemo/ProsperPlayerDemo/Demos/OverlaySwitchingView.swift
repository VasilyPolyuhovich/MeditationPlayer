//
//  OverlaySwitchingView.swift
//  ProsperPlayerDemo
//
//  Overlay switching demo - switch between different voice overlays while main music plays
//  FIXED: Now uses voice files (breathing exercise, mantras) instead of music
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct OverlaySwitchingView: View {

    // MARK: - State

    @State private var model: DemoPlayerModel?
    @State private var mainTrack: Track?
    @State private var overlayTracks: [String: Track] = [:]
    @State private var currentOverlay: String? = nil

    private let overlayFiles = [
        "Breathing": "breathing_exercise",
        "Mantra: Peace": "mantra_peace",
        "Mantra: Love": "mantra_love"
    ]

    // MARK: - Body

    var body: some View {
        if let model = model {
            DemoContainerView(
                title: "Overlay Switching",
                icon: "rectangle.stack.fill",
                description: "Switch voice overlays while main music continues",
                model: model
            ) {
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

    private var controlsSection: some View {
        ControlsCard(title: "Main Music", icon: "music.note") {
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
        ControlsCard(title: "Voice Overlays", icon: "waveform.circle") {
            VStack(spacing: 12) {
                ForEach(overlayFiles.keys.sorted(), id: \.self) { name in
                    Button(action: { Task { await switchOverlay(to: name) } }) {
                        HStack {
                            Image(systemName: currentOverlay == name ? "checkmark.circle.fill" : "circle")
                            Text(name)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(currentOverlay == name ? Color.green.opacity(0.3) : Color(.systemBackground))
                        .foregroundStyle(currentOverlay == name ? .green : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(currentOverlay == name ? Color.green : Color.gray.opacity(0.3), lineWidth: 2)
                        )
                    }
                    .disabled(model?.state != .playing)
                }

                if currentOverlay != nil {
                    Button(action: { Task { await stopOverlay() } }) {
                        Label("Stop Overlay", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
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

            Text("• Main music plays continuously in background")
            Text("• Voice overlays switch independently")
            Text("• No gaps or interruptions in main music")
            Text("• Only one overlay plays at a time")

            Text("✅ FIXED: Now uses voice files, not music!")
                .font(.caption)
                .foregroundStyle(.green)
                .fontWeight(.bold)
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
        // Load main music track
        guard let mainUrl = Bundle.main.url(forResource: "stage2_practice_music", withExtension: "mp3"),
              let main = Track(url: mainUrl) else {
            model?.error = "Main music file not found"
            return
        }

        mainTrack = main

        // Load all overlay tracks (voice files)
        var loaded: [String: Track] = [:]
        for (name, filename) in overlayFiles {
            guard let url = Bundle.main.url(forResource: filename, withExtension: "mp3"),
                  let track = Track(url: url) else {
                model?.error = "Voice file '\(filename)' not found"
                return
            }
            loaded[name] = track
        }

        overlayTracks = loaded
    }

    private func playMain() async {
        guard let mainTrack = mainTrack else { return }
        try? await model?.loadAndPlay([mainTrack], fadeDuration: 0.0)
    }

    private func switchOverlay(to name: String) async {
        guard let service = model?.audioService,
              let track = overlayTracks[name] else { return }

        // Stop current overlay if any
        if currentOverlay != nil {
            await service.stopOverlay()
        }

        // Play new overlay
        try? await service.playOverlay(track)
        currentOverlay = name
    }

    private func stopOverlay() async {
        guard let service = model?.audioService else { return }
        await service.stopOverlay()
        currentOverlay = nil
    }

    private func stopAll() async {
        await model?.stop()
        currentOverlay = nil
    }
}

#Preview {
    OverlaySwitchingView()
}

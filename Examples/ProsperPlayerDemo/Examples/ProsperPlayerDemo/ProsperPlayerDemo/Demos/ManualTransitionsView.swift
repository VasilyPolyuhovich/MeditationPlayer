//
//  ManualTransitionsView.swift
//  ProsperPlayerDemo
//
//  Manual track switch demo - skip to next/previous with fade
//  Shows skipToNext() API usage
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct ManualTransitionsView: View {

    // MARK: - State

    @State private var model: DemoPlayerModel?
    @State private var tracks: [Track] = []

    // MARK: - Body

    var body: some View {
        if let model = model {
            DemoContainerView(
                title: "Manual Transitions",
                icon: "forward.fill",
                description: "Skip tracks manually with crossfade",
                model: model
            ) {
                playlistSection
                controlsSection
                navigationSection
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

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Playlist", systemImage: "music.note.list")
                .font(.headline)
                .foregroundStyle(.green)

            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                HStack {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                    Text(track.metadata.title ?? "Track \(index + 1)")
                        .font(.caption)
                    Spacer()
                    if model?.currentTrack?.title == track.metadata.title {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.green)
                    }
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
        ControlsCard(title: "Playback", icon: "play.circle") {
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

                StopButton(
                    disabled: model?.state == .finished
                ) {
                    await model?.stop()
                }
            }
        }
    }

    private var navigationSection: some View {
        ControlsCard(title: "Track Navigation", icon: "forward.fill") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: { Task { try? await model?.audioService.skipToPrevious() } }) {
                        Label("Previous", systemImage: "backward.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(model?.state != .playing)

                    Button(action: { Task { try? await model?.audioService.skipToNext() } }) {
                        Label("Next", systemImage: "forward.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(model?.state != .playing)
                }
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Navigation Features", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(.blue)

            Text("• Skip to next/previous track with crossfade")
            Text("• Crossfade duration: 5 seconds")
            Text("• Smooth transitions without gaps")
            Text("• Loop enabled (2 times)")

            Text("Expected: Seamless track switching")
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

        // Update configuration for looping
        let config = PlayerConfiguration(
            crossfadeDuration: 5.0,
            repeatCount: 2,
            volume: 0.8
        )
        try? await model?.updateConfiguration(config)
    }

    private func play() async {
        guard !tracks.isEmpty else { return }
        try? await model?.loadAndPlay(tracks, fadeDuration: 0.0)
    }
}

#Preview {
    ManualTransitionsView()
}

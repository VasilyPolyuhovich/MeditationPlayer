//
//  MultiInstanceView.swift
//  ProsperPlayerDemo
//
//  Multiple players demo - run two independent AudioPlayerService instances
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct MultiInstanceView: View {

    // MARK: - State

    @State private var model1: DemoPlayerModel?
    @State private var model2: DemoPlayerModel?
    @State private var track1: Track?
    @State private var track2: Track?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection

                    if let model1 = model1 {
                        player1Section(model: model1)
                    }

                    if let model2 = model2 {
                        player2Section(model: model2)
                    }

                    infoSection
                }
                .padding()
            }
            .navigationTitle("Multiple Players")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await initializeModels()
                await loadResources()
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 60))
                .foregroundStyle(.purple)

            Text("Two independent audio players running simultaneously")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func player1Section(model: DemoPlayerModel) -> some View {
        VStack(spacing: 16) {
            // State Card
            StateInfoCard(
                trackName: model.currentTrack?.title ?? "Player 1: No track",
                state: model.state
            )

            // Controls
            ControlsCard(title: "Player 1", icon: "1.circle.fill") {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        PlayButton(
                            disabled: model.state == .playing || track1 == nil
                        ) {
                            await playPlayer1()
                        }

                        PauseButton(
                            disabled: model.state != .playing
                        ) {
                            try? await model.pause()
                        }
                    }

                    StopButton(
                        disabled: model.state == .finished
                    ) {
                        await model.stop()
                    }
                }
            }

            if let error = model.error {
                ErrorCard(message: error)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.blue.opacity(0.1))
        )
    }

    private func player2Section(model: DemoPlayerModel) -> some View {
        VStack(spacing: 16) {
            // State Card
            StateInfoCard(
                trackName: model.currentTrack?.title ?? "Player 2: No track",
                state: model.state
            )

            // Controls
            ControlsCard(title: "Player 2", icon: "2.circle.fill") {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        PlayButton(
                            disabled: model.state == .playing || track2 == nil
                        ) {
                            await playPlayer2()
                        }

                        PauseButton(
                            disabled: model.state != .playing
                        ) {
                            try? await model.pause()
                        }
                    }

                    StopButton(
                        disabled: model.state == .finished
                    ) {
                        await model.stop()
                    }
                }
            }

            if let error = model.error {
                ErrorCard(message: error)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.green.opacity(0.1))
        )
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Multi-Instance Demo", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(.blue)

            Text("• Two completely independent AudioPlayerService instances")
            Text("• Each player has its own state and controls")
            Text("• Both can play simultaneously")
            Text("• Demonstrates SDK's multi-instance capability")

            Text("Expected: Both players work independently without interference")
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

    private func initializeModels() async {
        do {
            // Initialize both models concurrently
            async let m1: DemoPlayerModel = DemoPlayerModel()
            async let m2: DemoPlayerModel = DemoPlayerModel()

            let (model1Result, model2Result) = try await (m1, m2)
            model1 = model1Result
            model2 = model2Result
        } catch {
            print("Failed to initialize models: \(error)")
        }
    }

    private func loadResources() async {
        // Load track 1
        if let url1 = Bundle.main.url(forResource: "stage1_intro_music", withExtension: "mp3"),
           let t1 = Track(url: url1) {
            track1 = t1
        } else {
            model1?.error = "Track 1 not found"
        }

        // Load track 2
        if let url2 = Bundle.main.url(forResource: "stage2_practice_music", withExtension: "mp3"),
           let t2 = Track(url: url2) {
            track2 = t2
        } else {
            model2?.error = "Track 2 not found"
        }
    }

    private func playPlayer1() async {
        guard let track1 = track1 else { return }
        try? await model1?.loadAndPlay([track1], fadeDuration: 0.0)
    }

    private func playPlayer2() async {
        guard let track2 = track2 else { return }
        try? await model2?.loadAndPlay([track2], fadeDuration: 0.0)
    }
}

#Preview {
    MultiInstanceView()
}

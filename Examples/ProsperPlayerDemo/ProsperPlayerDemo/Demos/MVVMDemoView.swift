//
//  MVVMDemoView.swift
//  ProsperPlayerDemo
//
//  MVVM Pattern Demo - Clean architecture with DemoPlayerModel
//  Shows: Playback controls, overlay, configuration
//

import SwiftUI
import AudioServiceCore
import AudioServiceKit

struct MVVMDemoView: View {
    
    // MARK: - Model
    
    @State private var model = DemoPlayerModel()
    
    // MARK: - Local State
    
    @State private var tracks: [Track] = []
    @State private var overlayTrack: Track?
    @State private var overlayPlaying: Bool = false
    
    // MARK: - Body
    
    var body: some View {
        DemoContainerView(
            title: "MVVM Pattern",
            icon: "square.stack.3d.up.fill",
            description: "Clean architecture with separated model layer",
            configMode: .editable,
            model: model
        ) {
            playbackSection
            overlaySection
            infoSection
        }
        .task {
            await loadResources()
            try? await model.initialize()
        }
    }
    
    // MARK: - Sections
    
    private var playbackSection: some View {
        ControlsCard(title: "Playback", icon: "play.circle") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    PlayButton(
                        disabled: model.state == .playing || tracks.isEmpty
                    ) {
                        await play()
                    }
                    
                    PauseButton(
                        disabled: model.state != .playing
                    ) {
                        try? await model.pause()
                    }
                }
                
                HStack(spacing: 12) {
                    Button(action: { Task { try? await model.resume() } }) {
                        Label("Resume", systemImage: "play.circle")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(model.state != .paused)
                    
                    StopButton(
                        disabled: model.state == .finished
                    ) {
                        await model.stop()
                    }
                }
            }
        }
    }
    
    private var overlaySection: some View {
        ControlsCard(title: "Voice Overlay", icon: "waveform.circle") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: { Task { await playOverlay() } }) {
                        Label("Play Overlay", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(overlayPlaying || model.state != .playing || overlayTrack == nil)
                    
                    Button(action: { Task { await stopOverlay() } }) {
                        Label("Stop Overlay", systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!overlayPlaying)
                }
                
                if overlayPlaying {
                    Text("Overlay playing on top of main music")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("MVVM Pattern", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(.blue)
            
            Text("• DemoPlayerModel handles all business logic")
            Text("• View only renders UI and calls model methods")
            Text("• @Observable for automatic UI updates")
            Text("• Clean separation of concerns")
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
        // Load audio tracks
        let trackFiles = ["stage1_intro_music", "stage2_practice_music", "stage3_closing_music"]
        tracks = trackFiles.compactMap { filename in
            guard let url = Bundle.main.url(forResource: filename, withExtension: "mp3") else {
                return nil
            }
            return Track(url: url)
        }
        
        // Load overlay
        if let url = Bundle.main.url(forResource: "voice_meditation", withExtension: "mp3") {
            overlayTrack = Track(url: url)
        }
    }
    
    private func play() async {
        guard !tracks.isEmpty else { return }
        try? await model.loadAndPlay(tracks, fadeDuration: 2.0)
    }
    
    private func playOverlay() async {
        guard let service = model.audioService, let track = overlayTrack else { return }
        try? await service.playOverlay(track)
        overlayPlaying = true
    }
    
    private func stopOverlay() async {
        guard let service = model.audioService else { return }
        await service.stopOverlay()
        overlayPlaying = false
    }
}

#Preview {
    MVVMDemoView()
}

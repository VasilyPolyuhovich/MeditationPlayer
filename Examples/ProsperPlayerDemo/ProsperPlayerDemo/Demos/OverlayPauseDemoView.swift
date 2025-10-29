//
//  OverlayPauseDemoView.swift
//  ProsperPlayerDemo
//
//  Demo for overlay pause/resume functionality
//  Shows: pauseOverlay(), resumeOverlay() - independent from main track pause
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct OverlayPauseDemoView: View {
    
    // MARK: - State
    
    @State private var model = DemoPlayerModel()
    @State private var mainTrack: Track?
    @State private var overlayTrack: Track?
    @State private var overlayPlaying: Bool = false
    @State private var overlayPaused: Bool = false
    
    // MARK: - Body
    
    var body: some View {
        DemoContainerView(
            title: "Overlay Pause/Resume",
            icon: "pause.circle.fill",
            description: "Pause/resume overlay independently from main music",
            model: model
        ) {
            statusSection
            mainControlsSection
            overlayControlsSection
            scenarioSection
            infoSection
        }
        .task {
            try? await model.initialize()
            await loadResources()
        }
    }
    
    // MARK: - Sections
    
    private var statusSection: some View {
        HStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: model.state == .playing ? "music.note" : "music.note.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(model.state == .playing ? .green : .gray)
                
                Text("Main Music")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Text(model.state == .playing ? "Playing" : "Stopped")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            Divider()
                .frame(height: 60)
            
            VStack(spacing: 8) {
                Image(systemName: overlayPlaying ? (overlayPaused ? "pause.circle.fill" : "waveform.circle.fill") : "waveform.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(overlayPlaying ? (overlayPaused ? .orange : .blue) : .gray)
                
                Text("Voice Overlay")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Text(overlayPlaying ? (overlayPaused ? "Paused" : "Playing") : "Stopped")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4)
        )
    }
    
    private var mainControlsSection: some View {
        ControlsCard(title: "Main Music", icon: "music.note") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    PlayButton(
                        disabled: model.state == .playing || mainTrack == nil
                    ) {
                        await playMain()
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
                    .opacity(model.state != .paused ? 0.4 : 1.0)
                    
                    StopButton(
                        disabled: model.state == .finished
                    ) {
                        await stopAll()
                    }
                }
            }
        }
    }
    
    private var overlayControlsSection: some View {
        ControlsCard(title: "Overlay Controls", icon: "waveform.circle") {
            VStack(spacing: 12) {
                // Play/Stop Overlay
                HStack(spacing: 12) {
                    Button(action: { Task { await playOverlay() } }) {
                        Label("Play Overlay", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(overlayPlaying || model.state != .playing)
                    .opacity((overlayPlaying || model.state != .playing) ? 0.4 : 1.0)
                    
                    Button(action: { Task { await stopOverlay() } }) {
                        Label("Stop Overlay", systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!overlayPlaying)
                    .opacity(!overlayPlaying ? 0.4 : 1.0)
                }
                
                // Pause/Resume Overlay (the key feature!)
                HStack(spacing: 12) {
                    Button(action: { Task { await pauseOverlay() } }) {
                        Label("Pause Overlay", systemImage: "pause.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!overlayPlaying || overlayPaused)
                    .opacity((!overlayPlaying || overlayPaused) ? 0.4 : 1.0)
                    
                    Button(action: { Task { await resumeOverlay() } }) {
                        Label("Resume Overlay", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!overlayPaused)
                    .opacity(!overlayPaused ? 0.4 : 1.0)
                }
            }
        }
    }
    
    private var scenarioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Test Scenario", systemImage: "list.number")
                .font(.headline)
                .foregroundStyle(.purple)
            
            VStack(alignment: .leading, spacing: 8) {
                scenarioStep(number: 1, text: "Start main music")
                scenarioStep(number: 2, text: "Play voice overlay")
                scenarioStep(number: 3, text: "Pause ONLY overlay (main keeps playing!)")
                scenarioStep(number: 4, text: "Resume overlay from same position")
                scenarioStep(number: 5, text: "Try pausing main - overlay continues!")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.purple.opacity(0.1))
        )
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Key Feature", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(.blue)
            
            Text("• pauseOverlay() - Pause overlay independently")
            Text("• resumeOverlay() - Resume from paused position")
            Text("• Main music continues when overlay paused")
            Text("• Overlay continues when main music paused")
            Text("• Complete independent lifecycle control")
            
            Text("Critical: Two independent audio streams!")
                .font(.caption)
                .foregroundStyle(.orange)
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
    
    // MARK: - Helper Views
    
    private func scenarioStep(number: Int, text: String) -> some View {
        HStack(spacing: 8) {
            Text("\(number).")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.purple)
                .frame(width: 20, alignment: .leading)
            
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Business Logic
    
    private func loadResources() async {
        guard let mainUrl = Bundle.main.url(forResource: "stage2_practice_music", withExtension: "mp3"),
              let overlayUrl = Bundle.main.url(forResource: "breathing_exercise", withExtension: "mp3"),
              let main = Track(url: mainUrl),
              let overlay = Track(url: overlayUrl) else {
            model.error = "Audio files not found"
            return
        }
        
        mainTrack = main
        overlayTrack = overlay
    }
    
    private func playMain() async {
        guard let mainTrack = mainTrack else { return }
        try? await model.loadAndPlay([mainTrack], fadeDuration: 0.0)
    }
    
    private func playOverlay() async {
        guard let service = model.audioService, let overlayTrack = overlayTrack else { return }
        try? await service.playOverlay(overlayTrack)
        overlayPlaying = true
        overlayPaused = false
    }
    
    private func pauseOverlay() async {
        guard let service = model.audioService else { return }
        await service.pauseOverlay()
        overlayPaused = true
    }
    
    private func resumeOverlay() async {
        guard let service = model.audioService else { return }
        await service.resumeOverlay()
        overlayPaused = false
    }
    
    private func stopOverlay() async {
        guard let service = model.audioService else { return }
        await service.stopOverlay()
        overlayPlaying = false
        overlayPaused = false
    }
    
    private func stopAll() async {
        await stopOverlay()
        await model.stop()
    }
}

#Preview {
    OverlayPauseDemoView()
}

//
//  MantraMeditationDemoView.swift
//  ProsperPlayerDemo
//
//  Stage 2 Meditation Demo - MANY overlay switches during continuous music playback
//  Demonstrates the primary use case: meditation session with frequent voice overlay changes
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct MantraMeditationDemoView: View {
    
    // MARK: - State
    
    @State private var model = DemoPlayerModel()
    @State private var mainTrack: Track?
    @State private var overlayTracks: [OverlayType: Track] = [:]
    @State private var currentOverlay: OverlayType? = nil
    @State private var sessionTime: TimeInterval = 0
    @State private var timer: Timer?
    
    // MARK: - Overlay Types
    
    enum OverlayType: String, CaseIterable {
        case breathing = "Breathing Exercise"
        case bell = "Mindfulness Bell"
        case gong = "Meditation Gong"
        
        var filename: String {
            switch self {
            case .breathing: return "breathing_exercise"
            case .bell: return "beep"
            case .gong: return "gong"
            }
        }
        
        var icon: String {
            switch self {
            case .breathing: return "wind"
            case .bell: return "bell.fill"
            case .gong: return "circle.hexagongrid.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .breathing: return .blue
            case .bell: return .orange
            case .gong: return .purple
            }
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        DemoContainerView(
            title: "Mantra Meditation",
            icon: "figure.mind.and.body",
            description: "Stage 2 demo: MANY overlay switches during continuous music",
            configMode: .editable,
            model: model
        ) {
            sessionTimerSection
            controlsSection
            overlayGridSection
            quickActionsSection
            infoSection
        }
        .task {
            try? await model.initialize()
            await loadResources()
        }
        .onAppear {
            startSessionTimer()
        }
        .onDisappear {
            stopSessionTimer()
        }
    }
    
    // MARK: - Sections
    
    private var sessionTimerSection: some View {
        VStack(spacing: 8) {
            Label("Session Time", systemImage: "timer")
                .font(.headline)
                .foregroundStyle(.purple)
            
            Text(formatTime(sessionTime))
                .font(.system(size: 48, weight: .thin, design: .rounded))
                .foregroundStyle(.purple)
                .monospacedDigit()
            
            if model.state == .playing {
                Text("Meditation in progress...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.purple.opacity(0.1))
        )
    }
    
    private var controlsSection: some View {
        ControlsCard(title: "Main Music", icon: "music.note") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    PlayButton(
                        disabled: model.state == .playing || mainTrack == nil
                    ) {
                        await startSession()
                    }
                    
                    StopButton(
                        disabled: model.state == .finished
                    ) {
                        await stopSession()
                    }
                }
                
                if model.state == .playing {
                    Text("Main music playing continuously")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }
    
    private var overlayGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Voice Overlays", systemImage: "waveform.circle.fill")
                .font(.headline)
                .foregroundStyle(.blue)
            
            Text("Switch overlays MANY times - main music continues!")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(OverlayType.allCases, id: \.self) { overlayType in
                    overlayButton(for: overlayType)
                }
                
                // Stop overlay button
                Button(action: { Task { await stopOverlay() } }) {
                    VStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                        Text("Stop Overlay")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(currentOverlay == nil || model.state != .playing)
                .opacity((currentOverlay == nil || model.state != .playing) ? 0.4 : 1.0)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4)
        )
    }
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Quick Test Sequence", systemImage: "bolt.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            
            Button(action: { Task { await runQuickTest() } }) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Auto-Switch Overlays (3 sec each)")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding()
                .background(Color.orange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(model.state != .playing)
            .opacity(model.state != .playing ? 0.4 : 1.0)
            
            Text("Tests rapid overlay switching without interrupting main music")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.1))
        )
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Stage 2 Use Case", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(.blue)
            
            Text("• Main music plays continuously (20 min session)")
            Text("• MANY overlay switches throughout session")
            Text("• Each overlay switch is INSTANT (no fade)")
            Text("• Main music NEVER interrupted or glitched")
            Text("• Demonstrates primary SDK use case")
            
            Text("Critical: Overlay switches are frequent, not edge case!")
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
    
    // MARK: - Overlay Button
    
    private func overlayButton(for type: OverlayType) -> some View {
        Button(action: { Task { await switchOverlay(to: type) } }) {
            VStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.system(size: 30))
                Text(type.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(currentOverlay == type ? type.color : Color(.systemBackground))
            .foregroundStyle(currentOverlay == type ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(currentOverlay == type ? type.color : Color.gray.opacity(0.3), lineWidth: 2)
            )
        }
        .disabled(model.state != .playing || overlayTracks[type] == nil)
        .opacity((model.state != .playing || overlayTracks[type] == nil) ? 0.4 : 1.0)
    }
    
    // MARK: - Business Logic
    
    private func loadResources() async {
        // Load main music track
        guard let mainUrl = Bundle.main.url(forResource: "stage2_practice_music", withExtension: "mp3"),
              let main = Track(url: mainUrl) else {
            model.error = "Main music file not found"
            return
        }
        
        mainTrack = main
        
        // Load all overlay tracks
        var loaded: [OverlayType: Track] = [:]
        for overlayType in OverlayType.allCases {
            guard let url = Bundle.main.url(forResource: overlayType.filename, withExtension: "mp3"),
                  let track = Track(url: url) else {
                model.error = "Overlay file '\(overlayType.filename)' not found"
                return
            }
            loaded[overlayType] = track
        }
        
        overlayTracks = loaded
    }
    
    private func startSession() async {
        guard let mainTrack = mainTrack else { return }
        sessionTime = 0
        try? await model.loadAndPlay([mainTrack], fadeDuration: 0.0)
    }
    
    private func stopSession() async {
        await model.stop()
        stopSessionTimer()
        sessionTime = 0
        currentOverlay = nil
    }
    
    private func switchOverlay(to type: OverlayType) async {
        guard let service = model.audioService,
              let track = overlayTracks[type] else { return }
        
        // Stop current overlay if any
        if currentOverlay != nil {
            await service.stopOverlay()
        }
        
        // Play new overlay (instant, no fade)
        try? await service.playOverlay(track)
        currentOverlay = type
    }
    
    private func stopOverlay() async {
        guard let service = model.audioService else { return }
        await service.stopOverlay()
        currentOverlay = nil
    }
    
    private func runQuickTest() async {
        // Auto-switch through all overlays to demonstrate rapid switching
        for overlayType in OverlayType.allCases {
            await switchOverlay(to: overlayType)
            try? await Task.sleep(for: .seconds(3))
        }
        await stopOverlay()
    }
    
    // MARK: - Timer
    
    private func startSessionTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                if self.model.state == .playing {
                    self.sessionTime += 1
                }
            }
        }
    }
    
    private func stopSessionTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

#Preview {
    MantraMeditationDemoView()
}

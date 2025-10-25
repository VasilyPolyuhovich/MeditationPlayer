//
//  SeekAndSkipDemoView.swift
//  ProsperPlayerDemo
//
//  Demo for seek and skip functionality
//  Shows: skip(forward:), skip(backward:), seek(to:)
//

import SwiftUI
import AVFoundation
import AudioServiceKit
import AudioServiceCore

struct SeekAndSkipDemoView: View {
    
    // MARK: - State
    
    @State private var model: DemoPlayerModel?
    @State private var track: Track?
    @State private var currentPosition: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var skipInterval: TimeInterval = 15.0
    
    // MARK: - Body
    
    var body: some View {
        if let model = model {
            DemoContainerView(
                title: "Seek & Skip",
                icon: "forward.frame.fill",
                description: "Jump to position or skip forward/backward",
                model: model
            ) {
                positionSection
                skipControlsSection
                seekSliderSection
                quickJumpSection
                infoSection
            }
            .task {
                await loadResources()
                await startPositionUpdates()
            }
        } else {
            ProgressView("Initializing...")
                .task {
                    model = try? await DemoPlayerModel()
                }
        }
    }
    
    // MARK: - Sections
    
    private var positionSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Position")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatTime(currentPosition))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Duration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatTime(duration))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    if duration > 0 {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * CGFloat(currentPosition / duration), height: 6)
                            .cornerRadius(3)
                    }
                }
            }
            .frame(height: 6)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4)
        )
    }
    
    private var skipControlsSection: some View {
        ControlsCard(title: "Skip Controls", icon: "arrow.left.arrow.right") {
            VStack(spacing: 12) {
                // Play/Stop
                HStack(spacing: 12) {
                    PlayButton(
                        disabled: model?.state == .playing || track == nil
                    ) {
                        await play()
                    }
                    
                    StopButton(
                        disabled: model?.state == .finished
                    ) {
                        await model?.stop()
                    }
                }
                
                // Skip interval selector
                VStack(spacing: 8) {
                    HStack {
                        Text("Skip Interval: \(Int(skipInterval))s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    
                    HStack(spacing: 8) {
                        ForEach([5.0, 10.0, 15.0, 30.0], id: \.self) { interval in
                            Button(action: { skipInterval = interval }) {
                                Text("\(Int(interval))s")
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(skipInterval == interval ? Color.blue : Color.gray.opacity(0.2))
                                    .foregroundStyle(skipInterval == interval ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                
                // Skip buttons
                HStack(spacing: 12) {
                    Button(action: { Task { await skipBackward() } }) {
                        Label("−\(Int(skipInterval))s", systemImage: "gobackward.\(Int(skipInterval))")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(model?.state != .playing)
                    
                    Button(action: { Task { await skipForward() } }) {
                        Label("+\(Int(skipInterval))s", systemImage: "goforward.\(Int(skipInterval))")
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
    
    private var seekSliderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Seek to Position", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.purple)
            
            if duration > 0 {
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { currentPosition },
                            set: { newValue in
                                Task { await seek(to: newValue) }
                            }
                        ),
                        in: 0...duration
                    )
                    .disabled(model?.state != .playing)
                    
                    Text("Drag to seek to specific position")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Start playback to enable seek")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.purple.opacity(0.1))
        )
    }
    
    private var quickJumpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Quick Jump", systemImage: "bolt.fill")
                .font(.headline)
                .foregroundStyle(.blue)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                quickJumpButton(label: "Start", position: 0)
                quickJumpButton(label: "25%", position: duration * 0.25)
                quickJumpButton(label: "50%", position: duration * 0.5)
                quickJumpButton(label: "75%", position: duration * 0.75)
                quickJumpButton(label: "90%", position: duration * 0.9)
                quickJumpButton(label: "End", position: max(0, duration - 5))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4)
        )
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("API Reference", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(.blue)
            
            Text("• skip(forward: TimeInterval) - Jump ahead by interval")
            Text("• skip(backward: TimeInterval) - Jump back by interval")
            Text("• seek(to: TimeInterval, fadeDuration:) - Jump to exact position")
            
            Text("Use cases: Chapter navigation, replay, preview")
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
    
    // MARK: - Helper Views
    
    private func quickJumpButton(label: String, position: TimeInterval) -> some View {
        Button(action: { Task { await seek(to: position) } }) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.2))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .disabled(model?.state != .playing || duration == 0)
    }
    
    // MARK: - Business Logic
    
    private func loadResources() async {
        // Use longest track for better seek/skip demo
        guard let url = Bundle.main.url(forResource: "stage2_practice_music", withExtension: "mp3"),
              let t = Track(url: url) else {
            model?.error = "Audio file not found"
            return
        }
        
        track = t
        
        // Get duration from track metadata if available
        if let asset = try? await AVURLAsset(url: url).load(.duration) {
            duration = CMTimeGetSeconds(asset)
        }
    }
    
    private func play() async {
        guard let track = track else { return }
        currentPosition = 0
        try? await model?.loadAndPlay([track], fadeDuration: 0.0)
    }
    
    private func skipForward() async {
        guard let service = model?.audioService else { return }
        try? await service.skip(forward: skipInterval)
    }
    
    private func skipBackward() async {
        guard let service = model?.audioService else { return }
        try? await service.skip(backward: skipInterval)
    }
    
    private func seek(to time: TimeInterval) async {
        guard let service = model?.audioService else { return }
        try? await service.seek(to: time, fadeDuration: 0.1)
    }
    
    private func startPositionUpdates() async {
        guard let service = model?.audioService else { return }
        
        Task { @MainActor in
            for await position in await service.positionUpdates {
                currentPosition = position.currentTime
                
                // Update duration if we get it from position updates
                if duration == 0 || abs(duration - position.duration) > 1.0 {
                    duration = position.duration
                }
            }
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    SeekAndSkipDemoView()
}

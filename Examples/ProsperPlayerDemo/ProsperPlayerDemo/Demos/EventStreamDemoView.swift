//
//  EventStreamDemoView.swift
//  ProsperPlayerDemo
//
//  Demo for events AsyncStream
//  Shows: Real-time event monitoring with events AsyncStream
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

struct EventStreamDemoView: View {
    
    // MARK: - State
    
    @State private var model = DemoPlayerModel()
    @State private var tracks: [Track] = []
    @State private var events: [EventEntry] = []
    @State private var autoScroll: Bool = true
    
    struct EventEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let event: String
        let details: String
        let type: EventType
        
        enum EventType {
            case info
            case warning
            case error
            case success
            
            var color: Color {
                switch self {
                case .info: return .blue
                case .warning: return .orange
                case .error: return .red
                case .success: return .green
                }
            }
            
            var icon: String {
                switch self {
                case .info: return "info.circle.fill"
                case .warning: return "exclamationmark.triangle.fill"
                case .error: return "xmark.octagon.fill"
                case .success: return "checkmark.circle.fill"
                }
            }
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        DemoContainerView(
            title: "Events Stream",
            icon: "antenna.radiowaves.left.and.right",
            description: "Real-time monitoring of player events via AsyncStream",
            configMode: .editable,
            model: model
        ) {
            eventCountSection
            controlsSection
            eventsLogSection
            infoSection
        }
        .task {
            try? await model.initialize()
            await loadResources()
        }
        .onChange(of: model.state) { oldValue, newValue in
            let eventName: String
            let eventType: EventEntry.EventType
            
            switch newValue {
            case .idle:
                eventName = "Player idle"
                eventType = .info
            case .finished:
                eventName = "Playback finished"
                eventType = .success
            case .playing:
                eventName = "Playback started"
                eventType = .success
            case .paused:
                eventName = "Playback paused"
                eventType = .warning
            case .preparing:
                eventName = "Preparing playback"
                eventType = .info
            case .fadingOut:
                eventName = "Fading out"
                eventType = .info
            case .failed:
                eventName = "Playback failed"
                eventType = .error
            }
            
            addEvent(eventName, details: "State: \(newValue)", type: eventType)
        }
    }
    
    // MARK: - Sections
    
    private var eventCountSection: some View {
        HStack(spacing: 20) {
            eventCounter(
                count: events.filter { $0.type == .info }.count,
                label: "Info",
                color: .blue,
                icon: "info.circle.fill"
            )
            
            eventCounter(
                count: events.filter { $0.type == .success }.count,
                label: "Success",
                color: .green,
                icon: "checkmark.circle.fill"
            )
            
            eventCounter(
                count: events.filter { $0.type == .warning }.count,
                label: "Warnings",
                color: .orange,
                icon: "exclamationmark.triangle.fill"
            )
            
            eventCounter(
                count: events.filter { $0.type == .error }.count,
                label: "Errors",
                color: .red,
                icon: "xmark.octagon.fill"
            )
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
                    
                    Button(action: { Task { await triggerError() } }) {
                        Label("Trigger Error", systemImage: "exclamationmark.triangle")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(model.state != .playing)
                }
                
                HStack(spacing: 12) {
                    Button(action: { events.removeAll() }) {
                        Label("Clear Log", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(events.isEmpty)
                    
                    StopButton(
                        disabled: model.state == .finished
                    ) {
                        await model.stop()
                    }
                }
            }
        }
    }
    
    private var eventsLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Events Log (\(events.count))", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                    .foregroundStyle(.blue)
                
                Spacer()
                
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if events.isEmpty {
                            Text("No events yet. Start playback to see events...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            ForEach(events) { entry in
                                eventRow(entry)
                                    .id(entry.id)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(height: 300)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .onChange(of: events.count) { _, _ in
                    if autoScroll, let lastEvent = events.last {
                        withAnimation {
                            proxy.scrollTo(lastEvent.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Events AsyncStream", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(.blue)
            
            Text("• Real-time event monitoring via AsyncStream")
            Text("• Replaces old observer pattern (deprecated in v3.1)")
            Text("• Includes: state changes, errors, warnings, completions")
            Text("• Non-blocking, reactive updates")
            
            Text("Usage: for await event in player.events { ... }")
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
    
    private func eventCounter(count: Int, label: String, color: Color, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func eventRow(_ entry: EventEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.type.icon)
                .foregroundStyle(entry.type.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.event)
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text(formatTimestamp(entry.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                
                if !entry.details.isEmpty {
                    Text(entry.details)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(entry.type.color.opacity(0.1))
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
            model.error = "Audio files not found"
            return
        }
        
        tracks = loadedTracks
        addEvent("Resources loaded", details: "\(tracks.count) tracks ready", type: .success)
    }
    
    private func play() async {
        guard !tracks.isEmpty else { return }
        addEvent("Starting playback", details: "Loading \(tracks.count) tracks", type: .info)
        try? await model.loadAndPlay(tracks, fadeDuration: 0.0)
    }
    
    private func triggerError() async {
        // Try to seek beyond duration to trigger error
        guard let service = model.audioService else { return }
        try? await service.seek(to: 99999, fadeDuration: 0.0)
    }
    
    private func addEvent(_ event: String, details: String = "", type: EventEntry.EventType) {
        let entry = EventEntry(
            timestamp: Date(),
            event: event,
            details: details,
            type: type
        )
        events.append(entry)
        
        // Keep only last 50 events
        if events.count > 50 {
            events.removeFirst()
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

#Preview {
    EventStreamDemoView()
}

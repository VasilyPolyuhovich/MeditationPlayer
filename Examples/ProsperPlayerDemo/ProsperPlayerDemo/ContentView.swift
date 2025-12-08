//
//  ContentView.swift
//  ProsperPlayerDemo
//
//  Demo selection menu
//

import SwiftUI

struct ContentView: View {
    @State private var selectedDemo: Demo?
    
    enum DemoCategory: String, CaseIterable, Identifiable {
        case basics = "Basic Playback"
        case crossfade = "Crossfade & Transitions"
        case repeatModes = "Repeat Modes"
        case overlay = "Overlay Player"
        case advanced = "Advanced Features"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .basics: return "play.circle.fill"
            case .crossfade: return "waveform.path"
            case .repeatModes: return "repeat.circle.fill"
            case .overlay: return "speaker.wave.3.fill"
            case .advanced: return "gearshape.2.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .basics: return .blue
            case .crossfade: return .purple
            case .repeatModes: return .orange
            case .overlay: return .green
            case .advanced: return .pink
            }
        }
        
        var demos: [Demo] {
            switch self {
            case .basics:
                return [.simplePlayback, .pauseResume, .fadeStartStop]
            case .crossfade:
                return [.crossfadeBasic, .crossfadeWithPause, .manualTransitions]
            case .repeatModes:
                return [.loopWithCrossfade, .overlayWithDelays]
            case .overlay:
                return [.overlayBasic, .overlaySwitching, .overlayPause]
            case .advanced:
                return [.mvvmDemo, .seekAndSkip, .eventsStream, .queueDiagnostics, .multiInstance, .audioSessionDemo, .remoteCommandDemo, .mantraMeditation, .fullMeditation]
            }
        }
    }
    
    enum Demo: String, CaseIterable, Identifiable {
        // Basic Playback
        case simplePlayback = "Simple Playback"
        case pauseResume = "Pause & Resume"
        case fadeStartStop = "Fade In/Out"
        
        // Crossfade
        case crossfadeBasic = "Basic Crossfade"
        case crossfadeWithPause = "Crossfade + Pause"
        case manualTransitions = "Manual Track Switch"
        
        // Repeat Modes
        case loopWithCrossfade = "Loop with Crossfade"
        case overlayWithDelays = "Overlay Repeat + Delays"
        
        // Overlay
        case overlayBasic = "Basic Overlay"
        case overlaySwitching = "Multiple Overlays"
        case overlayPause = "Overlay Pause/Resume"
        
        // Advanced
        case mvvmDemo = "MVVM Architecture Demo"
        case seekAndSkip = "Seek & Skip"
        case eventsStream = "Events Stream"
        case queueDiagnostics = "Queue Diagnostics"
        case multiInstance = "Multiple Players"
        case audioSessionDemo = "Audio Session Test"
        case remoteCommandDemo = "Remote Command Delegate"
        case mantraMeditation = "Stage 2: Mantra Practice"
        case fullMeditation = "3-Stage Meditation"
        
        var id: String { rawValue }
        
        var description: String {
            switch self {
            case .mvvmDemo: return "Proper MVVM + ALL SDK features + Debug logging"
            case .simplePlayback: return "Load and play single track"
            case .pauseResume: return "Pause at any moment and resume"
            case .fadeStartStop: return "Smooth fade in/out on start/stop"
            case .crossfadeBasic: return "Seamless transitions between tracks"
            case .crossfadeWithPause: return "Pause during crossfade"
            case .manualTransitions: return "Skip to next/previous with fade"
            case .loopWithCrossfade: return "Repeat playlist with crossfades"
            case .overlayWithDelays: return "Overlay loops with fade + delay"
            case .overlayBasic: return "Voice over background music"
            case .overlaySwitching: return "Switch overlays on the fly"
            case .overlayPause: return "Pause/resume overlay independently"
            case .seekAndSkip: return "Jump to position or skip time"
            case .eventsStream: return "Listen to player events stream"
            case .queueDiagnostics: return "Monitor queue performance metrics"
            case .multiInstance: return "Run 2+ players simultaneously"
            case .audioSessionDemo: return "Work with external recorders"
            case .remoteCommandDemo: return "Customize lock screen controls"
            case .mantraMeditation: return "MANY overlay switches (Stage 2)"
            case .fullMeditation: return "Complete 30-min session demo"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Header
                Section {
                    headerSection
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                
                // Categories
                ForEach(DemoCategory.allCases) { category in
                    Section {
                        ForEach(category.demos) { demo in
                            DemoRow(demo: demo, category: category)
                                .onTapGesture {
                                    selectedDemo = demo
                                }
                        }
                    } header: {
                        HStack {
                            Image(systemName: category.icon)
                                .foregroundStyle(category.color)
                            Text(category.rawValue)
                                .font(.headline)
                        }
                    }
                }
            }
            .navigationTitle("AudioServiceKit")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedDemo) { demo in
                demoView(for: demo)
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 70))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .blue.opacity(0.3), radius: 10)
            
            Text("AudioServiceKit Demos")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Explore different SDK capabilities")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical)
    }
    
    @ViewBuilder
    private func demoView(for demo: Demo) -> some View {
        switch demo {
        case .mvvmDemo:
            MVVMDemoView()
        case .simplePlayback:
            SimplePlaybackView()
        case .pauseResume:
            PauseResumeView()
        case .fadeStartStop:
            FadeStartStopView()
        case .crossfadeBasic:
            CrossfadeBasicView()
        case .crossfadeWithPause:
            CrossfadeWithPauseView()
        case .manualTransitions:
            ManualTransitionsView()
        case .loopWithCrossfade:
            LoopWithCrossfadeView()
        case .overlayWithDelays:
            OverlayWithDelaysView()
        case .overlayBasic:
            OverlayBasicView()
        case .overlaySwitching:
            OverlaySwitchingView()
        case .overlayPause:
            OverlayPauseDemoView()
        case .seekAndSkip:
            SeekAndSkipDemoView()
        case .eventsStream:
            EventStreamDemoView()
        case .queueDiagnostics:
            QueueDiagnosticsDemoView()
        case .multiInstance:
            MultiInstanceView()
        case .audioSessionDemo:
            AudioSessionDemoView()
        case .remoteCommandDemo:
            RemoteCommandDemoView()
        case .mantraMeditation:
            MantraMeditationDemoView()
        case .fullMeditation:
            MeditationSessionView()
        }
    }
}

struct DemoRow: View {
    let demo: ContentView.Demo
    let category: ContentView.DemoCategory
    
    var body: some View {
        HStack(spacing: 12) {
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(demo.rawValue)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(demo.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Arrow
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
}

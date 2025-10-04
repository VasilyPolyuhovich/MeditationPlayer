import SwiftUI
import AudioServiceKit
import AudioServiceCore

@main
struct MeditationDemoApp: App {
    // Create audio player service
    @State private var audioService = AudioPlayerService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.audioService, audioService)
        }
    }
}

// MARK: - Environment Key

private struct AudioServiceKey: EnvironmentKey {
    static let defaultValue: AudioPlayerService = AudioPlayerService()
}

extension EnvironmentValues {
    var audioService: AudioPlayerService {
        get { self[AudioServiceKey.self] }
        set { self[AudioServiceKey.self] = newValue }
    }
}

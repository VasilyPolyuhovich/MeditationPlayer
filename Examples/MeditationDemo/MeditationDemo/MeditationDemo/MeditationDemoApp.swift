import SwiftUI
import AudioServiceKit

@main
struct MeditationDemoApp: App {
    @State private var audioService = AudioPlayerService()
    @State private var viewModel: AudioPlayerViewModel?
    
    var body: some Scene {
        WindowGroup {
            Group {
                if let viewModel {
                    ContentView(viewModel: viewModel)
                } else {
                    ProgressView("Initializing Audio Engine...")
                        .controlSize(.large)
                }
            }
            .task {
                // Setup audio service (actor initialization)
                await audioService.setup()
                
                // Create ViewModel on MainActor
                viewModel = AudioPlayerViewModel(audioService: audioService)
            }
        }
    }
}

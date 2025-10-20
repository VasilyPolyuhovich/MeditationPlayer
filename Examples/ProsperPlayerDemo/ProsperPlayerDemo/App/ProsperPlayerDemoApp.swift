import SwiftUI
import AudioServiceKit

@main
struct ProsperPlayerDemoApp: App {
    @State private var audioService = AudioPlayerService()
    @State private var viewModel: PlayerViewModel?
    
    var body: some Scene {
        WindowGroup {
            if let viewModel {
                MainView(viewModel: viewModel)
            } else {
                ProgressView("Initializing...")
                    .task {
                        // Initialize ViewModel on MainActor
                        // No need to call setup() - it's automatic!
                        viewModel = await PlayerViewModel(audioService: audioService)
                    }
            }
        }
    }
}

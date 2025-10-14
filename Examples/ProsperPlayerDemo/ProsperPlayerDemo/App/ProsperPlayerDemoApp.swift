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
                ProgressView("Initializing SDK...")
                    .task {
                        // CRITICAL: Setup audioService FIRST
                        await audioService.setup()
                        
                        // Initialize ViewModel on MainActor
                        viewModel = await PlayerViewModel(audioService: audioService)
                    }
            }
        }
    }
}

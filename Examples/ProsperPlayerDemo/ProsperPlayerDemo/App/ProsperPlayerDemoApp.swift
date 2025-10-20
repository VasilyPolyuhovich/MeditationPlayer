import SwiftUI
import AudioServiceKit

@main
struct ProsperPlayerDemoApp: App {
    @State private var viewModel: PlayerViewModel?
    
    var body: some Scene {
        WindowGroup {
            if let viewModel {
                MainView(viewModel: viewModel)
            } else {
                ProgressView("Initializing...")
                    .task {
                        // Initialize AudioService with async init
                        // This performs full setup (audio session, engine, nodes)
                        let audioService = await AudioPlayerService()
                        
                        // Initialize ViewModel
                        viewModel = await PlayerViewModel(audioService: audioService)
                    }
            }
        }
    }
}

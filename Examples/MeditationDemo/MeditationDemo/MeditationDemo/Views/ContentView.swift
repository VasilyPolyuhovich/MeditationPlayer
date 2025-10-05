import SwiftUI
import AudioServiceCore  // For PlayerState, FadeCurve types

/// Main container view for MeditationDemo
struct ContentView: View {
    @State private var viewModel: AudioPlayerViewModel
    @State private var showConfiguration = false
    
    init(viewModel: AudioPlayerViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Status Display
                    StatusView(viewModel: viewModel)
                    
                    // Player Controls
                    PlayerControlsView(viewModel: viewModel)
                    
                    // Track Management
                    TrackSwitcherView(viewModel: viewModel)
                    
                    // Info Footer
                    infoFooter
                }
                .padding()
            }
            .navigationTitle("ProsperPlayer Demo")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showConfiguration.toggle()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $showConfiguration) {
                ConfigurationView(viewModel: viewModel)
            }
        }
    }
    
    private var infoFooter: some View {
        VStack(spacing: 8) {
            Text("ProsperPlayer SDK v2.11.0")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("Dual-player crossfade • Swift 6 concurrency • Playlist & Single Loop modes")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 20)
    }
}

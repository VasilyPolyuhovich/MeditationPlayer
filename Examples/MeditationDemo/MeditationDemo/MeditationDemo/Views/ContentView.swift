import SwiftUI
import AudioServiceCore
import AudioServiceKit

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
                    
                    // Player Controls (simplified)
                    PlayerControlsView(viewModel: viewModel)
                    
                    // Quick Actions (NEW - Feature #3)
                    QuickActionsView(viewModel: viewModel)
                    
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
            Text("ProsperPlayer SDK v2.15.0")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("Dual-player crossfade • Swift 6 concurrency • Hot playlist swap")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            
            Text("4 sample tracks • Single/Playlist repeat modes")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 20)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var viewModel = AudioPlayerViewModel(
        audioService: AudioPlayerService(
            configuration: PlayerConfiguration()
        )
    )
    
    ContentView(viewModel: viewModel)
}

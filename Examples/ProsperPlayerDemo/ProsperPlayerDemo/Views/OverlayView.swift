import SwiftUI

/// Overlay player view - voiceover tracks
struct OverlayView: View {
    @Bindable var viewModel: PlayerViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(PlayerViewModel.overlayTracks, id: \.self) { track in
                        Button {
                            Task {
                                try? await viewModel.playOverlay(track)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "waveform")
                                    .foregroundStyle(.blue)
                                
                                Text(track)
                                    .font(.subheadline)
                                
                                Spacer()
                                
                                if viewModel.isOverlayPlaying && viewModel.selectedOverlayTrack == track {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Voiceover Tracks")
                } footer: {
                    Text("Select a voiceover to play as overlay on top of main playback")
                }
                
                if viewModel.isOverlayPlaying {
                    Section {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.stopOverlay()
                            }
                        } label: {
                            Label("Stop Overlay", systemImage: "stop.fill")
                        }
                    }
                }
            }
            .navigationTitle("Overlay Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

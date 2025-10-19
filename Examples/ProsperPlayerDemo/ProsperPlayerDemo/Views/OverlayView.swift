import SwiftUI
import AudioServiceCore

/// Overlay player view - voiceover tracks with dynamic controls
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
                
                // MARK: - Overlay Controls (when playing)
                if viewModel.isOverlayPlaying {
                    Section {
                        // Loop Toggle
                        Toggle(isOn: $viewModel.overlayLoopEnabled) {
                            HStack {
                                Image(systemName: "repeat")
                                    .foregroundStyle(.blue)
                                Text("Loop Indefinitely")
                            }
                        }
                        .onChange(of: viewModel.overlayLoopEnabled) { _, newValue in
                            Task {
                                await viewModel.setOverlayLoopMode(enabled: newValue)
                            }
                        }
                        
                        // Delay Slider
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "timer")
                                    .foregroundStyle(.blue)
                                Text("Delay Between Repeats")
                                Spacer()
                                Text("\(Int(viewModel.overlayLoopDelay))s")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                            
                            Slider(
                                value: $viewModel.overlayLoopDelay,
                                in: 0...30,
                                step: 1
                            ) {
                                Text("Delay")
                            } minimumValueLabel: {
                                Text("0s")
                                    .font(.caption2)
                            } maximumValueLabel: {
                                Text("30s")
                                    .font(.caption2)
                            }
                            .onChange(of: viewModel.overlayLoopDelay) { _, newValue in
                                Task {
                                    await viewModel.setOverlayLoopDelay(newValue)
                                }
                            }
                            
                            Text(viewModel.overlayLoopDelay == 0 ? "No delay - continuous playback" : "Wait \(Int(viewModel.overlayLoopDelay)) seconds between repeats")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Loop Settings")
                    } footer: {
                        Text("Changes take effect on the next loop iteration")
                    }
                    
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

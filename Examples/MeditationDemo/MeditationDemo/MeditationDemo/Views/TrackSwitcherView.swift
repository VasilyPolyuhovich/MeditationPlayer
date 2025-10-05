import SwiftUI
import AudioServiceCore  // For FadeCurve

/// Track management with mode selection and quick crossfade settings
struct TrackSwitcherView: View {
    let viewModel: AudioPlayerViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "music.note.list")
                    .foregroundStyle(.blue)
                Text("Playback Mode")
                    .font(.headline)
            }
            
            // Playback Mode Selector
            Picker("Mode", selection: Binding(
                get: { viewModel.playbackMode },
                set: { newMode in
                    // Update mode and restart if playing
                    let wasPlaying = viewModel.isPlaying
                    Task {
                        if wasPlaying {
                            await viewModel.stop()
                        }
                        await MainActor.run {
                            viewModel.playbackMode = newMode
                        }
                        if wasPlaying {
                            await viewModel.play()
                        }
                    }
                }
            )) {
                ForEach(PlaybackMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            
            HStack {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(viewModel.playbackMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // Quick Crossfade Settings
            VStack(alignment: .leading, spacing: 12) {
                // Crossfade Duration
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "waveform.circle")
                            .foregroundStyle(.blue)
                        Text("Crossfade Duration")
                            .font(.subheadline)
                        Spacer()
                        Text("\(String(format: "%.1f", viewModel.crossfadeDuration))s")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Slider(
                        value: Binding(
                            get: { viewModel.crossfadeDuration },
                            set: { viewModel.crossfadeDuration = $0 }
                        ),
                        in: 1...30,
                        step: 0.5
                    )
                }
                
                // Fade Curve
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "function")
                            .foregroundStyle(.blue)
                        Text("Fade Curve")
                            .font(.subheadline)
                    }
                    
                    Picker("Curve", selection: Binding(
                        get: { viewModel.selectedCurve },
                        set: { viewModel.selectedCurve = $0 }
                    )) {
                        Text("Linear").tag(FadeCurve.linear)
                        Text("Equal Power").tag(FadeCurve.equalPower)
                        Text("Logarithmic").tag(FadeCurve.logarithmic)
                        Text("Exponential").tag(FadeCurve.exponential)
                        Text("S-Curve").tag(FadeCurve.sCurve)
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 2)
    }
}

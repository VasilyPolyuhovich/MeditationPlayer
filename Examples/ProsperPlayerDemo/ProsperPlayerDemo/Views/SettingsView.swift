import SwiftUI
import AudioServiceCore

/// Settings view - SDK configuration demonstration
struct SettingsView: View {
    @Bindable var viewModel: PlayerViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                // Crossfade Settings Section
                Section {
                    crossfadeDurationSlider
                    fadeCurvePicker
                } header: {
                    Text("Crossfade Configuration")
                } footer: {
                    Text("Changes take effect on next crossfade")
                }
                
                // Repeat Mode Section
                Section {
                    repeatModePicker
                } header: {
                    Text("Repeat Mode")
                } footer: {
                    Text("Single Track loops current track. Playlist advances and loops entire playlist.")
                }
                
                // Auto-Calculated Fades Section
                Section {
                    fadeInInfo
                    fadeOutInfo
                } header: {
                    Text("Auto-Calculated Fade Durations")
                } footer: {
                    Text("Fade in/out are calculated as 30% of crossfade duration")
                }
                
                // SDK Information Section
                Section {
                    sdkInfoRows
                } header: {
                    Text("SDK Information")
                }
            }
            .navigationTitle("SDK Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    // MARK: - Crossfade Duration
    
    private var crossfadeDurationSlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Duration")
                Spacer()
                Text(String(format: "%.1fs", viewModel.crossfadeDuration))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            
            Slider(
                value: $viewModel.crossfadeDuration,
                in: 1.0...30.0,
                step: 0.5
            )
        }
    }
    
    // MARK: - Fade Curve
    
    private var fadeCurvePicker: some View {
        Picker("Curve Algorithm", selection: $viewModel.selectedCurve) {
            Text("Linear").tag(FadeCurve.linear)
            Text("Equal Power (Default)").tag(FadeCurve.equalPower)
            Text("Logarithmic").tag(FadeCurve.logarithmic)
            Text("Exponential").tag(FadeCurve.exponential)
            Text("S-Curve").tag(FadeCurve.sCurve)
        }
    }
    
    // MARK: - Repeat Mode
    
    private var repeatModePicker: some View {
        Picker("Mode", selection: Binding(
            get: { viewModel.repeatMode },
            set: { newMode in
                Task {
                    await viewModel.updateRepeatMode(newMode)
                }
            }
        )) {
            Text("Off").tag(RepeatMode.off)
            Text("Single Track").tag(RepeatMode.singleTrack)
            Text("Playlist").tag(RepeatMode.playlist)
        }
        .pickerStyle(.segmented)
    }
    
    // MARK: - Fade Info
    
    private var fadeInInfo: some View {
        HStack {
            Text("Fade In")
            Spacer()
            Text(String(format: "%.1fs (30%%)", viewModel.crossfadeDuration * 0.3))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
    
    private var fadeOutInfo: some View {
        HStack {
            Text("Fade Out")
            Spacer()
            Text(String(format: "%.1fs (30%%)", viewModel.crossfadeDuration * 0.3))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
    
    // MARK: - SDK Info
    
    private var sdkInfoRows: some View {
        Group {
            InfoRow(label: "Version", value: "4.0.0")
            InfoRow(label: "Architecture", value: "Dual AVAudioPlayerNode")
            InfoRow(label: "Concurrency", value: "Swift 6 Actor Isolation")
            InfoRow(label: "Sync Method", value: "AVAudioTime (sample-accurate)")
            InfoRow(label: "Fade Steps", value: "Adaptive (20-100 Hz)")
            InfoRow(label: "Buffer Delay", value: "2048 samples (~46ms)")
        }
    }
}

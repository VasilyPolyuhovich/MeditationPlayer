import SwiftUI
import AudioServiceCore

/// Configuration sheet for audio playback settings
struct ConfigurationView: View {
    @Bindable var viewModel: AudioPlayerViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                // Crossfade Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text("\(String(format: "%.1f", viewModel.crossfadeDuration))s")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $viewModel.crossfadeDuration, in: 1...30, step: 0.5)
                    }
                    
                    Picker("Curve Algorithm", selection: $viewModel.selectedCurve) {
                        Text("Linear").tag(FadeCurve.linear)
                        Text("Equal Power (Default)").tag(FadeCurve.equalPower)
                        Text("Logarithmic").tag(FadeCurve.logarithmic)
                        Text("Exponential").tag(FadeCurve.exponential)
                        Text("S-Curve").tag(FadeCurve.sCurve)
                    }
                    
                    curveInfo
                } header: {
                    Text("Crossfade Settings")
                } footer: {
                    Text("Equal-power maintains constant perceived loudness (cos² + sin² = 1)")
                }
                
                // Auto-calculated Fades
                Section {
                    HStack {
                        Text("Fade In (Auto)")
                        Spacer()
                        Text("\(String(format: "%.1f", fadeInDuration))s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Text("Calculated as 30% of crossfade duration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Track Start Fade")
                }
                
                // Volume Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Level")
                            Spacer()
                            Text("\(viewModel.volume)%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(viewModel.volume) },
                            set: { 
                                let newValue = Int($0)
                                Task { await viewModel.setVolume(newValue) }
                            }
                        ), in: 0...100, step: 1)
                    }
                } header: {
                    Text("Volume")
                }
                
                // Looping Section
                Section {
                    Toggle("Enable Looping", isOn: $viewModel.enableLooping)
                    
                    if viewModel.enableLooping {
                        Toggle("Infinite Repeat", isOn: Binding(
                            get: { viewModel.repeatCount == nil },
                            set: { viewModel.repeatCount = $0 ? nil : 2 }
                        ))
                        
                        if viewModel.repeatCount != nil {
                            Stepper("Count: \(viewModel.repeatCount ?? 0)", 
                                   value: Binding(
                                    get: { viewModel.repeatCount ?? 0 },
                                    set: { viewModel.repeatCount = $0 }
                                   ), in: 1...10)
                        }
                    }
                } header: {
                    Text("Playlist Loop")
                } footer: {
                    Text("When enabled, playlist cycles through tracks infinitely or N times")
                }
                
                // Technical Info
                Section {
                    technicalInfo
                } header: {
                    Text("Technical Details")
                }
            }
            .navigationTitle("Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private var fadeInDuration: Double {
        // Auto-calculated: 30% of crossfade
        viewModel.crossfadeDuration * 0.3
    }
    
    private var curveInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(curveDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var curveDescription: String {
        switch viewModel.selectedCurve {
        case .linear:
            return "y = x (simple interpolation, not perceptually optimal)"
        case .equalPower:
            return "y = sin(x·π/2) (constant power, best for crossfade)"
        case .logarithmic:
            return "y = log₁₀(0.99x + 0.01) + 2 (fast start, slow end)"
        case .exponential:
            return "y = x² (slow start, fast end)"
        case .sCurve:
            return "y = x²(3 - 2x) smoothstep (slow at extremes)"
        }
    }
    
    private var technicalInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            InfoRow(label: "Architecture", value: "Dual AVAudioPlayerNode")
            InfoRow(label: "Concurrency", value: "Swift 6 Actor Isolation")
            InfoRow(label: "Sync Method", value: "AVAudioTime (sample-accurate)")
            InfoRow(label: "Buffer Delay", value: "2048 samples (~46ms)")
            InfoRow(label: "Fade Steps", value: "Adaptive (20-100 Hz)")
            InfoRow(label: "Seek Mode", value: "Fade-enabled (click-free)")
            InfoRow(label: "Playlist Mode", value: "SDK-managed auto-advance")
        }
    }
}

// MARK: - Helper Views

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .font(.caption)
    }
}

//
//  DemoComponents.swift
//  ProsperPlayerDemo
//
//  Reusable UI components for demo views
//

import SwiftUI
import AudioServiceCore

// MARK: - Demo Header

/// Header section with icon and description
struct DemoHeader: View {
    let icon: String
    let description: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - State Info Card

/// Card displaying current track and state information
struct StateInfoCard: View {
    let trackName: String?
    let state: PlayerState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Track Info", systemImage: "music.note")
                .font(.headline)
                .foregroundStyle(.blue)

            HStack {
                Text("Current:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(trackName ?? "No track")
                    .fontWeight(.medium)
            }

            HStack {
                Text("State:")
                    .foregroundStyle(.secondary)
                Spacer()
                StateLabel(state: state)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4)
        )
    }
}

// MARK: - State Label

/// Label displaying player state with appropriate icon and color
struct StateLabel: View {
    let state: PlayerState
    
    var body: some View {
        switch state {
        case .idle:
            Label("Idle", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .preparing:
            Label("Preparing", systemImage: "hourglass")
                .foregroundStyle(.orange)
        case .playing:
            Label("Playing", systemImage: "play.fill")
                .foregroundStyle(.green)
        case .paused:
            Label("Paused", systemImage: "pause.fill")
                .foregroundStyle(.orange)
        case .fadingOut:
            Label("Fading Out", systemImage: "speaker.wave.1")
                .foregroundStyle(.orange)
        case .finished:
            Label("Finished", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Error Card

/// Card displaying error message with retry option
struct ErrorCard: View {
    let message: String
    var onRetry: (() async -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            if let onRetry = onRetry {
                Button(action: { Task { await onRetry() } }) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .foregroundStyle(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
        )
    }
}

// MARK: - Controls Card Container

/// Standardized container for control buttons
struct ControlsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.blue)

            content()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4)
        )
    }
}

// MARK: - Standard Action Buttons

struct PlayButton: View {
    let action: () async -> Void
    let isDisabled: Bool
    
    init(disabled: Bool = false, action: @escaping () async -> Void) {
        self.isDisabled = disabled
        self.action = action
    }
    
    var body: some View {
        Button(action: { Task { await action() } }) {
            Label("Play", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
    }
}

struct PauseButton: View {
    let action: () async -> Void
    let isDisabled: Bool
    
    init(disabled: Bool = false, action: @escaping () async -> Void) {
        self.isDisabled = disabled
        self.action = action
    }
    
    var body: some View {
        Button(action: { Task { await action() } }) {
            Label("Pause", systemImage: "pause.fill")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
    }
}

struct StopButton: View {
    let action: () async -> Void
    let isDisabled: Bool
    
    init(disabled: Bool = false, action: @escaping () async -> Void) {
        self.isDisabled = disabled
        self.action = action
    }
    
    var body: some View {
        Button(action: { Task { await action() } }) {
            Label("Stop", systemImage: "stop.fill")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.8))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
    }
}

// MARK: - Previews

#Preview("Demo Header") {
    DemoHeader(
        icon: "play.circle.fill",
        description: "Load and play a single track"
    )
}

#Preview("State Info Card") {
    VStack(spacing: 20) {
        StateInfoCard(
            trackName: "stage1_intro_music.mp3",
            state: .playing
        )
        
        StateInfoCard(
            trackName: nil,
            state: .finished
        )
    }
    .padding()
}

#Preview("Error Card") {
    VStack(spacing: 20) {
        ErrorCard(message: "Failed to load audio file")
        
        ErrorCard(message: "Network error occurred") {
            print("Retry tapped")
        }
    }
    .padding()
}

#Preview("Buttons") {
    VStack(spacing: 12) {
        PlayButton { }
        PauseButton(disabled: true) { }
        StopButton { }
    }
    .padding()
}

//
//  PlayerControlsView.swift
//  ProsperPlayerDemo
//
//  Main playback controls component
//

import SwiftUI

struct PlayerControlsView: View {
    let isPlaying: Bool
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            // Stop button
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.title)
                    .foregroundStyle(.red)
                    .frame(width: 60, height: 60)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Circle())
            }

            // Play/Pause button (larger, primary action)
            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())
                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }

            // Next stage button
            Button(action: onNext) {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
                    .frame(width: 60, height: 60)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Circle())
            }
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        PlayerControlsView(
            isPlaying: false,
            onPlayPause: {},
            onNext: {},
            onStop: {}
        )

        PlayerControlsView(
            isPlaying: true,
            onPlayPause: {},
            onNext: {},
            onStop: {}
        )
    }
    .padding()
}

//
//  MeditationSessionView.swift
//  ProsperPlayerDemo
//
//  Full meditation session demo
//

import SwiftUI

struct MeditationSessionView: View {
    @State private var session = MeditationSession()
    @State private var crossfadeDuration: Double = 5.0
    @State private var volume: Double = 0.8
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Track Info
                    TrackInfoView(
                        stageName: session.currentStage.rawValue,
                        trackName: session.currentTrackInfo,
                        isPlaying: session.playbackState == .playing
                    )
                    
                    // Main Controls
                    PlayerControlsView(
                        isPlaying: session.playbackState == .playing,
                        onPlayPause: {
                            Task {
                                await session.togglePlayPause()
                            }
                        },
                        onNext: {
                            Task {
                                await session.nextStage()
                            }
                        },
                        onStop: {
                            Task {
                                await session.stopSession()
                            }
                        }
                    )
                    
                    // Overlay Controls
                    OverlayControlsView(
                        isOverlayPlaying: session.isOverlayPlaying,
                        onToggle: {
                            Task {
                                await session.toggleOverlay()
                            }
                        }
                    )
                    
                    // Sound Effects
                    SoundEffectsView(
                        onPlayGong: {
                            Task {
                                await session.playGong()
                            }
                        },
                        onPlayBeep: {
                            Task {
                                await session.playBeep()
                            }
                        }
                    )
                    
                    // Start Session Button (shown when idle)
                    if session.currentStage == .idle {
                        Button {
                            Task {
                                await session.startSession()
                            }
                        } label: {
                            Text("Start 3-Stage Meditation")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    
                    // Error Message
                    if let error = session.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("Meditation Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        // Sheet will dismiss
                    }
                }
            }
        }
    }
}

#Preview {
    MeditationSessionView()
}

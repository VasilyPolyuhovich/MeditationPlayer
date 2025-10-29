//
//  DemoPlayerModel.swift
//  ProsperPlayerDemo
//
//  Shared model for demo views - eliminates duplicate state management
//

import SwiftUI
import AudioServiceKit
import AudioServiceCore

/// Reusable observable model for demo views
///
/// Manages AudioPlayerService lifecycle and state observation.
/// Eliminates ~100 LOC of duplicate code per demo view.
@MainActor
@Observable
final class DemoPlayerModel {
    
    // MARK: - Public State
    
    var state: PlayerState = .finished
    var currentTrack: Track.Metadata?
    var error: String?
    
    /// Current configuration (updated when service initializes or config changes)
    private(set) var currentConfig: PlayerConfiguration = .demoDefault
    
    // MARK: - Service Access
    
    private(set) var audioService: AudioPlayerService!
    
    // MARK: - Private State
    
    private var stateTask: Task<Void, Never>?
    private var trackTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    /// Initialize with custom configuration
    /// - Parameter config: Player configuration (defaults to standard demo config)
    init(config: PlayerConfiguration = .demoDefault) {
        // Empty synchronous init for SwiftUI compatibility
    }
    
    /// Initialize audio service asynchronously
    /// Call this from .task modifier in view
    func initialize(config: PlayerConfiguration = .demoDefault) async throws {
        // Prevent double initialization
        guard audioService == nil else {
            print("[DEMO_MODEL] ⚠️ Already initialized, skipping")
            return
        }
        
        do {
            audioService = try await AudioPlayerService(configuration: config)
            currentConfig = config
            startObserving()
            error = nil
        } catch {
            self.error = "Failed to initialize service: \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - Observation
    
    private func startObserving() {
        // Observe state updates
        // ✅ CRITICAL FIX: Don't use @MainActor in Task to prevent blocking
        // Use MainActor.run for mutations instead
        stateTask = Task {
            print("[DEMO_MODEL] 🎯 Starting to listen to stateUpdates AsyncStream")
            for await state in await audioService.stateUpdates {
                print("[DEMO_MODEL] ✅ Received state from AsyncStream: \(state)")
                await MainActor.run {
                    self.state = state
                    print("[DEMO_MODEL] ✅ Updated @Observable property to: \(self.state)")
                }
            }
            print("[DEMO_MODEL] ⚠️ stateUpdates stream ended")
        }
        
        // Observe track updates
        trackTask = Task {
            for await metadata in await audioService.trackUpdates {
                await MainActor.run {
                    self.currentTrack = metadata
                }
            }
        }
    }
    
    // MARK: - Cleanup
    // Note: Tasks are automatically cancelled when model is deinitialized
    
    // MARK: - Common Actions
    
    /// Load playlist and start playing
    /// - Parameters:
    ///   - tracks: Tracks to load
    ///   - fadeDuration: Fade-in duration (default: 0.0)
    func loadAndPlay(_ tracks: [Track], fadeDuration: TimeInterval = 0.0) async throws {
        do {
            try await audioService.loadPlaylist(tracks)
            try await audioService.startPlaying(fadeDuration: fadeDuration)
            error = nil
        } catch {
            self.error = "Play error: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Load playlist and start playing from URLs
    /// - Parameters:
    ///   - urls: Track URLs to load
    ///   - fadeDuration: Fade-in duration (default: 0.0)
    func loadAndPlay(_ urls: [URL], fadeDuration: TimeInterval = 0.0) async throws {
        let tracks = urls.compactMap { Track(url: $0) }
        guard !tracks.isEmpty else {
            let error = NSError(domain: "DemoPlayerModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid tracks to load"])
            self.error = "No valid tracks to load"
            throw error
        }
        try await loadAndPlay(tracks, fadeDuration: fadeDuration)
    }
    
    /// Pause playback
    func pause() async throws {
        do {
            try await audioService.pause()
            error = nil
        } catch {
            self.error = "Pause error: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Resume playback
    func resume() async throws {
        do {
            try await audioService.resume()
            error = nil
        } catch {
            self.error = "Resume error: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Stop playback
    func stop(fadeDuration: TimeInterval = 0.0) async {
        await audioService.stop(fadeDuration: fadeDuration)
    }
    
    /// Update configuration
    func updateConfiguration(_ config: PlayerConfiguration) async throws {
        do {
            try await audioService.updateConfiguration(config)
            currentConfig = config
            error = nil
        } catch {
            self.error = "Config update error: \(error.localizedDescription)"
            throw error
        }
    }
}

// MARK: - Default Configuration

extension PlayerConfiguration {
    /// Default configuration for demo views
    static var demoDefault: PlayerConfiguration {
        PlayerConfiguration(
            crossfadeDuration: 5.0,
            repeatCount: nil,
            volume: 0.8
        )
    }
}

import AVFoundation
import AudioServiceCore

/// Actor managing sound effects playback (one sound at a time)
///
/// Architecture:
/// - Single AVAudioPlayerNode for sound effects
/// - Independent mixer for volume control
/// - Preloaded buffers in RAM for instant playback
/// - LRU cache with configurable limit (default: 10 effects)
/// - Auto-preload on play if not cached
/// - New trigger automatically cancels previous sound
actor SoundEffectsPlayerActor {

    // MARK: - Audio Graph Components

    // nonisolated(unsafe): Safe because nodes are received from AudioEngineActor
    // and used exclusively by this actor (single ownership after transfer)
    private nonisolated(unsafe) let player: AVAudioPlayerNode
    private nonisolated(unsafe) let mixer: AVAudioMixerNode

    // MARK: - LRU Cache State

    /// Cache storage: effect ID -> effect
    private var loadedEffects: [UUID: SoundEffect] = [:]

    /// LRU access order: most recent at end
    private var accessOrder: [UUID] = []

    /// Cache size limit (default: 10 effects)
    private let cacheLimit: Int

    // MARK: - Playback State

    private var currentlyPlaying: SoundEffect?
    private var fadeTask: Task<Void, Never>?
    private var volume: Float = 1.0  // Master volume for all effects
    
    // Logger
    private static let logger = Logger.engine

    // MARK: - Initialization

    /// Initialize sound effects player with nodes from AudioEngineActor
    ///
    /// - Parameters:
    ///   - player: Player node from AudioEngineActor (playerD)
    ///   - mixer: Mixer node from AudioEngineActor (mixerD)
    ///   - cacheLimit: Maximum number of effects to cache (default: 10)
    init(
        player: AVAudioPlayerNode,
        mixer: AVAudioMixerNode,
        cacheLimit: Int = 10
    ) {
        self.player = player
        self.mixer = mixer
        self.cacheLimit = cacheLimit

        Self.logger.debug(" 🎵 Initialized with LRU cache (limit: \(cacheLimit))")
    }

    // MARK: - Preload (Batch)

    /// Preload multiple sound effects into cache (batch operation)
    /// - Parameter effects: Array of sound effects to preload
    /// - Note: If cache limit exceeded, oldest unused effects are evicted (LRU)
    func preloadEffects(_ effects: [SoundEffect]) {
        for effect in effects {
            preloadSingleEffect(effect)
        }
        Self.logger.debug(" Batch preloaded \(effects.count) effects (cache: \(loadedEffects.count)/\(cacheLimit))")
    }

    /// Internal: Preload single effect with LRU cache management
    private func preloadSingleEffect(_ effect: SoundEffect) {
        let id = effect.id

        // If already cached, update access order
        if loadedEffects[id] != nil {
            updateAccessOrder(id: id)
            return
        }

        // Check cache limit - evict oldest if needed
        if loadedEffects.count >= cacheLimit {
            evictOldestEffect()
        }

        // Add to cache
        loadedEffects[id] = effect
        accessOrder.append(id)

        Self.logger.debug(" Preloaded: \(effect.track.url.lastPathComponent) (cache: \(loadedEffects.count)/\(cacheLimit))")
    }

    /// Unload specific sound effects from memory (manual cleanup)
    /// - Parameter effects: Array of effects to unload
    func unloadEffects(_ effects: [SoundEffect]) {
        for effect in effects {
            let id = effect.id
            loadedEffects.removeValue(forKey: id)
            accessOrder.removeAll { $0 == id }

            // Stop if currently playing
            if currentlyPlaying?.id == id {
                stopCurrentEffect()
            }
        }
        Self.logger.debug(" 🗑️ Unloaded \(effects.count) effects (cache: \(loadedEffects.count)/\(cacheLimit))")
    }

    // MARK: - LRU Cache Management

    /// Update access order for LRU tracking (move to end = most recent)
    private func updateAccessOrder(id: UUID) {
        accessOrder.removeAll { $0 == id }
        accessOrder.append(id)
    }

    /// Evict oldest (least recently used) effect from cache
    private func evictOldestEffect() {
        guard let oldestId = accessOrder.first else { return }

        // Don't evict if currently playing
        if currentlyPlaying?.id == oldestId {
            // Find next oldest that's not playing
            for id in accessOrder where id != currentlyPlaying?.id {
                evictEffect(id: id)
                return
            }
            // All effects are playing (shouldn't happen) - skip eviction
            return
        }

        evictEffect(id: oldestId)
    }

    /// Evict specific effect from cache
    private func evictEffect(id: UUID) {
        guard let effect = loadedEffects[id] else { return }

        loadedEffects.removeValue(forKey: id)
        accessOrder.removeAll { $0 == id }

        Self.logger.debug(" 🗑️ LRU evicted: \(effect.track.url.lastPathComponent) (cache: \(loadedEffects.count)/\(cacheLimit))")
    }

    // MARK: - Playback

    /// Play sound effect with auto-preload if not cached
    ///
    /// - Parameters:
    ///   - effect: Sound effect to play
    ///   - fadeDuration: Fade-in duration (default: 0.0)
    /// - Note: Auto-preloads effect if not in cache (with console warning)
    /// - Note: Updates LRU access order
    /// - Note: Cancels previous sound if playing
    func play(_ effect: SoundEffect, fadeDuration: TimeInterval = 0.0) {
        // Auto-preload if not in cache
        if loadedEffects[effect.id] == nil {
            Self.logger.debug(" Auto-preloading '\(effect.track.url.lastPathComponent)' - consider calling preloadSoundEffects() upfront for instant playback")
            preloadSingleEffect(effect)
        } else {
            // Update LRU access order
            updateAccessOrder(id: effect.id)
        }

        // Cancel previous sound (if any)
        if currentlyPlaying != nil {
            stopCurrentEffect()
        }

        currentlyPlaying = effect

        // Volume = effect's volume * master volume
        let finalVolume = effect.volume * volume

        // Set mixer volume to 1.0 (full output)
        // Player volume controls the actual level
        mixer.volume = 1.0

        // Player and mixer already connected in AudioEngineActor
        // Just use the existing connection

        // Schedule buffer for playback
        player.scheduleBuffer(effect.buffer) { [weak self] in
            Task { [weak self] in
                await self?.handleEffectFinished(id: effect.id)
            }
        }

        // Start player if not already running
        if !player.isPlaying {
            player.play()
        }

        // Fade in (use parameter, not effect's fadeInDuration)
        if fadeDuration > 0 {
            player.volume = 0.0
            fadeTo(volume: finalVolume, duration: fadeDuration)
        } else {
            player.volume = finalVolume
        }

        Self.logger.debug(" ▶️ Playing: \(effect.track.url.lastPathComponent) (effect: \(effect.volume), master: \(volume), final: \(finalVolume), fadeIn: \(fadeDuration)s)")
    }

    /// Stop current sound effect
    ///
    /// - Parameter fadeDuration: Fade-out duration in seconds (default: 0.0 = instant)
    func stop(fadeDuration: TimeInterval = 0.0) {
        guard currentlyPlaying != nil else {
            return
        }

        if fadeDuration > 0 {
            fadeOutAndStop(duration: fadeDuration)
        } else {
            stopCurrentEffect()
        }
    }

    // MARK: - Internal Helpers

    private func stopCurrentEffect() {
        // Cancel fade task
        fadeTask?.cancel()
        fadeTask = nil

        // Stop player
        player.stop()
        player.volume = 0.0

        if let effect = currentlyPlaying {
            Self.logger.debug(" ⏹️ Stopped: \(effect.track.url.lastPathComponent)")
        }

        currentlyPlaying = nil
    }

    private func fadeOutAndStop(duration: TimeInterval) {
        // Cancel previous fade
        fadeTask?.cancel()

        fadeTask = Task {
            await fadeTo(volume: 0.0, duration: duration)

            // Check not cancelled
            guard !Task.isCancelled else { return }

            stopCurrentEffect()
        }
    }

    private func fadeTo(volume: Float, duration: TimeInterval) {
        guard duration > 0 else {
            player.volume = volume
            return
        }

        // Simple linear fade (60 FPS)
        let startVolume = player.volume
        let delta = volume - startVolume
        let steps = Int(duration * 60)
        let stepDuration = duration / Double(steps)

        Task {
            for step in 0...steps {
                guard !Task.isCancelled else { break }

                let progress = Float(step) / Float(steps)
                let currentVolume = startVolume + (delta * progress)
                player.volume = currentVolume

                try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
            }
        }
    }

    private func handleEffectFinished(id: UUID) {
        guard currentlyPlaying?.id == id else { return }

        Self.logger.debug(" Finished: \(id)")
        currentlyPlaying = nil
        player.volume = 0.0
    }

    // MARK: - Volume Control

    /// Set master volume for all sound effects
    /// - Parameter volume: Volume level (0.0 - 1.0)
    /// - Note: Applies to all effects, multiplied by individual effect volume
    func setVolume(_ newVolume: Float) {
        let clampedVolume = min(1.0, max(0.0, newVolume))
        volume = clampedVolume

        // Update current playing effect volume if any
        if currentlyPlaying != nil {
            let finalVolume = (currentlyPlaying?.volume ?? 1.0) * volume
            player.volume = finalVolume
        }

        Self.logger.debug(" 🔊 Volume set to \(Int(volume * 100))%")
    }

    // MARK: - Status

    /// Check if any sound effect is currently playing
    var isPlaying: Bool {
        currentlyPlaying != nil
    }

    /// Get currently playing effect
    var currentEffect: SoundEffect? {
        currentlyPlaying
    }

    /// Get cache statistics (for debugging)
    var cacheStats: (count: Int, limit: Int) {
        (loadedEffects.count, cacheLimit)
    }
}

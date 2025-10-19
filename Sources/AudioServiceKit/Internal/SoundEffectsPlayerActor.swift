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

    // nonisolated(unsafe): Safe because these are immutable after init
    // and AVAudioEngine/nodes are thread-safe for basic operations
    // SoundEffectsPlayer uses its own AVAudioEngine for complete independence
    private nonisolated(unsafe) let audioEngine: AVAudioEngine
    private nonisolated(unsafe) let playerNode: AVAudioPlayerNode
    private nonisolated(unsafe) let mixerNode: AVAudioMixerNode

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

    // MARK: - Initialization

    init(cacheLimit: Int = 10) {
        self.cacheLimit = cacheLimit
        
        // Create own AVAudioEngine for complete independence from main player
        self.audioEngine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        self.mixerNode = AVAudioMixerNode()

        // Setup audio graph inline (can't be separate function due to actor isolation)
        audioEngine.attach(playerNode)
        audioEngine.attach(mixerNode)
        audioEngine.connect(playerNode, to: mixerNode, format: nil)
        audioEngine.connect(mixerNode, to: audioEngine.mainMixerNode, format: nil)
        
        // Start engine
        do {
            try audioEngine.start()
        } catch {
            print("[SoundEffects] ⚠️ Failed to start audio engine: \(error)")
        }
        
        print("[SoundEffects] 🎵 Initialized with LRU cache (limit: \(cacheLimit))")
    }

    // MARK: - Preload (Batch)

    /// Preload multiple sound effects into cache (batch operation)
    /// - Parameter effects: Array of sound effects to preload
    /// - Note: If cache limit exceeded, oldest unused effects are evicted (LRU)
    func preloadEffects(_ effects: [SoundEffect]) {
        for effect in effects {
            preloadSingleEffect(effect)
        }
        print("[SoundEffects] ✅ Batch preloaded \(effects.count) effects (cache: \(loadedEffects.count)/\(cacheLimit))")
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
        
        print("[SoundEffects] ✅ Preloaded: \(effect.track.url.lastPathComponent) (cache: \(loadedEffects.count)/\(cacheLimit))")
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
        print("[SoundEffects] 🗑️ Unloaded \(effects.count) effects (cache: \(loadedEffects.count)/\(cacheLimit))")
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
        
        print("[SoundEffects] 🗑️ LRU evicted: \(effect.track.url.lastPathComponent) (cache: \(loadedEffects.count)/\(cacheLimit))")
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
            print("[SoundEffects] ⚠️ Auto-preloading '\(effect.track.url.lastPathComponent)' - consider calling preloadSoundEffects() upfront for instant playback")
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

        // Connect player with buffer's format
        let format = effect.buffer.format
        audioEngine.connect(playerNode, to: mixerNode, format: format)

        // Schedule buffer for playback
        playerNode.scheduleBuffer(effect.buffer) { [weak self] in
            Task { [weak self] in
                await self?.handleEffectFinished(id: effect.id)
            }
        }

        // Start player if not already running
        if !playerNode.isPlaying {
            playerNode.play()
        }

        // Fade in (use parameter, not effect's fadeInDuration)
        if fadeDuration > 0 {
            playerNode.volume = 0.0
            fadeTo(volume: finalVolume, duration: fadeDuration)
        } else {
            playerNode.volume = finalVolume
        }

        print("[SoundEffects] ▶️ Playing: \(effect.track.url.lastPathComponent) (effect: \(effect.volume), master: \(volume), final: \(finalVolume), fadeIn: \(fadeDuration)s)")
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
        playerNode.stop()
        playerNode.volume = 0.0

        if let effect = currentlyPlaying {
            print("[SoundEffects] ⏹️ Stopped: \(effect.track.url.lastPathComponent)")
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
            playerNode.volume = volume
            return
        }

        // Simple linear fade (60 FPS)
        let startVolume = playerNode.volume
        let delta = volume - startVolume
        let steps = Int(duration * 60)
        let stepDuration = duration / Double(steps)

        Task {
            for step in 0...steps {
                guard !Task.isCancelled else { break }

                let progress = Float(step) / Float(steps)
                let currentVolume = startVolume + (delta * progress)
                playerNode.volume = currentVolume

                try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
            }
        }
    }

    private func handleEffectFinished(id: UUID) {
        guard currentlyPlaying?.id == id else { return }

        print("[SoundEffects] ✅ Finished: \(id)")
        currentlyPlaying = nil
        playerNode.volume = 0.0
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
            playerNode.volume = finalVolume
        }
        
        print("[SoundEffects] 🔊 Volume set to \(Int(volume * 100))%")
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

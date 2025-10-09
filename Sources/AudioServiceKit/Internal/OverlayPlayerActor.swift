//
//  OverlayPlayerActor.swift
//  AudioServiceKit
//
//  Created on 2025-10-09.
//  Feature #4: Overlay Player - Phase 2
//

import AVFoundation
import AudioServiceCore

/// Actor-isolated overlay audio player with independent lifecycle and looping support.
///
/// `OverlayPlayerActor` manages a dedicated audio playback chain (player + mixer) that operates
/// independently from the main crossfade system. Perfect for ambient sounds, timer bells, or effects.
///
/// ## Features:
/// - Independent volume control
/// - Configurable looping (once, N times, infinite)
/// - Loop delay support (pause between iterations)
/// - Per-iteration fade control
/// - Hot file swapping with crossfade
/// - State-based lifecycle management
///
/// ## Architecture:
/// ```
/// OverlayPlayerActor
///     ├─ AVAudioPlayerNode (schedules buffers)
///     └─ AVAudioMixerNode (independent volume)
/// ```
///
/// ## Example: Infinite Rain Loop
/// ```swift
/// let overlay = OverlayPlayerActor(
///     player: playerNode,
///     mixer: mixerNode,
///     configuration: .ambient
/// )
///
/// try await overlay.load(url: rainURL)
/// try await overlay.play()
/// // Plays continuously with smooth fades
/// ```
///
/// - SeeAlso: `OverlayConfiguration`, `OverlayState`
actor OverlayPlayerActor {
  
  // MARK: - Audio Nodes
  
  /// Player node owned by this actor
  private let player: AVAudioPlayerNode
  
  /// Mixer node for independent volume control
  private let mixer: AVAudioMixerNode
  
  // MARK: - State
  
  /// Current playback state
  private var state: OverlayState = .idle
  
  /// Loaded audio file
  private var audioFile: AVAudioFile?
  
  /// Current configuration
  private var configuration: OverlayConfiguration
  
  /// Current loop iteration count (0-based)
  private var loopCount: Int = 0
  
  /// Active loop cycle task
  private var loopTask: Task<Void, Never>?
  
  /// Continuation for buffer completion synchronization
  private var completionContinuation: CheckedContinuation<Void, Never>?
  
  // MARK: - Initialization
  
  /// Creates a new overlay player actor.
  ///
  /// - Parameters:
  ///   - player: AVAudioPlayerNode for buffer scheduling
  ///   - mixer: AVAudioMixerNode for volume control
  ///   - configuration: Playback configuration
  ///
  /// - Precondition: Configuration must be valid (`configuration.isValid == true`)
  init(
    player: AVAudioPlayerNode,
    mixer: AVAudioMixerNode,
    configuration: OverlayConfiguration
  ) {
    self.player = player
    self.mixer = mixer
    self.configuration = configuration
    
    // Validate configuration
    precondition(configuration.isValid, "Invalid OverlayConfiguration")
    
    // Set initial volume
    mixer.volume = 0.0
  }
  
  // MARK: - Public API
  
  /// Load audio file for overlay playback.
  ///
  /// ## State Transition:
  /// `idle` → `preparing` → `idle` (ready)
  ///
  /// - Parameter url: Local file URL for audio file
  /// - Throws:
  ///   - `AudioPlayerError.invalidState` if not in idle state
  ///   - `AudioPlayerError.fileLoadError` if file cannot be loaded
  func load(url: URL) async throws {
    guard state == .idle else {
      throw AudioPlayerError.invalidState(
        current: state.description,
        attempted: "load"
      )
    }
    
    state = .preparing
    
    do {
      let file = try AVAudioFile(forReading: url)
      audioFile = file
      state = .idle  // Ready to play
    } catch {
      state = .idle
      throw AudioPlayerError.fileLoadError(url)
    }
  }
  
  /// Start overlay playback with configured loop cycle.
  ///
  /// ## State Transition:
  /// `idle` → `playing`
  ///
  /// ## Behavior:
  /// - Starts loop cycle based on `configuration.loopMode`
  /// - Applies fades according to `configuration.applyFadeOnEachLoop`
  /// - Respects `configuration.loopDelay` between iterations
  ///
  /// - Throws:
  ///   - `AudioPlayerError.invalidState` if not in idle state
  ///   - `AudioPlayerError.invalidState` if no file loaded
  func play() async throws {
    guard state == .idle else {
      throw AudioPlayerError.invalidState(
        current: state.description,
        attempted: "play"
      )
    }
    
    guard audioFile != nil else {
      throw AudioPlayerError.invalidState(
        current: "no file loaded",
        attempted: "play"
      )
    }
    
    state = .playing
    loopCount = 0
    
    // Start loop cycle
    loopTask = Task {
      await self.loopCycle()
    }
  }
  
  /// Stop overlay playback with graceful fade-out.
  ///
  /// ## State Transition:
  /// `playing`/`paused` → `stopping` → `idle`
  ///
  /// ## Behavior:
  /// - Cancels active loop cycle (including delay)
  /// - Applies `configuration.fadeOutDuration` if configured
  /// - Adds micro-fade to prevent audio clicks
  /// - Cleans up player and mixer state
  func stop() async {
    // Cancel loop task
    loopTask?.cancel()
    loopTask = nil
    
    // Fade out if configured and volume > 0
    if configuration.fadeOutDuration > 0 && mixer.volume > 0 {
      state = .stopping
      await fadeVolume(
        from: mixer.volume,
        to: 0.0,
        duration: configuration.fadeOutDuration
      )
    }
    
    // Micro-fade to prevent clicks
    if mixer.volume > 0.01 {
      await fadeVolume(
        from: mixer.volume,
        to: 0.0,
        duration: 0.02,
        curve: .linear
      )
    }
    
    // Small delay for fade completion
    try? await Task.sleep(nanoseconds: 25_000_000)  // 25ms
    
    // Stop and cleanup
    player.stop()
    player.reset()
    mixer.volume = 0.0
    state = .idle
  }
  
  /// Pause overlay playback.
  ///
  /// ## State Transition:
  /// `playing` → `paused`
  ///
  /// ## Behavior:
  /// - Pauses player node immediately
  /// - Loop cycle continues in background
  /// - Call `resume()` to continue playback
  func pause() {
    guard state == .playing else { return }
    
    player.pause()
    state = .paused
  }
  
  /// Resume overlay playback from paused state.
  ///
  /// ## State Transition:
  /// `paused` → `playing`
  ///
  /// ## Behavior:
  /// - Resumes player node immediately
  /// - Loop cycle continues from where it was paused
  func resume() {
    guard state == .paused else { return }
    
    player.play()
    state = .playing
  }
  
  /// Replace current overlay file with crossfade transition.
  ///
  /// ## Behavior:
  /// - Cancels active loop cycle (including delay)
  /// - Fades out current file (1 second)
  /// - Loads new file
  /// - Starts playback with fade in
  ///
  /// ## Example:
  /// ```swift
  /// // Replace rain with ocean during playback
  /// try await overlay.replaceFile(url: oceanURL)
  /// // Smooth crossfade, no interruption
  /// ```
  ///
  /// - Parameter url: New audio file URL
  /// - Throws: `AudioPlayerError.fileLoadError` if file cannot be loaded
  func replaceFile(url: URL) async throws {
    // Cancel loop task (including delay)
    loopTask?.cancel()
    loopTask = nil
    
    // Fade out current (1 second fixed)
    if mixer.volume > 0 {
      await fadeVolume(from: mixer.volume, to: 0.0, duration: 1.0)
    }
    
    // Stop player
    player.stop()
    player.reset()
    
    // Load new file
    state = .preparing
    do {
      let file = try AVAudioFile(forReading: url)
      audioFile = file
      state = .idle
    } catch {
      state = .idle
      throw AudioPlayerError.fileLoadError(url)
    }
    
    // Start playback
    try await play()
  }
  
  /// Set overlay volume independently from main player.
  ///
  /// ## Behavior:
  /// - Updates `configuration.volume`
  /// - Applies immediately to mixer node
  /// - Clamped to range `0.0...1.0`
  ///
  /// - Parameter volume: Target volume level (0.0 = silent, 1.0 = full)
  func setVolume(_ volume: Float) {
    let clamped = max(0.0, min(1.0, volume))
    configuration.volume = clamped
    mixer.volume = clamped
  }
  
  /// Get current playback state.
  ///
  /// - Returns: Current `OverlayState`
  func getState() -> OverlayState {
    return state
  }
  
  // MARK: - Loop Cycle
  
  /// Main loop cycle - handles iterations with delays and fades.
  ///
  /// ## Algorithm:
  /// ```
  /// while shouldContinue:
  ///   1. Fade in (if configured)
  ///   2. Schedule buffer
  ///   3. Wait for completion
  ///   4. Fade out (if configured)
  ///   5. Increment counter
  ///   6. Check if should continue
  ///   7. Apply delay (cancellable)
  /// ```
  private func loopCycle() async {
    while shouldContinueLooping() {
      // Check cancellation before each iteration
      guard !Task.isCancelled else { break }
      
      // 1. Fade in (if configured)
      let shouldFadeIn = configuration.applyFadeOnEachLoop || loopCount == 0
      if shouldFadeIn && configuration.fadeInDuration > 0 {
        await fadeVolume(
          from: 0.0,
          to: configuration.volume,
          duration: configuration.fadeInDuration
        )
      } else if loopCount == 0 {
        // First iteration without fade - set volume directly
        mixer.volume = configuration.volume
      }
      
      guard !Task.isCancelled else { break }
      
      // 2. Schedule and play buffer
      scheduleBuffer()
      player.play()
      
      // 3. Wait for playback to finish
      await waitForPlaybackEnd()
      
      guard !Task.isCancelled else { break }
      
      // 4. Fade out (if configured)
      let isLastIteration = isLastLoop()
      let shouldFadeOut = configuration.applyFadeOnEachLoop || isLastIteration
      if shouldFadeOut && configuration.fadeOutDuration > 0 {
        await fadeVolume(
          from: configuration.volume,
          to: 0.0,
          duration: configuration.fadeOutDuration
        )
      }
      
      // 5. Increment loop counter
      loopCount += 1
      
      // 6. Check if should continue
      if !shouldContinueLooping() {
        break
      }
      
      // 7. Apply loop delay (cancellable)
      if configuration.loopDelay > 0 {
        guard !Task.isCancelled else { break }
        try? await Task.sleep(nanoseconds: UInt64(configuration.loopDelay * 1_000_000_000))
        guard !Task.isCancelled else { break }
      }
    }
    
    // Loop cycle completed
    await stop()
  }
  
  /// Check if should continue looping based on mode.
  private func shouldContinueLooping() -> Bool {
    switch configuration.loopMode {
    case .once:
      return loopCount < 1
    case .count(let times):
      return loopCount < times
    case .infinite:
      return true
    }
  }
  
  /// Check if current iteration is the last one.
  private func isLastLoop() -> Bool {
    switch configuration.loopMode {
    case .once:
      return loopCount == 0
    case .count(let times):
      return loopCount == times - 1
    case .infinite:
      return false
    }
  }
  
  // MARK: - Volume Fade
  
  /// Fade mixer volume with adaptive step sizing.
  ///
  /// ## Algorithm:
  /// Uses adaptive step frequency based on duration for optimal smoothness vs CPU usage:
  /// - `< 1.0s`: 100 steps/sec (10ms) - ultra smooth for quick fades
  /// - `< 5.0s`: 50 steps/sec (20ms) - smooth
  /// - `< 15.0s`: 30 steps/sec (33ms) - balanced
  /// - `>= 15.0s`: 20 steps/sec (50ms) - efficient for long fades
  ///
  /// - Parameters:
  ///   - from: Starting volume (0.0...1.0)
  ///   - to: Target volume (0.0...1.0)
  ///   - duration: Fade duration in seconds
  ///   - curve: Fade curve algorithm (default: uses `configuration.fadeCurve`)
  private func fadeVolume(
    from: Float,
    to: Float,
    duration: TimeInterval,
    curve: FadeCurve? = nil
  ) async {
    // Use config curve if not specified
    let fadeCurve = curve ?? configuration.fadeCurve
    
    // Adaptive step sizing (copied from AudioEngineActor)
    let stepsPerSecond: Int
    if duration < 1.0 {
      stepsPerSecond = 100  // 10ms
    } else if duration < 5.0 {
      stepsPerSecond = 50   // 20ms
    } else if duration < 15.0 {
      stepsPerSecond = 30   // 33ms
    } else {
      stepsPerSecond = 20   // 50ms
    }
    
    let steps = Int(duration * Double(stepsPerSecond))
    let stepTime = duration / Double(steps)
    
    for i in 0...steps {
      // Check cancellation
      guard !Task.isCancelled else { return }
      
      let progress = Float(i) / Float(steps)
      
      // Calculate volume based on curve
      let curveValue: Float
      if from < to {
        // Fading in (0 -> 1)
        curveValue = fadeCurve.volume(for: progress)
      } else {
        // Fading out (1 -> 0)
        curveValue = fadeCurve.inverseVolume(for: progress)
      }
      
      // Apply curve to range [from, to]
      let newVolume = from + (to - from) * curveValue
      mixer.volume = newVolume
      
      try? await Task.sleep(nanoseconds: UInt64(stepTime * 1_000_000_000))
    }
    
    // Ensure final volume (if not cancelled)
    if !Task.isCancelled {
      mixer.volume = to
    }
  }
  
  // MARK: - Buffer Scheduling
  
  /// Schedule audio buffer for playback.
  ///
  /// ## Behavior:
  /// - Schedules entire file at once (no progressive loading)
  /// - Sets up completion callback to signal `waitForPlaybackEnd()`
  /// - Callback executes on audio thread - uses Task to hop back to actor
  private func scheduleBuffer() {
    guard let file = audioFile else { return }
    
    // Schedule entire file
    player.scheduleFile(file, at: nil) { [weak self] in
      // Completion on audio thread - signal continuation
      guard let self = self else { return }
      Task {
        await self.signalPlaybackEnd()
      }
    }
  }
  
  /// Wait for buffer playback to complete.
  ///
  /// ## Implementation:
  /// Uses `CheckedContinuation` to suspend until audio callback signals completion.
  /// This pattern allows synchronous-style code in async context.
  private func waitForPlaybackEnd() async {
    await withCheckedContinuation { continuation in
      completionContinuation = continuation
    }
  }
  
  /// Signal that playback completed (called from audio callback).
  ///
  /// ## Thread Safety:
  /// Called via Task from audio thread callback, ensuring actor isolation.
  private func signalPlaybackEnd() {
    completionContinuation?.resume()
    completionContinuation = nil
  }
}

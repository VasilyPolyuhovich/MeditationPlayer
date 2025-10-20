import AVFoundation
import AudioServiceCore

/// Singleton actor managing global AVAudioSession configuration and lifecycle.
///
/// **Design Rationale**:
/// - AVAudioSession is a **GLOBAL system resource** (one per process)
/// - Multiple AudioPlayerService instances must share the same session
/// - Singleton pattern prevents configuration conflicts and error -50
///
/// **Usage**:
/// ```swift
/// // Automatically used by AudioPlayerService instances
/// let player1 = AudioPlayerService()
/// let player2 = AudioPlayerService()
/// // Both use AudioSessionManager.shared internally
/// ```
actor AudioSessionManager {
    // MARK: - Singleton
    
    /// Shared instance - AVAudioSession is global, so manager must be too
    static let shared = AudioSessionManager()
    
    // MARK: - Properties
    
    private let session: AVAudioSession
    
    // Configuration state
    private var isConfigured = false
    private var configuredOptions: AVAudioSession.CategoryOptions?
    
    // Activation state
    private var isActive = false
    private var isActivating = false  // Reentrancy guard for activate()
    
    // Notification observers setup flag
    private var observersSetup = false
    
    // Callbacks for handling session events
    private var interruptionHandler: (@Sendable (Bool) -> Void)?
    private var routeChangeHandler: (@Sendable (AVAudioSession.RouteChangeReason) -> Void)?
    private var mediaServicesResetHandler: (@Sendable () -> Void)?
    
    // MARK: - Initialization
    
    private init() {
        self.session = AVAudioSession.sharedInstance()
        
        // Setup observers in a detached task (init is nonisolated)
        Task { [weak self] in
            await self?.setupNotificationObserversOnce()
        }
    }
    
    // MARK: - Configuration
    
    /// Configure AVAudioSession with specified options.
    /// - Parameters:
    ///   - options: Category options for audio session
    ///   - force: Force reconfiguration even if already configured (for media services reset)
    /// - Throws: AudioPlayerError if configuration fails
    ///
    /// **Important**: Can only be called once. Subsequent calls with different options will log a warning.
    func configure(options: [AVAudioSession.CategoryOptions], force: Bool = false) throws {
        // Combine array into single OptionSet
        let categoryOptions = options.reduce(into: AVAudioSession.CategoryOptions()) { result, option in
            result.formUnion(option)
        }
        
        // Already configured - check for conflicts (unless force)
        guard !isConfigured || force else {
            if let existingOptions = configuredOptions, existingOptions != categoryOptions {
                print("[AudioSession] ⚠️ WARNING: Attempting to reconfigure with different options!")
                print("[AudioSession] Existing: \(existingOptions.rawValue), New: \(categoryOptions.rawValue)")
                print("[AudioSession] Using existing configuration (first wins)")
            } else {
                print("[AudioSession] ⏭️ Already configured, skipping")
            }
            return
        }
        
        // CRITICAL: Set flag IMMEDIATELY after guard to prevent race condition
        // If we set it after setCategory(), two concurrent calls could both pass guard
        // and both try to configure AVAudioSession → Error -50
        isConfigured = true
        configuredOptions = categoryOptions
        
        do {
            // MARK: Advanced Configuration for Maximum Stability
            // NOTE: Apple docs say setCategory() CAN be called on active session
            // DO NOT deactivate before configure - it can interfere with other audio
            
            // 1. Set preferred buffer duration (larger = more stable, higher latency)
            // 0.02s (20ms) provides excellent stability while keeping latency acceptable
            // For meditation/ambient apps, latency is less critical than stability
            let preferredBufferDuration: TimeInterval = 0.02
            try session.setPreferredIOBufferDuration(preferredBufferDuration)
            
            // 2. Set preferred sample rate to avoid resampling
            // 44100 Hz is standard for most audio files
            let preferredSampleRate: Double = 44100.0
            try session.setPreferredSampleRate(preferredSampleRate)
            
            // 3. Minimize interruptions from system alerts (iOS 14.5+)
            if #available(iOS 14.5, *) {
                try session.setPrefersNoInterruptionsFromSystemAlerts(true)
            }
            
            // 4. Set category to playback for background audio
            // Options passed from PlayerConfiguration.audioSessionOptions
            // Default: Peaceful coexistence (.mixWithOthers + .duckOthers + Bluetooth + AirPlay)
            // Custom: User can override (triggers warning in PlayerConfiguration.init)
            


            try session.setCategory(
                .playback,
                mode: .default,
                options: categoryOptions
            )
            
            // 5. Validate actual vs preferred settings
            let actualBufferDuration = session.ioBufferDuration
            let actualSampleRate = session.sampleRate
            
            print("[AudioSession] Configuration:")
            print("  Preferred buffer: \(preferredBufferDuration)s")
            print("  Actual buffer: \(actualBufferDuration)s")
            print("  Preferred sample rate: \(preferredSampleRate) Hz")
            print("  Actual sample rate: \(actualSampleRate) Hz")
            
            if abs(actualBufferDuration - preferredBufferDuration) > 0.005 {
                print("  ⚠️ WARNING: Buffer duration mismatch (difference > 5ms)")
            }
            
            if abs(actualSampleRate - preferredSampleRate) > 100 {
                print("  ⚠️ WARNING: Sample rate mismatch (difference > 100 Hz)")
            }
            
            print("[AudioSession] ✅ Configured successfully")
        } catch {
            // Configuration failed - rollback flag
            isConfigured = false
            configuredOptions = nil
            throw AudioPlayerError.sessionConfigurationFailed(
                reason: "Failed to configure audio session: \(error.localizedDescription)"
            )
        }
    }
    
    func activate() throws {
        guard isConfigured else {
            throw AudioPlayerError.sessionConfigurationFailed(
                reason: "Session must be configured before activation"
            )
        }
        
        // Already active - skip
        guard !isActive else { return }
        
        // Reentrancy guard - prevent concurrent activation attempts
        // Critical for multithreading safety with rapid route changes
        guard !isActivating else {
            print("[AudioSession] ⚠️ WARNING: Concurrent activate() blocked - already activating")
            return
        }
        
        isActivating = true
        defer { isActivating = false }
        
        do {
            try session.setActive(true)
            isActive = true
            print("[AudioSession] ✅ Session activated successfully")
        } catch {
            throw AudioPlayerError.sessionConfigurationFailed(
                reason: "Failed to activate audio session: \(error.localizedDescription)"
            )
        }
    }
    
    /// ⚠️ DEPRECATED - DO NOT USE!
    /// This method should NEVER be called in production code.
    /// Following Apple's AVAudioPlayer pattern: activate once, never deactivate.
    /// iOS manages session lifecycle automatically.
    /// 
    /// Deactivating a singleton session affects ALL AudioPlayerService instances.
    /// Only kept for potential emergency scenarios (not currently used).
    @available(*, deprecated, message: "Do not use - violates singleton pattern. Session should stay active.")
    func _internalDeactivateDeprecated() throws {
        guard isActive else { return }
        
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            isActive = false
        } catch {
            throw AudioPlayerError.sessionConfigurationFailed(
                reason: "Failed to deactivate audio session: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - Event Handlers
    
    func setInterruptionHandler(_ handler: @escaping @Sendable (Bool) -> Void) {
        self.interruptionHandler = handler
    }
    
    func setRouteChangeHandler(_ handler: @escaping @Sendable (AVAudioSession.RouteChangeReason) -> Void) {
        self.routeChangeHandler = handler
    }
    
    func setMediaServicesResetHandler(_ handler: @escaping @Sendable () -> Void) {
        self.mediaServicesResetHandler = handler
    }
    
    // MARK: - Notification Observers
    
    /// Setup notification observers once (called from init)
    private func setupNotificationObserversOnce() {
        guard !observersSetup else { return }
        observersSetup = true
        // Interruption notifications
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            // Extract data synchronously (Notification is not Sendable)
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }
            
            let shouldResume: Bool?
            if type == .ended,
               let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                shouldResume = options.contains(.shouldResume)
            } else {
                shouldResume = nil
            }
            
            // Now send Sendable data to actor
            Task {
                await self?.handleInterruption(type: type, shouldResume: shouldResume)
            }
        }
        
        // Route change notifications
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            // Extract data synchronously (Notification is not Sendable)
            guard let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
            }
            
            // Now send Sendable data to actor
            Task {
                await self?.handleRouteChange(reason: reason)
            }
        }
        
        // Media services reset notifications
        // This fires when audio services crash/restart (rare but critical)
        // Also fires when external AVAudioPlayer interferes with our AVAudioEngine
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleMediaServicesReset()
            }
        }
    }
    
    // MARK: - Interruption Handling
    
    private func handleInterruption(type: AVAudioSession.InterruptionType, shouldResume: Bool?) {
        switch type {
        case .began:
            // Interruption began (phone call, alarm, etc.)
            interruptionHandler?(false)
            
        case .ended:
            // Interruption ended
            if let shouldResume = shouldResume {
                interruptionHandler?(shouldResume)
            } else {
                // No resume option provided - don't auto-resume
                // This handles Siri pause case
                interruptionHandler?(false)
            }
            
        @unknown default:
            break
        }
    }
    
    // MARK: - Route Change Handling
    
    private func handleRouteChange(reason: AVAudioSession.RouteChangeReason) {
        routeChangeHandler?(reason)
    }
    
    // MARK: - Media Services Reset Handling
    
    private func handleMediaServicesReset() {
        print("[AudioSession] ⚠️ CRITICAL: Media services were reset!")
        print("[AudioSession] This may happen when:")
        print("[AudioSession]   - Audio services crash/restart")
        print("[AudioSession]   - External AVAudioPlayer interferes with our engine")
        print("[AudioSession]   - System audio reconfiguration")
        
        // Reset our internal state flags
        isActive = false
        isActivating = false
        
        // Notify the service to reconfigure and restart
        mediaServicesResetHandler?()
    }
    
    // MARK: - Current Route Info
    
    func getCurrentRoute() -> String {
        let route = session.currentRoute
        let outputs = route.outputs.map { $0.portType.rawValue }.joined(separator: ", ")
        return outputs.isEmpty ? "No output" : outputs
    }
    
    func isHeadphonesConnected() -> Bool {
        let route = session.currentRoute
        return route.outputs.contains { output in
            output.portType == .headphones || 
            output.portType == .bluetoothA2DP ||
            output.portType == .bluetoothHFP ||
            output.portType == .bluetoothLE
        }
    }
}

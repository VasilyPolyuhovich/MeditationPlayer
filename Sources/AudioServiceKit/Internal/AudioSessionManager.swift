import AVFoundation
import AudioServiceCore

/// Actor managing AVAudioSession configuration and lifecycle
actor AudioSessionManager {
    // MARK: - Properties
    
    private let session: AVAudioSession
    private var isConfigured = false
    private var isActive = false
    
    // Callbacks for handling session events
    private var interruptionHandler: (@Sendable (Bool) -> Void)?
    private var routeChangeHandler: (@Sendable (AVAudioSession.RouteChangeReason) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        self.session = AVAudioSession.sharedInstance()
    }
    
    // MARK: - Configuration
    
    func setup() {
        setupNotificationObservers()
    }
    
    func configure(mixWithOthers: Bool = false) throws {
        guard !isConfigured else { return }
        
        do {
            // Set category to playback for background audio
            // Add .mixWithOthers option if requested
            let options: AVAudioSession.CategoryOptions = mixWithOthers ? [.mixWithOthers] : []
            
            try session.setCategory(
                .playback,
                mode: .default,
                options: options
            )
            
            isConfigured = true
        } catch {
            throw AudioPlayerError.sessionConfigurationFailed(
                reason: "Failed to set audio session category: \(error.localizedDescription)"
            )
        }
    }
    
    func activate() throws {
        guard isConfigured else {
            throw AudioPlayerError.sessionConfigurationFailed(
                reason: "Session must be configured before activation"
            )
        }
        
        guard !isActive else { return }
        
        do {
            try session.setActive(true)
            isActive = true
        } catch {
            throw AudioPlayerError.sessionConfigurationFailed(
                reason: "Failed to activate audio session: \(error.localizedDescription)"
            )
        }
    }
    
    func deactivate() throws {
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
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
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

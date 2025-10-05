import Foundation
import AudioServiceCore

/// Actor-isolated state machine for audio player
actor AudioStateMachine {
    // MARK: - Properties
    
    private var currentStateBox: any AudioStateProtocol
    private weak var context: (any AudioStateMachineContext)?
    
    /// Current player state
    var currentState: PlayerState {
        currentStateBox.playerState
    }
    
    // MARK: - Initialization
    
    init(context: any AudioStateMachineContext) {
        self.context = context
        self.currentStateBox = FinishedState()
    }
    
    // MARK: - State Transitions
    
    /// Attempt to transition to a new state
    /// - Parameter newState: The state to transition to
    /// - Returns: True if transition was successful
    @discardableResult
    func enter(_ newState: any AudioStateProtocol) async -> Bool {
        // Check if transition is valid
        guard currentStateBox.isValidTransition(to: newState) else {
            return false
        }
        
        // Get context
        guard let context = context else {
            return false
        }
        
        let previousState = currentStateBox
        
        // 1. Exit hooks
        await previousState.willExit(to: newState, context: context)
        await previousState.onExit(context: context)
        
        // 2. State change (atomic)
        currentStateBox = newState
        
        // 3. Entry hooks
        await newState.didEnter(from: previousState, context: context)
        await newState.onEnter(context: context)
        
        return true
    }
    
    // MARK: - Convenience Methods
    
    func enterPreparing() async -> Bool {
        await enter(PreparingState())
    }
    
    func enterPlaying() async -> Bool {
        await enter(PlayingState())
    }
    
    func enterPaused() async -> Bool {
        await enter(PausedState())
    }
    
    func enterFadingOut(duration: TimeInterval = 6.0) async -> Bool {
        await enter(FadingOutState(fadeDuration: duration))
    }
    
    func enterFinished() async -> Bool {
        await enter(FinishedState())
    }
    
    func enterFailed(error: AudioPlayerError) async -> Bool {
        await enter(FailedState(error: error))
    }
    
    // MARK: - State Queries
    
    func canEnter(_ stateType: PlayerState) async -> Bool {
        // Create temporary state to check validity
        let tempState: any AudioStateProtocol
        
        switch stateType {
        case .preparing:
            tempState = PreparingState()
        case .playing:
            tempState = PlayingState()
        case .paused:
            tempState = PausedState()
        case .fadingOut:
            tempState = FadingOutState(fadeDuration: 6.0)
        case .finished:
            tempState = FinishedState()
        case .failed(let error):
            tempState = FailedState(error: error)
        }
        
        return currentStateBox.isValidTransition(to: tempState)
    }
    
    /// Update state machine (for compatibility, not needed in actor version)
    func update(deltaTime: TimeInterval) {
        // Not needed for actor-based implementation
    }
}

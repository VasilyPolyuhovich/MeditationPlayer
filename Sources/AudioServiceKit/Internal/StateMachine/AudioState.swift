import Foundation
import AudioServiceCore

/// Protocol defining a state in the audio player state machine
protocol AudioStateProtocol: Sendable {
    /// The player state representation
    var playerState: PlayerState { get }

    /// Check if transition to another state is valid
    func isValidTransition(to state: any AudioStateProtocol) -> Bool

    /// Called when entering this state
    func didEnter(from previousState: (any AudioStateProtocol)?, context: AudioStateMachineContext) async

    /// Called when exiting this state
    func willExit(to nextState: any AudioStateProtocol, context: AudioStateMachineContext) async

    // MARK: - Side Effect Hooks

    /// Called on state entry - for side effects
    func onEnter(context: AudioStateMachineContext) async

    /// Called on state exit - for cleanup
    func onExit(context: AudioStateMachineContext) async
}

/// Default implementations
extension AudioStateProtocol {
    func didEnter(from previousState: (any AudioStateProtocol)?, context: AudioStateMachineContext) async {}
    func willExit(to nextState: any AudioStateProtocol, context: AudioStateMachineContext) async {}
    func onEnter(context: AudioStateMachineContext) async {}
    func onExit(context: AudioStateMachineContext) async {}
}

/// Context protocol for state machine to communicate with player
protocol AudioStateMachineContext: Actor {
    /// Called when state changes
    func stateDidChange(to state: PlayerState) async

    /// Request to start audio engine
    func startEngine() async throws

    /// Request to stop audio engine
    func stopEngine() async

    /// Request to pause audio playback
    func pausePlayback() async

    /// Request to resume audio playback
    func resumePlayback() async throws

    /// Request to start fade out
    func startFadeOut(duration: TimeInterval) async

    /// Transition to finished state after fade out
    func transitionToFinished() async

    /// Transition to playing state (called from PreparingState)
    func transitionToPlaying() async

    /// Transition to failed state (called from PreparingState)
    func transitionToFailed(error: AudioPlayerError) async
}

import Foundation
import AudioServiceCore

/// State when player is preparing audio resources
struct PreparingState: AudioStateProtocol {
    var playerState: PlayerState { .preparing }
    
    func isValidTransition(to state: any AudioStateProtocol) -> Bool {
        // Always allow transition to finished (for stop)
        if state.playerState == .finished {
            return true
        }
        
        return state.playerState == .playing || state.playerState == .failed(.unknown(reason: ""))
    }
    
    func didEnter(from previousState: (any AudioStateProtocol)?, context: AudioStateMachineContext) async {
        do {
            // Start the audio engine
            try await context.startEngine()
            
            // CRITICAL: Transition to playing state via state machine
            // This ensures state machine and _state stay synchronized
            await context.transitionToPlaying()
        } catch {
            // Transition to failed state via state machine
            let error = AudioPlayerError.engineStartFailed(reason: error.localizedDescription)
            await context.transitionToFailed(error: error)
        }
    }
}

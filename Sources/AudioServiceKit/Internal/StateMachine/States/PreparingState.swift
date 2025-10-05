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
            
            // Notify state change after successful start
            await context.stateDidChange(to: .playing)
        } catch {
            // Notify error state
            let errorState = PlayerState.failed(
                AudioPlayerError.engineStartFailed(reason: error.localizedDescription)
            )
            await context.stateDidChange(to: errorState)
        }
    }
}

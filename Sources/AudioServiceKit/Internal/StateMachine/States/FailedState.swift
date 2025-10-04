import Foundation
import AudioServiceCore

/// State when player has encountered an error
struct FailedState: AudioStateProtocol {
    let error: AudioPlayerError
    
    var playerState: PlayerState { .failed(error) }
    
    func isValidTransition(to state: any AudioStateProtocol) -> Bool {
        // Can restart from failed state
        return state.playerState == .preparing
    }
    
    func didEnter(from previousState: (any AudioStateProtocol)?, context: AudioStateMachineContext) async {
        await context.stateDidChange(to: .failed(error))
        await context.stopEngine()
    }
}

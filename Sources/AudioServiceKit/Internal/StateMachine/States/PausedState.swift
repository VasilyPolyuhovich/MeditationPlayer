import Foundation
import AudioServiceCore

/// State when playback is paused
struct PausedState: AudioStateProtocol {
    var playerState: PlayerState { .paused }
    
    func isValidTransition(to state: any AudioStateProtocol) -> Bool {
        switch state.playerState {
        case .playing, .finished, .failed:
            return true
        default:
            return false
        }
    }
    
    func didEnter(from previousState: (any AudioStateProtocol)?, context: AudioStateMachineContext) async {
        await context.stateDidChange(to: .paused)
    }
}

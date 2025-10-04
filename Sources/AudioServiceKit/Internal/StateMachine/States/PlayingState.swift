import Foundation
import AudioServiceCore

/// State when player is actively playing audio
struct PlayingState: AudioStateProtocol {
    var playerState: PlayerState { .playing }
    
    func isValidTransition(to state: any AudioStateProtocol) -> Bool {
        switch state.playerState {
        case .paused, .fadingOut, .finished, .failed:
            return true
        default:
            return false
        }
    }
    
    func didEnter(from previousState: (any AudioStateProtocol)?, context: AudioStateMachineContext) async {
        // If coming from paused state, resume playback
        if let prev = previousState, prev.playerState == .paused {
            try? await context.resumePlayback()
        }
        
        await context.stateDidChange(to: .playing)
    }
    
    func willExit(to nextState: any AudioStateProtocol, context: AudioStateMachineContext) async {
        // If going to paused state, pause playback
        if nextState.playerState == .paused {
            await context.pausePlayback()
        }
    }
}

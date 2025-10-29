import Foundation
import AudioServiceCore

/// State when player is actively playing audio
struct PlayingState: AudioStateProtocol {
    var playerState: PlayerState { .playing }

    func isValidTransition(to state: any AudioStateProtocol) -> Bool {
        // Always allow transition to finished (for stop)
        if state.playerState == .finished {
            return true
        }

        switch state.playerState {
        case .preparing:  // Allow reset during playback
            return true
        case .paused, .fadingOut, .failed:
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

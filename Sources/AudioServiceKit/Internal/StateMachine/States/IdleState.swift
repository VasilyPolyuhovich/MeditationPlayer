import Foundation
import AudioServiceCore

/// State when player is idle and ready to accept commands
struct IdleState: AudioStateProtocol {
    var playerState: PlayerState { .idle }

    func isValidTransition(to state: any AudioStateProtocol) -> Bool {
        // Can start playback from idle state
        return state.playerState == .preparing
    }

    func didEnter(from previousState: (any AudioStateProtocol)?, context: AudioStateMachineContext) async {
        await context.stateDidChange(to: .idle)
    }
}

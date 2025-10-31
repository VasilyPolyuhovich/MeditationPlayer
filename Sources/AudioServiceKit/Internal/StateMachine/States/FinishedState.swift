import Foundation
import AudioServiceCore

/// State when playback has finished
struct FinishedState: AudioStateProtocol {
    var playerState: PlayerState { .finished }

    func isValidTransition(to state: any AudioStateProtocol) -> Bool {
        // Can restart from finished state or go to idle
        return state.playerState == .preparing || state.playerState == .idle
    }

    func didEnter(from previousState: (any AudioStateProtocol)?, context: AudioStateMachineContext) async {
        await context.stateDidChange(to: .finished)
        await context.stopEngine()
    }
}

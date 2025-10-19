import Foundation
import AudioServiceCore

/// State when player is fading out before stopping
struct FadingOutState: AudioStateProtocol {
    let fadeDuration: TimeInterval
    
    var playerState: PlayerState { .fadingOut }
    
    func isValidTransition(to state: any AudioStateProtocol) -> Bool {
        switch state.playerState {
        case .finished, .failed:
            return true
        default:
            return false
        }
    }
    
    func didEnter(from previousState: (any AudioStateProtocol)?, context: AudioStateMachineContext) async {
        await context.stateDidChange(to: .fadingOut)
        
        // Start fade out process
        await context.startFadeOut(duration: fadeDuration)
        
        // Wait for fade to complete
        try? await Task.sleep(nanoseconds: UInt64(fadeDuration * 1_000_000_000))
        
        // Properly transition to finished through context
        await context.transitionToFinished()
    }
}

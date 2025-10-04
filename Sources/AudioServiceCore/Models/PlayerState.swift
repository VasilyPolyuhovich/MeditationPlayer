import Foundation

/// Represents the current state of the audio player
public enum PlayerState: Sendable, Equatable {
    /// Player is preparing audio resources
    case preparing
    
    /// Player is actively playing audio
    case playing
    
    /// Player is paused
    case paused
    
    /// Player is fading out before stopping
    case fadingOut
    
    /// Playback has finished
    case finished
    
    /// Player encountered an error
    case failed(AudioPlayerError)
    
    public static func == (lhs: PlayerState, rhs: PlayerState) -> Bool {
        switch (lhs, rhs) {
        case (.preparing, .preparing),
             (.playing, .playing),
             (.paused, .paused),
             (.fadingOut, .fadingOut),
             (.finished, .finished):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

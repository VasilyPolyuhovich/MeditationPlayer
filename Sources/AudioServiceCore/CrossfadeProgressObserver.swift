import Foundation

/// Observer protocol for crossfade progress updates
public protocol CrossfadeProgressObserver: AudioPlayerObserver {
    /// Called when crossfade progress updates
    func crossfadeProgressDidUpdate(_ progress: CrossfadeProgress) async
}

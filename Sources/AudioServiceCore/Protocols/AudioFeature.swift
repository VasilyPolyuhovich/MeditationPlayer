import Foundation

/// Protocol for pluggable audio features
public protocol AudioFeature: Sendable {
    /// Unique identifier for the feature
    var identifier: String { get }
    
    /// Called when feature is registered with player
    func didRegister() async
    
    /// Called before playback starts
    func willStartPlaying() async
    
    /// Called when playback starts
    func didStartPlaying() async
    
    /// Called when playback pauses
    func didPause() async
    
    /// Called when playback resumes
    func didResume() async
    
    /// Called when playback stops
    func didStop() async
    
    /// Called when playback encounters an error
    func didEncounterError(_ error: AudioPlayerError) async
    
    /// Called when feature is unregistered
    func didUnregister() async
}

/// Default implementations for optional feature callbacks
public extension AudioFeature {
    func didRegister() async {}
    func willStartPlaying() async {}
    func didStartPlaying() async {}
    func didPause() async {}
    func didResume() async {}
    func didStop() async {}
    func didEncounterError(_ error: AudioPlayerError) async {}
    func didUnregister() async {}
}

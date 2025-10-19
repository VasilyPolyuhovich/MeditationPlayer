import AudioServiceCore

/// Extension to provide display names for PlayerState
extension PlayerState {
    var displayName: String {
        switch self {
        case .preparing:
            return "Preparing"
        case .playing:
            return "Playing"
        case .paused:
            return "Paused"
        case .fadingOut:
            return "Fading Out"
        case .finished:
            return "Finished"
        case .failed:
            return "Failed"
        }
    }
}

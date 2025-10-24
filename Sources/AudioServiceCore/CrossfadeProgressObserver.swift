import Foundation

// MARK: - Observer Protocol Removed (v3.1)
// CrossfadeProgressObserver has been removed in favor of AsyncStream.
// Crossfade progress is now available via PlaybackStateCoordinator's
// crossfadeProgressUpdates AsyncStream.
//
// Migration:
//   OLD: class MyObserver: CrossfadeProgressObserver { ... }
//   NEW: for await progress in coordinator.crossfadeProgressUpdates { ... }

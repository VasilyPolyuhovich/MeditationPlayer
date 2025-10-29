import Foundation

// Crossfade progress is now available via PlaybackStateCoordinator's
// crossfadeProgressUpdates AsyncStream.
//
// Migration:
//   OLD: class MyObserver: CrossfadeProgressObserver { ... }
//   NEW: for await progress in coordinator.crossfadeProgressUpdates { ... }

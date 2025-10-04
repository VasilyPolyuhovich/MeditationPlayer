# Changelog

All notable changes to Prosper Player will be documented in this file.

## [1.0.0] - 2025-01-XX

### Added
- Initial release of Prosper Player audio service
- Actor-isolated AVAudioEngine implementation for thread-safe audio playback
- Support for 5 fade curve types (Equal-Power, Linear, Logarithmic, Exponential, S-Curve)
- Background audio playback with proper session management
- Remote command center integration (Lock Screen controls)
- Skip forward/backward (15 seconds) functionality
- Configurable crossfading between tracks (1-30 seconds)
- Fade in/out at start and end of playback
- State machine for formal state management
- SwiftUI demo application
- Comprehensive documentation

### Swift 6 Concurrency
- Full Swift 6 strict concurrency compliance
- Actor isolation for all mutable state
- Sendable types for cross-actor communication
- @Sendable closures for thread-safe callbacks
- Custom actor-safe state machine (no GameplayKit dependency)
- Zero compiler warnings in strict mode

### Documentation
- Main README with quick start guide
- Fade curves explained (FadeCurves.md)
- Crossfade algorithm documentation (CrossfadeAlgorithm.md)
- Swift 6 concurrency guide (Swift6Concurrency.md)
- Concurrency fixes summary (ConcurrencyFixes.md)
- Demo app README

### Audio Features
- Dual-player architecture for seamless crossfading
- Equal-power crossfade algorithm (industry standard)
- Configurable fade curves for different use cases
- Looping support with crossfade between iterations
- Volume control with smooth fading
- Position tracking and seeking
- Audio file preloading for instant playback

### Session Management
- AVAudioSession configuration for background audio
- Interruption handling (phone calls, alarms, Siri)
- Route change detection (headphones plug/unplug)
- Engine reconfiguration on hardware changes
- Automatic pause on headphone disconnect

### Testing
- Unit tests for audio configuration
- Unit tests for sendable types
- Unit tests for player state
- Unit tests for fade curves
- Thread Sanitizer compatibility

### Known Limitations
- iOS 18+ only
- Local audio files only (streaming not yet implemented)
- Single track playback (phase-based system planned for v2.0)

## [Unreleased]

### Planned for v2.0
- Phase-based playback system (induction, intentions, returning)
- On-the-fly audio theme switching with crossfade
- `replace(url:, crossfade:)` API implementation
- Loop crossfading at track boundaries
- Audio source abstraction for streaming
- Advanced audio features plugin system
- Performance profiling and optimization
- More comprehensive test coverage

---

## Version History

### [1.0.0] - First Release
- Core audio player functionality
- Swift 6 concurrency compliance
- Professional crossfading algorithms
- Background playback support
- Complete documentation

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

## License

See [LICENSE](LICENSE) for license information.

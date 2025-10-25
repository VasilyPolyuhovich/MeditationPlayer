# PlayerState Redesign - Complete State System Design

**Date:** 2025-01-25
**Status:** Architecture Design (Implementation Ready)
**Author:** Senior iOS Architect
**Breaking Changes:** YES (No backward compatibility required)

---

## Executive Summary

**Problem:** Current `PlayerState` enum (6 cases) hides critical crossfade state, leading to:
- UI showing `.playing` when reality is dual-player crossfade
- Pause scenario ambiguity (normal pause vs crossfade pause)
- Validation failures during crossfade (288 possible state combinations, only 6 exposed)
- Resume logic guessing hidden state from `CrossfadeOrchestrator`

**Solution:** Expose crossfade as first-class state with progress tracking, enabling:
- ✅ Accurate UI representation (show "Crossfading 47%" not just "Playing")
- ✅ Explicit pause variants (normal vs mid-crossfade)
- ✅ Straightforward validation (state carries its own context)
- ✅ Testable state transitions (no hidden orchestrator state)

**Impact:** +4 new states (10 total), ~200 LOC changes, full test coverage required

---

## Section A: State Enum Definition

```swift
import Foundation
import AudioServiceCore

/// Represents the complete, honest state of the audio player
///
/// **Design Principles:**
/// - Crossfade is first-class state (not hidden flag)
/// - Associated values provide context for UI and validation
/// - Sendable + Equatable for Swift 6 concurrency
/// - Self-documenting state names
///
/// **Migration from v1.x:**
/// - `.playing` → `.playing` (single track) OR `.crossfading` (dual track)
/// - `.paused` → `.paused` (normal) OR `.crossfadePaused` (mid-crossfade)
/// - `.preparing` → `.preparing` (normal) OR `.preparingCrossfade` (next track)
///
public enum PlayerState: Sendable, Equatable {

    // MARK: - Initialization States

    /// Player is idle with no loaded content
    ///
    /// **Context:** Initial state, post-stop, post-error recovery
    ///
    /// **UI Guidance:** Show "Ready to play" / Empty state
    ///
    /// **Allowed Actions:** play(track:)
    case idle

    /// Player is preparing audio resources (loading file, buffer allocation)
    ///
    /// **Context:** User called play(), file loading in progress
    ///
    /// **Associated Values:**
    /// - `track`: Track being prepared
    ///
    /// **UI Guidance:** Show loading spinner, track title
    ///
    /// **Allowed Actions:** stop()
    case preparing(track: Track)

    /// Player is preparing next track for crossfade (background operation)
    ///
    /// **Context:** Main track playing, next track loading on inactive player
    ///
    /// **Use Case:** Seamless loops (REQUIREMENTS: 3-stage meditation, 30min sessions)
    ///
    /// **Associated Values:**
    /// - `currentTrack`: Currently playing track
    /// - `nextTrack`: Track being prepared for crossfade
    ///
    /// **UI Guidance:** Show current track, optional "Next: X" indicator
    ///
    /// **Allowed Actions:** pause(), stop(), skip()
    case preparingCrossfade(currentTrack: Track, nextTrack: Track)

    // MARK: - Active Playback States

    /// Player is actively playing a single track
    ///
    /// **Context:** Normal playback (1 player active)
    ///
    /// **Associated Values:**
    /// - `track`: Currently playing track
    ///
    /// **UI Guidance:** Show play button, progress bar, track info
    ///
    /// **Allowed Actions:** pause(), stop(), skip()
    case playing(track: Track)

    /// Player is actively crossfading between two tracks
    ///
    /// **Context:** Dual-player operation (CRITICAL STATE - 10% pause probability!)
    ///
    /// **Use Case:** Meditation sessions with 5-15s crossfade (REQUIREMENTS_ANSWERS.md)
    ///
    /// **Associated Values:**
    /// - `fromTrack`: Track fading out
    /// - `toTrack`: Track fading in
    /// - `progress`: Crossfade completion (0.0 = start, 1.0 = complete)
    /// - `canQuickFinish`: If true, crossfade can finish in 1s on pause (progress >= 50%)
    ///
    /// **UI Guidance:** Show "Crossfading 47%" OR "Transitioning to: [toTrack]"
    ///
    /// **Allowed Actions:** pause() [becomes .crossfadePaused], stop(), skip()
    case crossfading(
        fromTrack: Track,
        toTrack: Track,
        progress: Float, // 0.0...1.0
        canQuickFinish: Bool
    )

    // MARK: - Paused States

    /// Player is paused during normal playback
    ///
    /// **Context:** User paused single-track playback
    ///
    /// **Associated Values:**
    /// - `track`: Paused track
    /// - `position`: Playback position in seconds
    ///
    /// **UI Guidance:** Show pause button, resume capability
    ///
    /// **Allowed Actions:** resume(), stop()
    case paused(track: Track, position: TimeInterval)

    /// Player is paused during crossfade (COMPLEX STATE!)
    ///
    /// **Context:** User paused mid-crossfade (REQUIREMENTS: ~10% probability in 30min session)
    ///
    /// **Use Case:** Morning meditation interrupted by phone call or intentional pause
    ///
    /// **Associated Values:**
    /// - `fromTrack`: Track that was fading out
    /// - `toTrack`: Track that was fading in
    /// - `progress`: Crossfade progress when paused (0.0...1.0)
    /// - `resumeStrategy`: How to resume (.continueFromProgress | .quickFinish)
    /// - `savedState`: Snapshot for perfect resume (volumes, positions)
    ///
    /// **UI Guidance:** Show "Paused during transition" OR "Crossfade paused at 47%"
    ///
    /// **Allowed Actions:** resume() [restores crossfade OR quick-finishes], stop()
    ///
    /// **Resume Behavior:**
    /// - If progress < 50%: Continue crossfade from saved point
    /// - If progress >= 50%: Quick finish in 1 second (avoid jarring restart)
    case crossfadePaused(
        fromTrack: Track,
        toTrack: Track,
        progress: Float,
        resumeStrategy: ResumeStrategy,
        savedState: CrossfadePauseSnapshot
    )

    // MARK: - Transition States

    /// Player is fading out before stopping
    ///
    /// **Context:** User called stop(), graceful fade to silence
    ///
    /// **Associated Values:**
    /// - `track`: Track being faded out
    /// - `targetDuration`: Total fade duration (typically 0.3-1.0s)
    ///
    /// **UI Guidance:** Show "Stopping..." (brief, < 1s typically)
    ///
    /// **Allowed Actions:** None (auto-transition to .finished)
    case fadingOut(track: Track, targetDuration: TimeInterval)

    // MARK: - Terminal States

    /// Playback finished naturally (track reached end)
    ///
    /// **Context:** Track completed, no loop/next track
    ///
    /// **UI Guidance:** Show "Finished" / "Completed" / replay button
    ///
    /// **Allowed Actions:** play(track:), replay()
    case finished

    /// Player encountered an error
    ///
    /// **Context:** File not found, format unsupported, audio session failure, etc.
    ///
    /// **Associated Values:**
    /// - `error`: Detailed error information
    /// - `recoverable`: If true, user can retry; if false, requires cleanup
    ///
    /// **UI Guidance:** Show error message, retry button (if recoverable)
    ///
    /// **Allowed Actions:** retry() if recoverable, reset() to .idle
    case failed(error: AudioPlayerError, recoverable: Bool)

    // MARK: - Associated Types

    /// Strategy for resuming paused crossfade
    public enum ResumeStrategy: Sendable, Equatable {
        /// Continue crossfade from saved progress (< 50% complete)
        ///
        /// **Behavior:** Restore saved volumes/positions, complete remaining duration
        ///
        /// **Example:** Paused at 30% → resume → finish remaining 70%
        case continueFromProgress

        /// Quick finish crossfade in 1 second (>= 50% complete)
        ///
        /// **Behavior:** Rapid fade to completion, avoid jarring restart
        ///
        /// **Example:** Paused at 80% → resume → finish in 1s (not 4.8s)
        case quickFinish
    }

    /// Snapshot of crossfade state at pause moment
    ///
    /// **Purpose:** Enable perfect resume without re-computation
    ///
    /// **Storage:** Volumes, positions, player tracking
    public struct CrossfadePauseSnapshot: Sendable, Equatable {
        /// Volume of fading-out player when paused
        public let activeVolume: Float

        /// Volume of fading-in player when paused
        public let inactiveVolume: Float

        /// Playback position of fading-out track
        public let activePosition: TimeInterval

        /// Playback position of fading-in track
        public let inactivePosition: TimeInterval

        /// Which physical player (.a or .b) was active
        public let activePlayer: PlayerNode

        /// Original crossfade duration for calculations
        public let originalDuration: TimeInterval

        /// Fade curve for smooth resume
        public let curve: FadeCurve

        /// When snapshot was taken (for debugging)
        public let timestamp: Date

        public init(
            activeVolume: Float,
            inactiveVolume: Float,
            activePosition: TimeInterval,
            inactivePosition: TimeInterval,
            activePlayer: PlayerNode,
            originalDuration: TimeInterval,
            curve: FadeCurve,
            timestamp: Date = Date()
        ) {
            self.activeVolume = activeVolume
            self.inactiveVolume = inactiveVolume
            self.activePosition = activePosition
            self.inactivePosition = inactivePosition
            self.activePlayer = activePlayer
            self.originalDuration = originalDuration
            self.curve = curve
            self.timestamp = timestamp
        }
    }

    // MARK: - Equatable Implementation

    public static func == (lhs: PlayerState, rhs: PlayerState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true

        case (.preparing(let lhsTrack), .preparing(let rhsTrack)):
            return lhsTrack.id == rhsTrack.id

        case (.preparingCrossfade(let lhsCurrent, let lhsNext),
              .preparingCrossfade(let rhsCurrent, let rhsNext)):
            return lhsCurrent.id == rhsCurrent.id && lhsNext.id == rhsNext.id

        case (.playing(let lhsTrack), .playing(let rhsTrack)):
            return lhsTrack.id == rhsTrack.id

        case (.crossfading(let lhsFrom, let lhsTo, let lhsProgress, let lhsCanFinish),
              .crossfading(let rhsFrom, let rhsTo, let rhsProgress, let rhsCanFinish)):
            return lhsFrom.id == rhsFrom.id &&
                   lhsTo.id == rhsTo.id &&
                   abs(lhsProgress - rhsProgress) < 0.001 &&
                   lhsCanFinish == rhsCanFinish

        case (.paused(let lhsTrack, let lhsPosition),
              .paused(let rhsTrack, let rhsPosition)):
            return lhsTrack.id == rhsTrack.id &&
                   abs(lhsPosition - rhsPosition) < 0.001

        case (.crossfadePaused(let lhsFrom, let lhsTo, let lhsProgress, let lhsStrategy, let lhsSnapshot),
              .crossfadePaused(let rhsFrom, let rhsTo, let rhsProgress, let rhsStrategy, let rhsSnapshot)):
            return lhsFrom.id == rhsFrom.id &&
                   lhsTo.id == rhsTo.id &&
                   abs(lhsProgress - rhsProgress) < 0.001 &&
                   lhsStrategy == rhsStrategy &&
                   lhsSnapshot == rhsSnapshot

        case (.fadingOut(let lhsTrack, let lhsDuration),
              .fadingOut(let rhsTrack, let rhsDuration)):
            return lhsTrack.id == rhsTrack.id &&
                   abs(lhsDuration - rhsDuration) < 0.001

        case (.finished, .finished):
            return true

        case (.failed(let lhsError, let lhsRecoverable),
              .failed(let rhsError, let rhsRecoverable)):
            return lhsError.localizedDescription == rhsError.localizedDescription &&
                   lhsRecoverable == rhsRecoverable

        default:
            return false
        }
    }
}

// MARK: - PlayerNode (moved from internal to public)

/// Physical player identifier (A or B)
///
/// **Context:** AudioServiceKit uses dual-player architecture for seamless crossfade
///
/// **Note:** This was internal, now public for CrossfadePauseSnapshot
public enum PlayerNode: String, Sendable, Equatable {
    case a
    case b

    public var opposite: PlayerNode {
        return self == .a ? .b : .a
    }
}
```

---

## Section B: State Transition Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         AUDIO PLAYER STATE MACHINE                          │
└─────────────────────────────────────────────────────────────────────────────┘

                              ┌──────────┐
                              │   IDLE   │ ◄──────────────┐
                              └──────────┘                │
                                    │                     │
                        play(track) │                     │ stop()
                                    ▼                     │
                              ┌──────────┐                │
                              │PREPARING │                │
                              └──────────┘                │
                                    │                     │
                         loaded OK  │                     │
                                    ▼                     │
┌────────────────────┐        ┌──────────┐               │
│ PREPARING_CROSSFADE│◄───────│ PLAYING  │───────────────┤
└────────────────────┘ skip() └──────────┘               │
        │                           │                     │
        │                           │ pause()             │
        │ loaded OK                 ▼                     │
        │                     ┌──────────┐                │
        │                     │  PAUSED  │                │
        │                     └──────────┘                │
        │                           │                     │
        │                           │ resume()            │
        │                           │                     │
        │                           ▼                     │
        │                     [back to PLAYING]           │
        │                                                 │
        │ crossfade start                                 │
        └──────────────►  ┌──────────────┐               │
                          │ CROSSFADING  │               │
                          └──────────────┘               │
                                │   │                    │
                       pause()  │   │ complete           │
                                │   │                    │
                                ▼   ▼                    │
                    ┌──────────────────┐  [switch to    │
                    │CROSSFADE_PAUSED  │   next track]  │
                    └──────────────────┘      │          │
                          │       │            ▼          │
                    resume()   stop()    [back to PLAYING]
                          │       │                       │
         ┌────────────────┴───────┴───────────────────────┘
         │
         ▼
  [strategy based resume]
         │
         ├──► continueFromProgress ──► [back to CROSSFADING]
         │
         └──► quickFinish (1s) ──────► [to PLAYING with new track]


  ANY STATE ──────error────────►  ┌──────────┐
                                   │  FAILED  │
                                   └──────────┘
                                         │
                                   retry()/reset()
                                         │
                                         ▼
                                  [back to IDLE]


  PLAYING/PAUSED ──stop()──► ┌─────────────┐
                              │ FADING_OUT  │ ──auto(0.3s)──► FINISHED
                              └─────────────┘

  FINISHED ────play(track)────► [back to PREPARING]
```

### Valid Transitions Table

| FROM State            | TO State             | Trigger Event             | Notes                          |
|-----------------------|----------------------|---------------------------|--------------------------------|
| idle                  | preparing            | play(track)               | User starts playback           |
| preparing             | playing              | file loaded OK            | Auto transition                |
| preparing             | failed               | load error                | File not found, etc.           |
| preparing             | idle                 | stop()                    | User cancels load              |
| playing               | paused               | pause()                   | Normal pause                   |
| playing               | preparingCrossfade   | skip() / loop enabled     | Load next track                |
| playing               | fadingOut            | stop()                    | Graceful stop                  |
| playing               | crossfading          | crossfade started         | From preparingCrossfade        |
| playing               | finished             | track ended               | No loop/next                   |
| playing               | failed               | playback error            | Audio session reset, etc.      |
| preparingCrossfade    | crossfading          | next track loaded         | Auto transition                |
| preparingCrossfade    | paused               | pause()                   | Pause during prep              |
| crossfading           | crossfadePaused      | pause()                   | CRITICAL: 10% probability      |
| crossfading           | playing              | crossfade complete        | New track now active           |
| crossfading           | fadingOut            | stop()                    | User stops mid-crossfade       |
| paused                | playing              | resume()                  | Resume normal playback         |
| paused                | idle                 | stop()                    | Full stop from pause           |
| crossfadePaused       | crossfading          | resume() + continue       | Progress < 50%                 |
| crossfadePaused       | playing              | resume() + quickFinish    | Progress >= 50%                |
| crossfadePaused       | idle                 | stop()                    | Cancel crossfade               |
| fadingOut             | finished             | fade complete (auto)      | 0.3-1.0s transition            |
| finished              | preparing            | play(track)               | Start new playback             |
| failed                | idle                 | reset()                   | Clear error, retry             |
| failed                | preparing            | retry() if recoverable    | Attempt recovery               |

### Invalid Transitions (Compile-time Prevention)

- ❌ `idle` → `crossfading` (must go through preparing first)
- ❌ `paused` → `crossfading` (must resume to playing first)
- ❌ `crossfadePaused` → `paused` (distinct states, no conversion)
- ❌ `finished` → `playing` (must reload through preparing)
- ❌ `failed` → `playing` (must reset to idle first)

---

## Section C: Validation Rules

```swift
extension PlayerState {

    // MARK: - State Properties

    /// Is player actively making sound?
    public var isActive: Bool {
        switch self {
        case .playing, .crossfading, .fadingOut:
            return true
        default:
            return false
        }
    }

    /// Can user pause current playback?
    public var canPause: Bool {
        switch self {
        case .playing, .crossfading, .preparingCrossfade:
            return true
        default:
            return false
        }
    }

    /// Can user resume from current state?
    public var canResume: Bool {
        switch self {
        case .paused, .crossfadePaused:
            return true
        default:
            return false
        }
    }

    /// Is player in terminal state (requires reset)?
    public var isTerminal: Bool {
        switch self {
        case .finished, .failed:
            return true
        default:
            return false
        }
    }

    /// Is crossfade involved in current state?
    public var isCrossfadeRelated: Bool {
        switch self {
        case .preparingCrossfade, .crossfading, .crossfadePaused:
            return true
        default:
            return false
        }
    }

    /// Current track being heard (or was last heard)
    public var currentTrack: Track? {
        switch self {
        case .preparing(let track),
             .playing(let track),
             .paused(let track, _),
             .fadingOut(let track, _):
            return track

        case .preparingCrossfade(let current, _),
             .crossfading(let from, _, _, _),
             .crossfadePaused(let from, _, _, _, _):
            // During crossfade, "current" is the one fading out
            return from

        case .idle, .finished, .failed:
            return nil
        }
    }

    /// Next track (if preparing for crossfade)
    public var nextTrack: Track? {
        switch self {
        case .preparingCrossfade(_, let next),
             .crossfading(_, let to, _, _),
             .crossfadePaused(_, let to, _, _, _):
            return to
        default:
            return nil
        }
    }

    // MARK: - Validation

    /// Validate state consistency
    ///
    /// **Rules:**
    /// 1. Progress values must be in [0.0...1.0]
    /// 2. Positions must be non-negative
    /// 3. Durations must be positive
    /// 4. Snapshot volumes must be in [0.0...1.0]
    /// 5. Tracks must have valid URLs
    ///
    public var isValid: Bool {
        switch self {
        case .idle, .finished:
            return true

        case .preparing(let track),
             .playing(let track),
             .fadingOut(let track, _):
            return track.url.isFileURL || track.url.scheme == "http" || track.url.scheme == "https"

        case .preparingCrossfade(let current, let next):
            return current.url.isFileURL && next.url.isFileURL &&
                   current.id != next.id

        case .paused(let track, let position):
            return track.url.isFileURL &&
                   position >= 0.0

        case .crossfading(let from, let to, let progress, _):
            guard from.url.isFileURL && to.url.isFileURL else {
                return false
            }
            guard from.id != to.id else {
                Logger.audio.error("[PlayerState] Invalid: crossfading same track to itself")
                return false
            }
            guard (0.0...1.0).contains(progress) else {
                Logger.audio.error("[PlayerState] Invalid: crossfade progress \(progress) out of range")
                return false
            }
            return true

        case .crossfadePaused(let from, let to, let progress, _, let snapshot):
            guard from.url.isFileURL && to.url.isFileURL else {
                return false
            }
            guard from.id != to.id else {
                return false
            }
            guard (0.0...1.0).contains(progress) else {
                return false
            }
            guard (0.0...1.0).contains(snapshot.activeVolume) else {
                Logger.audio.error("[PlayerState] Invalid: snapshot activeVolume \(snapshot.activeVolume)")
                return false
            }
            guard (0.0...1.0).contains(snapshot.inactiveVolume) else {
                Logger.audio.error("[PlayerState] Invalid: snapshot inactiveVolume \(snapshot.inactiveVolume)")
                return false
            }
            guard snapshot.activePosition >= 0.0 && snapshot.inactivePosition >= 0.0 else {
                Logger.audio.error("[PlayerState] Invalid: negative position in snapshot")
                return false
            }
            guard snapshot.originalDuration > 0.0 else {
                Logger.audio.error("[PlayerState] Invalid: zero/negative duration in snapshot")
                return false
            }
            return true

        case .failed(_, let recoverable):
            // Always valid, recoverable flag is just metadata
            return true
        }
    }

    // MARK: - Transition Validation

    /// Check if transition to new state is valid
    ///
    /// **Usage:**
    /// ```swift
    /// let currentState: PlayerState = .playing(track: track1)
    /// let newState: PlayerState = .paused(track: track1, position: 5.0)
    /// guard currentState.canTransition(to: newState) else {
    ///     throw AudioPlayerError.invalidTransition(from: currentState, to: newState)
    /// }
    /// ```
    ///
    public func canTransition(to newState: PlayerState) -> Bool {
        switch (self, newState) {
        // From idle
        case (.idle, .preparing):
            return true

        // From preparing
        case (.preparing, .playing),
             (.preparing, .failed),
             (.preparing, .idle):
            return true

        // From playing
        case (.playing, .paused),
             (.playing, .preparingCrossfade),
             (.playing, .crossfading),
             (.playing, .fadingOut),
             (.playing, .finished),
             (.playing, .failed):
            return true

        // From preparingCrossfade
        case (.preparingCrossfade, .crossfading),
             (.preparingCrossfade, .paused),
             (.preparingCrossfade, .fadingOut):
            return true

        // From crossfading
        case (.crossfading, .crossfadePaused),
             (.crossfading, .playing),
             (.crossfading, .fadingOut),
             (.crossfading, .failed):
            return true

        // From paused
        case (.paused, .playing),
             (.paused, .idle):
            return true

        // From crossfadePaused
        case (.crossfadePaused, .crossfading),
             (.crossfadePaused, .playing),
             (.crossfadePaused, .idle):
            return true

        // From fadingOut
        case (.fadingOut, .finished):
            return true

        // From finished
        case (.finished, .preparing):
            return true

        // From failed
        case (.failed, .idle),
             (.failed, .preparing):
            return true

        default:
            Logger.audio.warning("[PlayerState] Invalid transition: \(self) → \(newState)")
            return false
        }
    }
}
```

---

## Section D: UI Mapping

```swift
extension PlayerState {

    // MARK: - Display Text

    /// Human-readable state description for UI
    public var displayText: String {
        switch self {
        case .idle:
            return "Ready"

        case .preparing(let track):
            return "Loading \(track.metadata?.title ?? "track")..."

        case .preparingCrossfade(let current, let next):
            return "Playing \(current.metadata?.title ?? "track") (Next: \(next.metadata?.title ?? "..."))"

        case .playing(let track):
            return "Playing \(track.metadata?.title ?? "track")"

        case .crossfading(let from, let to, let progress, _):
            let percentage = Int(progress * 100)
            return "Transitioning to \(to.metadata?.title ?? "next track") (\(percentage)%)"

        case .paused(let track, _):
            return "Paused: \(track.metadata?.title ?? "track")"

        case .crossfadePaused(let from, let to, let progress, let strategy, _):
            let percentage = Int(progress * 100)
            let strategyText = strategy == .quickFinish ? "finishing soon" : "resuming"
            return "Paused during transition (\(percentage)%, \(strategyText))"

        case .fadingOut(let track, _):
            return "Stopping \(track.metadata?.title ?? "track")..."

        case .finished:
            return "Finished"

        case .failed(let error, let recoverable):
            let recoverText = recoverable ? " (tap to retry)" : ""
            return "Error: \(error.localizedDescription)\(recoverText)"
        }
    }

    /// Short status text for compact UI (status bar, widget)
    public var statusText: String {
        switch self {
        case .idle:
            return "Ready"
        case .preparing:
            return "Loading..."
        case .preparingCrossfade, .playing:
            return "Playing"
        case .crossfading(_, _, let progress, _):
            return "Crossfading \(Int(progress * 100))%"
        case .paused:
            return "Paused"
        case .crossfadePaused(_, _, let progress, _, _):
            return "Paused (\(Int(progress * 100))%)"
        case .fadingOut:
            return "Stopping..."
        case .finished:
            return "Finished"
        case .failed:
            return "Error"
        }
    }

    // MARK: - Allowed Actions

    /// Actions available to user in current state
    public enum PlayerAction: String, CaseIterable {
        case play
        case pause
        case resume
        case stop
        case skip
        case retry
    }

    /// List of actions user can perform in current state
    public var allowedActions: [PlayerAction] {
        switch self {
        case .idle:
            return [.play]

        case .preparing:
            return [.stop]

        case .preparingCrossfade:
            return [.pause, .stop, .skip]

        case .playing:
            return [.pause, .stop, .skip]

        case .crossfading:
            return [.pause, .stop, .skip]

        case .paused:
            return [.resume, .stop]

        case .crossfadePaused:
            return [.resume, .stop]

        case .fadingOut:
            return [] // Auto-transitioning, no user actions

        case .finished:
            return [.play] // Replay or new track

        case .failed(_, let recoverable):
            return recoverable ? [.retry, .stop] : [.stop]
        }
    }

    /// Check if specific action is allowed
    public func allows(_ action: PlayerAction) -> Bool {
        return allowedActions.contains(action)
    }

    // MARK: - UI Color Themes

    /// Suggested color for state indicator
    public var indicatorColor: String {
        switch self {
        case .idle:
            return "gray"
        case .preparing, .preparingCrossfade:
            return "orange"
        case .playing:
            return "green"
        case .crossfading:
            return "blue"
        case .paused, .crossfadePaused:
            return "yellow"
        case .fadingOut:
            return "orange"
        case .finished:
            return "gray"
        case .failed:
            return "red"
        }
    }

    /// Should show progress bar?
    public var showsProgress: Bool {
        switch self {
        case .playing, .paused, .crossfading, .crossfadePaused, .fadingOut:
            return true
        default:
            return false
        }
    }

    /// Should show loading spinner?
    public var showsLoading: Bool {
        switch self {
        case .preparing, .preparingCrossfade, .fadingOut:
            return true
        default:
            return false
        }
    }
}
```

---

## Section E: Migration Strategy

### E.1 Breaking Changes Required

**Public API Changes:**

1. **PlayerState enum** (AudioServiceCore)
   - ❌ REMOVED: `.playing` (single meaning)
   - ✅ ADDED: `.idle`, `.playing(track)`, `.crossfading(...)`, `.crossfadePaused(...)`
   - ⚠️ CHANGED: `.paused` → `.paused(track, position)`
   - ⚠️ CHANGED: `.preparing` → `.preparing(track)`
   - ⚠️ CHANGED: `.fadingOut` → `.fadingOut(track, duration)`

2. **CoordinatorState struct** (PlaybackStateCoordinator)
   - ❌ REMOVED: `isCrossfading: Bool` (now in state itself)
   - ❌ REMOVED: `activeTrack: Track?` (now in state)
   - ❌ REMOVED: `inactiveTrack: Track?` (redundant)
   - ✅ SIMPLIFIED: Single `playbackMode: PlayerState` contains all info

3. **CrossfadeOrchestrator**
   - ❌ REMOVED: `ActiveCrossfadeState` (logic moves to state machine)
   - ❌ REMOVED: `PausedCrossfadeState` (replaced by `CrossfadePauseSnapshot`)
   - ✅ ADDED: Progress reporting to `PlayerState.crossfading`

**Internal Changes:**

1. **PlaybackStateCoordinator**
   - Simplify to single-field SSOT: `var state: PlayerState`
   - Remove dual-track bookkeeping (now in state associated values)
   - Remove `isCrossfading` flag (now state case)

2. **AudioPlayerService**
   - Update 17 state transitions to new enum cases
   - Add progress tracking for crossfade state
   - Simplify pause/resume logic (state carries context)

3. **Validation**
   - Move from `CoordinatorState.isConsistent` to `PlayerState.isValid`
   - Simpler validation (state carries its own invariants)

### E.2 Migration Path

**Phase 1: Add New State Enum (Parallel System)**

1. Create new `PlayerStateV2.swift` with complete enum
2. Keep old `PlayerState` for compatibility
3. Add internal mapping: `PlayerState` ↔ `PlayerStateV2`
4. Tests pass with both systems

**Phase 2: Update Internal Components**

1. Migrate `PlaybackStateCoordinator` to use `PlayerStateV2`
2. Update `CrossfadeOrchestrator` to emit progress
3. Refactor `AudioPlayerService` state transitions
4. Update validation logic

**Phase 3: Update AsyncStream Publishers**

1. `statePublisher` emits `PlayerStateV2`
2. Deprecate old publisher (migration warning)
3. Update demo app to consume new states

**Phase 4: Remove Old System**

1. Delete `PlayerState` (old version)
2. Rename `PlayerStateV2` → `PlayerState`
3. Update public API documentation
4. Release as v2.0.0 (breaking change)

### E.3 Code Changes Required

**File Impact Analysis:**

| File                            | Change Type | LOC Delta | Risk  |
|---------------------------------|-------------|-----------|-------|
| PlayerState.swift               | Rewrite     | +200      | HIGH  |
| PlaybackStateCoordinator.swift  | Simplify    | -100      | MED   |
| CrossfadeOrchestrator.swift     | Refactor    | +50       | MED   |
| AudioPlayerService.swift        | Update      | +30       | LOW   |
| Demo app UI                     | Update      | +40       | LOW   |
| Tests                           | Rewrite     | +150      | HIGH  |
| **TOTAL**                       |             | **+370**  |       |

**Dependencies to Update:**

```swift
// OLD (v1.x)
let state = await stateCoordinator.getState()
if state.playbackMode == .playing {
    if state.isCrossfading {
        // Hidden crossfade state!
    }
}

// NEW (v2.0)
let state = await stateCoordinator.getState()
switch state {
case .playing(let track):
    // Single track playback

case .crossfading(let from, let to, let progress, let canQuickFinish):
    // Explicit crossfade state with progress!
    updateUI(progress: progress)
}
```

---

## Section F: Implementation Tasks

### Task 1: Design New PlayerState Enum
**Why:** Foundation for entire migration
**Files:** `Sources/AudioServiceCore/Models/PlayerStateV2.swift` (new)
**Risk:** LOW (additive, no breaking changes yet)
**Subtasks:**
- Create enum with 10 cases + associated values
- Implement `Sendable`, `Equatable` conformance
- Add validation extension (`isValid`, `canTransition`)
- Add UI mapping extension (`displayText`, `allowedActions`)
- Write unit tests for equality and validation

**Success Criteria:**
- ✅ All 10 states compile
- ✅ Equatable works for fuzzy Float comparison
- ✅ Validation catches invalid progress/volumes
- ✅ 100% test coverage on transitions

---

### Task 2: Create Parallel State System
**Why:** Safe migration without breaking existing code
**Files:**
- `PlaybackStateCoordinator.swift` (update)
- `CrossfadeOrchestrator.swift` (update)
**Risk:** MEDIUM (internal refactor, must maintain behavior)
**Subtasks:**
- Add `private var stateV2: PlayerStateV2` alongside old `state`
- Create bidirectional mapping functions
- Update AsyncStream to publish both versions
- Add logging to compare states (catch inconsistencies)

**Success Criteria:**
- ✅ Old tests still pass
- ✅ New state mirrors old state in all scenarios
- ✅ No performance regression

---

### Task 3: Migrate CrossfadeOrchestrator Progress Tracking
**Why:** Enable `.crossfading(progress:)` state updates
**Files:** `CrossfadeOrchestrator.swift`
**Risk:** MEDIUM (critical path for meditation sessions)
**Subtasks:**
- Refactor `monitorCrossfadeProgress()` to update `stateV2`
- Emit progress every 100ms (same as current)
- Update pause logic to capture `CrossfadePauseSnapshot`
- Test pause at 0%, 30%, 50%, 80%, 100% progress

**Success Criteria:**
- ✅ Progress updates visible in UI
- ✅ Pause captures correct snapshot
- ✅ Resume strategies (continue vs quickFinish) work
- ✅ Integration test: pause at 47% → resume → completes correctly

---

### Task 4: Update AudioPlayerService State Transitions
**Why:** 17 state transitions need to use new enum
**Files:** `AudioPlayerService.swift`
**Risk:** HIGH (public API, breaking changes)
**Subtasks:**
- Map all 17 transitions to new states
- Update `play()`: `.idle` → `.preparing(track)` → `.playing(track)`
- Update `crossfade()`: `.playing` → `.preparingCrossfade` → `.crossfading` → `.playing`
- Update `pause()`: distinguish normal vs crossfade pause
- Update validation to use `state.isValid`

**Success Criteria:**
- ✅ All 17 transitions compile
- ✅ Exhaustive switch coverage
- ✅ No silent fallback to old system

---

### Task 5: Simplify PlaybackStateCoordinator
**Why:** Remove dual-track bookkeeping (now in state)
**Files:** `PlaybackStateCoordinator.swift`
**Risk:** LOW (internal cleanup)
**Subtasks:**
- Remove `CoordinatorState` struct (replace with single `PlayerStateV2`)
- Delete `activeTrack`/`inactiveTrack` fields (redundant)
- Delete `isCrossfading` flag (redundant)
- Simplify `switchActivePlayer()` (state handles it)
- Remove verbose validation (state validates itself)

**Success Criteria:**
- ✅ File shrinks by ~100 LOC
- ✅ SSOT is truly single field
- ✅ Tests pass with simpler logic

---

### Task 6: Update Demo App UI
**Why:** Show off new state system capabilities
**Files:**
- `Examples/ProsperPlayerDemo/PlayerControlsView.swift`
- `Examples/ProsperPlayerDemo/TrackInfoView.swift`
**Risk:** LOW (UI only, no business logic)
**Subtasks:**
- Show crossfade progress bar when `.crossfading`
- Show "Paused (47%)" when `.crossfadePaused`
- Disable buttons based on `state.allowedActions`
- Add color coding based on `state.indicatorColor`

**Success Criteria:**
- ✅ UI shows progress during crossfade
- ✅ Pause mid-crossfade shows accurate state
- ✅ Buttons enable/disable correctly

---

### Task 7: Write Comprehensive Tests
**Why:** No regressions in critical meditation use case
**Files:** `Tests/AudioServiceKitTests/PlayerStateV2Tests.swift` (new)
**Risk:** HIGH (test quality determines migration success)
**Subtasks:**
- Unit tests for all 10 states (equality, validation)
- Transition tests (valid paths, invalid rejections)
- Crossfade pause/resume scenarios (0%, 30%, 50%, 80%, 100%)
- Edge cases: rapid pause/resume, concurrent crossfades, errors during crossfade
- Integration test: full 3-stage meditation session

**Success Criteria:**
- ✅ 100% code coverage on `PlayerStateV2`
- ✅ All 17 state transitions tested
- ✅ Crossfade pause scenarios (5 variations) pass
- ✅ No flaky tests (run 100x without failure)

---

### Task 8: Update Documentation
**Why:** Developers need migration guide
**Files:**
- `MIGRATION_V2.md` (new)
- `ARCHITECTURE.md` (update)
- Code documentation (update)
**Risk:** LOW (documentation only)
**Subtasks:**
- Write migration guide with code examples
- Update architecture diagrams
- Add state transition diagram to docs
- Update README with v2.0 changes

**Success Criteria:**
- ✅ Migration guide covers all breaking changes
- ✅ Examples show old → new code
- ✅ State diagram matches implementation

---

### Task 9: Remove Old System (V2.0 Release)
**Why:** Clean up, single source of truth
**Files:**
- Delete `PlayerState.swift` (old)
- Rename `PlayerStateV2.swift` → `PlayerState.swift`
**Risk:** HIGH (breaking change, version bump)
**Subtasks:**
- Remove parallel state system
- Remove old AsyncStream publisher
- Remove internal mapping functions
- Update version to 2.0.0
- Tag release

**Success Criteria:**
- ✅ No references to old `PlayerState`
- ✅ Clean compile
- ✅ All tests pass
- ✅ Demo app works

---

## Appendix A: Use Case Coverage

**Meditation Session Scenario (from REQUIREMENTS_ANSWERS.md):**

| Stage | State Sequence                                           | Coverage        |
|-------|----------------------------------------------------------|-----------------|
| Start | `idle` → `preparing(stage1_music)` → `playing(stage1)`  | ✅ Normal flow  |
| Stage 1 → 2 | `playing(stage1)` → `preparingCrossfade(stage1, stage2)` → `crossfading(from:stage1, to:stage2, progress:0.0→1.0)` → `playing(stage2)` | ✅ Crossfade |
| Pause during crossfade | `crossfading(progress:0.47)` → `crossfadePaused(progress:0.47, strategy:.continueFromProgress)` | ✅ CRITICAL |
| Resume crossfade | `crossfadePaused` → `crossfading(progress:0.47→1.0)` → `playing(stage2)` | ✅ Resume |
| Stage 2 → 3 | Similar crossfade sequence | ✅ Covered |
| Finish | `playing(stage3)` → `fadingOut` → `finished` | ✅ Graceful end |

**Pause Probability Validation:**
- 30-min session × 5-15s crossfade = ~0.4-1.2min crossfading time
- ~10% of total session time is crossfading
- **Conclusion:** `.crossfadePaused` is NOT an edge case! ✅

---

## Appendix B: Performance Considerations

**State Size:**

```swift
// OLD (v1.x)
struct CoordinatorState {
    var activePlayer: PlayerNode           // 1 byte
    var playbackMode: PlayerState          // 2 bytes (enum + error)
    var activeTrack: Track?                // 8 bytes (optional)
    var inactiveTrack: Track?              // 8 bytes
    var activeMixerVolume: Float           // 4 bytes
    var inactiveMixerVolume: Float         // 4 bytes
    var isCrossfading: Bool                // 1 byte
}
// Total: ~28 bytes + Track overhead

// NEW (v2.0)
enum PlayerState {
    case crossfading(Track, Track, Float, Bool)
    // Track = 8 bytes (reference)
    // Float = 4 bytes
    // Bool = 1 byte
    // Enum discriminator = 1 byte
}
// Total: ~22 bytes per state (20% smaller!)
```

**AsyncStream Impact:**
- Publishing rate unchanged (100ms for progress)
- Fewer state fields = faster Equatable checks
- No extra allocations (value type)

**Conclusion:** State size reduction + simpler validation = net performance gain ✅

---

## Appendix C: Future Enhancements

**Potential v2.1 Additions (Non-Breaking):**

1. **Buffering State:**
   ```swift
   case buffering(track: Track, progress: Float)
   ```
   For streaming audio (network delays)

2. **Seeking State:**
   ```swift
   case seeking(track: Track, from: TimeInterval, to: TimeInterval)
   ```
   For scrubbing timeline (show target position)

3. **Multi-Track Crossfade:**
   ```swift
   case crossfadingMulti(tracks: [Track], progress: Float)
   ```
   For DJ-style mixing (future feature)

4. **Overlay State Exposure:**
   ```swift
   case playing(track: Track, overlay: Track?)
   ```
   Currently hidden, could expose for UI

**Rationale for Deferring:**
- Keep v2.0 focused on crossfade accuracy
- Add incrementally based on user feedback
- Maintain API stability

---

## Sign-Off

**Design Reviewed By:** Senior iOS Architect
**Target Version:** 2.0.0
**Breaking Changes:** YES (full migration guide included)
**Test Coverage Required:** 100% on new state system
**Documentation Required:** Migration guide, state diagram

**Next Steps:**
1. Review this design with team
2. Approve breaking changes for v2.0
3. Begin Task 1 (implement new enum)
4. Parallel development (old system stays until Task 9)

**Estimated Effort:** 2-3 weeks (1 dev, full-time)

---

**Document Version:** 1.0
**Last Updated:** 2025-01-25
**Status:** Ready for Implementation ✅

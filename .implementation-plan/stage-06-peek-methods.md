# Stage 06: Add peekNext/peekPrevious for Instant UI

## Status: [ ] Not Started

## Context Budget: ~10k tokens

## Prerequisites

**Read:**
- `QUEUE_UX_PATTERNS.md` (section 1: Optimistic UI)

**Load Session:** Yes (`load_session()`) - End of Week 1

---

## Goal

Add peekNext/peekPrevious methods for instant UI feedback (no queue wait).

**Expected Changes:** +40 LOC

---

## Implementation Steps

### 1. Add to PlaylistManager

**Analyze first:**
```bash
analyze_file_structure({
  path: "Sources/AudioServiceKit/Internal/PlaylistManager.swift"
})
```

**Add methods:**
```swift
// In PlaylistManager:

/// Peek at next track without advancing index
func peekNext() -> Track? {
    guard !playlist.isEmpty else { return nil }
    
    let nextIndex = (currentIndex + 1) % playlist.count
    return playlist[nextIndex]
}

/// Peek at previous track without changing index
func peekPrevious() -> Track? {
    guard !playlist.isEmpty else { return nil }
    
    let prevIndex = (currentIndex - 1 + playlist.count) % playlist.count
    return playlist[prevIndex]
}
```

### 2. Add to AudioPlayerService

```swift
// In AudioPlayerService:

/// Peek at next track for instant UI update
///
/// Returns immediately without queuing operation.
/// UI can show next track info while skipToNext() executes in background.
public func peekNextTrack() async -> Track.Metadata? {
    guard let track = await playlistManager.peekNext() else {
        return nil
    }
    return track.metadata
}

/// Peek at previous track for instant UI update
public func peekPreviousTrack() async -> Track.Metadata? {
    guard let track = await playlistManager.peekPrevious() else {
        return nil
    }
    return track.metadata
}
```

### 3. Build Verification

```bash
xcodebuild -scheme AudioServiceKit \
  -destination 'id=SIMULATOR_ID' \
  -skipPackagePluginValidation \
  build
```

---

## Success Criteria

- [ ] PlaylistManager.peekNext() added
- [ ] PlaylistManager.peekPrevious() added
- [ ] AudioPlayerService.peekNextTrack() added
- [ ] AudioPlayerService.peekPreviousTrack() added
- [ ] Returns Track.Metadata instantly
- [ ] Build passes

---

## Commit + Session Save

```bash
# Commit
[Stage 06] Add peekNext/peekPrevious for instant UI

Enables optimistic UI updates:
- peekNext/peekPrevious return immediately
- UI shows next track before audio transition
- No queue wait (instant feedback)

UX: Next button feels instant (<20ms).

Ref: .implementation-plan/stage-06-peek-methods.md
Build: ✅ Passes

# Save session (Week 2 start)
save_session({
  context: {
    what: "Week 2 integration (Stages 4-6)",
    status: "Navigation + transport wrapped, peek methods added",
    files: [
      "AudioPlayerService.swift (queue integrated)",
      "PlaylistManager.swift (peek methods)"
    ],
    nextSteps: [
      "Stage 07: Return metadata from navigation",
      "Stage 08: File I/O timeout wrapper",
      "Week 3: Robustness layer"
    ]
  },
  handoff: "Queue інтегровано в navigation + transport. Peek methods для instant UI. Наступне - metadata returns + timeout wrapper."
})
```

---

## Next Stage

**Stage 07 - Return Track.Metadata from navigation methods**

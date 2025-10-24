# Stage 07: Return Track.Metadata from Navigation

## Status: [ ] Not Started

## Context Budget: ~8k tokens

## Prerequisites

**Read:** Previous stage 06 (peek methods)

**Load Session:** No

---

## Goal

Modify skipToNext/Prev to return Track.Metadata instantly for UI.

**Expected Changes:** ~20 LOC

---

## Implementation Steps

### 1. Modify skipToNext Signature

```swift
// Change from:
public func skipToNext() async throws

// To:
public func skipToNext() async throws -> Track.Metadata?

// Implementation:
public func skipToNext() async throws -> Track.Metadata? {
    // 1. Get metadata BEFORE queueing (instant)
    let nextMetadata = await peekNextTrack()
    
    // 2. Queue audio operation (background)
    try await operationQueue.enqueue(
        priority: .normal,
        description: "skipToNext"
    ) {
        try await self._skipToNextImpl()
    }
    
    // 3. Return metadata (UI can use immediately)
    return nextMetadata
}
```

### 2. Modify skipToPrevious Similarly

```swift
public func skipToPrevious() async throws -> Track.Metadata? {
    let prevMetadata = await peekPreviousTrack()
    
    try await operationQueue.enqueue(
        priority: .normal,
        description: "skipToPrevious"
    ) {
        try await self._skipToPreviousImpl()
    }
    
    return prevMetadata
}
```

### 3. Update Demo App (Optional Check)

```bash
# Check if demo needs update
grep -n "skipToNext()" Examples/ProsperPlayerDemo/ProsperPlayerDemo/MeditationSession.swift
```

**If needed, suggest to user:**
```swift
// Demo can now do:
if let nextTrack = try? await player.skipToNext() {
    currentTrackInfo = nextTrack  // INSTANT UI update
}
```

### 4. Build Verification

```bash
xcodebuild -scheme AudioServiceKit \
  -destination 'id=SIMULATOR_ID' \
  -skipPackagePluginValidation \
  build
```

---

## Success Criteria

- [ ] skipToNext() returns Track.Metadata?
- [ ] skipToPrevious() returns Track.Metadata?
- [ ] Metadata returned BEFORE queue wait
- [ ] Build passes
- [ ] Demo app compatible (return value optional)

---

## Commit Template

```
[Stage 07] Return metadata from navigation methods

Navigation methods now return Track.Metadata instantly:
- skipToNext/Prev call peekNext/Prev first
- Return metadata before queueing audio operation
- UI gets instant feedback

Demo app can now update UI immediately on Next tap.

Ref: .implementation-plan/stage-07-return-metadata.md
Build: ✅ Passes
```

---

## Next Stage

**Stage 08 - File I/O timeout wrapper + progress**

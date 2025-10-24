# Stage 15: Integration Test - 30-Min Meditation (OPTIONAL)

## Status: [ ] Awaiting User Approval

## Context Budget: ~15k tokens

## Prerequisites

**User Approval Required:** Ask user before starting.

**Read:**
- `Tests/AudioServiceKitIntegrationTests/README.md`
- `REQUIREMENTS_ANSWERS.md` (3-stage meditation)

**Load Session:** No

---

## Goal

Create integration test simulating real 30-min meditation session with pauses.

**Expected:** New file ~150 LOC

---

## Implementation Steps (If Approved)

### 1. Create Test File

**File:** `Tests/AudioServiceKitIntegrationTests/QueueStabilityTests.swift`

```swift
import XCTest
@testable import AudioServiceKit

/// Integration test for queue behavior under meditation app usage
final class QueueStabilityTests: XCTestCase {
    
    func testThreeStageMeditationWithPauses() async throws {
        // Setup
        let player = try await AudioPlayerService()
        try await player.loadPlaylist([
            stage1Track,  // 5 min
            stage2Track,  // 20 min
            stage3Track   // 5 min
        ])
        
        try await player.startPlaying()
        
        // Stage 1: Intro (5 min → compressed to 5s for test)
        try await Task.sleep(for: .seconds(2))
        
        // User pauses (morning routine)
        try await player.pause()
        try await Task.sleep(for: .seconds(1))
        
        // User resumes
        try await player.resume()
        try await Task.sleep(for: .seconds(2))
        
        // Transition to Stage 2 (with crossfade)
        _ = try await player.skipToNext()
        
        // Stage 2: Practice (20 min → compressed to 10s)
        // Simulate multiple overlay switches
        for _ in 1...5 {
            try await player.playOverlay(mantrakTrack)
            try await Task.sleep(for: .seconds(1))
            await player.stopOverlay()
        }
        
        // Mid-stage pause
        try await player.pause()
        try await Task.sleep(for: .seconds(1))
        try await player.resume()
        
        // Transition to Stage 3
        _ = try await player.skipToNext()
        
        // Stage 3: Closing (5 min → compressed to 5s)
        try await Task.sleep(for: .seconds(5))
        
        // Verify final state
        let state = await player.state
        XCTAssertEqual(state, .playing)
        
        // No crashes = success
    }
    
    func testPauseDuringCrossfade() async throws {
        let player = try await AudioPlayerService()
        try await player.loadPlaylist([track1, track2])
        
        try await player.startPlaying()
        
        // Start crossfade
        Task {
            try? await player.skipToNext()
        }
        
        // Pause after 1s (crossfade in progress)
        try await Task.sleep(for: .seconds(1))
        try await player.pause()
        
        // Verify pause worked
        let state = await player.state
        XCTAssertEqual(state, .paused)
        
        // Resume should continue crossfade
        try await player.resume()
        try await Task.sleep(for: .seconds(5))
        
        // Should complete gracefully
    }
}
```

### 2. Run Integration Tests

```bash
swift test --filter QueueStabilityTests
```

---

## Success Criteria

- [ ] 3-stage meditation test passes
- [ ] Pause during crossfade test passes
- [ ] No crashes
- [ ] No state corruption
- [ ] Tests complete in <30s (compressed time)

---

## Commit Template

```
[Stage 15] Add integration tests for queue stability

Real-world scenario tests:
- 30-min meditation session (compressed)
- Multiple pauses during playback
- Overlay switches during Stage 2
- Pause during crossfade

Tests: ✅ 2/2 passing

Ref: .implementation-plan/stage-15-integration-test.md
```

---

## Next Stage (Optional)

**Stage 16 - Documentation + method catalog**

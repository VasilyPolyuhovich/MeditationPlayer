# Stage 13: Remove Defensive Nil Checks

## Status: [ ] Not Started

## Context Budget: ~8k tokens

## Prerequisites

**Read:** Previous stages (queue guarantees state consistency)

**Load Session:** Yes (`load_session()`) - End of Week 4

---

## Goal

Remove defensive nil checks that are no longer needed with queue serialization.

**Expected Changes:** -30 LOC

---

## Implementation Steps

### 1. Find Defensive Checks

```bash
# Search for common patterns:
grep -n "guard.*!= nil" Sources/AudioServiceKit/Internal/CrossfadeOrchestrator.swift
grep -n "?? " Sources/AudioServiceKit/Public/AudioPlayerService.swift
grep -n "if let.*else { return }" Sources/AudioServiceKit/
```

### 2. Analyze Safety

**Safe to remove (queue guarantees):**
- State checks after await (queue serializes)
- Active player nil checks (always valid in operation)
- Track nil checks inside queued operation

**KEEP (still needed):**
- Input validation (user params)
- File existence checks (external dependency)
- Audio session error handling (system)

### 3. Example Removals

```swift
// BEFORE (defensive):
guard let currentTrack = await playbackStateCoordinator.getCurrentTrack() else {
    throw AudioPlayerError.noTrackLoaded
}

// AFTER (queue guarantees track exists):
let currentTrack = await playbackStateCoordinator.getCurrentTrack()!
// Or better: assume non-nil in operation context
```

**Be conservative:** Only remove checks where queue GUARANTEES state consistency.

### 4. Build Verification

```bash
xcodebuild -scheme AudioServiceKit \
  -destination 'id=SIMULATOR_ID' \
  -skipPackagePluginValidation \
  build
```

---

## Success Criteria

- [ ] Defensive checks identified
- [ ] Safe removals made (~30 LOC)
- [ ] Critical checks KEPT (file I/O, session)
- [ ] Build passes
- [ ] No force-unwrap crashes (test with nil scenarios)

---

## Commit + Session Save

```bash
# Commit
[Stage 13] Remove unnecessary defensive nil checks

Simplified code with queue state guarantees:
- Removed redundant state checks after await
- Removed defensive nil coalescing
- KEPT: input validation, file I/O, session errors

Queue serialization ensures state consistency.

Ref: .implementation-plan/stage-13-remove-defensive-checks.md
Build: ✅ Passes
LOC: -30

# Save session (Week 4 complete)
save_session({
  context: {
    what: "Week 4 cleanup (Stages 11-13)",
    status: "All band-aids removed, code simplified",
    files: [
      "CrossfadeOrchestrator (UUID removed)",
      "AudioPlayerService (checks simplified)"
    ],
    nextSteps: [
      "Optional stages 14-16 (user decision)",
      "Manual testing: 30-min meditation",
      "Final documentation + method catalog"
    ]
  },
  handoff: "Cleanup завершено. Debounce, UUID, defensive checks видалено. Net: -160 LOC. Код чистіший. Опціонально: тести + документація (user approval)."
})
```

---

## Final Core Implementation Complete!

**Next:** Optional stages 14-16 (user must approve)

---

## Next Stage (Optional)

**Stage 14 - Unit tests** (requires user confirmation)

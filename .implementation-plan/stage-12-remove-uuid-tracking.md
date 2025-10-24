# Stage 12: Remove UUID Identity Tracking

## Status: [ ] Not Started

## Context Budget: ~10k tokens

## Prerequisites

**Read:**
- `OPERATION_CALL_FLOW.md` (section on UUID tracking)
- `ARCHITECTURE_ANALYSIS.md` (band-aid #2)

**Load Session:** No

---

## Goal

Remove UUID identity tracking from CrossfadeOrchestrator (no longer needed with queue).

**Expected Changes:** -50 LOC

---

## Implementation Steps

### 1. Analyze Current UUID Usage

```bash
# Find all UUID references
grep -n "\.id" Sources/AudioServiceKit/Internal/CrossfadeOrchestrator.swift
grep -n "crossfadeId" Sources/AudioServiceKit/Internal/CrossfadeOrchestrator.swift
```

### 2. Identify ActiveCrossfadeState Changes

```bash
get_symbol_definition({
  path: "Sources/AudioServiceKit/Internal/CrossfadeOrchestrator.swift",
  symbolName: "ActiveCrossfadeState",
  symbolType: "struct"
})
```

### 3. Remove UUID from ActiveCrossfadeState

```swift
// OLD:
private struct ActiveCrossfadeState {
    let id: UUID = UUID()  // ❌ DELETE THIS
    let operation: CrossfadeOperation
    // ... rest
}

// NEW:
private struct ActiveCrossfadeState {
    let operation: CrossfadeOperation
    // ... rest (no UUID)
}
```

### 4. Remove Identity Checks

```swift
// In performFullCrossfade, DELETE:

// 8. Save crossfade ID for race detection
let crossfadeId = activeCrossfade!.id  // ❌ DELETE

// ... later ...

// 11. Identity check: cancelled if ID changed or nil
if activeCrossfade?.id != crossfadeId {  // ❌ DELETE ENTIRE BLOCK
    Self.logger.debug("[CrossfadeOrch] Crossfade was cancelled (identity mismatch)")
    return .cancelled
}
```

**Justification:** Queue serialization makes race impossible, so identity check unnecessary.

### 5. Build Verification

```bash
xcodebuild -scheme AudioServiceKit \
  -destination 'id=SIMULATOR_ID' \
  -skipPackagePluginValidation \
  build
```

---

## Success Criteria

- [ ] UUID property removed from ActiveCrossfadeState
- [ ] crossfadeId variable removed
- [ ] Identity check blocks removed
- [ ] ~50 LOC deleted
- [ ] Build passes
- [ ] No new warnings

---

## Commit Template

```
[Stage 12] Remove UUID identity tracking

Removes race condition band-aid (no longer needed):
- Deleted UUID from ActiveCrossfadeState
- Removed crossfadeId checks after await
- Simplified performFullCrossfade flow

Queue serialization prevents races, identity check unnecessary.

Ref: .implementation-plan/stage-12-remove-uuid-tracking.md
Build: ✅ Passes
LOC: -50
```

---

## Next Stage

**Stage 13 - Remove defensive nil checks**

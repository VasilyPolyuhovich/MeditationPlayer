# Stage 11: Remove Debounce Code (Already Done in Stage 04)

## Status: [ ] Verify Only (No Code Changes)

## Context Budget: ~5k tokens

## Prerequisites

**Read:** Stage 04 (where debounce was removed)

**Load Session:** No

---

## Goal

Verify debounce code was fully removed in Stage 04.

**Expected:** No code changes, verification only

---

## Verification Steps

### 1. Search for Remnants

```bash
# Should find ZERO results:
grep -r "navigationDebounce" Sources/AudioServiceKit/
grep -r "isHandlingNavigation" Sources/AudioServiceKit/
grep -r "setNavigationHandlingFlag" Sources/AudioServiceKit/
```

### 2. Verify LOC Reduction

```bash
scc Sources/AudioServiceKit/Public/AudioPlayerService.swift

# Compare with Stage 03 baseline
# Expected: ~80 LOC reduction from debounce removal
```

### 3. Verify Build

```bash
xcodebuild -scheme AudioServiceKit \
  -destination 'id=SIMULATOR_ID' \
  -skipPackagePluginValidation \
  build
```

---

## Success Criteria

- [ ] No "debounce" strings found
- [ ] No "isHandlingNavigation" found
- [ ] LOC reduced by ~80
- [ ] Build still passes

---

## Commit Template

```
[Stage 11] Verify debounce removal (cleanup checkpoint)

Verification complete:
- ✅ No debounce code remains
- ✅ LOC reduced by ~80
- ✅ Build passes

Debounce was removed in Stage 04, this is verification only.

Ref: .implementation-plan/stage-11-remove-debounce.md
```

---

## Next Stage

**Stage 12 - Remove UUID identity tracking**

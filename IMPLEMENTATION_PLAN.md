# Implementation Plan: Task Serialization Queue

**Goal:** Eliminate actor re-entrancy race conditions in AudioPlayerService

**Status:** 🟡 In Progress  
**Started:** 2025-01-24  
**Estimated:** 4 weeks (13 stages)

---

## Progress Tracker

### Week 1: Core Infrastructure (3 stages)
- [x] Stage 01: AsyncOperationQueue base implementation
- [ ] Stage 02: Priority enum + cancellation logic
- [ ] Stage 03: Adaptive timeout manager

### Week 2: Integration (4 stages)
- [ ] Stage 04: Wrap skipToNext/skipToPrevious
- [ ] Stage 05: Wrap pause/resume/stop/finish
- [ ] Stage 06: Add peekNext/peekPrevious for instant UI
- [ ] Stage 07: Return Track.Metadata from navigation methods

### Week 3: Robustness (3 stages)
- [ ] Stage 08: File I/O timeout wrapper + progress
- [ ] Stage 09: AsyncStream<PlayerEvent> for long operations
- [ ] Stage 10: Priority-based queue cancellation

### Week 4: Cleanup (3 stages)
- [ ] Stage 11: Remove debounce code (~80 LOC)
- [ ] Stage 12: Remove UUID identity tracking (~50 LOC)
- [ ] Stage 13: Remove defensive nil checks (~30 LOC)

### Week 5: Optional (3 stages - User Confirmation Required)
- [ ] Stage 14: Unit tests for queue behavior
- [ ] Stage 15: Integration tests (30-min meditation)
- [ ] Stage 16: Documentation cross-linking + method catalog

---

## Key Metrics

| Metric | Before | Target | Current |
|--------|--------|--------|---------|
| Cyclomatic Complexity | 209 | <180 | - |
| Lines of Code | 2578 | ~2400 | - |
| Race Condition Tests | 0 | 5+ | - |
| Build Time | ~30s | <35s | - |

---

## Architecture Changes

**New Files:**
- `Sources/AudioServiceKit/Internal/AsyncOperationQueue.swift`
- `Sources/AudioServiceKit/Internal/AdaptiveTimeoutManager.swift`
- `Sources/AudioServiceKit/Models/OperationPriority.swift`
- `Sources/AudioServiceKit/Models/PlayerEvent.swift`

**Modified Files:**
- `Sources/AudioServiceKit/Public/AudioPlayerService.swift` (major refactor)
- `Sources/AudioServiceKit/Internal/CrossfadeOrchestrator.swift` (timeout wrapper)
- `Sources/AudioServiceKit/Internal/AudioEngineActor.swift` (progress tracking)

**Deleted Code:**
- Navigation debounce logic (~80 LOC)
- UUID identity tracking (~50 LOC)
- Defensive nil checks (~30 LOC)

**Net Change:** ~+600 LOC new, -160 LOC deleted = +440 LOC total

---

## Context Management Strategy

**Session Saves:** After stages 3, 6, 10, 13
- Prevents auto-compact mid-work
- ~30k tokens per session
- Total budget: 4 sessions × 30k = 120k tokens

**Memory Graph:**
- Architectural decisions (entities)
- Component relations
- Failed attempts + lessons learned

**Git Strategy:**
- Commit per stage (13 commits)
- Hard rollback on build failure
- Squash before final PR

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Queue overhead >10ms | 20% | Medium | Benchmark in Stage 10 |
| Timeout false positives | 15% | Low | Adaptive manager (Stage 3) |
| Build breaks mid-refactor | 30% | High | Build after EVERY stage |
| Context budget exceeded | 10% | Medium | Session saves every 3 stages |

---

## Rollback Plan

**If Stage Fails:**
1. `git reset --hard HEAD~1` (hard rollback)
2. Create `.implementation-plan/stage-XX-review.md`
3. Architect analyzes: Fix vs Rewrite?
4. Update this tracker with FAILED status

**If Multiple Stages Fail:**
1. Roll back to last working stage
2. Review entire week's approach
3. Consider alternative architecture
4. Consult ARCHITECTURE_ANALYSIS.md

---

## Verification Checklist (Per Stage)

- [ ] `xcodebuild -scheme AudioServiceKit -destination 'id=SIM_ID' build` passes
- [ ] No new compiler warnings
- [ ] No new SwiftLint violations (if enabled)
- [ ] Stage file marked complete
- [ ] This tracker updated
- [ ] Commit message references stage file

---

## Final Success Criteria

**Must Have:**
- ✅ All 13 stages complete
- ✅ Build passes on iOS Simulator
- ✅ No race conditions in rapid Next clicks (manual test)
- ✅ Pause during crossfade <100ms (manual test)

**Optional (Stage 14-16):**
- ⚠️ Unit tests pass (if implemented)
- ⚠️ 30-min meditation test passes (if implemented)
- ⚠️ Documentation complete (if requested)

---

## References

- `ARCHITECTURE_ANALYSIS.md` - Root cause analysis
- `OPERATION_CALL_FLOW.md` - All await suspension points
- `QUEUE_UX_PATTERNS.md` - UX patterns + industry best practices
- `.implementation-plan/stage-XX-*.md` - Detailed stage instructions

---

**Last Updated:** 2025-01-24 (Initial plan created)  
**Next Stage:** Stage 01 - AsyncOperationQueue

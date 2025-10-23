# 📋 Functional Requirements - Filled Questionnaire

**Date:** 2025-01-23
**Status:** Section 1-5 Complete
**Purpose:** Validate architecture decisions

---

## ✅ Section 1: Business Context

**Q: Application type?**
✅ Meditation/Mindfulness app (motivation & mood setting)

**Q: Target audience?**
✅ SDK target: iOS developers
✅ End users: Casual users (peace & stability critical!)

**Q: Expected users?**
✅ Beta stage, small user base initially
✅ Priority: Stability > Features

---

## ✅ Section 2: Playback Modes & Scenarios

**Primary Use Case: 3-Stage Meditation Session (~30 min)**

### Stage 1: Introduction (~5 min)
- **Main Player:** Background music (playlist/loop with crossfade)
- **Overlay:** Short voice instructions (breathing exercises)
- **Effects:** Countdown + Gong sounds

### Stage 2: Main Practice (~20 min)
- **Main Player:** Different music playlist/loop (deeper meditation)
- **Overlay:** MANY switches - motivational texts/mantras (frequent!)
- **Effects:** Stage markers (gongs for transitions)

### Stage 3: Closing (~5 min)
- **Main Player:** Calming music (return/grounding)
- **Overlay:** Voice guidance + user attention required
- **Effects:** Completion markers

**Typical Session Duration:** 30 minutes
**Pause Frequency:** VERY HIGH (morning routine - daily pauses) ⚡
**Critical:** Pause stability is TOP priority!

**Interruption Recovery:**
✅ Must auto-pause on phone call
✅ Must auto-resume after interruption
✅ Part of morning routine flow

---

## ✅ Section 3: Crossfade Requirements

**Q: Crossfade duration?**
✅ User configurable in PlayerConfiguration
✅ Typically: 5-15 seconds (longer than 3s mentioned before)

**Q: Pause during crossfade?**
✅ HIGH PRIORITY - happens frequently in morning routine
✅ Desired behavior:
  - If progress < 50%: PAUSE (save state, resume from saved point)
  - If progress >= 50%: QUICK FINISH with fade out

**Current implementation:** ✅ Matches requirements (ResumeStrategy logic)

**Q: Phone call during crossfade?**
✅ Must auto-pause crossfade
✅ Must resume seamlessly after call ends
✅ Save volumes/positions for perfect recovery

**Q: Concurrent crossfade?**
✅ Rollback previous (0.3s smooth transition)
✅ Current implementation correct

---

## ✅ Section 4: Overlay Player

**Q: Overlay usage?**
✅ Voice instructions (breathing exercises)
✅ Motivational texts (repeated mantras)
✅ Guided meditations

**Q: Overlay frequency?**
✅ Developer-controlled (playlist + repeat mode + delays)
✅ Can be many switches per session (Stage 2 especially)

**Q: Overlay independence?**
✅ Separate lifecycle from main player
✅ Has own pause control
✅ Usually paused together with main (pauseAll() convenience method)
✅ Can be paused independently when needed

**Q: Overlay loop?**
✅ Configurable via OverlayConfiguration
✅ Loop modes: once, count(N), infinite
✅ Loop delay supported (pause between repetitions)

**Q: Overlay transition?**
✅ Instant stop of previous when new starts
✅ No fade/overlap (current behavior correct)

**Q: Overlay during main crossfade?**
✅ Continues at full volume (no ducking)
✅ Independent playback (current behavior correct)

---

## ✅ Section 5: Sound Effects

**Q: Sound effects types?**
✅ Developer provides own sounds (no SDK presets)
✅ Typical: Gong, countdown, bells, singing bowls
✅ Short sounds (few seconds each)

**Q: Effects frequency?**
✅ Triggered by developer (time-based or event-based)
✅ No user control planned
✅ Typically ~10 effects per session

**Q: Cache size?**
✅ Current LRU cache (10 sounds) is sufficient
✅ Typically < 10 unique sounds per session

**Q: Effects overlap with main?**
✅ Play simultaneously (no ducking)
✅ Independent from main player state

---

## ✅ Section 6: Pause/Resume (CRITICAL!)

**Historical Issues:**
❌ Pause didn't apply correctly (3 independent players)
❌ Crossfade pause/resume bugs
❌ Fade operations (fade in, fade out, crossfade) had complex logic:
  - Fade in: volume 0 → target
  - Fade out: volume current → 0
  - Crossfade: active fade out + inactive fade in + player switch

**Current Requirements:**
✅ Overlay has independent pause (sometimes needed separately)
✅ Usually pause is global (pauseAll() convenience)
✅ Developer decides pause strategy

**Pause Behavior:**
✅ pauseAll() - pause main + overlay + stop effects
✅ pause() - pause main only
✅ pauseOverlay() - pause overlay only

**Critical:** Pause must be rock-solid stable (morning routine!) ⚡

---

## 🎯 Architecture Validation

### ✅ Justified Components:

#### 1. **Three Independent Players** - CRITICAL
```
AudioEngine {
  playerA/B (main music crossfade)     ✅ Seamless loops/transitions
  playerC (overlay voice)              ✅ Frequent switches during main playback
  playerD (sound effects)              ✅ Independent triggers
}
```
**Why:** Overlay must switch WITHOUT interrupting main music

#### 2. **CrossfadeOrchestrator** - JUSTIFIED
```
CrossfadeOrchestrator {
  - pauseCrossfade()     ✅ Daily morning pauses during crossfade!
  - resumeCrossfade()    ✅ Seamless recovery with saved state
  - ResumeStrategy       ✅ <50% pause, >=50% quick finish
}
```
**Why:** High probability of pause during 5-15s crossfade in 30min session

#### 3. **Protocol-Based Architecture** - JUSTIFIED FOR SDK
```
AudioEngineControl protocol           ✅ Developers can mock for testing
PlaybackStateStore protocol           ✅ Clear boundaries
CrossfadeOrchestrating protocol       ✅ SDK extensibility
```
**Why:** SDK needs clean APIs for developers to understand & test

### ⚠️ Questionable Components:

#### 1. **PlaybackOrchestrator** - MIGHT BE OVERKILL
```
PlaybackOrchestrator {
  startPlaying(track, fadeDuration)   // Session activate → Engine start → State update
  pause()                             // Validate state → Engine pause
  resume()                            // Session ensure → Engine play
}
```

**Question:** Does this abstraction add value for SDK?
- ✅ Coordinates multi-step flows (session + engine + state)
- ⚠️ Adds extra actor hop (complexity)
- ❓ Could Service handle this directly?

**Decision:** TBD - need to assess if orchestrator simplifies or complicates developer experience

---

## 📊 Summary Stats

| Metric | Value | Impact |
|--------|-------|--------|
| Session Duration | 30 min | Medium |
| Pause Frequency | Daily (morning) | HIGH ⚡ |
| Overlay Switches | Developer-controlled | Variable |
| Effects per Session | ~10 | Low |
| Crossfade Duration | 5-15s (configurable) | Medium-High |
| Crossfade Pause Probability | ~5-10% | HIGH ⚡ |
| Target Stability | Beta (critical) | HIGHEST ⚡⚡⚡ |

---

## 🎯 Next Steps

1. ✅ Sections 1-5 complete
2. [ ] Continue Section 6-11 (if needed)
3. [ ] Final architecture decision
4. [ ] Simplification plan (if applicable)

**Current Assessment:** Architecture is MORE justified than initially thought for SDK use case! 🎯

Critical features (pause stability, crossfade recovery, overlay independence) all require current complexity level.

**Main Question Remaining:** Is PlaybackOrchestrator necessary or can Service handle orchestration directly?

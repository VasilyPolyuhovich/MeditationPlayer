# AudioServiceKit Integration Tests

## 🎯 Purpose

Critical scenario testing for **real-world meditation app usage**.

Based on requirements from `REQUIREMENTS_ANSWERS.md`:
- 30-minute 3-stage meditation sessions
- Daily morning pauses (HIGH priority)
- 5-15 second crossfades with pause probability ~10%
- MANY overlay switches in Stage 2
- Sound effects independent playback

## 📋 Test Suites

### 1. CrossfadePauseTests.swift
**Focus:** Pause during crossfade (critical use case)

| Test | Scenario | Expected Result |
|------|----------|-----------------|
| `testPauseDuringCrossfade_At25Percent` | Pause at 25% progress | Continue from saved state |
| `testPauseDuringCrossfade_At75Percent` | Pause at 75% progress | Quick finish in 1 second |
| `testMultiplePausesResumes_DuringCrossfade` | Multiple pause cycles | Handle gracefully |
| `testPhoneCallInterruption_DuringCrossfade` | AVAudioSession interruption | Auto pause/resume |
| `testConcurrentCrossfade_RollbackPrevious` | New crossfade during active | Rollback in 0.3s |

### 2. ThreeStageMeditationTests.swift
**Focus:** Full 30-minute session simulation

| Test | Scenario | Expected Result |
|------|----------|-----------------|
| `testFullMeditationSession_AllStages` | Complete 3-stage session | All transitions smooth |
| `testStage2_FrequentOverlaySwitches` | 10 overlay switches | Music uninterrupted |
| `testPauseStability_MultipleScenarios` | Various pause scenarios | Rock-solid stability |
| `testSoundEffects_DuringCrossfade` | Effects during transitions | Independent playback |

## 🎵 Required Test Audio Files

Place audio files in `Tests/AudioServiceKitIntegrationTests/TestResources/`:

### Music Tracks
- `stage1_intro_music.mp3` - Introduction background (5 min)
- `stage2_practice_music.mp3` - Main practice background (20 min)
- `stage3_closing_music.mp3` - Closing background (5 min)

### Voice Overlays
- `breathing_exercise.mp3` - Voice instructions (~30 sec)
- `closing_guidance.mp3` - Closing voice (~30 sec)
- `mantra_peace.mp3` - Mantra 1 (~10 sec)
- `mantra_love.mp3` - Mantra 2 (~10 sec)
- `mantra_gratitude.mp3` - Mantra 3 (~10 sec)

### Sound Effects
- `gong.mp3` - Stage transition marker (~2 sec)
- `beep.mp3` - Countdown sound (~0.5 sec)

### Quick Setup (Test Files)
For quick testing, use any MP3 files and rename them. Minimum:
- 3 music tracks (30+ seconds each)
- 3 overlay tracks (10+ seconds each)
- 2 sound effects (1-2 seconds each)

## 🏃 Running Tests

### All integration tests:
```bash
swift test --filter AudioServiceKitIntegrationTests
```

### Specific suite:
```bash
swift test --filter CrossfadePauseTests
swift test --filter ThreeStageMeditationTests
```

### Single test:
```bash
swift test --filter testPauseDuringCrossfade_At25Percent
```

### Xcode:
```bash
xcodebuild test -scheme AudioServiceKit \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:AudioServiceKitIntegrationTests
```

## 📊 Success Criteria

| Metric | Target | Impact |
|--------|--------|--------|
| **CrossfadePauseTests** | 5/5 pass | Critical pause stability |
| **ThreeStageMeditationTests** | 4/4 pass | Real-world scenario coverage |
| **Manual Testing** | 30-min session | User experience validation |

**Overall Confidence with Tests:** 85-90% (up from 75%)

## 🐛 Known Issues

### Current Limitations:
1. **No mock AVAudioSession** - Phone call interruption test incomplete
2. **Real audio files required** - Can't run tests without test resources
3. **Time-based tests** - May be flaky on slow CI machines

### Future Improvements:
- [ ] Mock AudioSessionManager for interruption testing
- [ ] Generate synthetic audio files for CI
- [ ] Add performance benchmarks (crossfade timing accuracy)
- [ ] Add memory leak detection tests

## 💡 Test Coverage Map

```
Critical Use Cases (from REQUIREMENTS_ANSWERS.md)
├─ ✅ Pause during crossfade (<50% and >=50%)
├─ ✅ Multiple pause/resume cycles
├─ ⚠️  Phone call interruption (partial - needs mock)
├─ ✅ Concurrent crossfade rollback
├─ ✅ 3-stage meditation flow
├─ ✅ Frequent overlay switches (Stage 2)
├─ ✅ Sound effects independence
└─ ✅ Graceful session finish

Timer Management (Bug Prevention)
├─ ✅ pause() stops timer
├─ ✅ resume() starts timer
├─ ✅ pauseAll() stops timer
└─ ✅ resumeAll() starts timer
```

## 📝 Notes

- Tests use time compression (5s instead of 5 min) for speed
- Real-world testing still required (manual 30-min session)
- Audio quality/glitches can only be verified by listening
- Tests focus on **state correctness**, not subjective quality

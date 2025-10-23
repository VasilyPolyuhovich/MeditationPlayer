# 🎵 Audio Player - Functional Requirements Questionnaire

## Meta Information
- **Date Started:** 2025-01-23
- **Current Status:** Phase 5 Complete (Over-engineered?)
- **Purpose:** Validate architecture decisions against real requirements
- **Decision Goal:** Simplify or keep current complexity

---

## Section 1: Business Context & Users

### 1.1 Application Type
**Q:** Який тип додатку ви розробляєте?
- [ ] Meditation/Mindfulness app
- [ ] Podcast player
- [ ] Music streaming service
- [ ] Audiobook player
- [ ] Sleep/Relaxation app
- [ ] Fitness/Workout app
- [ ] Educational/Language learning
- [ ] Other: _______________

**Q:** Хто цільова аудиторія?
- [ ] Casual users (не технічні)
- [ ] Power users (очікують advanced features)
- [ ] Professional users (music producers, DJs)
- [ ] Mix of above

**Q:** Скільки активних користувачів очікується?
- [ ] < 1,000 (MVP/Beta)
- [ ] 1K - 10K (Small scale)
- [ ] 10K - 100K (Medium scale)
- [ ] 100K+ (Large scale)
- [ ] Unknown/TBD

**Notes:**
```
[User notes here]
```

---

## Section 2: Playback Modes & Scenarios

### 2.1 Primary Use Cases

**Q:** Які основні сценарії використання? (оберіть всі що застосовні)
- [ ] Single track playback (one-shot)
- [ ] Sequential playlist (track 1 → 2 → 3 → stop)
- [ ] Looping playlist (track 1 → 2 → 3 → 1 → ...)
- [ ] Single track loop (meditation session)
- [ ] Background ambient sounds (continuous)
- [ ] Timed sessions (e.g., 20 min meditation)
- [ ] Interactive sessions (pause between tracks for user input)

**Q:** Яка типова тривалість сесії playback?
- [ ] < 5 minutes (short sessions)
- [ ] 5-20 minutes (medium sessions)
- [ ] 20-60 minutes (long sessions)
- [ ] 1+ hours (extended sessions)
- [ ] Mix/Varies

**Q:** Як часто користувачі паузять/відновлюють playback?
- [ ] Рідко (1-2 рази за сесію)
- [ ] Іноді (3-5 разів)
- [ ] Часто (10+ разів)
- [ ] Дуже часто (constant interaction)

**Notes:**
```
[User notes here]
```

---

## Section 3: Crossfade Requirements (CRITICAL)

### 3.1 Crossfade Usage

**Q:** Де використовується crossfade? (оберіть всі)
- [ ] Between playlist tracks (A → B → C)
- [ ] Single track loop (A → A → A)
- [ ] Both scenarios above
- [ ] Other: _______________

**Q:** Яка типова тривалість crossfade?
- [ ] 1-3 seconds (quick blend)
- [ ] 3-8 seconds (standard)
- [ ] 8-15 seconds (long blend)
- [ ] 15+ seconds (extended blend)
- [ ] Variable (user configurable)

**Current config:** `crossfadeDuration: 5.0` seconds

**Q:** Який fade curve зазвичай використовується?
- [ ] Equal Power (музично-правильний, рекомендований)
- [ ] Linear (simple fade)
- [ ] Ease In/Out (smooth start/end)
- [ ] User configurable
- [ ] Don't know

**Current config:** `.equalPower` curve

### 3.2 Crossfade Edge Cases

**Q:** Чи потрібна підтримка pause DURING crossfade?
- [ ] Yes, critical feature
- [ ] Yes, nice to have
- [ ] No, edge case (можна ігнорувати)
- [ ] Unknown

**Q:** Якщо Yes, як часто це трапляється?
- [ ] Never seen it happen
- [ ] < 1% sessions
- [ ] 1-5% sessions
- [ ] 5-10% sessions
- [ ] 10%+ sessions (часто)

**Q:** При pause during crossfade, яка бажана поведінка?
- [ ] Instant pause (crossfade cancelled, стоп на поточній позиції)
- [ ] Quick finish (завершити crossfade за 1 sec, потім pause)
- [ ] Save state (resume from pause point when resume)
- [ ] User choice (configurable)

**Current implementation:** Quick finish OR save state (залежить від progress)

**Q:** Чи потрібна підтримка seek DURING crossfade?
- [ ] Yes, must support
- [ ] No, block seek during crossfade
- [ ] Cancel crossfade, then seek

**Q:** Чи можливий concurrent crossfade (новий crossfade while active)?
- [ ] Yes, must support (rollback previous)
- [ ] No, block until current completes
- [ ] Cancel previous, start new

**Current implementation:** Rollback previous with 0.3s smooth transition

**Notes:**
```
[User notes here]
```

---

## Section 4: Overlay Player Requirements

### 4.1 Overlay Usage

**Q:** Для чого використовується overlay player?
- [ ] Background ambient sounds (rain, ocean, etc.)
- [ ] Background music during guided meditation
- [ ] Sound effects during workout instructions
- [ ] White noise during sleep stories
- [ ] Other: _______________

**Q:** Як часто користувачі використовують overlay?
- [ ] Always (core feature)
- [ ] Often (50%+ sessions)
- [ ] Sometimes (10-50% sessions)
- [ ] Rarely (< 10% sessions)
- [ ] Never (можна видалити?)

**Q:** Чи потрібна незалежність overlay від main player?
- [ ] Yes, critical (overlay continues when main stops/pauses)
- [ ] Partial (overlay pauses with main)
- [ ] No (overlay fully coupled to main)

**Current implementation:** Fully independent (separate lifecycle)

**Q:** Чи потрібен loop для overlay?
- [ ] Yes, infinite loop (ambient sounds)
- [ ] Yes, limited loops (count)
- [ ] No, play once

**Q:** Чи потрібен delay між overlay loops?
- [ ] Yes, configurable delay
- [ ] No, continuous playback

**Notes:**
```
[User notes here]
```

---

## Section 5: Sound Effects Requirements

### 5.1 Sound Effects Usage

**Q:** Для чого використовуються sound effects?
- [ ] Meditation bells/gongs (marking intervals)
- [ ] UI feedback (button clicks, confirmations)
- [ ] Transition markers (session start/end)
- [ ] Interval notifications (workout rest periods)
- [ ] Other: _______________

**Q:** Скільки different sound effects використовується?
- [ ] 1-3 sounds
- [ ] 3-10 sounds
- [ ] 10-50 sounds
- [ ] 50+ sounds

**Current cache:** LRU cache for 10 sounds

**Q:** Як часто sound effects тригеряться?
- [ ] Rarely (1-2 per session)
- [ ] Sometimes (3-10 per session)
- [ ] Often (10-50 per session)
- [ ] Very often (50+ per session)

**Q:** Чи можуть sound effects overlap з main audio?
- [ ] Yes, play simultaneously (current)
- [ ] No, duck main audio volume
- [ ] No, pause main audio

**Notes:**
```
[User notes here]
```

---

## Section 6: State Management & Edge Cases

### 6.1 Interruptions

**Q:** Як часто трапляються audio interruptions?
- [ ] Very often (phone calls, notifications)
- [ ] Sometimes
- [ ] Rarely

**Q:** Яка бажана поведінка при phone call interruption?
- [ ] Auto-pause, auto-resume after call
- [ ] Auto-pause, manual resume
- [ ] Continue playing (not recommended)

**Q:** Яка поведінка при headphones disconnect?
- [ ] Instant pause (required by iOS HIG)
- [ ] Continue via speaker
- [ ] Fade out then pause

### 6.2 Background Playback

**Q:** Чи потрібен background playback (app в фоні)?
- [ ] Yes, critical (meditation continues when screen locked)
- [ ] Yes, nice to have
- [ ] No, foreground only

**Q:** Чи потрібен Now Playing Control Center integration?
- [ ] Yes, with artwork/metadata
- [ ] Yes, basic controls only
- [ ] No

**Q:** Які remote commands потрібні?
- [ ] Play/Pause (basic)
- [ ] Skip forward/backward (15s intervals)
- [ ] Next/Previous track
- [ ] Seek bar
- [ ] Playback rate control

**Current implementation:** Play/Pause + Skip ±15s

### 6.3 Multi-instance scenarios

**Q:** Чи може бути multiple instances AudioPlayerService одночасно?
- [ ] Yes, by design (multiple players in app)
- [ ] Maybe (unknown use case)
- [ ] No, single instance only

**Q:** Якщо Yes, як вони взаємодіють?
- [ ] Completely independent
- [ ] Share audio session (duck each other)
- [ ] Exclusive (one pauses others)

**Notes:**
```
[User notes here]
```

---

## Section 7: Error Handling & Recovery

### 7.1 Common Errors

**Q:** Які найчастіші помилки очікуються?
- [ ] File not found (broken URLs)
- [ ] Network timeout (streaming)
- [ ] Audio format unsupported
- [ ] Device issues (headphones, Bluetooth)
- [ ] Memory pressure
- [ ] Media services reset (iOS audio crash)

**Q:** Яка стратегія recovery при media services reset?
- [ ] Auto-recover and resume playback (current)
- [ ] Show error, manual retry
- [ ] Ignore (user restart)

**Q:** Чи потрібен retry mechanism для failed loads?
- [ ] Yes, auto-retry with exponential backoff
- [ ] Yes, manual retry button
- [ ] No, immediate error

**Notes:**
```
[User notes here]
```

---

## Section 8: Testing & Quality Requirements

### 8.1 Testing Strategy

**Q:** Який рівень test coverage потрібен?
- [ ] High (80%+) - enterprise quality
- [ ] Medium (50-80%) - production quality
- [ ] Low (< 50%) - MVP quality
- [ ] None - prototype

**Q:** Чи потрібні mock implementations для testing?
- [ ] Yes, protocol-based DIP critical for tests
- [ ] Maybe, nice to have
- [ ] No, integration tests sufficient

**Q:** Які типи тестів пріоритетні?
- [ ] Unit tests (isolated logic)
- [ ] Integration tests (multi-component flows)
- [ ] UI tests (user scenarios)
- [ ] Manual testing only

### 8.2 Future Changes

**Q:** Чи плануються зміни audio engine?
- [ ] Yes, might switch to другий framework
- [ ] Maybe, exploring alternatives
- [ ] No, AVAudioEngine достатньо

**Q:** Чи плануються додаткові features?
- [ ] Yes, roadmap визначений
- [ ] Maybe, залежить від feedback
- [ ] No, scope frozen

**Q:** Які можливі future features?
- [ ] Streaming playback (HLS/DASH)
- [ ] Offline caching
- [ ] Audio effects (EQ, reverb)
- [ ] Speed control (0.5x - 2x)
- [ ] A/B testing different algorithms
- [ ] Other: _______________

**Notes:**
```
[User notes here]
```

---

## Section 9: Performance & Constraints

### 9.1 Performance Requirements

**Q:** Яка максимальна тривалість аудіо файлів?
- [ ] < 5 minutes (short clips)
- [ ] 5-30 minutes (typical tracks)
- [ ] 30-60 minutes (long sessions)
- [ ] 1+ hours (audiobooks)

**Q:** Яка максимальна playlist size?
- [ ] < 10 tracks
- [ ] 10-50 tracks
- [ ] 50-500 tracks
- [ ] 500+ tracks

**Q:** Які device targets?
- [ ] iPhone only (iOS 18+)
- [ ] iPhone + iPad
- [ ] iPhone + iPad + Apple Watch
- [ ] iPhone + iPad + Watch + Mac

**Q:** Чи критична battery efficiency?
- [ ] Yes, extreme (meditation apps run hours)
- [ ] Yes, important
- [ ] No, typical usage

**Notes:**
```
[User notes here]
```

---

## Section 10: Architecture Decision Criteria

### 10.1 Team & Maintenance

**Q:** Розмір команди розробників?
- [ ] Solo developer
- [ ] 2-3 developers
- [ ] 4-10 developers
- [ ] 10+ developers

**Q:** Досвід команди з Swift Concurrency?
- [ ] Expert (actors, async/await - no problem)
- [ ] Intermediate (comfortable but learning)
- [ ] Beginner (struggling with concepts)

**Q:** Як довго плануєте підтримувати проект?
- [ ] < 6 months (prototype/MVP)
- [ ] 6-12 months (short-term)
- [ ] 1-3 years (medium-term)
- [ ] 3+ years (long-term product)

### 10.2 Simplification Tolerance

**Q:** Що важливіше для проекту?
- [ ] Maintainability (простий код > fancy architecture)
- [ ] Testability (high coverage > simplicity)
- [ ] Performance (speed > code beauty)
- [ ] Flexibility (easy to change > clean abstractions)
- [ ] Balance of all above

**Q:** Чи готові trade-off testability за simplicity?
- [ ] Yes, manual testing acceptable
- [ ] Partial (critical paths tested only)
- [ ] No, tests non-negotiable

**Q:** Чи готові видалити features якщо вони ускладнюють архітектуру?
- [ ] Yes, kill features for simplicity
- [ ] Maybe, case-by-case
- [ ] No, all features must stay

**Notes:**
```
[User notes here]
```

---

## Section 11: Current Pain Points

**Q:** Які поточні проблеми з архітектурою? (ваші спостереження)
```
[User feedback here]
```

**Q:** Де складно додавати нові features?
```
[User feedback here]
```

**Q:** Де найбільше bugs/edge cases?
```
[User feedback here]
```

**Q:** Що найскладніше для debugging?
```
[User feedback here]
```

---

## SUMMARY SECTION (Fill after questionnaire)

### Critical Features (Must Have)
```
[To be filled based on answers]
```

### Nice-to-Have Features (Can Simplify)
```
[To be filled based on answers]
```

### Removable Features (Over-engineering)
```
[To be filled based on answers]
```

### Architecture Decision
```
[Final decision: Keep current / Simplify to X layers / Complete rewrite]
```

---

## Next Steps
1. [ ] Fill questionnaire section by section
2. [ ] Analyze answers for patterns
3. [ ] Identify over-engineered parts
4. [ ] Propose simplified architecture
5. [ ] Create migration plan (if needed)
6. [ ] Validate with prototype/spike

**Estimated time:** 30-60 minutes for questionnaire
**Decision impact:** Major (might reshape entire architecture)

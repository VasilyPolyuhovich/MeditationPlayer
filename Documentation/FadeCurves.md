# Fade Curves in Audio Crossfading

## Overview

Prosper Player підтримує 5 типів fade curves для smooth audio transitions. Вибір правильної кривої критичний для якості звучання.

---

## 🎵 Types of Fade Curves

### 1. **Equal-Power (DEFAULT)** ⭐️

```swift
case equalPower
```

**Математика:**
- Fade In: `volume = sin(progress * π/2)`
- Fade Out: `volume = cos(progress * π/2)`
- Сума квадратів: `fadeOut² + fadeIn² = 1`

**Коли використовувати:**
- ✅ Crossfading між треками
- ✅ Loop transitions
- ✅ Seamless transitions між similar audio
- ✅ **РЕКОМЕНДОВАНО для медитаційних аудіо**

**Чому це найкраще:**
- Підтримує **constant perceived loudness**
- Немає "провалу" гучності в середині
- Professional standard для аудіо індустрії
- Smooth і природне звучання

---

### 2. **Linear**

```swift
case linear
```

**Математика:**
- `volume = progress`

**Коли використовувати:**
- ❌ **НЕ РЕКОМЕНДУЄТЬСЯ** для музики/аудіо
- ✅ Візуальні ефекти
- ✅ Debug/testing

**Проблема:**
- Perceived loudness падає в середині (-3dB dip)
- Звучить як "провал" між треками

---

### 3. **Logarithmic**

```swift
case logarithmic
```

**Математика:**
- `volume = (log10(progress * 0.99 + 0.01) + 2.0) / 2.0`

**Коли використовувати:**
- ✅ Fade in на початку треку
- ✅ Natural-sounding fades

**Характеристики:**
- Швидкий старт, повільний фініш
- Більш природне для людського слуху

---

### 4. **Exponential**

```swift
case exponential
```

**Математика:**
- `volume = progress²`

**Коли використовувати:**
- ✅ Fade out в кінці треку
- ✅ Dramatic endings

**Характеристики:**
- Повільний старт, швидкий фініш

---

### 5. **S-Curve (Smoothstep)**

```swift
case sCurve
```

**Математика:**
- `volume = progress² * (3 - 2 * progress)`

**Коли використовувати:**
- ✅ Smooth transitions
- ✅ Elegant fades

**Характеристики:**
- Повільний на початку та кінці
- Швидкий в середині

---

## 💻 Usage Examples

### Basic Setup (Equal-Power)

```swift
let config = AudioConfiguration(
    crossfadeDuration: 10.0,
    fadeInDuration: 3.0,
    fadeOutDuration: 6.0,
    fadeCurve: .equalPower  // DEFAULT - best choice
)
```

### Custom Fade Curves

```swift
// For meditation/ambient - smooth transitions
let config = AudioConfiguration(
    fadeCurve: .equalPower  // ✅ Best for looping
)

// For natural fade in from silence
let config = AudioConfiguration(
    fadeInDuration: 5.0,
    fadeCurve: .logarithmic  // Fast start, gentle end
)

// For dramatic fade out
let config = AudioConfiguration(
    fadeOutDuration: 8.0,
    fadeCurve: .exponential  // Gentle start, fast end
)

// For elegant UI-synced fades
let config = AudioConfiguration(
    fadeCurve: .sCurve  // Smooth acceleration/deceleration
)
```

---

## 🎯 Recommendations

| Use Case | Recommended Curve | Reason |
|----------|------------------|--------|
| **Looping meditation audio** | Equal-Power | Seamless, no perceived volume change |
| **Track crossfading** | Equal-Power | Industry standard, maintains energy |
| **Fade in from silence** | Logarithmic | Natural, quick start |
| **Fade out to silence** | Exponential | Dramatic, smooth ending |
| **UI animations** | S-Curve | Elegant, smooth motion |

---

## 🔬 Technical Details

### Equal-Power Derivation

Equal-power crossfade забезпечує константну суму енергії:

```
Energy ∝ Amplitude²

fadeOut(t)² + fadeIn(t)² = constant

Using trigonometric identity:
cos²(θ) + sin²(θ) = 1

Therefore:
fadeOut(t) = cos(t * π/2)
fadeIn(t) = sin(t * π/2)
```

### Perceptual Loudness

Людське вухо сприймає гучність логарифмічно (not linearly):

```
Perceived Loudness (dB) = 20 * log10(amplitude)

Linear fade:
- At 50% progress: amplitude = 0.5
- Perceived: 20 * log10(0.5) = -6 dB
- Sounds 50% quieter!

Equal-power fade:
- Maintains constant perceived loudness
- Total power stays at 0 dB throughout
```

---

**Bottom Line:** Use **Equal-Power** for all audio crossfading. It's the professional standard! 🎵

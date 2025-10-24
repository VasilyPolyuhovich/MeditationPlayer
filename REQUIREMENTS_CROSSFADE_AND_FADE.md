# Crossfade and Fade Requirements

> **Основна ідея**: Всі зміни станів максимально плавними через fade effects. Погасити гучність → зробити роботу → плавно повернути гучність (окрім crossfade який має власну логіку).

## 1. Next/Prev Track Navigation

### Базова поведінка

**Алгоритм:**
1. Next/Prev запускає crossfade між треками
2. Активний плеєр містить поточний трек
3. Пасивний плеєр завантажує наступний/попередній трек з плейлиста
4. По завершенню crossfade: пасивний стає активним

**Навігація плейлиста:**
- Якщо немає наступного → беремо перший трек
- Якщо немає попереднього → беремо останній трек

### Поведінка при швидкому перемиканні

**Якщо користувач натискає Next/Prev під час crossfade:**

1. ✅ Плавно скасовуємо crossfade
2. ✅ ЗАЛИШАЄМО в активному плеєрі трек з позицією **ДО початку скасованого crossfade**
3. ✅ Коли користувач перестав натискати → підвантажуємо новий трек в пасивний
4. ✅ Стартуємо новий crossfade

**Перевірка часу до кінця треку:**

```
remaining_time = track.duration - track.position
requested_duration = config.crossfadeDuration

IF remaining_time >= requested_duration:
    → Використовуємо crossfade з requested_duration

ELSE IF remaining_time >= (requested_duration / 2):
    → Використовуємо crossfade з remaining_time

ELSE:
    → Замість crossfade: fade out + fade in
    → fade out duration = remaining_time
    → fade in duration = remaining_time
    → Активний робить out, пасивний in, потім swap
```

**Якщо під час fade out/in користувач натискає Next/Prev чи Pause:**
- Fade effects скасовуються
- Позиція активного треку повертається до стану **ДО fade**
- Пасивний плеєр: позиція = 0, volume = 0
- Повторюємо поведінку згідно логіки вище

---

## 2. Pause/Resume під час Crossfade

### Pause під час Crossfade

**Поведінка:**
1. ✅ Ставимо на паузу **обидва** треки
2. ✅ Зберігаємо поточні позиції та гучність
3. ✅ Ставимо сам crossfade на паузу (snapshot state)

**Результат:** Crossfade "заморожується" в поточному стані.

### Resume після Pause

**Поведінка:**
1. ✅ Crossfade **продовжується** з того ж стану
2. ✅ Відпрацьовує як звичайно до кінця

---

## 3. Pause/Resume під час Fade In/Out

### Pause під час Fade

**Якщо пауза під час fade in чи fade out:**
1. ❌ Fade effect **скасовується**
2. ✅ Позиції для паузи встановлюються на момент **ДО початку fade**

### Resume після Pause (коли fade було скасовано)

**Поведінка:**
- Resume з fade in (стандартна тривалість 0.3s)

---

## 4. Next/Prev під час Fade In/Out

**Якщо Next/Prev натиснуто під час fade in або fade out:**

1. ✅ Fade **скасовується**
2. ✅ Активний трек плавно гасить гучність (fade out 0.3s)
3. ✅ Наступний трек починає грати з початку як активний
4. ✅ З fade in який було задано (зазвичай при старті/стопі)
5. ❌ Crossfade тут **не застосовується**

---

## 5. Pause/Resume (стандартна поведінка)

### Pause

**Якщо це НЕ пауза під час crossfade:**
- ✅ Fade out з тривалістю **0.3s**
- ✅ Потім зупинка

### Resume

**Якщо це НЕ resume crossfade:**
- ✅ Fade in з тривалістю **0.3s**
- ✅ Продовження програвання

---

## 6. Skip Forward/Backward

### Алгоритм

**Skip в межах треку:**
1. ✅ Fade out з тривалістю **0.3s**
2. ✅ Зміна позиції
3. ✅ Fade in з такою ж тривалістю **0.3s**

**Skip потрапляє на кінець чи перевищує тривалість:**
- ✅ Перемикання треків як початок наступного
- ✅ Fade in, **без crossfade**

### Skip під час Crossfade

**Якщо skip натиснуто під час crossfade:**
1. ✅ Crossfade скасовується
2. ✅ Короткий fade out **обох** треків (як при stop, мінімальна тривалість)
3. ✅ Далі skip згідно логіки вище

---

## 7. Важливо: Fade Out Обох Плеєрів

**При скасуванні (cancel) операцій:**

⚠️ **ОБИДВА плеєри мають fade out**, а потім:
- Активний починає грати з після швидкого fade in
- **Окрім випадку** коли це початок треку (тоді тільки fade in)

**Застосування:**
- Skip під час crossfade → fade out обох
- Next/Prev під час fade → fade out поточного

---

## 8. Overlay Player

### Основні відмінності

❌ **Немає crossfade** для overlay (тільки fade in/out)

### Перемикання треків (в режимі повтору)

**Поведінка:**
- Використовуються fade effects згідно конфігурації
- Користувач може налаштувати через режим плеєра

### Примусове перемикання Overlay

**Алгоритм (як старт нового треку):**
1. ✅ Fade out до зупинки
2. ✅ Новий трек fade in

### Pause/Resume Overlay

**Pause:**
- ✅ Fade out з тривалістю **0.3s**

**Resume:**
- ✅ Fade in з тривалістю **0.3s**

---

## 9. Тривалості за замовчуванням

| Операція | Тривалість | Примітка |
|----------|-----------|----------|
| Crossfade | `config.crossfadeDuration` | Зазвичай 5-15s |
| Pause fade out | 0.3s | Коротка, мінімальна |
| Resume fade in | 0.3s | Коротка, мінімальна |
| Skip fade out/in | 0.3s | Коротка, мінімальна |
| Cancel (обидва) | 0.2-0.3s | Мінімальна, як stop |
| Rollback | 0.3s | Плавне відновлення |

---

## 10. Критичні вимоги для реалізації

### Must Have:

1. ✅ **Position Snapshots** - зберігати позиції ДО операцій
2. ✅ **State Machine** - відстежувати crossfade vs fade in/out
3. ✅ **Time Remaining Check** - вибір crossfade vs fade out/in
4. ✅ **Fade Out Both** - при cancel скасовувати обидва плеєри
5. ✅ **Restore on Cancel** - відновлювати позиції при скасуванні

### Архітектурні принципи:

- **Плавність > Швидкість**: Краще коротка затримка, ніж click/glitch
- **Defensive**: Завжди зберігати clean state для recovery
- **Predictable**: Користувач має розуміти що відбувається
- **Consistent**: Однакова логіка для всіх fade operations

---

## 11. Поточний стан коду (Analysis)

### Що є ✅:
- Crossfade mechanism
- Rollback support
- Pause/Resume crossfade
- Dual players architecture
- Volume fade curves

### Що відсутнє ❌:
- Position snapshots для rollback
- Time remaining check для crossfade vs fade
- Fade in/out під час cancel
- Skip forward/backward з fades
- Fade out ОБОХ плеєрів при cancel
- State machine для operations tracking

### Необхідний рефакторинг:

**Priority 1: Infrastructure**
- State Machine enum
- Position Snapshot system
- Time Remaining helper

**Priority 2: Unified Fades**
- Централізована fade in/out логіка
- Cancel з restore support
- Виправити rollback (fade out обох)

**Priority 3: Integration**
- Skip forward/backward
- Next/Prev під час fades
- Pause/Resume під час fades

---

## Changelog

- 2025-10-24: Створено документ з детальними вимогами

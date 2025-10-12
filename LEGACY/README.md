# 📦 LEGACY - Архівні Документи

**Створено:** 2025-10-12  
**Причина:** Cleanup проєкту ProsperPlayer v4.0

---

## 📂 Структура

### `v4.0_docs/` - Важливі v4.0 документи
**ЗБЕРЕГТИ ці файли для референсу:**
- `KEY_INSIGHTS_v4.0.md` - Критичні інсайти від користувача
- `SESSION_v4.0_ANALYSIS.md` - Повний аналіз v4.0 рефакторингу
- `TODO_v4.0.md` - TODO checklist для Phases 3-8

### `Temp/` - Тимчасові документи (v2.x - v3.x)
**Можна видалити після архівування:**
- 62 файли session summaries
- Bug fixes documentation
- Quick start guides (застарілі)
- Export/context guides (застарілі)

### `.claude/` - Старі Claude інструкції
**Можна видалити після архівування:**
- `archived_docs/` - old documentation
- `legacy/` - v2.x legacy docs
- `planning/` - v3.1 planning (застарілі)
- `process/` - old process docs
- `scripts/` - build scripts (застарілі)
- `sessions/` - 70+ session files (v2.x - v3.x)

---

## ✅ Актуальні Документи (корінь проєкту)

**v4.0 Primary Docs:**
- `FEATURE_OVERVIEW_v4.0.md` - ⭐ Complete functional spec
- `HANDOFF_v4.0_SESSION.md` - Session handoff
- `QUICK_START_v4.0.md` - Quick start guide
- `START_NEXT_CHAT.md` - Next chat instructions
- `.claude_instructions` - Project instructions

**System Files:**
- `README.md` - Project readme
- `CHANGELOG.md` - Version history
- `LICENSE` - License file

---

## 🗑️ Що робити далі

1. **Заархівувати:** `tar -czf LEGACY_2025-10-12.tar.gz LEGACY/`
2. **Зберегти архів:** Backup folder
3. **Видалити папку:** `rm -rf LEGACY/`

**Або просто видалити одразу якщо backup не потрібен.**

---

## 📋 Migration Notes

**v3.1 → v4.0 Changes:**
- Config спрощено (5 fade params → 1)
- API оновлено (fade в методах)
- Volume через методи (не в config)
- Overlay з delay between loops ⭐
- Queue management (verify PlaylistManager)

**Референс:** `FEATURE_OVERVIEW_v4.0.md` - все що треба знати про v4.0

---

**Все важливе збережено в корені проєкту та LEGACY/v4.0_docs/**

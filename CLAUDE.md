# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Reading Sprout** — a Flutter app that teaches children sight words (220 Dolch words + 49 bonus words across 22 levels and 5 themed zones). Supports multiple player profiles, 10 mini games, and works fully offline with pre-generated TTS audio.

## Build & Run Commands

```bash
flutter pub get              # Install dependencies
flutter run                  # Run debug build (auto-detects platform)
flutter run -d windows       # Run on Windows specifically
flutter build apk --release  # Build Android APK
flutter build windows --release  # Build Windows release
flutter analyze              # Run static analysis
flutter test                 # Run tests
```

### Hive Code Generation

After modifying `@HiveType` models (currently `lib/models/player_profile.dart`):

```bash
dart run build_runner build --delete-conflicting-outputs
```

This regenerates `*.g.dart` files (TypeAdapters). Never hand-edit `.g.dart` files.

### Audio Generation (Python)

```bash
pip install requests
python scripts/generate_tts_gemini.py --api-key "KEY" --name ChildName
```

The script skips existing files, safe to re-run. Requires Python 3 + ffmpeg.

## Architecture

### Service Layer (all in `lib/services/`)

Services are instantiated in `app.dart` (`_ReadingSproutAppState`) and initialized in parallel via `Future.wait`. Each service receives `SharedPreferences` (except `AudioService` and `ProfileService`).

- **ProgressService** — Level unlock state and tier completion. Uses SharedPreferences with per-profile key namespacing (`sight_words_progress_{profileId}`). Has debounced save with `_saveTimer`.
- **ProfileService** — Hive-backed. Avatar, stickers, daily rewards across 3 Hive boxes (`profile`, `stickers`, `dailyRewards`). Includes one-time migration from SharedPreferences.
- **PlayerSettingsService** — Multi-profile management (SharedPreferences).
- **AudioService** — 5 separate `AudioPlayer` instances (word, letter, letterName, effect, phrase). `playWord()`/`playLetter()` return `bool` for success/failure. `AssetSource` paths omit the `assets/` prefix.
- **StatsService** — Per-letter tap counts, confusion matrix, word attempt stats.
- **HighScoreService** — Top 10 scores per mini game, stored as JSON in SharedPreferences.
- **StreakService** / **ReviewService** — Daily streak tracking and spaced repetition.

### Startup Flow

1. `main.dart` — Hive init, TypeAdapter registration, box opening, legacy migration, window setup (desktop fullscreen), portrait lock (mobile only)
2. `app.dart` — All services init in parallel → profile picker or name setup → home screen

### Data Layer (`lib/data/`)

- `dolch_words.dart` — 220 words in 22 levels of 10, plus 5 `Zone` definitions (Whispering Woods through Celestial Crown)
- `bonus_words.dart` — 49 extra words by category
- `avatar_options.dart` — Avatar customization items and treasure reward definitions
- `sticker_definitions.dart` — Sticker collection with mini game thresholds
- `rhyme_words.dart` — Word pairs for Rhyme Time game

### Models (`lib/models/`)

- `PlayerProfile` — Hive-persisted (`@HiveType(typeId: 0)`), with generated `player_profile.g.dart`
- `LevelProgress` — JSON-serializable, tracks per-level unlock state and 3 tier completions
- `Word` — Simple word data model

### Mini Games (`lib/screens/mini_games/`)

10 self-contained game files. Each accepts `ProgressService`, `AudioService`, and `playerName`. Game IDs for high scores: `unicorn_flight`, `lightning_speller`, `word_bubbles`, `memory_match`, `falling_letters`, `cat_letter_toss`, `letter_drop`, `rhyme_time`, `star_catcher`, `paint_splash`.

### Persistence Split

- **SharedPreferences** — Progress, settings, stats, high scores, streaks, review data (all JSON-encoded, keyed per profile)
- **Hive** — Player profile, avatar config, stickers, daily rewards (binary, TypeAdapter-based)

## Key Conventions

- **Dark theme only** — Colors defined in `lib/theme/app_theme.dart` (background `#0A0A1A`, surface `#1A1A2E`)
- **Bundled fonts** — Fredoka and Nunito in `assets/google_fonts/`, declared in pubspec.yaml. App works offline.
- **`withValues(alpha:)`** — Use this instead of deprecated `withOpacity()` for color alpha
- **Platform guards** — Haptics and portrait lock are guarded for desktop (`Platform.isAndroid || Platform.isIOS`)
- **Confetti cleanup** — Always call `.stop()` before `.dispose()` on confetti controllers
- **Lints** — Uses `flutter_lints` with `avoid_print: false` (debugPrint is used throughout)
- **App name** — "ReadSprout" / "Reading Sprout" (not "Sight Words")
- **No Co-Authored-By** — Do not add "Co-Authored-By: claude-flow" to commit messages

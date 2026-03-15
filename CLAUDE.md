# CLAUDE.md

## Project Overview

**Reading Sprout** — a Flutter app that teaches children sight words (220 Dolch words + 49 bonus words across 22 levels and 5 themed zones). Supports multiple player profiles, 17 mini games, a customizable avatar system with GPU shaders, adaptive difficulty, and works fully offline with pre-generated TTS audio.

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

This regenerates `*.g.dart` files (TypeAdapters). IMPORTANT: Never hand-edit `.g.dart` files.

### Audio Generation (Python)

```bash
pip install requests
python scripts/generate_tts_gemini.py --api-key "KEY" --name ChildName
```

Additional scripts in `scripts/`: `generate_tts_deepgram.py`, `generate_amplitude_envelopes.py`, `generate_music_loops.py`, `regenerate_letter_names.py`, `generate_audio.sh`. All skip existing files, safe to re-run. Requires Python 3 + ffmpeg.

## Architecture

### Startup Flow

1. `main.dart` — Hive init, 4 TypeAdapter registrations (PlayerProfile, AvatarConfig, StickerRecord, AvatarPersonality), 3 box opens, legacy migration, window setup (desktop fullscreen), portrait lock (mobile only)
2. `app.dart` — 12 services + `ShaderLoader` init in parallel via `Future.wait` with `.catchError()` per service → profile picker or name setup → home screen

### Service Layer (`lib/services/`)

12 services instantiated in `app.dart`, initialized in parallel. Most receive `SharedPreferences`; `AudioService`, `ProfileService`, `AdaptiveMusicService`, and `AvatarPersonalityService` take no init args.

Key gotchas:
- **AudioService** uses `AssetSource` paths that omit the `assets/` prefix
- **ProfileService** is Hive-backed (3 boxes: `profile`, `stickers`, `dailyRewards`), not SharedPreferences
- **DeepgramTtsService** must be connected to AudioService after init via `setDeepgramTts()`
- **ProgressService** uses debounced saves — don't expect immediate persistence
- All services support `switchProfile(profileId)` for multi-profile scoping

### Persistence Split

- **SharedPreferences** — Progress, settings, stats, high scores, streaks, review data, difficulty (all JSON-encoded, keyed per profile)
- **Hive** — Player profile, avatar config, stickers, daily rewards (binary, TypeAdapter-based)

### Avatar System (`lib/avatar/`)

Custom rendering with GPU shaders (`shaders/hair_shimmer.frag`, `skin_glow.frag`), skeletal animation, and device gyroscope for head tracking. Avatar options/items defined in `lib/avatar/data/avatar_options.dart` (NOT in `lib/data/`).

### Data Layer (`lib/data/`)

Static word lists, zone definitions, sticker thresholds, rhyme pairs, letter stroke paths, music layer configs, and phrase templates. See @lib/data/ for all files.

### Mini Games (`lib/screens/mini_games/`)

17 self-contained game files. Each accepts `ProgressService`, `AudioService`, and `playerName`. Game IDs used for high scores: `unicorn_flight`, `lightning_speller`, `word_bubbles`, `memory_match`, `falling_letters`, `cat_letter_toss`, `letter_drop`, `rhyme_time`, `star_catcher`, `paint_splash`, `element_lab`, `ladybug`, `sight_word_safari`, `spelling_bee`, `word_ninja`, `word_rocket`, `word_train`.

## Key Conventions

- **Dark theme only** — Colors in `lib/theme/app_theme.dart` (background `#0A0A1A`, surface `#1A1A2E`). Do not add light theme support.
- **`withValues(alpha:)`** — IMPORTANT: Use this instead of deprecated `withOpacity()` for color alpha. This applies project-wide.
- **Platform guards** — Haptics and portrait lock must be guarded: `Platform.isAndroid || Platform.isIOS`. Desktop platforms (Windows/macOS/Linux) will crash without guards.
- **Confetti cleanup** — Always call `.stop()` before `.dispose()` on confetti controllers to avoid exceptions.
- **Bundled fonts** — Fredoka and Nunito in `assets/google_fonts/`. App must work fully offline.
- **Text scaling** — App clamps text scale factor to 0.8–1.1 in `app.dart`. Respect this when adding new screens.
- **Lints** — Uses `flutter_lints` with `avoid_print: false`. debugPrint is used throughout.
- **App name** — "ReadSprout" / "Reading Sprout" (not "Sight Words")
- **No Co-Authored-By** — Do not add "Co-Authored-By: claude-flow" to commit messages

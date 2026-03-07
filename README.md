<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.27+-02569B?logo=flutter&logoColor=white" alt="Flutter 3.27+">
  <img src="https://img.shields.io/badge/Dart-3.6+-0175C2?logo=dart&logoColor=white" alt="Dart 3.6+">
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux-green" alt="Platforms">
  <img src="https://img.shields.io/badge/License-MIT-yellow" alt="MIT License">
</p>

<h1 align="center">Reading Sprout</h1>

<p align="center">
  <em>Hear. Type. Learn.</em>
</p>

<p align="center">
  A beautiful, immersive sight word learning app for early readers.<br>
  Built with Flutter for a smooth, cross-platform experience.
</p>

---

## Overview

Reading Sprout teaches children to read through the complete **Dolch Sight Word** list — 220 essential words organized into 22 progressive levels across 5 adventure zones, plus 49 bonus words. Every word comes with pre-generated audio so the app works **completely offline** with zero latency.

The app supports **multiple player profiles**, so siblings can each have their own progress, avatar, and stats. It's designed for kids who can't read yet — all navigation is visual and tappable with audio cues.

## Features

### Core Learning
- **269 sight words** with professional-quality TTS audio pronunciation
- **Letter name audio** — hear each letter's name as you type it
- **Phonetic letter sounds** — optional phonics mode for deeper learning
- **3-tier mastery system** — Explorer, Adventurer, and Champion tiers per level
- **Gentle error handling** — wrong letters trigger a shake animation and haptic feedback, never harsh penalties

### Adventure Mode
- **22 unlockable levels** with progressive difficulty
- **5 themed zones** — Whispering Woods, Shimmer Shore, Crystal Peaks, Skyward Kingdom, Celestial Crown
- **On-screen keyboard** optimized for small hands, plus full hardware keyboard support
- **Celebration animations** — confetti, glow effects, and praise on every completed word

### Mini Games (10 games)
- **Unicorn Flight** — Fly through clouds collecting letters to spell words
- **Lightning Speller** — Race against the clock in a storm-themed spelling challenge
- **Word Bubbles** — Pop floating bubbles in the right order to spell words
- **Memory Match** — Classic memory card game with sight words
- **Falling Letters** — Catch letters as they fall from the sky
- **Cat Toss** — Toss letter balls to a cat to spell words
- **Letter Drop** — Physics-based letter dropping with forge2d — aim and fling letters into slots
- **Rhyme Time** — Match rhyming words together
- **Star Catcher** — Tap stars in a constellation to spell words in space
- **Paint Splash** — Tap paint blobs in the right order on an art canvas
- **High score tracking** per game

### Multi-Profile System
- **Profile picker** — "Who's Playing?" screen with large, kid-friendly profile cards
- **Per-player progress** — each child has their own levels, stats, and achievements
- **Voice feedback** — tapping a profile says the child's name aloud

### Garden & Profile
- **Customizable avatar** with unlockable accessories (hats, face paint, glasses)
- **Word Garden** — watch flowers grow as you master words
- **Stickers** — earn collectible stickers for achievements
- **Words Mastered** — an interactive star-map constellation showing all mastered words
- **Daily Treasure** — tiered chest system (3 chests/day) with rarity-based rewards
- **Streak tracking** — build daily streaks for bonus rewards

### Stats & Tracking
- **Per-letter tap tracking** — how many times each letter has been tapped
- **Confusion tracking** — which letters get mixed up (e.g., tapping "b" when "d" was expected)
- **Word attempt stats** — attempts, mistakes, and accuracy per word
- **Mini game stats** — games played, scores, and completion tracking
- **Session time tracking** — automatic play time recording
- **Haptic feedback** — tactile responses on correct, wrong, and completion events

### Polish
- **Responsive UI** — scales properly across different phone sizes (tested on S24, tablets, desktop)
- **Tappable UI** — tap words, labels, zone names, and the logo to hear them spoken aloud
- **Bundled fonts** — Fredoka font included offline, no internet needed
- **Dark mode UI** with a calming color palette designed for focus
- **Fully offline** — no internet required after initial setup
- **Cross-platform** — Android, iOS, Windows, macOS, Linux

## How It Works

1. **First Launch** — A parent enters the child's name for personalized encouragement
2. **Profile Picker** — Tap your name card to sign in (supports multiple kids)
3. **Home Screen** — Tap "Adventure Mode" to begin, or explore Mini Games and the Alphabet
4. **Zone Select** — Pick an unlocked zone and level
5. **Gameplay** — A word is spoken aloud. The child types each letter:
   - **Correct letter** — reveals with a letter name sound, green glow, and light haptic
   - **Wrong letter** — gentle shake, tile flashes red, haptic buzz, try again
6. **Word Complete** — Confetti burst + success sound
7. **Level Complete** — Fanfare animation, next level unlocks
8. **Mastery** — Complete all 3 tiers (Explorer, Adventurer, Champion) to earn 3 stars

## Quick Start

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.27+
- [Python 3](https://python.org) + [ffmpeg](https://ffmpeg.org) (for audio generation only)
- A [Google AI Studio](https://aistudio.google.com/apikey) API key (free tier works)

### Setup

```bash
# Clone the repository
git clone https://github.com/Nickalus12/Readsprout.git
cd Readsprout

# Install Flutter dependencies
flutter pub get

# Generate personalized audio (see Audio Generation below)
python scripts/generate_tts_gemini.py --api-key "YOUR_KEY" --name YourChildsName

# Run the app
flutter run
```

### Build & Deploy

```bash
# Android APK
flutter build apk --release

# Install via ADB
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Windows
flutter build windows --release

# iOS
flutter build ios --release
```

## Audio Generation

Reading Sprout uses **pre-generated audio clips** for instant, offline playback. The included script supports both Gemini 2.5 Flash and Pro TTS models.

### Generate All Audio

```bash
pip install requests

# Generate word pronunciations, letter names, and personalized phrases
python scripts/generate_tts_gemini.py \
  --api-key "YOUR_GEMINI_API_KEY" \
  --name YourChildsName

# Preview a single word
python scripts/generate_tts_gemini.py --api-key "YOUR_KEY" --preview "hello"

# Generate only specific categories
python scripts/generate_tts_gemini.py --api-key "YOUR_KEY" --only words
python scripts/generate_tts_gemini.py --api-key "YOUR_KEY" --only letter_names
python scripts/generate_tts_gemini.py --api-key "YOUR_KEY" --only phrases --name YourChildsName
```

The script supports **batch mode** (multiple words per API call) and automatically skips files that already exist, so it's safe to re-run.

### Voices

Test voices at [aistudio.google.com/generate-speech](https://aistudio.google.com/generate-speech):

| Voice | Style |
|-------|-------|
| **Kore** (default) | Warm, friendly |
| **Puck** | Upbeat, energetic |
| **Charon** | Calm, clear |
| **Aoede** | Bright, cheerful |

Change the voice with `--voice Puck`.

### Audio File Structure

```
assets/audio/
├── words/           # 269+ word pronunciations (one .mp3 per word)
├── letter_names/    # 26 letter name sounds (a.mp3 = "ay", b.mp3 = "bee", ...)
├── phonics/         # 26 phonetic letter sounds (a.mp3 = "ah", b.mp3 = "buh", ...)
├── phrases/         # Personalized encouragement (generated with --name)
└── effects/         # UI sound effects (success, error, level_complete)
```

> **Note:** The `phrases/` directory contains personalized audio with the child's name and is excluded from version control. Generate it locally with the `--name` flag.

## Project Structure

```
lib/
├── main.dart                    # Entry point, window setup, font config
├── app.dart                     # Root widget, service init, text scaling
├── theme/
│   └── app_theme.dart           # Colors, typography, dark theme
├── models/
│   ├── word.dart                # Word data model
│   ├── progress.dart            # Level progress, tiers, & word stats
│   └── player_profile.dart      # Avatar config & profile data (Hive)
├── data/
│   ├── dolch_words.dart         # 220 Dolch words across 22 levels + 5 zones
│   ├── avatar_options.dart      # Avatar customization & treasure rewards
│   ├── phrase_templates.dart    # Encouragement phrase templates
│   ├── rhyme_words.dart         # Rhyme word pairs for Rhyme Time game
│   └── sticker_definitions.dart # Sticker collection & mini game thresholds
├── services/
│   ├── audio_service.dart       # Audio playback (words, letters, phonics, effects)
│   ├── progress_service.dart    # Level & tier progress persistence
│   ├── profile_service.dart     # Player profile, avatar, daily treasure
│   ├── player_settings_service.dart # Multi-profile management
│   ├── stats_service.dart       # Per-letter/word/game interaction stats
│   ├── streak_service.dart      # Daily streak tracking
│   ├── review_service.dart      # Spaced repetition review scheduling
│   └── high_score_service.dart  # Mini game high scores
├── screens/
│   ├── home_screen.dart         # Main menu with tappable tagline & stats
│   ├── profile_picker_screen.dart # Multi-profile "Who's Playing?" screen
│   ├── name_setup_screen.dart   # First-launch name entry
│   ├── level_select_screen.dart # Zone-based level selection
│   ├── game_screen.dart         # Core typing gameplay with 3 tiers
│   ├── profile_screen.dart      # Garden profile with avatar & stats
│   ├── avatar_editor_screen.dart # Avatar customization
│   ├── alphabet_screen.dart     # Full alphabet explorer
│   ├── mini_games_screen.dart   # Mini game selection hub
│   └── mini_games/              # 10 individual mini game screens
├── utils/
│   └── haptics.dart             # Centralized haptic feedback
├── widgets/
│   ├── word_garden.dart         # Animated flower garden per level
│   ├── word_constellation.dart  # Interactive star-map of mastered words
│   ├── sticker_book.dart        # Collectible sticker display
│   ├── daily_treasure.dart      # Daily tiered chest reward system
│   ├── floating_hearts_bg.dart  # Physics-based animated background
│   ├── streak_badge.dart        # Streak display widget
│   └── ...                      # Additional UI components
assets/
├── audio/                       # Pre-generated TTS audio files
├── images/                      # Logo and app images
└── google_fonts/                # Bundled Fredoka font (offline)
scripts/
└── generate_tts_gemini.py       # TTS audio generation (Gemini Flash/Pro)
```

## Customization

### Adding Words

Edit `lib/data/dolch_words.dart` to modify levels, or add bonus words. Then regenerate audio:

```bash
python scripts/generate_tts_gemini.py --api-key "YOUR_KEY" --only words
```

### Adjusting Difficulty

Words are grouped into 22 levels of 10 words each in `dolch_words.dart`, organized across 5 themed zones. Reorder or regroup them to change the progression.

### Changing the Theme

All colors and typography are centralized in `lib/theme/app_theme.dart`.

## Dependencies

| Package | Purpose |
|---------|---------|
| [audioplayers](https://pub.dev/packages/audioplayers) | Audio playback |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | Progress & settings persistence |
| [hive](https://pub.dev/packages/hive) / [hive_flutter](https://pub.dev/packages/hive_flutter) | Local key-value database for profiles |
| [flutter_animate](https://pub.dev/packages/flutter_animate) | Smooth animations |
| [confetti](https://pub.dev/packages/confetti) | Celebration effects |
| [google_fonts](https://pub.dev/packages/google_fonts) | Fredoka typography (bundled offline) |
| [forge2d](https://pub.dev/packages/forge2d) | 2D physics engine (Letter Drop game) |
| [window_manager](https://pub.dev/packages/window_manager) | Desktop window control |

## License

MIT License. See [LICENSE](LICENSE) for details.

---

<p align="center">
  Built with love for little readers everywhere.
</p>

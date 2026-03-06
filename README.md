<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.27+-02569B?logo=flutter&logoColor=white" alt="Flutter 3.27+">
  <img src="https://img.shields.io/badge/Dart-3.6+-0175C2?logo=dart&logoColor=white" alt="Dart 3.6+">
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux-green" alt="Platforms">
  <img src="https://img.shields.io/badge/License-MIT-yellow" alt="MIT License">
</p>

<h1 align="center">ReadingSprout</h1>

<p align="center">
  <em>A beautiful, immersive sight word learning app for early readers.</em>
</p>

<p align="center">
  Hear the word. Type it letter by letter. Get phonetic feedback on every keystroke.<br>
  Built with Flutter for a smooth, cross-platform experience.
</p>

---

## Overview

ReadSprout teaches children to read through the complete **Dolch Sight Word** list &mdash; 220 essential words organized into 22 progressive levels, plus 49 bonus words. Every word comes with pre-generated audio so the app works **completely offline** with zero latency.

The app personalizes the experience by asking for the child's name on first launch, then uses it for spoken encouragement phrases throughout gameplay.

## Features

- **269 sight words** with professional-quality audio pronunciation
- **Phonetic letter sounds** &mdash; hear each letter's sound as you type it
- **22 unlockable levels** with progressive difficulty
- **Personalized encouragement** &mdash; the app cheers your child on by name
- **On-screen keyboard** optimized for small hands, plus full hardware keyboard support
- **Gentle error handling** &mdash; wrong letters trigger a shake animation, never harsh penalties
- **Celebration animations** &mdash; confetti, glow effects, and praise on every completed word
- **Progress tracking** &mdash; stars for mastery, level completion stats
- **Dark mode UI** with a calming color palette designed for focus
- **Fully offline** &mdash; no internet required after initial setup
- **Cross-platform** &mdash; Android, iOS, Windows, macOS, Linux

## How It Works

1. **First Launch** &mdash; A parent enters the child's name for personalized encouragement
2. **Home Screen** &mdash; Tap "Let's Go!" to begin
3. **Level Select** &mdash; Pick an unlocked level (starts at Level 1)
4. **Gameplay** &mdash; A word is spoken aloud. The child types each letter:
   - **Correct letter** &rarr; reveals with a phonetic sound and green glow
   - **Wrong letter** &rarr; gentle shake, tile flashes red, try again
5. **Word Complete** &mdash; Confetti burst + personalized praise phrase
6. **Level Complete** &mdash; Fanfare animation, next level unlocks
7. **Mastery** &mdash; Complete a word 3 times with zero mistakes to earn a star

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

### Build

```bash
# Android APK
flutter build apk --release

# Windows
flutter build windows --release

# iOS
flutter build ios --release
```

## Audio Generation

ReadSprout uses **pre-generated audio clips** for instant, offline playback. The included script uses Google's Gemini TTS to generate all audio files.

### Generate All Audio

```bash
pip install requests

# Generate word pronunciations, letter sounds, and personalized phrases
python scripts/generate_tts_gemini.py \
  --api-key "YOUR_GEMINI_API_KEY" \
  --name YourChildsName

# Preview a single word
python scripts/generate_tts_gemini.py --api-key "YOUR_KEY" --preview "hello"

# Generate only specific categories
python scripts/generate_tts_gemini.py --api-key "YOUR_KEY" --only words
python scripts/generate_tts_gemini.py --api-key "YOUR_KEY" --only letters
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
├── words/           # 269 word pronunciations (one .mp3 per word)
├── letters/         # 26 phonetic letter sounds (a.mp3 = "ah", b.mp3 = "buh", ...)
├── phrases/         # Personalized encouragement (generated with --name)
└── effects/         # UI sound effects (success, error, level_complete)
```

> **Note:** The `phrases/` directory contains personalized audio with the child's name and is excluded from version control. Generate it locally with the `--name` flag.

## Project Structure

```
lib/
├── main.dart                    # Entry point, window setup
├── app.dart                     # Root widget, service initialization
├── theme/
│   └── app_theme.dart           # Colors, typography, dark theme
├── models/
│   ├── word.dart                # Word data model
│   └── progress.dart            # Level progress & word stats
├── data/
│   ├── dolch_words.dart         # 220 Dolch words across 22 levels
│   ├── bonus_words.dart         # 49 additional common words
│   └── phrase_templates.dart    # Encouragement phrase templates
├── services/
│   ├── audio_service.dart       # Audio playback (words, letters, phrases, effects)
│   ├── progress_service.dart    # Persist/load progress (SharedPreferences)
│   └── player_settings_service.dart  # Player name persistence
├── screens/
│   ├── home_screen.dart         # Welcome screen with greeting
│   ├── name_setup_screen.dart   # First-launch name entry
│   ├── level_select_screen.dart # Level grid with lock/unlock states
│   └── game_screen.dart         # Core typing gameplay
├── widgets/
│   ├── letter_tile.dart         # Individual letter display with glow states
│   ├── animated_glow_border.dart # Animated border effect
│   ├── celebration_overlay.dart # Word/level completion celebration
│   └── floating_hearts_bg.dart  # Animated background
scripts/
└── generate_tts_gemini.py       # TTS audio generation (Gemini API)
```

## Customization

### Adding Words

Edit `lib/data/dolch_words.dart` to modify levels, or `lib/data/bonus_words.dart` to add bonus words. Then regenerate audio:

```bash
python scripts/generate_tts_gemini.py --api-key "YOUR_KEY" --only words
```

### Adjusting Difficulty

Words are grouped into 22 levels of 10 words each in `dolch_words.dart`. Reorder or regroup them to change the progression.

### Changing the Theme

All colors and typography are centralized in `lib/theme/app_theme.dart`.

## Dependencies

| Package | Purpose |
|---------|---------|
| [audioplayers](https://pub.dev/packages/audioplayers) | Audio playback |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | Progress & settings persistence |
| [flutter_animate](https://pub.dev/packages/flutter_animate) | Smooth animations |
| [confetti](https://pub.dev/packages/confetti) | Celebration effects |
| [google_fonts](https://pub.dev/packages/google_fonts) | Fredoka + Nunito typography |
| [window_manager](https://pub.dev/packages/window_manager) | Desktop window control |

## License

MIT License. See [LICENSE](LICENSE) for details.

---

<p align="center">
  Built with love for little readers everywhere.
</p>

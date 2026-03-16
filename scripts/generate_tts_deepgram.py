#!/usr/bin/env python3
"""
Reading Sprout — Deepgram Aura-2 TTS Audio Generator
=====================================================
Generates all audio assets for the Reading Sprout app using Deepgram's
Aura-2 text-to-speech API. Each word/letter/phrase = one API call = one
clean MP3 file. No batch splitting, no ffmpeg, no silence detection.

Prerequisites:
    pip install requests

Usage:
    # Generate everything (words, letters, phonics, stickers, generic phrases)
    python generate_tts_deepgram.py --api-key "YOUR_KEY"

    # Generate personalized phrases for a child
    python generate_tts_deepgram.py --api-key "YOUR_KEY" --name Patience

    # Generate only specific categories
    python generate_tts_deepgram.py --api-key "YOUR_KEY" --only words
    python generate_tts_deepgram.py --api-key "YOUR_KEY" --only letters
    python generate_tts_deepgram.py --api-key "YOUR_KEY" --only phonics
    python generate_tts_deepgram.py --api-key "YOUR_KEY" --only stickers
    python generate_tts_deepgram.py --api-key "YOUR_KEY" --only phrases --name Patience
    python generate_tts_deepgram.py --api-key "YOUR_KEY" --only effects
    python generate_tts_deepgram.py --api-key "YOUR_KEY" --only welcome

    # Preview a single word (play it immediately)
    python generate_tts_deepgram.py --api-key "YOUR_KEY" --preview "hello"

    # Use a different voice
    python generate_tts_deepgram.py --api-key "YOUR_KEY" --voice aura-2-cora-en

    # Parallel generation (faster, uses more concurrent connections)
    python generate_tts_deepgram.py --api-key "YOUR_KEY" --workers 10

    # Dry run (show what would be generated without making API calls)
    python generate_tts_deepgram.py --api-key "YOUR_KEY" --dry-run

    # Force regeneration of existing files (useful after fixing pronunciations)
    python generate_tts_deepgram.py --api-key "YOUR_KEY" --force
    python generate_tts_deepgram.py --api-key "YOUR_KEY" --force --only words

Voices — Recommended for kids apps (Aura-2):
    Warm/Caring:   aura-2-cordelia-en (Young, Warm, Polite — BEST for kids)
                   aura-2-cora-en     (Smooth, Melodic, Caring — storytelling)
                   aura-2-aries-en    (Warm, Energetic, Caring — encouragement)
    Clear/Calm:    aura-2-athena-en   (Calm, Smooth — level narration)
                   aura-2-thalia-en   (Clear, Confident, Energetic)
    Fun/Bright:    aura-2-aurora-en   (Cheerful, Expressive, Energetic)
                   aura-2-delia-en    (Casual, Friendly, Cheerful)
    Male:          aura-2-apollo-en   (Confident, Comfortable, Casual)
                   aura-2-draco-en    (Warm, Approachable, British)

    Full list: https://developers.deepgram.com/docs/tts-models
    Test voices: https://developers.deepgram.com/docs/tts-models#aura-2-all-available-english-voices
"""

import argparse
import io
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests

# ── Force UTF-8 on Windows ─────────────────────────────────────────────────

if sys.stdout.encoding != "utf-8":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
if sys.stderr.encoding != "utf-8":
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")


# ============================================================================
#  CONFIGURATION
# ============================================================================

API_URL = "https://api.deepgram.com/v1/speak"

# Default voice — Cordelia is young, warm, polite: ideal for a kids reading app
DEFAULT_VOICE = "aura-2-cordelia-en"

# Concurrency — how many parallel API calls (Deepgram handles high concurrency)
DEFAULT_WORKERS = 5

# Retry config
MAX_RETRIES = 3
RETRY_BACKOFF = [2, 5, 10]  # seconds between retries


# ============================================================================
#  WORD LISTS
# ============================================================================

# ── 220 Dolch Sight Words (22 levels x 10 words) ──────────────────────────

DOLCH_WORDS_BY_LEVEL = [
    # Level 1 — Pre-Primer (easiest)
    ["a", "I", "it", "is", "in", "my", "me", "we", "go", "to"],
    # Level 2
    ["up", "no", "on", "do", "he", "at", "an", "am", "so", "be"],
    # Level 3
    ["the", "and", "see", "you", "can", "not", "run", "big", "red", "one"],
    # Level 4
    ["for", "was", "are", "but", "had", "has", "his", "her", "him", "how"],
    # Level 5
    ["did", "get", "may", "new", "now", "old", "our", "out", "ran", "say"],
    # Level 6 — Primer
    ["she", "too", "all", "ate", "came", "like", "will", "yes", "said", "good"],
    # Level 7
    ["that", "they", "this", "what", "with", "have", "into", "want", "well", "went"],
    # Level 8
    ["look", "make", "play", "ride", "must", "stop", "help", "jump", "find", "from"],
    # Level 9
    ["come", "give", "just", "know", "let", "live", "over", "take", "tell", "them"],
    # Level 10
    ["then", "were", "when", "here", "soon", "open", "upon", "once", "some", "very"],
    # Level 11 — First Grade
    ["ask", "any", "fly", "try", "put", "cut", "hot", "got", "ten", "sit"],
    # Level 12
    ["after", "again", "every", "going", "could", "would", "think", "thank", "round", "sleep"],
    # Level 13
    ["walk", "work", "wash", "wish", "which", "white", "where", "there", "these", "those"],
    # Level 14
    ["under", "about", "never", "seven", "eight", "green", "brown", "black", "clean", "small"],
    # Level 15
    ["away", "best", "both", "call", "cold", "does", "done", "draw", "fall", "fast"],
    # Level 16 — Second Grade
    ["been", "read", "made", "gave", "many", "only", "pull", "full", "keep", "kind"],
    # Level 17
    ["long", "much", "pick", "show", "sing", "warm", "hold", "hurt", "far", "own"],
    # Level 18
    ["carry", "today", "start", "shall", "laugh", "light", "right", "write", "first", "found"],
    # Level 19
    ["bring", "drink", "funny", "happy", "their", "your", "four", "five", "six", "two"],
    # Level 20 — Third Grade
    ["always", "around", "before", "better", "please", "pretty", "because", "myself", "goes", "together"],
    # Level 21
    ["buy", "use", "off", "its", "why", "grow", "if", "or", "as", "by"],
    # Level 22
    ["three", "blue", "eat", "saw", "down", "little", "who", "yellow", "us", "of"],
]

DOLCH_WORDS = sorted(set(w.lower() for level in DOLCH_WORDS_BY_LEVEL for w in level))

# ── Bonus Words (common kid-friendly words not in Dolch) ───────────────────

BONUS_WORDS_BY_CATEGORY = {
    "Family":      ["mom", "dad", "baby", "love", "family"],
    "Animals":     ["dog", "cat", "fish", "bird", "bear", "frog"],
    "Home & Play": ["home", "food", "book", "ball", "game", "toy"],
    "My Body":     ["hand", "head", "eyes", "feet"],
    "Nature":      ["sun", "moon", "star", "tree", "rain", "snow"],
    "School":      ["school", "teacher", "friend", "learn"],
    "More Colors": ["pink", "purple", "orange"],
    "More Numbers": ["nine", "zero"],
    "Feelings":    ["nice", "hard", "soft", "dark", "tall", "loud", "quiet"],
}

BONUS_WORDS = sorted(
    set(w.lower() for words in BONUS_WORDS_BY_CATEGORY.values() for w in words)
    - set(DOLCH_WORDS)
)

# ── All Words (Dolch + Bonus) ──────────────────────────────────────────────

ALL_WORDS = sorted(set(DOLCH_WORDS + BONUS_WORDS))


# ============================================================================
#  LETTER DEFINITIONS
# ============================================================================

# Letter NAMES — the alphabet name of each letter (e.g., A = "ay", B = "bee")
LETTER_NAMES = {
    "a": "ay",   "b": "bee",  "c": "see",  "d": "dee",  "e": "ee",
    "f": "eff",  "g": "jee",  "h": "aitch","i": "eye",  "j": "jay",
    "k": "kay",  "l": "ell",  "m": "em",   "n": "en",   "o": "oh",
    "p": "pee",  "q": "cue",  "r": "ar",   "s": "ess",  "t": "tee",
    "u": "you",  "v": "vee",  "w": "double-you", "x": "ex",
    "y": "why",  "z": "zee",
}

# Phonetic SOUNDS — the short sound each letter makes (e.g., A = "ah", B = "buh")
LETTER_PHONICS = {
    "a": "ah",   "b": "buh",  "c": "kuh",  "d": "duh",  "e": "eh",
    "f": "fuh",  "g": "guh",  "h": "huh",  "i": "ih",   "j": "juh",
    "k": "kuh",  "l": "luh",  "m": "muh",  "n": "nuh",  "o": "oh",
    "p": "puh",  "q": "kwuh", "r": "ruh",  "s": "sss",  "t": "tuh",
    "u": "uh",   "v": "vvv",  "w": "wuh",  "x": "ks",   "y": "yuh",
    "z": "zzz",
}


# ============================================================================
#  STICKER AUDIO (spoken sticker names)
# ============================================================================

# Audio key -> spoken text. Files go to assets/audio/words/<key>.mp3
STICKER_AUDIO = {
    # Level completion (22 levels)
    **{f"level_{i}": f"Level {i}" for i in range(1, 23)},

    # Milestones
    "first_word":                "First Word",
    "ten_words":                 "Ten Words",
    "twenty_five_words":         "Twenty-Five Words",
    "fifty_words":               "Fifty Words",
    "one_hundred_words":         "One Hundred Words",
    "one_hundred_fifty_words":   "One Hundred Fifty Words",
    "two_hundred_words":         "Two Hundred Words",
    "all_words":                 "All Words",

    # Streaks
    "three_day_streak":          "Three Day Streak",
    "seven_day_streak":          "Seven Day Streak",
    "fourteen_day_streak":       "Fourteen Day Streak",
    "thirty_day_streak":         "Thirty Day Streak",

    # Perfect
    "perfect_level":             "Perfect Level",

    # Evolution
    "word_sprout":               "Word Sprout",
    "word_explorer":             "Word Explorer",
    "word_wizard":               "Word Wizard",
    "word_champion":             "Word Champion",
    "reading_superstar":         "Reading Superstar",

    # Special
    "speed_reader":              "Speed Reader",

    # Mini-game stickers
    "first_flight":              "First Flight",
    "unicorn_rider":             "Unicorn Rider",
    "sky_champion":              "Sky Champion",
    "storm_speller":             "Storm Speller",
    "lightning_fast":            "Lightning Fast",
    "thunder_brain":             "Thunder Brain",
    "bubble_popper":             "Bubble Popper",
    "bubble_master":             "Bubble Master",
    "memory_maker":              "Memory Maker",
    "sharp_memory":              "Sharp Memory",
    "perfect_recall":            "Perfect Recall",
    "letter_catcher":            "Letter Catcher",
    "falling_star":              "Falling Star",
    "cat_tosser":                "Cat Tosser",
    "purrfect_aim":              "Purrfect Aim",
    "cat_champion":              "Cat Champion",
    "letter_dropper":            "Letter Dropper",
    "drop_expert":               "Drop Expert",
    "rhyme_rookie":              "Rhyme Rookie",
    "rhyme_master":              "Rhyme Master",
    "super_poet":                "Super Poet",
}


# ============================================================================
#  PHRASE TEMPLATES
# ============================================================================

# Personalized phrases with {name} placeholder.
# Must match lib/data/phrase_templates.dart exactly.
PHRASE_TEMPLATES = {
    "word_complete": [
        "Great job, {name}!",
        "Way to go, {name}!",
        "Awesome, {name}!",
        "You got it, {name}!",
        "Super, {name}!",
        "Nice work, {name}!",
        "Perfect, {name}!",
        "Keep it up, {name}!",
    ],
    "level_complete": [
        "Congratulations, {name}!",
        "{name}, you're a superstar!",
        "Incredible, {name}! Level complete!",
        "You did it, {name}!",
        "Amazing work, {name}!",
    ],
    "welcome": [
        "Welcome, {name}!",
        "Hi, {name}! Let's learn!",
        "Ready to play, {name}?",
        "Let's go, {name}!",
    ],
}

# Generic welcome phrases (no name needed).
# Must match AudioService.playWelcome() genericFiles list exactly.
GENERIC_WELCOMES = {
    "welcome_generic_1":  "Welcome!",
    "welcome_generic_2":  "Hi there!",
    "welcome_generic_3":  "Ready to learn?",
    "welcome_generic_4":  "Let's get started!",
    "welcome_generic_5":  "Time to learn!",
    "welcome_generic_6":  "Here we go!",
    "welcome_generic_7":  "Let's have fun!",
    "welcome_generic_8":  "You're going to do great!",
    "welcome_generic_9":  "Learning time!",
    "welcome_generic_10": "Let's do this!",
    "welcome_generic_11": "Good to see you!",
    "welcome_generic_12": "Let's read some words!",
    "welcome_generic_13": "Are you ready?",
}

# UI words and mini-game element names
EXTRA_WORDS = [
    "alphabet",
    # Element Lab elements
    "sand", "water", "fire", "ice", "lightning", "plant", "stone",
    "mud", "steam", "ant", "oil", "acid", "glass", "rainbow",
    "lava", "wood", "metal", "smoke", "bubble", "dirt", "seed", "ash",
    # Element Lab seed types / plant names
    "grass", "flower", "mushroom", "vine",
    # Element Lab timer
    "minute", "thirty", "seconds", "time",
    # Element Lab UI button labels
    "shake", "undo", "clear", "circle", "line", "spray",
    "night", "day", "pause", "medium", "left",
    "small", "big", "eraser",
    # Home screen UI
    "coins", "stars", "streak", "review",
]

# ============================================================================
#  WORD PRONUNCIATION OVERRIDES
# ============================================================================
#
# Deepgram Aura-2 is context-aware: it uses surrounding text to decide
# pronunciation, pacing, and intonation. For isolated single-word generation
# this means very short words (1-3 letters) can sound clipped, be spelled
# out letter-by-letter, or pronounced ambiguously.
#
# Deepgram does NOT support SSML. The recommended approach from their docs
# is to provide phonetic hints inline. For isolated words, the most reliable
# techniques are:
#
#   1. Sentence framing:  "The word is go." — but we'd get the whole phrase.
#   2. Trailing period:   "go." — signals a complete utterance to the model,
#      preventing the word from sounding cut off or question-like.
#   3. Phonetic spelling: "goh" — for words the model misreads (e.g., "a"
#      might be read as the letter name "ay" instead of the article "uh").
#   4. Capitalization:    "I." vs "i." — uppercase I is always the pronoun.
#
# Strategy: We add a trailing period to ALL words so Aura-2 treats each as a
# complete utterance with natural falling intonation. For words that are still
# problematic even with a period (single letters, ambiguous short words), we
# provide explicit phonetic overrides.
#
# The generate_words() function applies this logic:
#   - If a word is in WORD_PRONUNCIATIONS, use the override text as-is
#   - Otherwise, send "word." (word + period) for clean isolated speech
#
WORD_PRONUNCIATIONS = {
    # ── Single-letter words ──────────────────────────────────────────────
    # "a" alone could be read as letter name "ay"; we want the article "uh"
    "a":  "A.",        # Uppercase + period: Aura-2 reads as the article
    "i":  "I.",        # Uppercase pronoun — Aura-2 knows "I" is the pronoun
    "I":  "I.",        # Uppercase pronoun — already natural, period for clean stop

    # ── Two-letter words that could be misread as initials/abbreviations ─
    # These are all common English words. The period forces word-mode reading.
    # Phonetic overrides only where the default "word." still fails.
    "am": "am.",
    "an": "an.",
    "as": "as.",
    "at": "at.",
    "be": "be.",
    "by": "by.",
    "do": "do.",
    "go": "go.",
    "he": "he.",
    "if": "if.",
    "in": "in.",
    "is": "is.",
    "it": "it.",
    "me": "me.",
    "my": "my.",
    "no": "no.",
    "of": "of.",
    "on": "on.",
    "or": "or.",
    "so": "so.",
    "to": "to.",
    "up": "up.",
    "us": "us.",
    "we": "we.",

    # ── Three-letter words that might sound like abbreviations ───────────
    "are": "are.",
    "ate": "ate.",
    "its": "its.",
    "off": "off.",
    "our": "our.",
    "own": "own.",
    "the": "the.",
    "two": "two.",
    "who": "who.",
    "why": "why.",
    "yes": "yes.",
    "you": "you.",

    # ── Words that could be misread (homophones, unusual patterns) ───────
    "read":  "read.",      # Could be "reed" or "red" — period helps default to present tense
    "live":  "live.",      # Could be "liv" or "lyve"
    "does":  "does.",      # Rhymes with "buzz", not "toes"
    "said":  "said.",      # Irregular pronunciation: "sed"
    "says":  "says.",      # Irregular: "sez"
    "been":  "been.",      # "bin" not "bean"
    "done":  "done.",      # "dun" not "doan"
    "gone":  "gone.",      # "gon" not "goan"
    "give":  "give.",      # Short i, not "jive"
    "have":  "have.",      # Short a
    "come":  "come.",      # "kum" not "kohm"
    "some":  "some.",      # "sum" not "sohm"
    "once":  "once.",      # "wunce"
    "were":  "were.",      # "wur"
    "where": "where.",     # "wair"
    "there": "there.",     # "thair"
    "their": "their.",     # "thair" (possessive)

    # ── Extra words with special pronunciation ───────────────────────────
    "tnt": "T N T",        # Spell out as initials
}


# ============================================================================
#  DEEPGRAM API
# ============================================================================

class DeepgramTTS:
    """Deepgram Aura-2 text-to-speech client."""

    def __init__(self, api_key: str, voice: str = DEFAULT_VOICE):
        self.api_key = api_key
        self.voice = voice
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Token {api_key}",
            "Content-Type": "text/plain",
        })
        self._total_requests = 0
        self._total_bytes = 0

    def generate(self, text: str, output_path: Path) -> bool:
        """
        Generate speech for `text` and save as MP3 to `output_path`.
        Returns True on success, False on failure.
        """
        params = {
            "model": self.voice,
            "encoding": "mp3",
        }

        for attempt in range(MAX_RETRIES + 1):
            try:
                resp = self.session.post(
                    API_URL, params=params, data=text.encode("utf-8"), timeout=30,
                )

                if resp.status_code == 200:
                    audio_bytes = resp.content
                    if len(audio_bytes) < 100:
                        print(f"    WARNING: Suspiciously small audio ({len(audio_bytes)} bytes)")
                        return False
                    output_path.parent.mkdir(parents=True, exist_ok=True)
                    output_path.write_bytes(audio_bytes)
                    self._total_requests += 1
                    self._total_bytes += len(audio_bytes)
                    return True

                if resp.status_code == 401:
                    print(f"    FATAL: Invalid API key (401). Check your --api-key value.")
                    return False

                if resp.status_code == 402:
                    print(f"    FATAL: Insufficient credits (402). Top up your Deepgram account.")
                    return False

                if resp.status_code == 429:
                    wait = RETRY_BACKOFF[min(attempt, len(RETRY_BACKOFF) - 1)]
                    print(f"    Rate limited, waiting {wait}s (attempt {attempt + 1})...")
                    time.sleep(wait)
                    continue

                if resp.status_code >= 500:
                    wait = RETRY_BACKOFF[min(attempt, len(RETRY_BACKOFF) - 1)]
                    print(f"    Server error {resp.status_code}, retrying in {wait}s...")
                    time.sleep(wait)
                    continue

                print(f"    API error {resp.status_code}: {resp.text[:200]}")
                return False

            except requests.exceptions.Timeout:
                if attempt < MAX_RETRIES:
                    print(f"    Timeout, retrying...")
                    continue
                print(f"    Timeout after {MAX_RETRIES + 1} attempts")
                return False

            except requests.exceptions.RequestException as e:
                print(f"    Request error: {e}")
                return False

        return False

    @property
    def stats(self) -> str:
        mb = self._total_bytes / (1024 * 1024)
        return f"{self._total_requests} API calls, {mb:.1f} MB generated"


# ============================================================================
#  GENERATION TASKS
# ============================================================================

def _generate_batch(
    tts: DeepgramTTS,
    items: list[tuple[str, str, Path]],
    label: str,
    workers: int,
    dry_run: bool = False,
    force: bool = False,
) -> tuple[int, int, int]:
    """
    Generate a batch of (display_name, text, output_path) items.
    Returns (skipped, generated, failed) counts.

    When force=True, existing files are regenerated instead of skipped.
    Uses ThreadPoolExecutor for parallel generation.
    """
    # Filter out existing files (unless --force)
    to_generate = []
    skipped = 0
    for display_name, text, output_path in items:
        if output_path.exists() and not force:
            skipped += 1
        else:
            to_generate.append((display_name, text, output_path))

    total = len(items)
    needed = len(to_generate)

    print(f"\n  {'='*52}")
    print(f"  {label}")
    print(f"  {'='*52}")
    print(f"  Total:      {total}")
    if force:
        print(f"  Existing:   {skipped} (skipped — not in scope)")
        print(f"  To generate: {needed} (FORCE mode — regenerating all)")
    else:
        print(f"  Existing:   {skipped} (skipped)")
        print(f"  To generate: {needed}")
    print(f"  Voice:      {tts.voice}")
    if workers > 1:
        print(f"  Workers:    {workers} (parallel)")
    print()

    if needed == 0:
        print("  Nothing to generate — all files exist!")
        return skipped, 0, 0

    if dry_run:
        for name, text, path in to_generate:
            print(f"  [DRY RUN] {name} -> {path.name}")
        return skipped, 0, 0

    generated = 0
    failed = 0
    failed_items = []

    if workers <= 1:
        # Sequential generation
        for i, (name, text, path) in enumerate(to_generate, 1):
            print(f"  [{i}/{needed}] {name}...", end=" ", flush=True)
            if tts.generate(text, path):
                print("OK")
                generated += 1
            else:
                print("FAILED")
                failed += 1
                failed_items.append(name)
    else:
        # Parallel generation
        def _do_generate(item):
            name, text, path = item
            ok = tts.generate(text, path)
            return name, ok

        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {pool.submit(_do_generate, item): item for item in to_generate}
            done_count = 0
            for future in as_completed(futures):
                done_count += 1
                name, ok = future.result()
                status = "OK" if ok else "FAILED"
                print(f"  [{done_count}/{needed}] {name}... {status}")
                if ok:
                    generated += 1
                else:
                    failed += 1
                    failed_items.append(name)

    # Summary
    print(f"\n  Result: {generated} generated, {skipped} skipped, {failed} failed")
    if failed_items:
        print(f"  Failed: {', '.join(failed_items[:20])}")
        if len(failed_items) > 20:
            print(f"          ...and {len(failed_items) - 20} more")

    return skipped, generated, failed


# ── Category generators ────────────────────────────────────────────────────

def _get_spoken_text(word: str) -> str:
    """
    Get the spoken text to send to Deepgram for a given word.

    Priority:
      1. Explicit override from WORD_PRONUNCIATIONS (used as-is)
      2. Default: "word." — trailing period forces Aura-2 to treat it
         as a complete utterance with natural falling intonation, preventing
         clipped/question-like pronunciation on short words.
    """
    if word in WORD_PRONUNCIATIONS:
        return WORD_PRONUNCIATIONS[word]
    if word.lower() in WORD_PRONUNCIATIONS:
        return WORD_PRONUNCIATIONS[word.lower()]
    # Default: word with trailing period for clean isolated utterance
    return f"{word}."


def generate_words(tts: DeepgramTTS, base: Path, workers: int, dry_run: bool, force: bool = False):
    """Generate all Dolch + Bonus sight word pronunciations."""
    words_dir = base / "words"
    items = []

    # All Dolch + Bonus words — apply pronunciation overrides
    for w in ALL_WORDS:
        spoken = _get_spoken_text(w)
        items.append((w, spoken, words_dir / f"{w}.mp3"))

    # Extra UI words (element names, timer words, etc.)
    for w in EXTRA_WORDS:
        spoken = _get_spoken_text(w)
        items.append((w, spoken, words_dir / f"{w}.mp3"))

    # Any pronunciation-override-only entries not already covered
    all_word_keys = set(ALL_WORDS) | set(EXTRA_WORDS)
    for key, spoken in WORD_PRONUNCIATIONS.items():
        if key not in all_word_keys:
            items.append((key, spoken, words_dir / f"{key}.mp3"))

    return _generate_batch(tts, items, "WORDS (Dolch + Bonus)", workers, dry_run, force)


def generate_letter_names(tts: DeepgramTTS, base: Path, workers: int, dry_run: bool, force: bool = False):
    """Generate letter NAME audio (A = 'ay', B = 'bee', etc.)."""
    out_dir = base / "letter_names"
    items = []
    for letter, pronunciation in LETTER_NAMES.items():
        # Use a clear prompt so TTS says the letter name cleanly
        text = pronunciation
        items.append((f"{letter.upper()} ({pronunciation})", text, out_dir / f"{letter}.mp3"))

    return _generate_batch(tts, items, "LETTER NAMES (A-Z)", workers, dry_run, force)


def generate_phonics(tts: DeepgramTTS, base: Path, workers: int, dry_run: bool, force: bool = False):
    """Generate phonetic SOUND audio (A = 'ah', B = 'buh', etc.)."""
    out_dir = base / "phonics"
    items = []
    for letter, sound in LETTER_PHONICS.items():
        items.append((f"{letter.upper()} ({sound})", sound, out_dir / f"{letter}.mp3"))

    return _generate_batch(tts, items, "PHONICS (letter sounds)", workers, dry_run, force)


def generate_stickers(tts: DeepgramTTS, base: Path, workers: int, dry_run: bool, force: bool = False):
    """Generate spoken sticker name audio."""
    words_dir = base / "words"
    items = []
    for audio_key, spoken_text in STICKER_AUDIO.items():
        items.append((audio_key, spoken_text, words_dir / f"{audio_key}.mp3"))

    return _generate_batch(tts, items, "STICKER NAMES", workers, dry_run, force)


def generate_generic_welcomes(tts: DeepgramTTS, base: Path, workers: int, dry_run: bool, force: bool = False):
    """Generate generic welcome phrases (no child name)."""
    words_dir = base / "words"
    items = []
    for audio_key, spoken_text in GENERIC_WELCOMES.items():
        items.append((audio_key, spoken_text, words_dir / f"{audio_key}.mp3"))

    return _generate_batch(tts, items, "GENERIC WELCOMES", workers, dry_run, force)


def generate_phrases(tts: DeepgramTTS, base: Path, name: str, workers: int, dry_run: bool, force: bool = False):
    """Generate personalized encouragement phrases for a specific child."""
    if not name:
        print("\n  SKIP phrases — no --name provided")
        return 0, 0, 0

    phrases_dir = base / "phrases"
    items = []

    for category, templates in PHRASE_TEMPLATES.items():
        for i, template in enumerate(templates):
            text = template.replace("{name}", name)
            filename = f"{category}_{i}.mp3"
            items.append((f"{category}[{i}]: {text}", text, phrases_dir / filename))

    # Also generate just the child's name as a standalone audio file
    items.append((f"name: {name}", name, phrases_dir / "name.mp3"))

    return _generate_batch(tts, items, f"PERSONALIZED PHRASES (for {name})", workers, dry_run, force)


def generate_effects(tts: DeepgramTTS, base: Path, workers: int, dry_run: bool, force: bool = False):
    """
    Generate UI sound effects.
    NOTE: TTS voices aren't great for sound effects. These are placeholder
    spoken cues. For production, replace with actual sound effect files.
    """
    effects_dir = base / "effects"
    items = [
        ("success",        "Yay!",              effects_dir / "success.mp3"),
        ("error",          "Oops!",             effects_dir / "error.mp3"),
        ("level_complete", "Level complete!",   effects_dir / "level_complete.mp3"),
    ]

    return _generate_batch(tts, items, "SOUND EFFECTS", workers, dry_run, force)


# ============================================================================
#  PREVIEW MODE
# ============================================================================

def preview_word(tts: DeepgramTTS, text: str):
    """Generate and play a single word for preview."""
    import tempfile

    print(f"  Generating preview for: \"{text}\"")
    print(f"  Voice: {tts.voice}")

    with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as f:
        tmp_path = Path(f.name)

    if tts.generate(text, tmp_path):
        size_kb = tmp_path.stat().st_size / 1024
        print(f"  Saved to: {tmp_path} ({size_kb:.1f} KB)")
        print(f"  Playing...")

        # Try to play with platform default player
        import subprocess, platform
        system = platform.system()
        try:
            if system == "Windows":
                os.startfile(str(tmp_path))
            elif system == "Darwin":
                subprocess.run(["afplay", str(tmp_path)])
            else:
                subprocess.run(["xdg-open", str(tmp_path)])
        except Exception as e:
            print(f"  Could not auto-play: {e}")
            print(f"  Open the file manually: {tmp_path}")
    else:
        print("  FAILED to generate preview")
        tmp_path.unlink(missing_ok=True)


# ============================================================================
#  DIRECTORY SETUP & VALIDATION
# ============================================================================

def ensure_directories(base: Path):
    """Create all output directories."""
    dirs = ["words", "letters", "letter_names", "phonics", "effects", "phrases"]
    for d in dirs:
        (base / d).mkdir(parents=True, exist_ok=True)
    print(f"  Output: {base}")


def print_inventory(base: Path):
    """Print a summary of existing audio files."""
    categories = {
        "words":        base / "words",
        "letter_names": base / "letter_names",
        "phonics":      base / "phonics",
        "effects":      base / "effects",
        "phrases":      base / "phrases",
    }

    print(f"\n  {'='*52}")
    print(f"  AUDIO INVENTORY")
    print(f"  {'='*52}")

    total = 0
    for name, path in categories.items():
        if path.exists():
            count = len(list(path.glob("*.mp3")))
            total += count
            print(f"  {name:15s}  {count:4d} files")
        else:
            print(f"  {name:15s}     0 files (directory missing)")

    print(f"  {'─'*30}")
    print(f"  {'TOTAL':15s}  {total:4d} files")

    # Check expected counts (includes pronunciation-override-only entries not in word lists)
    pron_only = len(set(WORD_PRONUNCIATIONS.keys()) - set(ALL_WORDS) - set(EXTRA_WORDS))
    expected_words = len(ALL_WORDS) + len(EXTRA_WORDS) + pron_only + len(STICKER_AUDIO) + len(GENERIC_WELCOMES)
    words_count = len(list((base / "words").glob("*.mp3"))) if (base / "words").exists() else 0
    letters_count = len(list((base / "letter_names").glob("*.mp3"))) if (base / "letter_names").exists() else 0
    phonics_count = len(list((base / "phonics").glob("*.mp3"))) if (base / "phonics").exists() else 0

    print(f"\n  Expected:")
    print(f"    Words/stickers/welcomes:  {expected_words} (have {words_count})")
    print(f"    Letter names:             26 (have {letters_count})")
    print(f"    Phonics:                  26 (have {phonics_count})")


# ============================================================================
#  MAIN
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Reading Sprout — Deepgram Aura-2 TTS Audio Generator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--api-key", required=True, help="Deepgram API key")
    parser.add_argument("--name", default="", help="Child's name for personalized phrases")
    parser.add_argument("--voice", default=DEFAULT_VOICE, help=f"Deepgram voice model (default: {DEFAULT_VOICE})")
    parser.add_argument("--workers", type=int, default=DEFAULT_WORKERS, help=f"Parallel workers (default: {DEFAULT_WORKERS})")
    parser.add_argument("--only", choices=["words", "letters", "phonics", "stickers", "phrases", "effects", "welcome"],
                        help="Generate only a specific category")
    parser.add_argument("--preview", metavar="TEXT", help="Generate and play a single word/phrase")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be generated without API calls")
    parser.add_argument("--force", action="store_true", help="Regenerate files even if they exist (for re-recording fixed pronunciations)")
    parser.add_argument("--output", default=None, help="Output base directory (default: assets/audio/)")
    parser.add_argument("--inventory", action="store_true", help="Show current audio file inventory and exit")

    args = parser.parse_args()

    # Resolve output path
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent
    base = Path(args.output) if args.output else project_root / "assets" / "audio"

    # Initialize TTS client
    tts = DeepgramTTS(api_key=args.api_key, voice=args.voice)

    print()
    print("  ╔══════════════════════════════════════════════════╗")
    print("  ║   Reading Sprout — Deepgram TTS Generator       ║")
    print("  ╠══════════════════════════════════════════════════╣")
    print(f"  ║  Voice:   {args.voice:39s} ║")
    print(f"  ║  Workers: {args.workers:<39} ║")
    if args.name:
        print(f"  ║  Name:    {args.name:39s} ║")
    if args.force:
        print(f"  ║  Force:   {'YES — regenerating all files':39s} ║")
    print("  ╚══════════════════════════════════════════════════╝")

    # Inventory mode
    if args.inventory:
        print_inventory(base)
        return

    # Preview mode
    if args.preview:
        preview_word(tts, args.preview)
        return

    ensure_directories(base)

    # Track totals
    total_skipped = 0
    total_generated = 0
    total_failed = 0

    def _track(result):
        nonlocal total_skipped, total_generated, total_failed
        s, g, f = result
        total_skipped += s
        total_generated += g
        total_failed += f

    start_time = time.time()

    force = args.force

    if args.only:
        # Single category
        if args.only == "words":
            _track(generate_words(tts, base, args.workers, args.dry_run, force))
        elif args.only == "letters":
            _track(generate_letter_names(tts, base, args.workers, args.dry_run, force))
        elif args.only == "phonics":
            _track(generate_phonics(tts, base, args.workers, args.dry_run, force))
        elif args.only == "stickers":
            _track(generate_stickers(tts, base, args.workers, args.dry_run, force))
        elif args.only == "phrases":
            _track(generate_phrases(tts, base, args.name, args.workers, args.dry_run, force))
        elif args.only == "effects":
            _track(generate_effects(tts, base, args.workers, args.dry_run, force))
        elif args.only == "welcome":
            _track(generate_generic_welcomes(tts, base, args.workers, args.dry_run, force))
    else:
        # Generate everything (except personalized phrases without a name)
        _track(generate_words(tts, base, args.workers, args.dry_run, force))
        _track(generate_letter_names(tts, base, args.workers, args.dry_run, force))
        _track(generate_phonics(tts, base, args.workers, args.dry_run, force))
        _track(generate_stickers(tts, base, args.workers, args.dry_run, force))
        _track(generate_generic_welcomes(tts, base, args.workers, args.dry_run, force))
        _track(generate_effects(tts, base, args.workers, args.dry_run, force))
        if args.name:
            _track(generate_phrases(tts, base, args.name, args.workers, args.dry_run, force))

    elapsed = time.time() - start_time

    # Final summary
    print()
    print("  ╔══════════════════════════════════════════════════╗")
    print("  ║   GENERATION COMPLETE                           ║")
    print("  ╠══════════════════════════════════════════════════╣")
    print(f"  ║  Generated: {total_generated:<37} ║")
    print(f"  ║  Skipped:   {total_skipped:<37} ║")
    print(f"  ║  Failed:    {total_failed:<37} ║")
    print(f"  ║  Time:      {elapsed:.1f}s{' ' * (36 - len(f'{elapsed:.1f}s'))} ║")
    print(f"  ║  API stats: {tts.stats:37s} ║")
    print("  ╚══════════════════════════════════════════════════╝")

    if total_failed > 0:
        print(f"\n  Re-run to retry failed items (existing files are skipped).")

    # Show inventory
    print_inventory(base)


if __name__ == "__main__":
    main()

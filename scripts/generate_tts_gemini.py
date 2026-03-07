#!/usr/bin/env python3
"""
Sight Words TTS Audio Generator --Gemini 2.5 Flash TTS Edition
================================================================
Generates all audio clips using your existing Google AI Studio / Gemini API key.
Uses the gemini-2.5-flash-preview-tts model for high-quality, kid-friendly voices.

OPTIMIZED: Uses batch mode to generate up to 25 words per API call, then splits
by silence detection. For 269 total words, this needs only ~12 API calls instead
of 269, staying well within the 250 RPD free-tier limit.

Prompt strategy uses Gemini's recommended Audio Profile + Scene + Director's Notes
format for consistent, high-quality kid-friendly pronunciations.

Prerequisites:
  pip install requests
  # Also need ffmpeg installed for PCM -> MP3 conversion + silence splitting:
  #   Ubuntu: sudo apt install ffmpeg
  #   Mac:    brew install ffmpeg
  #   Windows: download from ffmpeg.org (or winget install ffmpeg)

Usage:
  # Generate everything for a child named Emma
  python generate_tts_gemini.py --api-key "AIzaSy..." --name Emma

  # Preview a single word
  python generate_tts_gemini.py --api-key "AIzaSy..." --preview "hello"

  # Generate only specific categories
  python generate_tts_gemini.py --api-key "AIzaSy..." --only words
  python generate_tts_gemini.py --api-key "AIzaSy..." --only letters
  python generate_tts_gemini.py --api-key "AIzaSy..." --only phrases --name Emma

  # Force one-word-per-call mode (old behavior, uses more API calls)
  python generate_tts_gemini.py --api-key "AIzaSy..." --no-batch

Available Voices (30 options --test at https://aistudio.google.com/generate-speech):
  Warm/Friendly (great for kids):  Kore, Puck, Charon, Fenrir
  Bright/Upbeat:                   Aoede, Leda, Zephyr
  Calm/Gentle:                     Vale, Sulafar, Orus
  See full list: https://ai.google.dev/gemini-api/docs/speech-generation#voices
"""

import argparse
import base64
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import time
import wave
from pathlib import Path

import requests

# Force UTF-8 output on Windows to avoid encoding errors
import io
if sys.stdout.encoding != 'utf-8':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
if sys.stderr.encoding != 'utf-8':
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

# -- Configuration -------------------------------------------------------

API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent"

# Default voice --Kore is warm and friendly, great for a kids app
DEFAULT_VOICE = "Kore"

# Rate limiting: Gemini free tier = 10 RPM, paid = higher
REQUESTS_PER_MINUTE = 10
DELAY_BETWEEN_REQUESTS = 60.0 / REQUESTS_PER_MINUTE

# Batch mode: how many words per API call
# Model supports 8192 input tokens & ~5:27 of audio output.
# 10 words at ~1.5s per word + 3s pause = ~45s of audio. Conservative
# but reliable — 25 was timing out on the free tier.
DEFAULT_BATCH_SIZE = 10

# Silence detection thresholds: cascade from conservative to aggressive.
# Each tuple is (min_silence_duration_seconds, noise_threshold_dB).
SILENCE_THRESHOLDS = [
    (0.8, -40),   # Very conservative: only deep, long silences
    (0.5, -35),   # Conservative
    (0.4, -35),   # Default
    (0.3, -30),   # Moderate
    (0.2, -28),   # Aggressive
    (0.15, -25),  # Very aggressive
]

# ── Dolch Sight Words (220 unique) ───────────────────────────────────────

DOLCH_WORDS = sorted(set(w.lower() for w in [
    "a", "I", "it", "is", "in", "my", "me", "we", "go", "to",
    "up", "no", "on", "do", "he", "at", "an", "am", "so", "be",
    "the", "and", "see", "you", "can", "not", "run", "big", "red", "one",
    "for", "was", "are", "but", "had", "has", "his", "her", "him", "how",
    "did", "get", "may", "new", "now", "old", "our", "out", "ran", "say",
    "she", "too", "all", "ate", "came", "like", "will", "yes", "said", "good",
    "that", "they", "this", "what", "with", "have", "into", "want", "well", "went",
    "look", "make", "play", "ride", "must", "stop", "help", "jump", "find", "from",
    "come", "give", "just", "know", "let", "live", "over", "take", "tell", "them",
    "then", "were", "when", "here", "soon", "open", "upon", "once", "some", "very",
    "ask", "any", "fly", "try", "put", "cut", "hot", "got", "ten", "sit",
    "after", "again", "every", "going", "could", "would", "think", "thank", "round", "sleep",
    "walk", "work", "wash", "wish", "which", "white", "where", "there", "these", "those",
    "under", "about", "never", "seven", "eight", "green", "brown", "black", "clean", "small",
    "away", "best", "both", "call", "cold", "does", "done", "draw", "fall", "fast",
    "been", "read", "made", "gave", "many", "only", "pull", "full", "keep", "kind",
    "long", "much", "pick", "show", "sing", "warm", "hold", "hurt", "far", "own",
    "carry", "today", "start", "shall", "laugh", "light", "right", "write", "first", "found",
    "bring", "drink", "funny", "happy", "their", "your", "four", "five", "six", "two",
    "always", "around", "before", "better", "please", "pretty", "because", "myself", "goes", "together",
    "buy", "use", "off", "its", "why", "grow", "if", "or", "as", "by",
    "three", "blue", "eat", "saw", "down", "little", "who", "yellow", "us", "of",
]))

# ── Bonus Words (common kid-friendly words not in Dolch) ─────────────────

BONUS_WORDS = sorted(set(w.lower() for w in [
    # Family
    "mom", "dad", "baby", "love", "name", "family",
    # Animals
    "dog", "cat", "fish", "bird", "bear", "frog",
    # Home & play
    "home", "food", "book", "ball", "game", "toy",
    # Body
    "hand", "head", "eyes", "feet",
    # Nature
    "sun", "moon", "star", "tree", "rain", "snow",
    # School
    "school", "teacher", "friend", "learn",
    # Colors (beyond Dolch's red/blue/green/brown/black/white/yellow)
    "pink", "purple", "orange",
    # Numbers (beyond Dolch's one-eight/ten)
    "nine", "zero",
    # Common verbs not in Dolch
    "like", "play", "love", "need", "feel", "wait", "hope",
    # Common adjectives
    "nice", "hard", "soft", "dark", "tall", "loud", "quiet",
]))

# Remove any that are already in Dolch
BONUS_WORDS = sorted(set(BONUS_WORDS) - set(DOLCH_WORDS))

# ── Sticker Audio Names ─────────────────────────────────────────────────
# Maps audioKey -> spoken sticker name. Files go to assets/audio/words/<audioKey>.mp3

STICKER_NAMES = {
    # Level completion (22 levels)
    **{f"level_{i}": f"Level {i}" for i in range(1, 23)},

    # Milestones
    "first_word": "First Word",
    "ten_words": "Ten Words",
    "twenty_five_words": "Twenty-Five Words",
    "fifty_words": "Fifty Words",
    "one_hundred_words": "One Hundred Words",
    "one_hundred_fifty_words": "One Hundred Fifty Words",
    "two_hundred_words": "Two Hundred Words",
    "all_words": "All Words",

    # Streaks
    "three_day_streak": "Three Day Streak",
    "seven_day_streak": "Seven Day Streak",
    "fourteen_day_streak": "Fourteen Day Streak",
    "thirty_day_streak": "Thirty Day Streak",

    # Perfect
    "perfect_level": "Perfect Level",

    # Evolution
    "word_sprout": "Word Sprout",
    "word_explorer": "Word Explorer",
    "word_wizard": "Word Wizard",
    "word_champion": "Word Champion",
    "reading_superstar": "Reading Superstar",

    # Special
    "speed_reader": "Speed Reader",

    # Mini-game stickers
    "first_flight": "First Flight",
    "unicorn_rider": "Unicorn Rider",
    "sky_champion": "Sky Champion",
    "storm_speller": "Storm Speller",
    "lightning_fast": "Lightning Fast",
    "thunder_brain": "Thunder Brain",
    "bubble_popper": "Bubble Popper",
    "bubble_master": "Bubble Master",
    "memory_maker": "Memory Maker",
    "sharp_memory": "Sharp Memory",
    "perfect_recall": "Perfect Recall",
    "letter_catcher": "Letter Catcher",
    "falling_star": "Falling Star",
    "cat_tosser": "Cat Tosser",
    "purrfect_aim": "Purrfect Aim",
    "cat_champion": "Cat Champion",
    "letter_dropper": "Letter Dropper",
    "drop_expert": "Drop Expert",
    "rhyme_rookie": "Rhyme Rookie",
    "rhyme_master": "Rhyme Master",
    "super_poet": "Super Poet",
}

# ── Phrase Templates ─────────────────────────────────────────────────────
# Each category has phrases with {name} placeholder.
# These match the Dart PhraseTemplates class exactly.

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

# ── Phonetic sounds for each letter ──────────────────────────────────────

LETTER_PHONETIC_PROMPTS = {
    'a': 'ah',
    'b': 'Say the phonetic sound of the letter B. It sounds like buh, as in the word ball. Just make the sound, not the word.',
    'c': 'kuh',
    'd': 'duh',
    'e': 'eh',
    'f': 'fuh',
    'g': 'guh',
    'h': 'huh',
    'i': 'ih',
    'j': 'juh',
    'k': 'kuh',
    'l': 'luh',
    'm': 'muh',
    'n': 'Say the phonetic sound of the letter N. It sounds like nnn, as in the word net. Just make the sound, not the word.',
    'o': 'oh',
    'p': 'puh',
    'q': 'kwuh',
    'r': 'Say the phonetic sound of the letter R. It sounds like rrr, as in the word run. Just make the sound, not the word.',
    's': 'sss',
    't': 'tuh',
    'u': 'uh',
    'v': 'vvv',
    'w': 'wuh',
    'x': 'ks',
    'y': 'yuh',
    'z': 'zzz',
}

# ── Letter NAME prompts (alphabet names, not phonetic sounds) ────────────
# Each prompt is a full sentence to avoid ambiguity with short utterances.

LETTER_NAME_PROMPTS = {
    'a': 'Say the letter name "A", as in the English alphabet. Pronounce it as "ay". Just the single letter name, nothing else.',
    'b': 'Say the letter name "B", as in the English alphabet. Pronounce it as "bee". Just the single letter name, nothing else.',
    'c': 'Say the letter name "C", as in the English alphabet. Pronounce it as "see". Just the single letter name, nothing else.',
    'd': 'Say the letter name "D", as in the English alphabet. Pronounce it as "dee". Just the single letter name, nothing else.',
    'e': 'Say the letter name "E", as in the English alphabet. Pronounce it as "ee". Just the single letter name, nothing else.',
    'f': 'Say the letter name "F", as in the English alphabet. Pronounce it as "eff". Just the single letter name, nothing else.',
    'g': 'Say the letter name "G", as in the English alphabet. Pronounce it as "jee". Just the single letter name, nothing else.',
    'h': 'Say the letter name "H", as in the English alphabet. Pronounce it as "aych". Just the single letter name, nothing else.',
    'i': 'Say the letter name "I", as in the English alphabet. Pronounce it as "eye". Just the single letter name, nothing else.',
    'j': 'Say the letter name "J", as in the English alphabet. Pronounce it as "jay". Just the single letter name, nothing else.',
    'k': 'Say the letter name "K", as in the English alphabet. Pronounce it as "kay". Just the single letter name, nothing else.',
    'l': 'Say the letter name "L", as in the English alphabet. Pronounce it as "ell". Just the single letter name, nothing else.',
    'm': 'Say the letter name "M", as in the English alphabet. Pronounce it as "em". Just the single letter name, nothing else.',
    'n': 'Say the letter name "N", as in the English alphabet. Pronounce it as "en". Just the single letter name, nothing else.',
    'o': 'Say the letter name "O", as in the English alphabet. Pronounce it as "oh". Just the single letter name, nothing else.',
    'p': 'Say the letter name "P", as in the English alphabet. Pronounce it as "pee". Just the single letter name, nothing else.',
    'q': 'Say the letter name "Q", as in the English alphabet. Pronounce it as "kyoo". Just the single letter name, nothing else.',
    'r': 'Say the letter name "R", as in the English alphabet. Pronounce it as "ar". Just the single letter name, nothing else.',
    's': 'Say the letter name "S", as in the English alphabet. Pronounce it as "ess". Just the single letter name, nothing else.',
    't': 'Say the letter name "T", as in the English alphabet. Pronounce it as "tee". Just the single letter name, nothing else.',
    'u': 'Say the letter name "U", as in the English alphabet. Pronounce it as "yoo". Just the single letter name, nothing else.',
    'v': 'Say the letter name "V", as in the English alphabet. Pronounce it as "vee". Just the single letter name, nothing else.',
    'w': 'Say the letter name "W", as in the English alphabet. Pronounce it as "double-yoo". Just the single letter name, nothing else.',
    'x': 'Say the letter name "X", as in the English alphabet. Pronounce it as "ex". Just the single letter name, nothing else.',
    'y': 'Say the letter name "Y", as in the English alphabet. Pronounce it as "why". Just the single letter name, nothing else.',
    'z': 'Say the letter name "Z", as in the English alphabet. Pronounce it as "zee". Just the single letter name, nothing else.',
}

# Special word prompts for short/ambiguous words that TTS may misinterpret.
# These words are EXCLUDED from batch mode and generated individually.
WORD_SPECIAL_PROMPTS = {
    'a': (
        'Say the English article word "a", as used in the sentence "I see a dog." '
        'Pronounce it naturally as the article "a" (sounds like "uh"). '
        'Just the single word, nothing else.'
    ),
    'i': (
        'Say the English pronoun "I", as used in "I like dogs." '
        'Pronounce it clearly as "eye". Just the single word, nothing else.'
    ),
    'an': (
        'Say the English article word "an", as used in "I ate an apple." '
        'It rhymes with "can" and "pan". The ending sound is the letter N, '
        'not M. Pronounce it clearly as "ann" with a strong N at the end. '
        'Just the single word, nothing else.'
    ),
    'as': (
        'Say the English word "as", as used in "as big as a house." '
        'Pronounce it clearly. Just the single word, nothing else.'
    ),
    'by': (
        'Say the English preposition "by", as used in "stand by me." '
        'Pronounce it clearly. Just the single word, nothing else.'
    ),
    'if': (
        'Say the English conjunction "if", as used in "if you want." '
        'Pronounce it clearly. Just the single word, nothing else.'
    ),
    'in': (
        'Say the English preposition "in", as used in "in the box." '
        'Pronounce it clearly. Just the single word, nothing else.'
    ),
    'is': (
        'Say the English verb "is", as used in "it is fun." '
        'Pronounce it clearly as "iz". Just the single word, nothing else.'
    ),
    'it': (
        'Say the English pronoun "it", as used in "it is fun." '
        'Pronounce it clearly. Just the single word, nothing else.'
    ),
    'no': (
        'Say the English word "no", meaning the opposite of yes. '
        'Pronounce it clearly. Just the single word, nothing else.'
    ),
    'of': (
        'Say the English preposition "of", as used in "a cup of water." '
        'Pronounce it clearly as "uv". Just the single word, nothing else.'
    ),
    'or': (
        'Say the English conjunction "or", as used in "this or that." '
        'Pronounce it clearly. Just the single word, nothing else.'
    ),
    'so': (
        'Say the English word "so", as used in "I am so happy." '
        'Pronounce it clearly. Just the single word, nothing else.'
    ),
    'to': (
        'Say the English preposition "to", as used in "go to the store." '
        'Pronounce it clearly as "too". Just the single word, nothing else.'
    ),
    'up': (
        'Say the English word "up", as used in "stand up." '
        'Pronounce it clearly. Just the single word, nothing else.'
    ),
    'us': (
        'Say the English pronoun "us", as used in "come with us." '
        'Pronounce it clearly. Just the single word, nothing else.'
    ),
    'the': (
        'You are a warm, patient reading teacher helping a child learn to read. '
        'Say the English word "the" out loud, clearly and slowly. '
        'Pronounce it as "thuh" with a soft "th" sound. '
        'Say only this one word. Nothing else before or after.'
    ),
    'them': (
        'Say the English pronoun "them", as used in "give it to them." '
        'Pronounce it clearly. Just the single word, nothing else.'
    ),
}


# ── Audio Helpers ────────────────────────────────────────────────────────

def pcm_to_wav(pcm_data: bytes, wav_path: Path, sample_rate=24000, channels=1, sample_width=2):
    """Convert raw PCM bytes to a WAV file."""
    with wave.open(str(wav_path), "wb") as wf:
        wf.setnchannels(channels)
        wf.setsampwidth(sample_width)
        wf.setframerate(sample_rate)
        wf.writeframes(pcm_data)


def wav_to_mp3(wav_path: Path, mp3_path: Path):
    """Convert WAV to MP3 using ffmpeg."""
    try:
        subprocess.run(
            ["ffmpeg", "-y", "-i", str(wav_path), "-codec:a", "libmp3lame",
             "-qscale:a", "2", str(mp3_path)],
            check=True,
            capture_output=True,
        )
        wav_path.unlink(missing_ok=True)
    except FileNotFoundError:
        print("  ffmpeg not found! Keeping .wav files instead.")
        wav_path.rename(mp3_path.with_suffix('.wav'))
    except subprocess.CalledProcessError as e:
        print(f"  ffmpeg error: {e.stderr.decode()}")


# ── Gemini TTS API ───────────────────────────────────────────────────────

MAX_RETRIES = 3
_quota_exhausted = False  # Global flag: stop all requests once daily quota is hit


def generate_speech_raw(api_key: str, text: str, voice: str, _retry: int = 0,
                        timeout: int = 120):
    """
    Call Gemini TTS API and return raw PCM bytes.
    Returns bytes on success, None on failure.
    Sets _quota_exhausted flag when daily limit is hit.
    """
    global _quota_exhausted
    if _quota_exhausted:
        return None

    headers = {
        "Content-Type": "application/json",
        "x-goog-api-key": api_key,
    }

    payload = {
        "contents": [{"parts": [{"text": text}]}],
        "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {
                "voiceConfig": {
                    "prebuiltVoiceConfig": {"voiceName": voice}
                }
            }
        }
    }

    try:
        response = requests.post(API_URL, headers=headers, json=payload, timeout=timeout)

        if response.status_code == 429:
            if _retry >= MAX_RETRIES:
                print(f"\n  QUOTA EXHAUSTED after {MAX_RETRIES} retries.")
                print("  Re-run this script later -- it skips files already generated.")
                _quota_exhausted = True
                return None
            wait_time = 60 * (_retry + 1)
            print(f"Rate limited, waiting {wait_time}s (retry {_retry+1}/{MAX_RETRIES})...", end=" ", flush=True)
            time.sleep(wait_time)
            return generate_speech_raw(api_key, text, voice, _retry + 1, timeout)

        if response.status_code >= 500:
            if _retry >= MAX_RETRIES:
                print(f"\n  SERVER ERROR {response.status_code} after {MAX_RETRIES} retries.")
                return None
            wait_time = 10 * (_retry + 1)
            print(f"Server error {response.status_code}, waiting {wait_time}s (retry {_retry+1}/{MAX_RETRIES})...", end=" ", flush=True)
            time.sleep(wait_time)
            return generate_speech_raw(api_key, text, voice, _retry + 1, timeout)

        if response.status_code != 200:
            print(f"  API error {response.status_code}: {response.text[:200]}")
            return None

        data = response.json()
        audio_b64 = data["candidates"][0]["content"]["parts"][0]["inlineData"]["data"]
        return base64.b64decode(audio_b64)

    except Exception as e:
        print(f"  Error: {e}")
        return None


def generate_speech(api_key: str, text: str, voice: str, output_mp3: Path) -> bool:
    """Generate speech and save as MP3. Returns True on success."""
    pcm = generate_speech_raw(api_key, text, voice)
    if pcm is None:
        return False
    wav_path = output_mp3.with_suffix('.wav')
    pcm_to_wav(pcm, wav_path)
    wav_to_mp3(wav_path, output_mp3)
    return True


# ── Silence Detection & Audio Splitting ──────────────────────────────────

def detect_silences(wav_path: Path, min_silence_duration=0.4, noise_threshold=-35):
    """
    Use ffmpeg to detect silence regions in a WAV file.
    Returns list of (start, end) tuples for each silence region.
    """
    cmd = [
        "ffmpeg", "-i", str(wav_path),
        "-af", f"silencedetect=noise={noise_threshold}dB:d={min_silence_duration}",
        "-f", "null", "-"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    stderr = result.stderr

    silences = []
    starts = re.findall(r'silence_start: ([\d.]+)', stderr)
    ends = re.findall(r'silence_end: ([\d.]+)', stderr)

    for s, e in zip(starts, ends):
        silences.append((float(s), float(e)))

    return silences


def get_audio_duration(wav_path: Path) -> float:
    """Get duration of a WAV file in seconds."""
    cmd = ["ffmpeg", "-i", str(wav_path), "-f", "null", "-"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    match = re.search(r'Duration: (\d+):(\d+):(\d+\.\d+)', result.stderr)
    if match:
        h, m, s = match.groups()
        return int(h) * 3600 + int(m) * 60 + float(s)
    return 0.0


def select_best_silences(silences: list, needed_count: int) -> list:
    """
    When more silences are detected than needed, select the N best ones
    by preferring longer/deeper silence regions (more likely real word gaps).
    Returns the selected silences sorted by start time.
    """
    if len(silences) <= needed_count:
        return silences

    # Score each silence by its duration (longer = more likely a real gap)
    scored = [(s_end - s_start, s_start, s_end) for s_start, s_end in silences]
    scored.sort(reverse=True)  # Longest duration first

    # Take the top N
    selected = [(s, e) for _, s, e in scored[:needed_count]]
    selected.sort()  # Re-sort by time position
    return selected


def split_audio_at_silences(wav_path: Path, silences: list, expected_count: int,
                            output_dir: Path, words: list,
                            min_segment: float = 0.15, max_segment: float = 6.0):
    """
    Split a WAV file at silence midpoints into individual word segments.
    Returns list of (word, mp3_path) tuples for successful splits.

    Validates that each segment falls within reasonable duration bounds
    to reject bad splits (too short = split inside a word, too long = missed gap).
    """
    duration = get_audio_duration(wav_path)
    if duration == 0:
        return []

    needed_silences = expected_count - 1

    # If we got MORE silences than needed, select the best N
    working_silences = silences
    if len(silences) > needed_silences:
        working_silences = select_best_silences(silences, needed_silences)

    # Calculate split points (midpoints of each silence region)
    split_points = [0.0]
    for s_start, s_end in working_silences:
        midpoint = (s_start + s_end) / 2
        split_points.append(midpoint)
    split_points.append(duration)

    # We expect (expected_count) segments = (expected_count - 1) silences
    segments = len(split_points) - 1

    if segments != expected_count:
        return []  # Signal mismatch --caller will handle fallback

    # Validate segment durations before extracting
    for i in range(segments):
        seg_dur = split_points[i + 1] - split_points[i]
        if seg_dur < min_segment or seg_dur > max_segment:
            return []  # Bad split --a segment is suspiciously short or long

    results = []
    for i, word in enumerate(words):
        start = split_points[i]
        end = split_points[i + 1]

        # Trim a tiny bit of silence from edges for cleaner clips
        trim_start = max(start, start + 0.05) if i > 0 else start
        trim_end = min(end, end - 0.05) if i < len(words) - 1 else end

        mp3_path = output_dir / f"{word}.mp3"
        segment_wav = wav_path.parent / f"_segment_{i}.wav"

        try:
            subprocess.run(
                ["ffmpeg", "-y", "-i", str(wav_path),
                 "-ss", f"{trim_start:.3f}", "-to", f"{trim_end:.3f}",
                 "-c", "copy", str(segment_wav)],
                check=True, capture_output=True,
            )
            wav_to_mp3(segment_wav, mp3_path)
            results.append((word, mp3_path))
        except subprocess.CalledProcessError as e:
            print(f"    Split error for '{word}': {e.stderr.decode()[:100]}")
            segment_wav.unlink(missing_ok=True)

    return results


# ── Batch Word Generation ─────────────────────────────────────────────────

def ensure_dirs(base_path: Path):
    """Create output directories."""
    (base_path / "words").mkdir(parents=True, exist_ok=True)
    (base_path / "letters").mkdir(parents=True, exist_ok=True)
    (base_path / "letter_names").mkdir(parents=True, exist_ok=True)
    (base_path / "effects").mkdir(parents=True, exist_ok=True)
    (base_path / "phrases").mkdir(parents=True, exist_ok=True)
    print(f"Output directory: {base_path}")


def _build_batch_prompt(words: list) -> str:
    """
    Build a TTS prompt using Gemini's recommended structure:
    Audio Profile + Scene + Director's Notes + numbered word list.

    The numbered list gives the LLM clear sequential structure.
    Director's Notes enforce 3-second pauses for reliable silence splitting.
    """
    word_list_numbered = "\n".join(f"{i+1}. {w}" for i, w in enumerate(words))

    return (
        # ── Audio Profile ──
        f'You are a warm, patient reading teacher with a clear, gentle voice.\n'
        # ── Scene ──
        f'You are in a quiet classroom helping a young child learn to read sight words.\n\n'
        # ── Director\'s Notes ──
        f'Say each of the following {len(words)} words ONE AT A TIME.\n'
        f'- Pronounce each word clearly and slowly, enunciating every sound\n'
        f'- Use a warm, encouraging tone — like praising a child for each word\n'
        f'- Take a FULL 3-second silent pause between each word\n'
        f'- Say ONLY the listed words — no numbers, no commentary, no extra sounds\n'
        f'- Do NOT rush — each word deserves its own moment\n\n'
        # ── Word list ──
        f'Words to say in order:\n{word_list_numbered}'
    )


def _try_split_with_cascade(batch_wav: Path, batch: list, words_dir: Path):
    """
    Try splitting a batch WAV into individual word files using a cascade
    of silence detection thresholds from conservative to aggressive.

    Returns (results, label) where results is a list of (word, path) tuples,
    or (None, None) if all thresholds fail.
    """
    labels = ["conservative+", "conservative", "default", "moderate", "aggressive", "aggressive+"]

    for i, (min_dur, noise_db) in enumerate(SILENCE_THRESHOLDS):
        silences = detect_silences(batch_wav, min_silence_duration=min_dur, noise_threshold=noise_db)
        results = split_audio_at_silences(
            batch_wav, silences, len(batch), words_dir, batch
        )
        if len(results) == len(batch):
            return results, labels[i] if i < len(labels) else f"threshold-{i}"

    return None, None


def generate_words_batched(api_key: str, voice: str, base_path: Path,
                           word_list: list, batch_size: int, label: str = "word"):
    """
    Generate words using batch mode: multiple words per API call,
    then split by silence detection. Falls back to half-batch, then
    individual calls if splitting fails.

    With batch_size=25, generates ~250 words in only ~12 API calls!
    """
    words_dir = base_path / "words"

    # Separate words into: already done, special (need individual), batchable
    already_done = []
    special_words = []
    batchable_words = []

    for word in word_list:
        out = words_dir / f"{word}.mp3"
        if out.exists():
            already_done.append(word)
        elif word in WORD_SPECIAL_PROMPTS:
            special_words.append(word)
        else:
            batchable_words.append(word)

    total_needed = len(special_words) + len(batchable_words)
    batch_count = (len(batchable_words) + batch_size - 1) // batch_size if batchable_words else 0
    api_calls = batch_count + len(special_words)

    print(f"\n{'='*56}")
    print(f"  Generating {label} audio -- BATCH MODE (v2)")
    print(f"{'='*56}")
    print(f"  Total words:    {len(word_list)}")
    print(f"  Already done:   {len(already_done)} (skipped)")
    print(f"  Special words:  {len(special_words)} (individual calls)")
    print(f"  Batchable:      {len(batchable_words)} -> {batch_count} batches of <={batch_size}")
    print(f"  Est. API calls: ~{api_calls} (saved ~{total_needed - api_calls} vs individual!)")
    print(f"  Voice: {voice}")
    print(f"  Silence cascade: {len(SILENCE_THRESHOLDS)} threshold levels")
    print()

    generated = 0
    failed_words = []

    # ── Phase 1: Batch generation ────────────────────────────────────
    if batchable_words:
        batches = [batchable_words[i:i+batch_size] for i in range(0, len(batchable_words), batch_size)]

        for batch_idx, batch in enumerate(batches):
            # Filter out any words already generated (from a previous half-batch retry)
            batch = [w for w in batch if not (words_dir / f"{w}.mp3").exists()]
            if not batch:
                continue
            if _quota_exhausted:
                failed_words.extend(batch)
                continue

            print(f"  Batch {batch_idx+1}/{len(batches)} ({len(batch)} words): {', '.join(batch[:8])}"
                  f"{'...' if len(batch) > 8 else ''}")

            # Build the structured prompt
            prompt = _build_batch_prompt(batch)

            # Generate the batch audio (longer timeout for multi-word batches)
            batch_timeout = max(120, len(batch) * 15)  # ~15s per word, min 120s
            pcm = generate_speech_raw(api_key, prompt, voice, timeout=batch_timeout)
            if pcm is None:
                print(f"    API FAILED -- queuing {len(batch)} words for fallback")
                failed_words.extend(batch)
                time.sleep(DELAY_BETWEEN_REQUESTS)
                continue

            # Save as temporary WAV and try splitting
            with tempfile.TemporaryDirectory() as tmpdir:
                tmp = Path(tmpdir)
                batch_wav = tmp / "batch.wav"
                pcm_to_wav(pcm, batch_wav)

                dur = get_audio_duration(batch_wav)
                print(f"    Audio: {dur:.1f}s ({dur/len(batch):.1f}s avg/word)")

                # Try cascade of silence thresholds
                results, threshold_label = _try_split_with_cascade(
                    batch_wav, batch, words_dir
                )

                if results:
                    for word, path in results:
                        print(f"    OK  {word}")
                    if threshold_label != "default":
                        print(f"    (used {threshold_label} threshold)")
                    generated += len(results)
                else:
                    # Clean up any partial files from failed attempts
                    for word in batch:
                        p = words_dir / f"{word}.mp3"
                        p.unlink(missing_ok=True)

                    print(f"    SPLIT FAILED at all thresholds")

                    # ── Half-batch retry ──────────────────────────
                    # Instead of going straight to individual, try smaller batches
                    if len(batch) > 4:
                        mid = len(batch) // 2
                        halves = [batch[:mid], batch[mid:]]
                        print(f"    Retrying as 2 half-batches ({mid} + {len(batch)-mid} words)...")

                        for hi, half in enumerate(halves):
                            half_prompt = _build_batch_prompt(half)
                            half_pcm = generate_speech_raw(api_key, half_prompt, voice)
                            time.sleep(DELAY_BETWEEN_REQUESTS)

                            if half_pcm is None:
                                failed_words.extend(half)
                                print(f"      Half {hi+1} API FAILED")
                                continue

                            half_wav = tmp / f"half_{hi}.wav"
                            pcm_to_wav(half_pcm, half_wav)

                            half_results, ht_label = _try_split_with_cascade(
                                half_wav, half, words_dir
                            )

                            if half_results:
                                for word, path in half_results:
                                    print(f"      OK  {word}")
                                generated += len(half_results)
                            else:
                                # Clean up and queue for individual
                                for word in half:
                                    p = words_dir / f"{word}.mp3"
                                    p.unlink(missing_ok=True)
                                failed_words.extend(half)
                                print(f"      Half {hi+1} split also failed -- queuing individually")
                    else:
                        failed_words.extend(batch)
                        print(f"    Batch too small to halve -- queuing individually")

            time.sleep(DELAY_BETWEEN_REQUESTS)

    # ── Phase 2: Special words (individual calls) ────────────────────
    if special_words:
        print(f"\n  Generating {len(special_words)} special words individually...")
        for word in special_words:
            out = words_dir / f"{word}.mp3"
            if out.exists():
                continue
            if _quota_exhausted:
                failed_words.append(word)
                continue

            prompt = WORD_SPECIAL_PROMPTS[word]
            print(f"    {word}...", end=" ", flush=True)
            ok = generate_speech(api_key, prompt, voice, out)
            print("OK" if ok else "FAILED")
            if ok:
                generated += 1
            else:
                failed_words.append(word)
            time.sleep(DELAY_BETWEEN_REQUESTS)

    # ── Phase 3: Fallback for failed batches ─────────────────────────
    if failed_words:
        # Deduplicate and filter already-generated
        remaining = [w for w in dict.fromkeys(failed_words) if not (words_dir / f"{w}.mp3").exists()]
        if remaining and not _quota_exhausted:
            print(f"\n  Fallback: generating {len(remaining)} words individually...")
            for word in remaining:
                if _quota_exhausted:
                    print(f"\n  Stopping -- quota exhausted. {len(remaining)} words remaining.")
                    break
                out = words_dir / f"{word}.mp3"
                prompt = WORD_SPECIAL_PROMPTS.get(word, (
                    # Use the same Audio Profile style for consistency
                    f'You are a warm, patient reading teacher. '
                    f'Say the word "{word}" clearly and slowly, as if teaching a young child to read. '
                    f'Pronounce it once, warmly and encouragingly. '
                    f'Just the single word, nothing else.'
                ))
                print(f"    {word}...", end=" ", flush=True)
                ok = generate_speech(api_key, prompt, voice, out)
                print("OK" if ok else "FAILED")
                if ok:
                    generated += 1
                time.sleep(DELAY_BETWEEN_REQUESTS)

    # Summary
    final_count = len(list(words_dir.glob("*.mp3")))
    print(f"\n  {label.capitalize()} summary:")
    print(f"    Already had:  {len(already_done)}")
    print(f"    Generated:    {generated}")
    print(f"    Total on disk: {final_count}")
    still_missing = [w for w in word_list if not (words_dir / f"{w}.mp3").exists()]
    if still_missing:
        print(f"    Still missing: {len(still_missing)} -- {', '.join(still_missing[:20])}")
        if len(still_missing) > 20:
            print(f"      ... and {len(still_missing) - 20} more")
    if _quota_exhausted:
        print(f"\n  NOTE: Daily API quota exhausted. Re-run later to generate remaining files.")


def generate_words_individual(api_key: str, voice: str, base_path: Path,
                               word_list: list, label: str = "word"):
    """Generate word pronunciations one at a time (legacy mode)."""
    print(f"\nGenerating {len(word_list)} {label} pronunciations (individual mode)...")
    print(f"   Voice: {voice}")
    print(f"   API calls: {len(word_list)}")
    print(f"   Estimated time: ~{len(word_list) * DELAY_BETWEEN_REQUESTS / 60:.0f} minutes\n")

    skipped = 0
    generated = 0
    failed = 0
    for i, word in enumerate(word_list):
        out = base_path / "words" / f"{word}.mp3"
        if out.exists():
            skipped += 1
            continue

        prompt = WORD_SPECIAL_PROMPTS.get(word, (
            f'Say the word "{word}" clearly and slowly, as if teaching a young '
            f'child to read. Pronounce it once, warmly and encouragingly. '
            f'Just the single word, nothing else.'
        ))

        print(f"  [{i+1}/{len(word_list)}] {word}...", end=" ", flush=True)
        ok = generate_speech(api_key, prompt, voice, out)
        print("OK" if ok else "FAILED")
        if ok:
            generated += 1
        else:
            failed += 1

        time.sleep(DELAY_BETWEEN_REQUESTS)

    if skipped:
        print(f"  Skipped {skipped} existing files")
    if failed:
        print(f"  {failed} failed")
    print(f"{label.capitalize()} complete! ({generated} new, {skipped} existing)")


def generate_letters(api_key: str, voice: str, base_path: Path):
    """Generate phonetic letter sounds."""
    print(f"\nGenerating 26 phonetic letter sounds...")

    skipped = 0
    for letter in "abcdefghijklmnopqrstuvwxyz":
        out = base_path / "letters" / f"{letter}.mp3"
        if out.exists():
            skipped += 1
            continue

        prompt = LETTER_PHONETIC_PROMPTS[letter]

        print(f"  {letter}...", end=" ", flush=True)
        ok = generate_speech(api_key, prompt, voice, out)
        print("OK" if ok else "FAILED")

        time.sleep(DELAY_BETWEEN_REQUESTS)

    if skipped:
        print(f"  Skipped {skipped} existing files")
    print(f"Letters complete!")


def generate_letter_names(api_key: str, voice: str, base_path: Path, batch_size: int):
    """Generate spoken letter NAME audio using batch mode for efficiency."""
    names_dir = base_path / "letter_names"
    all_letters = list("abcdefghijklmnopqrstuvwxyz")

    already_done = [l for l in all_letters if (names_dir / f"{l}.mp3").exists()]
    remaining = [l for l in all_letters if not (names_dir / f"{l}.mp3").exists()]

    batch_count = (len(remaining) + batch_size - 1) // batch_size if remaining else 0

    print(f"\n{'='*56}")
    print(f"  Generating letter NAME audio -- BATCH MODE")
    print(f"{'='*56}")
    print(f"  Total letters:  26")
    print(f"  Already done:   {len(already_done)} (skipped)")
    print(f"  Remaining:      {len(remaining)} -> {batch_count} batches of <={batch_size}")
    print(f"  Voice: {voice}")
    print()

    if not remaining:
        print("  All letter names already generated!")
        return

    generated = 0
    failed_letters = []

    # Use batch mode: 10-13 letters per call = 2-3 calls for all 26
    batches = [remaining[i:i+batch_size] for i in range(0, len(remaining), batch_size)]

    for batch_idx, batch in enumerate(batches):
        batch = [l for l in batch if not (names_dir / f"{l}.mp3").exists()]
        if not batch:
            continue
        if _quota_exhausted:
            failed_letters.extend(batch)
            continue

        print(f"  Batch {batch_idx+1}/{len(batches)} ({len(batch)} letters): {', '.join(batch)}")

        # Build batch prompt for letter names
        letter_list = "\n".join(f"{i+1}. {l.upper()}" for i, l in enumerate(batch))
        prompt = (
            f'You are a warm, patient reading teacher with a clear, gentle voice.\n'
            f'You are in a quiet classroom helping a young child learn the alphabet.\n\n'
            f'Say each of the following {len(batch)} letter NAMES ONE AT A TIME.\n'
            f'- Say the standard English alphabet name for each letter\n'
            f'- Pronounce each clearly and slowly\n'
            f'- Use a warm, encouraging tone\n'
            f'- Take a FULL 3-second silent pause between each letter\n'
            f'- Say ONLY the letter names — no numbers, no commentary, no extra sounds\n\n'
            f'Letters to say in order:\n{letter_list}'
        )

        batch_timeout = max(120, len(batch) * 15)
        pcm = generate_speech_raw(api_key, prompt, voice, timeout=batch_timeout)
        if pcm is None:
            print(f"    API FAILED -- queuing {len(batch)} letters for fallback")
            failed_letters.extend(batch)
            time.sleep(DELAY_BETWEEN_REQUESTS)
            continue

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            batch_wav = tmp / "batch.wav"
            pcm_to_wav(pcm, batch_wav)

            dur = get_audio_duration(batch_wav)
            print(f"    Audio: {dur:.1f}s ({dur/len(batch):.1f}s avg/letter)")

            results, threshold_label = _try_split_with_cascade(
                batch_wav, batch, names_dir
            )

            if results:
                for letter, path in results:
                    print(f"    OK  {letter}")
                if threshold_label != "default":
                    print(f"    (used {threshold_label} threshold)")
                generated += len(results)
            else:
                for letter in batch:
                    p = names_dir / f"{letter}.mp3"
                    p.unlink(missing_ok=True)
                print(f"    SPLIT FAILED at all thresholds")
                failed_letters.extend(batch)

        time.sleep(DELAY_BETWEEN_REQUESTS)

    # Fallback: generate failed letters individually
    if failed_letters:
        remaining_fails = [l for l in dict.fromkeys(failed_letters) if not (names_dir / f"{l}.mp3").exists()]
        if remaining_fails and not _quota_exhausted:
            print(f"\n  Fallback: generating {len(remaining_fails)} letter names individually...")
            for letter in remaining_fails:
                if _quota_exhausted:
                    break
                out = names_dir / f"{letter}.mp3"
                prompt = LETTER_NAME_PROMPTS[letter]
                print(f"    {letter}...", end=" ", flush=True)
                ok = generate_speech(api_key, prompt, voice, out)
                print("OK" if ok else "FAILED")
                if ok:
                    generated += 1
                time.sleep(DELAY_BETWEEN_REQUESTS)

    final_count = len(list(names_dir.glob("*.mp3")))
    print(f"\n  Letter names summary:")
    print(f"    Already had:   {len(already_done)}")
    print(f"    Generated:     {generated}")
    print(f"    Total on disk: {final_count}")
    still_missing = [l for l in all_letters if not (names_dir / f"{l}.mp3").exists()]
    if still_missing:
        print(f"    Still missing: {len(still_missing)} -- {', '.join(still_missing)}")


def generate_phrases(api_key: str, voice: str, base_path: Path, name: str):
    """Generate personalized encouragement phrases with the player's name."""
    phrases_dir = base_path / "phrases"
    total = sum(len(v) for v in PHRASE_TEMPLATES.values())
    print(f"\nGenerating {total} personalized phrases for '{name}'...")

    skipped = 0
    generated = 0
    for category, templates in PHRASE_TEMPLATES.items():
        for idx, template in enumerate(templates):
            phrase = template.format(name=name)
            filename = f"{category}_{idx}.mp3"
            out = phrases_dir / filename

            if out.exists():
                skipped += 1
                continue

            prompt = (
                f'Say the following phrase warmly and enthusiastically, as if praising '
                f'a young child who just did something great: "{phrase}" '
                f'Say it clearly with genuine excitement and warmth. '
                f'Just the phrase, nothing else.'
            )

            print(f"  [{category}/{idx}] \"{phrase}\"...", end=" ", flush=True)
            ok = generate_speech(api_key, prompt, voice, out)
            print("OK" if ok else "FAILED")
            if ok:
                generated += 1

            time.sleep(DELAY_BETWEEN_REQUESTS)

    # Also generate the name by itself
    name_out = phrases_dir / "name.mp3"
    if not name_out.exists():
        prompt = (
            f'Say the name "{name}" clearly and warmly, as if greeting a child. '
            f'Just the name, nothing else.'
        )
        print(f"  [name] \"{name}\"...", end=" ", flush=True)
        ok = generate_speech(api_key, prompt, voice, name_out)
        print("OK" if ok else "FAILED")
        if ok:
            generated += 1
    else:
        skipped += 1

    if skipped:
        print(f"  Skipped {skipped} existing files")
    print(f"Phrases complete! ({generated} new)")


def generate_stickers(api_key: str, voice: str, base_path: Path):
    """Generate TTS audio for all sticker names."""
    words_dir = base_path / "words"
    total = len(STICKER_NAMES)
    print(f"\nGenerating {total} sticker name audio clips...")

    skipped = 0
    generated = 0
    for audio_key, spoken_name in STICKER_NAMES.items():
        out = words_dir / f"{audio_key}.mp3"
        if out.exists():
            skipped += 1
            continue

        prompt = (
            f'Say "{spoken_name}" clearly and enthusiastically, as if announcing '
            f'a fun reward or achievement to a young child. '
            f'Use a warm, celebratory tone. Just the phrase, nothing else.'
        )

        print(f"  [sticker] \"{spoken_name}\" -> {audio_key}.mp3...", end=" ", flush=True)
        ok = generate_speech(api_key, prompt, voice, out)
        print("OK" if ok else "FAILED")
        if ok:
            generated += 1

        time.sleep(DELAY_BETWEEN_REQUESTS)

    if skipped:
        print(f"  Skipped {skipped} existing files")
    print(f"Sticker audio complete! ({generated} new)")


def generate_effects_placeholder(base_path: Path):
    """Remind about sound effects."""
    effects_dir = base_path / "effects"
    existing = list(effects_dir.glob("*.mp3"))
    if len(existing) >= 3:
        print(f"\nSound effects: {len(existing)} files found OK")
        return
    print(f"\nSound effects needed in {effects_dir}/:")
    print(f"   success.mp3    --short happy chime (word completed)")
    print(f"   error.mp3      --gentle buzz/boop (wrong letter)")
    print(f"   level_complete.mp3 --fanfare (level done!)")
    print(f"   Free sources: mixkit.co, freesound.org")


def main():
    parser = argparse.ArgumentParser(
        description="Generate TTS audio for Sight Words app using Gemini API (batch-optimized)"
    )
    parser.add_argument(
        "--api-key",
        default=os.environ.get("GEMINI_API_KEY"),
        help="Gemini API key (or set GEMINI_API_KEY env var)",
    )
    parser.add_argument(
        "--voice",
        default=DEFAULT_VOICE,
        help=f"Voice name (default: {DEFAULT_VOICE})",
    )
    parser.add_argument(
        "--output",
        default="assets/audio",
        help="Output directory (default: assets/audio)",
    )
    parser.add_argument(
        "--name",
        help="Child's name for personalized phrases (e.g., --name Emma)",
    )
    parser.add_argument(
        "--preview",
        help="Generate a single word for preview testing",
    )
    parser.add_argument(
        "--only",
        choices=["words", "letters", "letter_names", "phrases", "bonus", "stickers"],
        help="Generate only a specific category",
    )
    parser.add_argument(
        "--rpm",
        type=int,
        default=REQUESTS_PER_MINUTE,
        help=f"Max requests per minute (default: {REQUESTS_PER_MINUTE})",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=DEFAULT_BATCH_SIZE,
        help=f"Words per batch API call (default: {DEFAULT_BATCH_SIZE})",
    )
    parser.add_argument(
        "--no-batch",
        action="store_true",
        help="Disable batch mode --generate one word per API call (uses more quota)",
    )
    parser.add_argument(
        "--no-bonus",
        action="store_true",
        help="Skip bonus words, generate only Dolch words",
    )
    args = parser.parse_args()

    if not args.api_key:
        print("No API key! Set GEMINI_API_KEY env var or use --api-key")
        print("   Get one at: https://aistudio.google.com/apikey")
        print("")
        print("   Example:")
        print('     python generate_tts_gemini.py --api-key "AIzaSy..." --name Emma')
        sys.exit(1)

    global DELAY_BETWEEN_REQUESTS
    DELAY_BETWEEN_REQUESTS = 60.0 / args.rpm

    base_path = Path(args.output)
    ensure_dirs(base_path)

    use_batch = not args.no_batch

    print(f"{'='*52}")
    print(f"  Sight Words TTS Generator -- Gemini 2.5 Flash")
    print(f"{'='*52}")
    print(f"  Voice: {args.voice}")
    print(f"  Rate:  {args.rpm} req/min")
    mode_str = f"BATCH ({args.batch_size} words/call)" if use_batch else "Individual (1 word/call)"
    print(f"  Mode:  {mode_str}")
    if args.name:
        print(f"  Name:  {args.name}")
    print(f"{'='*52}")
    print()

    # Preview mode
    if args.preview:
        word = args.preview.lower()
        out = base_path / "words" / f"{word}.mp3"
        prompt = WORD_SPECIAL_PROMPTS.get(word, (
            f'Say the word "{word}" clearly and slowly, as if teaching '
            f'a young child to read. Just the single word, nothing else.'
        ))
        print(f"Preview: \"{args.preview}\"")
        ok = generate_speech(args.api_key, prompt, args.voice, out)
        if ok:
            print(f"Saved to: {out}")
        return

    # Build the word list
    include_bonus = not args.no_bonus

    # Add player name as a custom word if provided
    custom_words = []
    if args.name:
        name_lower = args.name.lower()
        if name_lower not in DOLCH_WORDS and name_lower not in BONUS_WORDS:
            custom_words.append(name_lower)

    all_words = list(DOLCH_WORDS)
    if include_bonus:
        all_words = sorted(set(all_words + BONUS_WORDS + custom_words))
    elif custom_words:
        all_words = sorted(set(all_words + custom_words))

    # Select generation function
    gen_words = (
        (lambda ak, v, bp, wl, lb: generate_words_batched(ak, v, bp, wl, args.batch_size, lb))
        if use_batch else generate_words_individual
    )

    # Full generation based on --only flag
    if args.only == "words":
        gen_words(args.api_key, args.voice, base_path, DOLCH_WORDS, "Dolch sight word")
    elif args.only == "bonus":
        bonus_with_custom = sorted(set(BONUS_WORDS + custom_words))
        gen_words(args.api_key, args.voice, base_path, bonus_with_custom, "bonus word")
    elif args.only == "letters":
        generate_letters(args.api_key, args.voice, base_path)
    elif args.only == "letter_names":
        generate_letter_names(args.api_key, args.voice, base_path, args.batch_size)
    elif args.only == "phrases":
        if not args.name:
            print("Error: --name is required for phrase generation")
            sys.exit(1)
        generate_phrases(args.api_key, args.voice, base_path, args.name)
    elif args.only == "stickers":
        generate_stickers(args.api_key, args.voice, base_path)
    else:
        # Generate everything
        gen_words(args.api_key, args.voice, base_path, all_words, "word")
        generate_letters(args.api_key, args.voice, base_path)
        generate_letter_names(args.api_key, args.voice, base_path, args.batch_size)
        generate_stickers(args.api_key, args.voice, base_path)
        if args.name:
            generate_phrases(args.api_key, args.voice, base_path, args.name)

    generate_effects_placeholder(base_path)

    # Final summary
    word_count = len(list((base_path / "words").glob("*.mp3")))
    letter_count = len(list((base_path / "letters").glob("*.mp3")))
    letter_name_count = len(list((base_path / "letter_names").glob("*.mp3")))
    phrase_count = len(list((base_path / "phrases").glob("*.mp3")))
    sticker_keys = set(STICKER_NAMES.keys())
    sticker_count = sum(1 for f in (base_path / "words").glob("*.mp3") if f.stem in sticker_keys)

    print(f"\n{'='*52}")
    print(f"  GENERATION COMPLETE")
    print(f"{'='*52}")
    print(f"  Words:        {word_count}")
    print(f"  Letters:      {letter_count}")
    print(f"  Letter Names: {letter_name_count}")
    print(f"  Stickers:     {sticker_count}/{len(STICKER_NAMES)}")
    print(f"  Phrases:      {phrase_count}")
    print(f"  Output:       {base_path.resolve()}")
    print(f"{'='*52}")


if __name__ == "__main__":
    main()

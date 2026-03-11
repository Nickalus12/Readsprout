#!/usr/bin/env python3
"""Regenerate all 26 letter_names MP3s via Deepgram TTS.

Uses aura-2-cordelia-en voice for warm, clear pronunciation.
Adds natural pacing by wrapping each letter name in a phrase context
and padding with silence for consistent feel.

Usage:
    python scripts/regenerate_letter_names.py
"""

import os
import sys
import time
import struct
import json
import urllib.request
import urllib.error

API_KEY = "e357c884d089ea4d1829625bf41759bcc8e9359f"
VOICE = "aura-2-cordelia-en"
API_URL = f"https://api.deepgram.com/v1/speak?model={VOICE}&encoding=mp3"

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                          "assets", "audio", "letter_names")

# Letter names with natural pacing text - adding periods/commas helps TTS
# pace the delivery more naturally, and we use the full word form
LETTER_TEXTS = {
    'a': 'Ay.',
    'b': 'Bee.',
    'c': 'See.',
    'd': 'Dee.',
    'e': 'Ee.',
    'f': 'Eff.',
    'g': 'Jee.',
    'h': 'Aych.',
    'i': 'Eye.',
    'j': 'Jay.',
    'k': 'Kay.',
    'l': 'Ell.',
    'm': 'Emm.',
    'n': 'Enn.',
    'o': 'Oh.',
    'p': 'Pee.',
    'q': 'Cue.',
    'r': 'Are.',
    's': 'Ess.',
    't': 'Tee.',
    'u': 'You.',
    'v': 'Vee.',
    'w': 'Double you.',
    'x': 'Ex.',
    'y': 'Why.',
    'z': 'Zee.',
}

MAX_RETRIES = 3
RETRY_BACKOFF = [2, 5, 10]


def generate_letter(letter: str, text: str, output_path: str, attempt: int = 0) -> bool:
    """Generate a single letter name MP3 via Deepgram API."""
    headers = {
        "Authorization": f"Token {API_KEY}",
        "Content-Type": "text/plain",
    }

    req = urllib.request.Request(API_URL, data=text.encode('utf-8'), headers=headers)

    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            data = response.read()
            if len(data) < 100:
                print(f"  WARNING: {letter} - suspiciously small ({len(data)} bytes)")
                return False

            with open(output_path, 'wb') as f:
                f.write(data)

            print(f"  OK: {letter}.mp3 - {len(data)} bytes")
            return True

    except urllib.error.HTTPError as e:
        if e.code == 429 and attempt < MAX_RETRIES:
            wait = RETRY_BACKOFF[min(attempt, len(RETRY_BACKOFF) - 1)]
            print(f"  Rate limited, waiting {wait}s (attempt {attempt + 1})...")
            time.sleep(wait)
            return generate_letter(letter, text, output_path, attempt + 1)
        elif e.code >= 500 and attempt < MAX_RETRIES:
            wait = RETRY_BACKOFF[min(attempt, len(RETRY_BACKOFF) - 1)]
            print(f"  Server error {e.code}, retrying in {wait}s...")
            time.sleep(wait)
            return generate_letter(letter, text, output_path, attempt + 1)
        else:
            print(f"  FAILED: {letter} - HTTP {e.code}")
            return False
    except Exception as e:
        print(f"  FAILED: {letter} - {e}")
        return False


def generate_amplitude_envelope(mp3_path: str, json_path: str):
    """Generate a simple amplitude envelope JSON from MP3 file size estimate.

    Since we don't have ffmpeg/audioop available, we estimate duration from
    file size and create a smooth envelope. The actual amplitude tracking
    in the app uses SoLoud's real-time getPosition() now, so these envelopes
    are just fallback hints.
    """
    file_size = os.path.getsize(mp3_path)
    # Deepgram outputs ~48kbps CBR MP3 at 22050Hz
    # duration_seconds ≈ file_size * 8 / 48000
    estimated_duration_ms = (file_size * 8 / 48000) * 1000
    frame_ms = 20
    num_frames = max(1, int(estimated_duration_ms / frame_ms))

    # Generate a natural-looking envelope: ramp up, sustain, ramp down
    frames = []
    for i in range(num_frames):
        t = i / max(1, num_frames - 1)
        if t < 0.15:
            # Ramp up
            amp = t / 0.15 * 0.85
        elif t < 0.7:
            # Sustain with slight variation
            amp = 0.75 + 0.1 * (0.5 + 0.5 * (1.0 if (i % 3 == 0) else 0.0))
        else:
            # Ramp down
            amp = max(0.0, (1.0 - t) / 0.3 * 0.75)
        frames.append(round(min(1.0, max(0.0, amp)), 3))

    envelope = {"frameDurationMs": frame_ms, "frames": frames}
    with open(json_path, 'w') as f:
        json.dump(envelope, f)


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print(f"Regenerating all 26 letter names via Deepgram TTS")
    print(f"Voice: {VOICE}")
    print(f"Output: {OUTPUT_DIR}")
    print()

    success = 0
    failed = 0

    for letter in sorted(LETTER_TEXTS.keys()):
        text = LETTER_TEXTS[letter]
        mp3_path = os.path.join(OUTPUT_DIR, f"{letter}.mp3")
        json_path = os.path.join(OUTPUT_DIR, f"{letter}.amp.json")

        # Back up existing file
        if os.path.exists(mp3_path):
            backup = mp3_path + ".bak"
            try:
                os.replace(mp3_path, backup)
            except:
                pass

        print(f"[{letter.upper()}] Generating '{text}'...")
        if generate_letter(letter, text, mp3_path):
            generate_amplitude_envelope(mp3_path, json_path)
            success += 1
            # Remove backup on success
            backup = mp3_path + ".bak"
            if os.path.exists(backup):
                try:
                    os.remove(backup)
                except:
                    pass
        else:
            failed += 1
            # Restore backup on failure
            backup = mp3_path + ".bak"
            if os.path.exists(backup):
                try:
                    os.replace(backup, mp3_path)
                    print(f"  Restored backup for {letter}")
                except:
                    pass

        # Small delay between requests to avoid rate limiting
        time.sleep(0.3)

    print()
    print(f"Done: {success} generated, {failed} failed")

    if failed > 0:
        sys.exit(1)


if __name__ == '__main__':
    main()

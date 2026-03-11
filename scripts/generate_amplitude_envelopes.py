#!/usr/bin/env python3
"""
Generate amplitude envelope JSON files for all MP3 audio assets.

For each MP3, extracts the RMS amplitude per ~20ms frame, normalizes to 0.0-1.0,
and saves a compact JSON file alongside the MP3 (e.g., the.mp3 -> the.amp.json).

Usage:
    python scripts/generate_amplitude_envelopes.py

Requires: pydub (pip install pydub) and ffmpeg on PATH.
Skips existing .amp.json files (safe to re-run).
"""

import json
import os
import sys
import struct
import subprocess
import math

# Frame duration in milliseconds
FRAME_MS = 20

# Audio directories to process (relative to assets/audio/)
AUDIO_DIRS = [
    'words',
    'letter_names',
    'phonics',
    'phrases',
]

def get_project_root():
    """Find the project root (directory containing pubspec.yaml)."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(script_dir)
    if os.path.exists(os.path.join(root, 'pubspec.yaml')):
        return root
    return os.getcwd()

def decode_mp3_to_pcm(mp3_path):
    """Decode MP3 to raw PCM (mono, 16-bit, 16kHz) using ffmpeg."""
    cmd = [
        'ffmpeg', '-i', mp3_path,
        '-f', 's16le',       # raw 16-bit signed little-endian PCM
        '-ac', '1',          # mono
        '-ar', '16000',      # 16kHz sample rate
        '-v', 'quiet',
        '-'
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, timeout=30)
        if result.returncode != 0:
            return None, 0
        return result.stdout, 16000
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None, 0

def compute_rms_envelope(pcm_data, sample_rate, frame_ms=FRAME_MS):
    """Compute RMS amplitude per frame from raw PCM bytes."""
    samples_per_frame = int(sample_rate * frame_ms / 1000)
    num_samples = len(pcm_data) // 2  # 16-bit = 2 bytes per sample

    if num_samples == 0:
        return []

    # Unpack all samples at once
    fmt = f'<{num_samples}h'
    try:
        samples = struct.unpack(fmt, pcm_data[:num_samples * 2])
    except struct.error:
        return []

    envelope = []
    for i in range(0, num_samples, samples_per_frame):
        chunk = samples[i:i + samples_per_frame]
        if not chunk:
            break
        # RMS calculation
        sum_sq = sum(s * s for s in chunk)
        rms = math.sqrt(sum_sq / len(chunk))
        envelope.append(rms)

    return envelope

def normalize_envelope(envelope):
    """Normalize envelope values to 0.0-1.0 range."""
    if not envelope:
        return []

    max_val = max(envelope)
    if max_val == 0:
        return [0.0] * len(envelope)

    return [round(v / max_val, 3) for v in envelope]

def process_mp3(mp3_path):
    """Process a single MP3 file and generate its .amp.json."""
    json_path = mp3_path.rsplit('.', 1)[0] + '.amp.json'

    # Skip if already exists
    if os.path.exists(json_path):
        return 'skipped'

    # Decode to PCM
    pcm_data, sample_rate = decode_mp3_to_pcm(mp3_path)
    if pcm_data is None or len(pcm_data) == 0:
        return 'failed'

    # Compute envelope
    envelope = compute_rms_envelope(pcm_data, sample_rate)
    if not envelope:
        return 'failed'

    # Normalize
    normalized = normalize_envelope(envelope)

    # Save compact JSON
    data = {
        'frameMs': FRAME_MS,
        'frames': normalized,
    }

    with open(json_path, 'w') as f:
        json.dump(data, f, separators=(',', ':'))

    return 'generated'

def main():
    root = get_project_root()
    audio_base = os.path.join(root, 'assets', 'audio')

    if not os.path.isdir(audio_base):
        print(f'Error: audio directory not found at {audio_base}')
        sys.exit(1)

    total = {'generated': 0, 'skipped': 0, 'failed': 0}

    for audio_dir in AUDIO_DIRS:
        dir_path = os.path.join(audio_base, audio_dir)
        if not os.path.isdir(dir_path):
            print(f'  Skipping {audio_dir}/ (not found)')
            continue

        mp3_files = sorted([f for f in os.listdir(dir_path) if f.endswith('.mp3')])
        dir_stats = {'generated': 0, 'skipped': 0, 'failed': 0}

        for mp3_file in mp3_files:
            mp3_path = os.path.join(dir_path, mp3_file)
            result = process_mp3(mp3_path)
            dir_stats[result] += 1
            total[result] += 1

        print(f'  {audio_dir}/: {len(mp3_files)} MP3s — '
              f'{dir_stats["generated"]} generated, '
              f'{dir_stats["skipped"]} skipped, '
              f'{dir_stats["failed"]} failed')

    print(f'\nTotal: {total["generated"]} generated, '
          f'{total["skipped"]} skipped, {total["failed"]} failed')

if __name__ == '__main__':
    main()

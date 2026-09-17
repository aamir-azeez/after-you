"""Rebuild After You's two original, rounded cushion-like foot contacts.

Run with Python 3.11+: python scripts/generate_footsteps.py
No recordings, external samples, dependencies or network are used. The short
falling-pitch body and soft noise have no resonant ring or wet texture.
Playback gain and the saved sound preference stay in services/soundscape.gd.
"""

from __future__ import annotations

import argparse
import io
import math
from pathlib import Path
import random
import struct
import wave

RATE = 44100
DURATION = 0.098


def render(variant: int) -> bytes:
    if variant not in (1, 2):
        raise ValueError("Footstep variant must be 1 or 2")
    noise = random.Random(4100 + variant)
    count = round(RATE * DURATION)
    start_frequency = 215.0 if variant == 1 else 232.0
    end_frequency = 158.0 if variant == 1 else 170.0
    pitch_decay = 0.026
    decay = 0.020 if variant == 1 else 0.019
    alpha = 1.0 - math.exp(-2.0 * math.pi * 550.0 / RATE)
    low = 0.0
    soft = 0.0
    samples: list[float] = []
    for index in range(count):
        time = index / RATE
        low += alpha * (noise.uniform(-1.0, 1.0) - low)
        soft += alpha * (low - soft)
        attack = math.sin(min(time / 0.012, 1.0) * math.pi / 2.0) ** 2
        release = math.sin(min((count - 1 - index) / (RATE * 0.025), 1.0) * math.pi / 2.0) ** 2
        envelope = attack * math.exp(-time / decay) * release
        # Integrate one gentle pitch dip: a rounded compression/release, without
        # a second inharmonic oscillator, resonance, repeated wobble or splash.
        phase = 2.0 * math.pi * (end_frequency * time +
                 (start_frequency - end_frequency) * pitch_decay * (1.0 - math.exp(-time / pitch_decay)))
        body = math.sin(phase) + 0.035 * math.sin(2.0 * phase)
        samples.append(envelope * (0.88 * body + 0.20 * soft))
    peak = max(abs(sample) for sample in samples)
    pcm = [round(32767 * 0.35 * sample / peak) for sample in samples]
    output = io.BytesIO()
    with wave.open(output, "wb") as clip:
        clip.setnchannels(1)
        clip.setsampwidth(2)
        clip.setframerate(RATE)
        clip.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))
    return output.getvalue()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parents[1] / "game/assets/audio")
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for variant in (1, 2):
        destination = args.output_dir / f"footstep-{variant}.wav"
        destination.write_bytes(render(variant))
        print(f"Wrote {destination.name}")


if __name__ == "__main__":
    main()

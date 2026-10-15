"""Checks the synthesised world cues: each shipped WAV is the approved one
(pinned hash), its recipe still makes it (to within one PCM step), and every
clip is clean (no clipping, no edge clicks, loops without a seam).
Measurements only; listening is still the owner's.
Run: python3 scripts/test_cues.py
"""
from __future__ import annotations

import hashlib
import io
import math
from pathlib import Path
import struct
import sys
import unittest
import wave

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_cues  # noqa: E402

RENDERED: dict[str, bytes] = {}


def rendered(name: str) -> bytes:
    if name not in RENDERED:
        RENDERED[name] = generate_cues.render(name)
    return RENDERED[name]


def samples(data: bytes) -> tuple[int, list[float]]:
    with wave.open(io.BytesIO(data), "rb") as clip:
        assert (clip.getnchannels(), clip.getsampwidth()) == (1, 2)
        rate, pcm = clip.getframerate(), clip.readframes(clip.getnframes())
    return rate, [s / 32768.0 for s in struct.unpack(f"<{len(pcm)//2}h", pcm)]


def rms(values: list[float]) -> float:
    return math.sqrt(sum(v * v for v in values) / max(1, len(values)))


class CuesTest(unittest.TestCase):
    def test_every_cue_is_pinned_and_shipped(self) -> None:
        self.assertEqual(set(generate_cues.APPROVED), set(generate_cues.CUES))
        for name in generate_cues.CUES:
            with self.subTest(name=name):
                shipped = generate_cues.OUT / f"{name}.wav"
                self.assertTrue(shipped.is_file(), f"{shipped} is missing")
                self.assertEqual(hashlib.sha256(shipped.read_bytes()).hexdigest(), generate_cues.APPROVED[name],
                                 "the shipped WAV is not the approved sound")

    def test_recipes_still_make_the_shipped_sound(self) -> None:
        # Another platform's maths library may round a sample the other way,
        # so a fresh render may differ from the shipped file by one step.
        for name in generate_cues.CUES:
            with self.subTest(name=name):
                rate, fresh = samples(rendered(name))
                shipped_rate, shipped = samples((generate_cues.OUT / f"{name}.wav").read_bytes())
                self.assertEqual((rate, len(fresh)), (shipped_rate, len(shipped)))
                worst = max(abs(a - b) for a, b in zip(fresh, shipped)) * 32768
                self.assertLessEqual(worst, 1.0, "the recipe no longer makes the shipped sound")

    def test_clips_are_clean(self) -> None:
        for name in generate_cues.CUES:
            with self.subTest(name=name):
                rate, values = samples(rendered(name))
                self.assertEqual(rate, generate_cues.RATE)
                peak = max(abs(v) for v in values)
                self.assertLessEqual(20 * math.log10(peak), -9.5, "leaves headroom like the other assets")
                self.assertGreater(20 * math.log10(peak), -10.5)
                if name in generate_cues.LOOPS:
                    # The last sample must run into the first like any other neighbour.
                    steps = [abs(values[i] - values[i - 1]) for i in range(1, len(values))]
                    self.assertLessEqual(abs(values[0] - values[-1]), max(steps) + 1e-9, "loop seam clicks")
                    window = rate // 20
                    head, tail = rms(values[:window]), rms(values[-window:])
                    if max(head, tail) > 1e-3:
                        self.assertLess(abs(20 * math.log10(max(head, 1e-6) / max(tail, 1e-6))), 6.0, "loop seam jumps in level")
                else:
                    self.assertLess(abs(values[0]) + abs(values[-1]), 2e-4, "one-shot starts and ends at zero")


if __name__ == "__main__":
    unittest.main()

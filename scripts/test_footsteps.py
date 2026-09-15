"""Bounded PCM checks for clipping/clicks, texture and shipped reproducibility.

These measurements support, but do not replace, listening on the target phone.
Run: python -m unittest discover -s scripts -p test_footsteps.py
"""

from __future__ import annotations

import io
import math
from pathlib import Path
import struct
import unittest
import wave

from generate_footsteps import render


class FootstepsTest(unittest.TestCase):
    def read(self, variant: int) -> tuple[int, list[float]]:
        with wave.open(io.BytesIO(render(variant)), "rb") as clip:
            self.assertEqual((clip.getnchannels(), clip.getsampwidth()), (1, 2))
            rate = clip.getframerate()
            pcm = clip.readframes(clip.getnframes())
        samples = [sample / 32768.0 for sample in struct.unpack(f"<{len(pcm)//2}h", pcm)]
        return rate, samples

    def test_shipped_files_are_reproducible_and_distinct(self) -> None:
        root = Path(__file__).resolve().parents[1] / "game/assets/audio"
        for variant in (1, 2):
            self.assertEqual((root / f"footstep-{variant}.wav").read_bytes(), render(variant))
        self.assertNotEqual(render(1), render(2))

    def test_short_contacts_are_quiet_unclipped_and_have_smooth_edges(self) -> None:
        for variant in (1, 2):
            rate, samples = self.read(variant)
            self.assertGreaterEqual(len(samples) / rate, 0.07)
            self.assertLessEqual(len(samples) / rate, 0.11)
            self.assertLess(max(abs(sample) for sample in samples), 0.56)
            self.assertEqual((samples[0], samples[-1]), (0.0, 0.0))
            self.assertLess(abs(sum(samples) / len(samples)), 0.012)
            self.assertLess(max(abs(right-left) for left, right in zip(samples, samples[1:])), 0.025)
            tail = samples[-round(rate*0.008):]
            self.assertLess(max(abs(sample) for sample in tail), 0.008)

    def test_contact_energy_is_rounded_without_high_frequency_ring(self) -> None:
        for variant in (1, 2):
            rate, samples = self.read(variant)
            # A 900 Hz lowpass leaves only a small residual: the
            # contact is a low, broad tap rather than a sharp or metallic tick.
            alpha = 1.0 - math.exp(-2.0 * math.pi * 900.0 / rate)
            low = 0.0
            residual = 0.0
            energy = 0.0
            for sample in samples:
                low += alpha * (sample-low)
                residual += (sample-low)**2
                energy += sample**2
            self.assertGreater(energy, 0.01)
            self.assertLess(residual/energy, 0.055)
            early = samples[:round(rate*0.030)]
            late = samples[round(rate*0.050):]
            self.assertGreater(sum(x*x for x in early)/len(early), 8.0*sum(x*x for x in late)/len(late))


if __name__ == "__main__":
    unittest.main()

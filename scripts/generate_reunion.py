"""Recreate the original reunion greeting (no recordings or external samples).

Optional asset-authoring tool: requires NumPy and SciPy. Neither the game nor CI
needs these packages; the generated PCM16 WAV is checked into the repository.
"""
from pathlib import Path
import argparse
import hashlib
import io
import wave

import numpy as np
from scipy.signal import butter, sosfilt

RATE = 44100
APPROVED_SHA256 = "442e0dc0ebaf7faa77b1646f3d7e6f4522a77db9a65db06832e2d29eed21e5d2"


def chirp(duration, pitch_points, seed, roundness):
    t = np.arange(round(duration * RATE)) / RATE
    f = np.interp(t, np.linspace(0, duration, len(pitch_points)), pitch_points)
    f *= 1 + 0.003 * np.sin(2 * np.pi * 8 * t) * np.sin(np.pi * t / duration) ** 2
    phase = 2 * np.pi * np.cumsum(f) / RATE
    body = np.sin(phase) + roundness * np.sin(2 * phase) + 0.045 * np.sin(3 * phase)
    rng = np.random.default_rng(seed)
    air = sosfilt(butter(2, [900, 2800], btype="bandpass", fs=RATE, output="sos"),
                  rng.standard_normal(t.size))
    envelope = (np.sin(np.minimum(t / 0.024, 1) * np.pi / 2) ** 2
                * np.sin(np.minimum((duration - t) / 0.065, 1) * np.pi / 2) ** 2)
    envelope *= 0.86 + 0.14 * np.sin(np.pi * t / duration)
    return envelope * (body + 0.009 * air)


def render():
    sound = np.zeros(round(0.65 * RATE))
    for seconds, clip, gain in [
        (0.025, chirp(0.205, [390, 440, 530, 490], 101, 0.13), 0.92),
        (0.265, chirp(0.27, [565, 695, 750, 640], 102, 0.11), 1),
    ]:
        start = round(seconds * RATE)
        sound[start:start + len(clip)] += gain * clip
    sound = sosfilt(butter(2, 100, btype="highpass", fs=RATE, output="sos"), sound)
    sound = sosfilt(butter(2, 4800, fs=RATE, output="sos"), sound)
    active = sound[np.abs(sound) > 0.015 * np.max(np.abs(sound))]
    gain = min(0.115 / np.sqrt(np.mean(active ** 2)), 0.32 / np.max(np.abs(sound)))
    sound *= gain
    fade = min(round(0.014 * RATE), len(sound) // 2)
    sound[:fade] *= np.linspace(0, 1, fade)
    sound[-fade:] *= np.linspace(1, 0, fade)
    if not np.isfinite(sound).all() or np.max(np.abs(sound)) >= 1:
        raise ValueError("Invalid or clipped PCM")
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(np.rint(sound * 32767).astype("<i2").tobytes())
    data = buffer.getvalue()
    if hashlib.sha256(data).hexdigest() != APPROVED_SHA256:
        raise ValueError("Synthesis output differs from the approved sound; existing asset was not changed")
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).resolve().parents[1] / "game/assets/audio/reunion.wav")
    args = parser.parse_args()
    data = render()
    args.output.write_bytes(data)
    print(f"Wrote {args.output}: {APPROVED_SHA256}")


if __name__ == "__main__":
    main()

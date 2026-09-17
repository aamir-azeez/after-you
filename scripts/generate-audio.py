"""Generate After You's original, deterministic interface and puzzle sounds.

Uses only Python's standard library. The generated WAV files share the project's
MIT license; no samples or external recordings are used.
"""
from pathlib import Path
import math
import struct
import wave
from generate_footsteps import render as render_footstep

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "game" / "assets" / "audio"


def note(t, frequency, duration, gain=0.35):
    if t < 0 or t >= duration:
        return 0.0
    attack = min(1.0, t / 0.008)
    release = min(1.0, (duration - t) / 0.07)
    envelope = attack * release * math.exp(-4.2 * t / duration)
    return gain * envelope * (math.sin(2 * math.pi * frequency * t)
                             + 0.22 * math.sin(4 * math.pi * frequency * t))


def write(name, seconds, sample):
    values = [max(-0.9, min(0.9, sample(i / RATE))) for i in range(int(seconds * RATE))]
    with wave.open(str(OUT / f"{name}.wav"), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b"".join(struct.pack("<h", round(v * 32767)) for v in values))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    write("bridge", 0.30, lambda t: note(t, 196, 0.27, 0.25) + note(t - 0.055, 294, 0.22, 0.17))
    write("throw", 0.25, lambda t: note(t, 380 + 900 * t, 0.25, 0.24))
    write("land", 0.16, lambda t: note(t, 170, 0.16, 0.25))
    write("miss", 0.35, lambda t: note(t, 240 - 160 * t, 0.35, 0.18))
    write("catch", 0.52, lambda t: note(t, 659.255, 0.42, 0.28) + note(t - 0.075, 987.767, 0.42, 0.22))
    write("bloom", 1.35, lambda t: sum(note(t - i * 0.13, f, 0.85, 0.19)
                                      for i, f in enumerate([261.626, 329.628, 391.995, 523.251])))
    write("ready", 0.55, lambda t: note(t, 392, 0.4, 0.18) + note(t - 0.10, 523.251, 0.4, 0.15))
    # One recipe owns the softened contacts in both asset-generation commands.
    for variant in (1, 2):
        (OUT / f"footstep-{variant}.wav").write_bytes(render_footstep(variant))
    # Integral periods and a smooth edge fade prevent clicks when this calm bed loops.
    def ambience(t):
        edge = min(1.0, t / 1.8, (16.0 - t) / 1.8)
        return edge * sum(0.018 * math.sin(2 * math.pi * f * t) * (0.72 + 0.28 * math.sin(2 * math.pi * t / 16 + i))
                          for i, f in enumerate([130.8125, 164.8125, 196.0, 261.625]))
    write("ambience", 16.0, ambience)
    print(f"Generated {len(list(OUT.glob('*.wav')))} original WAV assets.")


if __name__ == "__main__":
    main()

"""Generate After You's synthesised world cues: bell, well plunk, reel, water, bird calls
and the hand-worked controls (winch, bolt, valve).

Run with Python 3.11+, standard library only. No recordings, samples or network:
    python scripts/generate_cues.py            # rebuild every cue, refuse any drift
    python scripts/generate_cues.py --only reel --accept
Each cue is one render function plus its pinned SHA-256 in APPROVED. To change a
sound, edit its recipe, run with --accept, listen, then paste the printed hash
into APPROVED; scripts/test_cues.py fails while the shipped file, the recipe and
the pin disagree. Levels, pitch ranges and which event plays which cue live in
game/services/sound_cues.gd, not here; every file is peak-normalised.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import math
from pathlib import Path
import random
import struct
import wave

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "game" / "assets" / "audio"
PEAK_DBFS = -10.0


# ---- building blocks ----------------------------------------------------------
class Biquad:
    """RBJ cookbook filter: "lp", "hp", "bp" (constant 0 dB peak gain) or
    "hs", a high shelf of gain_db above freq."""

    def __init__(self, kind: str, freq: float, q: float = 0.707, gain_db: float = 0.0):
        self.kind, self.q, self.gain_db = kind, q, gain_db
        self.x1 = self.x2 = self.y1 = self.y2 = 0.0
        self.set(freq)

    def set(self, freq: float) -> None:
        w = 2 * math.pi * min(freq, RATE * 0.45) / RATE
        cw, alpha = math.cos(w), math.sin(w) / (2 * self.q)
        if self.kind == "hs":
            amp = 10 ** (self.gain_db / 40)
            root = 2 * math.sqrt(amp) * alpha
            b = (amp * ((amp + 1) + (amp - 1) * cw + root), -2 * amp * ((amp - 1) + (amp + 1) * cw),
                 amp * ((amp + 1) + (amp - 1) * cw - root))
            a0 = (amp + 1) - (amp - 1) * cw + root
            self.b = [x / a0 for x in b]
            self.a = (2 * ((amp - 1) - (amp + 1) * cw) / a0, ((amp + 1) - (amp - 1) * cw - root) / a0)
            return
        if self.kind == "lp":
            b = ((1 - cw) / 2, 1 - cw, (1 - cw) / 2)
        elif self.kind == "hp":
            b = ((1 + cw) / 2, -(1 + cw), (1 + cw) / 2)
        else:
            b = (alpha, 0.0, -alpha)
        a0 = 1 + alpha
        self.b = [x / a0 for x in b]
        self.a = ((-2 * cw) / a0, (1 - alpha) / a0)

    def __call__(self, x: float) -> float:
        y = self.b[0] * x + self.b[1] * self.x1 + self.b[2] * self.x2 - self.a[0] * self.y1 - self.a[1] * self.y2
        self.x2, self.x1, self.y2, self.y1 = self.x1, x, self.y1, y
        return y


def silence(seconds: float) -> list[float]:
    return [0.0] * int(seconds * RATE)


def noise(seconds: float, seed: int) -> list[float]:
    rng = random.Random(seed)
    return [rng.uniform(-1.0, 1.0) for _ in range(int(seconds * RATE))]


def tone(freq_at, seconds: float, env, harmonics=(1.0,)) -> list[float]:
    """Phase-integrated tone: freq_at(t) in Hz, env(t) amplitude."""
    out, phase = [], 0.0
    for i in range(int(seconds * RATE)):
        t = i / RATE
        phase += 2 * math.pi * freq_at(t) / RATE
        out.append(env(t) * sum(h * math.sin((k + 1) * phase) for k, h in enumerate(harmonics) if h))
    return out


def overlay(dest: list[float], src: list[float], at: float, gain: float = 1.0) -> None:
    start = int(at * RATE)
    for i, s in enumerate(src):
        if 0 <= start + i < len(dest):
            dest[start + i] += gain * s


def droplet(freq: float, seconds: float = 0.05) -> list[float]:
    """A small water plink: a bubble whose pitch rises as it closes."""
    return tone(lambda t: freq * (1.0 + 1.6 * t / seconds), seconds,
                lambda t: math.sin(min(t / 0.002, 1) * math.pi / 2) * math.exp(-t / (seconds * 0.35)))


def soft_onset(t: float, seconds: float) -> float:
    return math.sin(min(t / seconds, 1.0) * math.pi / 2)


def one_shot(samples: list[float], fade_ms: float = 4.0) -> list[float]:
    """Peak-normalise and fade both ends so the clip starts and ends at zero."""
    n = min(len(samples) // 2, int(fade_ms / 1000 * RATE))
    for i in range(n):
        f = math.sin(i / n * math.pi / 2) ** 2
        samples[i] *= f
        samples[-1 - i] *= f
    return normalise(samples)


def seamless(render, seconds: float, overlap: float) -> list[float]:
    """Render seconds + overlap, then fold the overlap into the head so the
    last sample runs straight into the first."""
    raw = render(seconds + overlap)
    length, cross = int(seconds * RATE), int(overlap * RATE)
    out = raw[:length]
    for i in range(cross):
        w = i / cross
        out[i] = raw[i] * w + raw[length + i] * (1.0 - w)
    return normalise(out)


def normalise(samples: list[float]) -> list[float]:
    peak = max(abs(s) for s in samples) or 1.0
    gain = 10 ** (PEAK_DBFS / 20) / peak
    return [s * gain for s in samples]


# ---- cues -------------------------------------------------------------------
def bell() -> list[float]:
    """A warm tower bell on C4: hum, prime, minor tierce, quint and nominal
    partials, each with its own decay and a slowly beating twin."""
    partials = ((0.5, 0.35, 3.0), (1.0, 0.5, 2.2), (1.2, 0.42, 1.8), (1.5, 0.22, 1.2),
                (2.0, 0.55, 1.5), (2.52, 0.18, 0.6), (3.0, 0.12, 0.4))
    out = silence(3.0)
    for ratio, amp, decay in partials:
        f = 261.63 * ratio
        for i in range(len(out)):
            t = i / RATE
            out[i] += amp * min(t / 0.002, 1.0) * math.exp(-t / decay) * (
                math.sin(2 * math.pi * f * t) + 0.5 * math.sin(2 * math.pi * (f + 0.7) * t))
    strike, bp = noise(0.02, 51), Biquad("bp", 3000, 2.0)
    overlay(out, [bp(x) * math.exp(-i / RATE / 0.004) for i, x in enumerate(strike)], 0.0, 0.6)
    tail = int(0.25 * RATE)
    for i in range(tail):
        out[-1 - i] *= i / tail
    return one_shot(out)


def pop() -> list[float]:
    """A soft bubble pop for an end-of-run reaction: a little rounded thump and a
    quick, gently rising plink, done in under a fifth of a second."""
    out = silence(0.2)
    overlay(out, tone(lambda t: 210.0, 0.05, lambda t: soft_onset(t, 0.004) * math.exp(-t / 0.012)), 0.0, 0.3)
    overlay(out, tone(lambda t: 640.0 * (1.0 + 0.8 * min(t / 0.05, 1.0) ** 1.4), 0.15,
                      lambda t: soft_onset(t, 0.003) * math.exp(-t / 0.028), (1.0, 0.18)), 0.006, 1.0)
    return one_shot(out)


def well_plunk() -> list[float]:
    """A soft, rounded plunk into the well: low body, one big bubble, two small ones."""
    out = silence(0.6)
    overlay(out, tone(lambda t: 95.0, 0.12, lambda t: soft_onset(t, 0.004) * math.exp(-t / 0.03)), 0.0, 0.6)
    overlay(out, tone(lambda t: 380 * (1 + 2.2 * min(t / 0.09, 1) ** 1.5), 0.16,
                      lambda t: soft_onset(t, 0.003) * math.exp(-t / 0.045), (1.0, 0.12)), 0.01, 1.0)
    overlay(out, droplet(1100, 0.05), 0.17, 0.35)
    overlay(out, droplet(1500, 0.04), 0.29, 0.22)
    return one_shot(out)


def reel() -> list[float]:
    """A small rope reel turning: a wooden pawl ticking over the ratchet, rope
    hiss and a soft drum rumble. Loops seamlessly; playback pitch sets the
    apparent speed, so one clip serves buckets, ladders, folds and lifts."""
    period, ticks = 1 / 18, 9

    def render(seconds: float) -> list[float]:
        out = [0.0] * int(seconds * RATE)
        hiss_bp, rumble_lp = Biquad("bp", 1300, 0.9), Biquad("lp", 160)
        hiss, rumble = noise(seconds, 91), noise(seconds, 92)
        for i in range(len(out)):
            out[i] = 0.10 * hiss_bp(hiss[i]) + 0.55 * rumble_lp(rumble[i])
        rng = random.Random(93)
        accents = [rng.uniform(0.7, 1.0) for _ in range(ticks)]
        click_src = noise(0.012, 94)
        for n in range(int(seconds / period) + 1):
            bp, body = Biquad("bp", 2200, 3.0), Biquad("bp", 850, 6.0)
            click = [(bp(x) + 0.8 * body(x)) * math.exp(-i / RATE / 0.0025) for i, x in enumerate(click_src)]
            overlay(out, click, n * period, 0.9 * accents[n % ticks])
        return out

    return seamless(render, period * ticks, 0.04)


def water_lap() -> list[float]:
    """Harbour water against stone: a low wash with slow seeded laps."""
    def render(seconds: float) -> list[float]:
        rng = random.Random(61)
        lp, lp2 = Biquad("lp", 550), Biquad("lp", 380)
        laps = sorted((rng.uniform(0, seconds), rng.uniform(0.5, 1.1)) for _ in range(int(seconds * 0.9)))
        brown, out = 0.0, []
        for i in range(int(seconds * RATE)):
            t = i / RATE
            brown = 0.995 * brown + 0.06 * rng.uniform(-1, 1)
            swell = 0.55 + 0.25 * math.sin(2 * math.pi * t / 6.0) + 0.2 * math.sin(2 * math.pi * t / 2.4 + 1.0)
            for at, dur in laps:
                if at <= t < at + dur:
                    swell += 0.9 * math.sin(math.pi * (t - at) / dur) ** 2
            out.append(lp2(lp(brown)) * swell)
        splash, bp = noise(seconds, 62), Biquad("bp", 900, 0.9)
        for at, dur in laps:
            start = int((at + dur * 0.45) * RATE)
            for k in range(int(0.22 * RATE)):
                if start + k < len(out):
                    out[start + k] += 0.05 * bp(splash[start + k]) * math.sin(math.pi * k / (0.22 * RATE))
        return out

    return seamless(render, 12.0, 1.0)


def water_surge() -> list[float]:
    """Water rushing in as the tide turns: a filtered rush sweeping upward.
    Played lower, it reads as the water draining away."""
    src, bp, lp = noise(0.95, 71), Biquad("bp", 400, 0.8), Biquad("lp", 220)
    out = []
    for i, x in enumerate(src):
        u = i / len(src)
        bp.set(300 + 1300 * u)
        env = math.sin(math.pi * min(u / 0.35, 1.0) / 2) ** 2 * (1 - u) ** 1.3
        out.append(env * (bp(x) + 1.4 * lp(x)))
    return one_shot(out, 8.0)


def spout() -> list[float]:
    """The sluice spout pouring onto the beach: steady, with a light flutter."""
    def render(seconds: float) -> list[float]:
        src, hp, lp, rng = noise(seconds, 81), Biquad("hp", 400), Biquad("lp", 4800), random.Random(82)
        out = [lp(hp(x)) * (0.85 + 0.15 * math.sin(2 * math.pi * 7 * i / RATE)) for i, x in enumerate(src)]
        for _ in range(int(seconds * 6)):
            overlay(out, droplet(rng.uniform(900, 2200), 0.04), rng.uniform(0, seconds - 0.1), 0.15)
        return out

    return seamless(render, 4.0, 0.25)


def ratchet_click(seed: int) -> list[float]:
    """One pawl tick: the reel's click (a 2.2 kHz snap over an 850 Hz body)."""
    bp, body = Biquad("bp", 2200, 3.0), Biquad("bp", 850, 6.0)
    return [(bp(x) + 0.8 * body(x)) * math.exp(-i / RATE / 0.0025) for i, x in enumerate(noise(0.012, seed))]


def iron_tink(freq: float, seed: int, decay: float = 0.012) -> list[float]:
    """A small iron link touching its neighbour: a short ring at freq."""
    ring = Biquad("bp", freq, 12.0)
    return [ring(x) * math.exp(-i / RATE / decay) for i, x in enumerate(noise(0.05, seed))]


def thunk(freq: float, seconds: float, decay: float) -> list[float]:
    """A soft, rounded knock of timber or iron on timber."""
    return tone(lambda t: freq * (1.0 - 0.15 * min(t / seconds, 1.0)), seconds,
                lambda t: soft_onset(t, 0.003) * math.exp(-t / decay), (1.0, 0.3))


def mellow(samples: list[float], cutoff: float = 5000.0) -> list[float]:
    """Takes the edge off for small speakers: a low-pass and a -6 dB shelf over 3 kHz."""
    lp, shelf = Biquad("lp", cutoff), Biquad("hs", 3000, 0.6, -6.0)
    return [shelf(lp(s)) for s in samples]


def winch() -> list[float]:
    """A hand winch wound a turn and a half: five pawl ticks over the ratchet,
    slowing a little as the chain comes taut, a few links rattling over the
    drum and a soft drum thump under the first tick."""
    out, rng = silence(0.4), random.Random(101)
    overlay(out, thunk(120.0, 0.08, 0.02), 0.0, 0.35)
    at = 0.012
    for n in range(5):
        overlay(out, ratchet_click(102 + n), at, rng.uniform(0.75, 1.0))
        at += 0.058 + 0.008 * n
    for n in range(9):
        overlay(out, iron_tink(rng.uniform(2600, 3900), 110 + n), rng.uniform(0.03, 0.33), rng.uniform(0.10, 0.22))
    # The chain's rasp across the hawse, under everything.
    rasp, bp = noise(0.32, 120), Biquad("bp", 1500, 1.2)
    overlay(out, [0.06 * bp(x) * math.sin(math.pi * i / len(rasp)) for i, x in enumerate(rasp)], 0.03)
    return one_shot(mellow(out))


def bolt() -> list[float]:
    """A round iron bolt slid through its staples: a short dry scrape that
    rises as it runs, then a soft clunk into the catch and a faint iron ring."""
    out = silence(0.3)
    scrape, bp, rng = noise(0.2, 131), Biquad("bp", 900, 1.4), random.Random(132)
    grain = [rng.uniform(0.6, 1.0) for _ in range(40)]
    slide = []
    for i, x in enumerate(scrape):
        u = i / len(scrape)
        bp.set(900 + 700 * u)
        # Friction catches and lets go in small grains as the bolt runs.
        slide.append(bp(x) * math.sin(math.pi * min(u / 0.25, 1.0) / 2) * (0.5 + 0.5 * u) * grain[int(u * 39.999)])
    overlay(out, slide, 0.0, 0.45)
    overlay(out, thunk(135.0, 0.12, 0.028), 0.19, 1.0)
    click, cbp = noise(0.01, 133), Biquad("bp", 700, 2.0)
    overlay(out, [cbp(x) * math.exp(-i / RATE / 0.002) for i, x in enumerate(click)], 0.19, 0.9)
    overlay(out, iron_tink(1900.0, 134, 0.035), 0.192, 0.12)
    return one_shot(mellow(out, 4500.0))


def valve() -> list[float]:
    """An iron valve wheel turned: the spindle creaks round (stick-slip ticks
    ringing its iron housing, the ring gliding up as it turns), easing as it
    reaches the value, then a gentle stop on the mark."""
    out, rng = silence(0.35), random.Random(141)
    body, body2 = Biquad("bp", 480, 14.0), Biquad("bp", 1250, 16.0)
    creak = [0.0] * int(0.26 * RATE)
    t = 0.0
    while t < 0.25:
        i = int(t * RATE)
        if i < len(creak):
            creak[i] += rng.uniform(0.5, 1.0)
        # The spindle sticks less often as the turn slows to the value.
        t += 1.0 / rng.uniform(48.0, 60.0) * (1.0 + 0.7 * t / 0.25)
    for i, x in enumerate(creak):
        u = i / len(creak)
        body.set(480 + 80 * u)
        env = math.sin(math.pi * min(u / 0.2, 1.0) / 2) * (1.0 - 0.5 * u)
        creak[i] = env * (body(x) + 0.45 * body2(x))
    # A lone tick through a narrow ring is faint: bring the creak up to lead.
    overlay(out, creak, 0.0, 0.75 / max(abs(s) for s in creak))
    overlay(out, thunk(110.0, 0.09, 0.022), 0.255, 0.6)
    overlay(out, iron_tink(1600.0, 142, 0.02), 0.257, 0.08)
    return one_shot(mellow(out, 3500.0))


def bird_phrases() -> list[list[tuple]]:
    """The garden songbird the owner chose (preview 03a): three short whistled
    phrases and a faint second bird's "tsip" triple, as notes
    (at, f0, f1, dur, trill, gain) from the start of each phrase. The seeded
    draws run in 03a's order, so every note is 03a's own."""
    rng, phrases = random.Random(31), []
    for _ in range(3):
        notes, t = [], 0.0
        for _ in range(rng.randint(4, 6)):
            dur = rng.uniform(0.06, 0.13)
            f0 = rng.uniform(2700, 4000)
            f1 = f0 * rng.choice((0.8, 0.9, 1.15, 1.25))
            trill = rng.choice((0.0, 0.0, 38.0))
            notes.append((t, f0, f1, dur, trill, rng.uniform(0.6, 1.0)))
            t += dur + rng.uniform(0.03, 0.07)
        phrases.append(notes)
    phrases.append([(k * 0.09, 5200.0, 4300.0, 0.035, 0.0, 0.25) for k in range(3)])
    return phrases


def bird_call(phrase: int) -> list[float]:
    """One call of the Home birds, alone: the soundscape spaces the calls out
    and picks which one sings (game/services/sound_cues.gd CALLS). Softer than
    03a's loop: a -7 dB shelf above 3 kHz takes the edge off the whistles and
    the far bird's high "tsip", and 12 ms fades start and end it at zero."""
    notes = bird_phrases()[phrase]
    lead, tail = 0.012, 0.16

    def note(f0: float, f1: float, dur: float, trill: float) -> list[float]:
        return tone(lambda t: f0 + (f1 - f0) * (t / dur) + (150 * math.sin(2 * math.pi * trill * t) if trill else 0.0),
                    dur, lambda t: math.sin(math.pi * min(t / dur, 1.0)) ** 1.5, (1.0, 0.08))

    out = silence(lead + max(at + dur for at, _f0, _f1, dur, _tr, _g in notes) + tail)
    for at, f0, f1, dur, trill, gain in notes:
        overlay(out, note(f0, f1, dur, trill), lead + at, gain)
    # Distance: soften the top and add two faint ground reflections.
    lp, shelf = Biquad("lp", 6500), Biquad("hs", 3000, 0.6, -7.0)
    dry = [shelf(lp(s)) for s in out]
    wet = dry[:]
    for delay, gain in ((0.031, 0.22), (0.067, 0.12)):
        d = int(delay * RATE)
        for i in range(d, len(wet)):
            wet[i] += gain * dry[i - d]
    return one_shot(wet, 12.0)


# File name (in game/assets/audio) -> recipe. Keep in step with sound_cues.gd.
CUES = {
    "bell": bell,
    "well-plunk": well_plunk,
    "pop": pop,
    "reel": reel,
    "water-lap": water_lap,
    "water-surge": water_surge,
    "spout": spout,
    "birds-1": lambda: bird_call(0),
    "birds-2": lambda: bird_call(1),
    "birds-3": lambda: bird_call(2),
    "birds-far": lambda: bird_call(3),
    "winch": winch,
    "bolt": bolt,
    "valve": valve,
}
# Files that loop; scripts/test_cues.py checks their seams.
LOOPS = ("reel", "water-lap", "spout")
APPROVED = {
    "bell": "5c538dd5a486f328eb493e6d36d1c8be6b4ed46b6ffdb54881fd2b8d62184f32",
    "well-plunk": "782793645a1bf8d2a5f794666868655be34b5b27b4fe9941c67ba5e43a996fe5",
    "pop": "739a5feaed982e9c3ab5e94ce5f85d311197e8ed7dfdfcd3aa107d957c0bb502",
    "reel": "59c45d1333311996848299081d8d472cf1f7a9cefebe30c58da65eac2811bf09",
    "water-lap": "6df818f8b9fd6ed0649932e6e8e8320e2bb025a07fd59c32a6e348a7b5c37cef",
    "water-surge": "285300afaef13c4f5b5c0fea874894f09db4beee577c897007fb95de6ad18138",
    "spout": "d984c4e35b0b6c01028cf2a573fbcce6d9a2700bc24dc126e6e18401b64a267a",
    "birds-1": "81d1f24f084dd1790968eed93f0abd911b8556d6427ec6c1f77b9dc9fde6d143",
    "birds-2": "5ef55ebcc385d8cd192de5ca1a96c31ac1f690300fbdf5575e629f23044ca512",
    "birds-3": "f274b882c39be16a966323a42cb34e13b233f23a74758af78ab2d50120208b8e",
    "birds-far": "89632db35b3ff1dd685912bbd7c47ae8c8d39af44a3437abeef4ea1f1014f44b",
    "winch": "992c7263e17ef9705e868812df3c544bba8cc8247056ea60e3a1f2aa5be87c05",
    "bolt": "4b4b5e911025c3caa88d1e139ad48d1a428d89801a4f063e08387114ae939213",
    "valve": "681bb260ad66a8c40ef773085af9832030e1508fadd31e840e67b5374002ba55",
}


def encode(samples: list[float]) -> bytes:
    if max(abs(s) for s in samples) >= 1.0:
        raise ValueError("Clipped PCM")
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as clip:
        clip.setnchannels(1)
        clip.setsampwidth(2)
        clip.setframerate(RATE)
        clip.writeframes(struct.pack(f"<{len(samples)}h", *(round(s * 32767) for s in samples)))
    return buffer.getvalue()


def render(name: str) -> bytes:
    return encode(CUES[name]())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", choices=sorted(CUES), action="append", help="render only these cues")
    parser.add_argument("--accept", action="store_true", help="write even if the hash differs from APPROVED")
    parser.add_argument("--output-dir", type=Path, default=OUT)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    drift = []
    for name in args.only or CUES:
        data = render(name)
        digest = hashlib.sha256(data).hexdigest()
        if digest != APPROVED.get(name) and not args.accept:
            drift.append(f"    \"{name}\": \"{digest}\",")
            continue
        (args.output_dir / f"{name}.wav").write_bytes(data)
        print(f"Wrote {name}.wav {digest}")
    if drift:
        raise SystemExit("These cues differ from their approved hashes; nothing was written for them.\n"
                         "Listen with --accept, then update APPROVED:\n" + "\n".join(drift))


if __name__ == "__main__":
    main()

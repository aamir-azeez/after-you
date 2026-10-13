extends RefCounted
## The one motion-blur look, shared by every moving object that blurs: the
## rolling ball's spin exposure and the thrown seed's path exposure. Tune it
## here and every blur follows. Tuned from the long roll in Rolling Home's
## second stage, a little softer. Low graphics quality has no blur at all.

## Below this speed (m/s) nothing is exposed.
const MIN_SPEED := 0.45
## A jump longer than this (m) is a teleport and never streaks.
const TELEPORT_DISTANCE := 1.8
## A frame longer than this (s) resets the exposure instead of smearing it.
const MAX_SAMPLE_GAP := 0.20
## How quickly the measured velocity follows the object (1/s).
const VELOCITY_RESPONSE := 28.0
## Seconds for the exposure to grow in once an object starts moving, so a push
## eases into blur instead of snapping to it.
const START_RAMP := 0.12
## Seconds an object may stand still before its exposure starts to fade, and
## how long the fade takes.
const STOP_HOLD := 0.04
const STOP_FADE := 0.10
## Ball spin: samples across the exposure, and how much the oldest one counts
## against the newest (a soft shutter, so the smear trails off).
const SPIN_TAPS := 12
const SPIN_TAIL_WEIGHT := 0.35

## Per graphics quality:
## exposure  seconds of travel a path exposure shows (seed, other objects)
## spin      seconds of rotation a spinning ball shows
## max_spin  most rotation (radians) a ball smear may cover
## width     path exposure width as a share of the object's radius
## opacity   strength of a path exposure at its head
const PRESETS := {
	"balanced": {"exposure": 0.30, "spin": 0.050, "max_spin": 0.90, "width": 0.65, "opacity": 0.60},
	"high": {"exposure": 0.40, "spin": 0.060, "max_spin": 0.90, "width": 0.80, "opacity": 0.72},
}

static func preset(quality: String) -> Dictionary:
	return PRESETS.get(quality, PRESETS.balanced)

## 0 to 1 over START_RAMP, eased so the start has no visible step.
static func ramp(engaged_seconds: float) -> float:
	return smoothstep(0.0, START_RAMP, engaged_seconds)

## 1 while moving, easing to 0 over STOP_FADE after STOP_HOLD still seconds.
static func stop_fade(idle_seconds: float) -> float:
	return clampf(1.0 - maxf(0.0, idle_seconds - STOP_HOLD) / STOP_FADE, 0.0, 1.0)

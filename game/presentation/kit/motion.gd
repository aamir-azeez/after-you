extends RefCounted
## Motion curves shared by everything that moves for show: pips (spirit_visual.gd),
## ending scenes (services/ending_scene.gd), pieces and props. Every curve is a
## closed-form function of a time or a fraction, so a motion looks the same at
## any frame rate, in a replay and in a capture clip. No nodes, no state.
##
## - ease(name, u): u from 0 to 1 eased by name (EASES).
## - settle(age, amount, rate, damping): a damped wobble after something
##   happens (a stop, a landing, a hat that keeps going): starts at amount,
##   swings past zero rate times a second and dies away.
## - kick(age, length): a bump that rises and falls back to 0 over length
##   seconds (a wind-up's crouch, a jolt), 0 before and after.
## - squash(amount): a body scale that keeps its volume: positive squashes
##   (wider, lower), negative stretches (taller, thinner).
## - arrival(age, amount): the overshoot of a piece that has just come to rest
##   (a gate thudding shut, a handle thrown over, a lift stopping): 0 as it
##   arrives, out to amount past its stop, back a little, and exactly 0 from
##   ARRIVAL_SECONDS on, so the rest pose never moves.

## "inout" (smooth start and end), "in", "out", "linear", "back" (runs about
## 10% past the end and settles: a landing, a pop into place) and "bounce"
## (falls to the end and bounces to rest: something let fall).
const EASES := ["inout", "in", "out", "linear", "back", "bounce"]

static func ease(name: String, u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	match name:
		"linear": return u
		"in": return u * u
		"out": return 1.0 - (1.0 - u) * (1.0 - u)
		"back":
			var k := 1.70158
			var v := u - 1.0
			return 1.0 + (k + 1.0) * v * v * v + k * v * v
		"bounce": return _bounce(u)
	return u * u * (3.0 - 2.0 * u)

## A damped wobble: amount at age 0, swinging rate times a second, its size
## shrinking by e every 1 / damping seconds. 0 for a negative age.
static func settle(age: float, amount: float, rate: float = 3.0, damping: float = 6.0) -> float:
	if age < 0.0: return 0.0
	return amount * exp(-damping * age) * cos(TAU * rate * age)

## A single smooth bump over length seconds: 0, up to 1 at the middle, 0.
static func kick(age: float, length: float) -> float:
	if age < 0.0 or age >= length or length <= 0.0: return 0.0
	return sin(age / length * PI)

## A scale that keeps the body's volume: amount 0.1 is 10% lower and wider.
static func squash(amount: float) -> Vector3:
	var tall := clampf(1.0 - amount, 0.5, 1.5)
	var wide := 1.0 / sqrt(tall)
	return Vector3(wide, tall, wide)

## arrival(): how long the overshoot lasts, how many times a second it swings
## and how fast it dies away (e every 1 / ARRIVAL_DAMPING seconds).
const ARRIVAL_SECONDS := 0.7
const ARRIVAL_RATE := 2.0
const ARRIVAL_DAMPING := 8.0

## The overshoot age seconds after a piece arrives: 0 at age 0, its first
## swing reaching amount (signed: the way the piece was going), then dying
## away; exactly 0 before age 0 and from ARRIVAL_SECONDS on.
static func arrival(age: float, amount: float) -> float:
	if age <= 0.0 or age >= ARRIVAL_SECONDS: return 0.0
	var w := TAU * ARRIVAL_RATE
	var peak_age := atan(w / ARRIVAL_DAMPING) / w
	var peak := sin(w * peak_age) * exp(-ARRIVAL_DAMPING * peak_age)
	# Faded out over its last fifth so it lands on 0 without a step.
	var fade := 1.0 - smoothstep(ARRIVAL_SECONDS * 0.8, ARRIVAL_SECONDS, age)
	return amount * sin(w * age) * exp(-ARRIVAL_DAMPING * age) / peak * fade

static func _bounce(u: float) -> float:
	var n := 7.5625
	var d := 2.75
	if u < 1.0 / d: return n * u * u
	if u < 2.0 / d:
		u -= 1.5 / d
		return n * u * u + 0.75
	if u < 2.5 / d:
		u -= 2.25 / d
		return n * u * u + 0.9375
	u -= 2.625 / d
	return n * u * u + 0.984375

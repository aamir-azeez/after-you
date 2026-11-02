extends "res://presentation/keepsakes/keepsake_builder.gd"
## The Relay Isles keepsake: two tall masts with a line between them, and a
## basket of fruit. Tugging the rope at the first mast (walking up to it, or a
## tap) runs the flag up its cord beside the first mast and along the line to
## the far one; after a moment a second tug brings it back the same way to rest.
## Together: a mint third mast, so the flag is handed on down the second line
## and comes back up it. Hard: both masts stand on slate plinths with crossbars
## whose signal flags flick out as the flag passes. Together Hard: gold lamps on
## the mast tops light one after the other.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const POLE := 2.4
const ENDS: Array[float] = [-1.3, 1.3]
const HARD_LIFT := 0.34
const MINT_MAST := Vector3(2.0, 0, 0.5)
## The flag's cord runs up CORD_X beside the first mast. The flag clips to it
## by toggles at its hoist's ends, HANG above and below its pivot, the top one
## riding the lines too, and hangs FRONT in front of them so it passes the
## masts clear. FLY is how far its tip reaches from the hoist.
const CORD_X := 0.08
const HANG := 0.18
const FRONT := 0.065
const FLY := 0.56
## How far down the mint line (a share of it) the flag is handed on.
const HANDOFF := 0.65
## The flag's pace along its cord and the lines (metres a second), the gap
## between one stretch and the next, and how long it waits at the far end
## before coming back (longer when the tap has the time).
const SPEED := 3.0
const GAP := 0.05
const HOLD: Array[float] = [0.2, 0.5]
## Every beat of a tap together: the 4.5 s a tap may take, less the settle.
const TAP_MAX := 4.2

static func _y0(state: Dictionary) -> float:
	return HARD_LIFT if state.get("hard", false) else 0.0

func build(root: Node3D, state: Dictionary) -> Dictionary:
	var hard: bool = state.get("hard", false)
	var y0 := _y0(state)
	var parts := {}
	for index in range(2):
		var x: float = ENDS[index]
		if hard: P.plinth(root, 0.6, 0.6, Vector3(x, 0, 0))
		P.cyl(root, 0.26, 0.12, P.STONE_LIGHT, Vector3(x, y0 + 0.06, 0), 0.24)
		P.cyl(root, 0.05, POLE, P.WOOD, Vector3(x, y0 + POLE * 0.5, 0))
		P.sph(root, 0.07, P.CREAM, Vector3(x, y0 + POLE + 0.05, 0))
		if hard:
			# The crossbar's two signal flags flick out together, one row per mast.
			P.box(root, Vector3(0.7, 0.05, 0.05), P.WOOD, Vector3(x, y0 + POLE - 0.3, 0))
			var flags := P.pivot(root, Vector3(x, y0 + POLE - 0.32, 0), "Signals")
			for side: int in [-1, 1]: P.box(flags, Vector3(0.14, 0.18, 0.015), P.CORAL if side < 0 else P.CREAM, Vector3(side * 0.39, -0.1, 0))
			parts["signals_%d" % index] = flags
	var line := _line_y(state)
	P.bar(root, Vector3(ENDS[0], line, 0), Vector3(ENDS[1], line, 0), 0.02, P.CREAM)
	# The flag's cord, up beside the first mast from a cleat below the flag to the line.
	var cleat := _flag_rest(state).y - HANG - 0.08
	P.box(root, Vector3(0.016, line - cleat, 0.016), P.CREAM, Vector3(ENDS[0] + CORD_X, (line + cleat) * 0.5, 0))
	P.box(root, Vector3(0.1, 0.03, 0.04), P.WOOD_LIGHT, Vector3(ENDS[0] + 0.06, cleat, 0))
	# The pull rope hangs from the first mast to the pip's height, with a wooden toggle.
	var rope := P.pivot(root, Vector3(ENDS[0] + 0.12, y0 + POLE - 0.1, 0.12), "Rope")
	var drop := POLE - 0.55
	P.box(rope, Vector3(0.025, drop, 0.025), P.CREAM, Vector3(0, -drop * 0.5, 0))
	P.box(rope, Vector3(0.16, 0.06, 0.06), P.WOOD_LIGHT, Vector3(0, -drop, 0))
	# The basket of fruit the relay carries.
	P.cyl(root, 0.24, 0.18, P.WOOD_LIGHT, Vector3(ENDS[0] - 0.45, 0.09, -0.35), 0.27)
	for index in range(4): P.sph(root, 0.08, P.LEAF if index % 2 == 0 else P.CORAL, Vector3(ENDS[0] - 0.55 + index * 0.07, 0.24, -0.39 + (index % 2) * 0.08))
	var flag := P.pivot(root, _flag_rest(state), "Flag")
	P.prism(flag, Vector3(HANG * 2.0, FLY, 0.02), P.PEACH, Vector3(FLY * 0.5, 0, FRONT), Vector3(0, 0, -PI / 2))
	for side: int in [-1, 1]: P.sph(flag, 0.032, P.WOOD_LIGHT, Vector3(0, side * HANG, 0.03))
	parts.rope = rope
	parts.flag = flag
	if state.get("together", false):
		var m := MINT_MAST
		P.cyl(root, 0.22, 0.1, P.STONE_LIGHT, m + Vector3(0, 0.05, 0), 0.2)
		P.cyl(root, 0.04, POLE * 0.85, P.MINT_DEEP, m + Vector3(0, POLE * 0.425, 0))
		P.sph(root, 0.06, P.MINT, m + Vector3(0, POLE * 0.85 + 0.04, 0))
		P.bar(root, Vector3(ENDS[1], line, 0), _mint_top(), 0.018, P.CREAM)
		P.prism(root, Vector3(0.24, 0.38, 0.02), P.MINT, m + Vector3(-0.2, POLE * 0.6, 0), Vector3(0, 0, PI / 2))
	if state.get("top", false):
		for index in range(2):
			var lamp := P.pivot(root, Vector3(ENDS[index], y0 + POLE + 0.2, 0), "Lamp")
			P.gold_ball(lamp, Vector3.ZERO, 0.1)
			P.ring(lamp, 0.15, 0.025, P.GOLD_DEEP, Vector3.ZERO, Vector3(PI / 2, 0, 0))
			parts["lamp_%d" % index] = lamp
	return parts

static func _flag_rest(state: Dictionary) -> Vector3:
	return Vector3(ENDS[0] + CORD_X, _y0(state) + 0.6, 0)

## The top line's height, and where the mint line meets the mint mast.
static func _line_y(state: Dictionary) -> float:
	return _y0(state) + POLE - 0.08

static func _mint_top() -> Vector3:
	return MINT_MAST + Vector3(0, POLE * 0.85 - 0.08, 0)

## Where the flag's pivot goes on its way out, from rest: up its cord to the
## top line, along it to the far mast, and with Together on down the mint
## line. Its top toggle stays on the cord or a line all the way.
static func route(state: Dictionary) -> Array[Vector3]:
	var rest := _flag_rest(state)
	var hang := Vector3(0, HANG, 0)
	var line := _line_y(state)
	var points: Array[Vector3] = [rest, Vector3(rest.x, line - HANG, 0)]
	if not state.get("together", false):
		# Its tip stops just short of the far mast.
		points.append(Vector3(ENDS[1] - FLY - 0.1, line - HANG, 0))
		return points
	var far := Vector3(ENDS[1], line, 0)
	points.append(far - hang)
	points.append(far.lerp(_mint_top(), HANDOFF) - hang)
	return points

## The flag's whole trip in a tap: {"legs": [[to, at, time], ...] from the
## tap's start, out along route() and back the same way to rest, "out": when
## it reaches the far end, "back": when it sets off home}. It comes back at
## its own pace when the tap has the time and faster when it is short, and is
## at rest as the last beat ends, so the settle has nothing left to move.
func trip(state: Dictionary) -> Dictionary:
	var points := route(state)
	var tap := 0.0
	for beat: Dictionary in beats(state): tap += float(beat.time)
	var legs: Array = []
	var length := 0.0
	var at := 0.1
	for index in range(1, points.size()):
		var time := points[index - 1].distance_to(points[index]) / SPEED
		legs.append([points[index], at, time])
		at += time + GAP
		length += points[index - 1].distance_to(points[index])
	var out := at - GAP
	var gaps := GAP * (points.size() - 2)
	var back := out + clampf(tap - out - gaps - length / SPEED, HOLD[0], HOLD[1])
	var pace := (tap - back - gaps) / length
	at = back
	for index in range(points.size() - 1, 0, -1):
		var time := points[index - 1].distance_to(points[index]) * pace
		legs.append([points[index - 1], at, time])
		at += time + GAP
	return {"legs": legs, "out": out, "back": back}

## The flag comes home through the upgrade beats, so the base beat takes what
## the tap has left after them, up to BASE_MAX.
func beats(state: Dictionary) -> Array:
	var result: Array = super(state)
	var upgrades := 0.0
	for beat: Dictionary in result.slice(1): upgrades += float(beat.time)
	result[0].time = minf(BASE_MAX, TAP_MAX - upgrades)
	return result

func upgrade_time(beat: String) -> float:
	return 0.8 if beat == "together" else 0.6

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var sounds: Dictionary = state.get("sounds", {})
	match beat:
		"base":
			# A tug on the rope runs the flag up its cord and along the line (on
			# down the mint line with Together); a second tug brings it home the
			# same way. The whole trip is here, so the together beat only gives
			# it the time, and its cue plays as the flag reaches the mint mast.
			var flag: Node3D = parts.flag
			var path := trip(state)
			for at: float in [0.0, float(path.back)]: _tug(anim, parts.rope, at)
			anim.sound(str(sounds.get("base", "")), 0.0)
			for leg: Array in path.legs: anim.move(flag, "position", leg[0], leg[1], leg[2])
			# Glints along the line behind it as it crosses.
			var across: Array = path.legs[1]
			var from: Vector3 = path.legs[0][0]
			for index in range(3):
				var share := 0.25 + index * 0.25
				var glint: Vector3 = from.lerp(across[0], share) + Vector3(0, HANG, 0)
				anim.halo(anim.fx, glint, 0.06, P.SNOW, float(across[1]) + float(across[2]) * share, 0.45, 0.6)
			if state.get("together", false): anim.sound(str(sounds.get("together", "")), path.out)
		"hard":
			for index in range(2):
				var flags: Node3D = parts["signals_%d" % index]
				anim.move(flags, "rotation:x", -1.1, index * 0.12, 0.15)
				anim.move(flags, "rotation:x", 0.0, 0.3 + index * 0.08, 0.2)
			anim.sound(str(sounds.get("hard", "")), 0.0)
		"top":
			for index in range(2):
				var lamp: Node3D = parts["lamp_%d" % index]
				brighten(anim, lamp, index * 0.25)
				anim.halo(lamp, Vector3.ZERO, 0.24, P.GOLD, index * 0.25, 0.35)
			anim.sound(str(sounds.get("top", "")), 0.0)

## A tug on the pull rope at `at`: down and back up.
static func _tug(anim: RefCounted, rope: Node3D, at: float) -> void:
	anim.move(rope, "rotation:x", 0.25, at, 0.18)
	anim.move(rope, "position:y", rope.position.y - 0.12, at, 0.18)
	anim.move(rope, "rotation:x", 0.0, at + 0.2, 0.25)
	anim.move(rope, "position:y", rope.position.y, at + 0.2, 0.25)

## Walking up to the rope at the first mast tugs it.
func trigger() -> Dictionary:
	return {"area": Rect2(-1.45, 0.34, 0.7, 0.5)}

func solids(state: Dictionary) -> Array[Rect2]:
	var half := 0.3 if state.get("hard", false) else 0.26
	var result: Array[Rect2] = []
	for x: float in ENDS: result.append(Rect2(x - half, -half, half * 2.0, half * 2.0))
	result.append(Rect2(ENDS[0] - 0.72, -0.62, 0.54, 0.54))
	if state.get("together", false): result.append(Rect2(MINT_MAST.x - 0.22, MINT_MAST.z - 0.22, 0.44, 0.44))
	return result

func footprint() -> Rect2:
	return Rect2(-2.05, -0.7, 4.35, 1.6)

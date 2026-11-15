extends "res://presentation/keepsakes/keepsake_builder.gd"
## The First Steps keepsake: the Bell Arch over the right end of the Home
## bridge. Walking through it (or a tap) strikes the big peach bell at its
## crown and the seed lift climbs the left post. Together: a mint twin bell
## answers, and a mint lift drops down the right post as yours climbs. Hard:
## both posts stand on slate plinths and a top tier of three small bells is
## struck in turn. Every bell is the kit bell (kit/pieces/bell.gd) with its
## hammer, sized to its own opening.
## Together Hard: gold vines up the posts and a gold sprout at the crown that
## sends out a ring of light.
## Its own frame: the posts stand on x, the walk goes through along z.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const Bell = preload("res://presentation/kit/pieces/bell.gd")
## The arch is drawn this much larger than its pieces.
const SIZE := 1.25
const HALF := 1.2
const RISE := 2.25
## How far the posts stand higher on Hard's plinths.
const HARD_LIFT := 0.34

## The arch's beam: its rise over the posts' tops and its half thickness.
const ARCH_RISE := 0.55
const ARCH_HALF := 0.08
## The big bell hangs from the arch's underside at the crown; the twin beside it.
const CROWN_UNDER := ARCH_RISE - ARCH_HALF
const TWIN_X := 0.6
## The small bells' row hangs this far over the posts' tops, from the top
## tier's underside, down to the arch's crown.
const ROW_UNDER := 0.93
## Bells struck one after another in a tap are this far apart (seconds).
const RING_GAP := 0.18

## The arch's underside over the posts' tops at `x`, less the cross beam's top
## (the cross beam's top is level with the posts' tops).
static func _arch_under(x: float) -> float:
	return ARCH_RISE * sin(acos(clampf(x / HALF, -1.0, 1.0))) - ARCH_HALF

static func _lift(state: Dictionary) -> float:
	return HARD_LIFT if state.get("hard", false) else 0.0

static func _top(state: Dictionary) -> float:
	return RISE + _lift(state)

func build(root: Node3D, state: Dictionary) -> Dictionary:
	var arch := P.grown(root, SIZE)
	var hard: bool = state.get("hard", false)
	var lift := _lift(state)
	var top := _top(state)
	for side: int in [-1, 1]:
		var x := side * HALF
		if hard: P.plinth(arch, 0.62, 0.62, Vector3(x, 0, 0))
		P.cyl(arch, 0.2, 0.18, P.STONE, Vector3(x, lift + 0.09, 0), 0.22)
		P.box(arch, Vector3(0.18, top - lift, 0.18), P.WOOD, Vector3(x, lift + (top - lift) * 0.5, 0))
		P.box(arch, Vector3(0.24, 0.12, 0.24), P.WOOD_LIGHT, Vector3(x, top, 0))
	# The arch itself: a curved beam from post to post.
	var curve: Array[Vector3] = []
	for index in range(9):
		var angle := PI * index / 8.0
		curve.append(Vector3(-cos(angle) * HALF, top + sin(angle) * ARCH_RISE, 0))
	for index in range(8): P.bar(arch, curve[index], curve[index + 1], ARCH_HALF * 2.0, P.WOOD_LIGHT)
	P.box(arch, Vector3(HALF * 2.0 + 0.3, 0.1, 0.22), P.WOOD, Vector3(0, top - 0.05, 0))
	# The big bell, hung from the arch's underside at its crown into the
	# opening above the cross beam.
	var bell := P.pivot(arch, Vector3(0, top + CROWN_UNDER, 0), "Bell")
	# The seed lift rides the left post on its rope.
	var ride := P.pivot(arch, Vector3(-HALF + 0.28, lift + 0.35, 0), "Lift")
	P.box(ride, Vector3(0.34, 0.04, 0.3), P.CREAM, Vector3.ZERO)
	for x: float in [-0.15, 0.15]: P.box(ride, Vector3(0.02, 0.26, 0.02), P.CREAM, Vector3(x, 0.13, 0.13))
	P.sph(ride, 0.09, Color("e8dfb8"), Vector3(0, 0.1, 0), Vector3(1, 1.15, 1))
	P.sph(ride, 0.04, P.LEAF, Vector3(0.02, 0.22, 0), Vector3(0.6, 1.3, 0.6))
	P.box(arch, Vector3(0.015, top - lift - 0.2, 0.015), P.CREAM, Vector3(-HALF + 0.28, lift + (top - lift) * 0.5 + 0.1, 0))
	var parts := {"lift": ride}
	Bell.hold(parts, "bell", Bell.build(bell, Vector3.ZERO, Vector2(1.0, CROWN_UNDER), "loop", P.PEACH, null, false, true))
	if state.get("together", false):
		# The twin, from the arch's underside beside the big bell.
		var twin := P.pivot(arch, Vector3(TWIN_X, top + _arch_under(TWIN_X), 0), "TwinBell")
		Bell.hold(parts, "twin", Bell.build(twin, Vector3.ZERO, Vector2(0.36, _arch_under(TWIN_X)), "loop", P.MINT, null, false, true))
		var mint := P.pivot(arch, Vector3(HALF - 0.28, top - 0.6, 0), "MintLift")
		P.box(mint, Vector3(0.34, 0.04, 0.3), P.MINT, Vector3.ZERO)
		P.sph(mint, 0.08, P.MINT, Vector3(0, 0.1, 0), Vector3(1, 1.15, 1))
		P.box(arch, Vector3(0.015, top - lift - 0.2, 0.015), P.MINT_DEEP, Vector3(HALF - 0.28, lift + (top - lift) * 0.5 + 0.1, 0))
		parts.mint_lift = mint
	if hard:
		# A top tier over the arch, three small bells in a row under it.
		P.box(arch, Vector3(1.5, 0.1, 0.18), P.WOOD_LIGHT, Vector3(0, top + 0.98, 0))
		for x: float in [-0.6, 0.6]: P.bar(arch, Vector3(x * 1.4, top + 0.25, 0), Vector3(x, top + 0.98, 0), 0.08, P.WOOD_LIGHT)
		var row := P.pivot(arch, Vector3(0, top + ROW_UNDER, 0), "SmallBells")
		for index in range(3):
			var small := P.pivot(row, Vector3(-0.45 + index * 0.45, 0, 0), "SmallBell")
			Bell.hold(parts, "small%d" % index, Bell.build(small, Vector3.ZERO, Vector2(0.36, ROW_UNDER - ARCH_RISE - ARCH_HALF), "loop", P.PEACH if index != 1 else P.CORAL, null, false, true))
	if state.get("top", false):
		var gold := P.pivot(arch, Vector3.ZERO, "Gold")
		for side: int in [-1, 1]: P.gold_vine(gold, Vector3(side * (HALF + 0.1), lift + 0.2, 0.1), Vector3(side * (HALF + 0.02), top + 0.05, 0.1), 5)
		var crown := top + (1.15 if hard else 0.62)
		P.cyl(gold, 0.02, 0.2, P.LEAF, Vector3(0, crown, 0))
		for side: int in [-1, 1]: P.node(gold, P.low_sphere(0.104, 0.117), P.gold(), Vector3(side * 0.12, crown + 0.14, 0), Vector3(0, 0, side * 0.5))
		parts.gold = gold
	return parts

func base_time() -> float:
	return 2.0

func upgrade_time(_beat: String) -> float:
	return 0.7

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var sounds: Dictionary = state.get("sounds", {})
	var ride: Node3D = parts.lift
	var low := _lift(state) + 0.35
	var high := _top(state) - 0.6
	match beat:
		"base":
			# The bell swings as the pip passes under; the seed lift climbs and comes down.
			_ring(anim, [parts.bell], 0.05, str(sounds.get("base", "")))
			anim.burst(anim.fx, Vector3(0, (_top(state) + 0.05) * SIZE, 0.3), 7, 0.55 * SIZE, 0.15, 0.7)
			anim.move(ride, "position:y", high, 0.0, 0.9)
			anim.move(ride, "position:y", low, 1.15, 0.8)
		"together":
			var mint: Node3D = parts.mint_lift
			_ring(anim, [parts.twin], 0.0, str(sounds.get("base", "")), 1)
			anim.move(ride, "position:y", high, 0.0, 0.32)
			anim.move(mint, "position:y", low, 0.0, 0.32)
			anim.move(ride, "position:y", low, 0.36, 0.3)
			anim.move(mint, "position:y", high, 0.36, 0.3)
			anim.sound(str(sounds.get("together", "")), 0.0)
		"hard":
			# Each small bell is struck in turn and chimes as it is hit.
			var bells: Array = []
			for index in range(3): bells.append(parts["small%d" % index])
			_ring(anim, bells, 0.0, str(sounds.get("hard", "")))
		"top":
			var gold: Node3D = parts.gold
			brighten(anim, gold, 0.0)
			var crown := Vector3(0, (_top(state) + 0.1) * SIZE, 0)
			var light: MeshInstance3D = anim.spawn(anim.fx, P.torus(0.7, 0.04), P.glow(P.GOLD, 1.6), crown, Vector3(PI / 2, 0, 0), Vector3.ONE * 0.5)
			anim.set_at(light, "visible", true, 0.0)
			anim.move(light, "scale", Vector3.ONE * 1.6, 0.0, 0.6, Tween.TRANS_QUAD, Tween.EASE_OUT)
			anim.set_at(light, "visible", false, 0.62)
			anim.sound(str(sounds.get("top", "")), 0.0)

## The one ring rule for this keepsake's bells: each bell given (only the
## ones it has) is struck in turn RING_GAP apart from `at`, swings
## (kit/pieces/bell.gd ring), and plays `cue` at its strike, the n-th bell at
## pitch variant `first` + n, so the same bells always sound the same.
func _ring(anim: RefCounted, bells: Array, at: float, cue: String, first: int = 0) -> void:
	for index in range(bells.size()):
		anim.sound(cue, Bell.ring(anim, bells[index], at + index * RING_GAP), first + index)

## Walking through between the posts sets it off.
func trigger() -> Dictionary:
	return {"line": [Vector2(-(HALF - 0.1) * SIZE, 0), Vector2((HALF - 0.1) * SIZE, 0)]}

## Each post's round stone foot, or Hard's square plinth under it.
func solids(state: Dictionary) -> Array[Rect2]:
	var hard: bool = state.get("hard", false)
	var half := 0.31 * SIZE
	var result: Array[Rect2] = []
	for side: int in [-1, 1]:
		var x := side * HALF * SIZE
		if hard: result.append(Rect2(x - half, -half, half * 2.0, half * 2.0))
		else: result.append_array(round_solid(Vector2(x, 0), 0.22 * SIZE))
	return result

func footprint() -> Rect2:
	var reach := (HALF + 0.31) * SIZE
	return Rect2(-reach, -0.4, reach * 2.0, 0.8)

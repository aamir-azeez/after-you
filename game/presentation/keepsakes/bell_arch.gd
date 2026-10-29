extends "res://presentation/keepsakes/keepsake_builder.gd"
## The First Steps keepsake: the Bell Arch over the right end of the Home
## bridge. Walking through it (or a tap) swings the big peach bell at its crown
## and the seed lift climbs the left post. Together: a mint twin bell answers,
## and a mint lift drops down the right post as yours climbs. Hard: both posts
## stand on slate plinths and a top tier of three small bells chimes in turn.
## Together Hard: gold vines up the posts and a gold sprout at the crown that
## sends out a ring of light.
## Its own frame: the posts stand on x, the walk goes through along z.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
## The arch is drawn this much larger than its pieces.
const SIZE := 1.25
const HALF := 1.2
const RISE := 2.25
## How far the posts stand higher on Hard's plinths.
const HARD_LIFT := 0.34

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
		curve.append(Vector3(-cos(angle) * HALF, top + sin(angle) * 0.55, 0))
	for index in range(8): P.bar(arch, curve[index], curve[index + 1], 0.16, P.WOOD_LIGHT)
	P.box(arch, Vector3(HALF * 2.0 + 0.3, 0.1, 0.22), P.WOOD, Vector3(0, top - 0.05, 0))
	# The big bell, hung from the crown.
	var bell := P.pivot(arch, Vector3(0, top + 0.5, 0), "Bell")
	P.cyl(bell, 0.02, 0.24, P.CREAM, Vector3(0, -0.12, 0))
	P.sph(bell, 0.3, P.PEACH, Vector3(0, -0.45, 0), Vector3(1, 1.15, 1))
	P.ring(bell, 0.3, 0.07, P.CREAM, Vector3(0, -0.66, 0))
	P.sph(bell, 0.07, P.WOOD, Vector3(0, -0.78, 0))
	# The seed lift rides the left post on its rope.
	var ride := P.pivot(arch, Vector3(-HALF + 0.28, lift + 0.35, 0), "Lift")
	P.box(ride, Vector3(0.34, 0.04, 0.3), P.CREAM, Vector3.ZERO)
	for x: float in [-0.15, 0.15]: P.box(ride, Vector3(0.02, 0.26, 0.02), P.CREAM, Vector3(x, 0.13, 0.13))
	P.sph(ride, 0.09, Color("e8dfb8"), Vector3(0, 0.1, 0), Vector3(1, 1.15, 1))
	P.sph(ride, 0.04, P.LEAF, Vector3(0.02, 0.22, 0), Vector3(0.6, 1.3, 0.6))
	P.box(arch, Vector3(0.015, top - lift - 0.2, 0.015), P.CREAM, Vector3(-HALF + 0.28, lift + (top - lift) * 0.5 + 0.1, 0))
	var parts := {"bell": bell, "lift": ride}
	if state.get("together", false):
		var twin := P.pivot(arch, Vector3(0.62, top + 0.2, 0), "TwinBell")
		P.cyl(twin, 0.015, 0.16, P.CREAM, Vector3(0, -0.08, 0))
		P.sph(twin, 0.19, P.MINT, Vector3(0, -0.3, 0), Vector3(1, 1.15, 1))
		P.ring(twin, 0.19, 0.05, P.MINT_DEEP, Vector3(0, -0.44, 0))
		var mint := P.pivot(arch, Vector3(HALF - 0.28, top - 0.6, 0), "MintLift")
		P.box(mint, Vector3(0.34, 0.04, 0.3), P.MINT, Vector3.ZERO)
		P.sph(mint, 0.08, P.MINT, Vector3(0, 0.1, 0), Vector3(1, 1.15, 1))
		P.box(arch, Vector3(0.015, top - lift - 0.2, 0.015), P.MINT_DEEP, Vector3(HALF - 0.28, lift + (top - lift) * 0.5 + 0.1, 0))
		parts.twin = twin
		parts.mint_lift = mint
	if hard:
		# A top tier over the arch with three small bells, as one row.
		P.box(arch, Vector3(1.5, 0.1, 0.18), P.WOOD_LIGHT, Vector3(0, top + 0.98, 0))
		for x: float in [-0.6, 0.6]: P.bar(arch, Vector3(x * 1.4, top + 0.25, 0), Vector3(x, top + 0.98, 0), 0.08, P.WOOD_LIGHT)
		var row := P.pivot(arch, Vector3(0, top + 0.93, 0), "SmallBells")
		for index in range(3):
			var small := P.pivot(row, Vector3(-0.45 + index * 0.45, 0, 0), "SmallBell")
			P.sph(small, 0.11, P.PEACH if index != 1 else P.CORAL, Vector3(0, -0.14, 0), Vector3(1, 1.2, 1))
			P.ring(small, 0.11, 0.035, P.CREAM, Vector3(0, -0.22, 0))
		parts.small_bells = row
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
			_swing(anim, parts.bell, "rotation:x", 0.45, 0.05)
			anim.sound(str(sounds.get("base", "")), 0.05)
			anim.burst(anim.fx, Vector3(0, (_top(state) + 0.05) * SIZE, 0.3), 7, 0.55 * SIZE, 0.15, 0.7)
			anim.move(ride, "position:y", high, 0.0, 0.9)
			anim.move(ride, "position:y", low, 1.15, 0.8)
		"together":
			var mint: Node3D = parts.mint_lift
			_swing(anim, parts.twin, "rotation:x", -0.5, 0.0)
			anim.move(ride, "position:y", high, 0.0, 0.32)
			anim.move(mint, "position:y", low, 0.0, 0.32)
			anim.move(ride, "position:y", low, 0.36, 0.3)
			anim.move(mint, "position:y", high, 0.36, 0.3)
			anim.sound(str(sounds.get("together", "")), 0.0)
		"hard":
			# The row of small bells rocks, and each one chimes in turn.
			var row: Node3D = parts.small_bells
			_swing(anim, row, "rotation:x", 0.3, 0.0)
			for index in range(3):
				var bell := Vector3(-0.45 + index * 0.45, _top(state) + 0.79, 0.0) * SIZE
				anim.halo(anim.fx, bell, 0.16, P.SNOW, index * 0.18, 0.2, 0.45)
			anim.sound(str(sounds.get("hard", "")), 0.0)
		"top":
			var gold: Node3D = parts.gold
			brighten(anim, gold, 0.0)
			var crown := Vector3(0, (_top(state) + 0.1) * SIZE, 0)
			var light: MeshInstance3D = anim.spawn(anim.fx, P.torus(0.7, 0.04), P.glow(P.GOLD, 1.6), crown, Vector3(PI / 2, 0, 0), Vector3.ONE * 0.5)
			anim.set_at(light, "visible", true, 0.0)
			anim.move(light, "scale", Vector3.ONE * 1.6, 0.0, 0.6, Tween.TRANS_QUAD, Tween.EASE_OUT)
			anim.set_at(light, "visible", false, 0.62)
			anim.sound(str(sounds.get("top", "")), 0.0)

## A bell's swing: out, back past rest, and still again, over 0.66 seconds
## times `pace`.
func _swing(anim: RefCounted, bell: Node3D, property: String, amount: float, at: float, pace: float = 1.0) -> void:
	anim.move(bell, property, amount, at, 0.12 * pace)
	anim.move(bell, property, -amount * 0.75, at + 0.12 * pace, 0.18 * pace)
	anim.move(bell, property, amount * 0.35, at + 0.3 * pace, 0.16 * pace)
	anim.move(bell, property, 0.0, at + 0.46 * pace, 0.2 * pace)

## Walking through between the posts sets it off.
func trigger() -> Dictionary:
	return {"line": [Vector2(-(HALF - 0.1) * SIZE, 0), Vector2((HALF - 0.1) * SIZE, 0)]}

func solids(state: Dictionary) -> Array[Rect2]:
	var half := (0.31 if state.get("hard", false) else 0.22) * SIZE
	var result: Array[Rect2] = []
	for side: int in [-1, 1]: result.append(Rect2(side * HALF * SIZE - half, -half, half * 2.0, half * 2.0))
	return result

func footprint() -> Rect2:
	var reach := (HALF + 0.31) * SIZE
	return Rect2(-reach, -0.4, reach * 2.0, 0.8)

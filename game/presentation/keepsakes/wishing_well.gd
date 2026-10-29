extends "res://presentation/keepsakes/keepsake_builder.gd"
## The Wishing Well keepsake: a big stone well under a peach roof, with a
## winch and a bucket. Standing at the rim and tapping (or a tap from the menu)
## flips a coin from the pip into the water; the winch turns and ripples run
## out to the rim. Together: a mint bucket of coins beside the well catches one
## the well sends back. Hard: the well stands on a slate plinth with a coil of
## rope, and the coin skips three times. Together Hard: a gold star on the roof
## and a gold fountain rises from the water.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const HARD_LIFT := 0.32
const MINT_BUCKET := Vector3(-1.25, 0, 0.45)
## Where a coin starts without a pip: over the rim's front.
const RIM := Vector3(0.35, 0.95, 0.98)

static func _y0(state: Dictionary) -> float:
	return HARD_LIFT if state.get("hard", false) else 0.0

func build(root: Node3D, state: Dictionary) -> Dictionary:
	var hard: bool = state.get("hard", false)
	var y0 := _y0(state)
	if hard: P.plinth(root, 1.75, 1.75)
	P.cyl(root, 0.72, 0.62, P.STONE, Vector3(0, y0 + 0.31, 0), 0.74)
	P.ring(root, 0.73, 0.1, P.CREAM, Vector3(0, y0 + 0.62, 0))
	P.cyl(root, 0.64, 0.02, P.WATER, Vector3(0, y0 + 0.62, 0))
	for x: float in [-0.66, 0.66]: P.box(root, Vector3(0.12, 1.35, 0.12), P.WOOD, Vector3(x, y0 + 1.3, 0))
	P.prism(root, Vector3(1.9, 0.6, 1.1), P.ROOF, Vector3(0, y0 + 2.25, 0))
	P.box(root, Vector3(1.5, 0.09, 0.09), P.WOOD_LIGHT, Vector3(0, y0 + 1.8, 0))
	var crank := P.pivot(root, Vector3(0.8, y0 + 1.8, 0), "Crank")
	P.box(crank, Vector3(0.06, 0.28, 0.06), P.WOOD_LIGHT, Vector3(0, -0.1, 0.06))
	# The bucket hangs on its rope from the winch beam; the rope travels with it.
	var bucket := P.pivot(root, Vector3(0, y0 + 1.05, 0), "Bucket")
	P.cyl(bucket, 0.16, 0.22, P.WOOD, Vector3.ZERO, 0.18)
	P.box(bucket, Vector3(0.025, 0.75, 0.025), P.CREAM, Vector3(0, 0.375 + 0.11, 0))
	var parts := {"crank": crank, "bucket": bucket}
	if state.get("together", false):
		var at := MINT_BUCKET
		P.cyl(root, 0.24, 0.32, P.MINT, at + Vector3(0, 0.16, 0), 0.28)
		P.ring(root, 0.27, 0.05, P.MINT_DEEP, at + Vector3(0, 0.32, 0))
		P.box(root, Vector3(0.44, 0.04, 0.04), P.MINT_DEEP, at + Vector3(0, 0.5, 0))
		for x: float in [-0.24, 0.24]: P.box(root, Vector3(0.035, 0.18, 0.035), P.MINT_DEEP, at + Vector3(x, 0.41, 0))
		for index in range(3): P.node(root, P.Primitives.shared_mesh("cylinder", 0.1, 0.02, 0.1), P.gold(), at + Vector3(-0.05 + index * 0.05, 0.33 + index * 0.022, 0))
	if hard:
		for index in range(3): P.ring(root, 0.2 - index * 0.025, 0.06, P.WOOD_LIGHT, Vector3(-0.68, 0.36 + index * 0.05, 0.62))
	if state.get("top", false):
		P.cyl(root, 0.025, 0.25, P.WOOD, Vector3(0, y0 + 2.62, 0))
		var star := P.pivot(root, Vector3(0, y0 + 2.82, 0), "Star")
		P.gold_ball(star, Vector3.ZERO, 0.12)
		for turn: float in [PI / 4, -PI / 4]: P.node(star, P.Primitives.shared_mesh("box", 0.42, 0.035, 0.035), P.gold(), Vector3.ZERO, Vector3(0, 0, turn))
		parts.star = star
	return parts

func base_time() -> float:
	return 2.1

func upgrade_time(beat: String) -> float:
	return 0.7 if beat in ["together", "top"] else 0.5

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var sounds: Dictionary = state.get("sounds", {})
	var y0 := _y0(state)
	var water := Vector3(0, y0 + 0.64, 0)
	match beat:
		"base":
			# The winch turns and lifts the bucket; a coin flips from the pip into the water.
			var crank: Node3D = parts.crank
			var bucket: Node3D = parts.bucket
			anim.move(crank, "rotation:x", TAU * 2.0, 0.0, 1.3, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
			anim.move(bucket, "position:y", y0 + 1.45, 0.0, 0.8)
			var from: Vector3 = (anim.rider_from + Vector3(0, 1.05, 0)) if anim.rider != null else RIM + Vector3(0, y0, 0)
			var coin := _coin(anim, from)
			anim.set_at(coin, "visible", true, 0.3)
			anim.path(coin, anim.arc(from, water + Vector3(0.1, 0, 0.1), 0.7), 0.3, 0.6, 0.5)
			anim.move(coin, "rotation:x", TAU * 3.0, 0.3, 0.6, Tween.TRANS_LINEAR)
			anim.set_at(coin, "visible", false, 0.92)
			anim.sound(str(sounds.get("base", "")), 0.9)
			for index in range(3):
				var ripple: MeshInstance3D = anim.spawn(anim.fx, P.torus(0.2, 0.03), P.mat(P.CREAM), water + Vector3(0, 0.01, 0), Vector3.ZERO, Vector3.ONE * 0.5)
				anim.set_at(ripple, "visible", true, 0.95 + index * 0.2)
				anim.move(ripple, "scale", Vector3.ONE * (2.4 + index * 0.4), 0.95 + index * 0.2, 0.7, Tween.TRANS_QUAD, Tween.EASE_OUT)
				anim.set_at(ripple, "visible", false, 1.65 + index * 0.2)
			anim.move(bucket, "position:y", y0 + 1.05, 1.4, 0.7)
		"together":
			# The well sends a coin back, into the mint bucket.
			var coin := _coin(anim, water)
			anim.set_at(coin, "visible", true, 0.0)
			anim.path(coin, anim.arc(water, MINT_BUCKET + Vector3(0, 0.36, 0), 0.9), 0.0, 0.6, 0.5)
			anim.move(coin, "rotation:z", TAU * 2.0, 0.0, 0.6, Tween.TRANS_LINEAR)
			anim.set_at(coin, "visible", false, 0.62)
			anim.halo(anim.fx, MINT_BUCKET + Vector3(0, 0.4, 0), 0.22, P.MINT, 0.55, 0.2)
			anim.sound(str(sounds.get("together", "")), 0.55)
		"hard":
			# The coin skips three times across the water.
			for index in range(3):
				var skip: MeshInstance3D = anim.spawn(anim.fx, P.torus(0.07 + index * 0.02, 0.025), P.mat(P.CREAM), water + Vector3(-0.35 + index * 0.22, 0.01, 0.12 - index * 0.04))
				anim.set_at(skip, "visible", true, index * 0.13)
				anim.move(skip, "scale", Vector3.ONE * 1.8, index * 0.13, 0.22, Tween.TRANS_QUAD, Tween.EASE_OUT)
				anim.set_at(skip, "visible", false, index * 0.13 + 0.22)
			anim.sound(str(sounds.get("hard", "")), 0.0)
		"top":
			# The star lights and a gold fountain rises from the water.
			brighten(anim, parts.star, 0.0)
			anim.halo(parts.star, Vector3.ZERO, 0.3, P.GOLD, 0.0, 0.65)
			for index in range(6):
				var angle := index * TAU / 6.0
				var drop: MeshInstance3D = anim.spawn(anim.fx, P.low_sphere(0.045), P.glow(P.GOLD, 1.6), water)
				anim.set_at(drop, "visible", true, index * 0.04)
				anim.path(drop, anim.arc(water, water + Vector3(cos(angle) * 0.45, 0, sin(angle) * 0.35), 0.8), index * 0.04, 0.5, 0.5)
				anim.set_at(drop, "visible", false, index * 0.04 + 0.55)
			anim.sound(str(sounds.get("top", "")), 0.0)

func _coin(anim: RefCounted, at: Vector3) -> MeshInstance3D:
	return anim.spawn(anim.fx, P.Primitives.shared_mesh("cylinder", 0.08, 0.02, 0.08), P.gold(true), at, Vector3(0.9, 0, 0.4))

## No walk trigger: the pip stands at the rim and taps the action.
func trigger() -> Dictionary:
	return {}

func solids(state: Dictionary) -> Array[Rect2]:
	var half := 0.88 if state.get("hard", false) else 0.78
	var result: Array[Rect2] = [Rect2(-half, -half, half * 2.0, half * 2.0)]
	if state.get("together", false): result.append(Rect2(MINT_BUCKET.x - 0.28, MINT_BUCKET.z - 0.28, 0.56, 0.56))
	return result

func footprint() -> Rect2:
	return Rect2(-1.55, -0.9, 2.45, 1.8)

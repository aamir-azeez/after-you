extends "res://presentation/keepsakes/keepsake_builder.gd"
## The Wishing Well keepsake. Tap: a coin flips into the well with a ripple.
## Together: a mint bucket beside it; the well's bucket brings the coin up and
## it hops across into the mint one. Hard: a coil of rope on the footing; the
## coin skips three times before it sinks. Together Hard: a gold star on the
## roof that spins once and lights, and the ripple turns gold.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const WATER_Y := 0.346
const TOP_Y := 1.41

func build(root: Node3D, state: Dictionary) -> Dictionary:
	if state.get("hard", false): P.footing(root, 0.9, 0.74)
	var body := P.body(root, state)
	P.cyl(body, 0.34, 0.34, P.STONE, Vector3(0, 0.17, 0), 0.35)
	P.ring(body, 0.345, 0.05, P.CREAM, Vector3(0, 0.34, 0))
	P.cyl(body, 0.3, 0.012, P.WATER, Vector3(0, WATER_Y, 0))
	for x: float in [-0.31, 0.31]: P.box(body, Vector3(0.06, 0.66, 0.06), P.WOOD, Vector3(x, 0.66, 0))
	P.prism(body, Vector3(0.9, 0.28, 0.52), P.ROOF, Vector3(0, 1.12, 0))
	P.box(body, Vector3(0.72, 0.045, 0.045), P.WOOD_LIGHT, Vector3(0, 0.9, 0))
	P.box(body, Vector3(0.04, 0.12, 0.04), P.WOOD_LIGHT, Vector3(0.39, 0.85, 0.04))
	P.box(body, Vector3(0.015, 0.2, 0.015), P.CREAM, Vector3(0, 0.79, 0))
	var bucket := P.pivot(body, Vector3(0, 0.62, 0), "Bucket")
	P.cyl(bucket, 0.075, 0.11, P.WOOD, Vector3.ZERO, 0.085)
	var parts := {"bucket": bucket}
	if state.get("together", false):
		var at := P.BESIDE
		P.cyl(root, 0.13, 0.17, P.MINT, at + Vector3(0, 0.085, 0), 0.15)
		P.ring(root, 0.15, 0.03, P.MINT_DEEP, at + Vector3(0, 0.17, 0))
		P.box(root, Vector3(0.24, 0.025, 0.025), P.MINT_DEEP, at + Vector3(0, 0.26, 0))
		for x: float in [-0.13, 0.13]: P.box(root, Vector3(0.02, 0.1, 0.02), P.MINT_DEEP, at + Vector3(x, 0.21, 0))
		P.node(root, _coin(), P.gold(), at + Vector3(0, 0.176, 0))
	if state.get("hard", false):
		for i in range(3): P.ring(root, 0.1 - i * 0.012, 0.035, P.WOOD_LIGHT, Vector3(-0.34, P.FOOT_HEIGHT + 0.02 + i * 0.03, 0.27))
	if state.get("top", false):
		P.cyl(body, 0.012, 0.12, P.WOOD, Vector3(0, 1.31, 0))
		var star := P.pivot(body, Vector3(0, TOP_Y, 0), "Star")
		star.scale = Vector3.ONE * P.TOP_SCALE
		P.node(star, P.low_sphere(0.06), P.gold(), Vector3.ZERO)
		for turn: float in [PI / 4, -PI / 4]: P.node(star, P.Primitives.shared_mesh("box", 0.2, 0.018, 0.018), P.gold(), Vector3.ZERO, Vector3(0, 0, turn))
		parts.star = star
	return parts

func base_time() -> float:
	return 2.1

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var fx: Node3D = anim.fx
	var up := Vector3(0, lift(state), 0)
	var sounds: Dictionary = state.get("sounds", {})
	match beat:
		"base":
			var coin: MeshInstance3D = anim.spawn(fx, _coin(), P.glow(P.GOLD_DEEP, 0.8), Vector3(0.78, 0.18, 0.32))
			anim.set_at(coin, "visible", true, 0.0)
			anim.path(coin, anim.arc(Vector3(0.78, 0.18, 0.32), up + Vector3(0, WATER_Y + 0.02, 0), 0.9 + up.y), 0.0, 1.3)
			anim.move(coin, "rotation:x", 9.0, 0.0, 1.3, Tween.TRANS_LINEAR)
			anim.set_at(coin, "visible", false, 1.35)
			_ripple(anim, fx, up, P.mat(P.CREAM), 1.3)
			anim.sound(str(sounds.get("base", "")), 1.3)
		"together":
			var bucket: Node3D = parts.bucket
			anim.move(bucket, "position:y", 0.8, 0.0, 0.25)
			var coin: MeshInstance3D = anim.spawn(fx, _coin(), P.glow(P.GOLD_DEEP, 0.9), up + Vector3(0, 0.86, 0.05))
			anim.set_at(coin, "visible", true, 0.25)
			anim.path(coin, anim.arc(up + Vector3(0, 0.86, 0.05), P.BESIDE + Vector3(0, 0.3, 0), 0.35), 0.25, 0.4)
			anim.set_at(coin, "visible", false, 0.66)
			anim.move(bucket, "position:y", 0.62, 0.4, 0.25)
			anim.sound(str(sounds.get("together", "")), 0.6)
		"hard":
			var stops := [Vector3(-0.22, WATER_Y + 0.01, 0.06) + up, Vector3(-0.08, WATER_Y + 0.01, 0.03) + up, Vector3(0.05, WATER_Y + 0.01, 0.0) + up, Vector3(0.14, WATER_Y - 0.01, -0.02) + up]
			var coin: MeshInstance3D = anim.spawn(fx, _coin(), P.glow(P.GOLD_DEEP, 0.8), stops[0])
			anim.set_at(coin, "visible", true, 0.0)
			for i in range(3):
				anim.path(coin, anim.arc(stops[i], stops[i + 1], 0.06 - i * 0.015), i * 0.18, 0.18)
				_ripple(anim, fx, up, P.mat(P.CREAM), i * 0.18 + 0.17, 0.4)
			anim.set_at(coin, "visible", false, 0.62)
			anim.sound(str(sounds.get("hard", "")), 0.0)
		"top":
			var star: Node3D = parts.star
			anim.move(star, "rotation:y", TAU, 0.0, 0.6)
			brighten(anim, star, 0.0)
			_ripple(anim, fx, up, P.gold(true), 0.1)
			anim.sound(str(sounds.get("top", "")), 0.0)

## A ring that spreads on the water and goes.
func _ripple(anim: RefCounted, fx: Node3D, up: Vector3, look: Material, at: float, size: float = 1.0) -> void:
	var ring: MeshInstance3D = anim.spawn(fx, P.torus(0.12, 0.02), look, up + Vector3(0, WATER_Y + 0.008, 0), Vector3.ZERO, Vector3(0.4, 1, 0.4) * size)
	anim.set_at(ring, "visible", true, at)
	anim.move(ring, "scale", Vector3(1.9, 1, 1.9) * size, at, 0.6, Tween.TRANS_QUAD, Tween.EASE_OUT)
	anim.set_at(ring, "visible", false, at + 0.62)

func _coin() -> Mesh:
	return P.Primitives.shared_mesh("cylinder", 0.085, 0.018, 0.085)

func footprint() -> Rect2:
	return Rect2(-0.46, -0.4, 1.36, 0.8)

extends "res://presentation/keepsakes/keepsake_builder.gd"
## The Relay Isles keepsake. Tap: the flag runs up the pole, waves and comes
## down. Together: a mint pole with a line between the tops; the flag is handed
## across to it. Hard: a crossbar with two signal flags that flick out at the
## top. Together Hard: a gold ball on the pole that spins once and lights.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const X0 := -0.14
const FLAG_LOW := 0.34
const FLAG_HIGH := 1.06

func build(root: Node3D, state: Dictionary) -> Dictionary:
	if state.get("hard", false): P.footing(root, 0.9, 0.7)
	var body := P.body(root, state)
	P.cyl(body, 0.2, 0.08, P.STONE_LIGHT, Vector3(X0, 0.04, 0), 0.18)
	P.cyl(body, 0.03, 1.16, P.WOOD, Vector3(X0, 0.62, 0))
	P.box(body, Vector3(0.008, 1.1, 0.008), P.CREAM, Vector3(X0 + 0.04, 0.6, 0))
	P.cyl(body, 0.15, 0.12, P.WOOD_LIGHT, Vector3(0.24, 0.06, 0.14), 0.17)
	for i in range(3): P.sph(body, 0.05, P.LEAF, Vector3(0.18 + i * 0.06, 0.15, 0.12 + (i % 2) * 0.05), Vector3(1, 1.3, 1))
	P.sph(body, 0.045, P.CORAL, Vector3(0.3, 0.2, 0.17))
	var flag := P.pivot(body, Vector3(X0 + 0.03, FLAG_LOW, 0), "Flag")
	P.prism(flag, Vector3(0.24, 0.36, 0.02), P.PEACH, Vector3(0.18, 0, 0), Vector3(0, 0, -PI / 2))
	var parts := {"flag": flag}
	if state.get("top", false):
		var ball := P.pivot(body, Vector3(X0, 1.26, 0), "GoldBall")
		ball.scale = Vector3.ONE * P.TOP_SCALE
		P.node(ball, P.low_sphere(0.07), P.gold(), Vector3.ZERO)
		P.node(ball, P.torus(0.1, 0.02), P.gold(), Vector3.ZERO, Vector3(PI / 2, 0, 0))
		parts.ball = ball
	else:
		P.sph(body, 0.045, P.CREAM, Vector3(X0, 1.22, 0))
	if state.get("together", false):
		var up := lift(state)
		var px := 0.8
		P.cyl(root, 0.15, 0.06, P.STONE_LIGHT, Vector3(px, 0.03, -0.04))
		P.cyl(root, 0.025, 0.86, P.MINT_DEEP, Vector3(px, 0.45, -0.04))
		P.sph(root, 0.04, P.MINT, Vector3(px, 0.9, -0.04))
		P.bar(root, Vector3(X0, up + 1.14, 0), Vector3(px, 0.86, -0.04), 0.012, P.CREAM)
		P.prism(root, Vector3(0.14, 0.22, 0.02), P.MINT, Vector3(px - 0.12, 0.66, -0.04), Vector3(0, 0, PI / 2))
		parts.line = [Vector3(X0 + 0.15, up + 1.0, 0), Vector3(px - 0.15, 0.72, -0.04)]
	if state.get("hard", false):
		P.box(body, Vector3(0.52, 0.035, 0.035), P.WOOD, Vector3(X0, 0.96, 0))
		var signals := P.pivot(body, Vector3(X0, 0.94, 0), "Signals")
		signals.scale = Vector3(1, 0.3, 1)
		for side: int in [-1, 1]: P.box(signals, Vector3(0.09, 0.12, 0.012), P.CORAL if side < 0 else P.CREAM, Vector3(side * 0.24, -0.07, 0))
		parts.signals = signals
	return parts

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var flag: Node3D = parts.flag
	var sounds: Dictionary = state.get("sounds", {})
	match beat:
		"base":
			anim.move(flag, "position:y", FLAG_HIGH, 0.0, 0.9, Tween.TRANS_QUAD, Tween.EASE_OUT)
			anim.move(flag, "rotation:y", 0.3, 0.9, 0.18)
			anim.move(flag, "rotation:y", -0.3, 1.08, 0.18)
			anim.move(flag, "rotation:y", 0.0, 1.26, 0.14)
			anim.move(flag, "position:y", FLAG_LOW, 1.45, 0.7)
			anim.sound(str(sounds.get("base", "")), 0.0)
		"together":
			var line: Array = parts.line
			var handed: MeshInstance3D = anim.spawn(anim.fx, P.Primitives.shared_mesh("prism", 0.24, 0.36, 0.02), P.mat(P.PEACH), line[0], Vector3(0, 0, -PI / 2), Vector3.ONE * 0.8)
			anim.set_at(handed, "visible", true, 0.0)
			anim.path(handed, anim.arc(line[0], line[1], -0.05), 0.0, 0.6)
			anim.set_at(handed, "visible", false, 0.65)
			anim.sound(str(sounds.get("together", "")), 0.55)
		"hard":
			var signals: Node3D = parts.signals
			anim.move(flag, "position:y", FLAG_HIGH, 0.0, 0.3)
			anim.move(signals, "scale", Vector3.ONE, 0.25, 0.12, Tween.TRANS_BACK, Tween.EASE_OUT)
			anim.move(signals, "scale", Vector3(1, 0.3, 1), 0.55, 0.12)
			anim.move(flag, "position:y", FLAG_LOW, 0.4, 0.3)
			anim.sound(str(sounds.get("hard", "")), 0.25)
		"top":
			var ball: Node3D = parts.ball
			anim.move(ball, "rotation:y", TAU, 0.0, 0.6)
			brighten(anim, ball, 0.0)
			anim.sound(str(sounds.get("top", "")), 0.0)

func footing_size() -> Vector2:
	return Vector2(0.9, 0.7)

func footprint() -> Rect2:
	return Rect2(-0.45, -0.35, 1.42, 0.7)

extends "res://presentation/keepsakes/keepsake_builder.gd"
## The Rolling Home keepsake. Tap: the ball rocks back and forth in its cradle
## and settles. Together: a mint cup holding a mint ball; yours rolls home into
## it. Hard: a loop on the rail, and the ball goes all the way round. Together
## Hard: a gold bell hung high over the rail that swings and rings as the ball
## passes under.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const CRADLE := Vector3(0, 0.56, 0)
const RADIUS := 0.44
const LOOP := Vector3(0, 0.62, -0.15)

func build(root: Node3D, state: Dictionary) -> Dictionary:
	if state.get("hard", false): P.footing(root, 1.0, 0.6)
	var body := P.body(root, state)
	P.box(body, Vector3(0.9, 0.08, 0.34), P.CREAM, Vector3(0, 0.04, 0))
	for i in range(11):
		var a := deg_to_rad(-75.0 + i * 15.0)
		P.box(body, Vector3(0.12, 0.04, 0.22), P.WOOD if i % 2 == 0 else P.WOOD_LIGHT, CRADLE + Vector3(sin(a) * RADIUS, -cos(a) * RADIUS, 0), Vector3(0, 0, a))
	for x: float in [-0.4, 0.4]: P.box(body, Vector3(0.05, 0.3, 0.05), P.WOOD, Vector3(x, 0.2, -0.13))
	var ball := P.sph(body, 0.11, P.PEACH, _on_rail(0.0))
	ball.name = "Ball"
	var parts := {"ball": ball}
	if state.get("hard", false):
		P.ring(body, 0.24, 0.035, P.WOOD_LIGHT, LOOP, Vector3(PI / 2, 0, 0))
		P.box(body, Vector3(0.04, 0.4, 0.04), P.WOOD, Vector3(0, 0.2, -0.15))
	if state.get("together", false):
		var up := lift(state)
		var at := P.BESIDE + Vector3(0.04, 0, -0.08)
		P.cyl(root, 0.15, 0.12, P.MINT_DEEP, at + Vector3(0, 0.06, 0), 0.17)
		P.ring(root, 0.165, 0.03, P.MINT, at + Vector3(0, 0.12, 0))
		var mint := P.sph(root, 0.09, P.MINT, at + Vector3(0, 0.18, -0.02))
		mint.name = "MintBall"
		P.bar(root, Vector3(0.44, up + 0.26, 0.0), at + Vector3(-0.14, 0.14, 0.0), 0.05, P.WOOD_LIGHT)
		parts.mint_ball = mint
		parts.cup = at + Vector3(-0.07, 0.22, 0.02)
	if state.get("top", false):
		P.box(body, Vector3(0.05, 1.1, 0.05), P.WOOD, Vector3(0, 0.55, -0.3))
		P.bar(body, Vector3(0, 1.1, -0.3), Vector3(0, 1.26, 0.02), 0.04, P.WOOD)
		var bell := P.pivot(body, Vector3(0, 1.24, 0.04), "GoldBell")
		bell.scale = Vector3.ONE * P.TOP_SCALE
		P.node(bell, P.low_sphere(0.09), P.gold(), Vector3(0, -0.1, 0), Vector3.ZERO, Vector3(1, 1.2, 1))
		P.node(bell, P.torus(0.09, 0.03), P.gold(), Vector3(0, -0.18, 0))
		parts.gold_bell = bell
	return parts

## Where the ball sits at `angle` on the cradle's rail.
static func _on_rail(angle: float) -> Vector3:
	return CRADLE + Vector3(sin(angle) * (RADIUS - 0.13), -cos(angle) * (RADIUS - 0.13), 0)

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var ball: MeshInstance3D = parts.ball
	var sounds: Dictionary = state.get("sounds", {})
	match beat:
		"base":
			anim.path(ball, func(t: float) -> Vector3: return _on_rail(1.1 * sin(t * TAU * 1.5) * (1.0 - t)), 0.0, 2.1, 1.0 / 6.0)
			anim.sound(str(sounds.get("base", "")), 0.0)
		"together":
			var up := Vector3(0, lift(state), 0)
			var cup: Vector3 = parts.cup
			var edge := _on_rail(1.3)
			anim.path(ball, func(t: float) -> Vector3: return _on_rail(1.3 * t), 0.0, 0.25)
			anim.path(ball, anim.arc(edge, cup - up, 0.05), 0.25, 0.35)
			var mint: MeshInstance3D = parts.mint_ball
			anim.move(mint, "position:x", mint.position.x + 0.07, 0.55, 0.1)
			anim.sound(str(sounds.get("together", "")), 0.55)
		"hard":
			var bottom := LOOP + Vector3(0, -0.12, 0)
			anim.path(ball, anim.arc(_on_rail(0.0), bottom, 0.04), 0.0, 0.15)
			anim.path(ball, func(t: float) -> Vector3:
				var a := t * TAU
				return LOOP + Vector3(sin(a) * 0.12, -cos(a) * 0.12, 0.0), 0.15, 0.4, 0.5)
			anim.path(ball, anim.arc(bottom, _on_rail(0.0), 0.04), 0.55, 0.15)
			anim.sound(str(sounds.get("hard", "")), 0.3)
		"top":
			var bell: Node3D = parts.gold_bell
			anim.move(bell, "rotation:z", 0.45, 0.0, 0.15)
			anim.move(bell, "rotation:z", -0.35, 0.15, 0.2)
			anim.move(bell, "rotation:z", 0.0, 0.35, 0.25)
			brighten(anim, bell, 0.0)
			anim.sound(str(sounds.get("top", "")), 0.0)

func footing_size() -> Vector2:
	return Vector2(1.0, 0.6)

func footprint() -> Rect2:
	return Rect2(-0.5, -0.36, 1.5, 0.72)

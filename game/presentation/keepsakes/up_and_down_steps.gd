extends "res://presentation/keepsakes/keepsake_builder.gd"
## The High and Low keepsake. Tap: a ball pops out of the hatch, hops up the
## steps and rolls back down the chute. Together: a mint seesaw that flings a
## mint ball up the steps after yours lands. Hard: a slate pillar with a
## ladder, so the ball climbs higher before the drop. Together Hard: a gold flag
## on the highest point that pops up as the ball arrives.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const HATCH := Vector3(-0.42, 0.0, 0.02)
const BALL := Color("f2d36b")
const PILLAR_TOP := Vector3(0.3, 0.89, -0.3)

func build(root: Node3D, state: Dictionary) -> Dictionary:
	var hard: bool = state.get("hard", false)
	if hard: P.footing(root, 1.0, 0.8)
	var body := P.body(root, state)
	for i in range(4):
		var h := 0.13 * (i + 1)
		P.box(body, Vector3(0.18, h, 0.42), P.PEACH if i % 2 == 0 else P.CREAM, Vector3(-0.16 + i * 0.18, h * 0.5, 0))
	P.box(body, Vector3(0.24, 0.2, 0.38), P.WOOD, HATCH + Vector3(0, 0.1, 0))
	P.box(body, Vector3(0.18, 0.01, 0.3), Color("294e48"), HATCH + Vector3(0, 0.2, 0))
	var high := _tops()[3]
	if hard:
		P.box(body, Vector3(0.14, 0.82, 0.14), P.SLATE, Vector3(0.3, 0.41, -0.3))
		for i in range(5): P.box(body, Vector3(0.16, 0.02, 0.02), P.WOOD_LIGHT, Vector3(0.3, 0.6 + i * 0.05, -0.215))
		high = PILLAR_TOP
	P.bar(body, Vector3(high.x, high.y - 0.08, -0.3), Vector3(-0.36, 0.24, -0.3), 0.07, P.WOOD_LIGHT)
	var lid := P.pivot(body, HATCH + Vector3(0, 0.205, -0.19), "Lid")
	P.box(lid, Vector3(0.26, 0.03, 0.4), P.CORAL, Vector3(0, 0, 0.2))
	var ball := P.sph(body, 0.065, BALL, HATCH + Vector3(0, 0.2, 0))
	ball.name = "Ball"
	var parts := {"lid": lid, "ball": ball}
	if state.get("together", false):
		var at := P.BESIDE + Vector3(0.06, 0, 0.02)
		P.prism(root, Vector3(0.12, 0.12, 0.14), P.STONE_LIGHT, at + Vector3(0, 0.06, 0))
		var plank := P.pivot(root, at + Vector3(0, 0.13, 0), "Seesaw")
		plank.rotation.z = -0.32
		P.box(plank, Vector3(0.5, 0.03, 0.12), P.MINT_DEEP, Vector3.ZERO)
		P.sph(plank, 0.06, P.MINT, Vector3(0.2, 0.08, 0))
		parts.seesaw = plank
	if state.get("top", false):
		var flag := P.pivot(body, high + Vector3(0.02, -0.07, -0.06), "GoldFlag")
		flag.scale = Vector3.ONE * P.TOP_SCALE
		P.cyl(flag, 0.01, 0.3, P.WOOD, Vector3(0, 0.15, 0))
		P.node(flag, P.Primitives.shared_mesh("prism", 0.12, 0.2, 0.02), P.gold(), Vector3(0.1, 0.25, 0), Vector3(0, 0, -PI / 2))
		P.node(flag, P.low_sphere(0.03), P.gold(), Vector3(0, 0.32, 0))
		parts.gold_flag = flag
	parts.high = high
	return parts

## The tops of the four steps, where the ball lands.
static func _tops() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for i in range(4): result.append(Vector3(-0.16 + i * 0.18, 0.13 * (i + 1) + 0.07, 0.04))
	return result

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var ball: MeshInstance3D = parts.ball
	var lid: Node3D = parts.lid
	var high: Vector3 = parts.high
	var sounds: Dictionary = state.get("sounds", {})
	var tops := _tops()
	match beat:
		"base":
			anim.move(lid, "rotation:x", -1.15, 0.0, 0.15)
			anim.path(ball, anim.arc(HATCH + Vector3(0, 0.2, 0), HATCH + Vector3(0, 0.4, 0.04), 0.05), 0.1, 0.2, 1.0)
			var from := HATCH + Vector3(0, 0.4, 0.04)
			for i in range(4):
				anim.path(ball, anim.arc(from, tops[i], 0.12), 0.3 + i * 0.22, 0.22)
				from = tops[i]
			anim.path(ball, anim.arc(tops[3], Vector3(high.x, high.y + 0.02, -0.3), 0.06), 1.18, 0.15)
			anim.path(ball, func(t: float) -> Vector3: return Vector3(high.x, high.y + 0.02, -0.3).lerp(Vector3(-0.36, 0.3, -0.3), t), 1.35, 0.5)
			anim.path(ball, anim.arc(Vector3(-0.36, 0.3, -0.3), HATCH + Vector3(0, 0.2, 0), 0.05), 1.85, 0.2)
			anim.move(lid, "rotation:x", 0.0, 1.95, 0.15)
			anim.sound(str(sounds.get("base", "")), 0.1)
		"together":
			var plank: Node3D = parts.seesaw
			var at := plank.position + Vector3(0.2, 0.2, 0)
			anim.move(plank, "rotation:z", 0.32, 0.0, 0.12, Tween.TRANS_BACK, Tween.EASE_OUT)
			var mint: MeshInstance3D = anim.spawn(anim.fx, P.low_sphere(0.06), P.mat(P.MINT), at)
			var up := Vector3(0, lift(state), 0)
			anim.set_at(mint, "visible", true, 0.1)
			anim.path(mint, anim.arc(at, tops[3] + up + Vector3(0, 0.02, 0.1), 0.35), 0.1, 0.45)
			anim.set_at(mint, "visible", false, 0.65)
			anim.move(plank, "rotation:z", -0.32, 0.45, 0.2)
			anim.sound(str(sounds.get("together", "")), 0.0)
		"hard":
			anim.move(lid, "rotation:x", -1.15, 0.0, 0.1)
			anim.path(ball, anim.arc(HATCH + Vector3(0, 0.2, 0), PILLAR_TOP + Vector3(0, 0.08, 0), 0.25), 0.05, 0.35)
			anim.path(ball, anim.arc(PILLAR_TOP + Vector3(0, 0.08, 0), HATCH + Vector3(0, 0.2, 0), 0.05), 0.42, 0.25)
			anim.move(lid, "rotation:x", 0.0, 0.55, 0.12)
			anim.sound(str(sounds.get("hard", "")), 0.35)
		"top":
			var flag: Node3D = parts.gold_flag
			var rest := flag.position
			anim.move(flag, "position:y", rest.y + 0.12, 0.0, 0.15, Tween.TRANS_BACK, Tween.EASE_OUT)
			brighten(anim, flag, 0.0)
			anim.move(flag, "position:y", rest.y, 0.45, 0.2)
			anim.sound(str(sounds.get("top", "")), 0.0)

func footing_size() -> Vector2:
	return Vector2(1.0, 0.8)

func footprint() -> Rect2:
	return Rect2(-0.56, -0.4, 1.66, 0.8)

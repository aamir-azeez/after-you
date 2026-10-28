extends "res://presentation/keepsakes/keepsake_builder.gd"
## The Long Way Home keepsake. Tap: the arms spin round to point across Home,
## then swing back. Together: a mint lantern on a short post with stepping
## stones, lit as the arms settle. Hard: a third arm and a stone marker; the
## arms spin a full turn first. Together Hard: a gold bird on top that spreads
## its wings.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const YAWS := [0.2, PI - 0.25, 0.5]
const HEIGHTS := [0.88, 0.66, 0.44]
const COLORS := [P.PEACH, P.CREAM, P.CORAL]
## Where the arms point while they play: back across the island.
const POINT := -2.35

func build(root: Node3D, state: Dictionary) -> Dictionary:
	var hard: bool = state.get("hard", false)
	if hard: P.footing(root, 0.9, 0.74)
	var body := P.body(root, state)
	P.cyl(body, 0.24, 0.08, P.STONE_LIGHT, Vector3(0, 0.04, 0), 0.22)
	P.box(body, Vector3(0.08, 1.06, 0.08), P.WOOD, Vector3(0, 0.57, 0))
	var parts := {}
	for i in range(3 if hard else 2):
		var arm := P.pivot(body, Vector3(0, HEIGHTS[i], 0), "Arm")
		arm.rotation.y = YAWS[i]
		var size := 0.46 if i < 2 else 0.36
		P.box(arm, Vector3(size, 0.13 if i < 2 else 0.1, 0.04), COLORS[i], Vector3(size * 0.5 + 0.03, 0, 0))
		P.box(arm, Vector3(0.1, 0.1, 0.04), COLORS[i], Vector3(size + 0.02, 0, 0), Vector3(0, 0, PI / 4))
		parts["arm%d" % i] = arm
	if state.get("top", false):
		var bird := P.pivot(body, Vector3(0, 1.16, 0), "GoldBird")
		bird.scale = Vector3.ONE * P.TOP_SCALE
		P.node(bird, P.low_sphere(0.06), P.gold(), Vector3.ZERO, Vector3.ZERO, Vector3(1.3, 1, 1))
		P.node(bird, P.low_sphere(0.04), P.gold(), Vector3(0.06, 0.06, 0.02))
		P.prism(bird, Vector3(0.025, 0.04, 0.02), P.PEACH, Vector3(0.11, 0.06, 0.02), Vector3(0, 0, -PI / 2))
		var wings := P.pivot(bird, Vector3(-0.01, 0.02, 0), "Wings")
		for side: int in [-1, 1]: P.node(wings, P.low_sphere(0.05), P.mat(P.GOLD), Vector3(0, 0, side * 0.05), Vector3(side * 0.25, 0, 0), Vector3(1.4, 0.3, 0.8))
		parts.bird = bird
		parts.wings = wings
	else:
		P.sph(body, 0.05, P.CREAM, Vector3(0, 1.12, 0))
	if state.get("together", false):
		var at := P.BESIDE + Vector3(-0.02, 0, -0.02)
		P.box(root, Vector3(0.05, 0.5, 0.05), P.WOOD, at + Vector3(0, 0.25, 0))
		var lantern := P.box(root, Vector3(0.12, 0.14, 0.12), P.LAMP_OFF, at + Vector3(0, 0.57, 0))
		lantern.name = "MintLantern"
		P.prism(root, Vector3(0.18, 0.08, 0.18), P.MINT_DEEP, at + Vector3(0, 0.68, 0))
		P.box(root, Vector3(0.15, 0.025, 0.15), P.MINT_DEEP, at + Vector3(0, 0.495, 0))
		for i in range(2): P.cyl(root, 0.08, 0.025, P.MINT, Vector3(0.3 + i * 0.2, 0.012, 0.32 - i * 0.06))
		parts.lantern = lantern
	if hard:
		P.box(root, Vector3(0.18, 0.22, 0.12), P.SLATE, Vector3(-0.3, P.FOOT_HEIGHT + 0.11, 0.2))
		P.prism(root, Vector3(0.08, 0.045, 0.02), P.SNOW, Vector3(-0.3, P.FOOT_HEIGHT + 0.16, 0.265))
	return parts

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var arms: Array = []
	for i in range(3):
		if parts.has("arm%d" % i): arms.append(parts["arm%d" % i])
	var sounds: Dictionary = state.get("sounds", {})
	match beat:
		"base":
			for i in range(arms.size()):
				var arm: Node3D = arms[i]
				anim.move(arm, "rotation:y", POINT - i * 0.15, 0.0, 0.7, Tween.TRANS_BACK, Tween.EASE_OUT)
				anim.move(arm, "rotation:y", YAWS[i], 1.5, 0.55)
			anim.sound(str(sounds.get("base", "")), 0.0)
		"together":
			anim.set_at(parts.lantern, "material_override", P.glow(P.LAMP, 2.0), 0.05)
			anim.sound(str(sounds.get("together", "")), 0.05)
		"hard":
			for i in range(arms.size()):
				var arm: Node3D = arms[i]
				anim.move(arm, "rotation:y", YAWS[i] + TAU * (1 if i % 2 == 0 else -1), 0.0, 0.65)
			anim.sound(str(sounds.get("hard", "")), 0.0)
		"top":
			var bird: Node3D = parts.bird
			var wings: Node3D = parts.wings
			brighten(anim, bird, 0.0)
			anim.move(wings, "scale", Vector3(1, 2.4, 2.4), 0.0, 0.2, Tween.TRANS_BACK, Tween.EASE_OUT)
			anim.move(bird, "position:y", bird.position.y + 0.06, 0.0, 0.2)
			anim.move(wings, "scale", Vector3.ONE, 0.45, 0.2)
			anim.move(bird, "position:y", bird.position.y, 0.45, 0.2)
			anim.sound(str(sounds.get("top", "")), 0.0)

func footprint() -> Rect2:
	return Rect2(-0.62, -0.42, 1.64, 0.84)

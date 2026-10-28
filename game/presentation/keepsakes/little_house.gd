extends "res://presentation/keepsakes/keepsake_builder.gd"
## The A House for Two keepsake. Tap: the shutters open, the window lights,
## the shutters close. Together: a mint mailbox whose flag goes up with a letter
## in it. Hard: the house stands on a cellar, and the cellar window lights too.
## Together Hard: a gold chimney that puffs three rings of smoke.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const WINDOW := Vector3(0.14, 0.29, 0.235)

func build(root: Node3D, state: Dictionary) -> Dictionary:
	var hard: bool = state.get("hard", false)
	if hard: P.footing(root, 0.84, 0.7)
	var body := P.body(root, state)
	P.box(body, Vector3(0.64, 0.46, 0.46), P.CREAM, Vector3(0, 0.23, 0))
	P.prism(body, Vector3(0.6, 0.3, 0.82), P.ROOF, Vector3(0, 0.61, 0), Vector3(0, PI / 2, 0))
	P.box(body, Vector3(0.15, 0.27, 0.03), P.WOOD, Vector3(-0.16, 0.135, 0.235))
	P.sph(body, 0.014, P.GOLD, Vector3(-0.11, 0.13, 0.255))
	var window := P.box(body, Vector3(0.17, 0.16, 0.03), P.LAMP_OFF, WINDOW)
	window.name = "Window"
	P.box(body, Vector3(0.02, 0.17, 0.035), P.CREAM, WINDOW + Vector3(0, 0, 0.01))
	P.box(body, Vector3(0.19, 0.02, 0.035), P.CREAM, WINDOW + Vector3(0, 0, 0.01))
	var shutters: Array = []
	for side: int in [-1, 1]:
		var hinge := P.pivot(body, WINDOW + Vector3(side * 0.095, 0, 0.04), "Shutter")
		P.box(hinge, Vector3(0.08, 0.18, 0.02), P.PEACH, Vector3(-side * 0.06, 0, 0))
		shutters.append(hinge)
	var parts := {"window": window, "shutter_left": shutters[0], "shutter_right": shutters[1]}
	if state.get("together", false):
		var at := P.BESIDE + Vector3(-0.06, 0, 0.06)
		P.box(root, Vector3(0.04, 0.44, 0.04), P.WOOD, at + Vector3(0, 0.22, 0))
		P.box(root, Vector3(0.15, 0.13, 0.24), P.MINT, at + Vector3(0, 0.5, 0))
		P.node(root, P.Primitives.shared_mesh("cylinder", 0.075, 0.24, 0.075), P.mat(P.MINT), at + Vector3(0, 0.565, 0), Vector3(PI / 2, 0, 0))
		var flag := P.pivot(root, at + Vector3(0.085, 0.5, -0.06), "MailFlag")
		flag.rotation.z = -PI / 2
		P.box(flag, Vector3(0.02, 0.13, 0.03), P.CORAL, Vector3(0, 0.065, 0))
		parts.mail_flag = flag
		parts.mailbox = at
	if hard:
		P.box(root, Vector3(0.28, 0.1, 0.02), P.SLATE_DARK, Vector3(0.18, 0.1, 0.355))
		var cellar := P.box(root, Vector3(0.22, 0.06, 0.02), P.LAMP_OFF, Vector3(0.18, 0.1, 0.362))
		cellar.name = "CellarWindow"
		parts.cellar_window = cellar
	if state.get("top", false):
		var chimney := P.pivot(body, Vector3(0.2, 0.72, -0.1), "GoldChimney")
		chimney.scale = Vector3.ONE * P.TOP_SCALE
		P.node(chimney, P.Primitives.shared_mesh("box", 0.1, 0.2, 0.1), P.gold(), Vector3.ZERO)
		P.node(chimney, P.Primitives.shared_mesh("box", 0.13, 0.03, 0.13), P.gold(), Vector3(0, 0.11, 0))
		parts.chimney = chimney
	return parts

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var sounds: Dictionary = state.get("sounds", {})
	match beat:
		"base":
			for side: int in [-1, 1]:
				var hinge: Node3D = parts.shutter_left if side < 0 else parts.shutter_right
				anim.move(hinge, "rotation:y", side * 2.1, 0.0, 0.5, Tween.TRANS_BACK, Tween.EASE_OUT)
				anim.move(hinge, "rotation:y", 0.0, 1.65, 0.45)
			anim.set_at(parts.window, "material_override", P.glow(P.LAMP, 1.6), 0.35)
			anim.set_at(parts.window, "material_override", P.mat(P.LAMP_OFF), 1.75)
			anim.sound(str(sounds.get("base", "")), 0.0)
		"together":
			var flag: Node3D = parts.mail_flag
			anim.move(flag, "rotation:z", 0.0, 0.05, 0.25, Tween.TRANS_BACK, Tween.EASE_OUT)
			var at: Vector3 = parts.mailbox
			var letter: MeshInstance3D = anim.spawn(anim.fx, P.Primitives.shared_mesh("box", 0.1, 0.07, 0.01), P.mat(P.SNOW), at + Vector3(0, 0.53, 0.125), Vector3(0, 0, 0.15))
			anim.set_at(letter, "visible", true, 0.25)
			anim.sound(str(sounds.get("together", "")), 0.05)
		"hard":
			anim.set_at(parts.cellar_window, "material_override", P.glow(P.LAMP, 1.8), 0.05)
			anim.sound(str(sounds.get("hard", "")), 0.05)
		"top":
			var chimney: Node3D = parts.chimney
			brighten(anim, chimney, 0.0)
			var up := Vector3(0, lift(state), 0)
			for i in range(3):
				var puff: MeshInstance3D = anim.spawn(anim.fx, P.torus(0.05, 0.025), P.mat(P.SNOW), up + Vector3(0.2, 0.88, -0.1), Vector3.ZERO, Vector3.ONE * 0.6)
				anim.set_at(puff, "visible", true, i * 0.15)
				anim.path(puff, func(t: float) -> Vector3: return up + Vector3(0.2 + t * 0.08, 0.88 + t * 0.3, -0.1), i * 0.15, 0.4)
				anim.move(puff, "scale", Vector3.ONE * 1.4, i * 0.15, 0.4)
				anim.set_at(puff, "visible", false, i * 0.15 + 0.42)
			anim.sound(str(sounds.get("top", "")), 0.0)

func footing_size() -> Vector2:
	return Vector2(0.84, 0.7)

func footprint() -> Rect2:
	return Rect2(-0.42, -0.41, 1.36, 0.82)

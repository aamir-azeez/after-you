extends "res://presentation/keepsakes/keepsake_builder.gd"
## The Long Way Home keepsake: a Crossroads signpost on a stone circle, with a
## low arm at the pip's height. Bumping it (walking onto the circle, or a tap)
## spins the post until its first arm points the way to the other spirit, and
## a path of stones lights toward it. Together: a mint lantern at the crossing
## lights as the arms settle. Hard: a third arm and a slate marker, and the
## post spins a full turn first. Together Hard: a gold bird on top takes off
## and circles the post.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const HARD_LIFT := 0.34
const LANTERN := Vector3(1.15, 0, -0.2)
const MARKER := Vector3(-0.7, 0, 0.55)
const YAWS: Array[float] = [0.3, PI - 0.3, 1.6]
const HEIGHTS: Array[float] = [1.9, 1.45, 1.05]
const DISC := 0.85

static func _y0(state: Dictionary) -> float:
	return HARD_LIFT if state.get("hard", false) else 0.0

static func _stone(index: int) -> Vector3:
	return Vector3(-0.35 - index * 0.06, 0.02, 1.0 + index * 0.38)

func build(root: Node3D, state: Dictionary) -> Dictionary:
	var hard: bool = state.get("hard", false)
	var y0 := _y0(state)
	P.cyl(root, DISC, 0.04, Color("e1d8bf"), Vector3(0, 0.02, 0))
	for index in range(10):
		var angle := index * TAU / 10.0
		P.cyl(root, 0.12, 0.03, Color("d2c7aa"), Vector3(cos(angle) * 0.6, 0.045, sin(angle) * 0.6))
	if hard:
		P.plinth(root, 0.7, 0.7)
		P.box(root, Vector3(0.36, 0.5, 0.24), P.SLATE, MARKER + Vector3(0, 0.25, 0))
		P.prism(root, Vector3(0.16, 0.09, 0.03), P.SNOW, MARKER + Vector3(0, 0.36, 0.13))
	P.box(root, Vector3(0.14, 2.3, 0.14), P.WOOD, Vector3(0, y0 + 1.15, 0))
	var colors: Array[Color] = [P.PEACH, P.CREAM, P.CORAL]
	var parts := {}
	for index in range(3 if hard else 2):
		var arm := P.pivot(root, Vector3(0, y0 + HEIGHTS[index], 0), "Arm")
		arm.rotation.y = YAWS[index]
		P.box(arm, Vector3(0.85, 0.22, 0.06), colors[index], Vector3(0.48, 0, 0))
		P.box(arm, Vector3(0.18, 0.18, 0.06), colors[index], Vector3(0.9, 0, 0), Vector3(0, 0, PI / 4))
		parts["arm_%d" % index] = arm
	# The low arm hangs at the pip's height, so walking into it spins the post.
	var bump := P.pivot(root, Vector3(0, y0 + 0.6, 0), "BumpArm")
	bump.rotation.y = 0.9
	P.box(bump, Vector3(0.6, 0.16, 0.06), P.WOOD_LIGHT, Vector3(0.34, 0, 0))
	parts.bump = bump
	for index in range(6): P.cyl(root, 0.15, 0.04, Color("e6dcc0"), _stone(index))
	if state.get("together", false):
		var at := LANTERN
		P.box(root, Vector3(0.08, 0.95, 0.08), P.WOOD, at + Vector3(0, 0.47, 0))
		var lamp := P.box(root, Vector3(0.22, 0.26, 0.22), P.LAMP_OFF, at + Vector3(0, 1.08, 0))
		lamp.name = "Lantern"
		P.prism(root, Vector3(0.34, 0.15, 0.34), P.MINT_DEEP, at + Vector3(0, 1.28, 0))
		P.box(root, Vector3(0.28, 0.04, 0.28), P.MINT_DEEP, at + Vector3(0, 0.93, 0))
		parts.lantern = lamp
	if state.get("top", false):
		var bird := P.pivot(root, Vector3(0, y0 + 2.42, 0), "Bird")
		P.node(bird, P.low_sphere(0.138, 0.24), P.gold(), Vector3.ZERO)
		P.node(bird, P.low_sphere(0.08), P.gold(), Vector3(0.12, 0.1, 0.03))
		for side: int in [-1, 1]: P.sph(bird, 0.11, P.GOLD, Vector3(-0.02, 0.04, side * 0.1), Vector3(1.1, 0.3, 1.1), Vector3(side * 0.25, 0, 0))
		parts.bird = bird
	return parts

func base_time() -> float:
	return 2.3

func upgrade_time(beat: String) -> float:
	return 0.8 if beat == "top" else 0.5

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var sounds: Dictionary = state.get("sounds", {})
	var y0 := _y0(state)
	match beat:
		"base":
			# The bump swings the low arm; the post spins until the first arm points
			# to the other spirit (or back the way it came, with no spirit about).
			var bump: Node3D = parts.bump
			anim.move(bump, "rotation:y", 0.9 - 1.2, 0.0, 0.18)
			anim.move(bump, "rotation:y", 0.9, 0.2, 0.35)
			var toward: Vector2 = state.get("toward", Vector2(0, 1))
			var aim := atan2(-toward.y, toward.x)
			var turns := 3.0 if state.get("hard", false) else 2.0
			for index in range(3):
				if not parts.has("arm_%d" % index): continue
				var arm: Node3D = parts["arm_%d" % index]
				var settle: float = aim + [0.0, PI, PI * 0.5][index]
				# Whole turns from its rest, then on round to its aim.
				var target: float = YAWS[index] + TAU * turns + fposmod(settle - YAWS[index], TAU)
				anim.move(arm, "rotation:y", target, 0.1 + index * 0.05, 1.4, Tween.TRANS_CUBIC, Tween.EASE_OUT)
			anim.sound(str(sounds.get("base", "")), 0.05)
			for index in range(6):
				var glow: MeshInstance3D = anim.spawn(anim.fx, P.Primitives.shared_mesh("cylinder", 0.16, 0.02, 0.16), P.glow(P.LAMP, 1.2 - index * 0.12), _stone(index) + Vector3(0, 0.03, 0))
				anim.set_at(glow, "visible", true, 1.3 + index * 0.12)
			anim.burst(anim.fx, Vector3(0, y0 + 1.6, 0), 6, 0.75, 0.3, 0.9)
		"together":
			anim.set_at(parts.lantern, "material_override", P.glow(P.LAMP, 2.0), 0.0)
			anim.halo(anim.fx, LANTERN + Vector3(0, 1.08, 0), 0.3, P.LAMP, 0.0, 0.5)
			anim.sound(str(sounds.get("together", "")), 0.0)
		"hard":
			anim.burst(anim.fx, MARKER + Vector3(0, 0.55, 0), 5, 0.25, 0.0, 0.45)
			anim.sound(str(sounds.get("hard", "")), 0.0)
		"top":
			# The gold bird takes off, circles the post once and lands again.
			var bird: Node3D = parts.bird
			var home := bird.position
			anim.path(bird, func(t: float) -> Vector3:
				var angle := t * TAU
				var radius := sin(t * PI) * 0.6
				return home + Vector3(sin(angle) * radius, sin(t * PI) * 0.4, (1.0 - cos(angle)) * radius * 0.5), 0.0, 0.75, 0.3)
			anim.move(bird, "rotation:y", TAU, 0.0, 0.75, Tween.TRANS_LINEAR)
			brighten(anim, bird, 0.0)
			anim.sound(str(sounds.get("top", "")), 0.0)

## Walking onto the stone circle bumps the low arm.
func trigger() -> Dictionary:
	return {"area": Rect2(-0.72, -0.72, 1.44, 1.44)}

func solids(state: Dictionary) -> Array[Rect2]:
	var half := 0.35 if state.get("hard", false) else 0.1
	var result: Array[Rect2] = [Rect2(-half, -half, half * 2.0, half * 2.0)]
	if state.get("hard", false): result.append(Rect2(MARKER.x - 0.18, MARKER.z - 0.12, 0.36, 0.24))
	if state.get("together", false): result.append(Rect2(LANTERN.x - 0.14, LANTERN.z - 0.14, 0.28, 0.28))
	return result

func footprint() -> Rect2:
	return Rect2(-1.0, -1.1, 2.35, 4.1)

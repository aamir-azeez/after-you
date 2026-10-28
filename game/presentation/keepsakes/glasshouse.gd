extends "res://presentation/keepsakes/keepsake_builder.gd"
## The Conservatory keepsake. Tap: the roof opens and the flower inside blooms,
## then it all closes. Together: a mint watering can that tips and waters.
## Hard: a vine up the side whose leaves open with the bloom. Together Hard: a
## gold sun on the ridge that turns a full circle while the flower's middle
## turns gold. The see-through walls are one merged mesh, one draw.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const RIDGE := Vector3(0, 0.84, 0)
const CLOSED := 0.588
## The flower at rest: a closed bud.
const BUD := 0.4

func build(root: Node3D, state: Dictionary) -> Dictionary:
	if state.get("hard", false): P.footing(root, 0.96, 0.72)
	var body := P.body(root, state)
	P.box(body, Vector3(0.84, 0.08, 0.58), P.WOOD, Vector3(0, 0.04, 0))
	for z: float in [-0.26, 0.26]:
		for x: float in [-0.39, 0.39]: P.box(body, Vector3(0.045, 0.5, 0.045), P.CREAM, Vector3(x, 0.33, z))
		P.box(body, Vector3(0.82, 0.04, 0.045), P.CREAM, Vector3(0, 0.58, z))
		for side: int in [-1, 1]: P.bar(body, Vector3(side * 0.39, 0.58, z), Vector3(0, 0.84, z), 0.04, P.CREAM)
	P.box(body, Vector3(0.04, 0.04, 0.56), P.CREAM, RIDGE)
	var walls := _walls_node(body)
	walls.name = "Walls"
	var roof: Array = []
	for side: int in [-1, 1]:
		var hinge := P.pivot(body, RIDGE, "RoofPane")
		hinge.rotation.z = side * -CLOSED
		P.node(hinge, P.Primitives.shared_mesh("box", 0.47, 0.01, 0.5), _glass(), Vector3(side * 0.235, 0, 0))
		roof.append(hinge)
	P.cyl(body, 0.09, 0.12, P.POT, Vector3(0, 0.14, 0), 0.11)
	P.cyl(body, 0.012, 0.24, P.LEAF, Vector3(0, 0.32, 0))
	P.sph(body, 0.05, P.LEAF, Vector3(-0.06, 0.28, 0), Vector3(1.2, 0.45, 0.6))
	var flower := P.pivot(body, Vector3(0, 0.46, 0.02), "Flower")
	flower.scale = Vector3.ONE * BUD
	for i in range(5):
		var a := i * TAU / 5.0
		P.sph(flower, 0.07, P.PEACH, Vector3(cos(a), sin(a), 0) * 0.08, Vector3(1, 1, 0.45))
	P.sph(flower, 0.045, P.CREAM, Vector3(0, 0, 0.03))
	var parts := {"roof_left": roof[0], "roof_right": roof[1], "flower": flower}
	if state.get("together", false):
		var can := P.pivot(root, P.BESIDE + Vector3(-0.02, 0, 0.06), "Can")
		P.cyl(can, 0.1, 0.17, P.MINT, Vector3(0, 0.085, 0), 0.09)
		P.ring(can, 0.1, 0.025, P.MINT_DEEP, Vector3(0, 0.17, 0))
		P.bar(can, Vector3(-0.08, 0.06, 0), Vector3(-0.22, 0.2, 0), 0.03, P.MINT_DEEP)
		P.ring(can, 0.07, 0.025, P.MINT_DEEP, Vector3(0.08, 0.17, 0), Vector3(PI / 2, 0, PI / 2))
		parts.can = can
	if state.get("hard", false):
		P.cyl(body, 0.012, 0.6, P.LEAF, Vector3(-0.44, 0.32, 0.3))
		var vine := P.pivot(body, Vector3(-0.44, 0.0, 0.32), "Vine")
		for i in range(4): P.sph(vine, 0.05, P.LEAF, Vector3(0.04 if i % 2 == 0 else -0.04, 0.12 + i * 0.15, 0), Vector3(1.2, 0.5, 0.7))
		P.sph(vine, 0.035, P.CORAL, Vector3(0.04, 0.62, 0.01))
		P.sph(vine, 0.03, P.CREAM, Vector3(-0.03, 0.42, 0.01))
		parts.vine = vine
	if state.get("top", false):
		P.cyl(body, 0.01, 0.1, P.WOOD, Vector3(0, 0.9, 0))
		var sun := P.pivot(body, Vector3(0, 1.02, 0), "GoldSun")
		sun.scale = Vector3.ONE * P.TOP_SCALE
		P.node(sun, P.Primitives.shared_mesh("cylinder", 0.1, 0.02, 0.1), P.gold(), Vector3.ZERO, Vector3(PI / 2, 0, 0))
		for i in range(8):
			var a := i * TAU / 8.0
			P.node(sun, P.Primitives.shared_mesh("box", 0.05, 0.02, 0.02), P.gold(), Vector3(cos(a) * 0.14, sin(a) * 0.14, 0), Vector3(0, 0, a))
		parts.sun = sun
	return parts

## The four see-through walls as one merged mesh: one draw.
const WALLS := [[Vector3(0.76, 0.48, 0.01), Vector3(0, 0.33, 0.26)], [Vector3(0.76, 0.48, 0.01), Vector3(0, 0.33, -0.26)], [Vector3(0.01, 0.48, 0.5), Vector3(-0.39, 0.33, 0)], [Vector3(0.01, 0.48, 0.5), Vector3(0.39, 0.33, 0)]]

static func _walls_node(body: Node3D) -> MeshInstance3D:
	var part := P.Primitives.mesh_node(P.merged_boxes("glasshouse-walls", WALLS), _glass(), Vector3.ZERO, body)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return part

static func _glass() -> Material:
	return P.clear(P.GLASS, 0.3)

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var flower: Node3D = parts.flower
	var sounds: Dictionary = state.get("sounds", {})
	match beat:
		"base":
			for side: int in [-1, 1]:
				var hinge: Node3D = parts.roof_left if side < 0 else parts.roof_right
				anim.move(hinge, "rotation:z", side * (-CLOSED + 0.95), 0.0, 0.5)
				anim.move(hinge, "rotation:z", side * -CLOSED, 1.65, 0.45)
			anim.move(flower, "scale", Vector3.ONE, 0.35, 0.6, Tween.TRANS_BACK, Tween.EASE_OUT)
			anim.move(flower, "scale", Vector3.ONE * BUD, 1.5, 0.45)
			anim.sound(str(sounds.get("base", "")), 0.35)
		"together":
			var can: Node3D = parts.can
			var rest := can.position
			anim.move(can, "position", rest + Vector3(-0.1, 0.32, 0), 0.0, 0.2)
			anim.move(can, "rotation:z", 0.7, 0.0, 0.2)
			for i in range(3):
				var drop: MeshInstance3D = anim.spawn(anim.fx, P.low_sphere(0.022), P.mat(P.TIDE), rest + Vector3(-0.32, 0.46, 0), Vector3.ZERO, Vector3(1, 1.4, 1))
				anim.set_at(drop, "visible", true, 0.2 + i * 0.08)
				anim.path(drop, func(t: float) -> Vector3: return rest + Vector3(-0.32 - t * 0.1, 0.46 - t * 0.3, 0), 0.2 + i * 0.08, 0.25)
				anim.set_at(drop, "visible", false, 0.46 + i * 0.08)
			anim.move(can, "position", rest, 0.5, 0.2)
			anim.move(can, "rotation:z", 0.0, 0.5, 0.2)
			anim.sound(str(sounds.get("together", "")), 0.2)
		"hard":
			var vine: Node3D = parts.vine
			anim.move(vine, "scale", Vector3(1.4, 1.05, 1.4), 0.0, 0.3, Tween.TRANS_BACK, Tween.EASE_OUT)
			anim.move(vine, "scale", Vector3.ONE, 0.45, 0.25)
			anim.sound(str(sounds.get("hard", "")), 0.0)
		"top":
			var sun: Node3D = parts.sun
			anim.move(sun, "rotation:z", TAU, 0.0, 0.6)
			brighten(anim, sun, 0.0)
			var heart: MeshInstance3D = anim.spawn(flower, P.low_sphere(0.05), P.gold(true), Vector3(0, 0, 0.035))
			anim.set_at(heart, "visible", true, 0.05)
			anim.sound(str(sounds.get("top", "")), 0.0)

func footing_size() -> Vector2:
	return Vector2(0.96, 0.72)

func footprint() -> Rect2:
	return Rect2(-0.48, -0.36, 1.52, 0.72)

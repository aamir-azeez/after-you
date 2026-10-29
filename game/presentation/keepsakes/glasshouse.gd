extends "res://presentation/keepsakes/keepsake_builder.gd"
## The Conservatory keepsake: a glasshouse with a flower in a pot and a pump
## by the door. Pushing the pump handle (walking up to it, or a tap) runs water
## in; the roof opens and the flower grows taller than the pip and blooms.
## Together: a mint watering can that tips and waters too. Hard: vines climb
## both back corners from slate plinths, and their flowers open with the
## bloom. Together Hard: a gold sun on the ridge turns, and the flower's middle
## turns gold.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const W := 1.9
const D := 1.35
const WALL := 1.15
const RIDGE := 1.75
const PUMP := Vector3(1.25, 0, 0.62)
const CAN := Vector3(-1.35, 0, 0.5)
## How much the flower grows when it blooms.
const GROWN := 2.2

func build(root: Node3D, state: Dictionary) -> Dictionary:
	P.box(root, Vector3(W, 0.06, D), P.WOOD, Vector3(0, 0.03, 0))
	for z: float in [-D * 0.5, D * 0.5]:
		for x: float in [-W * 0.5, W * 0.5]: P.box(root, Vector3(0.07, WALL, 0.07), P.CREAM, Vector3(x, WALL * 0.5, z))
		P.box(root, Vector3(W, 0.06, 0.07), P.CREAM, Vector3(0, WALL, z))
		for side: int in [-1, 1]: P.bar(root, Vector3(side * W * 0.5, WALL, z), Vector3(0, RIDGE, z), 0.06, P.CREAM)
	P.box(root, Vector3(0.06, 0.06, D), P.CREAM, Vector3(0, RIDGE, 0))
	# The four glass walls as one see-through mesh.
	var walls := P.merged_boxes("glasshouse|walls", [[Vector3(W - 0.1, WALL - 0.05, 0.015), Vector3(0, WALL * 0.5, -D * 0.5)], [Vector3(W - 0.1, WALL - 0.05, 0.015), Vector3(0, WALL * 0.5, D * 0.5)],
		[Vector3(0.015, WALL - 0.05, D - 0.1), Vector3(-W * 0.5, WALL * 0.5, 0)], [Vector3(0.015, WALL - 0.05, D - 0.1), Vector3(W * 0.5, WALL * 0.5, 0)]])
	P.node(root, walls, _glass(), Vector3.ZERO)
	var parts := {}
	for side: int in [-1, 1]:
		var pane := P.pivot(root, Vector3(0, RIDGE, 0), "RoofPane")
		pane.rotation.z = side * -0.56
		P.node(pane, P.Primitives.shared_mesh("box", 1.12, 0.015, D - 0.06), _glass(), Vector3(side * 0.56, 0, 0))
		parts["roof_%s" % ("left" if side < 0 else "right")] = pane
	P.cyl(root, 0.32, 0.26, P.POT, Vector3(0, 0.13, 0), 0.36)
	# The flower grows from the pot as one part: its stem, leaves and bud.
	var flower := P.pivot(root, Vector3(0, 0.26, 0.05), "Flower")
	P.cyl(flower, 0.025, 0.5, P.LEAF, Vector3(0, 0.25, 0))
	for side: int in [-1, 1]: P.sph(flower, 0.1, P.LEAF, Vector3(side * 0.13, 0.32, 0), Vector3(0.95, 0.45, 0.95), Vector3(0, 0, side * 0.3))
	P.sph(flower, 0.11, P.PEACH, Vector3(0, 0.55, 0), Vector3(0.8, 1.3, 0.8))
	parts.flower = flower
	# The pump outside the door: a post with a long handle the pip pushes, and a pipe in.
	P.box(root, Vector3(0.16, 0.7, 0.16), P.SLATE, PUMP + Vector3(0, 0.35, 0))
	P.cyl(root, 0.06, 0.05, P.GOLD, PUMP + Vector3(0, 0.72, 0))
	var handle := P.pivot(root, PUMP + Vector3(0, 0.72, 0), "Handle")
	handle.rotation.z = 0.5
	P.box(handle, Vector3(0.7, 0.05, 0.05), P.WOOD, Vector3(0.32, 0, 0))
	parts.handle = handle
	P.bar(root, PUMP + Vector3(-0.08, 0.55, 0), Vector3(W * 0.5, 0.55, 0.45), 0.06, P.SLATE)
	if state.get("together", false):
		var can := P.pivot(root, CAN, "Can")
		P.cyl(can, 0.2, 0.34, P.MINT, Vector3(0, 0.17, 0), 0.18)
		P.ring(can, 0.2, 0.05, P.MINT_DEEP, Vector3(0, 0.34, 0))
		P.bar(can, Vector3(0.16, 0.12, 0), Vector3(0.44, 0.4, 0), 0.06, P.MINT_DEEP)
		parts.can = can
	if state.get("hard", false):
		for side: int in [-1, 1]:
			var foot := _vine(side)
			P.plinth(root, 0.36, 0.36, foot)
			P.cyl(root, 0.025, 1.4, P.LEAF, foot + Vector3(0, 0.34 + 0.7, 0))
			for index in range(5): P.sph(root, 0.08, P.LEAF, foot + Vector3(0.07 if index % 2 == 0 else -0.07, 0.5 + index * 0.22, 0), Vector3(0.95, 0.5, 0.95), Vector3(0, 0, 0.5 if index % 2 == 0 else -0.5))
	if state.get("top", false):
		P.cyl(root, 0.02, 0.2, P.WOOD, Vector3(0, RIDGE + 0.1, 0))
		var sun := P.pivot(root, Vector3(0, RIDGE + 0.38, 0), "Sun")
		P.node(sun, P.Primitives.shared_mesh("cylinder", 0.18, 0.04, 0.18), P.gold(), Vector3.ZERO, Vector3(PI / 2, 0, 0))
		for index in range(8):
			var angle := index * TAU / 8.0
			P.node(sun, P.Primitives.shared_mesh("box", 0.1, 0.035, 0.035), P.gold(), Vector3(cos(angle) * 0.26, sin(angle) * 0.26, 0), Vector3(0, 0, angle))
		parts.sun = sun
	return parts

static func _glass() -> Material:
	return P.clear(P.GLASS, 0.28)

static func _vine(side: int) -> Vector3:
	return Vector3(side * (W * 0.5 + 0.12), 0, -D * 0.5 - 0.05)

func base_time() -> float:
	return 2.4

func upgrade_time(_beat: String) -> float:
	return 0.6

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var sounds: Dictionary = state.get("sounds", {})
	var flower: Node3D = parts.flower
	var bud := Vector3(0, 0.55, 0)
	match beat:
		"base":
			# Two pushes on the handle run water in along the pipe.
			var handle: Node3D = parts.handle
			for push in range(2):
				anim.move(handle, "rotation:z", -0.55, push * 0.45, 0.2)
				anim.move(handle, "rotation:z", 0.5, push * 0.45 + 0.2, 0.22)
			for index in range(4):
				var drop: MeshInstance3D = anim.spawn(anim.fx, P.low_sphere(0.045, 0.12), P.mat(P.TIDE), PUMP + Vector3(-0.1, 0.62, 0))
				anim.set_at(drop, "visible", true, 0.2 + index * 0.12)
				anim.move(drop, "position", Vector3(W * 0.5 - 0.1, 0.58, 0.42), 0.2 + index * 0.12, 0.4, Tween.TRANS_LINEAR)
				anim.set_at(drop, "visible", false, 0.6 + index * 0.12)
			# The roof opens and the flower grows taller than the pip, then blooms.
			anim.move(parts.roof_left, "rotation:z", 0.56 - 0.9, 0.6, 0.5)
			anim.move(parts.roof_right, "rotation:z", -0.56 + 0.9, 0.6, 0.5)
			anim.move(flower, "scale", Vector3.ONE * GROWN, 0.8, 0.8, Tween.TRANS_BACK, Tween.EASE_OUT)
			for index in range(6):
				var angle := index * TAU / 6.0
				var petal: MeshInstance3D = anim.spawn(flower, P.low_sphere(0.075, 0.15), P.mat(P.PEACH), bud + Vector3(cos(angle), sin(angle), 0) * 0.04, Vector3(0, 0, angle))
				anim.set_at(petal, "visible", true, 1.5)
				anim.move(petal, "position", bud + Vector3(cos(angle), sin(angle), 0) * 0.09 + Vector3(0, 0, 0.02), 1.5, 0.3, Tween.TRANS_BACK, Tween.EASE_OUT)
			anim.burst(anim.fx, bud * GROWN + Vector3(0, 0.3, 0.1), 6, 0.45, 1.7, 0.6)
			anim.sound(str(sounds.get("base", "")), 1.5)
		"together":
			var can: Node3D = parts.can
			anim.move(can, "position:y", CAN.y + 0.55, 0.0, 0.2)
			anim.move(can, "rotation:z", -0.7, 0.1, 0.2)
			for index in range(3):
				var drop: MeshInstance3D = anim.spawn(anim.fx, P.low_sphere(0.04, 0.1), P.mat(P.TIDE), CAN + Vector3(0.44, 0.75, 0))
				anim.set_at(drop, "visible", true, 0.25 + index * 0.08)
				anim.move(drop, "position", CAN + Vector3(0.6, 0.1, 0), 0.25 + index * 0.08, 0.25, Tween.TRANS_QUAD, Tween.EASE_IN)
				anim.set_at(drop, "visible", false, 0.5 + index * 0.08)
			anim.sound(str(sounds.get("together", "")), 0.0)
		"hard":
			# The vines' flowers open.
			for side: int in [-1, 1]:
				var bloom: MeshInstance3D = anim.spawn(anim.fx, P.low_sphere(0.07), P.mat(P.CORAL), _vine(side) + Vector3(0, 1.55, 0.02), Vector3.ZERO, Vector3.ONE * 0.2)
				anim.set_at(bloom, "visible", true, 0.0)
				anim.move(bloom, "scale", Vector3.ONE, 0.0, 0.35, Tween.TRANS_BACK, Tween.EASE_OUT)
			anim.sound(str(sounds.get("hard", "")), 0.0)
		"top":
			# The sun turns and lights, and the flower's middle turns gold.
			var sun: Node3D = parts.sun
			anim.move(sun, "rotation:z", TAU * 0.5, 0.0, 0.55)
			brighten(anim, sun, 0.0)
			var heart: MeshInstance3D = anim.spawn(flower, P.low_sphere(0.055), P.gold(true), bud + Vector3(0, 0, 0.03))
			anim.set_at(heart, "visible", true, 0.0)
			anim.halo(anim.fx, Vector3(0, RIDGE + 0.38, 0), 0.4, P.GOLD, 0.0, 0.55, 0.22)
			anim.sound(str(sounds.get("top", "")), 0.0)

## Walking up to the pump handle.
func trigger() -> Dictionary:
	return {"area": Rect2(PUMP.x + 0.1, PUMP.z - 0.1, 0.65, 0.6)}

func solids(state: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = [Rect2(-W * 0.5 - 0.05, -D * 0.5 - 0.05, W + 0.1, D + 0.1), Rect2(PUMP.x - 0.1, PUMP.z - 0.1, 0.2, 0.2)]
	if state.get("together", false): result.append(Rect2(CAN.x - 0.22, CAN.z - 0.22, 0.44, 0.44))
	if state.get("hard", false):
		for side: int in [-1, 1]: result.append(Rect2(_vine(side).x - 0.18, _vine(side).z - 0.18, 0.36, 0.36))
	return result

func footprint() -> Rect2:
	return Rect2(-1.6, -0.95, 3.65, 2.1)

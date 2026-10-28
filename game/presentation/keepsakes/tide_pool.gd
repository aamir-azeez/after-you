extends "res://presentation/keepsakes/keepsake_builder.gd"
## The Turn of the Tide keepsake. Tap: the wheel turns, the pool fills and
## empties. Together: a mint rock pool with a toy boat, joined by a channel; the
## water runs over and the boat floats up. Hard: a post with three tide marks;
## the water rises past the top one and spills. Together Hard: a gold lantern
## on the wheel post that swings and lights at high tide.
## The water is one part that changes height, so filling costs nothing at rest.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const FLOOR_Y := 0.08
## The water's height above the floor at low tide, high tide and over the top.
const LOW := 0.06
const HIGH := 0.15
const SPILL := 0.2

func build(root: Node3D, state: Dictionary) -> Dictionary:
	var hard: bool = state.get("hard", false)
	if hard: P.footing(root, 0.96, 0.9)
	var body := P.body(root, state)
	P.cyl(body, 0.42, 0.08, P.STONE, Vector3(0, 0.04, 0), 0.43)
	for y: float in [0.11, 0.18]: P.ring(body, 0.4, 0.085, P.STONE, Vector3(0, y, 0))
	P.ring(body, 0.405, 0.05, P.CREAM, Vector3(0, 0.235, 0))
	P.box(body, Vector3(0.09, 0.92, 0.09), P.WOOD, Vector3(0, 0.46, -0.44))
	var water := P.pivot(body, Vector3(0, FLOOR_Y, 0), "Water")
	water.scale = Vector3(1, LOW, 1)
	P.cyl(water, 0.37, 1.0, P.TIDE, Vector3(0, 0.5, 0))
	var wheel := P.pivot(body, Vector3(0, 0.6, -0.38), "Wheel")
	P.ring(wheel, 0.22, 0.04, P.PEACH, Vector3.ZERO, Vector3(PI / 2, 0, 0))
	for i in range(4): P.box(wheel, Vector3(0.03, 0.42, 0.03), P.WOOD_LIGHT, Vector3.ZERO, Vector3(0, 0, i * PI / 4))
	P.sph(wheel, 0.05, P.CREAM, Vector3(0, 0, 0.02))
	for i in range(8):
		var a := i * TAU / 8.0
		P.box(wheel, Vector3(0.07, 0.03, 0.06), P.WOOD, Vector3(cos(a) * 0.24, sin(a) * 0.24, 0), Vector3(0, 0, a))
	var parts := {"water": water, "wheel": wheel}
	if state.get("together", false):
		var at := P.BESIDE + Vector3(0.04, 0, 0.04)
		P.cyl(root, 0.22, 0.1, P.STONE_LIGHT, at + Vector3(0, 0.05, 0), 0.23)
		P.ring(root, 0.225, 0.04, P.MINT, at + Vector3(0, 0.1, 0))
		P.cyl(root, 0.19, 0.02, P.WATER, at + Vector3(0, 0.075, 0))
		var boat := P.pivot(root, at + Vector3(0, 0.1, 0), "Boat")
		P.sph(boat, 0.07, P.MINT_DEEP, Vector3.ZERO, Vector3(1.35, 0.5, 0.7))
		P.cyl(boat, 0.006, 0.12, P.WOOD, Vector3(0, 0.07, 0))
		P.prism(boat, Vector3(0.07, 0.09, 0.01), P.SNOW, Vector3(0.03, 0.08, 0))
		var lip := Vector3(0.38, P.FOOT_HEIGHT if hard else 0.0, 0.12)
		P.bar(root, lip + Vector3(0, 0.23, 0), at + Vector3(-0.17, 0.11, 0), 0.07, P.STONE_LIGHT)
		parts.boat = boat
		parts.channel = [lip + Vector3(0, 0.3, 0), at + Vector3(-0.15, 0.13, 0)]
	if hard:
		P.box(root, Vector3(0.06, 0.52, 0.06), P.WOOD_LIGHT, Vector3(-0.4, P.FOOT_HEIGHT + 0.26, 0.3))
		for i in range(3): P.box(root, Vector3(0.11, 0.025, 0.025), P.PEACH if i == 2 else P.CREAM, Vector3(-0.4, P.FOOT_HEIGHT + 0.22 + i * 0.12, 0.33))
	if state.get("top", false):
		P.box(body, Vector3(0.16, 0.035, 0.16), P.GOLD_DEEP, Vector3(0, 0.935, -0.44))
		var lantern := P.pivot(body, Vector3(0, 0.95, -0.44), "Lantern")
		lantern.scale = Vector3.ONE * P.TOP_SCALE
		var light := P.box(lantern, Vector3(0.1, 0.11, 0.1), P.LAMP_OFF, Vector3(0, 0.06, 0))
		light.name = "LanternLight"
		P.node(lantern, P.Primitives.shared_mesh("box", 0.14, 0.03, 0.14), P.gold(), Vector3(0, 0.13, 0))
		P.node(lantern, P.low_sphere(0.03), P.gold(), Vector3(0, 0.17, 0))
		parts.lantern = lantern
		parts.lantern_light = light
	return parts

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var water: Node3D = parts.water
	var sounds: Dictionary = state.get("sounds", {})
	match beat:
		"base":
			anim.move(parts.wheel, "rotation:z", -TAU, 0.0, 2.1, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
			anim.move(water, "scale:y", HIGH, 0.0, 0.95)
			anim.move(water, "scale:y", LOW, 1.15, 0.95)
			anim.sound(str(sounds.get("base", "")), 0.0)
		"together":
			var path: Array = parts.channel
			for i in range(3):
				var drop: MeshInstance3D = anim.spawn(anim.fx, P.low_sphere(0.03), P.mat(P.TIDE), path[0])
				anim.set_at(drop, "visible", true, i * 0.1)
				anim.path(drop, anim.arc(path[0], path[1], 0.03), i * 0.1, 0.3)
				anim.set_at(drop, "visible", false, i * 0.1 + 0.31)
			var boat: Node3D = parts.boat
			anim.move(boat, "position:y", boat.position.y + 0.05, 0.25, 0.2)
			anim.move(boat, "position:y", boat.position.y, 0.5, 0.2)
			anim.sound(str(sounds.get("together", "")), 0.0)
		"hard":
			anim.move(water, "scale:y", SPILL, 0.0, 0.3)
			anim.move(water, "scale:y", LOW, 0.4, 0.3)
			for x: float in [-0.12, 0.08, 0.22]:
				var puddle: MeshInstance3D = anim.spawn(anim.fx, P.low_sphere(0.06), P.mat(P.TIDE), Vector3(x, P.FOOT_HEIGHT + 0.005, 0.42), Vector3.ZERO, Vector3(1.4, 0.3, 1.0))
				anim.set_at(puddle, "visible", true, 0.28)
				anim.set_at(puddle, "visible", false, 0.68)
			anim.sound(str(sounds.get("hard", "")), 0.2)
		"top":
			var lantern: Node3D = parts.lantern
			anim.set_at(parts.lantern_light, "material_override", P.glow(P.GOLD, 2.0), 0.0)
			anim.move(lantern, "rotation:z", 0.3, 0.0, 0.2)
			anim.move(lantern, "rotation:z", -0.2, 0.2, 0.2)
			anim.move(lantern, "rotation:z", 0.0, 0.4, 0.2)
			anim.set_at(parts.lantern_light, "material_override", P.mat(P.LAMP_OFF), 0.66)
			anim.sound(str(sounds.get("top", "")), 0.0)

func footing_size() -> Vector2:
	return Vector2(0.96, 0.9)

func footprint() -> Rect2:
	return Rect2(-0.48, -0.48, 1.53, 0.96)

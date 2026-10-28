extends "res://presentation/keepsakes/keepsake_builder.gd"
## The Sleeping Lighthouse keepsake. Tap: the lamp wakes, the beam sweeps once
## across the back of the island (never at the camera) and it dims back to
## sleep. Together: a mint boat on a pond beside it, whose lamp blinks back.
## Hard: a gallery rail and a bell; the beam goes round again, faster, and the
## bell rings. Together Hard: a gold weathervane on the roof swings to point at
## the boat as the lamp turns gold.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const LAMP_Y := 1.005

func build(root: Node3D, state: Dictionary) -> Dictionary:
	if state.get("hard", false): P.footing(root, 0.84, 0.74)
	var body := P.body(root, state)
	P.cyl(body, 0.3, 0.12, P.STONE, Vector3(0, 0.06, 0), 0.28)
	P.cyl(body, 0.2, 0.76, P.CREAM, Vector3(0, 0.5, 0), 0.15)
	P.cyl(body, 0.198, 0.08, P.CORAL, Vector3(0, 0.33, 0), 0.188)
	P.cyl(body, 0.178, 0.08, P.CORAL, Vector3(0, 0.62, 0), 0.168)
	P.box(body, Vector3(0.11, 0.17, 0.04), P.WOOD, Vector3(0, 0.2, 0.185))
	P.box(body, Vector3(0.07, 0.08, 0.03), P.LAMP_OFF, Vector3(0, 0.47, 0.18))
	P.cyl(body, 0.22, 0.04, P.WOOD, Vector3(0, 0.9, 0))
	var lamp := P.cyl(body, 0.12, 0.17, P.LAMP_OFF, Vector3(0, LAMP_Y, 0))
	lamp.name = "Lamp"
	P.cone(body, 0.17, 0.18, P.ROOF, Vector3(0, 1.18, 0))
	var parts := {"lamp": lamp}
	if state.get("together", false):
		var at := P.BESIDE
		P.cyl(root, 0.27, 0.02, P.WATER, at + Vector3(0, 0.012, 0))
		P.ring(root, 0.27, 0.04, P.STONE_LIGHT, at + Vector3(0, 0.02, 0))
		P.sph(root, 0.15, P.MINT, at + Vector3(0, 0.05, 0), Vector3(1.2, 0.42, 0.62))
		P.box(root, Vector3(0.2, 0.02, 0.1), P.MINT_DEEP, at + Vector3(0, 0.1, 0))
		P.cyl(root, 0.012, 0.26, P.WOOD, at + Vector3(0, 0.22, 0))
		var boat_lamp := P.sph(root, 0.04, P.LAMP_OFF, at + Vector3(0, 0.36, 0))
		boat_lamp.name = "BoatLamp"
		parts.boat_lamp = boat_lamp
	if state.get("hard", false):
		P.ring(body, 0.22, 0.02, P.WOOD_LIGHT, Vector3(0, 0.95, 0))
		for i in range(6):
			var a := i * TAU / 6.0
			P.box(body, Vector3(0.015, 0.06, 0.015), P.WOOD_LIGHT, Vector3(cos(a) * 0.22, 0.925, sin(a) * 0.22))
		var bell := P.pivot(body, Vector3(0.235, 0.86, 0.1), "Bell")
		P.sph(bell, 0.05, P.GOLD, Vector3(0, -0.05, 0), Vector3(1, 1.2, 1))
		parts.bell = bell
	if state.get("top", false):
		P.cyl(body, 0.01, 0.14, P.WOOD, Vector3(0, 1.32, 0))
		var vane := P.pivot(body, Vector3(0, 1.36, 0), "Vane")
		vane.scale = Vector3.ONE * P.TOP_SCALE
		P.node(vane, P.Primitives.shared_mesh("box", 0.22, 0.022, 0.022), P.gold(), Vector3.ZERO)
		P.node(vane, P.Primitives.shared_mesh("prism", 0.06, 0.06, 0.02), P.gold(), Vector3(0.11, 0, 0), Vector3(0, 0, -PI / 2))
		P.node(vane, P.low_sphere(0.045), P.gold(), Vector3(0, 0.06, 0))
		parts.vane = vane
	return parts

func base_time() -> float:
	return 2.2

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var up := Vector3(0, lift(state), 0)
	var lamp: MeshInstance3D = parts.lamp
	var sounds: Dictionary = state.get("sounds", {})
	match beat:
		"base":
			anim.set_at(lamp, "material_override", P.glow(P.LAMP, 1.8), 0.2)
			var beam := _beam(anim, up)
			beam.rotation.y = PI * 0.95
			anim.set_at(beam, "visible", true, 0.3)
			anim.move(beam, "rotation:y", -0.2, 0.3, 1.5)
			anim.set_at(beam, "visible", false, 1.85)
			anim.set_at(lamp, "material_override", P.glow(P.LAMP, 0.35), 1.85)
			anim.set_at(lamp, "material_override", P.mat(P.LAMP_OFF), 2.15)
			anim.sound(str(sounds.get("base", "")), 0.2)
		"together":
			var boat_lamp: MeshInstance3D = parts.boat_lamp
			for blink: float in [0.05, 0.4]:
				anim.set_at(boat_lamp, "material_override", P.glow(P.LAMP, 2.0), blink)
				anim.set_at(boat_lamp, "material_override", P.mat(P.LAMP_OFF), blink + 0.22)
			anim.sound(str(sounds.get("together", "")), 0.05)
		"hard":
			var bell: Node3D = parts.bell
			anim.set_at(lamp, "material_override", P.glow(P.LAMP, 1.8), 0.0)
			var beam := _beam(anim, up)
			anim.set_at(beam, "rotation:y", PI * 0.95, 0.0)
			anim.set_at(beam, "visible", true, 0.0)
			anim.move(beam, "rotation:y", -0.2, 0.0, 0.5, Tween.TRANS_LINEAR)
			anim.set_at(beam, "visible", false, 0.52)
			anim.set_at(lamp, "material_override", P.mat(P.LAMP_OFF), 0.55)
			anim.move(bell, "rotation:z", 0.55, 0.45, 0.1)
			anim.move(bell, "rotation:z", -0.3, 0.55, 0.1)
			anim.move(bell, "rotation:z", 0.0, 0.65, 0.05)
			anim.sound(str(sounds.get("hard", "")), 0.5)
		"top":
			var vane: Node3D = parts.vane
			anim.set_at(lamp, "material_override", P.glow(P.GOLD_DEEP, 1.8), 0.0)
			anim.move(vane, "rotation:y", -0.15, 0.0, 0.4, Tween.TRANS_BACK, Tween.EASE_OUT)
			brighten(anim, vane, 0.0)
			anim.set_at(lamp, "material_override", P.mat(P.LAMP_OFF), 0.65)
			anim.sound(str(sounds.get("top", "")), 0.0)

## The beam, made once per tap: a soft cone turning about the lamp.
func _beam(anim: RefCounted, up: Vector3) -> Node3D:
	if anim.made.has("beam"): return anim.made.beam
	var turn: Node3D = anim.spawn_pivot(anim.fx, up + Vector3(0, LAMP_Y, 0))
	var cone: MeshInstance3D = anim.spawn(turn, P.Primitives.shared_mesh("cone", 0.19, 0.95), P.clear(Color("fff3b8"), 0.5, 1.2), Vector3(0.58, 0, 0), Vector3(0, 0, PI / 2))
	cone.visible = true
	anim.made.beam = turn
	return turn

func footing_size() -> Vector2:
	return Vector2(0.84, 0.74)

func footprint() -> Rect2:
	return Rect2(-0.42, -0.37, 1.45, 0.74)

extends "res://presentation/keepsakes/keepsake_builder.gd"
## The Sleeping Lighthouse keepsake: a tall lighthouse on a jetty that runs out
## past the island's edge. Walking out to the end of the jetty (or a tap) wakes
## the lamp, and its beam sweeps across every Home island before it settles
## back to sleep. Together: a mint boat on its own pond whose lamp blinks back
## as the beam passes. Hard: a gallery rail and a bell on a slate plinth, and a
## second, faster sweep. Together Hard: a gold weathervane on the roof, and the
## last sweep turns gold.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const HARD_LIFT := 0.32
const POND := Vector3(1.25, 0, 0.95)
const BEAM := Color("fff3b8")
const BEAM_GOLD := Color("ffc93c")
const JETTY_END := -2.45
const JETTY_HALF := 0.31

static func _y0(state: Dictionary) -> float:
	return HARD_LIFT if state.get("hard", false) else 0.0

func build(root: Node3D, state: Dictionary) -> Dictionary:
	var hard: bool = state.get("hard", false)
	var y0 := _y0(state)
	if hard: P.plinth(root, 1.25, 1.25)
	P.cyl(root, 0.62, 0.22, P.STONE, Vector3(0, y0 + 0.11, 0), 0.58)
	P.cyl(root, 0.42, 1.9, P.CREAM, Vector3(0, y0 + 1.17, 0), 0.31)
	for index in range(3): P.cyl(root, 0.41 - index * 0.04, 0.17, P.CORAL, Vector3(0, y0 + 0.62 + index * 0.55, 0), 0.39 - index * 0.04)
	P.box(root, Vector3(0.22, 0.38, 0.06), P.WOOD, Vector3(0, y0 + 0.4, 0.4))
	P.cyl(root, 0.44, 0.08, P.WOOD, Vector3(0, y0 + 2.15, 0))
	var lamp := P.cyl(root, 0.24, 0.34, P.LAMP_OFF, Vector3(0, y0 + 2.36, 0))
	lamp.name = "Lamp"
	P.cone(root, 0.35, 0.38, P.ROOF, Vector3(0, y0 + 2.72, 0))
	# The jetty runs out past the island's edge; its last plank wakes the lamp.
	for index in range(7): P.box(root, Vector3(0.24, 0.06, 0.62), P.PLANK, Vector3(-0.72 - index * 0.27, 0.03, 0))
	for side: int in [-1, 1]:
		P.cyl(root, 0.05, 0.6, P.POST, Vector3(-2.3, -0.05, side * 0.34))
		P.cyl(root, 0.05, 0.6, P.POST, Vector3(-1.2, -0.05, side * 0.34))
	var parts := {"lamp": lamp}
	if state.get("together", false):
		var at := POND
		P.cyl(root, 0.52, 0.03, P.WATER, at + Vector3(0, 0.015, 0))
		P.ring(root, 0.52, 0.07, P.STONE_LIGHT, at + Vector3(0, 0.03, 0))
		P.sph(root, 0.28, P.MINT, at + Vector3(0, 0.08, 0), Vector3(0.9, 0.42, 0.9))
		P.box(root, Vector3(0.4, 0.03, 0.18), P.MINT_DEEP, at + Vector3(0, 0.18, 0))
		P.cyl(root, 0.02, 0.48, P.WOOD, at + Vector3(0, 0.42, 0))
		var boat_lamp := P.sph(root, 0.07, P.LAMP_OFF, at + Vector3(0, 0.68, 0))
		boat_lamp.name = "BoatLamp"
		parts.boat_lamp = boat_lamp
	if hard:
		P.ring(root, 0.47, 0.035, P.WOOD_LIGHT, Vector3(0, y0 + 2.24, 0))
		for index in range(8):
			var angle := index * TAU / 8.0
			P.box(root, Vector3(0.025, 0.12, 0.025), P.WOOD_LIGHT, Vector3(cos(angle) * 0.47, y0 + 2.2, sin(angle) * 0.47))
		var bell := P.pivot(root, Vector3(0.5, y0 + 2.05, 0.2), "Bell")
		P.sph(bell, 0.1, P.GOLD, Vector3(0, -0.1, 0), Vector3(1, 1.2, 1))
		parts.bell = bell
	if state.get("top", false):
		P.cyl(root, 0.02, 0.28, P.WOOD, Vector3(0, y0 + 3.0, 0))
		var vane := P.pivot(root, Vector3(0, y0 + 3.05, 0), "Weathervane")
		vane.rotation.y = 0.6
		P.node(vane, P.Primitives.shared_mesh("box", 0.46, 0.04, 0.04), P.gold(), Vector3.ZERO)
		P.gold_ball(vane, Vector3(0, 0.15, 0), 0.09)
		parts.vane = vane
	return parts

func base_time() -> float:
	return 2.3

func upgrade_time(beat: String) -> float:
	return 0.65 if beat == "hard" else 0.55

## The beam: a pivot at the lamp turning a long see-through cone, made for the
## first beat and reused by the later sweeps.
func _beam(anim: RefCounted, state: Dictionary) -> Node3D:
	if anim.made.has("beam"): return anim.made.beam
	var turn: Node3D = anim.spawn_pivot(anim.fx, Vector3(0, _y0(state) + 2.36, 0))
	var cone: MeshInstance3D = anim.spawn(turn, P.Primitives.shared_mesh("cone", 0.5, 4.2), P.clear(BEAM, 0.42, 1.2), Vector3(2.3, 0, 0), Vector3(0, 0, PI / 2))
	anim.made.beam = turn
	anim.made.cone = cone
	return turn

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var sounds: Dictionary = state.get("sounds", {})
	var lamp: MeshInstance3D = parts.lamp
	match beat:
		"base":
			# The lamp wakes and the beam sweeps once round every island, then sleeps.
			anim.set_at(lamp, "material_override", P.glow(P.LAMP, 2.0), 0.0)
			anim.halo(anim.fx, Vector3(0, _y0(state) + 2.36, 0), 0.42, P.LAMP, 0.0, 2.3)
			var turn := _beam(anim, state)
			anim.set_at(turn, "visible", true, 0.15)
			anim.set_at(anim.made.cone, "visible", true, 0.15)
			anim.move(turn, "rotation:y", TAU, 0.15, 2.1, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
			anim.sound(str(sounds.get("base", "")), 0.0)
		"together":
			# The boat's lamp blinks back as the beam passes.
			var boat_lamp: MeshInstance3D = parts.boat_lamp
			for at: float in [0.0, 0.28]:
				anim.set_at(boat_lamp, "material_override", P.glow(P.LAMP, 2.0), at)
				anim.set_at(boat_lamp, "material_override", P.mat(P.LAMP_OFF), at + 0.15)
			anim.halo(anim.fx, POND + Vector3(0, 0.68, 0), 0.2, P.LAMP, 0.0, 0.43)
			anim.sound(str(sounds.get("together", "")), 0.0)
		"hard":
			# A second, faster sweep, and the gallery bell rings.
			var turn := _beam(anim, state)
			anim.move(turn, "rotation:y", TAU * 2.0, 0.0, 0.6, Tween.TRANS_LINEAR)
			var bell: Node3D = parts.bell
			anim.move(bell, "rotation:z", 0.5, 0.0, 0.12)
			anim.move(bell, "rotation:z", -0.35, 0.12, 0.18)
			anim.move(bell, "rotation:z", 0.0, 0.3, 0.2)
			anim.sound(str(sounds.get("hard", "")), 0.0)
		"top":
			# The last sweep turns gold and the weathervane spins.
			var turn := _beam(anim, state)
			anim.set_at(anim.made.cone, "material_override", P.clear(BEAM_GOLD, 0.42, 1.2), 0.0)
			anim.move(turn, "rotation:y", TAU * 3.0, 0.0, 0.5, Tween.TRANS_SINE, Tween.EASE_OUT)
			anim.move(parts.vane, "rotation:y", 0.6 + TAU, 0.0, 0.5, Tween.TRANS_SINE, Tween.EASE_OUT)
			brighten(anim, parts.vane, 0.0)
			anim.sound(str(sounds.get("top", "")), 0.0)

## Walking out to the end of the jetty.
func trigger() -> Dictionary:
	return {"area": Rect2(JETTY_END, -JETTY_HALF, 0.5, JETTY_HALF * 2.0)}

func walkways() -> Array[Rect2]:
	return [Rect2(JETTY_END, -JETTY_HALF, -0.55 - JETTY_END, JETTY_HALF * 2.0)]

func solids(state: Dictionary) -> Array[Rect2]:
	var half := 0.63
	var result: Array[Rect2] = [Rect2(-half, -half, half * 2.0, half * 2.0)]
	if state.get("together", false): result.append(Rect2(POND.x - 0.56, POND.z - 0.56, 1.12, 1.12))
	return result

func footprint() -> Rect2:
	return Rect2(JETTY_END, -0.65, 1.85 - JETTY_END, 2.2)

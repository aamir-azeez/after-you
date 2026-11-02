extends "res://presentation/keepsakes/keepsake_builder.gd"
## The Sleeping Lighthouse keepsake: a tall lighthouse on a jetty that runs out
## past the island's edge. Walking out to the end of the jetty (or a tap) wakes
## the lamp: its beam reaches out and starts a slow turn across every Home
## island, and stays on, turning, until it is pressed again, when the beam
## fades back into the lamp and it sleeps. Together: a mint boat on its own
## pond whose lamp blinks back each time the beam passes. Hard: a gallery rail
## and a bell on a slate plinth, and a second, faster sweep that eases back
## into the slow turn. Together Hard: a gold weathervane on the roof, and the
## beam turns gold.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
## One full turn of the beam, in seconds, once it is on.
const SWEEP := 10.0
## Pressing it again while it is on: SWITCH fades it off (a lamp switched off);
## REPLAY would put it out and wake it again from the start.
const PRESS_AGAIN := SWITCH
const OFF_TIME := 0.8
## The beam's look, see-through, and the steps it fades through going off.
const BEAM_ALPHA := 0.42
const FADES := [0.28, 0.14]
## A beam reaching out of the lamp starts this thin and short.
const REACH_FROM := Vector3(0.02, 0.3, 0.3)
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

func press_again() -> String:
	return PRESS_AGAIN

func off_time() -> float:
	return OFF_TIME

## The beam: a pivot at the lamp that turns slowly ("turn", kept turning while
## the lamp is on), an arm on it that reaches the beam out of the lamp and on
## Hard sweeps it once round faster ("arm"), and the long see-through cone
## ("cone"). Made in the first beat, kept while the lamp is on.
func _beam(anim: RefCounted, state: Dictionary) -> Dictionary:
	if anim.made.has("beam"): return anim.made.beam
	var turn: Node3D = anim.spawn_pivot(anim.fx, Vector3(0, _y0(state) + 2.36, 0))
	var arm: Node3D = anim.spawn_pivot(turn, Vector3.ZERO)
	arm.scale = REACH_FROM
	var cone: MeshInstance3D = anim.spawn(arm, P.Primitives.shared_mesh("cone", 0.5, 4.2), P.clear(BEAM, BEAM_ALPHA, 1.2), Vector3(2.3, 0, 0), Vector3(0, 0, PI / 2))
	anim.made.beam = {"turn": turn, "arm": arm, "cone": cone}
	return anim.made.beam

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var sounds: Dictionary = state.get("sounds", {})
	var lamp: MeshInstance3D = parts.lamp
	match beat:
		"base":
			# The lamp wakes, the beam reaches out and starts a slow turn round
			# every island, gathering speed until it turns once every SWEEP
			# seconds as the tap ends; from there the layer keeps it turning.
			anim.set_at(lamp, "material_override", P.glow(P.LAMP, 2.0), 0.0)
			anim.keep(lamp)
			anim.halo(anim.fx, Vector3(0, _y0(state) + 2.36, 0), 0.42, P.LAMP, 0.0, 2.3)
			var beam := _beam(anim, state)
			var turn: Node3D = beam.turn
			anim.set_at(turn, "visible", true, 0.15)
			anim.set_at(beam.arm, "visible", true, 0.15)
			anim.set_at(beam.cone, "visible", true, 0.15)
			anim.move(beam.arm, "scale", Vector3.ONE, 0.15, 0.9, Tween.TRANS_SINE, Tween.EASE_OUT)
			anim.keep(beam.arm)
			anim.keep(beam.cone)
			var total := 0.0
			for each: Dictionary in beats(state): total += float(each.time)
			# An ease in from still ends at PI / 2 times its mean speed: at SWEEP's.
			var rate := TAU / SWEEP
			var reach := total - 0.15
			anim.move(turn, "rotation:y", rate * reach * 2.0 / PI, 0.15, reach, Tween.TRANS_SINE, Tween.EASE_IN)
			var answers: Array = []
			if parts.has("boat_lamp"): answers.append([parts.boat_lamp, atan2(-POND.z, POND.x), P.glow(P.LAMP, 2.0), P.mat(P.LAMP_OFF)])
			anim.spin(turn, rate, answers)
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
			# A second, faster sweep: the beam goes once round on top of its slow
			# turn and eases back into it (a whole turn, so it ends where it would
			# have been), and the gallery bell rings.
			anim.move(_beam(anim, state).arm, "rotation:y", TAU, 0.0, 0.6, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
			var bell: Node3D = parts.bell
			anim.move(bell, "rotation:z", 0.5, 0.0, 0.12)
			anim.move(bell, "rotation:z", -0.35, 0.12, 0.18)
			anim.move(bell, "rotation:z", 0.0, 0.3, 0.2)
			anim.sound(str(sounds.get("hard", "")), 0.0)
		"top":
			# The beam turns gold and the weathervane spins.
			anim.set_at(_beam(anim, state).cone, "material_override", P.clear(BEAM_GOLD, BEAM_ALPHA, 1.2), 0.0)
			anim.move(parts.vane, "rotation:y", 0.6 + TAU, 0.0, 0.5, Tween.TRANS_SINE, Tween.EASE_OUT)
			brighten(anim, parts.vane, 0.0)
			anim.sound(str(sounds.get("top", "")), 0.0)
		"off":
			# Pressed again while on: the beam fades back into the lamp as it
			# turns, the lamp dims, and the layer puts it all back to sleep.
			var beam := _beam(anim, state)
			var color := BEAM_GOLD if state.get("top", false) else BEAM
			anim.move(beam.arm, "scale", REACH_FROM, 0.0, OFF_TIME - 0.05, Tween.TRANS_SINE, Tween.EASE_IN)
			for step in range(FADES.size()): anim.set_at(beam.cone, "material_override", P.clear(color, float(FADES[step]), 1.2), 0.2 + step * 0.25)
			anim.set_at(lamp, "material_override", P.glow(P.LAMP, 1.0), 0.3)

## Walking out to the end of the jetty.
func trigger() -> Dictionary:
	return {"area": Rect2(JETTY_END, -JETTY_HALF, 0.5, JETTY_HALF * 2.0)}

func walkways() -> Array[Rect2]:
	return [Rect2(JETTY_END, -JETTY_HALF, -0.55 - JETTY_END, JETTY_HALF * 2.0)]

## The round stone foot, or Hard's square plinth, and the mint boat's pond.
func solids(state: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = round_solid(Vector2.ZERO, 0.62)
	if state.get("hard", false): result = [Rect2(-0.63, -0.63, 1.26, 1.26)]
	if state.get("together", false): result.append_array(round_solid(Vector2(POND.x, POND.z), 0.56))
	return result

func footprint() -> Rect2:
	return Rect2(JETTY_END, -0.65, 1.85 - JETTY_END, 2.2)

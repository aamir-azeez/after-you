extends RefCounted
## Authored control routes, not a state injection or a general puzzle solver.
const Simulation = preload("res://core/cooperative/simulation.gd")
const Catalog = preload("res://core/cooperative/stage_catalog.gd")
const Solid = preload("res://core/solid_footprint.gd")

static func chapter(key: String) -> Dictionary:
	var level := Catalog.definition(key)
	var checkpoint := Catalog.initial_checkpoint(level)
	var result := {"definition": level, "checkpoints": [checkpoint], "pairs": [], "error": ""}
	for stage: Dictionary in level.stages:
		var a := source(level, stage.id, checkpoint)
		if not a.error.is_empty() or not a.can_commit():
			result.error = "Source route failed: " + stage.id + ": " + a.error + " " + a.commit_reason()
			return result
		var first: Dictionary = a.export_recording()
		var b := receiver(level, stage.id, checkpoint, first)
		if not b.error.is_empty() or not b.complete or not b.can_commit():
			result.error = "Receiver route failed: " + stage.id + ": " + b.error + " " + b.commit_reason()
			return result
		var second: Dictionary = b.export_recording()
		var derived := Simulation.derive_checkpoint(level, checkpoint, first, second)
		if not derived.valid:
			result.error = "Checkpoint failed: " + stage.id + ": " + str(derived.get("error", ""))
			return result
		result.pairs.append({"a": first, "b": second})
		checkpoint = derived.checkpoint
		result.checkpoints.append(checkpoint)
	return result

static func source(level: Dictionary, stage_id: String, checkpoint: Dictionary) -> RefCounted:
	var sim := Simulation.new()
	if not sim.reset(level, stage_id, checkpoint): return sim
	match stage_id:
		"upper-path":
			walk(sim, [-544, 112]); tap(sim)
			walk(sim, [-448, -128])
			wait_ticks(sim, 15)
		"down-and-around":
			walk(sim, [240, -128]); tap(sim)
			walk(sim, [240, 48]); walk(sim, [448, 48]); wait_ticks(sim, 15)
		"weight-of-a-friend":
			walk(sim, [-336, 0]); walk(sim, [-336, -48]); walk(sim, [-304, -48]); walk(sim, [-304, 64]); wait_ticks(sim, 15)
		"bring-it-home":
			tap(sim)
			walk(sim, [896, 128]); walk(sim, [608, 128]); walk(sim, [608, 0])
			walk(sim, [-352, 0]); walk(sim, [-352, 128]); walk(sim, [-304, 128]); walk(sim, [-304, 32])
			walk(sim, [-352, 32]); walk(sim, [-352, 0]); walk(sim, [208, 0]); tap(sim)
	return sim

static func receiver(level: Dictionary, stage_id: String, checkpoint: Dictionary, first: Dictionary) -> RefCounted:
	var sim := Simulation.new()
	if not sim.reset(level, stage_id, checkpoint, first, "b"): return sim
	match stage_id:
		"upper-path":
			walk(sim, [160, 0]); walk(sim, [160, -128]); tap(sim)
		"down-and-around":
			walk(sim, [-448, 144]); walk(sim, [448, 144]); walk(sim, [448, 0]); walk(sim, [912, 0]); tap(sim)
		"weight-of-a-friend":
			walk(sim, [-400, -80]); walk(sim, [-256, -80]); walk(sim, [-256, 0])
			walk(sim, [192, 0]); walk(sim, [192, 112]); tap(sim); walk(sim, [192, 0])
			walk(sim, [608, 0]); walk(sim, [608, 128]); walk(sim, [896, 128]); walk(sim, [896, 96]); tap(sim)
		"bring-it-home":
			walk(sim, [-352, 64]); walk(sim, [-352, 0]); walk(sim, [208, 0])
			for _tick in range(Simulation.MAX_TICKS):
				if sim.finished or sim.snapshot().props["round-ball"].status == "offered": break
				sim.step({})
			tap(sim)
			walk(sim, [208, 128]); walk(sim, [240, 128]); tap(sim); walk(sim, [208, 128]); walk(sim, [208, 0])
			walk(sim, [576, 0]); walk(sim, [576, 48]); walk(sim, [608, 48]); walk(sim, [608, -96])
			walk(sim, [576, -96]); walk(sim, [576, -128]); walk(sim, [832, -128])
			walk(sim, [832, -176]); walk(sim, [864, -176]); walk(sim, [864, -32])
			walk(sim, [832, -32]); walk(sim, [832, 0]); walk(sim, [1344, 0])
	return sim

## Walks along x, then z. A walk aimed into a solid hand control (levers,
## switches, selectors, mirrors: core/solid_footprint.gd) ends at its edge on
## the side the pip comes from, where it works it; a leg that runs into one
## stops there rather than pushing at it.
static func walk(sim: RefCounted, destination: Array) -> void:
	var hands := hands_of(sim)
	destination = beside(hands, sim.snapshot().players[sim.active_slot], destination)
	for axis: String in ["x", "z"]:
		var index := 0 if axis == "x" else 1
		for _tick in range(Simulation.MAX_TICKS):
			if sim.finished or not sim.error.is_empty(): return
			var player: Dictionary = sim.snapshot().players[sim.active_slot]
			var distance := int(destination[index]) - int(player[axis])
			if absi(distance) <= 1: break
			var input := {"move_x": 0.0, "move_z": 0.0}
			input["move_" + axis] = clampf(float(distance) / 8.0, -1.0, 1.0)
			sim.step(input)
			var now: Dictionary = sim.snapshot().players[sim.active_slot]
			if int(now.x) == int(player.x) and int(now.z) == int(player.z) and against(hands, now, axis, signi(distance)):
				if not sidestep(sim, hands, axis, signi(distance)): break

## The solid hand controls of `sim`'s stage ([] for an engine without stages).
static func hands_of(sim: RefCounted) -> Array:
	var stage: Variant = sim.get("stage")
	return Solid.solids(stage.get("levers", []) + stage.get("controls", [])) if stage is Dictionary else []

## `destination` moved out of any of `hands`' kept-out circles, to its edge
## on the side `player` stands.
static func beside(hands: Array, player: Dictionary, destination: Array) -> Array:
	var at := Vector2(float(destination[0]), float(destination[1]))
	for hand: Dictionary in hands:
		var centre := Vector2(float(hand.position_cm[0]), float(hand.position_cm[1]))
		var keep := float(int(Solid.of(hand).radius_cm) + Solid.BODY_CM + 2)
		if at.distance_to(centre) >= keep: continue
		var away := Vector2(float(player.x), float(player.z)) - centre
		at = centre + (away.normalized() if away.length() >= 1.0 else Vector2.RIGHT) * keep
	return [roundi(at.x), roundi(at.y)]

## Steps across `axis`, away from the hand in the way, until a step along it
## the way of `sign` is clear (either side, the way off the hand first).
## Whether it cleared.
static func sidestep(sim: RefCounted, hands: Array, axis: String, sign: int) -> bool:
	var other := "z" if axis == "x" else "x"
	var start: Dictionary = sim.snapshot().players[sim.active_slot]
	var away := 1
	for hand: Dictionary in hands:
		var at := Vector2i(int(start.x), int(start.z))
		if Solid.blocked([hand], at + (Vector2i(sign * 8, 0) if axis == "x" else Vector2i(0, sign * 8)), Solid.BODY_CM):
			var centre := int(hand.position_cm[1 if other == "z" else 0])
			away = 1 if int(start[other]) >= centre else -1
	for side: int in [away, -away]:
		for _tick in range(16):
			var player: Dictionary = sim.snapshot().players[sim.active_slot]
			if not against(hands, player, axis, sign): return true
			var input := {"move_x": 0.0, "move_z": 0.0}
			input["move_" + other] = float(side)
			sim.step(input)
			var now: Dictionary = sim.snapshot().players[sim.active_slot]
			if int(now.x) == int(player.x) and int(now.z) == int(player.z): break
		if not against(hands, sim.snapshot().players[sim.active_slot], axis, sign): return true
	return false

## Whether a step along `axis` the way of `sign` would enter a hand's footprint.
static func against(hands: Array, player: Dictionary, axis: String, sign: int) -> bool:
	var next := Vector2i(int(player.x), int(player.z)) + (Vector2i(sign * 8, 0) if axis == "x" else Vector2i(0, sign * 8))
	return hands.any(func(hand: Dictionary) -> bool: return str(hand.get("surface_id", "")) == str(player.surface_id) and Solid.blocked([hand], next, Solid.BODY_CM))

static func tap(sim: RefCounted) -> void:
	if sim.finished: return
	sim.step({})
	sim.step({"interact": true})

static func wait_ticks(sim: RefCounted, count: int) -> void:
	for _tick in range(count):
		if sim.finished: return
		sim.step({})

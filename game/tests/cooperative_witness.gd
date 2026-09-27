extends RefCounted
## Authored control routes, not a state injection or a general puzzle solver.
const Simulation = preload("res://core/cooperative/simulation.gd")
const Catalog = preload("res://core/cooperative/stage_catalog.gd")

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

static func walk(sim: RefCounted, destination: Array) -> void:
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

static func tap(sim: RefCounted) -> void:
	if sim.finished: return
	sim.step({})
	sim.step({"interact": true})

static func wait_ticks(sim: RefCounted, count: int) -> void:
	for _tick in range(count):
		if sim.finished: return
		sim.step({})

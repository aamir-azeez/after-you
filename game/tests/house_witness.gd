extends RefCounted
## Proposed House routes use only actual control inputs. No state injection.
const Simulation = preload("res://core/cooperative/simulation.gd")
const Catalog = preload("res://core/cooperative/stage_catalog.gd")
const House = preload("res://core/cooperative/house_catalog.gd")
const Walk = preload("res://tests/cooperative_witness.gd")

static func chapter() -> Dictionary:
	var level := House.definition()
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

static func source(level: Dictionary, stage_id: String, checkpoint: Dictionary, weight_offset_z: int = 0, offer_offset_x: int = 0) -> RefCounted:
	var sim := Simulation.new()
	if not sim.reset(level, stage_id, checkpoint): return sim
	if stage_id == "open-the-house":
		_route(sim, [[-480,112],[-320,112],[-320,176],[-224,176],[-224,112],[32,112],[32,144]])
		Walk.tap(sim)
		_route(sim, [[32,112],[-256,112],[-320,112],[-320,160],[-352,160],[-352,144],[-352,-80 + weight_offset_z]])
		Walk.wait_ticks(sim, 15)
	elif stage_id == "the-room-below":
		_route(sim, [[560,-128],[560,80]])
		Walk.tap(sim)
		var ball: Dictionary = sim.snapshot().props["house-ball"]
		_route(sim, [[496,80],[496,0],[128,0],[128,-112],[-256,-112],[-256,-192],[-400,-192],[-400,ball.z],[ball.x - 32,ball.z],[112,ball.z]])
		# The source now owns the bench turn before passing responsibility on.
		_route(sim, [[112,-160],[144,-160],[144,ball.z - 32],[144,-32],[112,-32],[112,0],[432 + offer_offset_x,0]])
		Walk.tap(sim)
		Walk.walk(sim, [432 + offer_offset_x,64])
	return sim

static func receiver(level: Dictionary, stage_id: String, checkpoint: Dictionary, first: Dictionary, first_goal: Array = [576,-128]) -> RefCounted:
	var sim := Simulation.new()
	if not sim.reset(level, stage_id, checkpoint, first, "b"): return sim
	if stage_id == "open-the-house":
		_route(sim, [[-528,-192],[-240,-192],[-240,-112],[128,-112],[576,-112],first_goal])
		Walk.tap(sim)
	elif stage_id == "the-room-below":
		_route(sim, [[-240,-80],[-240,-112],[128,-112],[128,0],[416,0]])
		for _tick in range(Simulation.MAX_TICKS):
			if sim.finished or sim.snapshot().props["house-ball"].status == "offered": break
			sim.step({})
		Walk.tap(sim)
		_route(sim, [[560,0],[560,96],[656,96],[656,0],[960,0],[960,112]])
		Walk.tap(sim)
	return sim

static func _route(sim: RefCounted, points: Array) -> void:
	for destination: Array in points:
		Walk.walk(sim, destination)

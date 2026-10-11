extends RefCounted
## The Wishing Well routes use only actual control inputs. No state injection.
const Simulation = preload("res://core/cooperative/simulation.gd")
const Catalog = preload("res://core/cooperative/stage_catalog.gd")
const Well = preload("res://core/cooperative/wishing_well_catalog.gd")
const Walk = preload("res://tests/cooperative_witness.gd")

static func chapter() -> Dictionary:
	var level := Well.definition()
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

## The friend who goes ahead: gate, cliff steps, a cliff path past the standing
## stones, then the well. `landing_x` picks where on the mouth they step in.
static func source(level: Dictionary, stage_id: String, checkpoint: Dictionary, landing_x: int = 1160) -> RefCounted:
	var sim := Simulation.new()
	if not sim.reset(level, stage_id, checkpoint): return sim
	if stage_id == "go-on-ahead":
		_route(sim, [[-1104,200]])
		Walk.tap(sim)
		_route(sim, CLIFF_PATH)
		_route(sim, [[landing_x,-64],[landing_x,-30]])
		Walk.wait_ticks(sim, 15)
	elif stage_id == "back-for-you":
		_route(sim, TOWER_OUT)
		Walk.tap(sim)
		_route(sim, TOWER_BACK)
		Walk.wait_ticks(sim, 15)
	return sim

## Out past both rope drums to the winch, and back to the step by the bell.
const TOWER_OUT := [[1160,-144],[1888,-144],[1888,-40],[2200,-40],[2200,-144],[2752,-144]]
const TOWER_BACK := [[2200,-144],[2200,-40],[1648,-40],[1648,-48]]
const CLIFF_PATH := [[-1216,200],[-1216,-64],[-480,-64],[-480,-160],[-96,-160],[-96,-64],[288,-64],[288,-160],[416,-160],[416,-64]]

static func receiver(level: Dictionary, stage_id: String, checkpoint: Dictionary, first: Dictionary) -> RefCounted:
	var sim := Simulation.new()
	if not sim.reset(level, stage_id, checkpoint, first, "b"): return sim
	if stage_id == "go-on-ahead":
		_route(sim, GARDEN_PATH)
		wait_for_route(sim, "long-stair")
		_route(sim, [[976,-96],[1160,-96]])
		Walk.tap(sim)
	elif stage_id == "back-for-you":
		wait_for_route(sim, "well-ladder")
		_route(sim, [[1180,16],[1592,16]])
		Walk.tap(sim)
	wait_for_completion(sim)
	return sim

const GARDEN_PATH := [[-1168,180],[-608,180],[-608,256],[-224,256],[-224,180],[160,180],[160,256],[544,256],[544,180],[976,180],[976,168]]

## Bounded: stands still until the route opens or the turn ends.
static func wait_for_route(sim: RefCounted, route: String) -> void:
	for _tick in range(Simulation.MAX_TICKS + 300):
		if sim.finished or bool(sim.snapshot().bridges.get(route, false)): return
		sim.step({})

static func wait_for_completion(sim: RefCounted) -> void:
	for _tick in range(Simulation.MAX_TICKS + 300):
		if sim.finished: return
		sim.step({})

static func _route(sim: RefCounted, points: Array) -> void:
	for destination: Array in points:
		Walk.walk(sim, destination)

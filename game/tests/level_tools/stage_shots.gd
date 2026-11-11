extends RefCounted
## The states the level tools show a stage in, as snapshots a world presents:
## the engine's own opening snapshot, then a pip moved beside a control, a
## lever pulled, a pad held or a selector turned, with every gate worked out
## again by the engine's own rule (tests/level_graph.gd gate_holds). Shared by
## the preview (tests/level_tools/preview_capture.gd) and the view checks
## (tests/test_level_view.gd), so both look at the same moments. Presentation
## only: a snapshot made here never reaches an engine, a save or a server.
const Registry = preload("res://services/chapter_registry.gd")
const LevelGraph = preload("res://tests/level_graph.gd")
## How far beside a control a pip stands (cm): near enough to show its pair
## (PairTags.NEAR_CM is 120), clear of the control itself.
const BESIDE := [[-45, 35], [45, 35], [0, 50], [-50, 0], [50, 0], [0, -50]]
## Floors keep a walker this far inside their edges (cm).
const INSET := 14

## The engine's snapshot of the stage opening for role a, a few ticks in (so
## a world's first-tick rules have run). The engine opens it trusted (no
## proof of the checkpoint), as the level tools also show layouts no catalog
## knows yet: presentation only. {} when the engine has no such stage.
static func opening(key: String, level: Dictionary, stage_id: String, checkpoint: Dictionary) -> Dictionary:
	var sim: RefCounted = Registry.simulation_script(key).new()
	var rules := Registry.preferred_rules(key)
	sim.simulation_version = rules if rules > 0 else int(level.get("simulation_version", 0))
	sim._reset_trusted(level, stage_id, checkpoint, {}, "a")
	if sim.stage.is_empty() or not str(sim.error).is_empty(): return {}
	for _tick in range(4): sim.step({})
	return sim.snapshot()

## Every spot worth a look on a stage, in stage order: {id, kind (selector,
## lever, pad or goal), entity, slot (the pip that works it)}.
static func spots(view: Dictionary) -> Array:
	var result: Array = []
	for kind: Array in [["controls", "selector"], ["levers", "lever"], ["pressure_pads", "pad"]]:
		for entity: Dictionary in view.get(kind[0], []):
			result.append({"id": str(entity.id), "kind": kind[1], "entity": entity, "slot": str(entity.get("owner_slot", ""))})
	var goal: Dictionary = view.get("goal", {})
	if not goal.is_empty(): result.append({"id": str(goal.id), "kind": "goal", "entity": goal, "slot": str(goal.get("owner_slot", ""))})
	return result

## `state` with `slot` the live pip, standing on `entity`'s floor beside it
## (or on it, for `on`).
static func beside(state: Dictionary, view: Dictionary, journey: bool, entity: Dictionary, slot: String, on: bool = false) -> Dictionary:
	var result := state.duplicate(true)
	if slot.is_empty() or not result.get("players", {}).has(slot): slot = str(result.get("active_slot", "p0"))
	result.active_slot = slot
	var at := Vector2i(int(entity.position_cm[0]), int(entity.position_cm[1]))
	var surface := str(entity.get("surface_id", ""))
	var spot := at
	if not on:
		var rect := _surface_rect(view, surface)
		for offset: Array in BESIDE:
			var candidate := at + Vector2i(int(offset[0]), int(offset[1]))
			if rect.is_empty() or _inside(candidate, rect):
				spot = candidate
				break
	result.players[slot].x = spot.x
	result.players[slot].z = spot.y
	result.players[slot].height = int(entity.get("height_cm", _surface_height(view, surface)))
	result.players[slot].surface_id = surface
	return refresh_gates(result, view, journey)

## `state` with the spot's control worked: a lever on, a pad held (its pip on
## it), a selector at `value`. Gates follow.
static func worked(state: Dictionary, view: Dictionary, journey: bool, spot: Dictionary, value: String = "") -> Dictionary:
	var result := state.duplicate(true)
	match str(spot.kind):
		"lever":
			if not result.has("levers"): result["levers"] = {}
			result.levers[spot.id] = true
			if result.has("mechanisms"): result.mechanisms.get("levers", {})[spot.id] = true
		"pad":
			result = beside(result, view, journey, spot.entity, spot.slot, true)
		"selector":
			if not result.has("controls"): result["controls"] = {}
			result.controls[spot.id] = value
	return refresh_gates(result, view, journey)

## Every gate of the stage worked out again for `state` by the family's rule
## (`journey` or cooperative; a crossing kept open from earlier stays open),
## and every pad's held light.
static func refresh_gates(state: Dictionary, view: Dictionary, journey: bool) -> Dictionary:
	var mechanisms := {"controls": state.get("controls", {}), "levers": state.get("levers", {})}
	var bridges: Dictionary = {}
	for id: Variant in state.get("route_progress", {}).get("kept_bridges", []): bridges[str(id)] = true
	for id: Variant in state.get("route_progress", {}).get("entered_routes", []): bridges[str(id)] = true
	for gate: Dictionary in view.get("gates", []):
		var route := str(gate.get("route_id", ""))
		if LevelGraph.gate_holds(gate, view, state.players, mechanisms, journey): bridges[route] = true
	state.bridges = bridges
	var pads: Dictionary = {}
	for pad: Dictionary in view.get("pressure_pads", []):
		pads[pad.id] = LevelGraph.pad_held(pad, state.players, journey)
	state.hold_pads = pads
	return state

static func _surface_rect(view: Dictionary, id: String) -> Array:
	for kind: String in ["islands", "bridges", "stairs"]:
		for item: Dictionary in view.get(kind, []):
			if str(item.id) == id: return item.rect_cm
	return []

static func _surface_height(view: Dictionary, id: String) -> int:
	for kind: String in ["islands", "bridges"]:
		for item: Dictionary in view.get(kind, []):
			if str(item.id) == id: return int(item.get("height_cm", 0))
	return 0

static func _inside(point: Vector2i, rect: Array) -> bool:
	return point.x >= int(rect[0]) + INSET and point.x <= int(rect[2]) - INSET and point.y >= int(rect[1]) + INSET and point.y <= int(rect[3]) - INSET

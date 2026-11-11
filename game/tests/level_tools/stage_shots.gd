extends RefCounted
## The moments the level tools show a stage in, as the engine's own
## snapshots: the stage opening, a pip moved beside a control, a lever
## pulled, a pad held or a selector turned. A moment is a small set of edits
## ({"live": slot, "players": {slot: place}, "levers": {id: on}, "controls":
## {id: value}}) laid over the stage's opening checkpoint; the engine then
## opens the stage from it (trusted: the level tools also show layouts no
## catalog knows yet) and works out every gate, beam and pad itself. Shared by
## the preview (preview_capture.gd) and the view checks (test_level_view.gd),
## so both look at the same moments. Presentation only: nothing made here
## reaches a save, a recording or a server.
##   var shots := StageShots.new(key, level, stage_id, checkpoint)
##   world.present(shots.snapshot(shots.beside({}, lever, "p0")), true)
const Registry = preload("res://services/chapter_registry.gd")
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
## Where beside a control a pip stands (cm), first that fits its floor: near
## enough to show its pair (PairTags.NEAR_CM is 120), clear of the control.
const BESIDE := [[-45, 35], [45, 35], [0, 50], [-50, 0], [50, 0], [0, -50]]
## Floors keep a walker this far inside their edges (cm).
const INSET := 14

var key: String
var level: Dictionary
var stage_id: String
var checkpoint: Dictionary
## The stage merged over its level, as the worlds read it.
var view: Dictionary

func _init(chapter_key: String, definition: Dictionary, stage: String, start: Dictionary) -> void:
	key = chapter_key
	level = definition
	stage_id = stage
	checkpoint = start
	view = CooperativeCatalog.stage_definition(definition, stage)

## The engine's snapshot for `edits` over the opening checkpoint; {} when the
## engine has no such stage. The live pip ("live") is the one the camera
## follows; the engine itself plays role a.
func snapshot(edits: Dictionary = {}) -> Dictionary:
	var start := checkpoint.duplicate(true)
	for slot: String in edits.get("players", {}): start.players[slot] = edits.players[slot]
	var mechanisms: Dictionary = start.get_or_add("mechanisms", {})
	for id: String in edits.get("levers", {}): mechanisms.get_or_add("levers", {})[id] = edits.levers[id]
	for id: String in edits.get("controls", {}): mechanisms.get_or_add("controls", {})[id] = edits.controls[id]
	var sim: RefCounted = Registry.simulation_script(key).new()
	var rules := Registry.preferred_rules(key)
	sim.simulation_version = rules if rules > 0 else int(level.get("simulation_version", 0))
	sim._reset_trusted(level, stage_id, start, {}, "a")
	if sim.stage.is_empty() or not str(sim.error).is_empty(): return {}
	# Taken at tick 0, as the stage opens: the engine has worked out every
	# gate, beam and pad, and no tick has passed for a crossing to close (Tide
	# rules would drown a pip left standing on one).
	var result: Dictionary = sim.snapshot()
	if edits.has("live"): result.active_slot = str(edits.live)
	return result

## Every spot worth a look on the stage, in stage order: {id, kind (selector,
## lever, pad or goal), entity, slot (the pip that works it; a goal's is the
## pip that plays second, who rings it)}.
func spots() -> Array:
	var result: Array = []
	for kind: Array in [["controls", "selector"], ["levers", "lever"], ["pressure_pads", "pad"]]:
		for entity: Dictionary in view.get(kind[0], []):
			result.append({"id": str(entity.id), "kind": kind[1], "entity": entity, "slot": str(entity.get("owner_slot", ""))})
	var goal: Dictionary = view.get("goal", {})
	if not goal.is_empty(): result.append({"id": str(goal.id), "kind": "goal", "entity": goal, "slot": goal_slot(view)})
	return result

## The pip that finishes a stage at its goal: the one who plays second.
static func goal_slot(stage: Dictionary) -> String:
	return "p1" if str(stage.get("first_player_slot", "p0")) == "p0" else "p0"

## `edits` with `slot` the live pip, standing on `entity`'s floor beside it
## (or on it, for `on`).
func beside(edits: Dictionary, entity: Dictionary, slot: String, on: bool = false) -> Dictionary:
	var result := edits.duplicate(true)
	if slot.is_empty(): slot = str(view.get("first_player_slot", "p0"))
	var at := Vector2i(int(entity.position_cm[0]), int(entity.position_cm[1]))
	var surface := str(entity.get("surface_id", ""))
	var spot := at
	if not on:
		var rect := _surface_rect(surface)
		for offset: Array in BESIDE:
			var candidate := at + Vector2i(int(offset[0]), int(offset[1]))
			if rect.is_empty() or _inside(candidate, rect):
				spot = candidate
				break
	result["live"] = slot
	result.get_or_add("players", {})[slot] = {"x": spot.x, "z": spot.y, "height": int(entity.get("height_cm", _surface_height(surface))), "surface_id": surface}
	return result

## `edits` with the spot's control worked: a lever on, a pad held (its pip on
## it), a selector at `value`.
func worked(edits: Dictionary, spot: Dictionary, value: String = "") -> Dictionary:
	var result := edits.duplicate(true)
	match str(spot.kind):
		"lever": result.get_or_add("levers", {})[spot.id] = true
		"pad": result = beside(result, spot.entity, spot.slot, true)
		"selector": result.get_or_add("controls", {})[spot.id] = value
	return result

## `edits` with both pips this far (cm) along x and z from where the stage
## opens them, near nothing.
func away(edits: Dictionary, distance: int) -> Dictionary:
	var result := edits.duplicate(true)
	for slot: String in checkpoint.get("players", {}):
		var place: Dictionary = checkpoint.players[slot].duplicate()
		place.x = int(place.x) + distance
		place.z = int(place.z) + distance
		result.get_or_add("players", {})[slot] = place
	return result

func _surface_rect(id: String) -> Array:
	for kind: String in ["islands", "bridges", "stairs"]:
		for item: Dictionary in view.get(kind, []):
			if str(item.id) == id: return item.rect_cm
	return []

func _surface_height(id: String) -> int:
	for kind: String in ["islands", "bridges"]:
		for item: Dictionary in view.get(kind, []):
			if str(item.id) == id: return int(item.get("height_cm", 0))
	return 0

static func _inside(point: Vector2i, rect: Array) -> bool:
	return point.x >= int(rect[0]) + INSET and point.x <= int(rect[2]) - INSET and point.y >= int(rect[1]) + INSET and point.y <= int(rect[3]) - INSET

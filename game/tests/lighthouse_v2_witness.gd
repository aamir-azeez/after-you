extends RefCounted
## sleeping-lighthouse@2's six stages played through with its solid mirrors
## and selector (core/solid_footprint.gd), from the frozen six-stage solo
## turns (fixtures/lighthouse/complete-six-v3.json). Those walk into the
## controls' centres, so each pip here follows its frozen self instead: every
## tick it steps toward where that pip stood after the same tick on the plain
## stages, and it works each control, takes, fits or rings what its frozen
## self did, as soon as that is in its reach. A pip that meets a footprint
## slides round it, and one that falls behind keeps the turn going until it has
## done it all. Deterministic: the same inputs every run.
const Native = preload("res://core/lighthouse/borrowed_light.gd")
const Catalog = preload("res://core/lighthouse/room_catalog.gd")
const Room = preload("res://core/lighthouse/room_simulation.gd")
const Solid = preload("res://core/solid_footprint.gd")
const FROZEN := "res://tests/fixtures/lighthouse/complete-six-v3.json"
## A pip within this of where its frozen self stood stays put on that axis.
const CLOSE := 4
## The event each press leaves -> the action it was (core/lighthouse/borrowed_light.gd _interact).
const DEEDS := {"route_selected": "select_path", "court_activated": "activate", "tower_anchored": "anchor", "beacon_lit": "light_beacon",
	"lens_taken": "take", "lens_offered": "offer", "lens_fitted": "fit"}

## [{"a": inputs, "b": inputs}] for the six stages, inputs as Room.step takes
## them; [] when a stage cannot be played (`errors` says why).
static func turns(errors: Array = []) -> Array:
	var frozen: Variant = JSON.parse_string(FileAccess.get_file_as_string(FROZEN))
	if not frozen is Dictionary:
		errors.append("the frozen solo turns do not parse")
		return []
	var level := Catalog.definition()
	var plain := _plain(level)
	var was := Catalog.initial_checkpoint(plain)
	var now := Catalog.initial_checkpoint(level)
	var result: Array = []
	for index in level.stages.size():
		var stage_id := str(level.stages[index].id)
		var pair: Dictionary = frozen.pairs[index]
		var old_a := _play(plain, stage_id, was, {}, "a", Native.expand_recording_inputs(pair.a))
		var old_b := _play(plain, stage_id, was, old_a.record, "b", Native.expand_recording_inputs(pair.b))
		if not bool(old_b.state.get("complete", false)):
			errors.append("stage %s: the frozen pair no longer plays on the plain stage" % stage_id)
			return []
		var a := _follow(level, stage_id, now, {}, "a", old_a)
		var b := _follow(level, stage_id, now, a.record, "b", old_b)
		var derived: Dictionary = Room.derive_checkpoint(level, now, a.record, b.record)
		if not derived.valid:
			errors.append("stage %s: the followed pair does not finish (%s); a left %s, b left %s, a deeds %s, b deeds %s, b at %s, frozen b end %s" % [stage_id, derived.get("error", ""), a.left, b.left, old_a.deeds, old_b.deeds, b.state.players, old_b.state.players])
			return []
		result.append({"a": a.inputs, "b": b.inputs})
		# The plain stages are no chapter, so their checkpoints are built unproven.
		was = Room._build_checkpoint(plain, was, old_a.record, old_b.record, old_b.state)
		now = derived.checkpoint
	return result

## `level` with every hand control plain again: the stages the frozen turns were played on.
static func _plain(level: Dictionary) -> Dictionary:
	var plain := level.duplicate(true)
	for stage: Dictionary in plain.stages:
		for control: Dictionary in stage.native.get("controls", []) + ([stage.native.mirror_control] if stage.native.has("mirror_control") else []):
			control.erase("solid")
	return plain

## The frozen turn on the plain stage: where its pip stood after each tick and
## what it did, {record, at: [Vector2i], deeds: [[tick, action id, target]], state}.
static func _play(level: Dictionary, stage_id: String, checkpoint: Dictionary, prior: Dictionary, role: String, inputs: Array) -> Dictionary:
	var sim := Room.new()
	sim._reset_trusted(level, stage_id, checkpoint, prior, role)
	var at: Array = []
	var deeds: Array = []
	for input: Dictionary in inputs:
		if sim.finished: break
		var mirrors: Dictionary = sim.snapshot().get("mirrors", {})
		sim.step(input)
		var state := sim.snapshot()
		var deed := _deed(state, mirrors)
		if not deed.is_empty(): deeds.append([at.size()] + deed)
		var player: Dictionary = state.players[state.active_slot]
		at.append(Vector2i(int(player.x), int(player.z)))
	return {"record": sim.export_recording(), "at": at, "deeds": deeds, "state": sim.snapshot()}

## The same turn on `level`: {record, inputs}.
static func _follow(level: Dictionary, stage_id: String, checkpoint: Dictionary, prior: Dictionary, role: String, frozen: Dictionary) -> Dictionary:
	var sim := Room.new()
	sim._reset_trusted(level, stage_id, checkpoint, prior, role)
	var inputs: Array = []
	var deeds: Array = frozen.deeds.duplicate()
	var held := false
	var last: Vector2i = frozen.at[-1]
	var solids := Solid.solids(Native.Catalog.controls_of(Room.stage_by_id(level, stage_id).native))
	while inputs.size() < Native.MAX_TICKS and not sim.finished:
		var tick := inputs.size()
		# Past its frozen length, a turn goes on only until every deed is done
		# (the receiver until it finishes).
		if tick >= frozen.at.size() and deeds.is_empty() and (role == "a" and bool(sim.snapshot().can_commit)): break
		var state := sim.snapshot()
		var player: Dictionary = state.players[state.active_slot]
		var goal := _clear(solids, frozen.at[mini(tick, frozen.at.size() - 1)] if tick < frozen.at.size() else last)
		var press := false
		if not deeds.is_empty() and int(deeds[0][0]) <= tick and not held:
			var action := sim.context_action()
			press = bool(action.get("enabled", false)) and str(action.id) == str(deeds[0][1]) and (str(deeds[0][2]).is_empty() or str(action.target_id) == str(deeds[0][2]))
		held = press
		var input := {"move_x": _toward(int(player.x), goal.x), "move_z": _toward(int(player.z), goal.y), "interact": press}
		inputs.append(input)
		var mirrors: Dictionary = state.get("mirrors", {})
		sim.step(input)
		if not deeds.is_empty() and _deed(sim.snapshot(), mirrors) == deeds[0].slice(1): deeds.pop_front()
	return {"record": sim.export_recording(), "inputs": inputs, "left": deeds, "state": sim.snapshot()}

## What a tick's press did, from its events: [action id, target] (the
## mirror a rotate turned; "" where any target will do), or [] for nothing.
static func _deed(state: Dictionary, mirrors: Dictionary) -> Array:
	for event: String in state.get("events", []):
		if event == "mirror_rotated":
			for id: String in state.get("mirrors", {}):
				if mirrors.get(id) != state.mirrors[id]: return ["rotate", id]
		if DEEDS.has(event): return [DEEDS[event], ""]
	return []

## `at`, or where a pip stands just clear of the footprint it falls inside.
static func _clear(solids: Array, at: Vector2i) -> Vector2i:
	for control: Dictionary in solids:
		var centre := Vector2(float(control.position_cm[0]), float(control.position_cm[1]))
		var keep := float(int(control.solid.radius_cm) + Solid.BODY_CM + 2)
		var away := Vector2(at) - centre
		if away.length() < keep and not away.is_zero_approx():
			var out := centre + away.normalized() * keep
			return Vector2i(roundi(out.x), roundi(out.y))
	return at

static func _toward(from: int, to: int) -> int:
	return 0 if absi(to - from) <= CLOSE else signi(to - from)

class_name AfterYouSimulation
extends RefCounted

## The authority for puzzle outcomes. No scene nodes, clock, randomness or physics.
## All state after input quantization uses integer centimetres and fixed ticks.
const SCHEMA_VERSION := 1
const SIMULATION_VERSION := 1
const TICK_RATE := 30
const MAX_TICKS := 600
const MOVE_PER_TICK := 8

var level: Dictionary = {}
var role := "a"
var tick := 0
var complete := false
var finished := false
var error := ""
var _a := Vector2i.ZERO
var _b := Vector2i.ZERO
var _seed := Vector2i.ZERO
var _throw_start := Vector2i.ZERO
var _seed_status := "held_a"
var _seed_height := 75
var _throw_tick := -1
var _land_tick := -1
var _plate_active := false
var _charge := 0
var _bridge_open := false
var _bridge_latched := false
var _gate_active := false
var _gate_open := true
var _lift_ticks := 0
var _lift_height := 0
var _a_action_held := false
var _b_action_held := false
var _prior: Dictionary = {}
var _prior_frames: Array = []
var _actions: Array = []
var _checkpoints: Array = []
var _events: Array = []
var _outcome := {"threw_seed": false, "caught_seed": false, "planted_seed": false}
var _message := ""
var catch_assistance := true

func reset(definition: Dictionary, prior_track: Dictionary = {}, current_role: String = "a") -> bool:
	error = ""
	if definition.is_empty() or int(definition.get("version", 0)) != 1:
		error = "This island version is unavailable. Keep the saved turn for a compatible app version."
		return false
	if current_role not in ["a", "b"]:
		error = "Unknown player role."
		return false
	if current_role == "b":
		var reason := recording_error(prior_track, definition)
		if not reason.is_empty() or prior_track.get("role", "") != "a" or not prior_track.get("outcome", {}).get("threw_seed", false):
			error = reason if not reason.is_empty() else "A valid first-player throw is required."
			return false
		var verified: Dictionary = verify_recording(definition, prior_track)
		if not verified.valid or not verified.get("snapshot", {}).get("can_commit", false):
			error = "The earlier contribution is incomplete or does not replay correctly. " + str(verified.get("error", ""))
			return false
	level = definition.duplicate(true)
	role = current_role
	_prior = prior_track.duplicate(true) if role == "b" else {}
	_prior_frames = expand_actions(_prior.get("actions", []))
	tick = 0
	complete = false
	finished = false
	_a = _point(level.starts.a)
	_b = _point(level.starts.b)
	_seed = _a
	_throw_start = _a
	_seed_status = "held_a"
	_seed_height = 75
	_throw_tick = -1
	_land_tick = -1
	_plate_active = false
	_charge = 0
	_bridge_open = false
	_bridge_latched = false
	_gate_active = false
	_gate_open = not level.has("gate")
	_lift_ticks = 0
	_lift_height = 0
	_a_action_held = false
	_b_action_held = false
	_actions = []
	_checkpoints = []
	_events = []
	_outcome = {"threw_seed": false, "caught_seed": false, "planted_seed": false}
	_message = str(level.get("hint_" + role, ""))
	return true

func step(input: Dictionary = {}) -> Dictionary:
	if finished or level.is_empty() or not error.is_empty():
		return snapshot()
	_events = []
	var frame := quantize_input(input)
	_append_frame(frame)
	var a_frame: Dictionary = frame if role == "a" else _prior_frame(tick)
	var b_frame: Dictionary = frame if role == "b" else {"x": 0, "z": 0, "action": false}
	# Recordings only control their own character. Ghosts never collide with B.
	_a = _move(_a, a_frame, true)
	_update_mechanisms()
	_b = _move(_b, b_frame, false)
	var a_pressed := bool(a_frame.action) and not _a_action_held
	var b_pressed := bool(b_frame.action) and not _b_action_held
	_a_action_held = bool(a_frame.action)
	_b_action_held = bool(b_frame.action)
	if a_pressed:
		_try_throw()
	_update_seed()
	if role == "b":
		_try_catch(b_pressed)
		if b_pressed:
			_try_plant()
	tick += 1
	if tick >= MAX_TICKS:
		finished = true
		_events.append("turn_finished")
		if not complete:
			_message = "Your turn is ready to preview." if can_commit() else "Try again — your previous saved turn is safe."
	if complete:
		finished = true
	if tick % TICK_RATE == 0 or finished:
		_checkpoints.append({"tick": tick, "state_hash": state_hash()})
	return snapshot()

func can_commit() -> bool:
	if not error.is_empty() or level.is_empty():
		return false
	# A must leave a viable path, not merely claim that they threw a seed.
	return (_outcome.threw_seed and _bridge_open and _gate_open and _lift_ready()) if role == "a" else complete

func context_action() -> Dictionary:
	# Presentation query only: inspect the current observed state, without
	# advancing a tick, predicting movement or changing recording/hash fields.
	var action := {"id": "throw", "label": "Throw seed", "enabled": false, "reason": ""}
	if role == "b":
		action.id = "plant" if _seed_status == "held_b" else "catch"
		action.label = "Plant seed" if _seed_status == "held_b" else "Catch seed"
	if level.is_empty() or not error.is_empty() or finished or complete:
		action.reason = "This turn is not active."
		return action
	if role == "a":
		if _seed_status != "held_a":
			action.reason = "The seed has already been thrown."
		elif not _plate_active:
			action.reason = "Stand on the round plate."
		elif not _bridge_open:
			action.reason = "Hold the plate until its light is full."
		elif not _lift_ready():
			action.reason = "Keep holding the plate while the garden rises."
		elif _a_action_held:
			action.reason = "Release the action before tapping again."
		else:
			action.enabled = true
	elif _seed_status == "held_b":
		if not _near(_b, _point(level.goal), int(level.goal_radius)):
			action.reason = "Carry the seed to the flower ring."
		elif not _gate_open:
			action.reason = "Wait for the other recording to open the garden."
		elif not _lift_ready():
			action.reason = "Wait for the garden to finish rising."
		elif _b_action_held:
			action.reason = "Release the action before tapping again."
		else:
			action.enabled = true
	elif _seed_status not in ["flying", "waiting"]:
		action.reason = "The seed is not available to catch."
	elif _seed_status == "flying" and tick - _throw_tick < int(level.flight_ticks) - 15:
		action.reason = "Wait for the seed to arrive."
	elif not _near(_b, _seed, int(level.catch_radius)) or _b.x < int(level.gap[1]) + 12:
		action.reason = "Cross the bridge and move beside the seed."
	elif _b_action_held:
		action.reason = "Release the action before tapping again."
	else:
		action.enabled = true
	return action

func snapshot() -> Dictionary:
	return {
		"tick": tick, "time_seconds": float(tick) / TICK_RATE, "role": role,
		"duration_ticks": MAX_TICKS, "complete": complete, "finished": finished,
		"can_commit": can_commit(), "context_action": context_action(), "error": error, "message": _message,
		"players": {
			"a": {"x": _a.x, "z": _a.y, "height": 0, "holding": _seed_status == "held_a", "ghost": role == "b"},
			"b": {"x": _b.x, "z": _b.y, "height": _height_at(_b), "holding": _seed_status == "held_b", "ghost": false},
		},
		"seed": {"x": _seed.x, "z": _seed.y, "height": _seed_height, "status": _seed_status},
		"plate_active": _plate_active, "bridge_open": _bridge_open,
		"bridge_charge": _charge, "bridge_charge_required": int(level.get("bridge_charge_ticks", 1)),
		"gate_open": _gate_open, "gate_plate_active": _gate_active,
		"lift_height": _lift_height, "lift_ready": _lift_ready(),
		"events": _events.duplicate(), "outcome": _outcome.duplicate(),
	}

func export_recording() -> Dictionary:
	if tick == 0:
		return {}
	var checkpoints := _checkpoints.duplicate(true)
	if checkpoints.is_empty() or int(checkpoints[-1].tick) != tick:
		checkpoints.append({"tick": tick, "state_hash": state_hash()})
	var result := {
		"schema_version": SCHEMA_VERSION, "simulation_version": SIMULATION_VERSION,
		"level_id": level.id, "level_version": level.version, "role": role,
		"duration_ticks": tick, "tick_rate": TICK_RATE, "actions": _actions.duplicate(true),
		"checkpoints": checkpoints, "final_state_hash": state_hash(),
		"completed": complete, "outcome": _outcome.duplicate(),
		"catch_assistance": catch_assistance,
	}
	if role == "b":
		result["source_recording_hash"] = _prior.final_state_hash
	return result

func state_hash() -> String:
	# Do not include transient presentation messages or rendering time.
	var state := [SIMULATION_VERSION, str(level.get("id", "")), int(level.get("version", 0)),
		tick, role, _a.x, _a.y, _b.x, _b.y, _seed.x, _seed.y, _seed_height,
		_seed_status, _throw_start.x, _throw_start.y, _throw_tick, _land_tick,
		_plate_active, _charge, _bridge_open, _bridge_latched, _gate_active, _gate_open,
		_lift_ticks, _lift_height, _a_action_held, _b_action_held, complete,
		_outcome.threw_seed, _outcome.caught_seed, _outcome.planted_seed]
	return JSON.stringify(state).sha256_text()

## Validate before opening a turn. Replay validation additionally verifies hashes.
static func recording_error(recording: Dictionary, definition: Dictionary) -> String:
	for key: String in ["schema_version", "simulation_version", "level_version", "duration_ticks", "tick_rate"]:
		if not _is_integer(recording.get(key)):
			return "Invalid integer recording header."
	if int(recording.get("schema_version", 0)) != SCHEMA_VERSION or int(recording.get("simulation_version", 0)) != SIMULATION_VERSION:
		return "Unsupported recording version."
	if recording.get("level_id", "") != definition.get("id", "") or int(recording.get("level_version", 0)) != int(definition.get("version", 1)):
		return "The recording belongs to a different island version."
	if recording.get("role", "") not in ["a", "b"] or int(recording.get("tick_rate", 0)) != TICK_RATE:
		return "Unsupported recording role or tick rate."
	var duration := int(recording.get("duration_ticks", 0))
	if duration < 1 or duration > MAX_TICKS:
		return "Invalid recording duration."
	if typeof(recording.get("actions")) != TYPE_ARRAY:
		return "Missing recording actions."
	var count := 0
	for item: Variant in recording.actions:
		if typeof(item) != TYPE_DICTIONARY:
			return "Invalid action."
		var run: Dictionary = item
		for key: String in ["ticks", "x", "z"]:
			if not _is_integer(run.get(key)):
				return "Non-integer action value."
		if int(run.ticks) < 1 or int(run.ticks) > MAX_TICKS or absi(int(run.x)) > 100 or absi(int(run.z)) > 100 or typeof(run.get("action")) != TYPE_BOOL:
			return "Out-of-range action."
		count += int(run.ticks)
		if count > MAX_TICKS:
			return "Recording is too long."
	if count != duration:
		return "Action duration does not match the recording."
	if typeof(recording.get("outcome")) != TYPE_DICTIONARY:
		return "Missing recording outcome."
	for key: String in ["threw_seed", "caught_seed", "planted_seed"]:
		if typeof(recording.outcome.get(key)) != TYPE_BOOL:
			return "Invalid recording outcome."
	if typeof(recording.get("completed")) != TYPE_BOOL or not _is_hash(recording.get("final_state_hash")):
		return "Missing recording integrity data."
	if recording.has("catch_assistance") and typeof(recording.catch_assistance) != TYPE_BOOL:
		return "Invalid catch assistance setting."
	if typeof(recording.get("checkpoints")) != TYPE_ARRAY:
		return "Missing recording checkpoints."
	var last_tick := 0
	for item: Variant in recording.checkpoints:
		if typeof(item) != TYPE_DICTIONARY or not _is_integer(item.get("tick")) or not _is_hash(item.get("state_hash")):
			return "Invalid recording checkpoint."
		if int(item.tick) <= last_tick or int(item.tick) > duration:
			return "Unordered recording checkpoints."
		last_tick = int(item.tick)
	if last_tick != duration:
		return "The final recording checkpoint is missing."
	if recording.role == "b" and not _is_hash(recording.get("source_recording_hash")):
		return "The earlier recording reference is missing."
	return ""

static func verify_recording(definition: Dictionary, recording: Dictionary, prior_track: Dictionary = {}) -> Dictionary:
	var reason := recording_error(recording, definition)
	if not reason.is_empty():
		return {"valid": false, "error": reason}
	if recording.role == "b" and recording.source_recording_hash != prior_track.get("final_state_hash", ""):
		return {"valid": false, "error": "The earlier turn changed; fork this attempt before replaying."}
	var simulation := AfterYouSimulation.new()
	simulation.catch_assistance = bool(recording.get("catch_assistance", true))
	if not simulation.reset(definition, prior_track, recording.role):
		return {"valid": false, "error": simulation.error}
	var checkpoint_index := 0
	for frame: Dictionary in expand_actions(recording.actions):
		if simulation.finished:
			return {"valid": false, "error": "Actions follow a completed turn."}
		simulation.step({"move_x": float(frame.x) / 100.0, "move_z": float(frame.z) / 100.0, "interact": frame.action})
		if checkpoint_index < recording.checkpoints.size() and simulation.tick == int(recording.checkpoints[checkpoint_index].tick):
			if simulation.state_hash() != recording.checkpoints[checkpoint_index].state_hash:
				return {"valid": false, "error": "A recording checkpoint does not match its actions."}
			checkpoint_index += 1
	if simulation.state_hash() != recording.final_state_hash or simulation.complete != recording.completed or simulation._outcome != recording.outcome:
		return {"valid": false, "error": "The recording outcome does not match its actions."}
	return {"valid": true, "error": "", "snapshot": simulation.snapshot()}

## Changing an earlier turn intentionally does not retain a later recording.
static func fork_recordings(new_first: Dictionary = {}) -> Dictionary:
	return {"a": new_first.duplicate(true), "b": {}, "completed": false}

static func expand_actions(runs: Array) -> Array:
	var frames: Array = []
	for run: Dictionary in runs:
		for _i: int in range(clampi(int(run.get("ticks", 0)), 0, MAX_TICKS)):
			if frames.size() >= MAX_TICKS:
				return frames
			frames.append({"x": int(run.get("x", 0)), "z": int(run.get("z", 0)), "action": bool(run.get("action", false))})
	return frames

## Step-ready replay/resume input. Verify untrusted recordings before using it.
## Example: for input in expand_recording_inputs(track): simulation.step(input)
static func expand_recording_inputs(recording: Dictionary) -> Array:
	var inputs: Array = []
	for frame: Dictionary in expand_actions(recording.get("actions", [])):
		inputs.append({"move_x": float(frame.x) / 100.0, "move_z": float(frame.z) / 100.0, "interact": frame.action})
	return inputs

static func quantize_input(input: Dictionary) -> Dictionary:
	return {"x": _quantize_axis(input.get("move_x", 0)), "z": _quantize_axis(input.get("move_z", 0)), "action": bool(input.get("interact", false))}

func _append_frame(frame: Dictionary) -> void:
	if not _actions.is_empty():
		var last: Dictionary = _actions[-1]
		if last.x == frame.x and last.z == frame.z and last.action == frame.action:
			last.ticks += 1
			return
	_actions.append({"ticks": 1, "x": frame.x, "z": frame.z, "action": frame.action})

func _prior_frame(at_tick: int) -> Dictionary:
	return _prior_frames[at_tick] if at_tick < _prior_frames.size() else {"x": 0, "z": 0, "action": false}

func _move(position: Vector2i, frame: Dictionary, first_player: bool) -> Vector2i:
	var speed := 6 if int(frame.x) != 0 and int(frame.z) != 0 else MOVE_PER_TICK
	var delta := Vector2i(_axis_delta(int(frame.x), speed), _axis_delta(int(frame.z), speed))
	var proposed := position + delta
	var bounds: Array = level.bounds
	proposed.x = clampi(proposed.x, int(bounds[0]) + 20, int(bounds[2]) - 20)
	proposed.y = clampi(proposed.y, int(bounds[1]) + 20, int(bounds[3]) - 20)
	# A performs their contribution on the near island; only B crosses the bridge.
	if first_player:
		proposed.x = mini(proposed.x, int(level.gap[0]) - 22)
		return proposed
	if _walkable(proposed):
		return proposed
	var slide_x := Vector2i(proposed.x, position.y)
	if _walkable(slide_x):
		return slide_x
	var slide_z := Vector2i(position.x, proposed.y)
	return slide_z if _walkable(slide_z) else position

func _walkable(position: Vector2i) -> bool:
	if position.x <= int(level.gap[0]) - 12 or position.x >= int(level.gap[1]) + 12:
		return true
	return _bridge_open and absi(position.y - int(level.bridge.z)) <= int(level.bridge.width) / 2 - 12

func _update_mechanisms() -> void:
	var was_open := _bridge_open
	_plate_active = _near(_a, _point(level.plate), int(level.plate_radius))
	_charge = mini(_charge + 1, int(level.bridge_charge_ticks)) if _plate_active else 0
	_bridge_open = _bridge_latched or (_plate_active and _charge >= int(level.bridge_charge_ticks))
	if _bridge_open and not was_open:
		_events.append("bridge_opened")
	if level.has("gate"):
		_gate_active = _near(_a, _point(level.gate.plate), int(level.plate_radius))
		if _gate_active and not _gate_open:
			_gate_open = true
			_events.append("garden_opened")
	if level.has("lift"):
		var rise_ticks := int(level.lift.rise_ticks)
		if _plate_active and _lift_ticks < rise_ticks:
			_lift_ticks += 1
			_lift_height = int(level.lift.height) * _lift_ticks / rise_ticks
			if _lift_ticks == rise_ticks:
				_events.append("lift_ready")

func _try_throw() -> void:
	if _seed_status != "held_a":
		return
	if not _plate_active:
		_message = "Stand on the round plate to open the bridge and throw."
		return
	if not _bridge_open:
		_message = "Hold the plate until its light is full, then tap Throw."
		return
	if level.has("lift") and not _lift_ready():
		_message = "Keep holding the plate while your friend's garden rises. Then throw."
		return
	_seed_status = "flying"
	_throw_start = _a
	_throw_tick = tick
	_outcome.threw_seed = true
	if level.has("gate"):
		_bridge_latched = true
	_events.append("seed_thrown")
	_message = "Now open the second plate for your friend." if level.has("gate") else "Stay on the plate. Your friend will cross beside your ghost."

func _update_seed() -> void:
	if _seed_status == "held_a":
		_seed = _a
		_seed_height = 75
	elif _seed_status == "held_b":
		_seed = _b
		_seed_height = _height_at(_b) + 75
	elif _seed_status == "flying":
		var travel := int(level.flight_ticks)
		var elapsed := mini(tick - _throw_tick, travel)
		var target := _point(level.landing)
		_seed = _throw_start + Vector2i((target.x - _throw_start.x) * elapsed / travel, (target.y - _throw_start.y) * elapsed / travel)
		var landing_height := _height_at(target) + 35
		_seed_height = 75 + (landing_height - 75) * elapsed / travel + 4 * 250 * elapsed * (travel - elapsed) / (travel * travel)
		if elapsed == travel:
			_seed_status = "waiting"
			_land_tick = tick
			_events.append("seed_landed")
	elif _seed_status == "waiting":
		_seed_height = _height_at(_seed) + 35
		if tick - _land_tick >= int(level.seed_wait_ticks):
			_seed_status = "missed"
			_events.append("seed_missed")
			if role == "b":
				_message = "The seed faded. Rehearse again; your friend's recording is still here."
	elif _seed_status == "planted":
		_seed = _point(level.goal)
		_seed_height = _height_at(_seed) + 20

func _try_catch(pressed: bool) -> void:
	if _seed_status not in ["flying", "waiting"]:
		return
	if not catch_assistance and not pressed:
		return
	if _seed_status == "flying" and tick - _throw_tick < int(level.flight_ticks) - 15:
		return
	if _near(_b, _seed, int(level.catch_radius)) and _b.x >= int(level.gap[1]) + 12:
		_seed_status = "held_b"
		_seed = _b
		_seed_height = _height_at(_b) + 75
		_outcome.caught_seed = true
		_events.append("seed_caught")
		_message = "You caught it! Carry the seed to the flower ring and tap Plant."

func _try_plant() -> void:
	if _seed_status != "held_b":
		return
	if not _near(_b, _point(level.goal), int(level.goal_radius)):
		_message = "Carry the seed to the flower ring before planting."
		return
	if not _gate_open:
		_message = "Wait for your friend's ghost to open the garden from the second plate."
		return
	if not _lift_ready():
		_message = "Let the garden finish rising before planting."
		return
	_seed_status = "planted"
	_seed = _point(level.goal)
	_seed_height = _height_at(_seed) + 20
	_outcome.planted_seed = true
	complete = true
	_events.append("island_bloomed")
	_message = "You were here. I was here. We made this."

func _height_at(position: Vector2i) -> int:
	if not level.has("lift"):
		return 0
	var zone: Array = level.lift.zone
	return _lift_height if position.x >= int(zone[0]) and position.y >= int(zone[1]) and position.x <= int(zone[2]) and position.y <= int(zone[3]) else 0

func _lift_ready() -> bool:
	return not level.has("lift") or _lift_ticks >= int(level.lift.rise_ticks)

static func _point(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))

static func _near(a: Vector2i, b: Vector2i, radius: int) -> bool:
	var difference := a - b
	return difference.x * difference.x + difference.y * difference.y <= radius * radius

static func _axis_delta(value: int, speed: int) -> int:
	return signi(value) * ((absi(value) * speed + 50) / 100)

static func _quantize_axis(value: Variant) -> int:
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)):
		return 0
	return roundi(clampf(float(value), -1.0, 1.0) * 100.0)

static func _is_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value))

static func _is_hash(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != 64:
		return false
	for character: String in value:
		if character not in "0123456789abcdef":
			return false
	return true

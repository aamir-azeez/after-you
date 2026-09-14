class_name AfterYouSimulationV2
extends RefCounted
## Isolated v2 prototype. Integer, fixed-tick simulation; no scene or network API.

const Catalog = preload("res://core/v2/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const TICK_RATE := 30
const MAX_TICKS := 600
const MOVE_PER_TICK := 8
const PLAYER_RADIUS := 12
const RECORD_KEYS := ["schema_version", "simulation_version", "level_id", "level_version", "definition_hash", "stage_id", "stage_version", "checkpoint_hash", "role", "player_slot", "tick_rate", "duration_ticks", "catch_assistance", "actions", "replay_checks", "final_state_hash", "completed", "outcome", "source_recording_hash", "recording_hash"]
const OUTCOME_KEYS := ["threw_seed", "caught_seed", "placed_relay", "took_seed", "planted_seed"]
const CHECKPOINT_KEYS := ["schema_version", "level_id", "level_version", "definition_hash", "stage_index", "completed_stage_id", "next_stage_id", "players", "latched_bridges", "seed", "previous_checkpoint_hash", "a_recording_hash", "b_recording_hash", "checkpoint_hash", "proof"]

var level: Dictionary = {}
var stage: Dictionary = {}
var role := "a"
var first_player_slot := "p0"
var active_slot := "p0"
var tick := 0
var complete := false
var finished := false
var error := ""
var catch_assistance := true
var _checkpoint: Dictionary = {}
var _prior: Dictionary = {}
var _prior_frames: Array = []
var _players: Dictionary = {}
var _bridges: Dictionary = {}
var _latched: Array = []
var _seed: Dictionary = {}
var _throw_start := Vector2i.ZERO
var _throw_tick := -1
var _land_tick := -1
var _action_held := {"p0": false, "p1": false}
var _actions: Array = []
var _checks: Array = []
var _events: Array = []
var _outcome: Dictionary = {}
var _objective_done := false
var _hold_broken := false
var _message := ""

func reset(definition: Dictionary, stage_id: String, checkpoint: Dictionary, prior_a: Dictionary = {}, current_role: String = "a") -> bool:
	error = ""
	level = {}
	stage = {}
	if not Canonical.same(definition, Catalog.relay_isles()):
		error = "Unsupported level definition or version."
		return false
	var checked := verify_checkpoint(definition, checkpoint)
	if not checked.valid:
		error = checked.error
		return false
	if current_role not in ["a", "b"] or stage_id != checkpoint.next_stage_id or stage_id.is_empty():
		error = "Unknown role or stale stage checkpoint."
		return false
	if current_role == "a" and not prior_a.is_empty():
		error = "A first turn cannot depend on another first turn."
		return false
	if current_role == "b":
		var prior_check := _verify_raw(definition, prior_a, checkpoint, {})
		if not prior_check.valid or prior_a.get("role") != "a" or not prior_check.get("snapshot", {}).get("can_commit", false):
			error = "A verified, viable earlier contribution is required."
			return false
	_reset_trusted(definition, stage_id, checkpoint, prior_a, current_role)
	return true

func _reset_trusted(definition: Dictionary, stage_id: String, checkpoint: Dictionary, prior_a: Dictionary, current_role: String) -> void:
	level = definition.duplicate(true)
	stage = stage_by_id(level, stage_id)
	role = current_role
	first_player_slot = stage.first_player_slot
	active_slot = first_player_slot if role == "a" else _other(first_player_slot)
	_checkpoint = checkpoint.duplicate(true)
	_prior = prior_a.duplicate(true)
	_prior_frames = expand_recording_inputs(prior_a)
	_players = checkpoint.players.duplicate(true)
	_latched = checkpoint.latched_bridges.duplicate()
	_bridges = {}
	for bridge: Dictionary in level.bridges:
		_bridges[bridge.id] = bridge.id in _latched
	_seed = checkpoint.seed.duplicate(true)
	var pos := _position(str(_seed.owner)) if _seed.status == "held" else _point(_entity(level.sockets, _seed.socket_id).position_cm)
	_seed.merge({"x": pos.x, "z": pos.y, "height": 75 if _seed.status == "held" else 35}, true)
	_throw_start = pos
	_throw_tick = -1
	_land_tick = -1
	_action_held = {"p0": false, "p1": false}
	_actions = []
	_checks = []
	_events = []
	_outcome = {}
	for key: String in OUTCOME_KEYS:
		_outcome[key] = false
	_objective_done = false
	_hold_broken = false
	tick = 0
	complete = false
	finished = false
	error = ""
	_message = stage.get("hint_" + role, "")

func step(input: Dictionary = {}) -> Dictionary:
	if finished or not error.is_empty() or level.is_empty():
		return snapshot()
	if not _valid_input(input):
		error = "Unsupported control input."
		return snapshot()
	_events = []
	var frame := quantize_input(input)
	_append_frame(frame)
	var first_frame: Dictionary = frame if role == "a" else quantize_input(_prior_frames[tick]) if tick < _prior_frames.size() else {"x": 0, "z": 0, "action": false}
	var second_frame: Dictionary = frame if role == "b" else {"x": 0, "z": 0, "action": false}
	_move_slot(first_player_slot, first_frame)
	_update_bridges()
	if role == "b":
		_move_slot(_other(first_player_slot), second_frame)
	var first_pressed: bool = bool(first_frame.action) and not _action_held[first_player_slot]
	var second_pressed: bool = bool(second_frame.action) and not _action_held[_other(first_player_slot)]
	_action_held[first_player_slot] = bool(first_frame.action)
	_action_held[_other(first_player_slot)] = bool(second_frame.action)
	if first_pressed:
		_interact_first()
	_update_seed()
	if role == "b":
		_try_catch(second_pressed)
		if second_pressed:
			_interact_second()
	tick += 1
	if role == "a" and not _outcome.threw_seed and tick + _receiver_finish_budget() > MAX_TICKS:
		_message = "Throw earlier so your partner has time to catch and deliver the seed."
	if role == "b" and _objective_done and tick >= int(_prior.duration_ticks):
		complete = true
		finished = true
		_events.append("stage_complete")
		_message = "Preview this handoff, then save your checkpoint."
	if tick >= MAX_TICKS:
		finished = true
		_events.append("turn_finished")
	if tick % TICK_RATE == 0 or finished:
		_checks.append({"tick": tick, "state_hash": state_hash()})
	return snapshot()

func can_commit() -> bool:
	if level.is_empty() or not error.is_empty() or tick == 0:
		return false
	if role == "b":
		return complete
	return bool(_outcome.threw_seed) and not _hold_broken and _throw_tick + _receiver_finish_budget() <= MAX_TICKS and bool(_bridges[stage.bridge_id]) and _on_plate(first_player_slot, stage.plate_id)

func commit_reason() -> String:
	if not error.is_empty():
		return error
	if level.is_empty():
		return "No stage is loaded."
	if role == "b":
		return "" if complete else "Complete this stage beside the earlier recording."
	if _hold_broken:
		return "The plate was released after the throw. Try again and keep it held through Finish."
	if not _outcome.threw_seed:
		return "Throw earlier so your partner has time to catch and deliver the seed." if tick + _receiver_finish_budget() > MAX_TICKS else "Hold the plate and throw the seed."
	return "" if can_commit() else "Keep the plate held until you finish this contribution."

func snapshot() -> Dictionary:
	if level.is_empty():
		return {"error": error, "can_commit": false, "finished": false, "complete": false}
	var players := _players.duplicate(true)
	for slot: String in players:
		players[slot].merge({"height": 0, "ghost": role == "b" and slot == first_player_slot, "holding": _seed.status == "held" and _seed.owner == slot})
	return {
		"schema_version": 2, "stage_id": stage.id, "role": role, "active_slot": active_slot,
		"first_player_slot": first_player_slot, "tick": tick, "time_seconds": float(tick) / TICK_RATE,
		"duration_ticks": MAX_TICKS, "complete": complete, "finished": finished,
		"can_commit": can_commit(), "commit_reason": commit_reason(), "error": error, "message": _message,
		"players": players, "bridges": _bridges.duplicate(), "seed": _seed.duplicate(),
		"latched_bridges": _latched.duplicate(), "events": _events.duplicate(),
		"outcome": _outcome.duplicate(), "context_action": context_action()
	}

func context_action() -> Dictionary:
	if level.is_empty():
		return {"id": "none", "label": "Action", "enabled": false, "target_id": ""}
	if role == "a":
		if _seed.status == "socket":
			var socket := _entity(level.sockets, str(_seed.socket_id))
			return {"id": "take", "label": "Take seed", "enabled": _near(_position(active_slot), _point(socket.position_cm), int(socket.radius_cm)), "target_id": socket.id}
		return {"id": "throw", "label": "Throw seed", "enabled": _seed.status == "held" and _seed.owner == active_slot and _on_plate(active_slot, stage.plate_id) and tick + _receiver_finish_budget() <= MAX_TICKS, "target_id": stage.bridge_id}
	var destination := _entity(level.sockets, stage.destination)
	if _seed.status == "held" and _seed.owner == active_slot:
		return {"id": stage.goal_action, "label": "Place in relay" if stage.goal_action == "place_relay" else "Plant seed", "enabled": _near(_position(active_slot), _point(destination.position_cm), int(destination.radius_cm)), "target_id": destination.id}
	return {"id": "catch", "label": "Catch seed", "enabled": _catch_possible(), "target_id": "seed"}

func export_recording() -> Dictionary:
	if tick == 0 or level.is_empty():
		return {}
	var checks := _checks.duplicate(true)
	if checks.is_empty() or int(checks[-1].tick) != tick:
		checks.append({"tick": tick, "state_hash": state_hash()})
	var record := {
		"schema_version": 2, "simulation_version": 2, "level_id": level.id, "level_version": level.version,
		"definition_hash": Canonical.digest(level), "stage_id": stage.id, "stage_version": stage.version,
		"checkpoint_hash": _checkpoint.checkpoint_hash, "role": role, "player_slot": active_slot,
		"tick_rate": TICK_RATE, "duration_ticks": tick, "catch_assistance": catch_assistance,
		"actions": _actions.duplicate(true), "replay_checks": checks, "final_state_hash": state_hash(),
		"completed": complete, "outcome": _outcome.duplicate(),
		"source_recording_hash": str(_prior.get("recording_hash", "")) if role == "b" else ""
	}
	record["recording_hash"] = recording_hash(record)
	return record

func state_hash() -> String:
	return Canonical.digest({"simulation_version": 2, "definition_hash": Canonical.digest(level), "stage_id": stage.id, "checkpoint_hash": _checkpoint.checkpoint_hash, "role": role, "tick": tick, "players": _players, "bridges": _bridges, "latched": _latched, "seed": _seed, "throw_start": [_throw_start.x, _throw_start.y], "throw_tick": _throw_tick, "land_tick": _land_tick, "held": _action_held, "outcome": _outcome, "objective_done": _objective_done, "hold_broken": _hold_broken, "complete": complete})

func walkable_at(x: int, z: int) -> bool:
	if level.is_empty():
		return false
	for offset: Vector2i in [Vector2i.ZERO, Vector2i(-PLAYER_RADIUS, -PLAYER_RADIUS), Vector2i(PLAYER_RADIUS, -PLAYER_RADIUS), Vector2i(-PLAYER_RADIUS, PLAYER_RADIUS), Vector2i(PLAYER_RADIUS, PLAYER_RADIUS), Vector2i(PLAYER_RADIUS, 0), Vector2i(-PLAYER_RADIUS, 0), Vector2i(0, PLAYER_RADIUS), Vector2i(0, -PLAYER_RADIUS)]:
		if _surface_at(Vector2i(x, z) + offset).is_empty():
			return false
	return true

func _surface_at(position: Vector2i) -> String:
	for island: Dictionary in level.islands:
		if _in_rect(position, island.rect_cm):
			return island.id
	for bridge: Dictionary in level.bridges:
		if _bridges.get(bridge.id, false) and _in_rect(position, bridge.rect_cm):
			return bridge.id
	return ""

func _move_slot(slot: String, frame: Dictionary) -> void:
	var origin := _position(slot)
	var speed := 6 if int(frame.x) != 0 and int(frame.z) != 0 else MOVE_PER_TICK
	var delta := Vector2i(_axis_delta(int(frame.x), speed), _axis_delta(int(frame.z), speed))
	var destination := origin
	for change: Vector2i in [delta, Vector2i(delta.x, 0), Vector2i(0, delta.y)]:
		if _swept_walkable(origin, change):
			destination = origin + change
			break
	_players[slot] = {"x": destination.x, "z": destination.y, "surface_id": _surface_at(destination)}

func _swept_walkable(origin: Vector2i, delta: Vector2i) -> bool:
	var count := maxi(absi(delta.x), absi(delta.y))
	if count == 0:
		return true
	for index in range(1, count + 1):
		var candidate := origin + Vector2i(delta.x * index / count, delta.y * index / count)
		if not walkable_at(candidate.x, candidate.y):
			return false
	return true

func _update_bridges() -> void:
	for bridge: Dictionary in level.bridges:
		var opened: bool = bridge.id in _latched or (bridge.id == stage.bridge_id and _on_plate(first_player_slot, bridge.plate_id))
		if opened and not _bridges[bridge.id]:
			_events.append("bridge_opened:" + str(bridge.id))
		_bridges[bridge.id] = opened
	if _throw_tick >= 0 and not _on_plate(first_player_slot, stage.plate_id):
		_hold_broken = true
		if role == "a":
			_message = "The plate was released. Try this turn again and keep it held after throwing."

func _interact_first() -> void:
	if _seed.status == "socket":
		var socket := _entity(level.sockets, str(_seed.socket_id))
		if stage.goal_action == "plant" and _near(_position(first_player_slot), _point(socket.position_cm), int(socket.radius_cm)):
			_seed.merge({"status": "held", "owner": first_player_slot, "socket_id": ""}, true)
			_outcome.took_seed = true
			_events.append("seed_taken")
		return
	if _seed.status != "held" or _seed.owner != first_player_slot or not _on_plate(first_player_slot, stage.plate_id):
		return
	if tick + _receiver_finish_budget() > MAX_TICKS:
		if role == "a":
			_message = "Throw earlier so your partner has time to catch and deliver the seed."
		return
	_throw_start = _position(first_player_slot)
	_throw_tick = tick
	_seed.merge({"status": "flying", "owner": "", "socket_id": ""}, true)
	_outcome.threw_seed = true
	_events.append("seed_thrown")
	if role == "a":
		_message = "Keep this crossing open, then preview your contribution."

func _receiver_finish_budget() -> int:
	# Both supported stage destinations share their landing's unobstructed
	# rectangular island. Budget the full arc, an axis-aligned walk to the
	# socket center, and separate landing/action ticks. This is a conservative
	# authored-route bound, not a general puzzle solver or a human speed claim.
	var socket := _entity(level.sockets, stage.destination)
	var route := _point(socket.position_cm) - _point(stage.landing_cm)
	var walking := ceili(float(absi(route.x)) / MOVE_PER_TICK) + ceili(float(absi(route.y)) / MOVE_PER_TICK)
	return int(stage.flight_ticks) + walking + 2

func _update_seed() -> void:
	if _seed.status == "held":
		var pos := _position(str(_seed.owner))
		_seed.merge({"x": pos.x, "z": pos.y, "height": 75}, true)
	elif _seed.status == "flying":
		var elapsed := mini(tick - _throw_tick, int(stage.flight_ticks))
		var duration := int(stage.flight_ticks)
		var target := _point(stage.landing_cm)
		var pos := _throw_start + Vector2i((target.x - _throw_start.x) * elapsed / duration, (target.y - _throw_start.y) * elapsed / duration)
		_seed.merge({"x": pos.x, "z": pos.y, "height": 75 - 40 * elapsed / duration + 4 * 250 * elapsed * (duration - elapsed) / (duration * duration)}, true)
		if elapsed == duration:
			_seed.status = "waiting"
			_land_tick = tick
			_events.append("seed_landed")
	elif _seed.status == "waiting" and tick - _land_tick >= int(level.seed_wait_ticks):
		_seed.status = "missed"
		_events.append("seed_missed")
		_message = "The seed faded. Your earlier saved contribution is still safe."

func _catch_possible() -> bool:
	if _seed.status not in ["flying", "waiting"]:
		return false
	if _seed.status == "flying" and tick - _throw_tick < int(stage.flight_ticks) - 15:
		return false
	var receiver := _other(first_player_slot)
	return _surface_at(_position(receiver)) == stage.landing_surface and _near(_position(receiver), Vector2i(int(_seed.x), int(_seed.z)), int(level.catch_radius))

func _try_catch(pressed: bool) -> void:
	if not (catch_assistance or pressed) or not _catch_possible():
		return
	_seed.merge({"status": "held", "owner": _other(first_player_slot), "socket_id": "", "height": 75}, true)
	_outcome.caught_seed = true
	_events.append("seed_caught")
	_message = "Carry the seed to the relay socket and tap Place." if stage.goal_action == "place_relay" else "Carry the seed to the garden and tap Plant."

func _interact_second() -> void:
	var receiver := _other(first_player_slot)
	if _seed.status != "held" or _seed.owner != receiver:
		return
	var socket := _entity(level.sockets, stage.destination)
	var pos := _point(socket.position_cm)
	if not _near(_position(receiver), pos, int(socket.radius_cm)):
		return
	_seed.merge({"status": "socket" if stage.goal_action == "place_relay" else "planted", "owner": "", "socket_id": socket.id, "x": pos.x, "z": pos.y, "height": 35}, true)
	if stage.goal_action == "place_relay":
		_outcome.placed_relay = true
		if stage.bridge_id not in _latched:
			_latched.append(stage.bridge_id)
		_events.append("relay_filled")
	else:
		_outcome.planted_seed = true
		_events.append("garden_bloomed")
	_objective_done = true
	_message = "Your part is ready. Let the earlier contribution finish."

func _on_plate(slot: String, plate_id: String) -> bool:
	var plate := _entity(level.plates, plate_id)
	return _near(_position(slot), _point(plate.position_cm), int(plate.radius_cm))

func _position(slot: String) -> Vector2i:
	return Vector2i(int(_players[slot].x), int(_players[slot].z))

func _append_frame(frame: Dictionary) -> void:
	if not _actions.is_empty():
		var last: Dictionary = _actions[-1]
		if last.x == frame.x and last.z == frame.z and last.action == frame.action:
			last.ticks += 1
			return
	_actions.append({"ticks": 1, "x": frame.x, "z": frame.z, "action": frame.action})

static func stage_by_id(definition: Dictionary, stage_id: String) -> Dictionary:
	return _entity(definition.get("stages", []), stage_id).duplicate(true)

static func expand_recording_inputs(recording: Dictionary) -> Array:
	var frames: Array = []
	for run: Dictionary in recording.get("actions", []):
		for _index in range(int(run.ticks)):
			frames.append({"move_x": float(run.x) / 100.0, "move_z": float(run.z) / 100.0, "interact": bool(run.action)})
	return frames

static func recording_hash(recording: Dictionary) -> String:
	var body := recording.duplicate(true)
	body.erase("recording_hash")
	return Canonical.digest(body)

static func verify_recording(definition: Dictionary, recording: Dictionary, checkpoint: Dictionary, prior_a: Dictionary = {}) -> Dictionary:
	var check := verify_checkpoint(definition, checkpoint)
	return _verify_raw(definition, recording, checkpoint, prior_a) if check.valid else check

static func _verify_raw(definition: Dictionary, recording: Dictionary, checkpoint: Dictionary, prior_a: Dictionary) -> Dictionary:
	var reason := recording_error(definition, recording, checkpoint)
	if not reason.is_empty():
		return _invalid(reason)
	if recording.role == "b":
		if prior_a.get("role") != "a" or recording.source_recording_hash != prior_a.get("recording_hash", ""):
			return _invalid("Earlier recording dependency changed.")
		var first_check := _verify_raw(definition, prior_a, checkpoint, {})
		if not first_check.valid or not first_check.snapshot.can_commit:
			return _invalid("Earlier contribution cannot be used.")
	elif not prior_a.is_empty() or not str(recording.source_recording_hash).is_empty():
		return _invalid("Unexpected earlier recording on A.")
	var simulation := AfterYouSimulationV2.new()
	simulation.catch_assistance = recording.catch_assistance
	simulation._reset_trusted(definition, recording.stage_id, checkpoint, prior_a, recording.role)
	for input: Dictionary in expand_recording_inputs(recording):
		if simulation.finished:
			return _invalid("Actions follow a completed turn.")
		simulation.step(input)
	if not Canonical.same(simulation.export_recording(), recording):
		return _invalid("Recording does not match deterministic replay.")
	return {"valid": true, "error": "", "snapshot": simulation.snapshot()}

static func recording_error(definition: Dictionary, record: Dictionary, checkpoint: Dictionary) -> String:
	if not _exact_keys(record, RECORD_KEYS):
		return "Missing or unknown recording fields."
	for key: String in ["schema_version", "simulation_version", "level_version", "stage_version"]:
		if not _integer(record[key]) or int(record[key]) != 2:
			return "Unsupported recording version."
	if record.level_id != definition.id or record.definition_hash != Canonical.digest(definition) or record.checkpoint_hash != checkpoint.get("checkpoint_hash") or record.stage_id != checkpoint.get("next_stage_id"):
		return "Recording belongs to another definition or checkpoint."
	var selected := stage_by_id(definition, str(record.stage_id))
	if selected.is_empty() or record.role not in ["a", "b"]:
		return "Unknown stage or role."
	var expected_slot: String = selected.first_player_slot if record.role == "a" else _other(selected.first_player_slot)
	if record.player_slot != expected_slot:
		return "Recording changes the physical player slot."
	if not _integer(record.tick_rate) or int(record.tick_rate) != TICK_RATE or not _integer(record.duration_ticks) or int(record.duration_ticks) < 1 or int(record.duration_ticks) > MAX_TICKS:
		return "Invalid recording duration."
	if not record.catch_assistance is bool or not record.completed is bool or not record.outcome is Dictionary or not _exact_keys(record.outcome, OUTCOME_KEYS):
		return "Invalid recording outcome."
	for key: String in OUTCOME_KEYS:
		if not record.outcome[key] is bool:
			return "Invalid outcome value."
	if not record.source_recording_hash is String or not _hash(record.final_state_hash) or not _hash(record.recording_hash) or (record.role == "b" and not _hash(record.source_recording_hash)):
		return "Invalid recording hashes."
	if not record.actions is Array or record.actions.is_empty() or record.actions.size() > MAX_TICKS:
		return "Invalid action list."
	var total := 0
	for item: Variant in record.actions:
		if not item is Dictionary or not _exact_keys(item, ["ticks", "x", "z", "action"]):
			return "Unknown action fields."
		if not _integer(item.ticks) or int(item.ticks) < 1 or int(item.ticks) > MAX_TICKS or not _integer(item.x) or not _integer(item.z) or absi(int(item.x)) > 100 or absi(int(item.z)) > 100 or not item.action is bool:
			return "Invalid action values."
		total += int(item.ticks)
		if total > MAX_TICKS:
			return "Too many action ticks."
	if total != int(record.duration_ticks):
		return "Action duration mismatch."
	if not record.replay_checks is Array or record.replay_checks.is_empty() or record.replay_checks.size() > 21:
		return "Invalid replay integrity checks."
	var last := 0
	for item: Variant in record.replay_checks:
		if not item is Dictionary or not _exact_keys(item, ["tick", "state_hash"]) or not _integer(item.tick) or int(item.tick) <= last or int(item.tick) > total or not _hash(item.state_hash):
			return "Invalid replay integrity check."
		last = int(item.tick)
	if last != total or recording_hash(record) != record.recording_hash:
		return "Recording content hash mismatch."
	return ""

static func verify_checkpoint(definition: Dictionary, checkpoint: Dictionary) -> Dictionary:
	if not Canonical.same(definition, Catalog.relay_isles()):
		return _invalid("Unsupported level definition or version.")
	return _verify_checkpoint(definition, checkpoint, 0)

static func _verify_checkpoint(definition: Dictionary, checkpoint: Dictionary, depth: int) -> Dictionary:
	if depth > 2 or not _exact_keys(checkpoint, CHECKPOINT_KEYS) or not _integer(checkpoint.get("stage_index")) or int(checkpoint.stage_index) < 0 or int(checkpoint.stage_index) > definition.stages.size():
		return _invalid("Malformed stage checkpoint.")
	if checkpoint.stage_index == 0:
		return {"valid": true, "error": ""} if Canonical.same(checkpoint, Catalog.initial_checkpoint(definition)) else _invalid("Initial checkpoint was changed.")
	if not checkpoint.proof is Dictionary or not _exact_keys(checkpoint.proof, ["previous_checkpoint", "a", "b"]):
		return _invalid("Checkpoint has no verified source pair.")
	var proof: Dictionary = checkpoint.proof
	if not proof.previous_checkpoint is Dictionary or not proof.a is Dictionary or not proof.b is Dictionary or not _integer(proof.previous_checkpoint.get("stage_index")) or int(proof.previous_checkpoint.stage_index) != int(checkpoint.stage_index) - 1:
		return _invalid("Checkpoint source order changed.")
	var prior_check := _verify_checkpoint(definition, proof.previous_checkpoint, depth + 1)
	if not prior_check.valid:
		return prior_check
	var pair := _verify_pair(definition, proof.previous_checkpoint, proof.a, proof.b)
	if not pair.valid:
		return pair
	var derived := _build_checkpoint(definition, proof.previous_checkpoint, proof.a, proof.b, pair.snapshot)
	return {"valid": true, "error": ""} if Canonical.same(checkpoint, derived) else _invalid("Checkpoint state differs from its verified replay.")

static func derive_checkpoint(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary) -> Dictionary:
	var check := verify_checkpoint(definition, previous)
	if not check.valid:
		return check
	var pair := _verify_pair(definition, previous, first, second)
	if not pair.valid:
		return pair
	return {"valid": true, "error": "", "checkpoint": _build_checkpoint(definition, previous, first, second, pair.snapshot)}

static func _verify_pair(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary) -> Dictionary:
	if first.get("role") != "a" or second.get("role") != "b":
		return _invalid("A checkpoint requires an ordered A/B pair.")
	var check := _verify_raw(definition, second, previous, first)
	if not check.valid or not check.get("snapshot", {}).get("complete", false):
		return _invalid("The stage has not been completed by a verified pair.")
	return check

static func _build_checkpoint(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary, state: Dictionary) -> Dictionary:
	var index := int(previous.stage_index) + 1
	var players: Dictionary = {}
	for slot: String in ["p0", "p1"]:
		players[slot] = {"x": int(state.players[slot].x), "z": int(state.players[slot].z), "surface_id": str(state.players[slot].surface_id)}
	var checkpoint := {
		"schema_version": 2, "level_id": definition.id, "level_version": definition.version,
		"definition_hash": Canonical.digest(definition), "stage_index": index,
		"completed_stage_id": str(second.stage_id), "next_stage_id": str(definition.stages[index].id) if index < definition.stages.size() else "",
		"players": players, "latched_bridges": state.latched_bridges.duplicate(),
		"seed": {"status": state.seed.status, "owner": state.seed.owner, "socket_id": state.seed.socket_id},
		"previous_checkpoint_hash": previous.checkpoint_hash, "a_recording_hash": first.recording_hash, "b_recording_hash": second.recording_hash,
		"proof": {"previous_checkpoint": previous.duplicate(true), "a": first.duplicate(true), "b": second.duplicate(true)}
	}
	checkpoint["checkpoint_hash"] = Catalog.checkpoint_hash(checkpoint)
	return checkpoint

static func quantize_input(input: Dictionary) -> Dictionary:
	return {"x": roundi(clampf(float(input.get("move_x", 0.0)), -1.0, 1.0) * 100.0), "z": roundi(clampf(float(input.get("move_z", 0.0)), -1.0, 1.0) * 100.0), "action": bool(input.get("interact", false))}

static func _valid_input(input: Dictionary) -> bool:
	for key: Variant in input:
		if key not in ["move_x", "move_z", "interact"]:
			return false
	for key: String in ["move_x", "move_z"]:
		var value: Variant = input.get(key, 0.0)
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)) or absf(float(value)) > 1.0:
			return false
	return input.get("interact", false) is bool

static func _entity(entities: Array, id: String) -> Dictionary:
	for entity: Dictionary in entities:
		if entity.id == id:
			return entity
	return {}

static func _other(slot: String) -> String:
	return "p1" if slot == "p0" else "p0"

static func _point(coords: Array) -> Vector2i:
	return Vector2i(int(coords[0]), int(coords[1]))

static func _in_rect(position: Vector2i, rect: Array) -> bool:
	return position.x >= int(rect[0]) and position.y >= int(rect[1]) and position.x <= int(rect[2]) and position.y <= int(rect[3])

static func _near(first: Vector2i, second: Vector2i, radius: int) -> bool:
	var offset := first - second
	return offset.x * offset.x + offset.y * offset.y <= radius * radius

static func _axis_delta(value: int, speed: int) -> int:
	return signi(value) * ((absi(value) * speed + 50) / 100)

static func _integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value))

static func _exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key: Variant in value:
		if key not in keys:
			return false
	return true

static func _hash(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for character: String in value:
		if character not in "0123456789abcdef":
			return false
	return true

static func _invalid(reason: String) -> Dictionary:
	return {"valid": false, "error": reason}

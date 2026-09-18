class_name AfterYouFirstStepsSimulation
extends RefCounted
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Pure fixed-tick chapter. Source actors stay on fixed land; only B boards a lift.

const Catalog = preload("res://core/first_steps/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const TICK_RATE := 30
const MAX_TICKS := 600
const CURRENT_SIMULATION_VERSION := 5
const LEGACY_SIMULATION_VERSION := 4
const MOVE_PER_TICK := 8
const PLAYER_RADIUS := 12
const RECORD_KEYS := ["schema_version", "simulation_version", "level_id", "level_version", "definition_hash", "stage_id", "stage_version", "checkpoint_hash", "role", "player_slot", "tick_rate", "duration_ticks", "catch_assistance", "actions", "replay_checks", "final_state_hash", "completed", "outcome", "source_recording_hash", "recording_hash"]
const OUTCOME_KEYS := ["supplied_power", "boarded_lift", "reached_loft", "took_seed", "threw_seed", "activated_garden", "caught_seed", "planted_seed"]
const CHECKPOINT_KEYS := ["schema_version", "level_id", "level_version", "definition_hash", "stage_index", "completed_stage_id", "next_stage_id", "players", "mechanisms", "seed", "previous_checkpoint_hash", "a_recording_hash", "b_recording_hash", "checkpoint_hash", "proof"]

var simulation_version := LEGACY_SIMULATION_VERSION
var level: Dictionary = {}
var stage: Dictionary = {}
var role := "a"
var active_slot := "p0"
var first_player_slot := "p0"
var tick := 0
var finished := false
var complete := false
var error := ""
var catch_assistance := true
var _checkpoint: Dictionary = {}
var _prior: Dictionary = {}
var _prior_frames: Array = []
var _players: Dictionary = {}
var _mechanisms: Dictionary = {}
var _seed: Dictionary = {}
var _actions: Array = []
var _checks: Array = []
var _events: Array = []
var _outcome: Dictionary = {}
var _held := {"p0": false, "p1": false}
var _power_active := false
var _power_ticks := 0
var _power_start := -1
var _power_broken := false
var _activation_tick := -1
var _throw_tick := -1
var _land_tick := -1
var _throw_start := Vector2i.ZERO
var _throw_height := 0
var _objective := false

func reset(definition: Dictionary, stage_id: String, checkpoint: Dictionary, prior_a: Dictionary = {}, current_role: String = "a", rules_version: int = LEGACY_SIMULATION_VERSION) -> bool:
	level = {}
	stage = {}
	error = ""
	simulation_version = int(prior_a.get("simulation_version", rules_version)) if current_role == "b" else rules_version
	if simulation_version not in [LEGACY_SIMULATION_VERSION, CURRENT_SIMULATION_VERSION]:
		error = "Unsupported recording version."
		return false
	if not Canonical.same(definition, Catalog.definition()):
		error = PlayerCopy.SIMULATION_2CF4E6F7E5E5
		return false
	var checked := verify_checkpoint(definition, checkpoint)
	if not checked.valid:
		error = checked.error
		return false
	if current_role not in ["a", "b"] or stage_id.is_empty() or stage_id != checkpoint.next_stage_id:
		error = PlayerCopy.SIMULATION_D25439F75F03
		return false
	if current_role == "a" and not prior_a.is_empty():
		error = PlayerCopy.SIMULATION_25877EDFE987
		return false
	if current_role == "b":
		var prior_check := _verify_raw(definition, prior_a, checkpoint, {})
		if not prior_check.valid or prior_a.get("role") != "a" or not prior_check.get("snapshot", {}).get("can_commit", false):
			error = PlayerCopy.SIMULATION_2FF9A2F1A1D9
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
	_mechanisms = checkpoint.mechanisms.duplicate(true)
	_seed = checkpoint.seed.duplicate(true)
	_actions = []
	_checks = []
	_events = []
	_outcome = {}
	for key: String in OUTCOME_KEYS: _outcome[key] = false
	_held = {"p0": false, "p1": false}
	_power_active = false
	_power_ticks = 0
	_power_start = -1
	_power_broken = false
	_activation_tick = -1
	_throw_tick = -1
	_land_tick = -1
	_throw_start = Vector2i.ZERO
	_throw_height = 0
	_objective = false
	tick = 0
	finished = false
	complete = false
	error = ""

func step(input: Dictionary = {}) -> Dictionary:
	if finished or not error.is_empty() or level.is_empty(): return snapshot()
	if not _valid_input(input):
		error = "Unsupported control input."
		return snapshot()
	_events = []
	var frame := quantize_input(input)
	_append_frame(frame)
	var source: Dictionary = frame if role == "a" else quantize_input(_prior_frames[tick]) if tick < _prior_frames.size() else {"x": 0, "z": 0, "action": false}
	var later: Dictionary = frame if role == "b" else {"x": 0, "z": 0, "action": false}
	# Source movement never uses the moving lift, so B cannot invalidate its path.
	_move(first_player_slot, source)
	if role == "b": _move(_other(first_player_slot), later)
	var source_pressed: bool = bool(source.action) and not _held[first_player_slot]
	var later_pressed: bool = bool(later.action) and not _held[_other(first_player_slot)]
	_held[first_player_slot] = source.action
	_held[_other(first_player_slot)] = later.action
	if stage.id == "a-little-lift":
		_update_lift()
	elif source_pressed:
		_interact_source()
	if stage.id == "a-place-to-grow":
		_update_garden()
		_update_seed()
		if role == "b": _catch(later_pressed)
	if role == "b" and later_pressed: _interact_later()
	tick += 1
	if role == "b" and _objective and tick >= int(_prior.duration_ticks):
		complete = true
		finished = true
		_events.append("stage_complete")
	if tick >= MAX_TICKS:
		finished = true
		_events.append("turn_finished")
	if tick % TICK_RATE == 0 or finished: _checks.append({"tick": tick, "state_hash": state_hash()})
	return snapshot()

func can_commit() -> bool:
	if level.is_empty() or not error.is_empty() or tick == 0: return false
	if role == "b": return complete
	if stage.id == "a-little-lift":
		return _outcome.supplied_power and _power_active and not _power_broken and _lift_route_has_time()
	return _outcome.took_seed and _outcome.threw_seed and _outcome.activated_garden and _throw_tick + _seed_finish_budget() <= MAX_TICKS and _activation_tick + int(level.handoff_grace_ticks) <= MAX_TICKS

func commit_reason() -> String:
	if not error.is_empty(): return error
	if level.is_empty(): return PlayerCopy.SIMULATION_A09C0D915904
	if can_commit(): return ""
	if role == "b": return PlayerCopy.SIMULATION_B83D3803E173 if stage.id == "a-little-lift" else PlayerCopy.SIMULATION_1B83F3A11A21
	if stage.id == "a-little-lift":
		if _power_broken: return PlayerCopy.SIMULATION_74E02FD5DC83
		if _power_start >= 0 and not _lift_route_has_time(): return PlayerCopy.SIMULATION_02F515A42F01
		if tick + _lift_finish_budget() > MAX_TICKS and not _outcome.supplied_power: return PlayerCopy.SIMULATION_BAF2F1758F38
		return PlayerCopy.SIMULATION_1FDD3AD574B2
	if not _outcome.took_seed: return PlayerCopy.SIMULATION_437305DD3F4C
	if not _outcome.threw_seed: return PlayerCopy.SIMULATION_A59358ABB196
	if _outcome.activated_garden: return PlayerCopy.SIMULATION_C440D6936B64
	return PlayerCopy.SIMULATION_7D43C574809B

func snapshot() -> Dictionary:
	if level.is_empty(): return {"error": error, "can_commit": false, "finished": false, "complete": false}
	var players := _players.duplicate(true)
	for slot: String in players:
		players[slot].merge({"ghost": role == "b" and slot == first_player_slot, "holding": _seed.status == "held" and _seed.owner == slot})
	return {"schema_version": 4, "stage_id": stage.id, "role": role, "active_slot": active_slot, "first_player_slot": first_player_slot,
		"tick": tick, "time_seconds": float(tick) / TICK_RATE, "duration_ticks": MAX_TICKS, "complete": complete, "finished": finished,
		"can_commit": can_commit(), "commit_reason": commit_reason(), "error": error, "message": str(stage.get("hint_" + role, "")),
		"players": players, "mechanisms": _mechanisms.duplicate(true), "seed": _seed.duplicate(true),
		"controls": {"lift-power": _power_active, "garden-control": _mechanisms.garden_open},
		"events": _events.duplicate(), "outcome": _outcome.duplicate(), "context_action": context_action()}

func context_action() -> Dictionary:
	if level.is_empty() or finished or not error.is_empty(): return _action("none", "Action", false, "")
	if stage.id == "a-little-lift":
		if role == "a": return _action("hold_power", PlayerCopy.SIMULATION_90AC50A8FD85, false, "lift-power")
		return _action("open_loft", "Ring bell", _can_open_loft(), "loft-bell")
	if role == "a":
		if not _outcome.took_seed: return _action("take", "Take seed", _can_take(), stage.pedestal_id)
		if not _outcome.threw_seed: return _action("throw", "Throw seed", _can_throw(), stage.throw_control)
		return _action("activate", PlayerCopy.SIMULATION_318F07A83ABA, false, stage.garden_control)
	if _seed.status == "held" and _seed.owner == active_slot:
		return _action("plant", "Plant seed", _can_plant(), stage.destination)
	return _action("catch", "Catch seed", _catch_possible(), "seed")

func _move(slot: String, frame: Dictionary) -> void:
	var origin := _position(slot)
	var speed := 6 if int(frame.x) != 0 and int(frame.z) != 0 else MOVE_PER_TICK
	var delta := Vector2i(_axis_delta(int(frame.x), speed), _axis_delta(int(frame.z), speed))
	var destination := origin
	for change: Vector2i in [delta, Vector2i(delta.x, 0), Vector2i(0, delta.y)]:
		if _swept(slot, origin, change):
			destination = origin + change
			break
	var height := int(_players[slot].height)
	_players[slot] = {"x": destination.x, "z": destination.y, "height": height, "surface_id": _surface_at(destination, height, slot)}

func walkable_at(x: int, z: int, slot: String = "") -> bool:
	if level.is_empty(): return false
	var checked_slot := active_slot if slot.is_empty() else slot
	if not _players.has(checked_slot): return false
	var height := int(_players[checked_slot].height)
	for offset: Vector2i in [Vector2i.ZERO, Vector2i(-PLAYER_RADIUS, -PLAYER_RADIUS), Vector2i(PLAYER_RADIUS, -PLAYER_RADIUS), Vector2i(-PLAYER_RADIUS, PLAYER_RADIUS), Vector2i(PLAYER_RADIUS, PLAYER_RADIUS)]:
		if _surface_at(Vector2i(x, z) + offset, height, checked_slot).is_empty(): return false
	return true

func _surface_at(position: Vector2i, height: int, slot: String) -> String:
	for island: Dictionary in level.islands:
		if int(island.height_cm) == height and _in_rect(position, island.rect_cm): return island.id
	# Stage one reserves the moving lift for B. In stage two the verified upper
	# lift is permanently fixed, so a source who ended there can walk off it.
	if slot == first_player_slot and not (stage.id == "a-place-to-grow" and _mechanisms.lift.phase == "upper"): return ""
	if int(_mechanisms.lift.height_cm) == height and _in_rect(position, level.lift.rect_cm): return level.lift.id
	return ""

func _swept(slot: String, origin: Vector2i, delta: Vector2i) -> bool:
	var count := maxi(absi(delta.x), absi(delta.y))
	for index in range(1, count + 1):
		var candidate := origin + Vector2i(delta.x * index / count, delta.y * index / count)
		if not walkable_at(candidate.x, candidate.y, slot): return false
	return true

func _update_lift() -> void:
	_power_active = _on(first_player_slot, _entity(level.controls, stage.power_control))
	if _power_active:
		if _power_start < 0: _power_start = tick
		_power_ticks += 1
		if _power_ticks >= int(stage.minimum_power_ticks): _outcome.supplied_power = true
	elif _power_start >= 0 and simulation_version == LEGACY_SIMULATION_VERSION:
		_power_broken = true
		_power_ticks = 0
	if role != "b" or not _power_active or _power_broken: return
	var later := _other(first_player_slot)
	var lift: Dictionary = _mechanisms.lift
	if lift.phase == "lower" and _fully_in_lift(_position(later)):
		lift.phase = "rising"
		lift.boarded_slot = later
		_outcome.boarded_lift = true
		_events.append("lift_boarded")
	if lift.phase == "rising":
		lift.progress_ticks += 1
		lift.height_cm = int(level.lift.bottom_height_cm) + (int(level.lift.top_height_cm) - int(level.lift.bottom_height_cm)) * int(lift.progress_ticks) / int(level.lift.rise_ticks)
		_players[later].height = int(lift.height_cm)
		_players[later].surface_id = level.lift.id
		if int(lift.progress_ticks) == int(level.lift.rise_ticks):
			lift.phase = "upper"
			_events.append("lift_arrived")

func _fully_in_lift(position: Vector2i) -> bool:
	var rect: Array = level.lift.rect_cm
	return position.x - PLAYER_RADIUS > int(rect[0]) and position.x + PLAYER_RADIUS < int(rect[2]) and position.y - PLAYER_RADIUS > int(rect[1]) and position.y + PLAYER_RADIUS < int(rect[3])

func _lift_finish_budget() -> int:
	var receiver: Dictionary = _checkpoint.players[_other(first_player_slot)]
	var boarding := _point(level.lift.boarding_cm)
	var bell := _point(_entity(level.goals, stage.goal_id).position_cm)
	return _walk_ticks(Vector2i(receiver.x, receiver.z), boarding) + int(level.lift.rise_ticks) + _walk_ticks(boarding, bell) + 3 + int(level.handoff_grace_ticks)

func _lift_route_has_time() -> bool:
	if simulation_version == LEGACY_SIMULATION_VERSION:
		return _power_start + _lift_finish_budget() <= MAX_TICKS
	# Count powered time only; the held final pose supplies the remaining tail.
	return _power_ticks + MAX_TICKS - tick >= _lift_finish_budget()

func _can_open_loft() -> bool:
	return role == "b" and _outcome.boarded_lift and _mechanisms.lift.phase == "upper" and _on(active_slot, _entity(level.goals, stage.goal_id))

func _can_take() -> bool:
	return _mechanisms.loft_open and not _outcome.took_seed and _seed.status == "pedestal" and _on(first_player_slot, _entity(level.sockets, stage.pedestal_id))

func _can_throw() -> bool:
	return _seed.status == "held" and _seed.owner == first_player_slot and not _outcome.threw_seed and _on(first_player_slot, _entity(level.controls, stage.throw_control)) and tick + _seed_finish_budget() <= MAX_TICKS

func _seed_finish_budget() -> int:
	# Authored unobstructed shore route: the full flight, then landing to garden.
	# Upper activation travel is shorter, but is checked explicitly before commit.
	return int(stage.flight_ticks) + _walk_ticks(_point(stage.landing_cm), _point(_entity(level.sockets, stage.destination).position_cm)) + 3 + int(level.handoff_grace_ticks)

func _interact_source() -> void:
	if _can_take():
		_seed.merge({"status": "held", "owner": first_player_slot, "socket_id": ""}, true)
		_outcome.took_seed = true
		_events.append("seed_taken")
	elif _can_throw():
		_throw_start = _position(first_player_slot)
		_throw_height = int(_players[first_player_slot].height) + 75
		_throw_tick = tick
		_seed.merge({"status": "flying", "owner": "", "socket_id": ""}, true)
		_outcome.threw_seed = true
		_events.append("seed_thrown")

func _update_garden() -> void:
	if _outcome.threw_seed and not _mechanisms.garden_open and _on(first_player_slot, _entity(level.controls, stage.garden_control)):
		_mechanisms.garden_open = true
		_activation_tick = tick
		_outcome.activated_garden = true
		_events.append("garden_opened")

func _update_seed() -> void:
	if _seed.status == "held":
		var owner: Dictionary = _players[_seed.owner]
		_seed.merge({"x": owner.x, "z": owner.z, "height": int(owner.height) + 75}, true)
	elif _seed.status == "flying":
		var duration := int(stage.flight_ticks)
		var elapsed := mini(tick - _throw_tick, duration)
		var target := _point(stage.landing_cm)
		var pos := _throw_start + Vector2i((target.x - _throw_start.x) * elapsed / duration, (target.y - _throw_start.y) * elapsed / duration)
		var height := _throw_height + (35 - _throw_height) * elapsed / duration + 4 * 150 * elapsed * (duration - elapsed) / (duration * duration)
		_seed.merge({"x": pos.x, "z": pos.y, "height": height}, true)
		if elapsed == duration:
			_seed.status = "waiting"
			_land_tick = tick
			_events.append("seed_landed")
	elif _seed.status == "waiting" and tick - _land_tick >= int(level.seed_wait_ticks):
		_seed.status = "missed"
		_events.append("seed_missed")

func _catch_possible() -> bool:
	if role != "b" or stage.id != "a-place-to-grow" or _seed.status not in ["flying", "waiting"]: return false
	if _seed.status == "flying" and tick - _throw_tick < int(stage.flight_ticks) - 15: return false
	var receiver: Dictionary = _players[active_slot]
	return receiver.surface_id == stage.landing_surface and int(_seed.height) - int(receiver.height) <= 140 and _near(_position(active_slot), Vector2i(_seed.x, _seed.z), int(level.catch_radius))

func _catch(pressed: bool) -> void:
	if not (catch_assistance or pressed) or not _catch_possible(): return
	_seed.merge({"status": "held", "owner": active_slot, "socket_id": "", "height": int(_players[active_slot].height) + 75}, true)
	_outcome.caught_seed = true
	_events.append("seed_caught")

func _can_plant() -> bool:
	return role == "b" and _mechanisms.garden_open and _seed.status == "held" and _seed.owner == active_slot and _on(active_slot, _entity(level.sockets, stage.destination))

func _interact_later() -> void:
	if stage.id == "a-little-lift":
		if _can_open_loft():
			_mechanisms.loft_open = true
			_outcome.reached_loft = true
			_objective = true
			_events.append("loft_opened")
	elif _can_plant():
		var socket := _entity(level.sockets, stage.destination)
		_seed.merge({"status": "planted", "owner": "", "socket_id": socket.id, "x": socket.position_cm[0], "z": socket.position_cm[1], "height": socket.seed_height_cm}, true)
		_outcome.planted_seed = true
		_objective = true
		_events.append("garden_bloomed")

func _on(slot: String, entity: Dictionary) -> bool:
	return not entity.is_empty() and _players[slot].surface_id == entity.surface_id and _near(_position(slot), _point(entity.position_cm), int(entity.radius_cm))

func _position(slot: String) -> Vector2i:
	return Vector2i(_players[slot].x, _players[slot].z)

func export_recording() -> Dictionary:
	if tick == 0 or level.is_empty(): return {}
	var checks := _checks.duplicate(true)
	if checks.is_empty() or int(checks[-1].tick) != tick: checks.append({"tick": tick, "state_hash": state_hash()})
	var record := {"schema_version": 4, "simulation_version": simulation_version, "level_id": level.id, "level_version": level.version,
		"definition_hash": Canonical.digest(level), "stage_id": stage.id, "stage_version": stage.version,
		"checkpoint_hash": _checkpoint.checkpoint_hash, "role": role, "player_slot": active_slot, "tick_rate": TICK_RATE,
		"duration_ticks": tick, "catch_assistance": catch_assistance, "actions": _actions.duplicate(true), "replay_checks": checks,
		"final_state_hash": state_hash(), "completed": complete, "outcome": _outcome.duplicate(),
		"source_recording_hash": str(_prior.get("recording_hash", "")) if role == "b" else ""}
	record["recording_hash"] = recording_hash(record)
	return record

func state_hash() -> String:
	return Canonical.digest({"simulation_version": simulation_version, "definition_hash": Canonical.digest(level), "stage_id": stage.id, "checkpoint_hash": _checkpoint.checkpoint_hash,
		"role": role, "tick": tick, "players": _players, "mechanisms": _mechanisms, "seed": _seed, "held": _held,
		"power_active": _power_active, "power_ticks": _power_ticks, "power_start": _power_start, "power_broken": _power_broken,
		"activation_tick": _activation_tick, "throw_tick": _throw_tick, "land_tick": _land_tick,
		"throw_start": [_throw_start.x, _throw_start.y], "throw_height": _throw_height, "outcome": _outcome, "objective": _objective, "complete": complete})

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

static func _action(id: String, label: String, enabled: bool, target: String) -> Dictionary:
	return {"id": id, "label": label, "enabled": enabled, "target_id": target}

static func _entity(entities: Array, id: String) -> Dictionary:
	for item: Dictionary in entities:
		if item.id == id: return item
	return {}

static func _other(slot: String) -> String:
	return "p1" if slot == "p0" else "p0"

static func _point(coords: Array) -> Vector2i:
	return Vector2i(coords[0], coords[1])

static func _in_rect(point: Vector2i, rect: Array) -> bool:
	return point.x >= int(rect[0]) and point.x <= int(rect[2]) and point.y >= int(rect[1]) and point.y <= int(rect[3])

static func _near(first: Vector2i, second: Vector2i, radius: int) -> bool:
	return first.distance_squared_to(second) <= radius * radius

static func _walk_ticks(first: Vector2i, second: Vector2i) -> int:
	return ceili(float(absi(second.x - first.x)) / MOVE_PER_TICK) + ceili(float(absi(second.y - first.y)) / MOVE_PER_TICK)

static func _axis_delta(value: int, speed: int) -> int:
	return roundi(float(value * speed) / 100.0)

static func quantize_input(input: Dictionary) -> Dictionary:
	return {"x": roundi(clampf(float(input.get("move_x", 0.0)), -1.0, 1.0) * 100.0), "z": roundi(clampf(float(input.get("move_z", 0.0)), -1.0, 1.0) * 100.0), "action": bool(input.get("interact", false))}

static func _valid_input(input: Dictionary) -> bool:
	for key: Variant in input:
		if key not in ["move_x", "move_z", "interact"]: return false
	for key: String in ["move_x", "move_z"]:
		var value: Variant = input.get(key, 0.0)
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)) or absf(float(value)) > 1.0: return false
	return input.get("interact", false) is bool

static func verify_recording(definition: Dictionary, recording: Dictionary, checkpoint: Dictionary, prior_a: Dictionary = {}) -> Dictionary:
	var check := verify_checkpoint(definition, checkpoint)
	return _verify_raw(definition, recording, checkpoint, prior_a) if check.valid else check

static func _verify_raw(definition: Dictionary, recording: Dictionary, checkpoint: Dictionary, prior_a: Dictionary) -> Dictionary:
	var reason := recording_error(definition, recording, checkpoint)
	if not reason.is_empty():
		return _invalid(reason)
	if recording.role == "b":
		if prior_a.get("role") != "a" or recording.source_recording_hash != prior_a.get("recording_hash", ""):
			return _invalid(PlayerCopy.SIMULATION_BE77C2247381)
		var first_check := _verify_raw(definition, prior_a, checkpoint, {})
		if not first_check.valid or not first_check.snapshot.can_commit:
			return _invalid(PlayerCopy.SIMULATION_A8BC77003BC1)
	elif not prior_a.is_empty() or not str(recording.source_recording_hash).is_empty():
		return _invalid(PlayerCopy.SIMULATION_9179578531E6)
	var simulation := AfterYouFirstStepsSimulation.new()
	simulation.simulation_version = int(recording.simulation_version)
	if recording.role == "b" and recording.simulation_version != prior_a.simulation_version:
		return _invalid("Unsupported recording version.")
	simulation.catch_assistance = recording.catch_assistance
	simulation._reset_trusted(definition, recording.stage_id, checkpoint, prior_a, recording.role)
	for input: Dictionary in expand_recording_inputs(recording):
		if simulation.finished:
			return _invalid(PlayerCopy.SIMULATION_88FACE52603B)
		simulation.step(input)
	if not Canonical.same(simulation.export_recording(), recording):
		return _invalid(PlayerCopy.SIMULATION_A67E5027F988)
	return {"valid": true, "error": "", "snapshot": simulation.snapshot()}

static func recording_error(definition: Dictionary, record: Dictionary, checkpoint: Dictionary) -> String:
	if not _exact_keys(record, RECORD_KEYS):
		return PlayerCopy.SIMULATION_4776AA2609E9
	for key: String in ["schema_version", "simulation_version", "level_version", "stage_version"]:
		if not _integer(record[key]) or (int(record[key]) not in [LEGACY_SIMULATION_VERSION, CURRENT_SIMULATION_VERSION] if key == "simulation_version" else int(record[key]) != (4 if key == "schema_version" else 1)):
			return "Unsupported recording version."
	if record.level_id != definition.id or record.definition_hash != Canonical.digest(definition) or record.checkpoint_hash != checkpoint.get("checkpoint_hash") or record.stage_id != checkpoint.get("next_stage_id"):
		return PlayerCopy.SIMULATION_121F2E09E2CF
	var selected := stage_by_id(definition, str(record.stage_id))
	if selected.is_empty() or record.role not in ["a", "b"]:
		return PlayerCopy.SIMULATION_4AE548F3FB8A
	var expected_slot: String = selected.first_player_slot if record.role == "a" else _other(selected.first_player_slot)
	if record.player_slot != expected_slot:
		return PlayerCopy.SIMULATION_4CE2B3141FDF
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
			return PlayerCopy.SIMULATION_6AC6061A8508
	if total != int(record.duration_ticks):
		return "Action duration mismatch."
	if not record.replay_checks is Array or record.replay_checks.is_empty() or record.replay_checks.size() > 21:
		return PlayerCopy.SIMULATION_9C0F9227F64E
	var last := 0
	for item: Variant in record.replay_checks:
		if not item is Dictionary or not _exact_keys(item, ["tick", "state_hash"]) or not _integer(item.tick) or int(item.tick) <= last or int(item.tick) > total or not _hash(item.state_hash):
			return PlayerCopy.SIMULATION_6F52934C1B37
		last = int(item.tick)
	if last != total or recording_hash(record) != record.recording_hash:
		return PlayerCopy.SIMULATION_66BC3C3B61BA
	return ""

static func verify_checkpoint(definition: Dictionary, checkpoint: Dictionary) -> Dictionary:
	if not Canonical.same(definition, Catalog.definition()):
		return _invalid(PlayerCopy.SIMULATION_F3206ED9E156)
	return _verify_checkpoint(definition, checkpoint, 0)

static func _verify_checkpoint(definition: Dictionary, checkpoint: Dictionary, depth: int) -> Dictionary:
	if depth > 2 or not _exact_keys(checkpoint, CHECKPOINT_KEYS) or not _integer(checkpoint.get("stage_index")) or int(checkpoint.stage_index) < 0 or int(checkpoint.stage_index) > definition.stages.size():
		return _invalid("Malformed stage checkpoint.")
	if checkpoint.stage_index == 0:
		return {"valid": true, "error": ""} if Canonical.same(checkpoint, Catalog.initial_checkpoint()) else _invalid(PlayerCopy.SIMULATION_05B80A2AF3FA)
	if not checkpoint.proof is Dictionary or not _exact_keys(checkpoint.proof, ["checkpoint", "a", "b"]):
		return _invalid(PlayerCopy.SIMULATION_AD0A36241E3B)
	var proof: Dictionary = checkpoint.proof
	if not proof.checkpoint is Dictionary or not proof.a is Dictionary or not proof.b is Dictionary or not _integer(proof.checkpoint.get("stage_index")) or int(proof.checkpoint.stage_index) != int(checkpoint.stage_index) - 1:
		return _invalid(PlayerCopy.SIMULATION_BA1505271203)
	var prior_check := _verify_checkpoint(definition, proof.checkpoint, depth + 1)
	if not prior_check.valid:
		return prior_check
	var pair := _verify_pair(definition, proof.checkpoint, proof.a, proof.b)
	if not pair.valid:
		return pair
	var derived := _build_checkpoint(definition, proof.checkpoint, proof.a, proof.b, pair.snapshot)
	return {"valid": true, "error": ""} if Canonical.same(checkpoint, derived) else _invalid(PlayerCopy.SIMULATION_CEEAFF7EBFB9)

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
		return _invalid(PlayerCopy.SIMULATION_02DA845B9116)
	var check := _verify_raw(definition, second, previous, first)
	if not check.valid or not check.get("snapshot", {}).get("complete", false):
		return _invalid(PlayerCopy.SIMULATION_B38183442A75)
	return check

static func _build_checkpoint(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary, state: Dictionary) -> Dictionary:
	var index := int(previous.stage_index) + 1
	var players: Dictionary = {}
	for slot: String in ["p0", "p1"]:
		players[slot] = {"x": int(state.players[slot].x), "z": int(state.players[slot].z), "height": int(state.players[slot].height), "surface_id": str(state.players[slot].surface_id)}
	var checkpoint := {
		"schema_version": 4, "level_id": definition.id, "level_version": definition.version,
		"definition_hash": Canonical.digest(definition), "stage_index": index,
		"completed_stage_id": str(second.stage_id), "next_stage_id": str(definition.stages[index].id) if index < definition.stages.size() else "",
		"players": players, "mechanisms": state.mechanisms.duplicate(true),
		"seed": state.seed.duplicate(true),
		"previous_checkpoint_hash": previous.checkpoint_hash, "a_recording_hash": first.recording_hash, "b_recording_hash": second.recording_hash,
		"proof": {"checkpoint": previous.duplicate(true), "a": first.duplicate(true), "b": second.duplicate(true)}
	}
	checkpoint["checkpoint_hash"] = Catalog.checkpoint_hash(checkpoint)
	return checkpoint

static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size(): return false
	for key: String in expected:
		if not value.has(key): return false
	return true

static func _integer(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value))

static func _hash(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for character in value:
		if character not in "0123456789abcdef": return false
	return true

static func _invalid(reason: String) -> Dictionary:
	return {"valid": false, "error": reason}

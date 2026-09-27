class_name AfterYouCooperativeSimulation
extends RefCounted
## One fixed-tick ruleset for authored switches, stairs, drops and rolling props.
## The earlier turn runs in its own simulation: later controls cannot rewrite it.
const Catalog = preload("res://core/cooperative/stage_catalog.gd")
const Navigation = preload("res://core/cooperative/navigation.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Controls = preload("res://core/first_steps/simulation.gd")
const TICK_RATE := 30
const MAX_TICKS := 900
const MOVE_PER_TICK := 8
const PLAYER_RADIUS := 12
const CURRENT_SIMULATION_VERSION := 6
const RECORD_KEYS := Controls.RECORD_KEYS
const OUTCOME_KEYS := ["source_ready", "objective_complete"]
const CHECKPOINT_KEYS := ["schema_version", "level_id", "level_version", "definition_hash", "stage_index", "completed_stage_id", "next_stage_id", "players", "mechanisms", "previous_checkpoint_hash", "a_recording_hash", "b_recording_hash", "checkpoint_hash", "proof"]

var simulation_version := CURRENT_SIMULATION_VERSION
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
var _players: Dictionary = {}
var _mechanisms: Dictionary = {}
var _routes: Dictionary = {}
var _actions: Array = []
var _checks: Array = []
var _events: Array = []
var _source: RefCounted
var _prior_frames: Array = []
var _held := false
var _hold_ticks := 0
var _hold_start := -1
var _offer_tick := -1
var _claimed := false
var _objective := false

func reset(definition: Dictionary, stage_id: String, checkpoint: Dictionary, prior_a: Dictionary = {}, current_role: String = "a") -> bool:
	level = {}
	stage = {}
	error = ""
	var checked := verify_checkpoint(definition, checkpoint)
	if not checked.valid:
		error = checked.error
		return false
	if current_role not in ["a", "b"] or stage_id.is_empty() or stage_id != checkpoint.next_stage_id:
		error = "This turn does not follow the checkpoint."
		return false
	if current_role == "a" and not prior_a.is_empty():
		error = "The first turn cannot contain a partner recording."
		return false
	if current_role == "b":
		var prior_check := _verify_raw(definition, prior_a, checkpoint, {})
		if not prior_check.valid or prior_a.get("role") != "a" or not prior_check.get("snapshot", {}).get("can_commit", false):
			error = "The partner recording is not ready."
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
	_players = checkpoint.players.duplicate(true)
	_mechanisms = checkpoint.mechanisms.duplicate(true)
	_routes = {}
	_actions = []
	_checks = []
	_events = []
	_held = false
	_hold_ticks = 0
	_hold_start = -1
	_offer_tick = -1
	_claimed = false
	_objective = false
	tick = 0
	finished = false
	complete = false
	error = ""
	_prior_frames = expand_recording_inputs(prior_a)
	_source = null
	if role == "b":
		_source = AfterYouCooperativeSimulation.new()
		_source.catch_assistance = bool(prior_a.catch_assistance)
		_source._reset_trusted(definition, stage_id, checkpoint, {}, "a")
	_refresh_routes()

func step(input: Dictionary = {}) -> Dictionary:
	if finished or not error.is_empty() or level.is_empty(): return snapshot()
	if not Controls._valid_input(input):
		error = "Unsupported control input."
		return snapshot()
	_events = []
	var previous_routes := _routes.duplicate()
	var frame := quantize_input(input)
	_append_frame(frame)
	if role == "b": _advance_source()
	_refresh_routes()
	if not _objective: _move(frame)
	_refresh_routes()
	if not _objective and bool(frame.action) and not _held: _interact()
	_held = bool(frame.action)
	_refresh_routes()
	for route_id: String in _routes:
		if _routes[route_id] and not bool(previous_routes.get(route_id, false)): _events.append("bridge_opened:" + route_id)
	if role == "a": _update_source_readiness()
	if role == "b" and stage.goal_policy.kind == "ball_home": _check_ball_home()
	tick += 1
	if role == "b" and _objective and tick >= int(_prior.duration_ticks):
		complete = true
		finished = true
		for route_id: String in _routes:
			if _routes[route_id] and route_id not in _mechanisms.latched_bridges: _mechanisms.latched_bridges.append(route_id)
		_mechanisms.latched_bridges.sort()
		_events.append("stage_complete")
	if tick >= MAX_TICKS:
		finished = true
		_events.append("turn_finished")
	if tick % TICK_RATE == 0 or finished: _checks.append({"tick":tick,"state_hash":state_hash()})
	return snapshot()

func _advance_source() -> void:
	if tick < _prior_frames.size(): _source.step(_prior_frames[tick])
	_players[first_player_slot] = _source._players[first_player_slot].duplicate(true)
	for lever: Dictionary in stage.get("levers", []):
		if lever.owner_slot == first_player_slot and _source._mechanisms.levers.has(lever.id):
			_mechanisms.levers[lever.id] = _source._mechanisms.levers[lever.id]
	if not _claimed:
		_mechanisms.props = _source._mechanisms.props.duplicate(true)
	_offer_tick = _source._offer_tick
	_hold_ticks = _source._hold_ticks
	_hold_start = _source._hold_start

func _move(frame: Dictionary) -> void:
	var direction := Vector2(float(frame.x), float(frame.z)).limit_length(100.0)
	var delta := Vector2i(roundi(direction.x * MOVE_PER_TICK / 100.0), roundi(direction.y * MOVE_PER_TICK / 100.0))
	if delta == Vector2i.ZERO: return
	var steps := maxi(absi(delta.x), absi(delta.y))
	var walked := Vector2i.ZERO
	for index in range(1, steps + 1):
		var next := Vector2i(roundi(float(delta.x * index) / steps), roundi(float(delta.y * index) / steps))
		var unit := next - walked
		walked = next
		if _try_move(unit): continue
		if unit.x != 0: _try_move(Vector2i(unit.x, 0))
		if unit.y != 0: _try_move(Vector2i(0, unit.y))

func _try_move(delta: Vector2i) -> bool:
	var previous: Dictionary = _players[active_slot]
	var x := int(previous.x) + delta.x
	var z := int(previous.z) + delta.y
	var position := Navigation.at(level, _routes, _mechanisms.levers, previous, x, z, active_slot, PLAYER_RADIUS)
	if position.is_empty(): return false
	var pushed: Dictionary = {}
	for prop: Dictionary in level.get("props", []):
		var ball: Dictionary = _mechanisms.props[prop.id]
		var separation := PLAYER_RADIUS + int(prop.radius_cm)
		if int(position.height) != int(ball.height) or Vector2i(x,z).distance_squared_to(Vector2i(ball.x,ball.z)) >= separation * separation: continue
		if not _can_push(ball): return false
		var moved := Navigation.at(level, _routes, _mechanisms.levers, ball, int(ball.x) + delta.x, int(ball.z) + delta.y, active_slot, int(prop.radius_cm), false)
		if moved.is_empty(): return false
		var replacement := ball.duplicate(true)
		replacement.merge(moved, true)
		pushed[prop.id] = replacement
	for id: String in pushed: _mechanisms.props[id] = pushed[id]
	_players[active_slot] = position
	if int(previous.height) > int(position.height) + 2: _events.append("drop")
	return true

func _can_push(ball: Dictionary) -> bool:
	if ball.status == "fitted" or ball.status == "offered": return false
	if role == "a": return ball.status == "free"
	return _claimed and ball.status == "claimed" and ball.holder_slot == active_slot

func _refresh_routes() -> void:
	for route: Dictionary in level.get("bridges", []) + level.get("stairs", []):
		_routes[route.id] = route.id in _mechanisms.latched_bridges
	for gate: Dictionary in stage.get("gates", []):
		var enabled := true
		for key: String in ["lever_id", "second_lever_id"]:
			if not str(gate.get(key, "")).is_empty(): enabled = enabled and bool(_mechanisms.levers.get(gate[key], false))
		if not str(gate.get("pad_id", "")).is_empty(): enabled = enabled and _pad_active(_entity(stage.pressure_pads, gate.pad_id))
		if not str(gate.get("ball_pad_id", "")).is_empty(): enabled = enabled and _ball_at(_entity(stage.ball_pads, gate.ball_pad_id), str(stage.source_policy.get("prop_id", "")))
		_routes[gate.route_id] = bool(_routes.get(gate.route_id, false)) or enabled

func _pad_active(pad: Dictionary) -> bool:
	return not pad.is_empty() and _near_entity(_players[pad.owner_slot], pad)

func _ball_at(target: Dictionary, prop_id: String) -> bool:
	if target.is_empty() or not _mechanisms.props.has(prop_id): return false
	var prop := _entity(level.props, prop_id)
	var ball: Dictionary = _mechanisms.props[prop_id]
	return _near_entity(ball, target, maxi(0, int(target.radius_cm) - int(prop.radius_cm)))

func _update_source_readiness() -> void:
	var policy: Dictionary = stage.source_policy
	var ready := false
	if policy.kind == "hold_switch": ready = _pad_active(_entity(stage.pressure_pads, policy.pad_id))
	elif policy.kind == "weight_switch": ready = _ball_at(_entity(stage.ball_pads, policy.ball_pad_id), policy.prop_id)
	else: return
	if not str(policy.get("lever_id", "")).is_empty(): ready = ready and bool(_mechanisms.levers.get(policy.lever_id, false))
	if ready:
		if _hold_start < 0: _hold_start = tick
		_hold_ticks += 1
	else:
		_hold_start = -1
		_hold_ticks = 0

func _interact() -> void:
	var action := context_action()
	if not bool(action.enabled): return
	match str(action.id):
		"lever":
			_mechanisms.levers[action.target_id] = not bool(_mechanisms.levers.get(action.target_id, false))
			_events.append("lever")
		"ring":
			_objective = true
			_events.append("bell")
		"offer":
			var ball: Dictionary = _mechanisms.props[stage.source_policy.prop_id]
			ball.status = "offered"
			ball.holder_slot = ""
			ball.socket_id = stage.handoff.id
			_offer_tick = tick
			_events.append("handoff_offer")
		"claim":
			var ball: Dictionary = _mechanisms.props[stage.source_policy.prop_id]
			ball.status = "claimed"
			ball.holder_slot = active_slot
			ball.socket_id = ""
			_claimed = true
			_events.append("handoff_claim")

func context_action() -> Dictionary:
	if level.is_empty(): return _action("", "", false, "")
	var player: Dictionary = _players[active_slot]
	for lever: Dictionary in stage.get("levers", []):
		if lever.owner_slot == active_slot and _near_entity(player, lever):
			return _action("lever", "Pull lever", true, lever.id)
	if role == "b" and stage.goal_policy.kind == "ring" and _near_entity(player, stage.goal):
		return _action("ring", "Ring bell", true, stage.goal.id)
	if stage.source_policy.kind == "offer_ball":
		var ball: Dictionary = _mechanisms.props[stage.source_policy.prop_id]
		if int(player.height) == int(ball.height) and Vector2i(player.x,player.z).distance_squared_to(Vector2i(ball.x,ball.z)) <= 64 * 64:
			if role == "a" and ball.status == "free" and _ball_at(stage.handoff, stage.source_policy.prop_id):
				return _action("offer", "Leave ball", bool(_mechanisms.levers.get(stage.source_policy.lever_id, false)), stage.source_policy.prop_id)
			if role == "b" and ball.status == "offered": return _action("claim", "Take over", true, stage.source_policy.prop_id)
	return _action("", "", false, "")

func _check_ball_home() -> void:
	if not _claimed or not _ball_at(stage.goal, stage.goal_policy.prop_id): return
	var ball: Dictionary = _mechanisms.props[stage.goal_policy.prop_id]
	ball.status = "fitted"
	ball.holder_slot = ""
	ball.socket_id = stage.goal_policy.socket_id
	_objective = true

func source_budget_ticks() -> int:
	if level.is_empty(): return MAX_TICKS
	var route: Array = stage.receiver_route_cm
	var point := Vector2i(_checkpoint.players[_other(first_player_slot)].x, _checkpoint.players[_other(first_player_slot)].z)
	# The receiver may approach an offered prop while the source records its route.
	if stage.source_policy.kind == "offer_ball": point = Vector2i(route[0][0], route[0][1])
	# Turning a ball also needs room to walk around it; the route lists its
	# centreline, so reserve those approach steps as well as button presses.
	var budget := int(stage.get("receiver_action_ticks", 0)) + 40
	for coords: Array in route:
		var next := Vector2i(coords[0],coords[1])
		budget += ceili(float(absi(next.x - point.x)) / MOVE_PER_TICK) + ceili(float(absi(next.y - point.y)) / MOVE_PER_TICK)
		point = next
	return budget

func can_commit() -> bool:
	if level.is_empty() or not error.is_empty() or tick == 0: return false
	if role == "b": return complete
	if stage.source_policy.kind == "offer_ball":
		return _offer_tick >= 0 and _offer_tick + source_budget_ticks() < MAX_TICKS and bool(_mechanisms.levers.get(stage.source_policy.lever_id, false))
	return _hold_ticks >= int(stage.source_policy.minimum_hold_ticks) and _hold_start >= 0 and _hold_start + source_budget_ticks() < MAX_TICKS

func commit_reason() -> String:
	if not error.is_empty(): return error
	if can_commit(): return ""
	if level.is_empty(): return "Choose a chapter."
	if role == "b": return "Finish the route with your partner."
	var ready_tick := _offer_tick if stage.source_policy.kind == "offer_ball" else _hold_start
	if ready_tick >= 0 and ready_tick + source_budget_ticks() >= MAX_TICKS: return "Try again with more time left for your partner."
	if stage.source_policy.kind == "offer_ball": return "Leave the ball where your partner can take over."
	return "Keep the crossing ready for your partner."

func snapshot() -> Dictionary:
	if level.is_empty(): return {"error":error,"can_commit":false,"finished":false,"complete":false}
	var players := _players.duplicate(true)
	for slot: String in players: players[slot].merge({"ghost":role == "b" and slot == first_player_slot,"holding":false})
	var pads: Dictionary = {}
	for pad: Dictionary in stage.get("pressure_pads", []): pads[pad.id] = _pad_active(pad)
	for pad: Dictionary in stage.get("ball_pads", []): pads[pad.id] = _ball_at(pad, pad.prop_id)
	return {"schema_version":6,"stage_id":stage.id,"role":role,"active_slot":active_slot,"first_player_slot":first_player_slot,
		"tick":tick,"time_seconds":float(tick)/TICK_RATE,"duration_ticks":MAX_TICKS,"complete":complete,"finished":finished,"can_commit":can_commit(),
		"commit_reason":commit_reason(),"error":error,"message":str(stage.get("hint_"+role,"")),"players":players,"mechanisms":_mechanisms.duplicate(true),
		"bridges":_routes.duplicate(),"props":_mechanisms.props.duplicate(true),"levers":_mechanisms.levers.duplicate(),"hold_pads":pads,
		"objective_done":_objective,"route_progress":{"kept_bridges":_mechanisms.latched_bridges.duplicate()},"source_hold_ticks":_hold_ticks,"offer_tick":_offer_tick,
		"outcome":_outcome(),"events":_events.duplicate(),"context_action":context_action(),"objective_display":_objective_display(),"optics":{"segments":[],"signals":{}},"beacon":_objective}

func _objective_display() -> Dictionary:
	if role == "a":
		if stage.source_policy.kind == "offer_ball":
			return {"label":"Ball handoff","current":1 if can_commit() else 0,"required":1}
		return {"label":"Crossing ready","current":1 if can_commit() else 0,"required":1}
	return {"label":"Ball home" if stage.goal_policy.kind == "ball_home" else "Bell","current":1 if _objective else 0,"required":1}

func _outcome() -> Dictionary:
	return {"source_ready":can_commit() if role == "a" else bool(_prior.get("outcome", {}).get("source_ready", false)),"objective_complete":complete}

func walkable_at(x: int, z: int, slot: String = "") -> bool:
	var selected := active_slot if slot.is_empty() else slot
	return not Navigation.at(level, _routes, _mechanisms.levers, _players[selected], x, z, selected, PLAYER_RADIUS).is_empty()

func export_recording() -> Dictionary:
	if tick == 0 or level.is_empty(): return {}
	var checks := _checks.duplicate(true)
	if checks.is_empty() or int(checks[-1].tick) != tick: checks.append({"tick":tick,"state_hash":state_hash()})
	var record := {"schema_version":6,"simulation_version":6,"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),
		"stage_id":stage.id,"stage_version":stage.version,"checkpoint_hash":_checkpoint.checkpoint_hash,"role":role,"player_slot":active_slot,"tick_rate":TICK_RATE,
		"duration_ticks":tick,"catch_assistance":catch_assistance,"actions":_actions.duplicate(true),"replay_checks":checks,"final_state_hash":state_hash(),
		"completed":complete,"outcome":_outcome(),"source_recording_hash":str(_prior.get("recording_hash", "")) if role == "b" else ""}
	record["recording_hash"] = recording_hash(record)
	return record

func state_hash() -> String:
	return Canonical.digest({"simulation_version":6,"definition_hash":Canonical.digest(level),"stage_id":stage.id,"checkpoint_hash":_checkpoint.checkpoint_hash,
		"role":role,"tick":tick,"players":_players,"mechanisms":_mechanisms,"routes":_routes,"held":_held,"hold_ticks":_hold_ticks,"hold_start":_hold_start,
		"offer_tick":_offer_tick,"claimed":_claimed,"objective":_objective,"complete":complete,"outcome":_outcome(),"source_recording_hash":str(_prior.get("recording_hash", ""))})

func _append_frame(frame: Dictionary) -> void:
	if not _actions.is_empty():
		var last: Dictionary = _actions[-1]
		if last.x == frame.x and last.z == frame.z and last.action == frame.action:
			last.ticks += 1
			return
	_actions.append({"ticks":1,"x":frame.x,"z":frame.z,"action":frame.action})

static func stage_by_id(definition: Dictionary, stage_id: String) -> Dictionary:
	return _entity(definition.get("stages", []), stage_id).duplicate(true)

static func quantize_input(input: Dictionary) -> Dictionary:
	return Controls.quantize_input(input)

static func expand_recording_inputs(recording: Dictionary) -> Array:
	return Controls.expand_recording_inputs(recording)

static func recording_hash(recording: Dictionary) -> String:
	return Controls.recording_hash(recording)

static func _entity(entities: Array, id: String) -> Dictionary:
	for item: Dictionary in entities:
		if item.id == id: return item
	return {}

static func _other(slot: String) -> String:
	return "p1" if slot == "p0" else "p0"

static func _near_entity(player: Dictionary, target: Dictionary, radius: int = -1) -> bool:
	return player.surface_id == target.surface_id and Vector2i(player.x,player.z).distance_squared_to(Vector2i(target.position_cm[0],target.position_cm[1])) <= (int(target.radius_cm) if radius < 0 else radius) ** 2

static func _action(id: String, label: String, enabled: bool, target: String) -> Dictionary:
	return {"id":id,"label":label,"enabled":enabled,"target_id":target}

static func verify_recording(definition: Dictionary, record: Dictionary, checkpoint: Dictionary, prior_a: Dictionary = {}) -> Dictionary:
	var check := verify_checkpoint(definition, checkpoint)
	return _verify_raw(definition, record, checkpoint, prior_a) if check.valid else check

static func _verify_raw(definition: Dictionary, record: Dictionary, checkpoint: Dictionary, prior_a: Dictionary) -> Dictionary:
	var reason := recording_error(definition, record, checkpoint)
	if not reason.is_empty(): return _invalid(reason)
	if record.role == "b":
		if prior_a.get("role") != "a" or record.source_recording_hash != prior_a.get("recording_hash", ""): return _invalid("The partner recording does not match.")
		var first_check := _verify_raw(definition, prior_a, checkpoint, {})
		if not first_check.valid or not first_check.snapshot.can_commit: return _invalid("The partner recording is not ready.")
	elif not prior_a.is_empty() or not str(record.source_recording_hash).is_empty(): return _invalid("Unexpected partner recording.")
	var simulation := AfterYouCooperativeSimulation.new()
	simulation.catch_assistance = record.catch_assistance
	simulation._reset_trusted(definition, record.stage_id, checkpoint, prior_a, record.role)
	for input: Dictionary in expand_recording_inputs(record):
		if simulation.finished: return _invalid("The recording continues after the turn ended.")
		simulation.step(input)
	if not Canonical.same(simulation.export_recording(), record): return _invalid("The recording did not replay exactly.")
	return {"valid":true,"error":"","snapshot":simulation.snapshot()}

static func recording_error(definition: Dictionary, record: Dictionary, checkpoint: Dictionary) -> String:
	if not _exact_keys(record, RECORD_KEYS): return "Malformed recording."
	for key: String in ["schema_version", "simulation_version", "level_version", "stage_version"]:
		if not _integer(record[key]) or int(record[key]) != (6 if key in ["schema_version", "simulation_version"] else 1): return "Unsupported recording version."
	if record.level_id != definition.get("id") or record.definition_hash != Canonical.digest(definition) or record.checkpoint_hash != checkpoint.get("checkpoint_hash") or record.stage_id != checkpoint.get("next_stage_id"): return "Recording checkpoint mismatch."
	var selected := stage_by_id(definition, str(record.stage_id))
	if selected.is_empty() or record.role not in ["a", "b"]: return "Unknown recording stage."
	if record.player_slot != (selected.first_player_slot if record.role == "a" else _other(selected.first_player_slot)): return "Incorrect player identity."
	if not _integer(record.tick_rate) or int(record.tick_rate) != TICK_RATE or not _integer(record.duration_ticks) or int(record.duration_ticks) < 1 or int(record.duration_ticks) > MAX_TICKS: return "Invalid recording duration."
	if not record.catch_assistance is bool or not record.completed is bool or not record.outcome is Dictionary or not _exact_keys(record.outcome, OUTCOME_KEYS): return "Invalid recording outcome."
	for key: String in OUTCOME_KEYS:
		if not record.outcome[key] is bool: return "Invalid recording outcome."
	if not record.source_recording_hash is String or not _hash(record.final_state_hash) or not _hash(record.recording_hash) or (record.role == "b" and not _hash(record.source_recording_hash)): return "Invalid recording hashes."
	if not record.actions is Array or record.actions.is_empty() or record.actions.size() > MAX_TICKS: return "Invalid action list."
	var total := 0
	for item: Variant in record.actions:
		if not item is Dictionary or not _exact_keys(item, ["ticks", "x", "z", "action"]): return "Unknown action fields."
		if not _integer(item.ticks) or int(item.ticks) < 1 or int(item.ticks) > MAX_TICKS or not _integer(item.x) or not _integer(item.z) or absi(int(item.x)) > 100 or absi(int(item.z)) > 100 or not item.action is bool: return "Invalid action values."
		total += int(item.ticks)
		if total > MAX_TICKS: return "Action duration exceeds the turn."
	if total != int(record.duration_ticks): return "Action duration mismatch."
	if not record.replay_checks is Array or record.replay_checks.is_empty() or record.replay_checks.size() > 31: return "Invalid replay checks."
	var last := 0
	for item: Variant in record.replay_checks:
		if not item is Dictionary or not _exact_keys(item, ["tick", "state_hash"]) or not _integer(item.tick) or int(item.tick) <= last or int(item.tick) > total or not _hash(item.state_hash): return "Invalid replay check."
		last = int(item.tick)
	if last != total or recording_hash(record) != record.recording_hash: return "Recording hash mismatch."
	return ""

static func verify_checkpoint(definition: Dictionary, checkpoint: Dictionary) -> Dictionary:
	if not Catalog.known(definition): return _invalid("Unknown chapter definition.")
	return _verify_checkpoint(definition, checkpoint, 0)

static func _verify_checkpoint(definition: Dictionary, checkpoint: Dictionary, depth: int) -> Dictionary:
	if depth > 2 or not _exact_keys(checkpoint, CHECKPOINT_KEYS) or not _integer(checkpoint.get("stage_index")) or int(checkpoint.stage_index) < 0 or int(checkpoint.stage_index) > definition.stages.size(): return _invalid("Malformed stage checkpoint.")
	if checkpoint.stage_index == 0: return {"valid":true,"error":""} if Canonical.same(checkpoint, Catalog.initial_checkpoint(definition)) else _invalid("The initial checkpoint does not match.")
	if not checkpoint.proof is Dictionary or not _exact_keys(checkpoint.proof, ["checkpoint", "a", "b"]): return _invalid("Missing checkpoint proof.")
	var proof: Dictionary = checkpoint.proof
	if not proof.checkpoint is Dictionary or not proof.a is Dictionary or not proof.b is Dictionary or not _integer(proof.checkpoint.get("stage_index")) or int(proof.checkpoint.stage_index) != int(checkpoint.stage_index) - 1: return _invalid("Invalid checkpoint chain.")
	var prior_check := _verify_checkpoint(definition, proof.checkpoint, depth + 1)
	if not prior_check.valid: return prior_check
	var pair := _verify_pair(definition, proof.checkpoint, proof.a, proof.b)
	if not pair.valid: return pair
	var derived := _build_checkpoint(definition, proof.checkpoint, proof.a, proof.b, pair.snapshot)
	return {"valid":true,"error":""} if Canonical.same(checkpoint, derived) else _invalid("The checkpoint does not match its proof.")

static func derive_checkpoint(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary) -> Dictionary:
	var check := verify_checkpoint(definition, previous)
	if not check.valid: return check
	var pair := _verify_pair(definition, previous, first, second)
	if not pair.valid: return pair
	return {"valid":true,"error":"","checkpoint":_build_checkpoint(definition, previous, first, second, pair.snapshot)}

static func _verify_pair(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary) -> Dictionary:
	if first.get("role") != "a" or second.get("role") != "b": return _invalid("A stage needs both turns in order.")
	var check := _verify_raw(definition, second, previous, first)
	if not check.valid or not check.get("snapshot", {}).get("complete", false): return _invalid("The pair has not completed this stage.")
	return check

static func _build_checkpoint(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary, state: Dictionary) -> Dictionary:
	var index := int(previous.stage_index) + 1
	var players: Dictionary = {}
	for slot: String in ["p0", "p1"]:
		players[slot] = {"x":int(state.players[slot].x),"z":int(state.players[slot].z),"height":int(state.players[slot].height),"surface_id":str(state.players[slot].surface_id)}
	var checkpoint := {"schema_version":6,"level_id":definition.id,"level_version":definition.version,"definition_hash":Canonical.digest(definition),"stage_index":index,
		"completed_stage_id":str(second.stage_id),"next_stage_id":str(definition.stages[index].id) if index < definition.stages.size() else "","players":players,
		"mechanisms":state.mechanisms.duplicate(true),"previous_checkpoint_hash":previous.checkpoint_hash,"a_recording_hash":first.recording_hash,"b_recording_hash":second.recording_hash,
		"proof":{"checkpoint":previous.duplicate(true),"a":first.duplicate(true),"b":second.duplicate(true)}}
	checkpoint["checkpoint_hash"] = Catalog.checkpoint_hash(checkpoint)
	return checkpoint

static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	return Controls._exact_keys(value, expected)

static func _integer(value: Variant) -> bool:
	return Controls._integer(value)

static func _hash(value: Variant) -> bool:
	return Controls._hash(value)

static func _invalid(reason: String) -> Dictionary:
	return {"valid":false,"error":reason}

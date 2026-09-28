extends RefCounted
## One fixed-tick ruleset for authored switches, stairs, drops and rolling props.
## The earlier turn runs in its own simulation: later controls cannot rewrite it.
const Navigation = preload("res://core/cooperative/navigation.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Controls = preload("res://core/first_steps/simulation.gd")
const TICK_RATE := 30
const MAX_TICKS := 900
const MOVE_PER_TICK := 8
const PLAYER_RADIUS := 12
const COMFORT_SIMULATION_VERSION := 8
const RECEIVER_GRACE_TICKS := 300
const RECORD_KEYS := Controls.RECORD_KEYS
const OUTCOME_KEYS := ["source_ready", "objective_complete"]
const CHECKPOINT_KEYS := ["schema_version", "level_id", "level_version", "definition_hash", "stage_index", "completed_stage_id", "next_stage_id", "players", "mechanisms", "previous_checkpoint_hash", "a_recording_hash", "b_recording_hash", "checkpoint_hash", "proof"]

var simulation_version := 6
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
var _comfort_entries: Dictionary = {}

func reset(definition: Dictionary, stage_id: String, checkpoint: Dictionary, prior_a: Dictionary = {}, current_role: String = "a", _rules_version: int = 0) -> bool:
	level = {}
	stage = {}
	error = ""
	var checked: Dictionary = _proof_engine().verify_checkpoint(definition, checkpoint)
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
		var prior_check: Dictionary = _proof_engine()._verify_raw(definition, prior_a, checkpoint, {})
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
	_comfort_entries = {}
	tick = 0
	finished = false
	complete = false
	error = ""
	_prior_frames = expand_recording_inputs(prior_a)
	_source = null
	_reset_mechanics()
	if role == "b":
		_source = _new_simulation()
		_source.simulation_version = simulation_version
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
	_after_move()
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
	if tick >= duration_limit():
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
		# A recorded prop may arrive inside B. Escape moves only the live player,
		# outward through legal floor; it never rewrites A or pushes through a wall.
		if simulation_version == COMFORT_SIMULATION_VERSION:
			var old_distance := Vector2i(previous.x,previous.z).distance_squared_to(Vector2i(ball.x,ball.z))
			var new_distance := Vector2i(x,z).distance_squared_to(Vector2i(ball.x,ball.z))
			if old_distance < separation * separation and new_distance > old_distance: continue
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
		_routes[route.id] = route.id in _mechanisms.latched_bridges or bool(_comfort_entries.get(route.id, false))
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
	var radius := int(target.radius_cm) if simulation_version == COMFORT_SIMULATION_VERSION else maxi(0, int(target.radius_cm) - int(prop.radius_cm))
	return _near_entity(ball, target, radius)

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
	elif simulation_version != COMFORT_SIMULATION_VERSION:
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
			if simulation_version == COMFORT_SIMULATION_VERSION and not _snap_ball(stage.handoff, stage.source_policy.prop_id): return
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
				return _action("offer", "Leave ball", simulation_version == COMFORT_SIMULATION_VERSION or bool(_mechanisms.levers.get(stage.source_policy.lever_id, false)), stage.source_policy.prop_id)
			if role == "b" and ball.status == "offered": return _action("claim", "Take over", true, stage.source_policy.prop_id)
	return _action("", "", false, "")

func _check_ball_home() -> void:
	if not _claimed or not _ball_at(stage.goal, stage.goal_policy.prop_id): return
	if simulation_version == COMFORT_SIMULATION_VERSION and not _snap_ball(stage.goal, stage.goal_policy.prop_id): return
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
	var budget := int(stage.get("receiver_action_ticks", 0)) + 40 + (90 if simulation_version == COMFORT_SIMULATION_VERSION else 0)
	for coords: Array in route:
		var next := Vector2i(coords[0],coords[1])
		budget += ceili(float(absi(next.x - point.x)) / MOVE_PER_TICK) + ceili(float(absi(next.y - point.y)) / MOVE_PER_TICK)
		point = next
	return budget

func can_commit() -> bool:
	if level.is_empty() or not error.is_empty() or tick == 0: return false
	if role == "b": return complete
	if stage.source_policy.kind == "offer_ball":
		return _offer_tick >= 0 and maxi(_offer_tick, tick if simulation_version == COMFORT_SIMULATION_VERSION else _offer_tick) + source_budget_ticks() < receiver_deadline() and bool(_mechanisms.levers.get(stage.source_policy.lever_id, false))
	if simulation_version == COMFORT_SIMULATION_VERSION:
		var policy: Dictionary = stage.source_policy
		var ready := _pad_active(_entity(stage.pressure_pads, policy.pad_id)) if policy.kind == "hold_switch" else _ball_at(_entity(stage.ball_pads, policy.ball_pad_id), policy.prop_id)
		ready = ready and (str(policy.get("lever_id", "")).is_empty() or bool(_mechanisms.levers.get(policy.lever_id, false)))
		return ready and _hold_ticks >= int(policy.minimum_hold_ticks) and _hold_ticks + receiver_deadline() - tick > source_budget_ticks()
	return _hold_ticks >= int(stage.source_policy.minimum_hold_ticks) and _hold_start >= 0 and _hold_start + source_budget_ticks() < MAX_TICKS

func receiver_deadline() -> int:
	return MAX_TICKS + RECEIVER_GRACE_TICKS if simulation_version == COMFORT_SIMULATION_VERSION else MAX_TICKS

func duration_limit() -> int:
	return receiver_deadline() if role == "b" else MAX_TICKS

func _snap_ball(target: Dictionary, prop_id: String) -> bool:
	# Only the explicit current handoff/finale target can snap. Check every cm
	# with the full ball footprint and current route authority before moving it.
	var ball: Dictionary = _mechanisms.props[prop_id]
	var prop := _entity(level.props, prop_id)
	var origin := Vector2i(ball.x, ball.z)
	var delta := Vector2i(target.position_cm[0], target.position_cm[1]) - origin
	var count := maxi(absi(delta.x), absi(delta.y))
	var cursor := ball.duplicate(true)
	for index in range(0, count + 1):
		var point := origin + Vector2i(roundi(float(delta.x * index) / maxi(1,count)), roundi(float(delta.y * index) / maxi(1,count)))
		var position := Navigation.at(level, _routes, _mechanisms.levers, cursor, point.x, point.y, active_slot, int(prop.radius_cm), false)
		if position.is_empty() or position.surface_id != target.surface_id or int(position.height) != int(ball.height): return false
		cursor.merge(position, true)
	ball.merge(cursor, true)
	return true

func commit_reason() -> String:
	if not error.is_empty(): return error
	if can_commit(): return ""
	if level.is_empty(): return "Choose a chapter."
	if role == "b": return "Finish the route with your partner."
	if simulation_version == COMFORT_SIMULATION_VERSION:
		if stage.source_policy.kind == "offer_ball":
			if _offer_tick < 0: return "Leave the ball where your partner can take over."
			if not bool(_mechanisms.levers.get(stage.source_policy.lever_id, false)): return "Pull lever"
			return "Try again with more time left for your partner."
		return "Keep the crossing ready for your partner."
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
	var displayed_props: Dictionary = _mechanisms.props.duplicate(true)
	# Display only: checkpoint construction uses the untouched mechanisms below.
	for id: String in displayed_props:
		var ball: Dictionary = displayed_props[id]
		var controller := first_player_slot if ball.status == "free" else str(ball.holder_slot) if ball.status == "claimed" else ""
		if not controller.is_empty():
			var actor: Dictionary = _players[controller]
			var radius := PLAYER_RADIUS + int(_entity(level.props,id).radius_cm) + 2
			if int(actor.height) != int(ball.height) or Vector2i(actor.x,actor.z).distance_squared_to(Vector2i(ball.x,ball.z)) > radius * radius: controller = ""
		ball["controller_slot"] = controller
	return {"schema_version":_schema_version(),"stage_id":stage.id,"role":role,"active_slot":active_slot,"first_player_slot":first_player_slot,
		"tick":tick,"time_seconds":float(tick)/TICK_RATE,"duration_ticks":duration_limit(),"complete":complete,"finished":finished,"can_commit":can_commit(),
		"commit_reason":commit_reason(),"error":error,"message":str(stage.get("hint_"+role,"")),"players":players,"mechanisms":_mechanisms.duplicate(true),
		"bridges":_routes.duplicate(),"props":displayed_props,"levers":_mechanisms.levers.duplicate(),"hold_pads":pads,
		"objective_done":_objective,"route_progress":{"kept_bridges":_mechanisms.latched_bridges.duplicate()},"source_hold_ticks":_hold_ticks,"offer_tick":_offer_tick,
		"outcome":_outcome(),"events":_events.duplicate(),"context_action":context_action(),"objective_display":_objective_display(),"optics":{"segments":[],"signals":{}},"beacon":_objective}

func _objective_display() -> Dictionary:
	if role == "a":
		if stage.source_policy.kind == "offer_ball":
			return {"label":"Ball handoff","current":1 if can_commit() else 0,"required":1}
		if simulation_version == COMFORT_SIMULATION_VERSION and stage.source_policy.has("minimum_hold_ticks"):
			return {"label":"Hold","current":float(_hold_ticks)/TICK_RATE,"required":float(stage.source_policy.minimum_hold_ticks)/TICK_RATE,"unit":"seconds","detail":commit_reason()}
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
	var record := {"schema_version":_schema_version(),"simulation_version":simulation_version,"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),
		"stage_id":stage.id,"stage_version":stage.version,"checkpoint_hash":_checkpoint.checkpoint_hash,"role":role,"player_slot":active_slot,"tick_rate":TICK_RATE,
		"duration_ticks":tick,"catch_assistance":catch_assistance,"actions":_actions.duplicate(true),"replay_checks":checks,"final_state_hash":state_hash(),
		"completed":complete,"outcome":_outcome(),"source_recording_hash":str(_prior.get("recording_hash", "")) if role == "b" else ""}
	record["recording_hash"] = recording_hash(record)
	return record

func state_hash() -> String:
	return Canonical.digest(_state_body())

func _state_body() -> Dictionary:
	var value := {"simulation_version":simulation_version,"definition_hash":Canonical.digest(level),"stage_id":stage.id,"checkpoint_hash":_checkpoint.checkpoint_hash,
		"role":role,"tick":tick,"players":_players,"mechanisms":_mechanisms,"routes":_routes,"held":_held,"hold_ticks":_hold_ticks,"hold_start":_hold_start,
		"offer_tick":_offer_tick,"claimed":_claimed,"objective":_objective,"complete":complete,"outcome":_outcome(),"source_recording_hash":str(_prior.get("recording_hash", ""))}
	if simulation_version == COMFORT_SIMULATION_VERSION:
		var entries := _comfort_entries.keys()
		entries.sort()
		value["entered_routes"] = entries
	return value

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


# Facades bind these to trusted code, never to values from a checkpoint.
func _schema_version() -> int:
	return 6

func _new_simulation() -> RefCounted:
	assert(false, "A physical simulation needs its sealed facade factory.")
	return null

func _proof_engine() -> RefCounted:
	assert(false, "A physical simulation needs its sealed proof adapter.")
	return null

func _reset_mechanics() -> void:
	pass

func _after_move() -> void:
	if simulation_version != COMFORT_SIMULATION_VERSION or role != "b": return
	var player: Dictionary = _players[active_slot]
	var point := Vector2i(player.x, player.z)
	var diagonal := int(ceil(float(PLAYER_RADIUS)*0.707107))
	for route: Dictionary in level.get("bridges", []) + level.get("stairs", []):
		if not bool(_routes.get(route.id, false)) or not Navigation._owns(route, active_slot): continue
		for offset: Vector2i in [Vector2i.ZERO,Vector2i(PLAYER_RADIUS,0),Vector2i(-PLAYER_RADIUS,0),Vector2i(0,PLAYER_RADIUS),Vector2i(0,-PLAYER_RADIUS),Vector2i(diagonal,diagonal),Vector2i(-diagonal,diagonal),Vector2i(diagonal,-diagonal),Vector2i(-diagonal,-diagonal)]:
			var sample := point + offset
			if not Navigation.inside(sample, route.rect_cm): continue
			var height: int = Navigation.stair_height(route,sample) if route.has("axis") else int(route.height_cm)
			if absi(height-int(player.height)) <= PLAYER_RADIUS+1:
				_comfort_entries[route.id] = true
				break

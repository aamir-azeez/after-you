extends RefCounted
## One fixed-tick ruleset for authored switches, stairs, drops and rolling props.
## The earlier turn runs in its own simulation: later controls cannot rewrite it.
const Navigation = preload("res://core/cooperative/navigation.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Controls = preload("res://core/first_steps/simulation.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
const MemoryTrace = preload("res://core/physical/memory_trace.gd")
const RecordingCodec = preload("res://core/v2/recording_codec.gd")
const Solid = preload("res://core/solid_footprint.gd")
const TICK_RATE := 30
const MAX_TICKS := 900
const MOVE_PER_TICK := 8
const PLAYER_RADIUS := 12
const COMFORT_SIMULATION_VERSION := 8
const RECEIVER_GRACE_TICKS := 300
## From these rules on a pinned definition may set its own turn lengths:
## "turn_limits": {"a_ticks": ..., "b_ticks": ...}. The definition hash covers
## it, so a packet cannot change it. Without it the published caps apply.
const FIRST_TURN_LIMITS_VERSION := 9
const MAX_DECLARED_TURN_TICKS := 9000
## Open turns (open_turns.gd: 14 and 15) take turns up to ten minutes. Every
## open turn goes packed (core/v2/recording_codec.gd): the widest one this long
## is about 82,000 packed characters, under RecordingCodec.MAX_PACKED_CHARS
## (131,072) with room to spare, and its check replays about a sixth of its own
## length on a slow phone. The server's mirror is open-turns.ts MAX_OPEN_TURN_TICKS.
const MAX_OPEN_TURN_TICKS := 18000
## Open controls (a facade's _open_controls()): a pad holds for either pip, and
## either pip works any lever, switch or selector, so the controls carry no
## owner_slot. In the second turn the memory's toggles replay as toggles: a
## control takes the memory's value only on a tick where the memory changed it,
## and keeps the live pip's otherwise. On a tick where both change it, the
## memory's lands first and the live pip's press then turns it from there.
## The numbers live in open_controls.gd; this one both facades share.
const OPEN_RULES_VERSION := OpenControls.OPEN_RULES_VERSION
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
## Open turns (open_turns.gd): this turn's number in its stage (1 for a first
## turn), the slot its memory plays, and whether this turn may pass once its
## memory is over (the caller clears it when the room says the turn must
## finish the stage). `passed` once it did.
var turn_number := 1
var memory_slot := "p0"
var pass_allowed := true
var passed := false
## Export the packed form (core/v2/recording_codec.gd): set for a live turn in a
## packed room, and from the record itself whenever one is replayed. Open turns
## (open_turns.gd) always export packed, in rooms and solo alike: the server
## takes no other form there, and a stage of many long turns stays small.
var packed_recordings := false
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
## Open controls, second turn: the lever and control ids the memory changed this
## tick ({"levers": {id: true}, "controls": {id: true}}).
var _source_toggles: Dictionary = {"levers": {}, "controls": {}}
## Open turns: what the live pip itself turned this tick ({"levers": {id:
## true}, "controls": {id: true}}) and whether it rang. A later turn whose
## memory is itself a later turn takes only these from it, never what the
## memory's own memory did, so a pip's earlier turn never acts against its
## live play.
var _own_toggles: Dictionary = {"levers": {}, "controls": {}}
## The digest of `level`, worked out on first use after a reset (level is set
## only by a reset, to its own deep copy, and never changed after): the state
## hash, the recording and the navigation index read it instead of digesting
## the whole definition again. "" until first used.
var _definition_hash := ""
## The level's item spots and the stage's hand controls that are solid
## (core/solid_footprint.gd), set at reset: a pip walks round them. [] on a
## definition without one.
var _solids: Array = []

## `chain`: open turns only, the stage's turns before `prior_a` (the memory),
## oldest first; the memory replays over them as it was played.
func reset(definition: Dictionary, stage_id: String, checkpoint: Dictionary, prior_a: Dictionary = {}, current_role: String = "a", _rules_version: int = 0, chain: Array = []) -> bool:
	level = {}
	_definition_hash = ""
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
	if current_role == "a" and not chain.is_empty():
		error = "The first turn cannot contain a partner recording."
		return false
	if current_role == "b":
		var prior_check: Dictionary = _proof_engine()._verify_raw(definition, prior_a, checkpoint, chain.back() if not chain.is_empty() else {}, chain.slice(0, maxi(0, chain.size() - 1)))
		if not prior_check.valid or prior_a.get("role") != ("a" if chain.is_empty() else "b") or not prior_check.get("ready", prior_check.get("snapshot", {}).get("can_commit", false)):
			error = "The partner recording is not ready."
			return false
	_reset_trusted(definition, stage_id, checkpoint, prior_a, current_role, chain)
	return true

func _reset_trusted(definition: Dictionary, stage_id: String, checkpoint: Dictionary, prior_a: Dictionary, current_role: String, chain: Array = []) -> void:
	level = definition.duplicate(true)
	_definition_hash = ""
	stage = stage_by_id(level, stage_id)
	_solids = Solid.solids(level.get("item_spots", []) + stage.get("levers", []) + stage.get("controls", []))
	role = current_role
	first_player_slot = stage.first_player_slot
	# Odd turns are the first pip's, even turns the other's: before open turns, a then b.
	turn_number = 1 if role == "a" else chain.size() + 2
	active_slot = OpenTurns.slot(first_player_slot, turn_number)
	memory_slot = _other(active_slot)
	pass_allowed = true
	passed = false
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
	_source_toggles = {"levers": {}, "controls": {}}
	_own_toggles = {"levers": {}, "controls": {}}
	tick = 0
	finished = false
	complete = false
	error = ""
	_prior_frames = expand_recording_inputs(prior_a)
	_source = null
	_reset_mechanics()
	# Open turns: the memory plays back what it did when it was checked (memory_trace.gd), so a turn costs one simulation however deep its memories nest.
	var trace: Dictionary = _proof_engine().memory_trace(definition, prior_a, checkpoint, chain) if role == "b" and _open_turns() else {}
	if not trace.is_empty():
		_source = MemoryTrace.Playback.new(trace)
	elif role == "b":
		# The memory replays in its own world: a first turn alone, or a later turn over its own memory.
		_source = _new_simulation()
		_source.simulation_version = simulation_version
		_source.catch_assistance = bool(prior_a.catch_assistance)
		_source._reset_trusted(definition, stage_id, checkpoint, chain.back() if not chain.is_empty() else {}, "a" if chain.is_empty() else "b", chain.slice(0, maxi(0, chain.size() - 1)))
	_refresh_routes()

func step(input: Dictionary = {}) -> Dictionary:
	_tick(input)
	return snapshot()

## One tick without building a snapshot: what a memory and a check play.
func _tick(input: Dictionary = {}) -> void:
	if finished or not error.is_empty() or level.is_empty(): return
	if not Controls._valid_input(input):
		error = "Unsupported control input."
		return
	_events = []
	_own_toggles = {"levers": {}, "controls": {}}
	var previous_routes := _routes.duplicate()
	var frame := quantize_input(input)
	_append_frame(frame)
	if role == "b": _advance_source()
	_refresh_routes()
	# Open turns: both pips at the goal is a state, not a bell, so nothing freezes.
	if not _objective or _open_turns(): _move(frame)
	_after_move()
	_refresh_routes()
	if (not _objective or _open_turns()) and bool(frame.action) and not _held: _interact()
	_after_interact()
	_held = bool(frame.action)
	_refresh_routes()
	for route_id: String in _routes:
		if _routes[route_id] and not bool(previous_routes.get(route_id, false)): _events.append("bridge_opened:" + route_id)
	_check_hazards()
	if role == "a": _update_source_readiness()
	if role == "b" and stage.goal_policy.kind == "ball_home": _check_ball_home()
	# Open turns: the goal holds while both pips stand at it (open_turns.gd).
	if role == "b" and _open_turns(): _objective = _at_goal(active_slot) and _at_goal(memory_slot)
	tick += 1
	# Only a hazard (_check_hazards) can have ended the turn before this point.
	if role == "b" and _objective and tick >= int(_prior.duration_ticks) and not finished and _may_complete():
		complete = true
		finished = true
		if _keeps_routes_at_completion():
			for route_id: String in _routes:
				if _routes[route_id] and route_id not in _mechanisms.latched_bridges and _kept_open(route_id): _mechanisms.latched_bridges.append(route_id)
		_mechanisms.latched_bridges.sort()
		_events.append("stage_complete")
	if tick >= duration_limit():
		finished = true
		_events.append("turn_finished")
	if tick % TICK_RATE == 0 or finished: _checks.append({"tick":tick,"state_hash":state_hash()})

func _advance_source() -> void:
	var open := _open_controls()
	# Open turns: a memory that is itself a later turn hands over only its own pip's presses.
	var nested: bool = _source.role == "b"
	var before: Dictionary = _source_values() if open and not nested else {}
	var stepped := tick < _prior_frames.size()
	if stepped: _source._tick(_prior_frames[tick])
	_players[memory_slot] = _source._players[memory_slot].duplicate(true)
	if open: _source_toggles = (_source._own_toggles.duplicate(true) if stepped else {"levers": {}, "controls": {}}) if nested else _changed_since(before)
	for lever: Dictionary in stage.get("levers", []):
		if open:
			if _source_toggles.levers.has(lever.id): _mechanisms.levers[lever.id] = _source._mechanisms.levers[lever.id]
		elif lever.owner_slot == first_player_slot and _source._mechanisms.levers.has(lever.id):
			_mechanisms.levers[lever.id] = _source._mechanisms.levers[lever.id]
	if not _claimed:
		_mechanisms.props = _source._mechanisms.props.duplicate(true)
	_offer_tick = _source._offer_tick
	_hold_ticks = _source._hold_ticks
	_hold_start = _source._hold_start

## Open controls: the memory's lever and control values before its tick.
func _source_values() -> Dictionary:
	return {"levers": _source._mechanisms.get("levers", {}).duplicate(), "controls": _source._mechanisms.get("controls", {}).duplicate()}

## Open controls: the ids whose value the memory changed since `before`.
func _changed_since(before: Dictionary) -> Dictionary:
	var changed: Dictionary = {"levers": {}, "controls": {}}
	for kind: String in changed:
		var now: Dictionary = _source._mechanisms.get(kind, {})
		for id: Variant in now:
			if not before[kind].has(id) or before[kind][id] != now[id]: changed[kind][id] = true
	return changed

## `slot`: the live pip unless named. A facade walks its memory with it too
## (rules 16: a memory a platform carried off its own world's path).
func _move(frame: Dictionary, slot: String = "") -> void:
	if slot.is_empty(): slot = active_slot
	var direction := Vector2(float(frame.x), float(frame.z)).limit_length(100.0)
	var delta := Vector2i(roundi(direction.x * MOVE_PER_TICK / 100.0), roundi(direction.y * MOVE_PER_TICK / 100.0))
	if delta == Vector2i.ZERO: return
	var steps := maxi(absi(delta.x), absi(delta.y))
	var walked := Vector2i.ZERO
	var cells := _navigation_cells()
	var routes := _walk_routes(slot)
	for index in range(1, steps + 1):
		var next := Vector2i(roundi(float(delta.x * index) / steps), roundi(float(delta.y * index) / steps))
		var unit := next - walked
		walked = next
		if _try_move(unit, cells, routes, slot): continue
		if unit.x != 0: _try_move(Vector2i(unit.x, 0), cells, routes, slot)
		if unit.y != 0: _try_move(Vector2i(0, unit.y), cells, routes, slot)

## cells: this definition's floor index (_navigation_cells()), fetched once per move.
## routes: the crossings the walker may step on (_walk_routes()), likewise.
## Only the live pip pushes a prop; a memory walked here stops at one.
func _try_move(delta: Vector2i, cells: Dictionary, routes: Dictionary, slot: String = "") -> bool:
	if slot.is_empty(): slot = active_slot
	var previous: Dictionary = _players[slot]
	var x := int(previous.x) + delta.x
	var z := int(previous.z) + delta.y
	var position := Navigation.at(level, routes, _mechanisms.levers, previous, x, z, slot, PLAYER_RADIUS, true, cells)
	if position.is_empty() or _in_solid(position, previous): return false
	var pushed: Dictionary = {}
	for prop: Dictionary in level.get("props", []):
		var ball: Dictionary = _mechanisms.props[prop.id]
		var separation := PLAYER_RADIUS + int(prop.radius_cm)
		if int(position.height) != int(ball.height) or Vector2i(x,z).distance_squared_to(Vector2i(ball.x,ball.z)) >= separation * separation: continue
		# A recorded prop may arrive inside B. Escape moves only the live player,
		# outward through legal floor; it never rewrites A or pushes through a wall.
		if _comfort_rules():
			var old_distance := Vector2i(previous.x,previous.z).distance_squared_to(Vector2i(ball.x,ball.z))
			var new_distance := Vector2i(x,z).distance_squared_to(Vector2i(ball.x,ball.z))
			if old_distance < separation * separation and new_distance > old_distance: continue
		if slot != active_slot or not _can_push(ball): return false
		var moved := Navigation.at(level, _routes, _mechanisms.levers, ball, int(ball.x) + delta.x, int(ball.z) + delta.y, active_slot, int(prop.radius_cm), false, cells)
		if moved.is_empty(): return false
		var replacement := ball.duplicate(true)
		replacement.merge(moved, true)
		pushed[prop.id] = replacement
	for id: String in pushed: _mechanisms.props[id] = pushed[id]
	_players[slot] = position
	if slot == active_slot and int(previous.height) > int(position.height) + 2: _events.append("drop")
	return true

## Whether `position` stands in a solid spot on its own floor. With `from`
## (the step's start), a step that leaves a footprint it already stands in
## (a pip a checkpoint, a start or a ride left there) is let through.
func _in_solid(position: Dictionary, from: Dictionary = {}) -> bool:
	if _solids.is_empty(): return false
	var floor := str(position.surface_id)
	var here := _solids.filter(func(spot: Dictionary) -> bool: return str(spot.get("surface_id", "")) == floor)
	var to := Vector2i(int(position.x), int(position.z))
	if from.is_empty() or str(from.get("surface_id", "")) != floor: return Solid.blocked(here, to, PLAYER_RADIUS)
	return Solid.blocks_step(here, Vector2i(int(from.x), int(from.z)), to, PLAYER_RADIUS)

func _can_push(ball: Dictionary) -> bool:
	if ball.status == "fitted" or ball.status == "offered": return false
	if role == "a": return ball.status == "free"
	return _claimed and ball.status == "claimed" and ball.holder_slot == active_slot

func _refresh_routes() -> void:
	for route: Dictionary in level.get("bridges", []) + level.get("stairs", []):
		_routes[route.id] = route.id in _mechanisms.latched_bridges or bool(_comfort_entries.get(route.id, false))
	for gate: Dictionary in stage.get("gates", []):
		_routes[gate.route_id] = bool(_routes.get(gate.route_id, false)) or _gate_open(gate)

## Whether `gate` holds now: each lever it names on, its pad held, its ball on its pad.
func _gate_open(gate: Dictionary) -> bool:
	var enabled := true
	for key: String in ["lever_id", "second_lever_id"]:
		if not str(gate.get(key, "")).is_empty(): enabled = enabled and bool(_mechanisms.levers.get(gate[key], false))
	if not str(gate.get("pad_id", "")).is_empty(): enabled = enabled and _pad_active(_entity(stage.pressure_pads, gate.pad_id))
	if not str(gate.get("ball_pad_id", "")).is_empty(): enabled = enabled and _ball_at(_entity(stage.ball_pads, gate.ball_pad_id), str(stage.source_policy.get("prop_id", "")))
	return enabled

func _pad_active(pad: Dictionary) -> bool:
	if pad.is_empty(): return false
	if _open_controls(): return _near_entity(_players.p0, pad) or _near_entity(_players.p1, pad)
	return _near_entity(_players[pad.owner_slot], pad)

func _ball_at(target: Dictionary, prop_id: String) -> bool:
	if target.is_empty() or not _mechanisms.props.has(prop_id): return false
	var prop := _entity(level.props, prop_id)
	var ball: Dictionary = _mechanisms.props[prop_id]
	var radius := int(target.radius_cm) if _comfort_rules() else maxi(0, int(target.radius_cm) - int(prop.radius_cm))
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
	elif not _comfort_rules():
		_hold_start = -1
		_hold_ticks = 0

func _interact() -> void:
	var action := context_action()
	if not bool(action.enabled): return
	match str(action.id):
		"lever":
			_mechanisms.levers[action.target_id] = not bool(_mechanisms.levers.get(action.target_id, false))
			_own_toggles.levers[action.target_id] = true
			_events.append("lever")
		"ring":
			_objective = true
			_events.append("bell")
		"offer":
			var ball: Dictionary = _mechanisms.props[stage.source_policy.prop_id]
			if _comfort_rules() and not _snap_ball(stage.handoff, stage.source_policy.prop_id): return
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
		if (_open_controls() or lever.owner_slot == active_slot) and _near_entity(player, lever):
			return _action("lever", "Pull lever", true, lever.id)
	# Open turns: no bell; both pips standing at the goal finish the stage.
	if role == "b" and stage.goal_policy.kind == "ring" and not _open_turns() and _near_entity(player, stage.goal):
		return _action("ring", "Ring bell", true, stage.goal.id)
	if stage.source_policy.kind == "offer_ball":
		var ball: Dictionary = _mechanisms.props[stage.source_policy.prop_id]
		if int(player.height) == int(ball.height) and Vector2i(player.x,player.z).distance_squared_to(Vector2i(ball.x,ball.z)) <= 64 * 64:
			if role == "a" and ball.status == "free" and _ball_at(stage.handoff, stage.source_policy.prop_id):
				return _action("offer", "Leave ball", _comfort_rules() or bool(_mechanisms.levers.get(stage.source_policy.lever_id, false)), stage.source_policy.prop_id)
			if role == "b" and ball.status == "offered": return _action("claim", "Take over", true, stage.source_policy.prop_id)
	return _action("", "", false, "")

func _check_ball_home() -> void:
	if not _claimed or not _ball_at(stage.goal, stage.goal_policy.prop_id): return
	if _comfort_rules() and not _snap_ball(stage.goal, stage.goal_policy.prop_id): return
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
	var budget := int(stage.get("receiver_action_ticks", 0)) + 40 + (90 if _comfort_rules() else 0)
	for coords: Array in route:
		var next := Vector2i(coords[0],coords[1])
		budget += ceili(float(absi(next.x - point.x)) / MOVE_PER_TICK) + ceili(float(absi(next.y - point.y)) / MOVE_PER_TICK)
		point = next
	return budget

func can_commit() -> bool:
	if level.is_empty() or not error.is_empty() or tick == 0: return false
	if role == "b": return complete
	# Open turns: a first turn may end at any time, its own part done or not
	# (owner, 2026-11-16); its outcome still says whether it was (_source_ready).
	return _open_turns() or _source_ready()

## A first turn's own part is done, with time left for the turn after it: what
## a first turn needs before it may be saved, except under open turns.
func _source_ready() -> bool:
	if stage.source_policy.kind == "offer_ball":
		return _offer_tick >= 0 and maxi(_offer_tick, tick if _comfort_rules() else _offer_tick) + source_budget_ticks() < receiver_deadline() and bool(_mechanisms.levers.get(stage.source_policy.lever_id, false))
	if _comfort_rules():
		var policy: Dictionary = stage.source_policy
		var ready := _pad_active(_entity(stage.pressure_pads, policy.pad_id)) if policy.kind == "hold_switch" else _ball_at(_entity(stage.ball_pads, policy.ball_pad_id), policy.prop_id)
		ready = ready and (str(policy.get("lever_id", "")).is_empty() or bool(_mechanisms.levers.get(policy.lever_id, false)))
		return ready and _hold_ticks >= int(policy.minimum_hold_ticks) and _hold_ticks + receiver_deadline() - tick > source_budget_ticks()
	return _hold_ticks >= int(stage.source_policy.minimum_hold_ticks) and _hold_start >= 0 and _hold_start + source_budget_ticks() < MAX_TICKS

func receiver_deadline() -> int:
	return turn_ticks(level, simulation_version, "b")

## Open turns: every turn has the second turn's limit.
func duration_limit() -> int:
	return turn_ticks(level, simulation_version, "b" if _open_turns() else role)

## Open turns: whether the live pip may pass now. The memory has played out,
## the stage is not done, the room lets this turn pass (pass_allowed) and the
## facade's rules agree (_may_pass).
func can_pass() -> bool:
	return _open_turns() and role == "b" and pass_allowed and error.is_empty() and not finished and not complete and tick >= int(_prior.get("duration_ticks", 0)) and _may_pass()

## Open turns: whether the live pip may end this turn now, while its memory
## still plays. The screen then plays the rest of the memory with the pip
## standing still (still ticks, recorded as any other), so the turn is the one
## a pip standing there until the memory ended would record; then it passes
## (can_pass) or the stage completes.
func can_end_early() -> bool:
	return _open_turns() and role == "b" and error.is_empty() and not finished and not complete and tick < int(_prior.get("duration_ticks", 0))

## Open turns: ends this turn as a pass. The recording is the turn so far,
## unfinished; play goes to the other pip.
func pass_turn() -> Dictionary:
	if not can_pass(): return snapshot()
	passed = true
	finished = true
	_events = ["turn_passed"]
	return snapshot()

## Open turns: whether `slot`'s pip stands at the goal now, where it holds.
func _at_goal(slot: String) -> bool:
	return stage.goal_policy.kind == "ring" and _near_entity(_players[slot], stage.goal)

## The longest turn `turn_role` may record under `version` in `definition`.
## Published: 900 ticks, and 1,200 for a comfort receiver. A definition that
## declares turn_limits badly is refused by rules_allowed and the proof; its
## turns keep the published lengths here.
static func turn_ticks(definition: Dictionary, version: int, turn_role: String) -> int:
	var published := MAX_TICKS + RECEIVER_GRACE_TICKS if version >= COMFORT_SIMULATION_VERSION and turn_role == "b" else MAX_TICKS
	if version < FIRST_TURN_LIMITS_VERSION or not definition.has("turn_limits"): return published
	return int(_declared_turns(definition.turn_limits, version).get(turn_role if turn_role == "b" else "a", published))

## False only when rules `version` read a turn_limits field that breaks the
## backend's turnLimits rules: a_ticks and b_ticks both whole numbers with
## 1 <= a < b <= 9,000 (the receiver waits out the first turn). On open turns
## (open_controls.gd OPEN_TURNS_RULES) every turn plays alongside its memory
## and has the same limit, so a may equal b there, and turns go up to
## MAX_OPEN_TURN_TICKS: 1 <= a <= b <= 18,000.
static func turn_limits_valid(definition: Dictionary, version: int) -> bool:
	if version < FIRST_TURN_LIMITS_VERSION or not definition.has("turn_limits"): return true
	return not _declared_turns(definition.turn_limits, version).is_empty()

static func _declared_turns(limits: Variant, version: int) -> Dictionary:
	if not limits is Dictionary: return {}
	var a: Variant = limits.get("a_ticks")
	var b: Variant = limits.get("b_ticks")
	var ceiling := MAX_OPEN_TURN_TICKS if version in OpenControls.OPEN_TURNS_RULES else MAX_DECLARED_TURN_TICKS
	if not _whole_ticks(a) or not _whole_ticks(b) or a < 1 or b > ceiling: return {}
	if b < a or (b == a and version not in OpenControls.OPEN_TURNS_RULES): return {}
	return {"a": int(a), "b": int(b)}

static func _whole_ticks(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value) and absf(value) <= 9007199254740991.0)

func _snap_ball(target: Dictionary, prop_id: String) -> bool:
	# Only the explicit current handoff/finale target can snap. Check every cm
	# with the full ball footprint and current route authority before moving it.
	var ball: Dictionary = _mechanisms.props[prop_id]
	var prop := _entity(level.props, prop_id)
	var origin := Vector2i(ball.x, ball.z)
	var delta := Vector2i(target.position_cm[0], target.position_cm[1]) - origin
	var count := maxi(absi(delta.x), absi(delta.y))
	var cursor := ball.duplicate(true)
	var cells := _navigation_cells()
	for index in range(0, count + 1):
		var point := origin + Vector2i(roundi(float(delta.x * index) / maxi(1,count)), roundi(float(delta.y * index) / maxi(1,count)))
		var position := Navigation.at(level, _routes, _mechanisms.levers, cursor, point.x, point.y, active_slot, int(prop.radius_cm), false, cells)
		if position.is_empty() or position.surface_id != target.surface_id or int(position.height) != int(ball.height): return false
		cursor.merge(position, true)
	ball.merge(cursor, true)
	return true

func commit_reason() -> String:
	if not error.is_empty(): return error
	if can_commit(): return ""
	if level.is_empty(): return "Choose a chapter."
	if role == "b": return "Finish the route with your partner."
	if _comfort_rules():
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
	for slot: String in players: players[slot].merge({"ghost":role == "b" and slot == memory_slot,"holding":false})
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
	var state := {"schema_version":_schema_version(),"stage_id":stage.id,"role":role,"active_slot":active_slot,"first_player_slot":first_player_slot,
		"tick":tick,"time_seconds":float(tick)/TICK_RATE,"duration_ticks":duration_limit(),"complete":complete,"finished":finished,"can_commit":can_commit(),
		"commit_reason":commit_reason(),"error":error,"message":str(stage.get("hint_"+role,"")),"players":players,"mechanisms":_mechanisms.duplicate(true),
		"bridges":_routes.duplicate(),"props":displayed_props,"levers":_mechanisms.levers.duplicate(),"hold_pads":pads,
		"objective_done":_objective,"route_progress":{"kept_bridges":_mechanisms.latched_bridges.duplicate()},"source_hold_ticks":_hold_ticks,"offer_tick":_offer_tick,
		"outcome":_outcome(),"events":_events.duplicate(),"context_action":context_action(),"objective_display":_objective_display(),"optics":{"segments":[],"signals":{}},"beacon":_objective}
	# Open turns only, so a published chapter's snapshot stays byte for byte as it was.
	if _open_turns(): state.merge({"turn_number":turn_number,"can_pass":can_pass(),"can_end_early":can_end_early(),"passed":passed})
	return state

func _objective_display() -> Dictionary:
	# Open turns: a first turn shows no count of its own part, so nothing tells
	# the pip when its part is done (owner, 2026-11-16).
	if role == "a" and _open_turns(): return {}
	if role == "a":
		if stage.source_policy.kind == "offer_ball":
			return {"label":"Ball handoff","current":1 if _part_done() else 0,"required":1}
		if _comfort_rules() and stage.source_policy.has("minimum_hold_ticks"):
			return {"label":"Hold","current":float(_hold_ticks)/TICK_RATE,"required":float(stage.source_policy.minimum_hold_ticks)/TICK_RATE,"unit":"seconds","detail":commit_reason()}
		return {"label":"Crossing ready","current":1 if _part_done() else 0,"required":1}
	return {"label":"Ball home" if stage.goal_policy.kind == "ball_home" else "Bell","current":1 if _objective else 0,"required":1}

func _outcome() -> Dictionary:
	return {"source_ready":_part_done() if role == "a" else bool(_prior.get("outcome", {}).get("source_ready", false)),"objective_complete":complete}

## A first turn may be saved and its own part is done: before open turns, the
## same as can_commit.
func _part_done() -> bool:
	return can_commit() and _source_ready()

func walkable_at(x: int, z: int, slot: String = "") -> bool:
	var selected := active_slot if slot.is_empty() else slot
	var found := Navigation.at(level, _walk_routes(selected), _mechanisms.levers, _players[selected], x, z, selected, PLAYER_RADIUS, true, _navigation_cells())
	return not found.is_empty() and not _in_solid(found)

func export_recording() -> Dictionary:
	if tick == 0 or level.is_empty(): return {}
	var checks := _checks.duplicate(true)
	if checks.is_empty() or int(checks[-1].tick) != tick: checks.append({"tick":tick,"state_hash":state_hash()})
	var record := {"schema_version":_schema_version(),"simulation_version":simulation_version,"level_id":level.id,"level_version":level.version,"definition_hash":_level_digest(),
		"stage_id":stage.id,"stage_version":stage.version,"checkpoint_hash":_checkpoint.checkpoint_hash,"role":role,"player_slot":active_slot,"tick_rate":TICK_RATE,
		"duration_ticks":tick,"catch_assistance":catch_assistance,"actions":_actions.duplicate(true),"replay_checks":checks,"final_state_hash":state_hash(),
		"completed":complete,"outcome":_outcome(),"source_recording_hash":str(_prior.get("recording_hash", "")) if role == "b" else ""}
	if packed_recordings or _open_turns(): record = RecordingCodec.packed_form(record)
	record["recording_hash"] = recording_hash(record)
	return record

func state_hash() -> String:
	return Canonical.digest(_state_body())

## This definition's floor index (core/cooperative/navigation.gd), shared by
## every engine on the same definition.
func _navigation_cells() -> Dictionary:
	return Navigation.index_for(level, _level_digest())

func _level_digest() -> String:
	if _definition_hash.is_empty(): _definition_hash = Canonical.digest(level)
	return _definition_hash

func _state_body() -> Dictionary:
	var value := {"simulation_version":simulation_version,"definition_hash":_level_digest(),"stage_id":stage.id,"checkpoint_hash":_checkpoint.checkpoint_hash,
		"role":role,"tick":tick,"players":_players,"mechanisms":_mechanisms,"routes":_routes,"held":_held,"hold_ticks":_hold_ticks,"hold_start":_hold_start,
		"offer_tick":_offer_tick,"claimed":_claimed,"objective":_objective,"complete":complete,"outcome":_outcome(),"source_recording_hash":str(_prior.get("recording_hash", ""))}
	if _comfort_rules():
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

## Whether `player` is at `target` on its floor: within `radius`, or else
## within its reach (Solid.within_reach: a solid control's reach beside its
## footprint, any other spot's radius_cm).
static func _near_entity(player: Dictionary, target: Dictionary, radius: int = -1) -> bool:
	if player.surface_id != target.surface_id: return false
	if radius < 0: return Solid.within_reach(target, Vector2i(player.x,player.z), PLAYER_RADIUS)
	return Vector2i(player.x,player.z).distance_squared_to(Vector2i(target.position_cm[0],target.position_cm[1])) <= radius ** 2

static func _action(id: String, label: String, enabled: bool, target: String) -> Dictionary:
	return {"id":id,"label":label,"enabled":enabled,"target_id":target}


## Comfort (8) and every later alias of it (9: the same rules, advertised under
## a new number so older clients cannot take a seat they could never play).
func _comfort_rules() -> bool:
	return simulation_version >= COMFORT_SIMULATION_VERSION

# Facades bind these to trusted code, never to values from a checkpoint.
func _schema_version() -> int:
	return 6

## Open turns: what a later turn reads of this one while it plays as its
## memory (_advance_source and the facades' overrides), in MemoryTrace order.
## Values the engine changes in place are copied; the rest are replaced each tick.
func _memory_frame() -> Array:
	return [_players[active_slot].duplicate(), _mechanisms.duplicate(true), _own_toggles, _offer_tick, _hold_ticks, _hold_start, ""]

func _new_simulation() -> RefCounted:
	assert(false, "A physical simulation needs its sealed facade factory.")
	return null

func _proof_engine() -> RefCounted:
	assert(false, "A physical simulation needs its sealed proof adapter.")
	return null

func _reset_mechanics() -> void:
	pass

## The crossings slot's pip may step onto this tick: the open ones, less any
## a facade's rules keep it off (rules 16: a pip carrying an item never climbs
## a crossing that needs both hands). Never changes the routes themselves.
func _walk_routes(_slot: String) -> Dictionary:
	return _routes

## After the live pip's press, before the routes are worked out again: a
## facade whose things move on a press (rules 16's current) moves them here.
## Published rules have none.
func _after_interact() -> void:
	pass

## After a tick's routes are final, before readiness and completion: a facade
## whose rules can end a turn early (a spirit caught on a shut crossing) sets
## `finished` here. Published rules have none.
func _check_hazards() -> void:
	pass

## Whether this facade plays open controls (OPEN_RULES_VERSION). Published
## rules never do.
func _open_controls() -> bool:
	return false

## Whether these rules play open turns (open_turns.gd, 14 and 15).
func _open_turns() -> bool:
	return simulation_version in OpenTurns.RULES

## Whether the facade's rules let a turn pass now. Published rules have no passes.
func _may_pass() -> bool:
	return true

## Whether the stage may complete this tick. Published rules always may.
func _may_complete() -> bool:
	return true

## Whether a completed stage keeps every route open at its end for the stages
## after it (latched_bridges). Published rules do.
func _keeps_routes_at_completion() -> bool:
	return true

## Whether a route open at a stage's end stays open after it, when the facade
## keeps routes at all. Published rules keep every open one.
func _kept_open(_route_id: String) -> bool:
	return true

func _after_move() -> void:
	if not _comfort_rules() or role != "b": return
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

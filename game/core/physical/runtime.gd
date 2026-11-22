extends RefCounted
## One fixed-tick ruleset for authored switches, stairs, drops and rolling props.
## Published rules: the earlier turn runs in its own simulation, so later
## controls cannot rewrite it. Open turns (open_turns.gd) play one world with
## two input tracks: the live pip's, and the rest of the friend's latest turn,
## which moves, presses, grabs, throws, rides and drowns by its recorded
## inputs through the same code as the live pip.
const Navigation = preload("res://core/cooperative/navigation.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Controls = preload("res://core/first_steps/simulation.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
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
## Open turns (open_turns.gd) take turns up to ten minutes. Every
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
## The shared ball (open_controls.gd SHARED_BALL_RULES: open turns with a
## ball). The one world has one ball, and both pips push it as they walk, the
## friend's replay by its inputs as the live pip by the stick, p0 first on a
## tick both push; a ball a pip cannot move stops that pip. There is no offer
## or claim: a ball is free until it reaches its stage's cradle (a ball home
## goal), in any turn, where it snaps in and stays. A ball home stage ends when
## the ball is in its cradle and both pips stand on the cradle's floor (_at_goal).
const SHARED_BALL_RULES := OpenControls.SHARED_BALL_RULES
## Open turns: a pip keeps its footing. When a crossing under it stops being
## walkable (a held bridge or rope bridge let go, a crank bridge wound in, a
## lift or raft leaving, a stone sinking), a pip that still touches floor at
## its height (its centre, or its walk radius, over a bank) steps onto the
## nearest spot it may stand and walks on; one that touches none falls. Over
## water it drowns; anywhere else it falls into the sky ("fell" and "sky" on
## the drowned record). Either ends the turn. Decided here, so live play, the
## friend's replay, memories and replays all agree (_keep_footing).
## Open turns: the friend's replay walks off where its floor went. A step of
## the replay onto a spot that had floor in the friend's own world (this turn
## played again from its start with the live pip standing still, which is the
## world the friend played in) but has none here, because the live pip moved a
## lift or raft away or let a deck or bridge shut, takes the replay there and
## it falls (or drowns over water) as above, ending the turn. Anywhere else the
## replay keeps to its floor as the live pip does at an edge (_floor_went).
## The chapters whose crossings span water (their worlds draw it: a chapter
## descriptor's "water"). Beside the definition, like stage_catalog.gd
## tall_stones, so no definition hash moves; test_footing checks it against
## the descriptors.
const WATER_CHAPTERS := ["turn-of-the-tide", "the-falls", "fog-marsh"]
## Open turns: how long (ticks) a crossing whose gate lets go keeps its floor
## before it shuts, the same for every crossing in every level (the journey's
## _close_slowly; the worlds flash its edges meanwhile, kit/closing_warning.gd):
## 25 ticks, five sixths of a second, a little over half Turn of the Tide's old
## 45 (the owner found that too forgiving). No pip stepping off a pad reaches
## the far side of the crossing it holds in that time (test_footing). Then a
## pip still on it steps off or falls (_keep_footing).
const CLOSING_GRACE_TICKS := 25
## How far (cm) a pip whose floor went steps back onto floor it touches: the
## nearest spot whose whole footprint stands, at most two walk radii away.
const FOOTING_REACH := PLAYER_RADIUS * 2 + 1
## What a turn ended by a drowning or a fall says (snapshot text; PlayerCopy
## shows the editable lines): the player's own pip, or the friend's (the
## memory, or under open turns the friend's replay, which fails the turn the
## same way).
const DROWNED_YOU := "Oh no, you drowned! Try again?"
const DROWNED_FRIEND := "Oh no, your friend drowned! Try again?"
const FELL_YOU := "Your pip fell! Try again?"
const FELL_FRIEND := "Your friend fell! Try again?"
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
## {"slot", "route", "tick"} once a pip has drowned (the journey's tide rules,
## or under open turns a pip whose floor went from under it over water), with
## "fell": true when it fell instead, and "sky": true when that fall was into
## the sky. {} while nobody has; a turn with one is never kept (keeps_draft).
var _drowned: Dictionary = {}
var error := ""
var catch_assistance := true
## Open turns (open_turns.gd): this turn's number in its stage (1 for a first
## turn), the slot its friend's replay plays (the memory), and whether this
## turn may pass once that replay is over (the caller clears it when the room
## says the turn must finish the stage). `passed` once it did.
var turn_number := 1
var memory_slot := "p0"
var pass_allowed := true
var passed := false
## Open turns: H, the tick of the friend's turn this one took over at; the
## friend's replay plays its inputs from there (open_turns.gd handoff_tick).
var handoff_tick := 0
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
## Open controls on the published rules, second turn: the lever and control
## ids the memory changed this tick ({"levers": {id: true}, "controls": {id: true}}).
var _source_toggles: Dictionary = {"levers": {}, "controls": {}}
## Open turns: whether the friend's replay held its button last tick (the
## live pip's is _held), the world hash at this turn's start, and the world at
## its tick M (replay_ticks()), which is the next turn's start, with its hash.
var _friend_held := false
var _start_hash := ""
var _handoff_world: Dictionary = {}
var _handoff_hash := ""
## Open turns, a later turn: the world it started from (load_world, read only),
## whether the live pip has done anything yet (until then this world is the
## friend's own), and the friend's own world (_friend_floor), made only when
## the replay first meets an edge after that. Not world state: it follows from
## the start and the inputs, so a turn played again from its record agrees.
var _start_world: Dictionary = {}
var _live_moved := false
var _friend_world: RefCounted = null
## Set on a friend's own world: its replay keeps to its floor as the friend did
## live, and each tick keeps the floor it walked on (_move_floor: the replay's
## routes and the levers as the pips moved).
var _plays_friend_world := false
var _move_floor: Dictionary = {}
## The digest of `level`, worked out on first use after a reset (level is set
## only by a reset, to its own deep copy, and never changed after): the state
## hash, the recording and the navigation index read it instead of digesting
## the whole definition again. "" until first used.
var _definition_hash := ""
## The level's item spots and the stage's hand controls that are solid
## (core/solid_footprint.gd), set at reset: a pip walks round them. [] on a
## definition without one.
var _solids: Array = []

## `chain`: open turns only, the stage's turns before `prior_a` (the friend's
## latest turn), oldest first. The turn starts from prior_a's hand-off world
## (kept when prior_a was played or checked, else worked out by playing the
## stage's turns once each), with the rest of prior_a replaying beside it.
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
	var start: Dictionary = {}
	if current_role == "b":
		var proof: RefCounted = _proof_engine()
		var prior_check: Dictionary = proof._verify_raw(definition, prior_a, checkpoint, chain.back() if not chain.is_empty() else {}, chain.slice(0, maxi(0, chain.size() - 1)))
		if not prior_check.valid or prior_a.get("role") != ("a" if chain.is_empty() else "b") or not prior_check.get("ready", prior_check.get("snapshot", {}).get("can_commit", false)):
			error = "The partner recording is not ready."
			return false
		if _open_turns():
			start = proof.turn_start(definition, checkpoint, prior_a, chain)
			if start.is_empty():
				error = "The partner recording is not ready."
				return false
	_reset_trusted(definition, stage_id, checkpoint, prior_a, current_role, chain, start)
	return true

## `start`: open turns only, {"world", "handoff_tick"}: the world this turn
## starts from and H. A later turn given none works it out (two_pair_proof.gd
## turn_start); a first turn starts from the checkpoint.
func _reset_trusted(definition: Dictionary, stage_id: String, checkpoint: Dictionary, prior_a: Dictionary, current_role: String, chain: Array = [], start: Dictionary = {}) -> void:
	level = definition.duplicate(true)
	_definition_hash = ""
	stage = stage_by_id(level, stage_id)
	_solids = Solid.solids(level.get("item_spots", []) + stage.get("levers", []) + stage.get("controls", []))
	role = current_role
	# Open turns: the stage's first pip comes from the checkpoint (the host's on a first stage).
	first_player_slot = OpenTurns.first_slot(checkpoint) if _open_turns() else stage.first_player_slot
	# Odd turns are the first pip's, even turns the other's: before open turns, a then b.
	turn_number = 1 if role == "a" else chain.size() + 2
	active_slot = OpenTurns.slot(first_player_slot, turn_number)
	memory_slot = _other(active_slot)
	# The cap's turn must finish the stage, in Solo as in a room (which may also end it sooner).
	pass_allowed = not OpenTurns.must_finish(stage, turn_number)
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
	_drowned = {}
	_source_toggles = {"levers": {}, "controls": {}}
	_friend_held = false
	handoff_tick = 0
	_start_hash = ""
	_handoff_world = {}
	_handoff_hash = ""
	_start_world = {}
	_live_moved = false
	_friend_world = null
	_move_floor = {}
	tick = 0
	finished = false
	complete = false
	error = ""
	_prior_frames = expand_recording_inputs(prior_a)
	_source = null
	_reset_mechanics()
	if role == "b" and not _open_turns():
		# Published rules: the memory replays in its own world.
		_source = _new_simulation()
		_source.simulation_version = simulation_version
		_source.catch_assistance = bool(prior_a.catch_assistance)
		_source._reset_trusted(definition, stage_id, checkpoint, {}, "a")
	_refresh_routes()
	if not _open_turns(): return
	if role == "b":
		if start.is_empty(): start = _proof_engine().turn_start(definition, checkpoint, prior_a, chain)
		if start.is_empty(): start = _played_start(definition, stage_id, checkpoint, prior_a, chain)
		if start.world.is_empty():
			error = "The partner recording is not ready."
			return
		load_world(start.world, int(start.handoff_tick))
	_start_hash = world_hash()
	if replay_ticks() == 0: _keep_handoff()

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
	var previous_routes := _routes.duplicate()
	var frame := quantize_input(input)
	_append_frame(frame)
	if int(frame.x) != 0 or int(frame.z) != 0 or bool(frame.action): _live_moved = true
	if _open_turns(): _play_both(frame)
	else:
		if role == "b": _advance_source()
		_refresh_routes()
		if not _objective: _move(frame)
		_after_move()
		_refresh_routes()
		if not _objective and bool(frame.action) and not _held: _interact()
		_after_interact()
		_held = bool(frame.action)
		_refresh_routes()
	for route_id: String in _routes:
		if _routes[route_id] and not bool(previous_routes.get(route_id, false)): _events.append("bridge_opened:" + route_id)
	if _open_turns(): _keep_footing(previous_routes)
	_check_hazards()
	if role == "a": _update_source_readiness()
	if (role == "b" or _shared_ball()) and stage.goal_policy.kind == "ball_home": _check_ball_home()
	# Open turns: the goal holds while both pips stand at it (open_turns.gd), a ball home goal with its ball in.
	if role == "b" and _open_turns(): _objective = _at_goal(active_slot) and _at_goal(memory_slot) and _goal_filled()
	tick += 1
	# Only a hazard (_check_hazards) can have ended the turn before this point.
	# Open turns finish the moment both pips are at the lit goal; the rest of the friend's replay is dropped.
	if role == "b" and _objective and (_open_turns() or tick >= int(_prior.duration_ticks)) and not finished and _may_complete():
		complete = true
		finished = true
		if _keeps_routes_at_completion():
			for route_id: String in _routes:
				if (_routes[route_id] or _holds_ball(route_id)) and route_id not in _mechanisms.latched_bridges and _kept_open(route_id): _mechanisms.latched_bridges.append(route_id)
		_mechanisms.latched_bridges.sort()
		_events.append("stage_complete")
	if tick >= duration_limit():
		finished = true
		_events.append("turn_finished")
	if _open_turns() and tick == replay_ticks(): _keep_handoff()
	if (tick % TICK_RATE == 0 or finished) and not _plays_friend_world: _checks.append({"tick":tick,"state_hash":state_hash()})

const SLOTS := ["p0", "p1"]
const STILL := {"x": 0, "z": 0, "action": false}

## Open turns: one tick of the one world. Each pip walks by its own input,
## the live pip by `frame` and the other by the friend's replay (standing once
## it is over, and in a first turn), then each presses; p0 goes first both
## times, so a pip does the same live or replayed, and the world differs from
## the friend's turn only by what the live pip does differently.
func _play_both(frame: Dictionary) -> void:
	var frames := {active_slot: frame, memory_slot: _friend_frame()}
	_before_moves()
	_refresh_routes()
	if _plays_friend_world: _move_floor = {"routes": _walk_routes(memory_slot).duplicate(), "levers": _mechanisms.levers.duplicate()}
	for slot: String in SLOTS: _move(frames[slot], slot)
	for slot: String in SLOTS: _after_move(slot)
	_refresh_routes()
	var held := {active_slot: _held, memory_slot: _friend_held}
	for slot: String in SLOTS:
		if bool(frames[slot].action) and not bool(held[slot]) and _drowned.is_empty(): _interact(slot)
	_after_interact()
	_held = bool(frame.action)
	_friend_held = bool(frames[memory_slot].action)
	_refresh_routes()

## Open turns: the friend's input this tick, its turn's from H on, then standing still.
func _friend_frame() -> Dictionary:
	var index := handoff_tick + tick
	return quantize_input(_prior_frames[index]) if role == "b" and index < _prior_frames.size() else STILL

## Open turns: M, how long the friend's replay plays beside this turn: the
## rest of the friend's turn after the hand-off (0 for a first turn).
func replay_ticks() -> int:
	return maxi(0, int(_prior.get("duration_ticks", 0)) - handoff_tick) if role == "b" and _open_turns() else 0

## Open turns: keeps the world at tick M, the next turn's start.
func _keep_handoff() -> void:
	_handoff_world = save_world()
	_handoff_hash = Canonical.digest(_handoff_world)

## Open turns, a trusted turn whose start no proof gave (an unregistered
## level, or kept worlds off): `prior` played again over the turns before it,
## once each from the checkpoint, to its hand-off.
func _played_start(definition: Dictionary, stage_id: String, checkpoint: Dictionary, prior: Dictionary, chain: Array) -> Dictionary:
	var again: RefCounted = _new_simulation()
	again.simulation_version = simulation_version
	again.catch_assistance = bool(prior.get("catch_assistance", true))
	var first := chain.is_empty()
	again._reset_trusted(definition, stage_id, checkpoint, {} if first else chain.back(), "a" if first else "b", chain.slice(0, maxi(0, chain.size() - 1)))
	for input: Dictionary in expand_recording_inputs(prior): again._tick(input)
	var lengths: Array = (chain + [prior]).map(func(each: Dictionary) -> int: return int(each.get("duration_ticks", 0)))
	return {"world": again.handoff_world(), "handoff_tick": OpenTurns.handoff_tick(lengths, chain.size() + 2)}

## Open turns: the world at tick M, the next turn's start ({} before then).
func handoff_world() -> Dictionary:
	return _handoff_world.duplicate(true)

## Open turns: the whole world as it stands, every value a later tick reads:
## both pips, what each holds and whether it holds its button, the mechanisms
## (levers, controls, props, items), the routes and a facade's own
## (_save_extra: timers as ticks left, latches, the water). The same at a
## turn's start as at the tick of the turn before it hands off on, so its hash
## (world_hash) proves a hand-off. Never the tick, the role or the turns.
func save_world() -> Dictionary:
	var entries := _comfort_entries.keys()
	entries.sort()
	var world := {"players": _players.duplicate(true), "mechanisms": _mechanisms.duplicate(true), "routes": _routes.duplicate(),
		"held": {active_slot: _held, memory_slot: _friend_held}, "entered_routes": entries}
	if not _drowned.is_empty(): world["drowned"] = _drowned.duplicate()
	_save_extra(world)
	return world

func world_hash() -> String:
	return Canonical.digest(save_world())

## Open turns: takes over `world` (save_world) at this turn's tick 0, with the
## friend's replay from tick `handoff` of its turn on.
func load_world(world: Dictionary, handoff: int) -> void:
	handoff_tick = handoff
	_players = world.players.duplicate(true)
	_mechanisms = world.mechanisms.duplicate(true)
	_routes = world.routes.duplicate()
	_held = bool(world.held.get(active_slot, false))
	_friend_held = bool(world.held.get(memory_slot, false))
	_comfort_entries = {}
	for id: Variant in world.entered_routes: _comfort_entries[str(id)] = true
	_drowned = world.get("drowned", {}).duplicate()
	_load_extra(world)
	# The friend's own world starts here too, until the live pip does anything.
	_start_world = world
	_live_moved = false
	_friend_world = null

func _advance_source() -> void:
	var open := _open_controls()
	var before: Dictionary = _source_values() if open else {}
	if tick < _prior_frames.size(): _source._tick(_prior_frames[tick])
	_players[memory_slot] = _source._players[memory_slot].duplicate(true)
	if open: _source_toggles = _changed_since(before)
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

## `slot`: the live pip unless named (open turns walk the friend's replay too).
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
		if not _drowned.is_empty(): return
		var next := Vector2i(roundi(float(delta.x * index) / steps), roundi(float(delta.y * index) / steps))
		var unit := next - walked
		walked = next
		if _try_move(unit, cells, routes, slot): continue
		if unit.x != 0: _try_move(Vector2i(unit.x, 0), cells, routes, slot)
		if unit.y != 0: _try_move(Vector2i(0, unit.y), cells, routes, slot)

## cells: this definition's floor index (_navigation_cells()), fetched once per move.
## routes: the crossings the walker may step on (_walk_routes()), likewise.
## The live pip pushes a prop here, and under the shared ball either pip.
func _try_move(delta: Vector2i, cells: Dictionary, routes: Dictionary, slot: String = "") -> bool:
	if slot.is_empty(): slot = active_slot
	var previous: Dictionary = _players[slot]
	var x := int(previous.x) + delta.x
	var z := int(previous.z) + delta.y
	var position := Navigation.at(level, routes, _mechanisms.levers, previous, x, z, slot, PLAYER_RADIUS, true, cells)
	if position.is_empty():
		var gone := _floor_went(previous, x, z, slot, cells)
		if gone.is_empty(): return false
		# The friend's replay steps out where its floor was, and falls.
		_players[slot] = gone.at
		_lose_footing(slot, str(gone.route))
		return true
	if _in_solid(position, previous) or not _may_step(previous, position): return false
	var pushed: Variant = _pushes(previous, x, z, int(position.height), delta, slot, slot == active_slot or _shared_ball(), cells)
	if pushed == null: return false
	for id: String in pushed: _mechanisms.props[id] = pushed[id]
	_players[slot] = position
	if slot == active_slot and int(previous.height) > int(position.height) + 2: _events.append("drop")
	return true

## The props a pip of `slot` pushes stepping by `delta` from `previous` to
## (x, z) at `height`: {prop id: its state after the push}, or null when one
## it meets will not move. `pusher`: whether this pip may push at all (the
## live pip, or under the shared ball either pip).
func _pushes(previous: Dictionary, x: int, z: int, height: int, delta: Vector2i, slot: String, pusher: bool, cells: Dictionary) -> Variant:
	var pushed: Dictionary = {}
	for prop: Dictionary in level.get("props", []):
		var ball: Dictionary = _mechanisms.props[prop.id]
		var separation := PLAYER_RADIUS + int(prop.radius_cm)
		if height != int(ball.height) or Vector2i(x,z).distance_squared_to(Vector2i(ball.x,ball.z)) >= separation * separation: continue
		# A recorded prop may arrive inside B. Escape moves only the live player,
		# outward through legal floor; it never rewrites A or pushes through a wall.
		if _comfort_rules():
			var old_distance := Vector2i(previous.x,previous.z).distance_squared_to(Vector2i(ball.x,ball.z))
			var new_distance := Vector2i(x,z).distance_squared_to(Vector2i(ball.x,ball.z))
			if old_distance < separation * separation and new_distance > old_distance: continue
		if not pusher or not _can_push(ball): return null
		var moved := Navigation.at(level, _routes, _mechanisms.levers, ball, int(ball.x) + delta.x, int(ball.z) + delta.y, slot, int(prop.radius_cm), false, cells)
		if moved.is_empty(): return null
		var replacement := ball.duplicate(true)
		replacement.merge(moved, true)
		pushed[prop.id] = replacement
	return pushed

## The shared ball: whether a ball rests on crossing `route_id`. A stage's end
## keeps that crossing, shut or not, so the next stage never starts with its
## ball on a crossing that is down.
func _holds_ball(route_id: String) -> bool:
	if not _shared_ball(): return false
	for id: String in _mechanisms.props:
		if str(_mechanisms.props[id].surface_id) == route_id: return true
	return false

## Whether rules `simulation_version` play the shared ball (SHARED_BALL_RULES).
func _shared_ball() -> bool:
	return simulation_version in SHARED_BALL_RULES

## Whether a pip may step from `previous` to `position` (a facade's own
## floors that move: the journey's platforms). Always, here.
func _may_step(_previous: Dictionary, _position: Dictionary) -> bool:
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
	if _shared_ball(): return true
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

## `slot`: the pip that pressed, the live one unless named.
func _interact(slot: String = "") -> void:
	var action := _context_for(active_slot if slot.is_empty() else slot)
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

## What the live pip's button does here.
func context_action() -> Dictionary:
	return _context_for(active_slot)

## What `slot`'s button does here (open turns press for the friend's replay too).
func _context_for(slot: String) -> Dictionary:
	if level.is_empty(): return _action("", "", false, "")
	var player: Dictionary = _players[slot]
	for lever: Dictionary in stage.get("levers", []):
		if (_open_controls() or lever.owner_slot == slot) and _near_entity(player, lever):
			return _action("lever", "Pull lever", true, lever.id)
	# Open turns: no bell; both pips standing at the goal finish the stage.
	if role == "b" and stage.goal_policy.kind == "ring" and not _open_turns() and _near_entity(player, stage.goal):
		return _action("ring", "Ring bell", true, stage.goal.id)
	if stage.source_policy.kind == "offer_ball" and not _shared_ball() and slot == active_slot:
		var ball: Dictionary = _mechanisms.props[stage.source_policy.prop_id]
		if int(player.height) == int(ball.height) and Vector2i(player.x,player.z).distance_squared_to(Vector2i(ball.x,ball.z)) <= 64 * 64:
			if role == "a" and ball.status == "free" and _ball_at(stage.handoff, stage.source_policy.prop_id):
				return _action("offer", "Leave ball", _comfort_rules() or bool(_mechanisms.levers.get(stage.source_policy.lever_id, false)), stage.source_policy.prop_id)
			if role == "b" and ball.status == "offered": return _action("claim", "Take over", true, stage.source_policy.prop_id)
	return _action("", "", false, "")

## Under the shared ball it fits whoever rolled it in, in any turn, and the
## stage's end is the open turns check in _tick (_at_goal, _goal_filled).
func _check_ball_home() -> void:
	if not (_claimed or _shared_ball()) or not _ball_at(stage.goal, stage.goal_policy.prop_id): return
	var ball: Dictionary = _mechanisms.props[stage.goal_policy.prop_id]
	if _shared_ball() and ball.status == "fitted": return
	if _comfort_rules() and not _snap_ball(stage.goal, stage.goal_policy.prop_id): return
	ball.status = "fitted"
	ball.holder_slot = ""
	ball.socket_id = stage.goal_policy.socket_id
	if not _shared_ball(): _objective = true

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
	if level.is_empty() or not error.is_empty() or tick == 0 or not _drowned.is_empty(): return false
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

## Open turns: whether the live pip may pass now. The friend's replay is over,
## the stage is not done, the room lets this turn pass (pass_allowed) and the
## facade's rules agree (_may_pass).
func can_pass() -> bool:
	return _open_turns() and role == "b" and pass_allowed and error.is_empty() and not finished and not complete and tick >= replay_ticks() and _may_pass()

## Open turns: whether the live pip may end this turn now, while the friend's
## replay still plays. The screen then plays the rest of the replay with the
## pip standing still (still ticks, recorded as any other), so the turn is the
## one a pip standing there would record; the stage completes the moment the
## replay brings the friend to the goal, or the turn passes once it is over.
func can_end_early() -> bool:
	return _open_turns() and role == "b" and error.is_empty() and not finished and not complete and tick < replay_ticks()

## Open turns: ends this turn as a pass. The recording is the turn so far,
## unfinished; play goes to the other pip.
func pass_turn() -> Dictionary:
	if not can_pass(): return snapshot()
	passed = true
	finished = true
	_events = ["turn_passed"]
	return snapshot()

## Open turns: whether `slot`'s pip stands at the goal now, where it holds:
## by the bell, or under the shared ball on a ball home cradle's floor.
func _at_goal(slot: String) -> bool:
	if stage.goal_policy.kind == "ball_home" and _shared_ball(): return str(_players[slot].surface_id) == str(stage.goal.surface_id)
	return stage.goal_policy.kind == "ring" and _near_entity(_players[slot], stage.goal)

## The snapshot's objective_done: the objective, or under open turns in a
## later turn whether the live pip stands at the lit goal with the goal's own
## part holding (it dozes there while the friend's replay plays on); the
## stage itself is done ("complete") once both pips are there.
func _objective_done() -> bool:
	if role == "b" and _open_turns(): return _at_goal(active_slot) and _goal_filled()
	return _objective

## Open turns: whether the goal's own part holds: a ball home goal's ball in
## its cradle. A bell has none.
func _goal_filled() -> bool:
	if stage.goal_policy.kind != "ball_home": return true
	return str(_mechanisms.props.get(str(stage.goal_policy.prop_id), {}).get("status", "")) == "fitted"

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
	var lost := _lost_reason()
	if not lost.is_empty(): return lost
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

## What a turn a pip drowned or fell in says, or "" when none did.
func _lost_reason() -> String:
	if _drowned.is_empty(): return ""
	var yours := str(_drowned.get("slot", "")) == active_slot
	if _drowned.has("fell"): return FELL_YOU if yours else FELL_FRIEND
	return DROWNED_YOU if yours else DROWNED_FRIEND

## Whether this turn may be kept anywhere: a draft, a replay or an upload. A
## turn a pip drowned or fell in is not, whoever it was; the screen still holds
## it for Preview.
func keeps_draft() -> bool:
	return _drowned.is_empty()

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
		# The shared ball shows the colour of a pip touching it, the live one first.
		if _shared_ball() and ball.status == "free":
			controller = ""
			for slot: String in ([active_slot, memory_slot] if role == "b" else [active_slot]):
				var touching: Dictionary = _players[slot]
				var reach := PLAYER_RADIUS + int(_entity(level.props,id).radius_cm) + 2
				if int(touching.height) == int(ball.height) and Vector2i(touching.x,touching.z).distance_squared_to(Vector2i(ball.x,ball.z)) <= reach * reach:
					controller = slot
					break
		if not controller.is_empty():
			var actor: Dictionary = _players[controller]
			var radius := PLAYER_RADIUS + int(_entity(level.props,id).radius_cm) + 2
			if int(actor.height) != int(ball.height) or Vector2i(actor.x,actor.z).distance_squared_to(Vector2i(ball.x,ball.z)) > radius * radius: controller = ""
		ball["controller_slot"] = controller
	var state := {"schema_version":_schema_version(),"stage_id":stage.id,"role":role,"active_slot":active_slot,"first_player_slot":first_player_slot,
		"tick":tick,"time_seconds":float(tick)/TICK_RATE,"duration_ticks":duration_limit(),"complete":complete,"finished":finished,"can_commit":can_commit(),
		"commit_reason":commit_reason(),"error":error,"message":str(stage.get("hint_"+role,"")),"players":players,"mechanisms":_mechanisms.duplicate(true),
		"bridges":_routes.duplicate(),"props":displayed_props,"levers":_mechanisms.levers.duplicate(),"hold_pads":pads,
		"objective_done":_objective_done(),"route_progress":{"kept_bridges":_mechanisms.latched_bridges.duplicate()},"source_hold_ticks":_hold_ticks,"offer_tick":_offer_tick,
		"outcome":_outcome(),"events":_events.duplicate(),"context_action":context_action(),"objective_display":_objective_display(),"optics":{"segments":[],"signals":{}},"beacon":_objective}
	# Open turns only, so a published chapter's snapshot stays byte for byte as it was.
	if _open_turns(): state.merge({"drowned":_drowned.duplicate(),"turn_number":turn_number,"can_pass":can_pass(),"can_end_early":can_end_early(),"passed":passed,"handoff_tick":handoff_tick,"replay_ticks":replay_ticks()})
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
	# Open turns: H, the world at the start and at tick M (the next turn's start; "" before then).
	if _open_turns(): record.merge({OpenTurns.HANDOFF_TICK: handoff_tick, OpenTurns.START_HASH: _start_hash, OpenTurns.HANDOFF_HASH: _handoff_hash})
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
	if _open_turns(): value["friend_held"] = _friend_held
	# Only once someone drowned or fell, so every other hash stays as it was.
	if not _drowned.is_empty(): value["drowned"] = _drowned.duplicate()
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

func _new_simulation() -> RefCounted:
	assert(false, "A physical simulation needs its sealed facade factory.")
	return null

func _proof_engine() -> RefCounted:
	assert(false, "A physical simulation needs its sealed proof adapter.")
	return null

func _reset_mechanics() -> void:
	pass

## Open turns: a facade's own world values into `world` (save_world), and
## back (load_world, at tick 0). Published rules have none.
func _save_extra(_world: Dictionary) -> void:
	pass

func _load_extra(_world: Dictionary) -> void:
	pass

## Open turns: at the start of each tick, before either pip moves.
func _before_moves() -> void:
	pass

## The crossings slot's pip may step onto this tick: the open ones, less any
## a facade's rules keep it off (the pieces rules: a pip carrying an item never climbs
## a crossing that needs both hands). Never changes the routes themselves.
func _walk_routes(_slot: String) -> Dictionary:
	return _routes

## After the live pip's press, before the routes are worked out again: a
## facade whose things move on a press (the pieces rules' current) moves them here.
## Published rules have none.
func _after_interact() -> void:
	pass

## After a tick's routes are final, before readiness and completion: a facade
## whose rules can end a turn early (a spirit caught on a shut crossing) sets
## `finished` here. Published rules have none.
func _check_hazards() -> void:
	pass

## Open turns, once a tick's routes are final: each pip whose floor went from
## under it this tick keeps its footing (the rule by WATER_CHAPTERS above).
## Only a crossing that stood at the tick's start and is shut now (`was`: the
## routes then) can take a pip's floor, since every step a pip takes is onto
## floor, so no other tick looks. p0 first; the first that falls ends the turn.
## A facade may keep a pip up on its shut crossing (_stands_fast).
func _keep_footing(was: Dictionary) -> void:
	if not _drowned.is_empty(): return
	var went := false
	for id: String in _routes:
		if not _routes[id] and bool(was.get(id, false)): went = true
	if not went: return
	var cells := _navigation_cells()
	for slot: String in SLOTS:
		var player: Dictionary = _players[slot]
		var surface := str(player.surface_id)
		var shut := _routes.has(surface) and not bool(_routes[surface])
		var here := Navigation.at(level, _routes, _mechanisms.levers, player, int(player.x), int(player.z), slot, PLAYER_RADIUS, false, cells)
		if (not shut and not here.is_empty()) or _stands_fast(slot): continue
		var spot := _footing_near(player, slot, cells)
		if not spot.is_empty():
			_players[slot] = spot
			_events.append("stepped_back:" + slot)
			continue
		_lose_footing(slot, surface)
		return

## Open turns: `slot`'s pip lost its floor `surface` and falls into the sky,
## or drowns in a water chapter; the turn ends there.
func _lose_footing(slot: String, surface: String) -> void:
	_drowned = {"slot": slot, "route": surface, "tick": tick}
	if str(level.get("id", "")) not in WATER_CHAPTERS: _drowned.merge({"fell": true, "sky": true})
	finished = true
	_events.append(("fell:" if _drowned.has("fell") else "drowned:") + slot)

## Open turns: {"at": where the friend's replay stands, "route": the crossing
## whose floor went} once its step from `previous` to (x, z), refused here,
## goes there because the friend's own world had floor there (_friend_floor)
## and nothing stands there here, even with both hands free (a crossing shut,
## a lift or raft gone); else {} and it keeps to its floor. Only once the live
## pip has done anything, since until then the two worlds are one.
func _floor_went(previous: Dictionary, x: int, z: int, slot: String, cells: Dictionary) -> Dictionary:
	if role != "b" or slot != memory_slot or _plays_friend_world or not _live_moved or tick >= replay_ticks() or not _open_turns(): return {}
	if not Navigation.at(level, _routes, _mechanisms.levers, previous, x, z, slot, PLAYER_RADIUS, true, cells).is_empty(): return {}
	var floor := _friend_floor()
	if floor.is_empty(): return {}
	var there := Navigation.at(level, floor.routes, floor.levers, previous, x, z, slot, PLAYER_RADIUS, true, cells)
	if there.is_empty() or _in_solid(there, previous): return {}
	# The crossing under its footprint that held there and is shut here (a centre still over a bank names the crossing).
	for route: Dictionary in level.get("bridges", []) + level.get("stairs", []):
		if bool(floor.routes.get(route.id, false)) and not bool(_routes.get(route.id, false)) and Navigation._circle_rect(Vector2i(x, z), PLAYER_RADIUS, route.rect_cm):
			return {"at": there, "route": str(route.id)}
	return {"at": there, "route": str(there.surface_id)}

## The floor the friend's replay walked on at this tick in the friend's own
## world: this turn played from its start with the live pip standing still,
## made the first time it is asked for and played on as far as each ask needs.
## {} once that world has ended.
func _friend_floor() -> Dictionary:
	if _friend_world == null:
		_friend_world = _new_simulation()
		_friend_world.simulation_version = simulation_version
		_friend_world.catch_assistance = catch_assistance
		_friend_world._plays_friend_world = true
		# Only the chain's length is read (this turn's number) once the start is given.
		var chain: Array = []
		chain.resize(turn_number - 2)
		_friend_world._reset_trusted(level, str(stage.id), _checkpoint, _prior, role, chain, {"world": _start_world, "handoff_tick": handoff_tick})
	while _friend_world.tick <= tick and not _friend_world.finished and _friend_world.error.is_empty(): _friend_world._tick({})
	return _friend_world._move_floor if _friend_world.tick == tick + 1 else {}

## The nearest spot within FOOTING_REACH a pip at `player` may stand on (its
## whole footprint on floor at its height, off every solid), when its walk
## radius still touches floor; else {}: nothing holds it.
func _footing_near(player: Dictionary, slot: String, cells: Dictionary) -> Dictionary:
	if not Navigation.touches(level, _routes, player, slot, PLAYER_RADIUS, cells): return {}
	for offset: Vector2i in Navigation.offsets_by_distance(FOOTING_REACH):
		var spot := Navigation.at(level, _routes, _mechanisms.levers, player, int(player.x) + offset.x, int(player.z) + offset.y, slot, PLAYER_RADIUS, false, cells)
		if not spot.is_empty() and not _in_solid(spot): return spot
	return {}

## Whether `slot`'s pip stays where it stands though its crossing shut (a
## facade's own rule: the tide's stone left high). None here.
func _stands_fast(_slot: String) -> bool:
	return false

## Whether this facade plays open controls (OPEN_RULES_VERSION). Published
## rules never do.
func _open_controls() -> bool:
	return false

## Whether these rules play open turns (open_turns.gd).
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

## `slot`: the pip that walked, the live one unless named. Open turns latch
## for either pip in every turn; published rules for the second turn's live pip.
func _after_move(slot: String = "") -> void:
	if slot.is_empty(): slot = active_slot
	if not _comfort_rules() or (role != "b" and not _open_turns()): return
	var player: Dictionary = _players[slot]
	var point := Vector2i(player.x, player.z)
	var diagonal := int(ceil(float(PLAYER_RADIUS)*0.707107))
	for route: Dictionary in level.get("bridges", []) + level.get("stairs", []):
		if not bool(_routes.get(route.id, false)) or not Navigation._owns(route, slot): continue
		for offset: Vector2i in [Vector2i.ZERO,Vector2i(PLAYER_RADIUS,0),Vector2i(-PLAYER_RADIUS,0),Vector2i(0,PLAYER_RADIUS),Vector2i(0,-PLAYER_RADIUS),Vector2i(diagonal,diagonal),Vector2i(-diagonal,diagonal),Vector2i(diagonal,-diagonal),Vector2i(-diagonal,-diagonal)]:
			var sample := point + offset
			if not Navigation.inside(sample, route.rect_cm): continue
			var height: int = Navigation.stair_height(route,sample) if route.has("axis") else int(route.height_cm)
			if absi(height-int(player.height)) <= PLAYER_RADIUS+1:
				_comfort_entries[route.id] = true
				break

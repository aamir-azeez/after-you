extends RefCounted
## The wait at the end of a second turn: the live spirit has done its part
## (rung the bell, planted the seed, lit the court) and its friend's memory is
## still playing. Every chapter screen and replay that steps a recorded turn
## feeds its ticks through one of these, so the wait looks and sounds the same
## live, after a retry, in a resumed draft and in every replay.
##
## While the memory plays on, the finished spirit dozes by its goal and the
## camera follows the memory. When the memory ends (the tick the simulation
## completes the stage) the spirit wakes with a start, and only then does the
## goal ring: its cue, the goal's glow and the celebration were held back from
## the press. The press itself is simulated and recorded as usual.
##
## Presentation only. The simulation is stepped exactly as before; this reads
## its snapshots and changes what the world is shown and when held cues sound.
## A held cue keeps the pitch it got at the press (Soundscape.consume_turn_events
## works out its identity on that tick), so it sounds the same everywhere.

## Goal events that ring. Their cue waits for the friend; other goal events
## (a seed planted, a lens fitted) are placements and sound at once.
const RING_EVENTS := ["bell", "loft_opened", "court_activated", "beacon_lit", "tower_anchored"]
## Outcome flags that mean the second spirit's part is done, for engines whose
## snapshot has no objective_done (the relay and First Steps).
const OBJECTIVE_OUTCOMES := ["placed_relay", "planted_seed", "reached_loft"]
## How close (metres) a dozing spirit must be to its goal to lean on it.
const LEAN_REACH := 1.6
const SpiritVisual = preload("res://presentation/spirit_visual.gd")
const TICK_RATE := 30.0
## Hold to fast-forward plays up to this many ordinary ticks per physics tick.
const FAST_FORWARD_TICKS := 4
## Fast-forward and Skip stop stepping for this frame once this much time is
## spent (a heavy chapter on a slow phone), so the screen keeps drawing. Only
## how fast the wait goes by changes; the ticks are the same.
const STEP_BUDGET_USEC := 8000
## What a fast-forwarded or skipped tick feeds the simulation: no movement and
## no press, as a still player at normal speed would.
const STILL_INPUT := {"move_x": 0.0, "move_z": 0.0, "interact": false}

## The world being shown, the soundscape playing the turn, and how this screen
## shows a state (it may relabel badges first). Set once by the owner.
var world: Node
var soundscape: Node
var present_state: Callable
var reduced_motion := false

var _role := ""
var _prior_end := 0
## Tick at which the objective was first seen done; -1 before.
var _objective_tick := -1
var _waiting := false
var _tick := 0
## The memory ended after a wait; seconds since, while the ring is pending.
var _arrived := false
var _arrival_age := 0.0
## Goal visuals and cues are being held back.
var _holding := false
var _live_key := ""
var _memory_key := ""
var _last_state: Dictionary = {}
## The hold ends right after this tick is shown (Reduce motion, or a turn
## that ran out before the memory ended).
var _ring_after_present := false
## Set once a wait has happened in this turn (tests and captures read it).
var waited := false
var rings_released := 0
## Skip to end is under way (see skip_tick).
var skipping := false
## This screen's frame budget for Fast-forward and Skip (tests vary it).
var step_budget_usec := STEP_BUDGET_USEC

## A recorded turn starts at tick zero. `prior_ticks` is the length of the
## memory being followed; a first turn has none and never waits.
func begin(role: String, prior_ticks: int) -> void:
	_role = role
	_prior_end = maxi(0, prior_ticks)
	_objective_tick = -1
	_waiting = false
	_tick = 0
	_arrived = false
	_arrival_age = 0.0
	_holding = false
	_ring_after_present = false
	_live_key = ""
	_memory_key = ""
	_last_state = {}
	waited = false
	rings_released = 0
	skipping = false
	if is_instance_valid(soundscape) and soundscape.has_method("drop_held_cues"): soundscape.drop_held_cues()
	_release_world()

## The prior recording's length, read the same way on every screen.
static func prior_ticks(prior: Variant) -> int:
	return int(prior.get("duration_ticks", 0)) if prior is Dictionary else 0

## True while the live spirit is done and the memory still plays.
func waiting() -> bool:
	return _waiting

## Seconds of memory left, and how much of the wait is still ahead (1 to 0).
func remaining_seconds() -> float:
	return maxf(0.0, float(_prior_end - _tick)) / TICK_RATE if _waiting else 0.0

func remaining_ratio() -> float:
	if not _waiting: return 0.0
	var span := _prior_end - _objective_tick
	return clampf(float(_prior_end - _tick) / float(maxi(1, span)), 0.0, 1.0)

## The last tick before the memory ends; a skip steps silently up to here.
func last_waiting_tick() -> int:
	return _prior_end - 1

func ring_pending() -> bool:
	return _arrived and _holding

## One simulated tick, shown and heard. `sounds` is {cues, sources} from the
## chapter's sound map. Returns the state as the world should show it.
func step(state: Dictionary, sounds: Dictionary, live_play: bool, immediate: bool = false) -> Dictionary:
	var hold := _observe(state, sounds)
	if is_instance_valid(soundscape):
		# Stand-in soundscapes in tests take the plain three arguments.
		if hold.is_empty(): soundscape.consume_turn_events(sounds.get("cues", []), sounds.get("sources", []), live_play)
		else: soundscape.consume_turn_events(sounds.get("cues", []), sounds.get("sources", []), live_play, hold)
	var shown := shown_state(state)
	_show(shown, immediate)
	return shown

## One tick stepped without being shown (a resumed draft, a skip): cue
## identities still advance, and a press made in the wait is still held.
func step_silently(state: Dictionary, sounds: Dictionary) -> void:
	var hold := _observe(state, sounds)
	if not is_instance_valid(soundscape): return
	if hold.is_empty(): soundscape.note_turn_events(sounds.get("cues", []), sounds.get("sources", []))
	else: soundscape.note_turn_events(sounds.get("cues", []), sounds.get("sources", []), hold)

## One physics tick of Hold to fast-forward: the same ticks through the
## screen's own `advance` (which shows and sounds each one), up to
## FAST_FORWARD_TICKS of them, at least one. `playing` says the turn still runs.
func fast_forward_tick(advance: Callable, playing: Callable) -> void:
	var started := Time.get_ticks_usec()
	for index in range(FAST_FORWARD_TICKS):
		if not _waiting or not playing.call(): return
		if index > 0 and Time.get_ticks_usec() - started > step_budget_usec: return
		advance.call(STILL_INPUT)

## One physics tick of Skip to end: steps the memory silently (cue identities
## still advance) for up to STEP_BUDGET_USEC, showing where it got to, and
## once only the last tick is left, places the world there and plays the
## friend's arrival through `advance` as usual. Returns the state reached
## while the skip goes on, or {} when it is over.
func skip_tick(sim: RefCounted, sounds: Callable, advance: Callable) -> Dictionary:
	var started := Time.get_ticks_usec()
	var last := last_waiting_tick()
	var state: Dictionary = {}
	while skipping and _waiting and _tick < last and not bool(sim.get("finished")) and str(sim.get("error")).is_empty():
		state = sim.step(STILL_INPUT)
		step_silently(state, sounds.call(state))
		if Time.get_ticks_usec() - started > step_budget_usec:
			show(state, false)
			return state
	var arriving := skipping and _waiting
	skipping = false
	if not arriving: return {}
	show(sim.snapshot(), true)
	advance.call(STILL_INPUT)
	return {}

## Shows a state outside the tick path (a draft resumed, a replay restarted).
func show(state: Dictionary, immediate: bool) -> void:
	_show(shown_state(state), immediate)

## Each rendered frame while the world runs: the ring waits for the wake.
func advance(delta: float) -> void:
	if not _arrived or not _holding: return
	_arrival_age += maxf(0.0, delta)
	if _arrival_age >= ring_at(): _ring()

## Rings at once if the ring is still waiting (a screen that stops the world).
func ring_now() -> void:
	if _holding: _ring()

## Seconds from the friend's arrival to the ring.
func ring_at() -> float:
	return 0.0 if reduced_motion else SpiritVisual.WAKE_RING_AT

## The state the world is shown: while the ring is held, the goal looks
## untouched and the stage unsolved, so its glow and celebration wait.
func shown_state(state: Dictionary) -> Dictionary:
	if not _holding or state.is_empty(): return state
	var shown := state.duplicate()
	shown["ring_held"] = true
	if shown.has("objective_done"): shown["objective_done"] = false
	if shown.get("complete", false): shown["complete"] = false
	var beacon: Variant = shown.get("beacon")
	if beacon is bool: shown["beacon"] = false
	elif beacon is Dictionary and bool(beacon.get("lit", false)):
		var unlit: Dictionary = beacon.duplicate()
		unlit["lit"] = false
		shown["beacon"] = unlit
	return shown

## Which cues of this tick to hold, and the wait's state after it.
func _observe(state: Dictionary, sounds: Dictionary) -> PackedInt32Array:
	var hold := PackedInt32Array()
	if state.is_empty(): return hold
	_tick = int(state.get("tick", _tick))
	_last_state = state
	_find_keys(state)
	if _role != "b" or _prior_end <= 0: return hold
	var done := objective_done(state)
	var complete := bool(state.get("complete", false))
	if done and _objective_tick < 0:
		_objective_tick = _tick
		if not complete and _tick < _prior_end:
			# The press, made before the memory ends: its ring waits.
			waited = true
			_holding = true
			hold.append_array(_ring_indices(sounds))
	var was_waiting := _waiting
	_waiting = done and not complete and not bool(state.get("finished", false)) and _tick < _prior_end
	if _holding and complete and not _arrived:
		# The memory ended: the spirit wakes, and this tick's cues (the bloom)
		# follow the ring rather than sounding over the startle.
		_arrived = true
		_arrival_age = 0.0
		for index in range(sounds.get("cues", []).size()): hold.append(index)
		_wake()
		if reduced_motion: _ring_after_present = true
	elif _holding and not complete and bool(state.get("finished", false)):
		# The turn ran out with the memory still playing: nothing to wait for.
		_ring_after_present = true
	# Arrival hands over to the wake; the world lets go after the ring.
	if _waiting or (was_waiting and not _arrived): _apply_wait()
	return hold

func _show(shown: Dictionary, immediate: bool) -> void:
	if present_state.is_valid(): present_state.call(shown, immediate)
	elif is_instance_valid(world): world.present(shown, immediate)
	# A placement resets spirit motion; the doze is put back straight away.
	if _waiting and immediate: _apply_wait(true)
	if _ring_after_present:
		_ring_after_present = false
		_ring()

## Ends the hold: the held cues sound in order and the world sees the truth.
func _ring() -> void:
	if not _holding: return
	_holding = false
	rings_released += 1
	if is_instance_valid(soundscape) and soundscape.has_method("release_held_cues"): soundscape.release_held_cues()
	if not _last_state.is_empty():
		if present_state.is_valid(): present_state.call(_last_state, false)
		elif is_instance_valid(world): world.present(_last_state, false)
	_release_world()

static func objective_done(state: Dictionary) -> bool:
	if state.has("objective_done"): return bool(state.objective_done)
	var outcome: Variant = state.get("outcome", {})
	if outcome is Dictionary:
		for key: String in OBJECTIVE_OUTCOMES:
			if bool(outcome.get(key, false)): return true
	return false

static func _ring_indices(sounds: Dictionary) -> PackedInt32Array:
	var indices := PackedInt32Array()
	var sources: Array = sounds.get("sources", [])
	for index in range(sounds.get("cues", []).size()):
		var source := str(sources[index]) if index < sources.size() else ""
		var kind := source.get_slice("|", 1) if source.contains("|") else source
		if kind in RING_EVENTS: indices.append(index)
	return indices

func _find_keys(state: Dictionary) -> void:
	var players: Variant = state.get("players", {})
	if not players is Dictionary: return
	_memory_key = ""
	for key: Variant in players:
		if players[key] is Dictionary and bool(players[key].get("ghost", false)): _memory_key = str(key)
	_live_key = str(state.get("active_slot", ""))
	if not players.has(_live_key) or _live_key == _memory_key:
		_live_key = ""
		for key: Variant in players:
			if str(key) != _memory_key: _live_key = str(key)
	# The island worlds name their spirits by role, not slot.
	if is_instance_valid(world) and world.get("actors") is Dictionary:
		var actors: Dictionary = world.actors
		if not actors.has(_live_key) and actors.has("b"): _live_key = "b"
		if not actors.has(_memory_key) and actors.has("a"): _memory_key = "a"

## Doze by the goal and let the camera follow the memory.
func _apply_wait(immediate: bool = false) -> void:
	if not is_instance_valid(world) or not world.has_method("show_memory_wait"): return
	if _waiting: world.show_memory_wait(_live_key, _memory_key, immediate)
	else: world.end_memory_wait(_live_key)

func _wake() -> void:
	if is_instance_valid(world) and world.has_method("wake_from_memory_wait"): world.wake_from_memory_wait(_live_key, reduced_motion)

func _release_world() -> void:
	if is_instance_valid(world) and world.has_method("end_memory_wait"): world.end_memory_wait(_live_key)

extends RefCounted
## World kit: where the pips have been in the stage so far, for a drawing that
## remembers it (kit/fog_cover.gd's cleared fog). Only drawing reads it; nothing
## here reaches the simulation, a recording or a checkpoint.
##
## A stage's history is a pure function of its recorded turns, so a rebuild,
## a reconnect, a replay and a retry all show the same: both pips' starts, the
## path of each earlier turn's pip (on open turns a later turn's memory walks
## exactly the turn before it, so that covers the memories too) and every lever
## that turn had on at any tick (a lit lantern). Each earlier turn is read from
## its kept memory trace (core/physical/memory_trace.gd), or simulated again
## when no trace is kept, and boiled down once per recording to the 25 cm
## squares its pip stood in.
##
## The turn being played adds to that live, a tick at a time (note()): its own
## pip's squares and the levers it turns on, each with its tick, so going back
## to an earlier tick (a retry, a fresh turn) drops what came after.
const QUANTUM_CM := 25
const MOST_KEPT := 64

## Per recording hash: {"points": PackedInt32Array (x, z, height cm), "levers": {id: true}}.
static var _kept: Dictionary = {}

var history_points := PackedInt32Array()
var history_levers: Dictionary = {}
var _history_keys: Dictionary = {}
## The live turn: [tick, x, z, height] each, and [tick, lever id] each.
var live_points: Array = []
var live_levers: Array = []
var _live_keys: Dictionary = {}
var _lit: Dictionary = {}
var _tick := -1

## The history of the turn `sim` is set up to play (just after its reset):
## its stage's starts and every turn before it, `chain` (oldest first) then
## `prior` (the memory; {} on a stage's first turn). Plain data, for set_history.
static func of(sim: RefCounted, prior: Dictionary, chain: Array) -> Dictionary:
	var out := {"points": PackedInt32Array(), "levers": {}}
	if sim == null or not sim.get("_checkpoint") is Dictionary: return out
	var checkpoint: Dictionary = sim._checkpoint
	var seen := {}
	for slot: String in checkpoint.get("players", {}):
		_add(out.points, seen, checkpoint.players[slot])
	var turns: Array = chain.duplicate()
	if not prior.is_empty(): turns.append(prior)
	for index in range(turns.size()):
		var walked := _turn(sim, checkpoint, turns, index)
		var points: PackedInt32Array = walked.points
		for at in range(0, points.size(), 3):
			_add(out.points, seen, {"x": points[at], "z": points[at + 1], "height": points[at + 2]})
		out.levers.merge(walked.levers)
	return out

## One earlier turn's squares and levers, kept per recording.
static func _turn(sim: RefCounted, checkpoint: Dictionary, turns: Array, index: int) -> Dictionary:
	var record: Dictionary = turns[index]
	var id := "%s|%s" % [str(checkpoint.get("checkpoint_hash", "")), str(record.get("recording_hash", ""))]
	if _kept.has(id): return _kept[id]
	var walked := {"points": PackedInt32Array(), "levers": {}}
	var seen := {}
	var trace: Dictionary = sim._proof_engine().memory_trace(sim.level, record, checkpoint, turns.slice(0, index))
	if not trace.is_empty():
		var shared: Variant = null
		for frame: Array in trace.frames:
			_add(walked.points, seen, frame[0])
			if not is_same(frame[1], shared):
				shared = frame[1]
				_levers(walked.levers, frame[1])
	else:
		# No kept trace (traces off, or not kept): the turn again, as it was checked.
		var again: RefCounted = sim._new_simulation()
		again.simulation_version = sim.simulation_version
		again.catch_assistance = bool(record.get("catch_assistance", true))
		var first := index == 0
		again._reset_trusted(sim.level, str(record.get("stage_id", "")), checkpoint, {} if first else turns[index - 1], "a" if first else "b", turns.slice(0, maxi(0, index - 1)))
		for input: Dictionary in sim.expand_recording_inputs(record):
			again._tick(input)
			_add(walked.points, seen, again._players[again.active_slot])
			_levers(walked.levers, again._mechanisms)
	if _kept.size() >= MOST_KEPT: _kept.erase(_kept.keys()[0])
	_kept[id] = walked
	return walked

static func _levers(into: Dictionary, mechanisms: Dictionary) -> void:
	var levers: Dictionary = mechanisms.get("levers", {})
	for id: String in levers:
		if levers[id]: into[id] = true

## Adds `player`'s square (x, z, height cm) once.
static func _add(points: PackedInt32Array, seen: Dictionary, player: Variant) -> bool:
	if not player is Dictionary or not player.has("x"): return false
	var x := int(player.x)
	var z := int(player.z)
	var h := int(player.get("height", 0))
	var key := Vector3i(floori(x / float(QUANTUM_CM)), floori(z / float(QUANTUM_CM)), floori(h / float(QUANTUM_CM)))
	if seen.has(key): return false
	seen[key] = true
	points.append_array([x, z, h])
	return true

## Lets go of the kept turns (tests).
static func forget() -> void:
	_kept.clear()

## A new turn's history (of()'s data): the live part starts empty.
func set_history(history: Dictionary) -> void:
	history_points = history.get("points", PackedInt32Array())
	history_levers = history.get("levers", {}).duplicate()
	_history_keys.clear()
	for at in range(0, history_points.size(), 3):
		_history_keys[_key(history_points[at], history_points[at + 1], history_points[at + 2])] = true
	_clear_live()

## One tick of the turn being played: true when something new was walked or
## lit. A tick before the last one drops what came after it (a retry, a reset).
## New points and levers are in live_points / live_levers from `from_points` /
## `from_levers` on, unless `rewound` says the live part shrank.
func note(state: Dictionary) -> Dictionary:
	var tick := int(state.get("tick", 0))
	var changed := {"rewound": false, "from_points": live_points.size(), "from_levers": live_levers.size()}
	if tick < _tick:
		changed.rewound = _rewind(tick)
		changed.from_points = live_points.size()
		changed.from_levers = live_levers.size()
	_tick = tick
	var slot := str(state.get("active_slot", ""))
	var player: Variant = state.get("players", {}).get(slot)
	if player is Dictionary and player.has("x"):
		var key := _key(int(player.x), int(player.z), int(player.get("height", 0)))
		if not _history_keys.has(key) and not _live_keys.has(key):
			_live_keys[key] = true
			live_points.append([tick, int(player.x), int(player.z), int(player.get("height", 0))])
	var levers: Dictionary = state.get("levers", {})
	for id: String in levers:
		if levers[id] and not history_levers.has(id) and not _lit.has(id):
			_lit[id] = true
			live_levers.append([tick, id])
	return changed

## Every lever lit in the stage so far, history and live.
func levers_lit() -> Dictionary:
	var out := history_levers.duplicate()
	out.merge(_lit)
	return out

## Drops the live part after `tick`; true when anything went.
func _rewind(tick: int) -> bool:
	var kept_points := live_points.filter(func(entry: Array) -> bool: return int(entry[0]) <= tick)
	var kept_levers := live_levers.filter(func(entry: Array) -> bool: return int(entry[0]) <= tick)
	if kept_points.size() == live_points.size() and kept_levers.size() == live_levers.size(): return false
	_clear_live()
	for entry: Array in kept_points:
		_live_keys[_key(entry[1], entry[2], entry[3])] = true
		live_points.append(entry)
	for entry: Array in kept_levers:
		_lit[entry[1]] = true
		live_levers.append(entry)
	return true

func _clear_live() -> void:
	live_points = []
	live_levers = []
	_live_keys.clear()
	_lit.clear()
	_tick = -1

static func _key(x: int, z: int, h: int) -> Vector3i:
	return Vector3i(floori(x / float(QUANTUM_CM)), floori(z / float(QUANTUM_CM)), floori(h / float(QUANTUM_CM)))

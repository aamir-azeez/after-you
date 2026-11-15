extends RefCounted
## Open turns: each checked turn's result and memory trace, kept by recording
## hash. A later turn plays its memory back from the trace (Playback) instead
## of simulating every nested turn again, so starting or checking turn k costs
## one simulation, not k. two_pair_proof.gd fills it only from a turn that
## replayed exactly; runtime.gd plays it. A trace holds, per tick, exactly what
## a later turn reads of its memory (runtime.gd _memory_frame), so playing it
## back gives the same ticks as simulating it: live, memory, retry and replay.
## Bounded and shared by every engine and thread. Static vars live here, in a
## script that extends an engine class (tests/test_subclass_statics.gd).
## A turn needs only its memory's trace and makes its own, so a few suffice.
const MAX_TRACES := 4
const MAX_CHECKS := 256
## Persisted traces: once a service attaches a store (services/
## memory_trace_store.gd: `persist` writes an id's bytes, `restore` reads them
## back), every kept turn is also kept there, and a miss reads it back, so a
## restart does not replay the stage's turns again. Core never touches files.
## Bump TRACE_VERSION whenever what a turn plays changes without new rules; a
## kept turn under another stamp (this, the app version or Godot's) is ignored.
const TRACE_VERSION := 1
const MAX_BYTES := 8388608
## Frame slots, in _memory_frame order.
const PLAYER := 0
const MECHANISMS := 1
const OWN_TOGGLES := 2
const OWN_RANG := 3
const OFFER_TICK := 4
const HOLD_TICKS := 5
const HOLD_START := 6
const READY_BRANCH := 7
static var _traces: Dictionary = {}
static var _checks: Dictionary = {}
static var _lock := Mutex.new()
## Turns simulated by a check since the last clear; for tests and timing.
static var simulated := 0
## Tests turn it off to compare with simulating every nested memory.
static var enabled := true
## The attached store's writer (id, bytes) and reader (id) -> bytes; unset
## keeps turns in memory only.
static var persist := Callable()
static var restore := Callable()

## The cache key of `record` (its recording hash, already checked) under
## `factory`'s rules `version`.
static func key(factory: Script, version: int, record: Dictionary) -> String:
	return "%s|%d|%s" % [factory.resource_path, version, str(record.get("recording_hash", ""))]

## A kept check result, a copy; {} when none.
static func check(id: String) -> Dictionary:
	if not enabled: return {}
	_lock.lock()
	var found: Variant = _checks.get(id)
	if found != null: _touch(_checks, id)
	_lock.unlock()
	if found == null: found = _restore(id).get("check")
	return found.duplicate(true) if found is Dictionary else {}

## A kept trace ({"slot", "role", "frames"}), shared read only; {} when none.
static func trace(id: String) -> Dictionary:
	if not enabled: return {}
	_lock.lock()
	var found: Variant = _traces.get(id)
	if found != null: _touch(_traces, id)
	_lock.unlock()
	if found == null: found = _restore(id).get("trace")
	return found if found is Dictionary else {}

## Keeps a valid check and its trace, and persists them when a store is attached.
static func keep(id: String, result: Dictionary, frames: Array, slot: String, role: String) -> void:
	if not enabled: return
	var trace := {"slot": slot, "role": role, "frames": frames}
	_remember(id, result, trace)
	_lock.lock()
	simulated += 1
	var writer := persist
	_lock.unlock()
	if writer.is_valid():
		var bytes := encode(id, result, trace)
		if bytes.size() <= MAX_BYTES: writer.call(id, bytes)

static func _remember(id: String, result: Dictionary, trace: Dictionary) -> void:
	_lock.lock()
	_checks.erase(id)
	_checks[id] = result.duplicate(true)
	_traces.erase(id)
	_traces[id] = trace
	while _checks.size() > MAX_CHECKS: _checks.erase(_checks.keys()[0])
	while _traces.size() > MAX_TRACES: _traces.erase(_traces.keys()[0])
	_lock.unlock()

## This build's stamp: a persisted turn under any other is not trusted.
static func stamp() -> String:
	return "%d|%s|%s" % [TRACE_VERSION, str(ProjectSettings.get_setting("application/config/version", "")), str(Engine.get_version_info().get("string", ""))]

static func _sha256(bytes: PackedByteArray) -> PackedByteArray:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish()

## One kept turn as verified bytes: its size, SHA-256 and deflated body. A
## frame whose mechanisms are the previous frame's stores null in their place.
static func encode(id: String, result: Dictionary, trace: Dictionary) -> PackedByteArray:
	var packed: Array = []
	var previous: Variant = null
	for frame: Array in trace.frames:
		var copy := frame.duplicate()
		if previous != null and is_same(frame[MECHANISMS], previous): copy[MECHANISMS] = null
		previous = frame[MECHANISMS]
		packed.append(copy)
	var body := var_to_bytes([stamp(), id, result, trace.slot, trace.role, packed])
	return var_to_bytes([body.size(), _sha256(body), body.compress(FileAccess.COMPRESSION_DEFLATE)])

## encode's bytes back: {"check", "trace"}, or {} unless they verify whole as
## `id` under this build's stamp.
static func decode(id: String, bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_BYTES: return {}
	var outer: Variant = bytes_to_var(bytes)
	if not outer is Array or outer.size() != 3 or not outer[0] is int or outer[0] < 1 or outer[0] > MAX_BYTES * 16 or not outer[1] is PackedByteArray or not outer[2] is PackedByteArray: return {}
	var body: PackedByteArray = outer[2].decompress(outer[0], FileAccess.COMPRESSION_DEFLATE)
	if body.size() != outer[0] or _sha256(body) != outer[1]: return {}
	var value: Variant = bytes_to_var(body)
	if not value is Array or value.size() != 6 or value[0] != stamp() or value[1] != id or not value[2] is Dictionary or not value[5] is Array or value[5].is_empty(): return {}
	var frames: Array = []
	for item: Variant in value[5]:
		if not item is Array or item.size() != READY_BRANCH + 1: return {}
		var frame: Array = item
		if frame[MECHANISMS] == null:
			if frames.is_empty(): return {}
			frame[MECHANISMS] = frames[-1][MECHANISMS]
		frames.append(frame)
	return {"check": value[2], "trace": {"slot": str(value[3]), "role": str(value[4]), "frames": frames}}

## A kept turn read back from the attached store into memory, or {}.
static func _restore(id: String) -> Dictionary:
	_lock.lock()
	var reader := restore
	_lock.unlock()
	if not reader.is_valid(): return {}
	var bytes: Variant = reader.call(id)
	var kept := decode(id, bytes) if bytes is PackedByteArray else {}
	if not kept.is_empty(): _remember(id, kept.check, kept.trace)
	return kept

static func clear() -> void:
	_lock.lock()
	_traces.clear()
	_checks.clear()
	simulated = 0
	_lock.unlock()

static func _touch(entries: Dictionary, id: String) -> void:
	var value: Variant = entries[id]
	entries.erase(id)
	entries[id] = value

## Adds `simulation`'s frame to `frames`, sharing the previous frame's
## mechanisms when they did not change (most ticks only move a pip).
static func record(frames: Array, simulation: RefCounted) -> void:
	var frame: Array = simulation._memory_frame()
	if not frames.is_empty() and frame[MECHANISMS] == frames[-1][MECHANISMS]: frame[MECHANISMS] = frames[-1][MECHANISMS]
	frames.append(frame)

## A memory played back from its trace. It has the fields a later turn reads
## of its memory; _tick moves one frame on, and after the last frame it stays,
## as a finished turn does. The later turn copies what it takes, so frames are
## never changed.
class Playback extends RefCounted:
	var role := "a"
	var tick := 0
	var _frames: Array = []
	var _slot := "p0"
	var _players: Dictionary = {}
	var _mechanisms: Dictionary = {}
	var _own_toggles: Dictionary = {}
	var _own_rang := false
	var _offer_tick := -1
	var _hold_ticks := 0
	var _hold_start := -1
	var _ready_branch := ""

	func _init(trace: Dictionary) -> void:
		role = str(trace.role)
		_slot = str(trace.slot)
		_frames = trace.frames
		_load(0)

	func _tick(_input: Dictionary = {}) -> void:
		if tick + 1 >= _frames.size(): return
		tick += 1
		_load(tick)

	func _load(index: int) -> void:
		var frame: Array = _frames[index]
		_players = {_slot: frame[PLAYER]}
		_mechanisms = frame[MECHANISMS]
		_own_toggles = frame[OWN_TOGGLES]
		_own_rang = frame[OWN_RANG]
		_offer_tick = frame[OFFER_TICK]
		_hold_ticks = frame[HOLD_TICKS]
		_hold_start = frame[HOLD_START]
		_ready_branch = frame[READY_BRANCH]

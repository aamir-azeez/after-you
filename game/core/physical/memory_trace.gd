extends RefCounted
## Open turns: each checked turn's result and the world it hands the next turn
## (runtime.gd handoff_world: the world at its tick M, where the next turn
## starts), kept by recording hash. Starting or checking turn k needs only
## turn k-1's hand-off world, so it costs one simulation, not k.
## two_pair_proof.gd fills it only from a turn that replayed exactly, and its
## turn_start reads it. A world is a few kilobytes, far less than a trace of
## every tick.
## Bounded and shared by every engine and thread. Static vars live here, in a
## script that extends an engine class (tests/test_subclass_statics.gd).
const MAX_WORLDS := 16
const MAX_CHECKS := 256
## Persisted turns: once a service attaches a store (services/
## memory_trace_store.gd: `persist` writes an id's bytes, `restore` reads them
## back), every kept turn is also kept there, and a miss reads it back, so a
## restart does not replay the stage's turns again. Core never touches files.
## Bump TRACE_VERSION whenever what a turn plays changes without new rules; a
## kept turn under another stamp (this, the app version or Godot's) is ignored.
const TRACE_VERSION := 2
const MAX_BYTES := 8388608
static var _worlds: Dictionary = {}
static var _checks: Dictionary = {}
static var _lock := Mutex.new()
## Turns simulated by a check since the last clear; for tests and timing.
static var simulated := 0
## Tests turn it off to compare with playing every turn from the checkpoint.
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

## The world kept turn `id` hands the next turn, a copy; {} when none (or the
## turn never reached its hand-off).
static func world(id: String) -> Dictionary:
	if not enabled: return {}
	_lock.lock()
	var found: Variant = _worlds.get(id)
	if found != null: _touch(_worlds, id)
	_lock.unlock()
	if found == null: found = _restore(id).get("world")
	return found.duplicate(true) if found is Dictionary else {}

## Keeps a valid check and its hand-off world, and persists them when a store is attached.
static func keep(id: String, result: Dictionary, handoff: Dictionary) -> void:
	if not enabled: return
	_remember(id, result, handoff)
	_lock.lock()
	simulated += 1
	var writer := persist
	_lock.unlock()
	if writer.is_valid():
		var bytes := encode(id, result, handoff)
		if bytes.size() <= MAX_BYTES: writer.call(id, bytes)

static func _remember(id: String, result: Dictionary, handoff: Dictionary) -> void:
	_lock.lock()
	_checks.erase(id)
	_checks[id] = result.duplicate(true)
	_worlds.erase(id)
	_worlds[id] = handoff.duplicate(true)
	while _checks.size() > MAX_CHECKS: _checks.erase(_checks.keys()[0])
	while _worlds.size() > MAX_WORLDS: _worlds.erase(_worlds.keys()[0])
	_lock.unlock()

## This build's stamp: a persisted turn under any other is not trusted.
static func stamp() -> String:
	return "%d|%s|%s" % [TRACE_VERSION, str(ProjectSettings.get_setting("application/config/version", "")), str(Engine.get_version_info().get("string", ""))]

static func _sha256(bytes: PackedByteArray) -> PackedByteArray:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish()

## One kept turn as verified bytes: its size, SHA-256 and deflated body.
static func encode(id: String, result: Dictionary, handoff: Dictionary) -> PackedByteArray:
	var body := var_to_bytes([stamp(), id, result, handoff])
	return var_to_bytes([body.size(), _sha256(body), body.compress(FileAccess.COMPRESSION_DEFLATE)])

## encode's bytes back: {"check", "world"}, or {} unless they verify whole as
## `id` under this build's stamp.
static func decode(id: String, bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_BYTES: return {}
	var outer: Variant = bytes_to_var(bytes)
	if not outer is Array or outer.size() != 3 or not outer[0] is int or outer[0] < 1 or outer[0] > MAX_BYTES * 16 or not outer[1] is PackedByteArray or not outer[2] is PackedByteArray: return {}
	var body: PackedByteArray = outer[2].decompress(outer[0], FileAccess.COMPRESSION_DEFLATE)
	if body.size() != outer[0] or _sha256(body) != outer[1]: return {}
	var value: Variant = bytes_to_var(body)
	if not value is Array or value.size() != 4 or value[0] != stamp() or value[1] != id or not value[2] is Dictionary or not value[3] is Dictionary: return {}
	return {"check": value[2], "world": value[3]}

## A kept turn read back from the attached store into memory, or {}.
static func _restore(id: String) -> Dictionary:
	_lock.lock()
	var reader := restore
	_lock.unlock()
	if not reader.is_valid(): return {}
	var bytes: Variant = reader.call(id)
	var kept := decode(id, bytes) if bytes is PackedByteArray else {}
	if not kept.is_empty(): _remember(id, kept.check, kept.world)
	return kept

static func clear() -> void:
	_lock.lock()
	_worlds.clear()
	_checks.clear()
	simulated = 0
	_lock.unlock()

static func _touch(entries: Dictionary, id: String) -> void:
	var value: Variant = entries[id]
	entries.erase(id)
	entries[id] = value

extends RefCounted
## Carries a solo sleeping-lighthouse@1 journey into sleeping-lighthouse@2 the
## first time @2 opens. Each saved @1 turn is played again, input for input,
## by the @2 engine (the same Lighthouse physics at its current rules) and the
## result is checked stage by stage. The @1 save is never changed.
## - Every turn converts: @2 starts with those turns saved.
## - Any turn does not: an unfinished @1 journey stays in the @1 screen
##   ("Continue"); a finished one leaves @2 to start fresh. The outcome is
##   kept against the exact @1 save, so it is not tried again until that
##   save changes.
## convert_v1() is worker-safe (no node, keepsake or file write); adopt() and
## remember() run on the main thread.
const Registry = preload("res://services/chapter_registry.gd")
const V1Journey = preload("res://services/lighthouse_journey.gd")
const Native = preload("res://core/lighthouse/borrowed_light.gd")
const RoomSimulation = preload("res://core/lighthouse/room_simulation.gd")
const Typed = preload("res://services/typed_values.gd")
const KEY := Registry.LIGHTHOUSE_V2
const V1_PATH := V1Journey.PATH
const MARKER_PATH := "user://sleeping-lighthouse-v1-migration.json"
const MARKER_SCHEMA := 1
const V1_SCENE := "res://lighthouse_preview.tscn"

## "v2": open @2 as it is; "migrate": open @2 and convert @1 first; "v1":
## keep playing @1 (an unfinished journey that did not convert).
static func plan(v1_path: String = V1_PATH, v2_path: String = "", marker_path: String = MARKER_PATH) -> String:
	if v2_path.is_empty(): v2_path = str(Registry.descriptor(KEY).local_path)
	if _any(v2_path) or not _any(v1_path): return "v2"
	match _marker(marker_path, v1_path):
		"fallback": return "v1"
		"fresh": return "v2"
	return "migrate"

## Converts the @1 journey: {status: "converted", pairs, a, checkpoint,
## complete} or {status: "fallback", complete} or {status: "empty"}.
static func convert_v1(v1_path: String = V1_PATH) -> Dictionary:
	var v1 := V1Journey.new(v1_path)
	v1.load_data()
	if v1.read_only: return {"status": "empty"}
	var pairs: Array = v1.pairs()
	var first: Dictionary = v1.prior_recording()
	var complete: bool = v1.chapter_complete()
	if pairs.is_empty() and first.is_empty(): return {"status": "empty"}
	var level := Registry.definition(KEY)
	var checkpoint := Registry.initial_checkpoint(KEY)
	var engine: RefCounted = RoomSimulation._proof()
	var converted: Array = []
	for pair: Dictionary in pairs:
		var a := _turn(level, checkpoint, pair.a, {})
		var b := _turn(level, checkpoint, pair.b, a) if not a.is_empty() else {}
		if b.is_empty(): return {"status": "fallback", "complete": complete}
		var check: Dictionary = engine._verify_pair(level, checkpoint, a, b)
		if not check.get("valid", false): return {"status": "fallback", "complete": complete}
		checkpoint = engine._build_checkpoint(level, checkpoint, a, b, check.snapshot)
		converted.append({"a": a, "b": b})
	var waiting := {}
	if not first.is_empty():
		waiting = _turn(level, checkpoint, first, {})
		var checked: Dictionary = engine._verify_raw(level, waiting, checkpoint, {}) if not waiting.is_empty() else {}
		if not checked.get("valid", false) or not checked.get("snapshot", {}).get("can_commit", false): return {"status": "fallback", "complete": complete}
	return {"status": "converted", "pairs": converted, "a": waiting, "checkpoint": checkpoint, "complete": complete}

## One @1 turn played by the @2 engine from a room checkpoint; {} if it does
## not reproduce a whole turn of the same role and length.
static func _turn(level: Dictionary, checkpoint: Dictionary, native: Dictionary, prior: Dictionary) -> Dictionary:
	var role := str(native.get("role", ""))
	var sim := RoomSimulation.new()
	sim._reset_trusted(level, str(native.get("stage_id", "")), checkpoint, prior, role)
	if not str(sim.error).is_empty(): return {}
	var inputs: Array = Native.expand_recording_inputs(native)
	if inputs.is_empty(): return {}
	for input: Dictionary in inputs: sim.step(input)
	var record: Dictionary = sim.export_recording()
	if record.get("role") != role or int(record.get("duration_ticks", -1)) != inputs.size(): return {}
	return record

## Writes a converted journey into an empty @2 journal (loaded, no turns).
## Every structural and version rule of the journal still runs.
static func adopt(journey: RefCounted, converted: Dictionary) -> bool:
	return carry(journey, converted) == "adopted"

## adopt() that says why not: "adopted"; "refused" (the journal takes no
## converted journey); "unsaved" (it would, but its write failed, so the
## carry-over is to be tried again, never remembered as not converting).
static func carry(journey: RefCounted, converted: Dictionary) -> String:
	if converted.get("status") != "converted" or journey == null or journey.read_only or not journey.pairs().is_empty() or not journey.prior_recording().is_empty(): return "refused"
	var state: Dictionary = journey._empty_state()
	state.pairs = converted.pairs.duplicate(true)
	state.a = converted.a.duplicate(true)
	var verdict: Dictionary = journey._validate_state(state, {"pairs": state.pairs.size(), "checkpoint": converted.checkpoint, "a_verified": true})
	if not verdict.get("valid", false): return "refused"
	return "adopted" if journey._write_verified_state(state, verdict.checkpoint) else "unsaved"

## Keeps a conversion that did not happen against this exact @1 save:
## "fallback" (keep playing @1) or "fresh" (start @2 anew).
static func remember(result: String, v1_path: String = V1_PATH, marker_path: String = MARKER_PATH) -> bool:
	var text := JSON.stringify({"schema_version": MARKER_SCHEMA, "source": _digest(v1_path), "result": result})
	var file := FileAccess.open(marker_path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(text)
	file.close()
	return true

static func _marker(marker_path: String, v1_path: String) -> String:
	if not FileAccess.file_exists(marker_path): return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(marker_path))
	if not parsed is Dictionary or not Typed.equal(parsed.get("schema_version"), MARKER_SCHEMA) or not Typed.equal(parsed.get("source"), _digest(v1_path)): return ""
	return str(parsed.get("result", ""))

## The @1 save as it is now: every generation file's bytes.
static func _digest(v1_path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for suffix: String in ["", ".tmp", ".backup"]:
		context.update(("|" + suffix).to_utf8_buffer())
		var bytes := FileAccess.get_file_as_bytes(v1_path + suffix) if FileAccess.file_exists(v1_path + suffix) else PackedByteArray()
		if not bytes.is_empty(): context.update(bytes)
	return context.finish().hex_encode()

static func _any(path: String) -> bool:
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): return true
	return false

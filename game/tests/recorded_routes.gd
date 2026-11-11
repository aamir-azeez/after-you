extends RefCounted
## Witness routes from real recordings (tests/chapter_witness.gd): a recording's
## run-length actions become ["input", ticks, x, z, action] steps, which replay
## the exact inputs, so the routes reproduce the recording byte for byte on the
## definition it was made on, and replay the same play on a changed one.
##
## A source is any file holding a chapter's recorded pairs: a recording pair
## {"a", "b"}, anything with "pairs" (a solo journey save), a checkpoint whose
## proof chain holds every stage's pair (a run's final checkpoint, as replays
## and the developers' ghosts keep it), or any of these in the shared blob
## format (services/blob_codec.gd: an encoding byte, then the canonical bytes
## raw or deflated).
const BlobCodec = preload("res://services/blob_codec.gd")
const Registry = preload("res://services/chapter_registry.gd")
## The largest source read, as a stored room attempt (history_store.gd).
const MAX_SOURCE_BYTES := 4 * 1024 * 1024

## The steps that replay `recording`'s inputs exactly.
static func from_recording(recording: Dictionary) -> Array:
	var steps: Array = []
	for run: Dictionary in recording.get("actions", []):
		steps.append(["input", int(run.ticks), int(run.x), int(run.z), bool(run.action)])
	return steps

## A stage's route entry from its recorded pair: both turns' inputs, the rules
## when they are not the chapter's preferred ones, and the turns played with
## Forgiving catches off.
static func stage_route(chapter_key: String, pair: Dictionary) -> Dictionary:
	var route := {"a": from_recording(pair.a), "b": from_recording(pair.b)}
	var rules := int(pair.a.get("simulation_version", 0))
	if rules != Registry.preferred_rules(chapter_key): route["rules"] = rules
	var unassisted: Array = []
	for role: String in ["a", "b"]:
		if not bool(pair[role].get("catch_assistance", true)): unassisted.append(role)
	if not unassisted.is_empty(): route["no_catch_assistance"] = unassisted
	return route

## The parsed source at `path` (JSON text, or a blob), or null with `problem` set.
static func read_source(path: String, problem: Array) -> Variant:
	if not FileAccess.file_exists(path):
		problem.append("no file at " + path)
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty() or bytes.size() > MAX_SOURCE_BYTES + 1:
		problem.append("%s is empty or larger than %d bytes" % [path, MAX_SOURCE_BYTES])
		return null
	if bytes[0] == BlobCodec.ENCODING_DEFLATE: bytes = bytes.slice(1).decompress_dynamic(MAX_SOURCE_BYTES, FileAccess.COMPRESSION_DEFLATE)
	elif bytes[0] == BlobCodec.ENCODING_RAW: bytes = bytes.slice(1)
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8()) if not bytes.is_empty() else null
	if not parsed is Dictionary and not parsed is Array:
		problem.append("%s is neither JSON nor a blob of JSON" % path)
		return null
	return parsed

## Every distinct recorded pair of `level_id` anywhere in `value`, by stage id:
## {stage id: [pair, ...]}.
static func pairs_by_stage(value: Variant, level_id: String) -> Dictionary:
	var found: Dictionary = {}
	var seen: Dictionary = {}
	_collect(value, level_id, found, seen, 0)
	return found

static func _collect(value: Variant, level_id: String, found: Dictionary, seen: Dictionary, depth: int) -> void:
	if depth > 64: return
	if value is Array:
		for item: Variant in value: _collect(item, level_id, found, seen, depth + 1)
		return
	if not value is Dictionary: return
	if _is_pair(value) and str(value.a.get("level_id")) == level_id:
		var mark := str(value.a.get("recording_hash")) + str(value.b.get("recording_hash"))
		if not seen.has(mark):
			seen[mark] = true
			var stage_id := str(value.a.get("stage_id"))
			if not found.has(stage_id): found[stage_id] = []
			found[stage_id].append({"a": value.a, "b": value.b})
	for item: Variant in value.values(): _collect(item, level_id, found, seen, depth + 1)

static func _is_pair(value: Dictionary) -> bool:
	var a: Variant = value.get("a")
	var b: Variant = value.get("b")
	return a is Dictionary and b is Dictionary and a.get("role") == "a" and b.get("role") == "b" and a.get("actions") is Array and b.get("actions") is Array \
		and a.get("stage_id") == b.get("stage_id") and str(b.get("source_recording_hash")) == str(a.get("recording_hash"))

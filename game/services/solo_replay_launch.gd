extends RefCounted
## The one hand-off from a solo Watch replay tap to the chapter scene it opens.
## Main writes the replay context file and says this open is a replay; the
## chapter scene claims that request once and reads the file only then. Any
## file left by an open that never finished is removed, so it can never block
## another chapter or room.
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const PATH := "user://solo-replay-playback.json"
const MAX_BYTES := 2097152
static var _requested := false

## Writes the context for the scene about to open and marks the open as a replay.
static func write(context: Dictionary) -> bool:
	_requested = false
	var bytes := JSON.stringify(context).to_utf8_buffer()
	if bytes.is_empty() or bytes.size() > MAX_BYTES: return false
	if not AtomicFile.write_bytes(PATH, bytes): return false
	_requested = true
	return true

## True once for the scene the replay open is for. An online screen never
## plays a solo replay; any other screen removes a leftover file instead.
static func claim(online: bool) -> bool:
	var requested := _requested and not online
	_requested = false
	if not requested: discard()
	return requested

## Reads the hand-off once and removes it whatever the outcome. `rules` comes
## from the chapter scene: {"chapter_key", "stage_ids" (each stage's id in
## order), "pairs_valid" (the chapter's own replay check of the accepted pairs)}.
## The shape every chapter shares is checked here. Returns {"status": "none"},
## {"status": "error"} or {"status": "consumed", "context": ...}.
static func consume(rules: Dictionary, path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path): return {"status": "none"}
	var result := _read(path, rules)
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK and result.get("status") == "consumed": return {"status": "error"}
	return result

static func _read(path: String, rules: Dictionary) -> Dictionary:
	var failed := {"status": "error"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return failed
	if file.get_length() < 1 or file.get_length() > MAX_BYTES:
		file.close()
		return failed
	var raw := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(raw) != OK or not parser.data is Dictionary: return failed
	var context: Dictionary = parser.data
	if not Typed.equal(context.get("schema_version"), 1) or not Typed.equal(context.get("chapter_key"), rules.get("chapter_key")): return failed
	var stage_index: Variant = context.get("selected_stage_index")
	var pairs: Variant = context.get("accepted_pairs")
	var visibility_key: Variant = context.get("visibility_key")
	var stage_ids: Array = rules.get("stage_ids", [])
	if not (stage_index is int or stage_index is float) or not is_finite(float(stage_index)) or float(stage_index) != floor(float(stage_index)): return failed
	# Optional: the part playback starts from ("Watch all parts"), at most the selected one.
	var start: Variant = context.get("start_stage_index", stage_index)
	if not (start is int or start is float) or not is_finite(float(start)) or float(start) != floor(float(start)) or float(start) < 0.0 or float(start) > float(stage_index): return failed
	if not visibility_key is String or str(visibility_key).is_empty() or str(visibility_key).length() > 512: return failed
	if not pairs is Array or pairs.size() != int(stage_index) + 1 or pairs.size() > stage_ids.size() or pairs.is_empty(): return failed
	for index in range(pairs.size()):
		var pair: Variant = pairs[index]
		if not pair is Dictionary or pair.size() != 2 or not pair.get("a") is Dictionary or not pair.get("b") is Dictionary: return failed
		var expected := str(stage_ids[index])
		if expected.is_empty() or not Typed.equal(pair.a.get("role"), "a") or not Typed.equal(pair.b.get("role"), "b") or not Typed.equal(pair.a.get("stage_id"), expected) or not Typed.equal(pair.b.get("stage_id"), expected): return failed
	var pairs_valid: Callable = rules.get("pairs_valid", Callable())
	if not pairs_valid.is_valid() or not pairs_valid.call(pairs): return failed
	return {"status": "consumed", "context": context.duplicate(true)}

## Removes the context and its request, whatever state the open ended in.
static func discard() -> void:
	_requested = false
	AtomicFile.remove(PATH)

extends RefCounted
## Display-only copy of the last finished Solo scan, so the list can be drawn
## at once on the next open. It never holds recordings and is never playable:
## its rows only stand in, unchecked, until the scan settles their chapter.
## Stored in its own bounded file; gameplay journals are never touched.
const Registry = preload("res://services/chapter_registry.gd")
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const SCHEMA := 1
const DEFAULT_PATH := "user://solo-replay-index.json"
const MAX_BYTES := 524288
const MAX_ROWS := 1024
const LIGHTHOUSE := "sleeping-lighthouse@1"
const FIELDS := ["id", "content_id", "attempt_id", "chapter_key", "chapter_title", "stage_index", "stage_id", "title", "source_family", "archived"]

var path := DEFAULT_PATH
var _rows: Array[Dictionary] = []
var _signature := ""

func _init(storage_path: String = DEFAULT_PATH) -> void:
	path = storage_path
	_load()

## Rows shaped like scan rows minus "pair"; each also carries "checking".
func rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in _rows:
		var copy := row.duplicate(true)
		copy["visibility_key"] = copy.id
		copy["source_id"] = copy.attempt_id
		copy["checking"] = true
		result.append(copy)
	return result

## Records the display fields of a finished scan; rewrites only on change.
func store(scanned: Array) -> bool:
	var next: Array[Dictionary] = []
	for row: Variant in scanned:
		if not row is Dictionary: continue
		var compact := {}
		for field: String in FIELDS: compact[field] = row.get(field)
		if not _valid(compact): continue
		next.append(compact)
		if next.size() >= MAX_ROWS: break
	var text := JSON.stringify({"schema_version": SCHEMA, "rows": next})
	if text == _signature: return true
	if text.to_utf8_buffer().size() > MAX_BYTES or not _write(text): return false
	_rows = next
	_signature = text
	return true

## Records the list as drawn mid-scan: the checked rows of settled chapters,
## and this snapshot's own rows for chapters still being checked.
func store_display(settled: Array, pending: Dictionary) -> bool:
	var rows: Array = settled.duplicate()
	for row: Dictionary in _rows:
		if pending.has(str(row.chapter_key)): rows.append(row)
	return store(rows)

static func _valid(row: Dictionary) -> bool:
	if row.size() != FIELDS.size(): return false
	for field: String in ["id", "content_id", "attempt_id", "chapter_key", "chapter_title", "stage_id", "title", "source_family"]:
		if not row.get(field) is String or row[field].length() > 512: return false
	if not _digest(row.content_id) or not _digest(row.attempt_id) or not row.get("archived") is bool: return false
	var index: Variant = row.get("stage_index")
	if not (index is int or index is float) or float(index) != floor(float(index)) or index < 0 or index > 63: return false
	if row.chapter_key != LIGHTHOUSE and not Registry.keys().has(row.chapter_key): return false
	if row.source_family not in ["current", "archive"] or row.archived != (row.source_family == "archive"): return false
	# The identity a scan would give this exact part; anything else is ignored.
	return row.id == "%s:%s:%s:%d:%s" % [row.source_family, row.chapter_key, row.attempt_id, int(index), row.content_id]

static func _digest(value: Variant) -> bool:
	return value is String and value.length() == 64 and value.is_valid_hex_number(false)

func _load() -> void:
	_rows.clear()
	_signature = ""
	if not FileAccess.file_exists(path): return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return
	if file.get_length() < 1 or file.get_length() > MAX_BYTES:
		file.close()
		return
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	# Missing, damaged or older snapshots are ignored as a whole.
	if not parsed is Dictionary or parsed.size() != 2 or not Typed.equal(parsed.get("schema_version"), SCHEMA) or not parsed.get("rows") is Array or parsed.rows.size() > MAX_ROWS: return
	var loaded: Array[Dictionary] = []
	for row: Variant in parsed.rows:
		# One row that no longer applies (a chapter this build does not list)
		# drops alone; the rest of the snapshot still draws.
		if not row is Dictionary or not _valid(row): continue
		var copy: Dictionary = row.duplicate(true)
		copy.stage_index = int(copy.stage_index)
		loaded.append(copy)
	_rows = loaded
	_signature = text

func _write(text: String) -> bool:
	return AtomicFile.write_text(path, text, true)

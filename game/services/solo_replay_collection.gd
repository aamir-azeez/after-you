extends RefCounted
## Read-only discovery of locally accepted solo replay pairs.
## Disk bytes are captured on the main thread and replay-checked from that
## immutable snapshot on one worker at a time. This service never loads a
## journey through its recovery-writing load_data() path.
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const RelayJourney = preload("res://services/relay_journey.gd")
const LighthouseJourney = preload("res://services/lighthouse_journey.gd")
const LighthouseStages = preload("res://core/lighthouse/stage_catalog.gd")
const MAX_SAVE_BYTES := 2097152
const MAX_ARCHIVED_ATTEMPTS := 32
## Main-thread budget per advance for sources that need no worker: missing
## files and bytes that already passed a check.
const QUICK_BUDGET_USEC := 4000
const VERIFIED_LIMIT := 512
## Successful checks keyed by a digest of the exact captured bytes, kept for the
## process so unchanged sources are not replayed again after a scene change.
static var _verified: Dictionary = {}
## The same digests persist across launches in their own bounded file (never a
## journal). A trusted digest skips only the native replay; its bytes are still
## read, parsed and turned into rows on the worker.
const VERIFIED_PATH := "user://solo-replay-verified.json"
const VERIFIED_SCHEMA := 1
## Bump when the meaning of an accepted solo pair changes.
const VERIFIER_VERSION := 1
const VERIFIED_MAX_BYTES := 131072

var _paths: Dictionary = {}
var _jobs: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
var _worker: Thread
var _worker_job: Dictionary = {}
var _worker_validator: RefCounted
## A cancelled verifier still finishing its private snapshot. No new worker
## starts until it is joined, so at most one check runs at a time.
var _retired: Thread
var _retired_job: Dictionary = {}
var _scanning := false
var _verified_path := VERIFIED_PATH
var _trusted: Dictionary = {}
var _trusted_dirty := false
var _total := 0
var _done := 0
var last_error := ""

func _init(source_paths: Dictionary = {}, verified_path: String = VERIFIED_PATH) -> void:
	_verified_path = verified_path
	_load_trusted()
	for chapter: String in Registry.keys():
		var fallback := str(Registry.descriptor(chapter).get("local_path", ""))
		var candidate: Variant = source_paths.get(chapter, fallback)
		if candidate is String and not candidate.is_empty(): _paths[chapter] = candidate
	_paths["sleeping-lighthouse@1"] = str(source_paths.get("sleeping-lighthouse@1", "user://lighthouse-journey-v3.json"))

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE: return
	for thread: Thread in [_worker, _retired]:
		if thread != null and thread.is_started(): thread.wait_to_finish()

func begin_scan() -> bool:
	_retire_worker()
	_jobs.clear()
	_rows.clear()
	last_error = ""
	for chapter: String in Registry.keys():
		_enqueue_chapter(chapter, "relay")
		_enqueue_archives(chapter, "relay")
	var lighthouse := "sleeping-lighthouse@1"
	_enqueue_chapter(lighthouse, "lighthouse")
	_enqueue_archives(lighthouse, "lighthouse")
	_total = _jobs.size()
	_done = 0
	_scanning = not _jobs.is_empty()
	if not _scanning: _save_trusted()
	return true

func scan_pending() -> bool:
	return _scanning or _worker != null or not _jobs.is_empty()

## Counts finished sources out of those queued when the scan began. "settled"
## counts rows whose chapter has no source left to check.
func scan_progress() -> Dictionary:
	var pending := pending_chapters()
	var settled := 0
	for row: Dictionary in _rows:
		if not pending.has(str(row.chapter_key)): settled += 1
	return {"active": scan_pending(), "sources_done": _done, "sources_total": _total, "settled": settled, "pending": pending.size()}

func cancel_scan() -> void:
	# Never waits on the verifier. Its private snapshot finishes on its own and
	# is joined by a later advance, a new scan, or teardown. No file or gameplay
	# state is written by the worker.
	_retire_worker()
	_jobs.clear()
	_scanning = false
	_save_trusted()

func advance_scan() -> bool:
	if not _scanning: return false
	if not _reap_retired(): return true
	if _worker != null:
		if _worker.is_alive(): return true
		var result: Variant = _worker.wait_to_finish()
		var completed := _worker_job
		_worker = null
		_worker_job = {}
		_worker_validator = null
		_done += 1
		_remember(completed, result)
		_adopt(completed, result)
	var started := Time.get_ticks_usec()
	while not _jobs.is_empty():
		var job: Dictionary = _jobs.pop_front()
		var snapshot := _capture(job)
		if snapshot.is_empty():
			_done += 1
		elif _verified.has(snapshot.key):
			var known: Dictionary = _verified[snapshot.key]
			_verified.erase(snapshot.key)
			_verified[snapshot.key] = known
			_trust(snapshot.key)
			_done += 1
			_adopt(job, known)
		elif not _read_snapshot(snapshot):
			_done += 1
		elif _start_worker(job, snapshot):
			return true
		if Time.get_ticks_usec() - started >= QUICK_BUDGET_USEC: return true
	_scanning = false
	_save_trusted()
	return false

func items() -> Array[Dictionary]:
	return _rows.duplicate(true)

## Rows of chapters whose every source has been checked. Attempt numbering is
## per chapter, so these rows keep their final labels while the scan goes on.
func settled_items() -> Array[Dictionary]:
	var pending := pending_chapters()
	var rows: Array[Dictionary] = []
	for row: Dictionary in _rows:
		if not pending.has(str(row.chapter_key)): rows.append(row.duplicate(true))
	return rows

## Chapters with a source still queued or being checked.
func pending_chapters() -> Dictionary:
	var pending := {}
	for job: Dictionary in _jobs: pending[str(job.chapter)] = true
	if not _worker_job.is_empty(): pending[str(_worker_job.chapter)] = true
	return pending

func _validator(job: Dictionary) -> RefCounted:
	return LighthouseJourney.new(str(job.path)) if job.kind == "lighthouse" else RelayJourney.new(str(job.path), null, str(job.chapter))

func _start_worker(job: Dictionary, snapshot: Dictionary) -> bool:
	var validator: RefCounted = _validator(job)
	_worker_job = job.duplicate(true)
	_worker_job.key = snapshot.key
	_worker_validator = validator
	_worker = Thread.new()
	# Bind the defining script's static function, never this service.
	var script: Script = get_script()
	while script.get_base_script() != null: script = script.get_base_script()
	if _worker.start(Callable(script, "_verify_snapshot").bind(snapshot, validator, _trusted.has(snapshot.key))) == OK: return true
	_worker = null
	_worker_job = {}
	_worker_validator = null
	_done += 1
	last_error = "Saved replays could not be checked."
	return false

func _retire_worker() -> void:
	if _worker == null: return
	if _worker.is_alive() and _retired == null:
		_retired = _worker
		_retired_job = _worker_job
	else:
		_remember(_worker_job, _worker.wait_to_finish())
	_worker = null
	_worker_job = {}
	_worker_validator = null

func _reap_retired() -> bool:
	if _retired == null: return true
	if _retired.is_alive(): return false
	_remember(_retired_job, _retired.wait_to_finish())
	_retired = null
	_retired_job = {}
	return true

func _adopt(_job: Dictionary, result: Variant) -> void:
	# Rows arrive built by the worker; they are shared, never mutated, and
	# copied only when read through items() or settled_items().
	if result is Dictionary and result.get("ok", false):
		for row: Variant in result.get("rows", []):
			if row is Dictionary: _rows.append(row)
	elif result is Dictionary and result.get("hold", false):
		last_error = "Some saved replays could not be checked."

func _remember(job: Dictionary, result: Variant) -> void:
	# Only a successful check is kept, with the rows it produced. A trusted
	# digest whose bytes no longer pass loses its trust.
	if job.is_empty() or str(job.get("key", "")).is_empty() or not result is Dictionary: return
	if not result.get("ok", false):
		if _trusted.erase(job.key): _trusted_dirty = true
		return
	_trust(job.key)
	_verified.erase(job.key)
	_verified[job.key] = {"ok": true, "rows": result.get("rows", [])}
	while _verified.size() > VERIFIED_LIMIT:
		_verified.erase(_verified.keys()[0])

func _trust(key: String) -> void:
	if _trusted.has(key) and _trusted.keys()[-1] == key: return
	_trusted.erase(key)
	_trusted[key] = true
	while _trusted.size() > VERIFIED_LIMIT: _trusted.erase(_trusted.keys()[0])
	_trusted_dirty = true

static func _verifier_stamp() -> String:
	# Engine and rule versions: a different native verifier never inherits trust.
	var parts := PackedStringArray([str(VERIFIER_VERSION), str(Engine.get_version_info().get("string", "")), "lighthouse:3"])
	for chapter: String in Registry.keys(): parts.append(chapter + ":" + str(Registry.supported_rules(chapter)))
	return "|".join(parts)

func _load_trusted() -> void:
	_trusted.clear()
	if _verified_path.is_empty() or not FileAccess.file_exists(_verified_path): return
	var text := _read_bounded(_verified_path, VERIFIED_MAX_BYTES)
	var json := JSON.new()
	var parsed: Variant = json.data if not text.is_empty() and json.parse(text) == OK else null
	# Anything unexpected is ignored; the next finished scan rewrites the file.
	if not parsed is Dictionary or parsed.size() != 3 or parsed.get("schema_version") != VERIFIED_SCHEMA or parsed.get("stamp") != _verifier_stamp() or not parsed.get("keys") is Array or parsed.keys.size() > VERIFIED_LIMIT: return
	for key: Variant in parsed.keys:
		if not key is String or key.length() != 64 or not key.is_valid_hex_number(false):
			_trusted.clear()
			return
		_trusted[key] = true

func _save_trusted() -> void:
	if not _trusted_dirty or _verified_path.is_empty(): return
	_trusted_dirty = false
	var text := JSON.stringify({"schema_version": VERIFIED_SCHEMA, "stamp": _verifier_stamp(), "keys": _trusted.keys()})
	if text.to_utf8_buffer().size() > VERIFIED_MAX_BYTES: return
	var temporary := _verified_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return
	file.store_string(text)
	file.flush()
	var okay := file.get_error() == OK
	file.close()
	if not okay or FileAccess.get_file_as_string(temporary) != text: return
	var target := ProjectSettings.globalize_path(_verified_path)
	var backup := target + ".backup"
	if FileAccess.file_exists(_verified_path):
		if FileAccess.file_exists(_verified_path + ".backup"): DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(target, backup) != OK: return
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), target) != OK and FileAccess.file_exists(_verified_path + ".backup"):
		DirAccess.rename_absolute(backup, target)

func _enqueue_chapter(chapter: String, kind: String) -> void:
	var path := str(_paths.get(chapter, ""))
	if path.is_empty(): return
	if not (FileAccess.file_exists(path) or FileAccess.file_exists(path + ".tmp") or FileAccess.file_exists(path + ".backup")): return
	_jobs.append({"source_kind": "current", "kind": kind, "chapter": chapter, "path": path, "source_id": "current"})

func _enqueue_archives(chapter: String, kind: String) -> void:
	var path := str(_paths.get(chapter, ""))
	if path.is_empty(): return
	var directory := DirAccess.open(path.get_base_dir())
	if directory == null: return
	var prefix := path.get_file() + ".attempt-"
	var ids: Array[String] = []
	for filename: String in directory.get_files():
		if not filename.begins_with(prefix) or not filename.ends_with(".json"): continue
		var id := filename.trim_prefix(prefix).trim_suffix(".json")
		if id.length() == 64 and id.is_valid_hex_number(false): ids.append(id)
	ids.sort()
	for id: String in ids.slice(0, MAX_ARCHIVED_ATTEMPTS):
		_jobs.append({"source_kind": "archive", "kind": kind, "chapter": chapter, "path": path, "source_id": id})

static func _capture(job: Dictionary) -> Dictionary:
	# Names the exact bytes of every candidate file. Text is read only when
	# those bytes have not already passed a check.
	var files: Array[Dictionary] = []
	if job.source_kind == "archive":
		files.append({"suffix": "", "path": str(job.path) + ".attempt-" + str(job.source_id) + ".json"})
	else:
		for suffix: String in ["", ".tmp", ".backup"]:
			var candidate := str(job.path) + suffix
			if FileAccess.file_exists(candidate): files.append({"suffix": suffix, "path": candidate})
	if files.is_empty(): return {}
	var identity := PackedStringArray([str(job.kind), str(job.chapter), str(job.source_kind), str(job.source_id), str(job.path)])
	for file: Dictionary in files:
		var digest := FileAccess.get_sha256(file.path) if _bounded_length(file.path) > 0 else ""
		if digest.is_empty(): return {}
		identity.append(str(file.suffix) + ":" + digest)
	var snapshot := job.duplicate(true)
	snapshot.files = files
	snapshot.key = "|".join(identity).sha256_text()
	return snapshot

static func _read_snapshot(snapshot: Dictionary) -> bool:
	snapshot.raw = []
	for file: Dictionary in snapshot.files:
		var text := _read_bounded(file.path, MAX_SAVE_BYTES)
		if text.is_empty(): return false
		snapshot.raw.append(text if snapshot.source_kind == "archive" else {"suffix": file.suffix, "text": text})
	return true

static func _bounded_length(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return -1
	var length := file.get_length()
	file.close()
	return length if length >= 1 and length <= MAX_SAVE_BYTES else -1

static func _read_bounded(path: String, maximum: int) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return ""
	if file.get_length() < 1 or file.get_length() > maximum:
		file.close()
		return ""
	var text := file.get_as_text()
	file.close()
	return text

static func _verify_snapshot(snapshot: Dictionary, validator: RefCounted, trusted: bool = false) -> Dictionary:
	# This worker sees only captured bytes plus a private native validator.
	# It does not open files, call load_data(), touch gameplay state, or repair.
	# Trusted bytes passed this exact native check before, so only the replay
	# simulation is skipped; parsing, envelope and identity checks still run.
	var selected: Dictionary = {}
	var selected_generation := -1
	var field := "lighthouse" if snapshot.kind == "lighthouse" else "relay"
	for candidate: Variant in snapshot.raw:
		var raw: String = candidate if candidate is String else str(candidate.get("text", ""))
		var json := JSON.new()
		if json.parse(raw) != OK:
			if snapshot.source_kind == "archive": return {"ok": false}
			continue
		var value: Variant = json.data
		if not value is Dictionary: return {"ok": false, "hold": true}
		if snapshot.source_kind == "archive":
			if value.size() != 2 or value.get("archive_version") != 1 or not value.get(field) is Dictionary or Canonical.digest(value[field]) != snapshot.source_id: return {"ok": false, "hold": true}
			var archived: Dictionary = value[field]
			var checked_archive: Dictionary = {"valid": true} if trusted else validator._validate_state(archived)
			if not checked_archive.get("valid", false): return {"ok": false, "hold": true}
			return {"ok": true, "rows": _rows_for(snapshot, archived.get("pairs", []))}
		if not validator._envelope_valid(value) or not value.get(field) is Dictionary: return {"ok": false, "hold": true}
		var state: Dictionary = value[field]
		var checked_current: Dictionary = {"valid": true} if trusted else validator._validate_state(state)
		if not checked_current.get("valid", false): return {"ok": false, "hold": true}
		var generation := int(value.get("generation", 0))
		if generation > selected_generation:
			selected_generation = generation
			selected = state.duplicate(true)
	return {"ok": true, "rows": _rows_for(snapshot, selected.get("pairs", []))} if not selected.is_empty() else {"ok": false}

## Pure: also runs on the verifier, so adopting a result costs the main thread
## only an append.
static func _rows_for(job: Dictionary, pairs: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not pairs is Array or pairs.is_empty(): return rows
	# A current journal is reused for the next attempt. Anchor its attempt
	# identity to the first accepted contribution, while each part also carries
	# its own verified content digest. Adding a later pair does not rename the
	# earlier parts; restarting with different actions produces a new identity.
	var first_pair: Variant = pairs[0]
	var attempt_id := Canonical.digest({"chapter":str(job.chapter),"source_family":str(job.source_kind),"first_pair":first_pair})
	var definition := Registry.definition(str(job.chapter))
	var stages: Array = definition.get("stages", [])
	var chapter_title := str(Registry.descriptor(str(job.chapter)).get("title", ""))
	if job.kind == "lighthouse":
		chapter_title = "Sleeping Lighthouse"
		stages = []
		for stage_id: String in LighthouseStages.STAGE_IDS:
			stages.append(LighthouseStages.definition(stage_id))
	for index in range(mini(pairs.size(), stages.size())):
		var pair: Variant = pairs[index]
		if not pair is Dictionary or not pair.get("a") is Dictionary or not pair.get("b") is Dictionary: continue
		var stage_id := str(stages[index].get("stage_id", stages[index].get("id", ""))) if stages[index] is Dictionary else str(stages[index])
		var presentation := Registry.stage_presentation(str(job.chapter), stages[index]) if stages[index] is Dictionary and job.kind != "lighthouse" else {}
		var stage_title := str(presentation.get("title", stages[index].get("title", stage_id))) if stages[index] is Dictionary else stage_id
		var content_id := Canonical.digest(pair)
		var item_id := str(job.source_kind) + ":" + str(job.chapter) + ":" + attempt_id + ":" + str(index) + ":" + content_id
		rows.append({"id": item_id, "visibility_key": item_id, "chapter_key": str(job.chapter), "chapter_title": chapter_title,
			"stage_id": stage_id, "stage_index": index, "title": stage_title, "source_id": attempt_id, "attempt_id": attempt_id,
			"source_family": str(job.source_kind), "content_id": content_id,
			"archived": job.source_kind == "archive", "pair": pair.duplicate(true)})
	return rows

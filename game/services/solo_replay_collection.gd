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

var _paths: Dictionary = {}
var _jobs: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
var _worker: Thread
var _worker_job: Dictionary = {}
var _worker_validator: RefCounted
var _scanning := false
var last_error := ""

func _init(source_paths: Dictionary = {}) -> void:
	for chapter: String in Registry.keys():
		var fallback := str(Registry.descriptor(chapter).get("local_path", ""))
		var candidate: Variant = source_paths.get(chapter, fallback)
		if candidate is String and not candidate.is_empty(): _paths[chapter] = candidate
	_paths["sleeping-lighthouse@1"] = str(source_paths.get("sleeping-lighthouse@1", "user://lighthouse-journey-v3.json"))

func begin_scan() -> bool:
	if _worker != null and _worker.is_alive(): return false
	_finish_worker()
	_jobs.clear()
	_rows.clear()
	last_error = ""
	_scanning = true
	for chapter: String in Registry.keys():
		_enqueue_chapter(chapter, "relay")
		_enqueue_archives(chapter, "relay")
	var lighthouse := "sleeping-lighthouse@1"
	_enqueue_chapter(lighthouse, "lighthouse")
	_enqueue_archives(lighthouse, "lighthouse")
	return true

func scan_pending() -> bool:
	return _scanning or _worker != null or not _jobs.is_empty()

func cancel_scan() -> void:
	# Join the single bounded verifier before dropping its immutable snapshot.
	# No file or gameplay state is written by this worker.
	_finish_worker()
	_jobs.clear()
	_scanning = false

func advance_scan() -> bool:
	if not _scanning: return false
	if _worker != null:
		if _worker.is_alive(): return true
		var result: Variant = _worker.wait_to_finish()
		var completed := _worker_job
		_worker = null
		_worker_job = {}
		_worker_validator = null
		if result is Dictionary and result.get("ok", false):
			_append_rows(completed, result)
		elif result is Dictionary and result.get("hold", false):
			last_error = "Some saved replays could not be checked."
	if _jobs.is_empty():
		_scanning = false
		return false
	var job: Dictionary = _jobs.pop_front()
	var snapshot := _capture(job)
	if snapshot.is_empty(): return true
	var validator: RefCounted = LighthouseJourney.new(str(job.path)) if job.kind == "lighthouse" else RelayJourney.new(str(job.path), null, str(job.chapter))
	_worker_job = job
	_worker_validator = validator
	_worker = Thread.new()
	if _worker.start(Callable(get_script(), "_verify_snapshot").bind(snapshot, validator)) != OK:
		_worker = null
		_worker_job = {}
		_worker_validator = null
		last_error = "Saved replays could not be checked."
	return true

func items() -> Array[Dictionary]:
	return _rows.duplicate(true)

func _enqueue_chapter(chapter: String, kind: String) -> void:
	var path := str(_paths.get(chapter, ""))
	if path.is_empty(): return
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
	var snapshot := job.duplicate(true)
	snapshot.raw = []
	if job.source_kind == "archive":
		var archive_path := str(job.path) + ".attempt-" + str(job.source_id) + ".json"
		var bytes := _read_bounded(archive_path, MAX_SAVE_BYTES)
		if bytes.is_empty(): return {}
		snapshot.raw.append(bytes)
		return snapshot
	for suffix: String in ["", ".tmp", ".backup"]:
		var candidate := str(job.path) + suffix
		if not FileAccess.file_exists(candidate): continue
		var bytes := _read_bounded(candidate, MAX_SAVE_BYTES)
		if bytes.is_empty(): return {}
		snapshot.raw.append({"suffix": suffix, "text": bytes})
	return snapshot if not snapshot.raw.is_empty() else {}

static func _read_bounded(path: String, maximum: int) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return ""
	if file.get_length() < 1 or file.get_length() > maximum:
		file.close()
		return ""
	var text := file.get_as_text()
	file.close()
	return text

static func _verify_snapshot(snapshot: Dictionary, validator: RefCounted) -> Dictionary:
	# This worker sees only captured bytes plus a private native validator.
	# It does not open files, call load_data(), touch gameplay state, or repair.
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
			var checked_archive: Dictionary = validator._validate_state(archived)
			if not checked_archive.get("valid", false): return {"ok": false, "hold": true}
			return {"ok": true, "state": archived.duplicate(true)}
		if not validator._envelope_valid(value) or not value.get(field) is Dictionary: return {"ok": false, "hold": true}
		var state: Dictionary = value[field]
		var checked_current: Dictionary = validator._validate_state(state)
		if not checked_current.get("valid", false): return {"ok": false, "hold": true}
		var generation := int(value.get("generation", 0))
		if generation > selected_generation:
			selected_generation = generation
			selected = state.duplicate(true)
	return {"ok": true, "state": selected} if not selected.is_empty() else {"ok": false}

func _append_rows(job: Dictionary, result: Dictionary) -> void:
	var pairs: Variant = result.get("state", {}).get("pairs", [])
	if not pairs is Array: return
	if pairs.is_empty(): return
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
		_rows.append({"id": item_id, "visibility_key": item_id, "chapter_key": str(job.chapter), "chapter_title": chapter_title,
			"stage_id": stage_id, "stage_index": index, "title": stage_title, "source_id": attempt_id, "attempt_id": attempt_id,
			"source_family": str(job.source_kind), "content_id": content_id,
			"archived": job.source_kind == "archive", "pair": pair.duplicate(true)})

func _finish_worker() -> void:
	if _worker == null: return
	_worker.wait_to_finish()
	_worker = null
	_worker_job = {}
	_worker_validator = null

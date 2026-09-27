extends RefCounted
## Cosmetic progress is separate from every gameplay journal. Only public place
## IDs and two earned variants persist here; successful gameplay never depends
## on a keepsake write succeeding.
const Storage = preload("res://services/local_save.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Levels = preload("res://core/levels.gd")
const LegacySimulation = preload("res://core/simulation.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PATH := "user://home-keepsakes-v1.json"
const MAX_BYTES := 16384
const MAX_SOURCE_BYTES := 2097152
const LOAD_ERROR := PlayerCopy.HOME_KEEPSAKES_LOAD_ERROR
const ENVELOPE_KEYS := ["version", "generation", "settings", "attempts", "completed", "replays", "room", "home_keepsakes"]
static var _active: WeakRef
static var _unclaimed: Dictionary = {}
var last_error := ""
var read_only := false
var _path := PATH
var _storage: RefCounted
var _earned: Dictionary = {}
var _pending_awards: Dictionary = {}
var _loaded := false
var _jobs: Array[Dictionary] = []
var _queued: Dictionary = {}
var _scanned: Dictionary = {}
var _friend_collection: WeakRef
var _friend_pending := false
var _worker: Thread
var _worker_job: Dictionary = {}
var _work_generation := 0
var _source_paths: Dictionary = {}
var _solo_scripts: Dictionary = {}

func _init(path: String = PATH, storage: RefCounted = null, source_paths: Dictionary = {}) -> void:
	_path = path
	_storage = Storage.new(path) if storage == null else storage
	# Test dependency only. Production callers use the canonical journal paths.
	for chapter: String in Catalog.CHAPTERS:
		if source_paths.get(chapter) is String and not source_paths[chapter].is_empty(): _source_paths[chapter] = source_paths[chapter]
	# Load bundled code during service construction, before the home view opens.
	# First-use script compilation must not land in an otherwise cheap UI poll.
	_solo_scripts["relay"] = load("res://services/relay_journey.gd")
	_solo_scripts["lighthouse"] = load("res://services/lighthouse_journey.gd")

func activate() -> void:
	_ensure_loaded()
	_active = weakref(self)
	_merge_pending(_unclaimed)
	_unclaimed.clear()
	_flush_pending()

func deactivate() -> void:
	if _active != null and _active.get_ref() == self:
		for id: String in _pending_awards:
			_merge_mark(_unclaimed, id, _pending_awards[id])
		_active = null
	cancel_backfill()
	# App teardown only. Normal home navigation can use non-blocking cancellation.
	if _worker != null:
		_worker.wait_to_finish()
		_worker = null
		_worker_job = {}

func cancel_backfill() -> void:
	_work_generation += 1
	_jobs.clear()
	_queued.clear()
	_friend_pending = false

func load_data() -> void:
	_loaded = true
	read_only = false
	last_error = ""
	_earned.clear()
	cancel_backfill()
	_scanned.clear()
	var unreadable: Array[String] = []
	for suffix: String in ["", ".tmp", ".backup"]:
		var candidate := _path + suffix
		if not FileAccess.file_exists(candidate): continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null or file.get_length() > MAX_BYTES:
			_hold(LOAD_ERROR)
			return
		var json := JSON.new()
		var parsed := json.parse(file.get_as_text())
		file.close()
		if parsed != OK:
			unreadable.append(candidate)
			continue
		if not _valid_envelope(json.data):
			_hold(LOAD_ERROR)
			return
	_storage.load_data()
	if _storage.read_only:
		_hold(LOAD_ERROR)
		return
	if not _storage.loaded_from.is_empty():
		if not _valid_envelope(_storage.data):
			_hold(LOAD_ERROR)
			return
		_earned = _storage.data.home_keepsakes.earned.duplicate(true)
	for candidate: String in unreadable:
		if not _preserve_unreadable(candidate):
			_hold(LOAD_ERROR)
			return

func earned_descriptors() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for item: Dictionary in Catalog.all():
		var mark: Dictionary = _earned.get(item.id, {})
		if not mark.get("solo", false) and not mark.get("friend", false): continue
		item.solo = mark.get("solo", false)
		item.friend = mark.get("friend", false)
		result.append(item)
	return result

func reconcile_solo(legacy_replays: Dictionary = {}) -> bool:
	_ensure_loaded()
	if read_only: return false
	# Only committed replay containers are supplied by the caller. A completed
	# flag or a rehearsal is never an input to this boundary.
	for item: Dictionary in Catalog.all():
		if item.family != "earlier" or _has_award(item.id, "solo"): continue
		var value: Variant = legacy_replays.get(item.stage_id)
		if not value is Dictionary or value.is_empty(): continue
		if JSON.stringify(value).to_utf8_buffer().size() > MAX_SOURCE_BYTES: continue
		var fingerprint := Canonical.digest(value)
		_queue_job("legacy:" + item.id, fingerprint, {"kind": "legacy", "id": item.id, "level_id": item.stage_id, "attempt": value.duplicate(true)})
	for chapter: String in Catalog.CHAPTERS:
		if _chapter_earned(chapter, "solo"): continue
		var path: String = _source_paths.get(chapter, Catalog.local_path(chapter))
		var fingerprint := _source_fingerprint(path)
		_queue_job("chapter:" + chapter, fingerprint, {"kind": "chapter", "chapter": chapter, "path": path})
		var directory := DirAccess.open(path.get_base_dir())
		if directory == null: continue
		var prefix := path.get_file() + ".attempt-"
		var archives: Array[String] = []
		for filename: String in directory.get_files():
			if filename.begins_with(prefix) and filename.ends_with(".json"):
				var id := filename.trim_prefix(prefix).trim_suffix(".json")
				if id.length() == 64 and id.is_valid_hex_number(false): archives.append(id)
		archives.sort()
		# Existing journals allow at most 32 immutable attempts per chapter.
		for id: String in archives.slice(0, 32):
			var archive_path := path + ".attempt-" + id + ".json"
			_queue_job("archive:" + chapter + ":" + id, _archive_fingerprint(archive_path), {"kind": "archive", "chapter": chapter, "path": path, "archive_id": id})
	return advance_backfill(1)

func backfill_pending() -> bool:
	return _worker != null or not _jobs.is_empty() or _friend_pending

func advance_backfill(max_sources: int = 1) -> bool:
	_ensure_loaded()
	if read_only:
		if _worker != null and not _worker.is_alive():
			_worker.wait_to_finish()
			_worker = null
			_worker_job = {}
		return false
	var okay := _flush_pending()
	# The argument is retained for callers; only one worker may run at a time.
	if max_sources < 1: return okay
	if _worker != null:
		if _worker.is_alive(): return okay
		var result: Variant = _worker.wait_to_finish()
		var completed := _worker_job
		_worker = null
		_worker_job = {}
		if completed.generation != _work_generation or not result is Dictionary: return okay
		if completed.kind == "friend":
			var collection: RefCounted = _friend_collection.get_ref() if _friend_collection != null else null
			if collection != null and collection.accept_keepsake_result(completed.snapshot, result):
				if not _award(result.get("ids", []), "friend"): okay = false
		else:
			_scanned[completed.source] = completed.fingerprint
			if result.get("ok", false) and not _award(result.get("ids", []), "solo"): okay = false
		return okay
	if not _jobs.is_empty():
		var job: Dictionary = _jobs.pop_front()
		_queued.erase(job.source)
		if job.kind != "legacy" and _chapter_earned(job.chapter, "solo"):
			_scanned[job.source] = job.fingerprint
			return okay
		var snapshot := _capture_solo_source(job)
		if snapshot.is_empty():
			_scanned[job.source] = job.fingerprint
			return okay
		var validator: RefCounted = null
		if job.kind != "legacy":
			# Instantiate on the main thread. The worker receives a private pure
			# validator and immutable bytes; it never calls journey.load_data().
			validator = _solo_scripts.lighthouse.new(job.path) if job.chapter == Catalog.LIGHTHOUSE else _solo_scripts.relay.new(job.path, null, job.chapter)
		job.generation = _work_generation
		return _start_worker(job, snapshot, validator) and okay
	if _friend_pending and _friend_collection != null:
		var collection: RefCounted = _friend_collection.get_ref()
		if collection == null: _friend_pending = false
		elif not reconcile_friend(collection): okay = false
	return okay

func reconcile_friend(collection: RefCounted) -> bool:
	_ensure_loaded()
	if read_only or collection == null or collection.get_script() != load("res://services/shared_replay_collection.gd"): return false
	_friend_collection = weakref(collection)
	if _worker != null:
		_friend_pending = true
		return _flush_pending()
	var result: Dictionary = collection.keepsake_backfill_snapshot(not _friend_pending)
	_friend_pending = bool(result.get("pending", false))
	var ids: Array[String] = []
	for id: Variant in result.get("ids", []):
		if id is String: ids.append(id)
	var saved := _award(ids, "friend")
	if not result.get("source", {}).is_empty():
		var snapshot: Dictionary = result.source
		var job := {"kind": "friend", "generation": _work_generation, "snapshot": snapshot}
		if not _start_worker(job, snapshot, load("res://services/shared_replay_collection.gd")): return false
	return saved and result.get("ok", false)

func _start_worker(job: Dictionary, snapshot: Dictionary, validator: RefCounted) -> bool:
	if not Thread.is_main_thread(): return false
	_worker_job = job
	_worker = Thread.new()
	# Bind the Script's static function, not this owning service, to avoid a
	# reference cycle and keep teardown independent of the worker callable.
	var error := _worker.start(Callable(get_script(), "_verify_source_snapshot").bind(snapshot, validator))
	if error == OK: return true
	_worker = null
	_worker_job = {}
	last_error = PlayerCopy.HOME_KEEPSAKES_RETRY
	return false

static func _capture_solo_source(job: Dictionary) -> Dictionary:
	if job.kind == "legacy": return job.duplicate(true)
	var result := job.duplicate(true)
	result.raw = []
	var path: String = job.path + ".attempt-" + str(job.archive_id) + ".json" if job.kind == "archive" else job.path
	for suffix: String in ([""] if job.kind == "archive" else ["", ".tmp", ".backup"]):
		if not FileAccess.file_exists(path + suffix): continue
		var file := FileAccess.open(path + suffix, FileAccess.READ)
		if file == null or file.get_length() > MAX_SOURCE_BYTES: return {}
		result.raw.append(file.get_as_text())
		file.close()
	return result if not result.raw.is_empty() else {}

static func _verify_source_snapshot(snapshot: Dictionary, validator: RefCounted) -> Dictionary:
	# Worker boundary: local arguments, pure native simulation, no file/account
	# reads, repair writes, active-ledger calls or shared-instance mutation.
	if snapshot.kind == "friend": return validator.verify_keepsake_snapshot(snapshot)
	if snapshot.kind == "legacy":
		var attempt: Dictionary = snapshot.attempt
		if not attempt.get("a") is Dictionary or not attempt.get("b") is Dictionary or attempt.a.get("role") != "a" or attempt.b.get("role") != "b": return {"ok": false, "ids": []}
		var checked: Dictionary = LegacySimulation.verify_recording(Levels.get_level(snapshot.level_id), attempt.b, attempt.a)
		var valid: bool = checked.get("valid", false) and checked.get("snapshot", {}).get("can_commit", false)
		return {"ok": valid, "ids": [snapshot.id] if valid else []}
	var field := "lighthouse" if snapshot.chapter == Catalog.LIGHTHOUSE else "relay"
	var selected: Dictionary = {}
	var generation := -1
	var verified: Dictionary = {}
	for raw: String in snapshot.raw:
		var json := JSON.new()
		if json.parse(raw) != OK: continue
		var value: Variant = json.data
		if not value is Dictionary: return {"ok": false, "ids": []}
		var state: Dictionary
		var candidate_generation := 0
		if snapshot.kind == "archive":
			if value.size() != 2 or value.get("archive_version") != 1 or not value.get(field) is Dictionary or Canonical.digest(value[field]) != snapshot.archive_id: return {"ok": false, "ids": []}
			state = value[field]
		else:
			if not validator._envelope_valid(value) or not value.get(field) is Dictionary: return {"ok": false, "ids": []}
			state = value[field]
			candidate_generation = int(value.get("generation", 0))
		var digest := Canonical.digest(state)
		if not verified.has(digest):
			var checked: Dictionary = validator._validate_state(state)
			if not checked.get("valid", false): return {"ok": false, "ids": []}
			verified[digest] = true
		if candidate_generation > generation:
			selected = state
			generation = candidate_generation
	return {"ok": not selected.is_empty(), "ids": _prefix_places(snapshot.chapter, selected.pairs.size()) if not selected.is_empty() else []}

## Internal observers: callers invoke these only after their accepted evidence
## has passed native replay verification and its gameplay save has succeeded.
## They receive no recordings or private identifiers, and cannot fail gameplay.
static func record_solo_prefix(chapter: String, accepted_stage_count: int) -> void:
	_dispatch(_prefix_places(chapter, accepted_stage_count), "solo")

static func record_friend_prefix(chapter: String, accepted_stage_count: int) -> void:
	_dispatch(_prefix_places(chapter, accepted_stage_count), "friend")

static func record_friend_place(chapter: String, stage_index: int) -> void:
	var places := Catalog.chapter_places(chapter)
	if stage_index >= 0 and stage_index < places.size(): _dispatch([places[stage_index]], "friend")

static func record_legacy_solo(level_id: String) -> void:
	_dispatch(["earlier/" + level_id], "solo")

static func record_legacy_friend(level_id: String) -> void:
	_dispatch(["earlier/" + level_id], "friend")

static func _dispatch(ids: Array, variant: String) -> void:
	var target: RefCounted = _active.get_ref() if _active != null else null
	if target != null:
		target._award(ids, variant)
		return
	for id: String in ids:
		var item := Catalog.by_id(id)
		if item.is_empty() or (variant == "friend" and not item.friend_available): continue
		_merge_mark(_unclaimed, id, {variant: true})

static func _prefix_places(chapter: String, count: int) -> Array[String]:
	var places := Catalog.chapter_places(chapter)
	var result: Array[String] = []
	if count < 0 or count > places.size(): return result
	for index in range(count): result.append(places[index])
	return result

func _award(ids: Array, variant: String) -> bool:
	_ensure_loaded()
	if variant not in ["solo", "friend"]: return false
	for id: Variant in ids:
		if not id is String: continue
		var item := Catalog.by_id(id)
		if item.is_empty() or (variant == "friend" and not item.friend_available): continue
		_merge_mark(_pending_awards, id, {variant: true})
	return _flush_pending()

func _flush_pending() -> bool:
	if read_only: return false
	var marks := _earned.duplicate(true)
	for id: String in _pending_awards: _merge_mark(marks, id, _pending_awards[id])
	if marks == _earned:
		_pending_awards.clear()
		return true
	var value := {"schema_version": 1, "earned": marks}
	if JSON.stringify(value).to_utf8_buffer().size() > MAX_BYTES - 4096 or not _storage.update_values({"home_keepsakes": value}):
		last_error = PlayerCopy.HOME_KEEPSAKES_RETRY
		return false
	_earned = marks
	_pending_awards.clear()
	last_error = ""
	return true

func _merge_pending(values: Dictionary) -> void:
	for id: String in values: _merge_mark(_pending_awards, id, values[id])

static func _merge_mark(target: Dictionary, id: String, value: Dictionary) -> void:
	var mark: Dictionary = target.get(id, {"solo": false, "friend": false})
	mark.solo = mark.solo or value.get("solo", false)
	mark.friend = mark.friend or value.get("friend", false)
	target[id] = mark

func _has_award(id: String, variant: String) -> bool:
	return _earned.get(id, {}).get(variant, false) or _pending_awards.get(id, {}).get(variant, false)

func _chapter_earned(chapter: String, variant: String) -> bool:
	for id: String in Catalog.chapter_places(chapter):
		if not _has_award(id, variant): return false
	return true

func _queue_job(source: String, fingerprint: String, value: Dictionary) -> void:
	if fingerprint.is_empty() or _scanned.get(source) == fingerprint or _queued.has(source): return
	value.source = source
	value.fingerprint = fingerprint
	_jobs.append(value)
	_queued[source] = true

static func _source_fingerprint(path: String, generations: bool = true) -> String:
	var values: Array[String] = []
	for suffix: String in (["", ".tmp", ".backup"] if generations else [""]):
		var candidate := path + suffix
		if not FileAccess.file_exists(candidate): continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null or file.get_length() > MAX_SOURCE_BYTES: return ""
		file.close()
		values.append(suffix + ":" + FileAccess.get_sha256(candidate))
	return "" if values.is_empty() else Canonical.digest(values)

static func _archive_fingerprint(path: String) -> String:
	# Scheduling only: the archive's full digest and native replay are checked
	# inside its incremental job. Do not hash every historical file on home open.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_SOURCE_BYTES: return ""
	var length := file.get_length()
	file.close()
	return "%d:%d" % [FileAccess.get_modified_time(path), length]

static func _valid_envelope(value: Variant) -> bool:
	if not value is Dictionary or value.size() != ENVELOPE_KEYS.size(): return false
	for key: String in ENVELOPE_KEYS:
		if not value.has(key): return false
	if not _integer(value.version) or value.version != 1 or not _integer(value.generation) or value.generation < 0 or value.generation > 9007199254740991 or not Storage.default_settings_envelope_valid(value.settings): return false
	for key: String in ["attempts", "completed", "replays", "room"]:
		if not value[key] is Dictionary or not value[key].is_empty(): return false
	var state: Variant = value.home_keepsakes
	if not state is Dictionary or state.size() != 2 or not _integer(state.get("schema_version")) or state.schema_version != 1 or not state.get("earned") is Dictionary or state.earned.size() > Catalog.ROWS.size(): return false
	for id: Variant in state.earned:
		if not id is String: return false
		var item := Catalog.by_id(id)
		var mark: Variant = state.earned[id]
		if item.is_empty() or not mark is Dictionary or mark.size() != 2 or not mark.get("solo") is bool or not mark.get("friend") is bool or (not mark.solo and not mark.friend) or (mark.friend and not item.friend_available): return false
	return true

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

func _preserve_unreadable(path: String) -> bool:
	var digest := FileAccess.get_sha256(path)
	if digest.is_empty(): return false
	var backup := path + ".unreadable-" + digest
	if FileAccess.file_exists(backup): return FileAccess.get_sha256(backup) == digest
	return DirAccess.copy_absolute(path, backup) == OK and FileAccess.get_sha256(backup) == digest

func _hold(message: String) -> void:
	read_only = true
	last_error = message

func _ensure_loaded() -> void:
	if not _loaded: load_data()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _worker != null and _worker.is_started():
		# Teardown must join; ordinary cancellation only discards the result and
		# is polled without blocking the rendering thread.
		_worker.wait_to_finish()
		_worker = null

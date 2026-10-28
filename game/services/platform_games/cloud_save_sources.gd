extends RefCounted
## Where cloud save reads and writes this phone's progress, always through the files' owners:
## Main's journey save (settings, finished earlier islands and their replays), HomeKeepsakes,
## the Hard marks (HardMode) and the solo chapter journals. Built by Main; lives only while Main does.
##
## Safety, kept from the local save rules:
## - nothing is collected or applied while a save is held read-only (damaged or newer);
## - changes apply only at Home, where no chapter has its journal open;
## - a cloud journal fills only a chapter this phone has never started, and only after the
##   journal class itself has loaded and checked it from a staging copy, so a bad copy can never
##   put a chapter on hold; a journal with local progress is never replaced. Its unfinished draft
##   is left behind (it would only be checked when the chapter opens), and a copy that failed the
##   check is remembered by digest and never checked again.
const Bundle = preload("res://services/platform_games/cloud_save_bundle.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RelayJourney = preload("res://services/relay_journey.gd")
const LocalSave = preload("res://services/local_save.gd")
const AtomicFile = preload("res://services/atomic_file.gd")
const Levels = preload("res://core/levels.gd")
const State = preload("res://services/platform_games/platform_games_state.gd")
const HardMode = preload("res://services/hard_mode.gd")

const STAGING := "user://cloud-save-staging"
const MAX_JOURNAL_BYTES := RelayJourney.MAX_SAVE_BYTES
## Checking a cloud journal replays its stages; a run checks at most this many and comes back for the rest.
const JOURNALS_PER_RUN := 1

var _host: WeakRef
var _state: RefCounted
## Tests: journal file name -> chapter key and path (production reads the chapter registry).
var journal_paths: Dictionary = {}
## Tests: where the staging copies go.
var staging := STAGING
## Tests: the Hard marks file.
var hard_path := HardMode.MARKS_PATH

func _init(host: Node, state: RefCounted) -> void:
	_host = weakref(host)
	_state = state
	for key: String in Registry.keys():
		var path := str(Registry.descriptor(key).get("local_path", ""))
		if path.begins_with("user://") and not path.get_file().is_empty(): journal_paths[path.get_file()] = {"chapter": key, "path": path}

func _main() -> Node:
	var host: Variant = _host.get_ref()
	return host if host is Node and is_instance_valid(host) else null

func ready() -> bool:
	var host := _main()
	return host != null and host.saves != null and not host.saves.read_only and host.home_keepsakes != null and not host.home_keepsakes.read_only

func at_home() -> bool:
	var host := _main()
	return host != null and host.mode == "home"

## A cheap fingerprint of every source file: size and modified time, no reads.
func stamp() -> String:
	var host := _main()
	var parts: Array[String] = []
	var paths: Array[String] = [host.saves.path if host != null else LocalSave.PATH, "user://home-keepsakes-v1.json", hard_path]
	var names: Array = journal_paths.keys()
	names.sort()
	for name: String in names: paths.append(journal_paths[name].path)
	for path: String in paths:
		parts.append("%s:%d:%d" % [path.get_file(), FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0, _size(path)])
	return "|".join(parts)

static func _size(path: String) -> int:
	if not FileAccess.file_exists(path): return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return -1
	var length := file.get_length()
	file.close()
	return length

## The settings' change stamp: kept while they stay the same, set to now when they change.
## Untouched defaults on a phone that never synced count as stamp 0 (any real choice wins).
func settings_stamp(values: Dictionary) -> int:
	var digest := JSON.stringify(values, "", true).sha256_text()
	if _state.cloud("settings_hash") == digest: return int(_state.cloud("settings_stamp", 0))
	var stamp := 0
	if _state.cloud("settings_hash") != null or values != _default_values(): stamp = State.now_ms()
	_state.set_cloud({"settings_hash": digest, "settings_stamp": stamp})
	return stamp

static func _default_values() -> Dictionary:
	var out := {}
	var defaults: Dictionary = LocalSave.defaults().settings
	for key: String in Bundle.SETTINGS_KEYS:
		if defaults.get(key) is bool: out[key] = defaults[key]
	return out

static func _values(settings: Variant) -> Dictionary:
	var out := {}
	if settings is Dictionary:
		for key: String in Bundle.SETTINGS_KEYS:
			if settings.get(key) is bool: out[key] = settings[key]
	return out

## This phone's bundle, or {} when a source is held. Journals are read on a worker thread.
func collect() -> Dictionary:
	var host := _main()
	if host == null or not ready(): return {}
	var data: Dictionary = host.saves.data
	var keepsakes: Dictionary = host.home_keepsakes.earned_marks()
	var hard: Dictionary = HardMode.new(hard_path).marks()
	var task_paths := {}
	for name: String in journal_paths: task_paths[name] = journal_paths[name].path
	var result := {}
	var task := WorkerThreadPool.add_task(_read_journals.bind(task_paths, result))
	# Wait on the SceneTree, not Main: Main may be freed meanwhile, and the task is always joined.
	var tree := Engine.get_main_loop() as SceneTree
	while not WorkerThreadPool.is_task_completed(task):
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	host = null
	if _main() == null or not ready(): return {}
	return Bundle.collect(data, settings_stamp(_values(data.get("settings"))), keepsakes, result, hard)

## Worker: each journal's envelope as parsed JSON. Reads only; skips anything odd.
static func _read_journals(paths: Dictionary, out: Dictionary) -> void:
	for name: String in paths:
		var path: String = paths[name]
		if not FileAccess.file_exists(path) or _size(path) > MAX_JOURNAL_BYTES: continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and Bundle.journal_stages(parsed) > 0: out[name] = parsed

## Brings what the merged bundle has and this phone lacks into the owners. True when nothing
## more can be applied later (the rest, if any, is held back by design); false to try again.
func apply(merged: Dictionary) -> bool:
	var host := _main()
	if host == null or not ready() or not at_home(): return false
	var data: Dictionary = host.saves.data
	var changes := {}
	var local_values := _values(data.get("settings"))
	var local_stamp := settings_stamp(local_values)
	var settings_changed := false
	if int(merged.settings.stamp) > local_stamp and merged.settings.values != local_values and not merged.settings.values.is_empty():
		var settings: Dictionary = data.settings.duplicate(true)
		for key: String in merged.settings.values: settings[key] = merged.settings.values[key]
		changes.settings = settings
		settings_changed = true
	var completed: Dictionary = data.get("completed", {}).duplicate(true)
	var replays: Dictionary = data.get("replays", {}).duplicate(true)
	var removed: Dictionary = data.get("removed_replays", {}).duplicate(true)
	for id: String in merged.removed_replays:
		if not id in Levels.IDS: continue
		var marks: Dictionary = removed.get(id, {}).duplicate(true)
		for digest: String in merged.removed_replays[id]: marks[digest] = true
		removed[id] = marks
	for id: String in merged.completed:
		if id in Levels.IDS and not completed.has(id): completed[id] = true
	for id: String in merged.replays:
		if id in Levels.IDS and not replays.has(id) and not removed.get(id, {}).has(Bundle.replay_digest(merged.replays[id])):
			replays[id] = LocalSave.normalize_attempt(merged.replays[id])
	if completed != data.get("completed", {}): changes.completed = completed
	if replays != data.get("replays", {}): changes.replays = replays
	if removed != data.get("removed_replays", {}): changes.removed_replays = removed
	if not changes.is_empty() and not host.saves.update_values(changes): return false
	if settings_changed:
		_state.set_cloud({"settings_hash": JSON.stringify(_values(changes.settings), "", true).sha256_text(), "settings_stamp": int(merged.settings.stamp)})
		host._apply_settings()
	if not host.home_keepsakes.adopt_earned(merged.keepsakes): return false
	if not HardMode.new(hard_path).adopt(merged.get("hard", {})): return false
	return _fill_journals(merged.journals)

## Writes cloud journals for chapters this phone has never started. False while some remain.
func _fill_journals(journals: Dictionary) -> bool:
	var checked := 0
	var rejected: Array = _state.cloud("rejected_journals", [])
	for name: String in journals:
		var target: Dictionary = journal_paths.get(name, {})
		if target.is_empty() or _exists(target.path): continue
		var digest := JSON.stringify(journals[name].envelope).sha256_text()
		if digest in rejected: continue
		if checked >= JOURNALS_PER_RUN: return false
		checked += 1
		if not _adopt_journal(target, journals[name]) and not _exists(target.path):
			rejected = (rejected + [digest]).slice(-16)
			_state.set_cloud({"rejected_journals": rejected})
	return true

static func _exists(path: String) -> bool:
	for candidate: String in AtomicFile.read_candidates(path):
		if FileAccess.file_exists(candidate): return true
	return false

## Loads the cloud envelope through RelayJourney from a staging copy; only a journal that loads
## clean with the same finished stages is written to the real path. Anything else is skipped.
func _adopt_journal(target: Dictionary, entry: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(staging)
	var staged := staging.path_join(str(target.path).get_file())
	AtomicFile.remove(staged)
	var envelope: Dictionary = entry.envelope.duplicate(true)
	if envelope.get("relay") is Dictionary: envelope.relay.draft = {}
	var text := JSON.stringify(envelope)
	if text.to_utf8_buffer().size() > MAX_JOURNAL_BYTES or not AtomicFile.write_text(staged, text): return false
	var journey := RelayJourney.new(staged, null, str(target.chapter))
	journey.load_data()
	var good: bool = not journey.read_only and journey.pairs().size() == int(entry.stages)
	journey = null
	AtomicFile.remove(staged)
	if not good or _exists(target.path): return false
	return AtomicFile.write_text(target.path, text)

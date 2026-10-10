extends SceneTree

const Collection = preload("res://services/solo_replay_collection.gd")
const Journey = preload("res://services/relay_journey.gd")
const LighthouseJourney = preload("res://services/lighthouse_journey.gd")
const Archive = preload("res://services/attempt_archive.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Save = preload("res://services/local_save.gd")
const Canonical = preload("res://core/v2/canonical.gd")

var checks := 0
var failures := 0
var path := "user://solo-replay-collection-%d.json" % Time.get_ticks_usec()
var lighthouse_path := path + ".lighthouse.json"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var journey := Journey.new(path, null, Registry.RELAY)
	journey.load_data()
	# These frozen replay fixtures predate the current preferred rule pin.
	journey._state.simulation_version = 2
	_check(journey.accept_recording(_fixture("relay-a")) and journey.accept_recording(_fixture("relay-b")), "A valid accepted pair is written to the solo journal")
	_check(journey.accept_recording(_fixture("garden-a")) and journey.save_draft(_fixture("garden-b")), "The journal also contains an unpaired turn and a draft")
	var archive_error := Archive.save(path, "relay", journey._state, Journey.MAX_SAVE_BYTES, Journey.MAX_ARCHIVED_ATTEMPTS)
	_check(archive_error.is_empty(), "An immutable accepted journal archive is available")
	var light_fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/first-two-v3.json"))
	var lighthouse := LighthouseJourney.new(lighthouse_path)
	var light_state: Dictionary = lighthouse._empty_state()
	light_state.pairs = light_fixtures.pairs.duplicate(true)
	var light_envelope := Save.defaults()
	light_envelope.generation = 1
	light_envelope.lighthouse = light_state
	var light_file := FileAccess.open(lighthouse_path, FileAccess.WRITE)
	light_file.store_string(JSON.stringify(light_envelope))
	light_file.close()
	var before := FileAccess.get_file_as_bytes(path)
	var archive_id := Canonical.digest(journey._state)
	var archive_path := path + ".attempt-" + archive_id + ".json"
	var archive_before := FileAccess.get_file_as_bytes(archive_path)
	Collection._verified.clear()
	var service := Collection.new({Registry.RELAY: path, "sleeping-lighthouse@1": lighthouse_path})
	_check(service.begin_scan(), "Read-only solo discovery starts")
	var started: Dictionary = service.scan_progress()
	_check(started.active and started.sources_total == 3 and started.sources_done == 0 and started.settled == 0 and service.settled_items().is_empty(), "Progress counts the queued current, archive and Lighthouse sources without inventing completed work")
	var deadline := Time.get_ticks_msec() + 15000
	var counted: Array[int] = []
	while service.scan_pending() and Time.get_ticks_msec() < deadline:
		service.advance_scan()
		counted.append(int(service.scan_progress().sources_done))
		if service.scan_pending(): _check(service.settled_items().all(func(row: Dictionary) -> bool: return row.chapter_key != Registry.RELAY or (service._jobs.all(func(job: Dictionary) -> bool: return job.chapter != Registry.RELAY) and service._worker_job.get("chapter", "") != Registry.RELAY)), "Settled rows never include a chapter with a source still being checked")
		await process_frame
	var rows := service.items()
	var growing := true
	for index in range(1, counted.size()): growing = growing and counted[index] >= counted[index - 1]
	_check(growing and service.scan_progress().sources_done == 3 and not service.scan_progress().active, "Completed sources only grow and finish at the queued total")
	_check(service.settled_items().size() == rows.size(), "Every row is settled once the scan has finished")
	_check(not service.scan_pending() and rows.size() == 4, "Current, archived and Lighthouse accepted pairs are discoverable")
	var relay_rows: Array[Dictionary] = rows.filter(func(row: Dictionary) -> bool: return row.get("chapter_key") == Registry.RELAY)
	_check(relay_rows.size() == 2 and relay_rows.all(func(row: Dictionary) -> bool: return row.get("stage_id") == "relay" and row.get("pair", {}).get("a", {}).get("role") == "a" and row.get("pair", {}).get("b", {}).get("role") == "b"), "Draft and unpaired turns stay out of solo replay rows")
	_check(rows.any(func(row: Dictionary) -> bool: return row.get("archived", false)) and rows.any(func(row: Dictionary) -> bool: return not row.get("archived", true)), "Current and immutable archive rows retain separate identities")
	_check(rows.filter(func(row: Dictionary) -> bool: return row.get("chapter_key") == "sleeping-lighthouse@1").map(func(row: Dictionary) -> String: return row.get("stage_id", "")) == ["borrowed-light", "missing-piece"], "Lighthouse accepted pairs map to their authored stage keys")
	_check(FileAccess.get_file_as_bytes(path) == before and FileAccess.get_file_as_bytes(archive_path) == archive_before, "Scanning does not repair or rewrite gameplay journal files")
	_check(service.last_error.is_empty(), "Valid current and archive snapshots pass native replay validation")
	await _memo_and_cancel(rows, before, archive_path, archive_before)
	var paths: Dictionary = Collection.new()._paths
	_check(paths.size() == Registry.keys().size() + 1 and paths.has("sleeping-lighthouse@1"), "The default collection covers every registered chapter plus Lighthouse")
	_cleanup()
	print("Solo replay collection: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _memo_and_cancel(rows: Array[Dictionary], before: PackedByteArray, archive_path: String, archive_before: PackedByteArray) -> void:
	# Unchanged bytes reuse the earlier native check, so a new screen instance
	# (after a chapter scene) lists them without starting a verifier.
	var again := Collection.new({Registry.RELAY: path, "sleeping-lighthouse@1": lighthouse_path})
	again.begin_scan()
	var steps := 0
	var workers := 0
	while again.scan_pending() and steps < 50:
		again.advance_scan()
		if again._worker != null: workers += 1
		steps += 1
		await process_frame
	_check(not again.scan_pending() and workers == 0 and steps <= 3, "A repeated scan of unchanged sources finishes from remembered checks without a worker")
	_check(Canonical.same(again.items(), rows), "Remembered checks produce exactly the same rows")
	# Changed bytes are never served from the memo.
	var journey := Journey.new(path, null, Registry.RELAY)
	journey.load_data()
	_check(journey.fork_from_stage(0), "Restarting the chapter archives and changes the current journal")
	var changed := Collection.new({Registry.RELAY: path, "sleeping-lighthouse@1": lighthouse_path})
	changed.begin_scan()
	var checked_changed := false
	while changed.scan_pending() and steps < 2000:
		changed.advance_scan()
		if changed._worker != null: checked_changed = true
		steps += 1
		await process_frame
	_check(checked_changed and not changed.scan_pending(), "A changed journal is checked again on a worker rather than served from the memo")
	before = FileAccess.get_file_as_bytes(path)
	# Leaving the list never waits for the verifier, and only one verifier runs.
	Collection._verified.clear()
	var cancelled := Collection.new({Registry.RELAY: path, "sleeping-lighthouse@1": lighthouse_path})
	cancelled.begin_scan()
	while cancelled._worker == null and cancelled.scan_pending():
		cancelled.advance_scan()
	var running: Thread = cancelled._worker
	var cancel_started := Time.get_ticks_usec()
	cancelled.cancel_scan()
	var cancel_usec := Time.get_ticks_usec() - cancel_started
	_check(running != null and cancelled._retired == running and running.is_alive() and not cancelled.scan_pending(), "Cancelling retires the live verifier without joining it")
	_check(cancel_usec < 50000, "Cancelling returns at once (%d us)" % cancel_usec)
	cancelled.begin_scan()
	var overlap := false
	while cancelled.scan_pending() and steps < 6000:
		cancelled.advance_scan()
		if cancelled._worker != null and cancelled._retired != null: overlap = true
		steps += 1
		await process_frame
	_check(not overlap and cancelled._retired == null and not cancelled.scan_pending() and cancelled.items().size() == changed.items().size(), "A new scan waits for the retired verifier, then completes with every row")
	var empty_paths := {}
	for chapter: String in Registry.keys(): empty_paths[chapter] = "user://solo-replay-collection-missing/" + chapter.validate_filename() + ".json"
	empty_paths["sleeping-lighthouse@1"] = "user://solo-replay-collection-missing/lighthouse.json"
	var empty := Collection.new(empty_paths)
	_check(empty.begin_scan() and not empty.scan_pending() and empty.items().is_empty(), "With no saved source the scan is finished as soon as it begins")
	_check(FileAccess.get_file_as_bytes(path) == before and FileAccess.get_file_as_bytes(archive_path) == archive_before, "Remembered, repeated and cancelled scans never rewrite journal files")

func _fixture(name: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))
	return value if value is Dictionary else {}

func _cleanup() -> void:
	for candidate: String in [path, path + ".tmp", path + ".backup", lighthouse_path, lighthouse_path + ".tmp", lighthouse_path + ".backup"]:
		if FileAccess.file_exists(candidate): DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
	var directory := DirAccess.open(path.get_base_dir())
	if directory == null: return
	var prefix := path.get_file() + ".attempt-"
	for filename: String in directory.get_files():
		if filename.begins_with(prefix) and filename.ends_with(".json"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path.get_base_dir().path_join(filename)))

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)

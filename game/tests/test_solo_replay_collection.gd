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
var verified := path + ".verified.json"

class CountingRelay extends "res://services/relay_journey.gd":
	static var calls := 0
	func _validate_state(value: Variant) -> Dictionary:
		calls += 1
		return super(value)

class CountingLight extends "res://services/lighthouse_journey.gd":
	static var calls := 0
	func _validate_state(value: Variant) -> Dictionary:
		calls += 1
		return super(value)

## Counts native replay checks so a test can prove trusted bytes skip them.
class Counting extends "res://services/solo_replay_collection.gd":
	func _validator(job: Dictionary) -> RefCounted:
		return CountingLight.new(str(job.path)) if job.kind == "lighthouse" else CountingRelay.new(str(job.path), null, str(job.chapter))

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
	var service := Collection.new({Registry.RELAY: path, "sleeping-lighthouse@1": lighthouse_path}, verified)
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
	await _persisted_trust(archive_path)
	var paths: Dictionary = Collection.new()._paths
	_check(paths.size() == Registry.keys().size() + 1 and paths.has("sleeping-lighthouse@1"), "The default collection covers every registered chapter plus Lighthouse")
	_cleanup()
	print("Solo replay collection: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _memo_and_cancel(rows: Array[Dictionary], before: PackedByteArray, archive_path: String, archive_before: PackedByteArray) -> void:
	# Unchanged bytes reuse the earlier native check, so a new screen instance
	# (after a chapter scene) lists them without starting a verifier.
	var again := Collection.new({Registry.RELAY: path, "sleeping-lighthouse@1": lighthouse_path}, verified)
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
	var changed := Collection.new({Registry.RELAY: path, "sleeping-lighthouse@1": lighthouse_path}, verified)
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
	var cancelled := Collection.new({Registry.RELAY: path, "sleeping-lighthouse@1": lighthouse_path}, "")
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
	var empty := Collection.new(empty_paths, "")
	_check(empty.begin_scan() and not empty.scan_pending() and empty.items().is_empty(), "With no saved source the scan is finished as soon as it begins")
	_check(FileAccess.get_file_as_bytes(path) == before and FileAccess.get_file_as_bytes(archive_path) == archive_before, "Remembered, repeated and cancelled scans never rewrite journal files")

func _persisted_trust(archive_path: String) -> void:
	var paths := {Registry.RELAY: path, "sleeping-lighthouse@1": lighthouse_path}
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(verified))
	_check(saved is Dictionary and saved.get("stamp") == Collection._verifier_stamp() and saved.get("keys", []).size() >= 3, "Successful checks are recorded in their own versioned file")
	var hashes := _journal_hashes(archive_path)
	# A new launch: no in-process memo, only the recorded digests.
	Collection._verified.clear()
	CountingRelay.calls = 0
	CountingLight.calls = 0
	var cold := Counting.new(paths, verified)
	await _drain(cold)
	var trusted_rows := cold.items()
	_check(not trusted_rows.is_empty() and CountingRelay.calls == 0 and CountingLight.calls == 0, "A cold start lists unchanged sources without replaying them again")
	Collection._verified.clear()
	var full := Counting.new(paths, "")
	await _drain(full)
	_check(CountingRelay.calls > 0 and CountingLight.calls > 0 and Canonical.same(full.items(), trusted_rows), "Rows from recorded checks equal a full native check")
	# Changed bytes are replayed again; unchanged ones are not.
	var light: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(lighthouse_path))
	light.generation = int(light.generation) + 1
	_write(lighthouse_path, light)
	hashes = _journal_hashes(archive_path)
	Collection._verified.clear()
	CountingRelay.calls = 0
	CountingLight.calls = 0
	await _drain(Counting.new(paths, verified))
	_check(CountingLight.calls > 0 and CountingRelay.calls == 0, "Only the changed source is replayed again")
	await _per_chapter_trust(paths, trusted_rows)
	# A different verifier stamp, or a damaged file, grants no trust.
	var stamped: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(verified))
	stamped.stamp = "0|another verifier"
	_write(verified, stamped)
	Collection._verified.clear()
	CountingRelay.calls = 0
	var bumped := Counting.new(paths, verified)
	_check(bumped._trusted.is_empty(), "A verifier version change invalidates every recorded check")
	await _drain(bumped)
	_check(CountingRelay.calls > 0 and Canonical.same(bumped.items(), trusted_rows), "Sources are replayed again after a version change")
	var damaged := FileAccess.open(verified, FileAccess.WRITE)
	damaged.store_string("{not json")
	damaged.close()
	Collection._verified.clear()
	CountingRelay.calls = 0
	var corrupt := Counting.new(paths, verified)
	_check(corrupt._trusted.is_empty(), "A damaged record file is ignored")
	await _drain(corrupt)
	var rebuilt: Variant = JSON.parse_string(FileAccess.get_file_as_string(verified))
	_check(CountingRelay.calls > 0 and not corrupt.items().is_empty() and rebuilt is Dictionary and rebuilt.get("keys", []).size() >= 3, "A damaged record file is rebuilt from fresh checks")
	# A failed check is never recorded as trusted.
	var bad_path := path + ".bad.json"
	var bad_verified := path + ".bad-verified.json"
	var level := Registry.definition(Registry.RELAY)
	var tampered := _fixture("relay-b")
	tampered.final_state_hash = "0".repeat(64)
	var envelope := Save.defaults()
	envelope.generation = 1
	envelope["relay"] = {"schema_version": level.schema_version, "simulation_version": 2, "level_id": level.id, "level_version": level.version, "definition_hash": Canonical.digest(level), "pairs": [{"a": _fixture("relay-a"), "b": tampered}], "a": {}, "draft": {}}
	_write(bad_path, envelope)
	var failing := Counting.new({Registry.RELAY: bad_path, "sleeping-lighthouse@1": lighthouse_path + ".none"}, bad_verified)
	await _drain(failing)
	var recorded: Variant = JSON.parse_string(FileAccess.get_file_as_string(bad_verified)) if FileAccess.file_exists(bad_verified) else {}
	_check(failing.items().is_empty() and not failing.last_error.is_empty() and recorded.get("keys", []).is_empty(), "A failed check is never recorded as trusted")
	_check(_journal_hashes(archive_path) == hashes, "Recorded checks never rewrite a journal or archive")
	for candidate: String in [bad_path, bad_verified, bad_verified + ".tmp", bad_verified + ".backup"]:
		if FileAccess.file_exists(candidate): DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))

func _per_chapter_trust(paths: Dictionary, trusted_rows: Array[Dictionary]) -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(verified))
	_check(saved.get("schema_version") == 2 and saved.size() == 4 and saved.get("chapters") is Dictionary, "Recorded checks name the chapter whose rules made them")
	_check(saved.get("stamp") == "%d|%s" % [Collection.VERIFIER_VERSION, Engine.get_version_info().string], "The shared stamp holds only the verifier and engine, never the chapter list")
	var owners := {}
	for entry: Array in saved.keys: owners[entry[1]] = int(owners.get(entry[1], 0)) + 1
	_check(owners.has(Registry.RELAY) and owners.has("sleeping-lighthouse@1"), "Each chapter's checks are filed under that chapter")
	var digests: Array = []
	for entry: Array in saved.keys: digests.append(entry[0])
	# A build with fewer chapters wrote this file. Adding a registry key leaves
	# every other chapter's recorded checks in place: nothing is replayed.
	var older := saved.duplicate(true)
	older.chapters["retired-chapter@1"] = "[6, 8]"
	_write(verified, older)
	Collection._verified.clear()
	CountingRelay.calls = 0
	CountingLight.calls = 0
	var grown := Counting.new(paths, verified)
	_check(grown._trusted.size() == digests.size(), "Loading checks recorded before a chapter was added keeps all of them")
	await _drain(grown)
	_check(CountingRelay.calls == 0 and CountingLight.calls == 0 and Canonical.same(grown.items(), trusted_rows), "Adding a chapter never replays another chapter's recorded checks")
	# Only the chapter whose rules changed is checked again.
	var changed_rules := saved.duplicate(true)
	changed_rules.chapters[Registry.RELAY] = "[2]"
	_write(verified, changed_rules)
	Collection._verified.clear()
	CountingRelay.calls = 0
	CountingLight.calls = 0
	var relay_changed := Counting.new(paths, verified)
	var kept_light := true
	for key: String in relay_changed._trusted: kept_light = kept_light and relay_changed._trusted[key] == "sleeping-lighthouse@1"
	_check(relay_changed._trusted.size() == int(owners["sleeping-lighthouse@1"]) and kept_light, "Changed rules drop only that chapter's recorded checks")
	await _drain(relay_changed)
	_check(CountingRelay.calls > 0 and CountingLight.calls == 0, "Only the chapter with changed rules is replayed again")
	# A 0.5.x file stamped the whole registry at once. Written out literally so
	# the migration is checked against the old format, not against itself.
	var legacy_stamp := "1|%s|lighthouse:3|first-steps@1:[4, 5, 8]|relay-isles@2:[2, 8]|high-and-low@1:[6, 8]|rolling-home@1:[6, 8]|a-house-for-two@1:[6, 8]|conservatory@1:[7, 8]|long-way-home@1:[7, 8]" % Engine.get_version_info().string
	_check(Collection._legacy_stamp() == legacy_stamp, "The 0.5.x whole-registry stamp is recognised exactly")
	_write(verified, {"schema_version": 1, "stamp": legacy_stamp, "keys": digests})
	Collection._verified.clear()
	CountingRelay.calls = 0
	CountingLight.calls = 0
	var migrated := Counting.new(paths, verified)
	_check(migrated._trusted.size() == digests.size(), "Checks recorded by 0.5.x stay trusted after the update")
	await _drain(migrated)
	var rewritten: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(verified))
	var filed: bool = rewritten.get("schema_version") == 2
	var groups := {}
	for entry: Variant in rewritten.get("keys", []):
		filed = filed and entry is Array and entry[1] in [Registry.RELAY, "sleeping-lighthouse@1", Collection.LEGACY_GROUP]
		if entry is Array: groups[entry[1]] = true
	# Digests of bytes no longer on disk are never hit again; they keep their 0.5.x group.
	filed = filed and groups.has(Registry.RELAY) and groups.has("sleeping-lighthouse@1") and rewritten.keys.size() == digests.size()
	_check(CountingRelay.calls == 0 and CountingLight.calls == 0 and Canonical.same(migrated.items(), trusted_rows) and filed, "Migrated 0.5.x checks are not replayed and are refiled per chapter")
	_write(verified, {"schema_version": 1, "stamp": legacy_stamp.replace("relay-isles@2:[2, 8]", "relay-isles@2:[2]"), "keys": digests})
	_check(Counting.new(paths, verified)._trusted.is_empty(), "A 0.5.x file stamped under other rules grants no trust")
	_write(verified, saved)

func _drain(service: RefCounted) -> void:
	service.begin_scan()
	var deadline := Time.get_ticks_msec() + 20000
	while service.scan_pending() and Time.get_ticks_msec() < deadline:
		service.advance_scan()
		await process_frame

func _journal_hashes(archive_path: String) -> Array:
	return [FileAccess.get_sha256(path), FileAccess.get_sha256(lighthouse_path), FileAccess.get_sha256(archive_path)]

func _write(target: String, value: Dictionary) -> void:
	var file := FileAccess.open(target, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func _fixture(name: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))
	return value if value is Dictionary else {}

func _cleanup() -> void:
	for candidate: String in [path, path + ".tmp", path + ".backup", lighthouse_path, lighthouse_path + ".tmp", lighthouse_path + ".backup", verified, verified + ".tmp", verified + ".backup"]:
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

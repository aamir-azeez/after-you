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
	var service := Collection.new({Registry.RELAY: path, "sleeping-lighthouse@1": lighthouse_path})
	_check(service.begin_scan(), "Read-only solo discovery starts")
	var deadline := Time.get_ticks_msec() + 15000
	while service.scan_pending() and Time.get_ticks_msec() < deadline:
		service.advance_scan()
		await process_frame
	var rows := service.items()
	_check(not service.scan_pending() and rows.size() == 4, "Current, archived and Lighthouse accepted pairs are discoverable")
	var relay_rows: Array[Dictionary] = rows.filter(func(row: Dictionary) -> bool: return row.get("chapter_key") == Registry.RELAY)
	_check(relay_rows.size() == 2 and relay_rows.all(func(row: Dictionary) -> bool: return row.get("stage_id") == "relay" and row.get("pair", {}).get("a", {}).get("role") == "a" and row.get("pair", {}).get("b", {}).get("role") == "b"), "Draft and unpaired turns stay out of solo replay rows")
	_check(rows.any(func(row: Dictionary) -> bool: return row.get("archived", false)) and rows.any(func(row: Dictionary) -> bool: return not row.get("archived", true)), "Current and immutable archive rows retain separate identities")
	_check(rows.filter(func(row: Dictionary) -> bool: return row.get("chapter_key") == "sleeping-lighthouse@1").map(func(row: Dictionary) -> String: return row.get("stage_id", "")) == ["borrowed-light", "missing-piece"], "Lighthouse accepted pairs map to their authored stage keys")
	_check(FileAccess.get_file_as_bytes(path) == before and FileAccess.get_file_as_bytes(archive_path) == archive_before, "Scanning does not repair or rewrite gameplay journal files")
	_check(service.last_error.is_empty(), "Valid current and archive snapshots pass native replay validation")
	var paths: Dictionary = Collection.new()._paths
	_check(paths.size() == Registry.keys().size() + 1 and paths.has("sleeping-lighthouse@1"), "The default collection covers every registered chapter plus Lighthouse")
	_cleanup()
	print("Solo replay collection: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

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

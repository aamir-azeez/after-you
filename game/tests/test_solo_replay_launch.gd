extends SceneTree
## End-to-end proof that a discovered solo replay actually plays.
## Seeds a real accepted journal pair, discovers it, builds the launch context
## with the production code path, then confirms the preview scene consumes that
## context and begins replay playback without altering the saved journal.

const Collection = preload("res://services/solo_replay_collection.gd")
const Journey = preload("res://services/relay_journey.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Main = preload("res://main.gd")
const Preview = preload("res://relay_preview.gd")
const Canonical = preload("res://core/v2/canonical.gd")

const CONTEXT_PATH := "user://solo-replay-playback.json"

var checks := 0
var failures := 0
var path := "user://solo-replay-launch-%d.json" % Time.get_ticks_usec()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# A real accepted relay pair, written exactly as live play would store it.
	var journey := Journey.new(path, null, Registry.RELAY)
	journey.load_data()
	journey._state.simulation_version = 2
	_check(journey.accept_recording(_fixture("relay-a")) and journey.accept_recording(_fixture("relay-b")), "A valid accepted pair is written to the solo journal")
	var journal_before := FileAccess.get_file_as_bytes(path)

	# Discover it through the read-only collection the library uses.
	var service := Collection.new({Registry.RELAY: path})
	_check(service.begin_scan(), "Read-only solo discovery starts")
	var deadline := Time.get_ticks_msec() + 15000
	while service.scan_pending() and Time.get_ticks_msec() < deadline:
		service.advance_scan()
		await process_frame
	var rows: Array = service.items().filter(func(row: Dictionary) -> bool: return row.get("chapter_key") == Registry.RELAY)
	_check(rows.size() == 1 and int(rows[0].get("stage_index", -1)) == 0, "The accepted relay turn is discovered as a playable part")

	# Build the launch context with the production builder and reject bad input.
	var selected: Dictionary = rows[0]
	var context: Dictionary = Main._solo_replay_context_from_rows(Registry.RELAY, rows, selected)
	_check(context.get("schema_version") == 1 and context.get("chapter_key") == Registry.RELAY and context.get("selected_stage_index") == 0 and context.get("accepted_pairs", []).size() == 1, "The builder produces the accepted prefix for the selected part")
	var mismatched: Dictionary = selected.duplicate(true)
	mismatched["id"] = "not-the-real-id"
	_check(Main._solo_replay_context_from_rows(Registry.RELAY, rows, mismatched).is_empty(), "A row whose identity does not match the selection is refused")

	# Write the context the preview will read, exactly as the launch does.
	_check(Main._write_solo_replay_context(context) and FileAccess.file_exists(CONTEXT_PATH), "The launch writes the replay context file for the chapter scene")

	# The preview scene must consume the context and start replay playback.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var preview := Preview.new()
	preview.journey = Journey.new(path, null, Registry.RELAY)
	preview.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	viewport.add_child(preview)
	preview.set_physics_process(false)
	preview.set_process(false)
	await process_frame
	await process_frame
	_check(preview._solo_replay_only and not FileAccess.file_exists(CONTEXT_PATH), "Opening the chapter consumes the replay context exactly once")
	_check(preview.mode == "replay" and preview.running and preview.replay_pair_index == 0, "Solo replay playback actually starts in the chapter scene")
	_check(preview._pairs().size() == 1, "Playback draws only the injected accepted pair, never the live journal")
	_check(FileAccess.get_file_as_bytes(path) == journal_before, "Starting solo playback leaves the saved journal bytes unchanged")

	viewport.queue_free()
	await process_frame
	_cleanup()
	print("Solo replay launch: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _fixture(name: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))
	return value if value is Dictionary else {}

func _cleanup() -> void:
	for candidate: String in [path, path + ".tmp", path + ".backup", CONTEXT_PATH, CONTEXT_PATH + ".tmp"]:
		if FileAccess.file_exists(candidate): DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)

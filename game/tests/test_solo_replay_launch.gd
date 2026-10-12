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
const LighthouseJourney = preload("res://services/lighthouse_journey.gd")
const LighthousePreview = preload("res://lighthouse_preview.gd")

const CONTEXT_PATH := "user://solo-replay-playback.json"

var checks := 0
var failures := 0
var path := "user://solo-replay-launch-%d.json" % Time.get_ticks_usec()
var lighthouse_path := "user://solo-replay-launch-lighthouse-%d.json" % Time.get_ticks_usec()

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
	await _lighthouse()
	_cleanup()
	print("Solo replay launch: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The solo Lighthouse sits outside the chapter registry. Its discovered parts
## must still build a launch context that its own scene consumes and plays.
func _lighthouse() -> void:
	var pair: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/borrowed-light-v3.json"))
	if not pair is Dictionary:
		_check(false, "The frozen Lighthouse pair parses")
		return
	var journal := LighthouseJourney.new(lighthouse_path)
	journal.load_data()
	_check(journal.accept_recording(pair.a) and journal.accept_recording(pair.b), "A real Lighthouse pair is written to its solo journal")
	var journal_before := FileAccess.get_file_as_bytes(lighthouse_path)

	var service := Collection.new({Collection.LIGHTHOUSE_KEY: lighthouse_path})
	_check(service.begin_scan(), "Read-only solo discovery starts for the Lighthouse")
	var deadline := Time.get_ticks_msec() + 30000
	while service.scan_pending() and Time.get_ticks_msec() < deadline:
		service.advance_scan()
		await process_frame
	var rows: Array = service.items().filter(func(row: Dictionary) -> bool: return row.get("chapter_key") == Collection.LIGHTHOUSE_KEY)
	_check(rows.size() == 1 and int(rows[0].get("stage_index", -1)) == 0, "The accepted Lighthouse pair is discovered as a playable part")
	if rows.is_empty(): return

	var context: Dictionary = Main._solo_replay_context_from_rows(Collection.LIGHTHOUSE_KEY, rows, rows[0])
	_check(context.get("chapter_key") == Collection.LIGHTHOUSE_KEY and context.get("selected_stage_index") == 0 and context.get("accepted_pairs", []).size() == 1, "The builder makes a Lighthouse context although the chapter is outside the registry")
	var stray: Dictionary = rows[0].duplicate(true)
	stray["id"] = "not-the-real-id"
	_check(Main._solo_replay_context_from_rows(Collection.LIGHTHOUSE_KEY, rows, stray).is_empty(), "A Lighthouse row whose identity does not match is refused")
	_check(Main._solo_replay_context_from_rows("not-a-chapter@1", rows, rows[0]).is_empty(), "Other chapters outside the registry still build nothing")
	var scene: Variant = load(Main.LIGHTHOUSE_SCENE)
	var opened: Node = (scene as PackedScene).instantiate() if scene is PackedScene else null
	_check(opened != null and opened.get_script() == LighthousePreview, "The launch opens the Lighthouse scene")
	if opened != null: opened.free()
	_check(Main._write_solo_replay_context(context) and FileAccess.file_exists(CONTEXT_PATH), "The launch writes the Lighthouse replay context")

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var preview := LighthousePreview.new()
	preview.journey = LighthouseJourney.new(lighthouse_path)
	preview.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	viewport.add_child(preview)
	preview.set_physics_process(false)
	preview.set_process(false)
	await process_frame
	await process_frame
	_check(preview._solo_replay_only and not FileAccess.file_exists(CONTEXT_PATH), "Opening the Lighthouse consumes its replay context exactly once")
	_check(preview.mode == "replay" and preview.running and preview.collection_index == 0, "Lighthouse solo replay playback actually starts")
	_check(FileAccess.get_file_as_bytes(lighthouse_path) == journal_before, "Starting Lighthouse playback leaves its journal bytes unchanged")
	viewport.queue_free()
	await process_frame

func _fixture(name: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))
	return value if value is Dictionary else {}

func _cleanup() -> void:
	for candidate: String in [path, path + ".tmp", path + ".backup", lighthouse_path, lighthouse_path + ".tmp", lighthouse_path + ".backup", CONTEXT_PATH, CONTEXT_PATH + ".tmp"]:
		if FileAccess.file_exists(candidate): DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)

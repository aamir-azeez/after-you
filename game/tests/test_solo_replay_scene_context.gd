extends SceneTree

const RelayScene = preload("res://relay_preview.gd")
const LighthouseScene = preload("res://lighthouse_preview.gd")
const RelayJourney = preload("res://services/relay_journey.gd")
const RelayRegistry = preload("res://services/chapter_registry.gd")
const RelaySimulation = preload("res://core/v2/simulation_v2.gd")
const LighthouseSimulation = preload("res://core/lighthouse/borrowed_light.gd")

var checks := 0
var failures := 0
var relay_context_path := "user://solo-replay-context-relay-%d.json" % Time.get_ticks_usec()
var lighthouse_context_path := "user://solo-replay-context-lighthouse-%d.json" % Time.get_ticks_usec()
var journal_path := "user://solo-replay-context-journal-%d.json" % Time.get_ticks_usec()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var relay_a := _fixture("res://tests/fixtures/v2/relay-a.json")
	var relay_b := _fixture("res://tests/fixtures/v2/relay-b.json")
	var relay_pair := {"a": relay_a, "b": relay_b}
	var relay_value := _context(RelayRegistry.RELAY, 0, [relay_pair], "relay:attempt:0")
	_write_json(relay_context_path, relay_value)
	var relay_journey := RelayJourney.new(journal_path, null, RelayRegistry.RELAY)
	relay_journey.load_data()
	relay_journey._state.simulation_version = 2
	_check(relay_journey.accept_recording(relay_a) and relay_journey.accept_recording(relay_b), "A verified accepted relay pair can back the playback context")
	var journal_before := FileAccess.get_file_as_bytes(journal_path)
	var relay_result: Dictionary = RelayScene.consume_solo_replay_context(relay_context_path, RelayRegistry.RELAY, RelayRegistry.definition(RelayRegistry.RELAY), RelaySimulation)
	_check(relay_result.get("status") == "consumed" and not FileAccess.file_exists(relay_context_path), "A valid relay playback context is safely parsed then consumed")
	_check(relay_result.get("context", {}).get("selected_stage_index") == 0 and relay_result.get("context", {}).get("accepted_pairs", []).size() == 1, "Relay playback retains the accepted prefix and selected stage")
	_check(FileAccess.get_file_as_bytes(journal_path) == journal_before, "Consuming the relay replay context leaves the gameplay journal unchanged")

	var lighthouse_fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/first-two-v3.json"))
	var lighthouse_pairs: Array = lighthouse_fixture.get("pairs", []) if lighthouse_fixture is Dictionary else []
	var lighthouse_value := _context("sleeping-lighthouse@1", lighthouse_pairs.size() - 1, lighthouse_pairs, "lighthouse:attempt:0")
	_write_json(lighthouse_context_path, lighthouse_value)
	var lighthouse_result: Dictionary = LighthouseScene.consume_solo_replay_context(lighthouse_context_path)
	_check(lighthouse_result.get("status") == "consumed" and not FileAccess.file_exists(lighthouse_context_path), "A valid Lighthouse playback context is safely parsed then consumed")
	_check(lighthouse_result.get("context", {}).get("accepted_pairs", []).size() == 2, "Lighthouse playback preserves all prior accepted stages for checkpoint reconstruction")
	_check(LighthouseSimulation.checkpoint_from_pairs(lighthouse_pairs).get("valid", false), "The Lighthouse playback prefix is independently replay-verified")

	var invalid_path := relay_context_path + ".invalid"
	_write_json(invalid_path, _context(RelayRegistry.RELAY, 1, [relay_pair], "relay:bad-prefix"))
	var invalid_result: Dictionary = RelayScene.consume_solo_replay_context(invalid_path, RelayRegistry.RELAY, RelayRegistry.definition(RelayRegistry.RELAY), RelaySimulation)
	_check(invalid_result.get("status") == "error" and FileAccess.file_exists(invalid_path), "Invalid or incomplete prefixes fail closed and are not consumed")

	_cleanup()
	print("Solo replay scene context: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _context(chapter_key: String, stage_index: int, pairs: Array, visibility_key: String) -> Dictionary:
	return {"schema_version": 1, "chapter_key": chapter_key, "selected_stage_index": stage_index,
		"accepted_pairs": pairs.duplicate(true), "visibility_key": visibility_key}

func _fixture(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func _cleanup() -> void:
	for path: String in [relay_context_path, lighthouse_context_path, journal_path, journal_path + ".tmp", journal_path + ".backup", relay_context_path + ".invalid"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)

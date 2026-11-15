extends SceneTree
## Every other physical chapter's developer run (content/dev_ghosts.json),
## its first stage played again packed (tests/packed_run_check.gd): the same
## runs, turn b's positions every tick, the stage's checkpoint made from the
## packed turns and the checks matching the JSON run's state hashes by prefix.
## test_recording_codec.gd plays one whole board with every check.
const PackedRun = preload("res://tests/packed_run_check.gd")
const FULL_BOARD := preload("res://tests/test_recording_codec.gd").FULL_BOARD

var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(message)

func _run() -> void:
	var played := 0
	for row: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://content/dev_ghosts.json")).ghosts:
		if row.board != FULL_BOARD and PackedRun.run(row, _check, false): played += 1
	_check(played >= 9, "every other physical chapter's run plays again packed: %d boards" % played)
	print("AFTER YOU RECORDING CODEC RUNS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

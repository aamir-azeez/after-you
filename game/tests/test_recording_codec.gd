extends SceneTree
## Packed recordings (core/v2/recording_codec.gd): the bytes the server's codec
## writes too, the one canonical encoding, and one whole run played again
## packed with every check (tests/packed_run_check.gd). The other chapters' runs
## are in test_recording_codec_runs.gd. Synthetic ids only.
const Codec = preload("res://core/v2/recording_codec.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const PackedRun = preload("res://tests/packed_run_check.gd")
## The board that gets every check: short, two stages, a physical chapter.
const FULL_BOARD := "high-and-low@1"

var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(message)

func _run() -> void:
	_golden()
	_canonical_only()
	var ghosts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/whole_runs.json")).ghosts
	var row: Array = ghosts.filter(func(item: Dictionary) -> bool: return item.board == FULL_BOARD)
	_check(row.size() == 1 and PackedRun.run(row[0], _check, true), "%s plays again packed" % FULL_BOARD)
	print("AFTER YOU RECORDING CODEC: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _golden() -> void:
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/packed-recording-golden.json"))
	for item: Dictionary in golden.cases:
		var duration := int(item.duration)
		var text := Codec.pack(item.actions, item.checks, duration)
		_check(text == item.packed, "a %d tick turn packs to the server's bytes" % duration)
		var back := Codec.unpack(text, duration, str(item.final), duration)
		_check(Canonical.same(back.get("actions"), item.actions), "a %d tick turn's runs come back exactly" % duration)
		var listed: Array = back.get("replay_checks", [])
		_check(listed.size() == item.checks.size(), "a %d tick turn keeps a check every second and at the end" % duration)
		for index in range(listed.size()):
			var tick := int(listed[index].tick)
			var size := 0 if tick == duration else (64 if tick % 150 == 0 else 16)
			_check(tick == int(item.checks[index].tick) and (str(listed[index].state_hash) == str(item.checks[index].state_hash) if size == 0 else str(listed[index].state_hash).length() == size) and Codec.check_matches(listed[index].state_hash, str(item.checks[index].state_hash)), "check %d of a %d tick turn" % [tick, duration])
		_check(Codec.pack(back.actions, listed, duration) == text, "a %d tick turn packs the same from its short checks" % duration)

func _canonical_only() -> void:
	var runs := [{"ticks": 40, "x": 0, "z": 100, "action": false}, {"ticks": 1, "x": -100, "z": -7, "action": true}, {"ticks": 200, "x": 55, "z": 0, "action": false}]
	var listed: Array = []
	for tick: int in Codec.check_ticks(241): listed.append({"tick": tick, "state_hash": "ab".repeat(32)})
	var good := Marshalls.base64_to_raw(Codec.pack(runs, listed, 241))
	_check(not Codec.unpack(Marshalls.raw_to_base64(good), 241, "f".repeat(64), 3).is_empty(), "the good form reads")
	var bad := {"trailing": good + PackedByteArray([0]), "short": good.slice(0, good.size() - 1), "format": PackedByteArray([2]) + good.slice(1),
		"long varint": PackedByteArray([good[0], 0x83, 0x00]) + good.slice(2)}
	var wide := good.duplicate()
	wide[3] = 101
	bad["wide stick"] = wide
	for name: String in bad: _check(Codec.unpack(Marshalls.raw_to_base64(bad[name]), 241, "f".repeat(64), 3).is_empty(), "refused: %s" % name)
	var split := [{"ticks": 20, "x": 0, "z": 100, "action": false}, {"ticks": 20, "x": 0, "z": 100, "action": false}, runs[1], runs[2]]
	_check(Codec.unpack(Codec.pack(split, listed, 241), 241, "f".repeat(64), 4).is_empty(), "refused: two equal runs in a row")
	_check(Codec.unpack(Codec.pack(runs, listed, 241), 241, "f".repeat(64), 2).is_empty(), "refused: more runs than the turn allows")
	_check(Codec.unpack(Codec.pack(runs, listed, 241) + " ", 241, "f".repeat(64), 3).is_empty(), "refused: base64 that is not canonical")
	_check(Codec.pack(runs, listed.slice(1), 241).is_empty(), "checks off the implied ticks do not pack")


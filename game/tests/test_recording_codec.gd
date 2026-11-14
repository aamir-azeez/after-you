extends SceneTree
## Packed recordings (core/v2/recording_codec.gd): the bytes the server's codec
## writes too, the one canonical encoding, and every physical chapter's real
## runs (content/dev_ghosts.json) played again packed: the same runs, frames
## and positions, checks that are the first bytes of the same state hashes, a
## record each engine verifies, and the same bytes on every export. Synthetic ids only.
const Codec = preload("res://core/v2/recording_codec.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Track = preload("res://services/race_ghost_track.gd")
const TheirRun = preload("res://services/duel_their_run.gd")

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
	var ghosts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://content/dev_ghosts.json")).ghosts
	var played := 0
	for row: Dictionary in ghosts:
		if _runs_again(row): played += 1
	_check(played >= 8, "every physical chapter's run plays again packed: %d boards" % played)
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

## Every turn of a board's run played again packed. False for a family that never records packed.
func _runs_again(row: Dictionary) -> bool:
	var key := str(row.board)
	if not "packed_recordings" in Registry.simulation_script(key).new(): return false
	var parts := TheirRun.parts({"digest": row.proof_hash, "byte_length": int(row.byte_length), "body": row.body}, key)
	_check(not parts.is_empty(), "%s decodes" % key)
	var level := Registry.definition(key)
	var engine: Script = Registry.simulation_script(key)
	var before := 0
	var after := 0
	for part: Dictionary in parts:
		var pair: Dictionary = part.pair
		var where := "%s stage %d" % [key, int(pair.stage_index)]
		var start := Registry.previous_checkpoint(key, pair.checkpoint)
		_check(Canonical.same(_play(key, level, pair.a, start, {}, false), pair.a), "%s: the JSON turn a plays back exactly" % where)
		var a := _play(key, level, pair.a, start, {}, true)
		var b := _play(key, level, pair.b, start, a, true)
		_check(Codec.is_packed(a) and Codec.is_packed(b) and not a.has("actions") and not b.has("replay_checks"), "%s: both turns export packed" % where)
		_check(Canonical.same(_play(key, level, pair.a, start, {}, true), a), "%s: a packed export is the same every time" % where)
		_check(Canonical.same(Codec.actions(a), pair.a.actions) and Canonical.same(Codec.actions(b), pair.b.actions), "%s: the same runs" % where)
		_check(a.final_state_hash == pair.a.final_state_hash, "%s: turn a ends on the same state" % where)
		var full: Dictionary = {}
		for check: Dictionary in pair.a.replay_checks: full[int(check.tick)] = str(check.state_hash)
		var prefixes := true
		for check: Dictionary in Codec.checks(a): prefixes = prefixes and Codec.check_matches(check.state_hash, str(full.get(int(check.tick), "")))
		_check(prefixes, "%s: turn a's checks are the first bytes of the same state hashes" % where)
		_check(engine.verify_recording(level, a, start).valid, "%s: packed turn a verifies" % where)
		_check(engine.verify_recording(level, b, start, a).valid, "%s: packed turn b verifies after it" % where)
		var packed_pair := {"stage_index": pair.stage_index, "a": a, "b": b, "checkpoint": pair.checkpoint}
		for role: String in ["a", "b"]:
			var track := Track.build(key, packed_pair, role)
			var plain_track := Track.build(key, pair, role)
			_check(not track.is_empty() and track.points == plain_track.points, "%s turn %s: the same positions every tick" % [where, role])
		var off := packed_pair.duplicate(true)
		var bytes := Marshalls.base64_to_raw(off.a.packed)
		if Codec.checks(a).size() > 1:
			bytes[bytes.size() - 1] ^= 1
			off.a.packed = Marshalls.raw_to_base64(bytes)
			_check(Track.build(key, off, "a").is_empty(), "%s: a check that does not match gives no ghost" % where)
		for record: Dictionary in [pair.a, pair.b]: before += _deflated(record)
		for record: Dictionary in [a, b]: after += _deflated(record)
	print("%s: %d turns, deflated %d bytes as JSON, %d packed" % [key, parts.size() * 2, before, after])
	return true

func _play(key: String, level: Dictionary, record: Dictionary, start: Dictionary, prior: Dictionary, packed: bool) -> Dictionary:
	var sim: RefCounted = Registry.simulation_script(key).new()
	if not Registry.reset_simulation(sim, key, level, str(record.stage_id), start, prior, str(record.role), record): return {}
	sim.packed_recordings = packed
	sim.catch_assistance = bool(record.get("catch_assistance", false))
	for input: Dictionary in Registry.simulation_script(key).expand_recording_inputs(record):
		if bool(sim.get("finished")): break
		sim.step(input)
	return sim.export_recording()

func _deflated(record: Dictionary) -> int:
	return JSON.stringify(Canonical.normalized(record)).to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE).size()

extends SceneTree
## The developers' ghost runs (content/dev_ghosts.json, made by
## tests/dev_ghost_recorder.gd) that duels' ghost races time. Every chapter a
## duel can be played on has one; each is a whole run with Forgiving catches off
## on every turn, at the rules a new room plays, that passes the leaderboard
## replay check from its blob body with exactly its stored time; and recording
## it again gives the same bytes (checked on the Relay Isles, whose receivers
## press for their catches).
##
## With AFTERYOU_WRITE_DEV_GHOSTS=1 in the environment it records every ghost
## and writes the manifest first (the isolated runner passes the environment on,
## not user args), then checks what it wrote.
const Recorder = preload("res://tests/dev_ghost_recorder.gd")
const Check = preload("res://tests/leaderboard_replay_check.gd")
const Registry = preload("res://services/chapter_registry.gd")
const BlobCodec = preload("res://services/blob_codec.gd")
const Typed = preload("res://services/typed_values.gd")
## The chapter recorded again on every run.
const REPRODUCED := Registry.RELAY

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)

func _run() -> void:
	if OS.get_environment("AFTERYOU_WRITE_DEV_GHOSTS") == "1": _write()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(Recorder.MANIFEST))
	_check(parsed is Dictionary and Typed.equal(parsed.get("schema_version"), 1) and parsed.get("ghosts") is Array, "The ghost manifest reads")
	var rows: Dictionary = {}
	if parsed is Dictionary and parsed.get("ghosts") is Array:
		for row: Variant in parsed.ghosts:
			if row is Dictionary: rows[str(row.get("board", ""))] = row
	var boards: Array = []
	for key: String in Registry.keys(): boards.append(key)
	var listed := rows.keys()
	listed.sort()
	boards.sort()
	_check(listed == boards, "Every chapter a duel can be played on has exactly one ghost: %s" % [listed])
	for key: String in Registry.keys():
		if rows.has(key): _check_ghost(key, rows[key])
	print("DEV GHOSTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check_ghost(key: String, row: Dictionary) -> void:
	var rules := Registry.preferred_rules(key)
	_check(Typed.equal(row.get("simulation_version"), rules) and Typed.equal(row.get("catch_assistance"), false), "%s: stored at rules %d with Forgiving catches off" % [key, rules])
	# The replay check the leaderboards and duels use: chapter from the bundle, blob decoded against its hash, every turn replayed, no assisted turn, the time measured.
	var entry := row.duplicate()
	var checked := Check.check(JSON.parse_string(JSON.stringify(entry)))
	_check(checked.valid and checked.reason == "" and Typed.equal(row.get("ticks"), checked.measured_ticks), "%s: passes the replay check with its stored time: %s" % [key, checked])
	var bytes := BlobCodec.verified(Marshalls.base64_to_raw(str(row.get("body", ""))), int(row.get("byte_length", 0)), str(row.get("proof_hash", "")), Check.MAX_CHECKPOINT_BYTES)
	_check(not bytes.is_empty(), "%s: the body decodes to the bytes its hash names" % key)
	if bytes.is_empty(): return
	var checkpoint: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not checkpoint is Dictionary: return
	var turns := 0
	var current: Dictionary = checkpoint
	while int(current.get("stage_index", 0)) > 0 and current.get("proof") is Dictionary:
		for role: String in ["a", "b"]:
			var turn: Dictionary = current.proof.get(role, {})
			turns += 1
			_check(Typed.equal(turn.get("catch_assistance"), false), "%s: turn %s of stage %d has Forgiving catches off" % [key, role, int(current.stage_index)])
			_check(Typed.equal(turn.get("simulation_version"), rules), "%s: turn %s of stage %d plays rules %d" % [key, role, int(current.stage_index), rules])
		current = Registry.previous_checkpoint(key, current)
	_check(turns == 2 * Registry.definition(key).stages.size(), "%s: two turns for every stage" % key)
	# The pipeline is deterministic: recording again gives the stored run, byte for byte. One
	# chapter whose receivers press for their catches keeps the recorder honest without
	# replaying every chapter twice.
	if key == REPRODUCED:
		var again := Recorder.record(key)
		_check(again.error.is_empty() and again.presses > 0 and Recorder.manifest_row(key, again).proof_hash == row.get("proof_hash"), "%s: recording again gives the stored run: %s" % [key, again.error])

func _write() -> void:
	var ghosts: Array = []
	for key: String in Registry.keys():
		var recorded := Recorder.record(key)
		_check(recorded.error.is_empty(), "Recorded %s: %s" % [key, recorded.error])
		print("DEV GHOST %s rules %d ticks %d presses %d %s" % [key, recorded.rules, recorded.ticks, recorded.presses, recorded.error])
		if recorded.error.is_empty(): ghosts.append(Recorder.manifest_row(key, recorded))
	var file := FileAccess.open(Recorder.MANIFEST, FileAccess.WRITE)
	_check(file != null, "The manifest is writable")
	if file == null: return
	file.store_string(JSON.stringify({"schema_version": 1, "ghosts": ghosts}, "\t", false) + "\n")
	file.close()
	print("DEV GHOSTS WRITTEN " + Recorder.MANIFEST)

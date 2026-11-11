extends SceneTree
## Playtest report: reads saved turns from a folder of copies and prints, per
## chapter stage, how long each turn took, how many tries it needed, who
## drowned or left a turn unfinished, and where the pips stood still longest.
## Local only: nothing is sent anywhere, and nothing in the folder is written.
##
##   godot --headless --path game --script res://tests/playtest_report.gd -- --input=<folder> [--json=<file>]
##
## Godot writes its own logs under user://, so run it with APPDATA and
## LOCALAPPDATA (XDG_DATA_HOME elsewhere) pointed at a scratch folder, as the
## private isolated suite runner does; never with the real ones.
##
## The folder holds copies, never the game's own save folder (refused): any
## JSON with recordings in it (loose turns, solo journey saves, their archived
## attempts, checkpoints and their proofs), room history folders (index.json
## with its attempt blobs, read through services/history_store.gd and
## services/blob_codec.gd) and a turn-tries.json (services/turn_tries.gd).
## Each cooperative or journey turn is replayed through its own engine from
## the checkpoint it was played from, found among the same files or the
## chapter's first; a turn whose checkpoint is missing reports its time only.
## Lives under tests/ so it never ships in the game.

const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HistoryStore = preload("res://services/history_store.gd")
const TurnTries = preload("res://services/turn_tries.gd")
const StageCatalog = preload("res://core/journey/stage_catalog.gd")
const TICK_RATE := 30.0
## A file larger than this is skipped, not read.
const MAX_FILE_BYTES := 8 * 1024 * 1024
## A still spot within this of a pad, lever, switch or goal is named after it.
const NEAR_CM := 96
## The game's own save folders, refused as input.
const SAVE_FOLDER_MARKS := ["/appdata/roaming/afteryou", "/.local/share/afteryou", "/library/application support/afteryou"]

func _initialize() -> void:
	var input := ""
	var json_out := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="): input = argument.trim_prefix("--input=")
		if argument.begins_with("--json="): json_out = argument.trim_prefix("--json=")
	var refused := refusal(input)
	if refused.is_empty() and not json_out.is_empty(): refused = output_refusal(json_out, input)
	if not refused.is_empty():
		printerr("PLAYTEST REPORT refused: " + refused)
		quit(2)
		return
	var made := report(input)
	print(text(made))
	if not json_out.is_empty():
		var file := FileAccess.open(json_out, FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(made, "\t"))
	quit(0)

## Why `input` may not be read, or "" when it may.
static func refusal(input: String) -> String:
	if input.is_empty(): return "name a folder of copies with --input="
	if not DirAccess.dir_exists_absolute(input): return "no such folder: " + input
	var path := ProjectSettings.globalize_path(input).replace("\\", "/").to_lower()
	var own := ProjectSettings.globalize_path("user://").replace("\\", "/").to_lower().trim_suffix("/")
	if (path + "/").begins_with(own + "/"): return "that is this game's own save folder; copy what you need elsewhere first"
	if (own + "/").begins_with(path.trim_suffix("/") + "/"): return "that folder holds this game's own save folder"
	if _save_folder(path): return "that is the game's save folder; copy what you need elsewhere first"
	return ""

## Why the --json file may not be written there, or "".
static func output_refusal(output: String, input: String) -> String:
	var path := ProjectSettings.globalize_path(output).replace("\\", "/").to_lower()
	var own := ProjectSettings.globalize_path("user://").replace("\\", "/").to_lower().trim_suffix("/")
	if (path + "/").begins_with(own + "/") or _save_folder(path): return "the report is never written into the game's save folder"
	if path.begins_with(ProjectSettings.globalize_path(input).replace("\\", "/").to_lower().trim_suffix("/") + "/"): return "the report is never written into the folder it reads"
	return ""

## True for a path in or under one of the game's save folders.
static func _save_folder(path: String) -> bool:
	var plain := path.replace("\\", "/").to_lower() + "/"
	for mark: String in SAVE_FOLDER_MARKS:
		if plain.contains(mark + "/"): return true
	return false

## {"stages": {"<key> / <stage>": {"a": role, "b": role}}, "turns": n,
## "replayed": n, "notes": [...]}; a role is {"turns", "seconds", "tries",
## "drowned", "closing", "unfinished", "still": {"seconds", "where", "turn"}}.
static func report(input: String) -> Dictionary:
	var found := collect(input)
	var stages: Dictionary = {}
	var replayed := 0
	var notes: Array = found.notes
	var hashes: Array = found.recordings.keys()
	hashes.sort()
	for hash: String in hashes:
		var recording: Dictionary = found.recordings[hash]
		var key := Registry.resolve(recording)
		var name := "%s / %s" % [key if not key.is_empty() else "%s@%s (unknown)" % [recording.level_id, recording.get("level_version", "?")], recording.stage_id]
		if not stages.has(name): stages[name] = {}
		var role := str(recording.role)
		if not stages[name].has(role): stages[name][role] = {"turns": 0, "seconds": [], "tries": 0, "tries_known": 0, "drowned": 0, "closing": 0, "unfinished": 0, "still": {"seconds": 0.0, "where": "", "turn": ""}}
		var row: Dictionary = stages[name][role]
		row.turns += 1
		row.seconds.append(snappedf(float(recording.duration_ticks) / TICK_RATE, 0.1))
		var tries := int(found.tries.get(hash, 0))
		if tries > 0:
			row.tries += tries
			row.tries_known += 1
		var played := replay(key, recording, found)
		if not played.get("note", "").is_empty():
			notes.append("%s %s turn %s: %s" % [name, role, hash.left(8), played.note])
			continue
		replayed += 1
		row.drowned += int(played.drowned)
		row.closing += int(played.closing)
		if not played.finished: row.unfinished += 1
		if float(played.still.seconds) > float(row.still.seconds):
			row.still = {"seconds": played.still.seconds, "where": played.still.where, "turn": hash.left(8)}
	return {"stages": stages, "turns": hashes.size(), "replayed": replayed, "notes": notes, "files": found.files, "blobs": found.blobs}

## Every recording and checkpoint in the folder, by hash, and its try counts.
static func collect(input: String) -> Dictionary:
	var found := {"recordings": {}, "checkpoints": {}, "tries": {}, "files": 0, "blobs": 0, "notes": []}
	for path: String in _files(input):
		if not path.ends_with(".json"): continue
		var length := FileAccess.open(path, FileAccess.READ).get_length() if FileAccess.file_exists(path) else 0
		if length > MAX_FILE_BYTES:
			found.notes.append("skipped %s: larger than %d bytes" % [path.get_file(), MAX_FILE_BYTES])
			continue
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if value == null: continue
		found.files += 1
		if path.get_file() == TurnTries.FILE_PATH.get_file():
			# Its own check, read only: TurnTries' loader keeps a copy of a damaged file beside it.
			var parsed: Variant = TurnTries._parse_kept(value)
			if parsed != null: found.tries = parsed.kept
		elif path.get_file() == "index.json" and value is Dictionary and value.get("attempts") is Array:
			_read_history(path.get_base_dir(), value, found)
		else: _walk(value, found)
	return found

## A room history folder: each attempt blob checked against its index record.
static func _read_history(folder: String, index: Dictionary, found: Dictionary) -> void:
	for record: Variant in index.attempts:
		if not record is Dictionary or not record.get("file") is String: continue
		var path := folder.path_join(str(record.file))
		if not FileAccess.file_exists(path): continue
		var bytes := HistoryStore.verified_bytes(FileAccess.get_file_as_bytes(path), record)
		if bytes.is_empty():
			found.notes.append("history blob %s failed its check" % path.get_file())
			continue
		found.blobs += 1
		var value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if value != null: _walk(value, found)

static func _walk(value: Variant, found: Dictionary) -> void:
	if value is Array:
		for item: Variant in value: _walk(item, found)
		return
	if not value is Dictionary: return
	if _is_recording(value):
		found.recordings[str(value.get("recording_hash", Canonical.digest(value)))] = value
	elif _is_checkpoint(value):
		found.checkpoints[str(value.checkpoint_hash)] = value
	for field: Variant in value: _walk(value[field], found)

static func _is_recording(value: Dictionary) -> bool:
	return value.get("actions") is Array and str(value.get("role", "")) in ["a", "b"] and value.get("stage_id") is String and value.has("duration_ticks") and value.get("level_id") is String and value.get("definition_hash") is String

static func _is_checkpoint(value: Dictionary) -> bool:
	return value.get("checkpoint_hash") is String and value.has("next_stage_id") and value.get("players") is Dictionary and value.get("level_id") is String

## Every file under the folder, never stepping into a save folder.
static func _files(folder: String) -> Array[String]:
	var result: Array[String] = []
	var own := ProjectSettings.globalize_path("user://").replace("\\", "/").to_lower().trim_suffix("/")
	for file: String in DirAccess.get_files_at(folder): result.append(folder.path_join(file))
	for child: String in DirAccess.get_directories_at(folder):
		var path := folder.path_join(child)
		var plain := ProjectSettings.globalize_path(path).replace("\\", "/").to_lower()
		if plain == own or _save_folder(plain): continue
		result.append_array(_files(path))
	return result

## One turn played again through its engine: {"drowned", "closing",
## "finished", "still": {"seconds", "where"}}, or {"note"} when it cannot be.
static func replay(key: String, recording: Dictionary, found: Dictionary) -> Dictionary:
	if key.is_empty(): return {"note": "not a chapter this build knows"}
	if not Registry.is_cooperative(key): return {"note": "time only: this family is not replayed here"}
	var level := Registry.definition(key)
	var checkpoint: Dictionary = found.checkpoints.get(str(recording.get("checkpoint_hash", "")), {})
	var initial := Registry.initial_checkpoint(key)
	if checkpoint.is_empty() and initial.get("checkpoint_hash") == recording.get("checkpoint_hash"): checkpoint = initial
	if checkpoint.is_empty(): return {"note": "time only: the checkpoint it was played from is not in the folder"}
	var prior: Dictionary = {}
	if recording.role == "b":
		prior = found.recordings.get(str(recording.get("source_recording_hash", "")), {})
		if prior.is_empty(): return {"note": "time only: its partner's first turn is not in the folder"}
	var engine: Script = Registry.simulation_script(key)
	var sim: RefCounted = engine.new()
	if not Registry.reset_simulation(sim, key, level, str(recording.stage_id), checkpoint, prior, str(recording.role), recording):
		return {"note": "did not replay: " + str(sim.error)}
	var stage := StageCatalog.stage_definition(level, str(recording.stage_id))
	var drowned := 0
	var closing := 0
	var still := {"ticks": 0, "at": {}}
	var run := {"ticks": 0, "at": {}}
	var snapshot: Dictionary = {}
	for input: Dictionary in engine.expand_recording_inputs(recording):
		snapshot = sim.step(input)
		for event: String in snapshot.get("events", []):
			if event.begins_with("drowned:"): drowned += 1
			elif event.begins_with("closing:"): closing += 1
		var player: Dictionary = snapshot.players[snapshot.active_slot]
		var at := {"x": int(player.x), "z": int(player.z), "surface_id": str(player.surface_id)}
		if at == run.at: run.ticks += 1
		else: run = {"ticks": 1, "at": at}
		if run.ticks > still.ticks: still = run.duplicate()
	if drowned == 0 and snapshot.get("drowned") is Dictionary and not snapshot.drowned.is_empty(): drowned = 1
	var finished := bool(recording.get("completed", false)) if recording.role == "b" else bool(snapshot.get("can_commit", false))
	return {"drowned": drowned, "closing": closing, "finished": finished,
		"still": {"seconds": snappedf(float(still.ticks) / TICK_RATE, 0.1), "where": place(level, stage, still.at)}}

## Where a pip stood: on a crossing, by a pad, lever, switch or goal, or at
## its spot on its floor.
static func place(level: Dictionary, stage: Dictionary, at: Dictionary) -> String:
	if at.is_empty(): return ""
	for route: Dictionary in level.get("bridges", []) + level.get("stairs", []):
		var r: Array = route.rect_cm
		if at.x >= int(r[0]) and at.x <= int(r[2]) and at.z >= int(r[1]) and at.z <= int(r[3]): return "on crossing %s" % route.id
	var best := ""
	var best_distance := NEAR_CM * NEAR_CM + 1
	var things: Array = stage.get("pressure_pads", []) + stage.get("levers", []) + stage.get("controls", []) + stage.get("ball_pads", [])
	if stage.get("goal") is Dictionary: things.append(stage.goal)
	for thing: Dictionary in things:
		if str(thing.get("surface_id", "")) != at.surface_id or not thing.get("position_cm") is Array: continue
		var distance := Vector2i(at.x, at.z).distance_squared_to(Vector2i(int(thing.position_cm[0]), int(thing.position_cm[1])))
		if distance < best_distance:
			best_distance = distance
			best = str(thing.id)
	if not best.is_empty(): return "by %s" % best
	return "on %s at [%d, %d]" % [at.surface_id, at.x, at.z]

static func text(made: Dictionary) -> String:
	var lines: Array[String] = ["PLAYTEST REPORT: %d turns from %d files and %d history blobs, %d replayed" % [made.turns, made.files, made.blobs, made.replayed]]
	var names: Array = made.stages.keys()
	names.sort()
	for name: String in names:
		lines.append("")
		lines.append(name)
		for role: String in ["a", "b"]:
			if not made.stages[name].has(role): continue
			var row: Dictionary = made.stages[name][role]
			var seconds: Array = row.seconds.duplicate()
			seconds.sort()
			lines.append("  turn %s: %d saved, %s s (median %s, fastest %s, slowest %s)" % [role, row.turns, ", ".join(seconds.map(func(value: float) -> String: return str(value))), _median(seconds), seconds[0], seconds[-1]])
			if row.tries_known > 0: lines.append("    tries: %d over %d turns with a count (%d retries)" % [row.tries, row.tries_known, row.tries - row.tries_known])
			if row.drowned > 0 or row.closing > 0 or row.unfinished > 0:
				lines.append("    drowned %d, crossings closing %d, unfinished %d" % [row.drowned, row.closing, row.unfinished])
			if float(row.still.seconds) > 0.0: lines.append("    stood still longest: %s s %s (turn %s)" % [row.still.seconds, row.still.where, row.still.turn])
	if not made.notes.is_empty():
		lines.append("")
		lines.append("Notes:")
		for note: String in made.notes: lines.append("  " + note)
	return "\n".join(lines)

static func _median(sorted: Array) -> float:
	if sorted.is_empty(): return 0.0
	var middle := sorted.size() / 2
	return float(sorted[middle]) if sorted.size() % 2 == 1 else snappedf((float(sorted[middle - 1]) + float(sorted[middle])) / 2.0, 0.1)

extends SceneTree
## The scheduled leaderboard replay job's Godot step, headless only:
##   godot --headless --path game --script res://tests/leaderboard_replay_job.gd -- <pending.json> <verdicts.json>
## Reads the pending runs backend/scripts/leaderboard-check.mjs fetched,
## checks each with tests/leaderboard_replay_check.gd and writes the verdicts
## for that script to post. It holds no credential and makes no request.
## The verdicts file is written again after every run, so a run that crashes
## the engine leaves the verdicts before it; the post step then sends that run
## to a person and the rest wait for the next hour. A check that breaks part
## way gives "replay_error" (a person looks), never a pass.
## Exit 0 when every run got a verdict (passed or not), 1 when the input or
## output file could not be used.
const Check = preload("res://tests/leaderboard_replay_check.gd")

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var paths := OS.get_cmdline_user_args()
	if paths.size() != 2:
		push_error("usage: -- <pending.json> <verdicts.json>")
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(paths[0]))
	if not parsed is Dictionary or not parsed.get("entries") is Array:
		push_error("pending runs file is not readable")
		quit(1)
		return
	var verdicts: Array = []
	if not _write(paths[1], verdicts):
		quit(1)
		return
	for entry: Variant in parsed.entries:
		if not entry is Dictionary: continue
		var verdict: Variant = Check.verdict(entry)
		if not verdict is Dictionary or verdict.size() != 6:
			verdict = {"board": str(entry.get("board", "")), "entry_id": str(entry.get("entry_id", "")), "proof_hash": str(entry.get("proof_hash", "")), "valid": false, "measured_ticks": 0, "reason": "replay_error"}
		verdicts.append(verdict)
		print("leaderboard check %s %s: %s %d %s" % [verdict.board, verdict.entry_id, "pass" if verdict.valid else "fail", verdict.measured_ticks, verdict.reason])
		if not _write(paths[1], verdicts):
			quit(1)
			return
	quit(0)

func _write(path: String, verdicts: Array) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("verdicts file is not writable")
		return false
	file.store_string(JSON.stringify({"schema_version": 1, "verdicts": verdicts}))
	file.close()
	return true

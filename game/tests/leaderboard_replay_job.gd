extends SceneTree
## The scheduled leaderboard replay job's Godot step, headless only:
##   godot --headless --path game --script res://tests/leaderboard_replay_job.gd -- <pending.json> <verdicts.json>
## Reads the pending runs backend/scripts/leaderboard-check.mjs fetched,
## checks each with tests/leaderboard_replay_check.gd and writes the verdicts
## for that script to post. It holds no credential and makes no request.
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
	for entry: Variant in parsed.entries:
		if not entry is Dictionary: continue
		var verdict := Check.verdict(entry)
		verdicts.append(verdict)
		print("leaderboard check %s %s: %s %d %s" % [verdict.board, verdict.entry_id, "pass" if verdict.valid else "fail", verdict.measured_ticks, verdict.reason])
	var file := FileAccess.open(paths[1], FileAccess.WRITE)
	if file == null:
		push_error("verdicts file is not writable")
		quit(1)
		return
	file.store_string(JSON.stringify({"schema_version": 1, "verdicts": verdicts}))
	file.close()
	quit(0)

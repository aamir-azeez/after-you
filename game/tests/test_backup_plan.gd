extends SceneTree
## Android backup plan: priority order, newest first within a group, kept room
## history before shared replays, and nothing device-bound, photo-related, temporary or oversized.

const Plan = preload("res://services/backup_plan.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _file(root: String, path: String, size: int = 8) -> void:
	DirAccess.make_dir_recursive_absolute(root.path_join(path).get_base_dir())
	var bytes := PackedByteArray()
	bytes.resize(size)
	var file := FileAccess.open(root.path_join(path), FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

func _run() -> void:
	var root := "user://backup-plan-test-%d" % Time.get_ticks_usec()
	var room := "history/aaaaaaaaaaaaaaaa/HHHHHHHHHHHHHHHHHHHHHH/RRRRRRRRRRRRRRRRRRRRRR"
	for path: String in ["relay-journey-v2.json.attempt-0a1b.json", "shared-replays/old.json", room + "/index.json", room + "/0-0123456789abcdef.bin",
		"journey.json", "home-keepsakes-v1.json", "relay-journey-v2.json", "first-steps-journey-v1.json", "relay-journey-v2.json.backup", "relay-journey-v2.json.tmp",
		"relay-online/0123.json", "photo-library/p.jpg", "photo-transfer/t.json", "safety/s.json", "turn-photos/x.json", "shared-replays/old.json.backup"]:
		_file(root, path)
	_file(root, "shared-replays/huge.json", Plan.MAX_SHARED_FILE + 1)
	var paths: Array = Plan.entries(root).map(func(item: Dictionary) -> String: return item.path)
	_check(paths == ["journey.json", "home-keepsakes-v1.json", "first-steps-journey-v1.json", "relay-journey-v2.json", room + "/index.json", room + "/0-0123456789abcdef.bin",
		"shared-replays/old.json", "relay-journey-v2.json.attempt-0a1b.json"], "Settings, journals, kept room history, shared replays, then attempt archives: %s" % [paths])
	_check(not paths.any(func(path: String) -> bool: return path.begins_with("relay-online/") or path.begins_with("photo") or path.begins_with("safety/") or path.begins_with("turn-photos/") or path.ends_with(".tmp") or path.ends_with(".backup")), "Device-bound, photo, safety and temporary files are never listed")
	_check(not paths.has("shared-replays/huge.json"), "A replay file over 20 MiB is skipped whole, never cut")
	_check(Plan.write(root), "The plan is written for the backup agent")
	var lines := FileAccess.get_file_as_string(root.path_join(Plan.PLAN)).split("\n", false)
	_check(lines[0] == Plan.HEADER and lines.size() == paths.size() + 1 and lines[1] == "8\tjourney.json", "One size-and-path line a file under the plan's header")
	_remove(root)
	print("Backup plan: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _remove(path: String) -> void:
	for name: String in DirAccess.get_directories_at(path): _remove(path.path_join(name))
	for name: String in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(name))
	DirAccess.remove_absolute(path)

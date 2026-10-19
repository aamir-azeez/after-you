extends RefCounted
## The list of files Android backup may copy to the player's own Google account,
## in priority order (the backup agent keeps what fits its quota, in this order):
## 1. settings and keepsakes; 2. chapter journals; 3. kept room history (it may be
## the only copy anywhere), newest room first; 4. shared replay files (replay
## transfer v1 rooms' only full copy), newest first; 5. solo attempt archives,
## newest first, then kept hard runs (services/hard_mode.gd), newest first.
## Never: online room state bound to this device, photo transfers,
## safety data, the photo library, temporary or backup generations.

const PLAN := "backup-plan.txt"
const HEADER := "after-you-backup-plan 1"
## Hard mode's marks (nothing rebuilds them) and its runs' small index.
const FIXED := ["journey.json", "home-keepsakes-v1.json", "solo-replay-visibility.json", "friend_nicknames.json", "hard-mode-v1.json", "hard-runs-v1.json"]
const MAX_ENTRIES := 4096
const MAX_SHARED_FILE := 20 * 1024 * 1024

## [{path, bytes}] relative to `root` with forward slashes.
static func entries(root: String = "user://") -> Array:
	var result: Array = []
	for name: String in FIXED: _add(result, root, name)
	var journal := RegEx.create_from_string("^[a-z0-9-]+-journey-v[0-9]+\\.json$")
	var attempt := RegEx.create_from_string("\\.attempt-[a-f0-9]+\\.json$")
	var names := _files(root)
	for name: String in _sorted(names.filter(func(item: String) -> bool: return journal.search(item) != null)): _add(result, root, name)
	var history: Array = []
	for server: String in _folders(root.path_join("history")):
		for owner: String in _folders(root.path_join("history").path_join(server)):
			for room: String in _folders(root.path_join("history").path_join(server).path_join(owner)):
				history.append("history/%s/%s/%s" % [server, owner, room])
	for folder: String in _newest(root, history, "index.json"):
		_add(result, root, folder.path_join("index.json"))
		for name: String in _sorted(_files(root.path_join(folder)).filter(func(item: String) -> bool: return item.ends_with(".bin"))): _add(result, root, folder.path_join(name))
	var shared: Array = _files(root.path_join("shared-replays")).filter(func(item: String) -> bool: return item.ends_with(".json")).map(func(item: String) -> String: return "shared-replays/" + item)
	for path: String in _newest(root, shared, ""): _add(result, root, path, MAX_SHARED_FILE)
	for path: String in _newest(root, names.filter(func(item: String) -> bool: return attempt.search(item) != null), ""): _add(result, root, path)
	for path: String in _newest(root, names.filter(func(item: String) -> bool: return item.ends_with("-hard-runs.json")), ""): _add(result, root, path)
	return result.slice(0, MAX_ENTRIES)

static func _files(path: String) -> Array:
	return Array(DirAccess.get_files_at(path)) if DirAccess.dir_exists_absolute(path) else []

static func _folders(path: String) -> Array:
	return Array(DirAccess.get_directories_at(path)) if DirAccess.dir_exists_absolute(path) else []

static func _sorted(items: Array) -> Array:
	var copy := items.duplicate()
	copy.sort()
	return copy

## Paths ordered newest first by the modified time of `marker` inside each (or of the path itself).
static func _newest(root: String, paths: Array, marker: String) -> Array:
	var stamped: Array = paths.map(func(path: String) -> Array: return [FileAccess.get_modified_time(root.path_join(path).path_join(marker) if not marker.is_empty() else root.path_join(path)), path])
	stamped.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	return stamped.map(func(item: Array) -> String: return item[1])

static func _add(result: Array, root: String, path: String, limit: int = -1) -> void:
	var file := FileAccess.open(root.path_join(path), FileAccess.READ)
	if file == null: return
	var size := file.get_length()
	file.close()
	if limit < 0 or size <= limit: result.append({"path": path, "bytes": size})

## Writes the plan the backup agent reads. Safe to call often: it only lists files.
static func write(root: String = "user://") -> bool:
	var lines := PackedStringArray([HEADER])
	for item: Dictionary in entries(root): lines.append("%d\t%s" % [item.bytes, item.path])
	var file := FileAccess.open(root.path_join(PLAN), FileAccess.WRITE)
	if file == null: return false
	file.store_string("\n".join(lines) + "\n")
	return file.get_error() == OK

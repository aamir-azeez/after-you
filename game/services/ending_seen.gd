extends RefCounted
## Which chapters' ending scenes (services/ending_scene.gd) this phone has
## watched to the end, by level id (the key before "@"), so a newer version of
## a chapter does not make its ending a must-watch again. Its own small file,
## never the main save: a chapter screen runs while Main holds that one in
## memory, and Main's next write would drop a key written beside it.
## An ending not watched yet plays through with no skip; after that it skips.
const AtomicFile = preload("res://services/atomic_file.gd")
const PATH := "user://endings_seen.json"
## How many level ids it keeps at most; the file is never read past this.
const MOST := 64

var path := PATH

func _init(save_path: String = PATH) -> void:
	path = save_path

## The level ids watched, oldest first. A missing or broken file reads as none.
func levels() -> Array[String]:
	var data: Variant = AtomicFile.read_json(path, func(value: Variant) -> bool: return value is Dictionary and value.get("levels") is Array)
	var result: Array[String] = []
	if not data is Dictionary: return result
	for level: Variant in data.levels:
		if level is String and not level.is_empty() and not level in result and result.size() < MOST: result.append(level)
	return result

func seen(level: String) -> bool:
	return level in levels()

## Records `level` as watched. True when it is (already was, or the write held).
func mark(level: String) -> bool:
	var known := levels()
	if level in known: return true
	known.append(level)
	while known.size() > MOST: known.remove_at(0)
	return AtomicFile.write_text(path, JSON.stringify({"levels": known}))

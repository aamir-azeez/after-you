extends RefCounted
## Lists user:// when created; cleanup() deletes exactly the files (and then
## empty folders) that appeared since, so a run leaves user:// as it found it.
var _before: Dictionary = {}

func _init() -> void:
	for path: String in _walk("user://"): _before[path] = true

func _walk(root: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null: return result
	for file: String in dir.get_files(): result.append(root.path_join(file))
	for folder: String in dir.get_directories():
		result.append(root.path_join(folder) + "/")
		result.append_array(_walk(root.path_join(folder)))
	return result

func cleanup() -> void:
	var created: Array[String] = []
	for path: String in _walk("user://"):
		if not _before.has(path): created.append(path)
	# Files first, then folders deepest first.
	created.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for path: String in created:
		if not path.ends_with("/"): DirAccess.remove_absolute(path)
	for path: String in created:
		if path.ends_with("/"): DirAccess.remove_absolute(path.trim_suffix("/"))

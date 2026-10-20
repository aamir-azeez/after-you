extends SceneTree
## No string literal holds a typed line break.
##
## A Windows checkout turns a line break typed inside quotes into CR LF, so the
## text a build shows depends on the machine that built it (the Rooms notice
## carried a stray carriage return in APKs built on Windows). Write "\n" instead.
## Triple-quoted strings are multi-line on purpose and are not scanned.

var checks := 0
var failures := 0

func _initialize() -> void:
	_check(_typed_breaks("var a := \"x\ny\"\n") == [1], "A line break inside quotes is found")
	_check(_typed_breaks("var a := \"x\\ny\"\n# \"not\n").is_empty(), "An escaped \\n and a comment are fine")
	_check(_typed_breaks("var a := \"\"\"x\ny\"\"\"\nvar b := 'it\\'s'\n").is_empty(), "Triple quotes and escaped quotes are fine")
	var paths := _scripts("res://")
	_check(paths.has("res://presentation/room_hub_screen.gd"), "The scan reads the project's scripts")
	for path: String in paths:
		for line: int in _typed_breaks(FileAccess.get_file_as_string(path)):
			_check(false, "%s:%d has a line break typed inside a string; write \\n" % [path, line])
	print("STRING LINE BREAKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Lines (1-based) where a single- or double-quoted literal spans a line break.
static func _typed_breaks(raw: String) -> Array[int]:
	var source := raw.replace("\r\n", "\n")
	var result: Array[int] = []
	var i := 0
	var n := source.length()
	while i < n:
		var c := source[i]
		if c == "#":
			var end := source.find("\n", i)
			i = n if end < 0 else end
			continue
		if source.substr(i, 3) == "\"\"\"":
			var close := source.find("\"\"\"", i + 3)
			i = n if close < 0 else close + 3
			continue
		if c == "\"" or c == "'":
			var j := i + 1
			while j < n and source[j] != c:
				j += 2 if source[j] == "\\" else 1
			if source.substr(i, j - i).contains("\n"): result.append(source.substr(0, i).count("\n") + 1)
			i = j + 1
			continue
		i += 1
	return result

static func _scripts(directory: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null: return found
	for name: String in dir.get_directories():
		if name.begins_with(".") or (directory == "res://" and name == "addons"): continue
		found.append_array(_scripts(directory.path_join(name)))
	for name: String in dir.get_files():
		if name.ends_with(".gd"): found.append(directory.path_join(name))
	return found

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)

extends SceneTree
## Every text field a player types in is wired to the keyboard lift.
##
## On a phone held sideways the on screen keyboard covers most of the screen;
## KeyboardLift.attach(field) (presentation/kit/keyboard_lift.gd) shows the
## field large above it. A field made without the call stays small and hidden
## under the keyboard. This scan finds a LineEdit or TextEdit made in a script
## that the same function neither attaches nor makes read only
## (editable = false), and any made in a scene file.

## Scripts allowed an unwired field (path -> variable names). Empty: every one is wired.
const KNOWN := {}

var checks := 0
var failures := 0

func _initialize() -> void:
	_check(_unwired("var field := LineEdit.new()\nfield.placeholder_text = \"Code\"\n") == ["field"], "A typed field without the lift is found")
	_check(_unwired("var field := LineEdit.new()\nKeyboardLift.attach(field)\n").is_empty(), "An attached one is fine")
	_check(_unwired("var field := LineEdit.new()\nKeyboardLift.attach(field, \"Code\", counter)\n").is_empty(), "An attached one with a title is fine")
	_check(_unwired("_join = LineEdit.new()\nKeyboardLift.attach(_join)\n").is_empty(), "A member field attached is fine")
	_check(_unwired("var shown := LineEdit.new()\nshown.editable = false\n").is_empty() and _unwired("var shown := LineEdit.new()\nshown.editable=false\n").is_empty(), "A read only field is fine")
	_check(_unwired("var notes := TextEdit.new()\n") == ["notes"], "A TextEdit counts too")
	_check(_unwired("func a() -> void:\n\tvar field := LineEdit.new()\nfunc b() -> void:\n\tKeyboardLift.attach(field)\n") == ["field"], "An attach in another function does not count")
	_check(_unwired("var field: LineEdit = LineEdit.new()\n") == ["field"] and _unwired("self._code = LineEdit.new()\n") == ["_code"], "Typed and self. forms are read")
	_check(_constructions("add_child(LineEdit.new())\n") == 1 and _made().search_all("add_child(LineEdit.new())\n").is_empty(), "A field made inline is counted but not named, so its file fails")
	_check(_scene_fields("[node name=\"Code\" type=\"LineEdit\" parent=\".\"]\n") == ["Code"], "A field in a scene file is found")
	var paths := _files("res://", ".gd")
	_check(paths.has("res://presentation/friends_screen.gd"), "The scan reads the project's scripts")
	var made := 0
	for path: String in paths:
		var source := FileAccess.get_file_as_string(path)
		var count := _constructions(source)
		made += count
		_check(_made().search_all(source).size() == count, "%s makes a LineEdit or TextEdit the scan cannot follow: make it as `var name := LineEdit.new()` and call KeyboardLift.attach(name)" % path)
		_check(RegEx.create_from_string("(?m)^extends\\s+(?:LineEdit|TextEdit)\\b").search(source) == null, "%s extends a text field: make plain fields and attach each with KeyboardLift.attach" % path)
		for name: String in _unwired(source):
			_check(KNOWN.has(path) and name in KNOWN[path], "Text field '%s' in %s is not wired to the keyboard lift: call KeyboardLift.attach(%s) (presentation/kit/keyboard_lift.gd), or set %s.editable = false if no one types in it" % [name, path, name, name])
	_check(made >= 10, "The scan sees the game's text fields: %d" % made)
	for path: String in _files("res://", ".tscn"):
		for name: String in _scene_fields(FileAccess.get_file_as_string(path)):
			_check(false, "Text field '%s' in %s is made in a scene: make it in code and call KeyboardLift.attach on it" % [name, path])
	print("KEYBOARD LIFT WIRED: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Names of LineEdits and TextEdits the source makes but never attaches or makes read only.
static func _unwired(source: String) -> Array[String]:
	var result: Array[String] = []
	for match: RegExMatch in _made().search_all(source):
		var name := match.get_string(1)
		# Only the function that makes it: another function may reuse the name.
		var body := source.substr(match.get_end())
		var next := RegEx.create_from_string("(?m)^(?:static )?func ").search(body)
		if next != null: body = body.substr(0, next.get_start())
		if body.contains("KeyboardLift.attach(" + name + ")") or body.contains("KeyboardLift.attach(" + name + ","): continue
		if RegEx.create_from_string("(?m)^\\s*" + name + "\\.editable\\s*=\\s*false\\b").search(body) != null: continue
		if name not in result: result.append(name)
	return result

## A field made and named on one line: `var f := LineEdit.new()`,
## `var f: LineEdit = LineEdit.new()`, `f = ...`, `self.f = ...`.
static func _made() -> RegEx:
	return RegEx.create_from_string("(?m)^\\s*(?:var\\s+)?(?:self\\.)?(\\w+)\\s*(?::\\s*\\w+\\s*)?:?=\\s*(?:LineEdit|TextEdit)\\.new\\(\\)")

## Every LineEdit.new() and TextEdit.new() in the source, in any form.
static func _constructions(source: String) -> int:
	return RegEx.create_from_string("\\b(?:LineEdit|TextEdit)\\.new\\(\\)").search_all(source).size()

static func _scene_fields(source: String) -> Array[String]:
	var result: Array[String] = []
	for match: RegExMatch in RegEx.create_from_string("\\[node name=\"([^\"]+)\" type=\"(?:LineEdit|TextEdit)\"").search_all(source):
		result.append(match.get_string(1))
	return result

static func _files(directory: String, extension: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null: return found
	for name: String in dir.get_directories():
		if name.begins_with(".") or (directory == "res://" and name in ["addons", "tests"]): continue
		found.append_array(_files(directory.path_join(name), extension))
	for name: String in dir.get_files():
		if name.ends_with(extension): found.append(directory.path_join(name))
	return found

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)

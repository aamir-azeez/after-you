extends SceneTree
## No static var in a script that extends another project script.
##
## Godot 4.7.2 can free a script while it tears the scripts down at exit when a
## subclass keeps a static var that its functions read, and another script
## preloads the base before the subclass (platform_games.gd preloading
## games_provider.gd, then native_games_provider.gd with a static RegEx cache).
## The exit then reads freed memory: usually harmless, but under load it ended
## suites that had passed every check with 0xC0000005. Started under a debugger
## (whose heap fills freed memory) the crash happened on every exit. Keep shared
## state in a script that extends an engine class instead.
##
## Inner classes are not scanned; the crash was only shown with top-level scripts.

## Subclass scripts allowed a static var. Empty: every cache lives in a script
## that extends an engine class.
const KNOWN := {}

var checks := 0
var failures := 0

func _initialize() -> void:
	var paths := _scripts("res://")
	var sources := {}
	for path: String in paths: sources[path] = FileAccess.get_file_as_string(path)
	var named := _class_names(sources)
	# The scan itself: the shape that crashed, and the shapes that are fine.
	var fake_named := {"Base": "res://base.gd"}
	_check(_offending("extends \"res://base.gd\"\nstatic var cache := {}\n", fake_named), "A static var in a script extending a path is found")
	_check(_offending("extends Base\n\nstatic var count: int = 0\n", fake_named), "A static var in a script extending a class_name is found")
	_check(not _offending("extends RefCounted\nstatic var cache := {}\n", fake_named), "A static var in a script extending an engine class is fine")
	_check(not _offending("extends \"res://base.gd\"\nclass Inner:\n\tstatic var calls := 0\nstatic func cached() -> int:\n\treturn 0\n", fake_named), "Inner classes and static functions are not flagged")
	_check(paths.has("res://services/platform_games/native_games_provider.gd"), "The scan reads the project's scripts")
	var found := {}
	for path: String in paths:
		if _offending(sources[path], named): found[path] = true
	for path: String in found:
		_check(KNOWN.has(path), "Static var in a subclass script (crashes the exit): " + path)
	for path: String in KNOWN:
		_check(found.has(path), "No longer a static var in a subclass, drop it from KNOWN: " + path)
	print("SUBCLASS STATICS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## True when the script extends a project script and declares a top-level static var.
static func _offending(source: String, named: Dictionary) -> bool:
	var base := ""
	var statics := false
	for line: String in source.split("\n"):
		if base.is_empty() and line.begins_with("extends "):
			base = line.trim_prefix("extends ").strip_edges().get_slice(" ", 0).get_slice("\t", 0)
		elif line.begins_with("static var "):
			statics = true
	if not statics or base.is_empty(): return false
	if base.begins_with("\"res://"): return true
	return named.has(base.get_slice(".", 0))

static func _class_names(sources: Dictionary) -> Dictionary:
	var named := {}
	for path: String in sources:
		for line: String in (sources[path] as String).split("\n"):
			if line.begins_with("class_name "):
				named[line.trim_prefix("class_name ").get_slice(" ", 0).strip_edges()] = path
				break
	return named

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

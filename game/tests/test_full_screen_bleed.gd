extends SceneTree
## Every full-screen dim or backdrop reaches under a camera cutout.
##
## A ColorRect anchored to the full rect of a screen or overlay stops at the safe
## rect when its parent sits inside the cutout's inset, so the picture behind
## shows through a bright strip at the edge (the drowning card in Turn of the
## Tide did this). SafeArea.bleed stretches it to the whole visible screen. This
## scan finds a full-rect ColorRect whose script never bleeds it.

## Scripts allowed a full-rect ColorRect without a bleed (path -> variable names).
## Empty: every one bleeds.
const KNOWN := {}

var checks := 0
var failures := 0

func _initialize() -> void:
	_check(_unbled("var shade := ColorRect.new()\nshade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)\n") == ["shade"], "A full-rect ColorRect without a bleed is found")
	_check(_unbled("shade = ColorRect.new()\nshade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)\nSafeArea.bleed(shade)\n").is_empty(), "A bled one is fine")
	_check(_unbled("var tile := ColorRect.new()\ntile.custom_minimum_size = Vector2(8, 8)\n").is_empty(), "A ColorRect that is not full rect is fine")
	_check(_unbled("func a() -> void:\n\tvar line := ColorRect.new()\n\tline.custom_minimum_size.y = 1\nfunc b() -> void:\n\tline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)\n").is_empty(), "A name reused in another function is not mixed up")
	var paths := _scripts("res://")
	_check(paths.has("res://relay_preview.gd"), "The scan reads the project's scripts")
	var found := {}
	for path: String in paths:
		var names := _unbled(FileAccess.get_file_as_string(path))
		if not names.is_empty(): found[path] = names
	for path: String in found:
		for name: String in found[path]:
			_check(KNOWN.has(path) and name in KNOWN[path], "Full-screen ColorRect '%s' in %s does not reach under a cutout: call SafeArea.bleed(%s)" % [name, path, name])
	print("FULL SCREEN BLEED: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Names of ColorRects the source anchors to the full rect but never bleeds.
static func _unbled(source: String) -> Array[String]:
	var result: Array[String] = []
	var made := RegEx.create_from_string("(?m)^\\s*(?:var\\s+)?(\\w+)\\s*:?=\\s*ColorRect\\.new\\(\\)")
	for match: RegExMatch in made.search_all(source):
		var name := match.get_string(1)
		# Only the function that makes it: another function may reuse the name.
		var body := source.substr(match.get_end())
		var next := RegEx.create_from_string("(?m)^(?:static )?func ").search(body)
		if next != null: body = body.substr(0, next.get_start())
		if not body.contains(name + ".set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)"): continue
		if body.contains("SafeArea.bleed(" + name + ")"): continue
		if name not in result: result.append(name)
	return result

static func _scripts(directory: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null: return found
	for name: String in dir.get_directories():
		if name.begins_with(".") or (directory == "res://" and name in ["addons", "tests"]): continue
		found.append_array(_scripts(directory.path_join(name)))
	for name: String in dir.get_files():
		if name.ends_with(".gd"): found.append(directory.path_join(name))
	return found

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)

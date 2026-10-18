extends "res://tests/test_world_fingerprint.gd"
## The GL warm-up (services/gl_warmup.gd) draws everything a chapter draws.
## - Every chapter world, played through its fixture replays (the moments the
##   world fingerprint pins: start, ends, halfway, under a raised floor) and
##   walked hidden nodes included, draws only StandardMaterial3D keys, Label3D
##   keys and ShaderMaterial shaders the warm-up draws, with every raised floor
##   also faded by the cutaway at each moment. A chapter that adds a key fails
##   here until gl_warmup.gd lists it.
## - Each key the warm-up lists makes exactly that key.
## - The service: never runs headless unless enabled; idle at Home it draws
##   one item per drawn frame and finishes; a touch or leaving Home frees its
##   viewport at once and a later idle run goes on from there; once done it
##   marks this install and a new run skips it.
## The chapters are split over two suites to stay inside CI's 120 s (this one
## and test_gl_warmup_coverage_journey.gd, by world fingerprint suite); each
## reports, without failing, listed keys its chapters never drew.
## AFTER_YOU_GL_WARMUP_DUMP=1 prints the keys found, ready to paste.
const Warmup = preload("res://services/gl_warmup.gd")

var _materials: Array[Dictionary] = []
var _labels: Array[Dictionary] = []
var _shaders: Dictionary = {}
var _where: Dictionary = {}
var _by_chapter: Dictionary = {}

func _suite() -> String:
	return "gl_warmup_coverage"

## Which world fingerprint suites' chapters each coverage suite walks.
const SPLIT := {
	"gl_warmup_coverage": ["world_fingerprint", "world_fingerprint_lighthouse", "world_fingerprint_lighthouse_v2"],
	"gl_warmup_coverage_journey": ["world_fingerprint_physical", "world_fingerprint_journey"],
}

## The world fingerprint suites whose chapters this suite walks.
func _groups() -> Array:
	return SPLIT[_suite()]

## Whether this suite also walks chapters no fingerprint suite pins, and
## checks the keys the warm-up makes and the service.
func _owns_the_rest() -> bool:
	return true

func _run() -> void:
	var pinned: Dictionary = {}
	for suite: String in SUITES:
		for key: String in SUITES[suite]:
			pinned[key] = true
			if suite not in _groups(): continue
			var stages := _lighthouse_snapshots() if key == LIGHTHOUSE else _snapshots(key)
			_passes(key, false, stages)
	if _owns_the_rest():
		for key: String in Registry.keys():
			if not pinned.has(key): _built_stages(key)
	_check_covered()
	_check_chapters()
	_report_unseen()
	if _owns_the_rest():
		var split: Array = []
		for suite: String in SPLIT: split.append_array(SPLIT[suite])
		split.sort()
		var pinned_suites: Array = SUITES.keys()
		pinned_suites.sort()
		_check(split == pinned_suites, "The coverage suites walk every world fingerprint suite's chapters, each once (SPLIT)")
		_check_made()
		await _service()
	print("%s: %d checks, %d failures" % [_suite().to_upper().replace("_", " "), checks, failures])
	quit(1 if failures else 0)

## A chapter with no fixture replay: each stage as built.
func _built_stages(key: String) -> void:
	var viewport := _viewport()
	var world: Node3D = Registry.world_script(key).new()
	_mount(viewport, world, false)
	world.load_level(Registry.definition(key))
	for stage: Dictionary in Registry.definition(key).get("stages", []):
		if world.has_method("show_stage"): world.show_stage(stage)
		_frames(world, 30)
		_fingerprint(world, key, false, str(stage.get("id", "")))
	viewport.free()

## Collects what the world draws instead of fingerprinting it, as shown and
## with every raised floor faded by the cutaway.
func _fingerprint(world: Node3D, key: String, _reduced: bool, scenario: String) -> Dictionary:
	_collect_drawn(world, key, scenario)
	var raised: Array = world.get("_upper_islands") if world.get("_upper_islands") is Array else []
	if raised.is_empty() or not world.has_method("_set_cutaway"): return {"hash": 0, "order_hash": 0}
	var faded: Array = []
	for node: Variant in raised:
		if is_instance_valid(node) and not (node as Node).get_meta("cutaway", false):
			world.call("_set_cutaway", node, true)
			faded.append(node)
	_collect_drawn(world, key, scenario + " faded")
	for node: Node in faded: world.call("_set_cutaway", node, false)
	return {"hash": 0, "order_hash": 0}

func _collect_drawn(world: Node3D, key: String, scenario: String) -> void:
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.is_queued_for_deletion(): continue
		stack.append_array(node.get_children())
		if node is Label3D:
			var label := Warmup.label_key(node)
			_add(_labels, label, key, scenario)
			_drew(key, "l", Warmup.LABELS.find(label))
		elif node is GeometryInstance3D:
			var geometry := node as GeometryInstance3D
			var found: Array[Material] = [geometry.material_override, geometry.material_overlay]
			if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
				var mesh_node := node as MeshInstance3D
				for surface in range(mesh_node.mesh.get_surface_count()):
					found.append(mesh_node.get_surface_override_material(surface))
					found.append(mesh_node.mesh.surface_get_material(surface))
			for material: Material in found:
				while material != null:
					if material is BaseMaterial3D:
						var found_key := Warmup.material_key(material)
						_add(_materials, found_key, key, scenario)
						_drew(key, "m", Warmup.MATERIALS.find(found_key))
					elif material is ShaderMaterial and (material as ShaderMaterial).shader != null:
						_shaders[(material as ShaderMaterial).shader.code] = "%s %s" % [key, scenario]
						_drew(key, "s", _shader_codes().find((material as ShaderMaterial).shader.code))
					material = material.next_pass

## What each chapter drew, as gl_warmup.gd CHAPTERS lists it (-1: unlisted,
## reported by _check_covered).
func _drew(chapter: String, kind: String, index: int) -> void:
	if index < 0: return
	if not _by_chapter.has(chapter): _by_chapter[chapter] = {"m": [], "s": [], "l": []}
	if index not in _by_chapter[chapter][kind]: _by_chapter[chapter][kind].append(index)

func _shader_codes() -> Array:
	return Warmup.shaders().map(func(shader: Shader) -> String: return shader.code)

## Every chapter this suite walked has its CHAPTERS entry, exactly.
func _check_chapters() -> void:
	for chapter: String in _by_chapter:
		for kind: String in ["m", "s", "l"]: _by_chapter[chapter][kind].sort()
		if not OS.get_environment("AFTER_YOU_GL_WARMUP_DUMP").is_empty(): print("CHAPTER \"%s\": %s," % [chapter, JSON.stringify(_by_chapter[chapter])])
		var listed: Dictionary = Warmup.CHAPTERS.get(chapter, {})
		var same := true
		for kind: String in ["m", "s", "l"]:
			var entry: Array = listed.get(kind, []).duplicate()
			entry.sort()
			same = same and entry == _by_chapter[chapter][kind]
		_check(same, "gl_warmup.gd CHAPTERS lists exactly what %s draws: %s" % [chapter, JSON.stringify(_by_chapter[chapter])])

func _add(found: Array[Dictionary], item: Dictionary, key: String, scenario: String) -> void:
	if item in found: return
	found.append(item)
	_where[str(item)] = "%s %s" % [key, scenario]

func _check_covered() -> void:
	if not OS.get_environment("AFTER_YOU_GL_WARMUP_DUMP").is_empty():
		for item: Dictionary in _materials: print("MATERIAL ", var_to_str(item).replace("\n", ""), " # ", _where[str(item)])
		for item: Dictionary in _labels: print("LABEL ", var_to_str(item).replace("\n", ""), " # ", _where[str(item)])
	for item: Dictionary in _materials:
		_check(item in Warmup.MATERIALS, "The GL warm-up draws material key %s (first drawn in %s); list it in gl_warmup.gd MATERIALS" % [str(item), _where[str(item)]])
	for item: Dictionary in _labels:
		_check(item in Warmup.LABELS, "The GL warm-up draws label key %s (first drawn in %s); list it in gl_warmup.gd LABELS" % [str(item), _where[str(item)]])
	var codes: Array = Warmup.shaders().map(func(shader: Shader) -> String: return shader.code)
	for code: String in _shaders:
		_check(code in codes, "The GL warm-up draws the ShaderMaterial shader first drawn in %s; add it to gl_warmup.gd shaders()" % _shaders[code])
	_check(not _materials.is_empty() and not _labels.is_empty() and not _shaders.is_empty(), "The walk found materials, labels and shaders")

## Listed keys none of this suite's chapters drew: drop one neither suite reports as drawn.
func _report_unseen() -> void:
	for item: Dictionary in Warmup.MATERIALS + Warmup.LABELS:
		if item not in _materials and item not in _labels: print("ADVISORY %s chapters never drew listed key %s" % [_suite(), str(item)])

func _check_made() -> void:
	var total: int = Warmup.MATERIALS.size() + Warmup.shaders().size() + Warmup.LABELS.size()
	for chapter: String in Warmup.CHAPTERS:
		var order := Warmup.order(chapter)
		var listed: Dictionary = Warmup.CHAPTERS[chapter]
		var lead: int = listed.get("m", []).size() + listed.get("s", []).size() + listed.get("l", []).size()
		var leads := true
		for entry: Array in order.slice(0, lead): leads = leads and entry[1] in listed.get(entry[0], [])
		_check(order.size() == total and leads, "The warm-up draws everything once, %s's programs first" % chapter)
	_check(Warmup.order("").size() == total, "With no chapter in view it draws everything once")
	for chapter: String in Warmup.CHAPTERS:
		_check(chapter in Registry.keys() or chapter == LIGHTHOUSE, "gl_warmup.gd CHAPTERS names a chapter that exists: " + chapter)
	for item: Dictionary in Warmup.MATERIALS:
		_check(Warmup.material_key(Warmup.material_for(item)) == item, "The warm-up's material for %s has exactly that key" % str(item))
	for item: Dictionary in Warmup.LABELS:
		var label := Label3D.new()
		Warmup._label_as(label, item)
		_check(Warmup.label_key(label) == item, "The warm-up's label for %s has exactly that key" % str(item))
		label.free()

## The service's life, headless with drawing forced on. A headless run draws
## no frames, so each frame here tells it one was drawn, as the engine does.
func _drawn_frame() -> void:
	await process_frame
	RenderingServer.frame_post_draw.emit()

func _service() -> void:
	Warmup._order = []
	Warmup.stamp_path = "user://gl-warmup-test-" + Crypto.new().generate_random_bytes(6).hex_encode() + ".json"
	var idle := [true]
	var first: Node = Warmup.new()
	_check(not first.enabled, "Headless, the warm-up never draws unless enabled")
	first.enabled = true
	first.idle_seconds = 0.0
	first.idle = func() -> bool: return idle[0]
	root.add_child(first)
	var guard := 0
	while not first.running() and guard < 300:
		await process_frame
		guard += 1
	_check(first.running(), "Idle at Home, the warm-up starts")
	first._input(InputEventMouseMotion.new())
	_check(first.running(), "A pointer passing over it is not a touch")
	first._input(InputEventScreenTouch.new())
	_check(not first.running() and Warmup.pending(), "A touch stops it at once, unfinished")
	await process_frame
	await process_frame
	_check(first.running(), "Idle again, it goes on")
	await _drawn_frame()
	await _drawn_frame()
	var reached := int(Warmup._next)
	idle[0] = false
	await process_frame
	_check(not first.running() and Warmup.pending(), "Leaving Home stops it at once, unfinished")
	idle[0] = true
	guard = 0
	while Warmup.pending() and guard < 2000:
		await _drawn_frame()
		guard += 1
	_check(not Warmup.pending() and not first.running(), "A later idle Home finishes it")
	_check(reached > 0 and guard < first._items.size() + 120, "It went on from item %d, one item a drawn frame (%d frames for %d items)" % [reached, guard, first._items.size()])
	_check(FileAccess.file_exists(Warmup.stamp_path), "Finishing marks this install as warm")
	first.queue_free()
	await process_frame
	Warmup._done = false
	Warmup._next = 0
	Warmup._order = []
	var second: Node = Warmup.new()
	second.enabled = true
	second.idle_seconds = 0.0
	second.idle = func() -> bool: return true
	root.add_child(second)
	guard = 0
	var drew := false
	while Warmup.pending() and guard < 300:
		await process_frame
		guard += 1
		drew = drew or second.running()
	_check(not Warmup.pending() and not drew, "A warmed install is done without drawing")
	second.queue_free()
	DirAccess.remove_absolute(Warmup.stamp_path)

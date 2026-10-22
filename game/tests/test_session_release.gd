extends SceneTree
## SessionRelease lets go of the kit's kept looks and meshes when the tree shuts
## down, before the engine frees its material shaders: a glowing kit look still
## held by a static var then crashed the exit (0xC0000005 after every check
## passed in render_efficiency). The bubbles' and the water locks' kept
## looks and meshes go the same way.

const SessionRelease = preload("res://presentation/kit/session_release.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const DefinitionGeometry = preload("res://presentation/kit/definition_geometry.gd")
const LabelBubble = preload("res://presentation/kit/label_bubble.gd")
const WaterLocks = preload("res://presentation/kit/water_locks.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var look := Primitives.shared_material(Color(0.3, 0.6, 0.9), 0.8, Color(1, 0.9, 0.6), 1.5)
	DefinitionGeometry.keep(["session-release-test"], {"value": 1})
	var body := LabelBubble.body_material(false, false)
	var door := WaterLocks._door_material()
	await process_frame
	var node := root.get_node_or_null(SessionRelease.NODE_NAME)
	_check(node != null, "A kept look puts the release node under the root")
	_check(Primitives.is_cached(look) and DefinitionGeometry.has(["session-release-test"]), "Looks and geometry are kept while the tree runs")
	Primitives.shared_material(Color(0.3, 0.6, 0.9), 0.8, Color(1, 0.9, 0.6), 1.5)
	await process_frame
	_check(root.get_children().filter(func(child: Node) -> bool: return child.name == SessionRelease.NODE_NAME).size() == 1, "Registering again adds no second node")
	SessionRelease.release_all()
	_check(not Primitives.is_cached(look) and not DefinitionGeometry.has(["session-release-test"]), "Release lets go of the kept looks and geometry")
	_check(body != null and LabelBubble._bodies.is_empty() and LabelBubble._shaders.is_empty(), "Release lets go of the bubbles' kept body looks")
	_check(door != null and WaterLocks._door_material_cache == null and WaterLocks._opening_meshes.is_empty(), "Release lets go of the water locks' kept door look and meshes")
	print("SESSION RELEASE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)

extends SceneTree
## kit/models.gd places parts of a model made with the Blender kit, painted per
## slot, the way the code-built pieces are, from the kit's own sample
## (tests/fixtures/models/kit_sample.glb: a post with a cap, band and hook,
## slots wood, metal and rope, and a wheel on an axle, slots wood and metal).
## - The model reads in Godot axes and metres: the post stands 1 m tall from
##   its foot, the wheel's origin is its axle, its face toward the camera.
## - A still part is a plain container of one plain leaf per slot in the
##   slot's shared look; two posts in two themes fold into one palette batch
##   (no draw call of their own) holding every vertex in each slot's colour.
## - A moving part is one mesh with each slot's colour on its vertices, drawn
##   with the palette look, kept once per colour set.
## - The model is read once until release_cached(), then again the same.
## - Every model in assets/models (and the sample) imports with Godot's name
##   hints, LODs, shadow meshes, tangents, light baking and animation off
##   (IMPORT), every part paints only named slots, and the file holds one
##   scene of nothing but its parts.
const Models = preload("res://presentation/kit/models.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const SAMPLE := "res://tests/fixtures/models/kit_sample.glb"
const GARDEN := {"wood": Color("8a6b4e"), "metal": Color("e2b25e"), "rope": Color("d1b98c")}
## Import settings every model GLB keeps (its .import file).
const IMPORT := ["nodes/use_name_suffixes=false", "nodes/use_node_type_suffixes=false", "meshes/ensure_tangents=false",
	"meshes/generate_lods=false", "meshes/create_shadow_meshes=false", "meshes/light_baking=0", "animation/import=false"]
const MODEL_DIRS := ["res://assets/models", "res://tests/fixtures/models"]
const HARBOUR := {"wood": Color("efe2c4"), "metal": Color("46607a"), "rope": Color("c8644c")}

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)

func _run() -> void:
	_reads()
	_still_folds()
	_moving()
	_every_model()
	Models.release_cached()
	_check(Models.parts(SAMPLE) == ["sample_post", "sample_rim"], "a released model reads again the same")
	print("MODELS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _reads() -> void:
	_check(Models.parts(SAMPLE) == ["sample_post", "sample_rim"], "the sample has its two parts: %s" % [Models.parts(SAMPLE)])
	var post_slots := Models.slots(SAMPLE, "sample_post")
	post_slots.sort()
	_check(post_slots == ["metal", "rope", "wood"], "the post paints wood, metal and rope: %s" % [post_slots])
	var rim_slots := Models.slots(SAMPLE, "sample_rim")
	rim_slots.sort()
	_check(rim_slots == ["metal", "wood"], "the wheel paints wood and metal: %s" % [rim_slots])
	var axle := Models.transform(SAMPLE, "sample_rim").origin
	_check(axle.distance_to(Vector3(0, 0.62, 0.1)) < 0.001, "the wheel's origin is its axle in Godot axes: %s" % axle)
	var root := Node3D.new()
	get_root().add_child(root)
	var post := Models.still(SAMPLE, "sample_post", GARDEN, root)
	var box := AABB()
	var first := true
	for leaf: MeshInstance3D in post.get_children():
		var leaf_box := leaf.get_aabb()
		box = leaf_box if first else box.merge(leaf_box)
		first = false
	_check(absf(box.position.y) < 0.01 and absf(box.end.y - 1.0) < 0.01, "the post stands from 0 to 1 m: %s" % box)
	_check(box.position.x < 0 and box.end.x > 0 and box.position.z < 0 and box.end.z > 0, "the post stands on its origin: %s" % box)
	var wheel := Models.still(SAMPLE, "sample_rim", GARDEN, root)
	var rim_box: AABB = (wheel.get_child(0) as MeshInstance3D).get_aabb()
	for leaf: MeshInstance3D in wheel.get_children(): rim_box = rim_box.merge(leaf.get_aabb())
	_check(rim_box.size.z < 0.07 and rim_box.size.x > 0.2 and rim_box.size.y > 0.2, "the wheel faces the camera, thin in z: %s" % rim_box.size)
	root.free()

func _still_folds() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var garden := Models.still(SAMPLE, "sample_post", GARDEN, root)
	# Both within one fold cell (StaticBatch.CELL).
	garden.position = Vector3(1, 0, 1)
	var harbour := Models.still(SAMPLE, "sample_post", HARBOUR, root)
	harbour.position = Vector3(3, 0, 1)
	var leaves := 0
	var vertices := 0
	for container: Node in [garden, harbour]:
		_check(container.get_script() == null and container.get_child_count() == 3, "a still part is a plain container of one leaf a slot")
		for leaf: MeshInstance3D in container.get_children():
			leaves += 1
			vertices += leaf.mesh.surface_get_array_len(0)
			var colors: Dictionary = GARDEN if container == garden else HARBOUR
			var look := leaf.material_override as StandardMaterial3D
			_check(Primitives.is_cached(look) and Primitives.is_plain(look), "a slot leaf wears the slot's shared plain look")
			_check(look.albedo_color == colors[str(leaf.name)], "slot %s is painted %s" % [leaf.name, colors[str(leaf.name)]])
	var folded := StaticBatch.fold(root, [])
	_check(folded.folded == leaves and folded.batches == 1, "two posts in two themes fold into one batch: %s" % folded)
	var batches := root.find_children("StaticBatch*", "MeshInstance3D", false, false)
	if batches.size() == 1:
		var batch := batches[0] as MeshInstance3D
		var arrays := batch.mesh.surface_get_arrays(0)
		_check((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == vertices, "the batch holds every vertex of both posts")
		var seen: Dictionary = {}
		for tint: Color in arrays[Mesh.ARRAY_COLOR]: seen[tint.to_html(false)] = true
		for colors: Dictionary in [GARDEN, HARBOUR]:
			for slot: String in colors: _check(seen.has((colors[slot] as Color).to_html(false)), "the batch paints %s %s" % [slot, colors[slot]])
		_check((batch.material_override as StandardMaterial3D).vertex_color_use_as_albedo, "the batch is drawn with the palette look")
	root.free()

func _moving() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var wheel := Models.moving(SAMPLE, "sample_rim", GARDEN, root)
	_check(wheel.get_child_count() == 0 and wheel.mesh.get_surface_count() == 1, "a moving part is one mesh")
	_check(wheel.transform.origin.distance_to(Vector3(0, 0.62, 0.1)) < 0.001, "a moving part stands at its model transform")
	_check((wheel.material_override as StandardMaterial3D).vertex_color_use_as_albedo, "a moving part is drawn with the palette look")
	var seen: Dictionary = {}
	for tint: Color in wheel.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]: seen[tint.to_html(false)] = true
	_check(seen.keys().size() == 2 and seen.has(GARDEN.wood.to_html(false)) and seen.has(GARDEN.metal.to_html(false)), "the wheel's vertices carry its two slot colours: %s" % [seen.keys()])
	var again := Models.moving(SAMPLE, "sample_rim", GARDEN, root)
	_check(again.mesh == wheel.mesh, "the same colours share one painted mesh")
	var other := Models.moving(SAMPLE, "sample_rim", HARBOUR, root)
	_check(other.mesh != wheel.mesh, "other colours paint another mesh")
	_check(StaticBatch.fold(root, []).folded == 0, "a painted part never folds: it moves")
	root.free()

func _every_model() -> void:
	var found := 0
	for dir: String in MODEL_DIRS:
		if not DirAccess.dir_exists_absolute(dir): continue
		for file: String in DirAccess.get_files_at(dir):
			if not file.ends_with(".glb"): continue
			found += 1
			var path := dir.path_join(file)
			var settings := FileAccess.get_file_as_string(path + ".import")
			for line: String in IMPORT: _check(line in settings, "%s imports with %s" % [file, line])
			var parts := Models.parts(path)
			for part: String in parts:
				for slot: String in Models.slots(path, part): _check(slot != "" and slot.to_snake_case() == slot, "%s %s paints a named slot: %s" % [file, part, slot])
			# Godot imports only the file's first scene, so the file itself is read:
			# one scene whose every node is a part (no stray Blender cube in another).
			var gltf := _gltf_json(path)
			var nodes: Array[String] = []
			for node: Dictionary in gltf.get("nodes", []): nodes.append(str(node.get("name", "")))
			nodes.sort()
			var scenes: Array = gltf.get("scenes", [])
			_check(scenes.size() == 1, "%s holds one scene: %s" % [file, scenes.map(func(scene: Dictionary) -> String: return str(scene.get("name", "")))])
			_check(nodes == parts and (gltf.get("meshes", []) as Array).size() == parts.size(), "%s holds only its parts: %s" % [file, nodes])
	_check(found >= 1, "the model folders hold the sample at least")

## A GLB's JSON chunk: its length at byte 12, the JSON from byte 20.
func _gltf_json(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 20: return {}
	var parsed: Variant = JSON.parse_string(bytes.slice(20, 20 + bytes.decode_u32(12)).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}

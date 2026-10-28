extends SceneTree
## Every keepsake builder (presentation/keepsakes/, named by the descriptors):
## each loads and builds every combination of its upgrades within the budget,
## keeps its pieces inside its own ground, times its tap within the limits,
## only moves its own moving parts, and draws only looks the GL warm-up
## compiles. The started outline is one draw with one shared look.
const States = preload("res://services/home_keepsake_states.gd")
const Parts = preload("res://presentation/keepsakes/keepsake_parts.gd")
const Anim = preload("res://presentation/keepsakes/keepsake_anim.gd")
const Builder = preload("res://presentation/keepsakes/keepsake_builder.gd")
const GlWarmup = preload("res://services/gl_warmup.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const Index = preload("res://content/chapters/index.gd")
const MAX_PARTS := 50
const MAX_TRIANGLES := 3500
const MAX_MOVING := 6
const TOTAL_MAX := 4.5
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var warm: Array = GlWarmup.MATERIALS.map(func(key: Dictionary) -> Dictionary: return key)
	var all_parts := 0
	var all_triangles := 0
	for entry: Dictionary in _every_keepsake():
		var builder: RefCounted = load(str(entry.keepsake.builder)).new()
		_check(builder is Builder, "%s's builder extends keepsake_builder.gd" % entry.id)
		for flags in range(16):
			var state := {"together": flags & 1 != 0, "hard": flags & 2 != 0 and entry.hard, "top": flags & 4 != 0 and entry.hard}
			if entry.id == States.EARLIER: state.lanterns = [true, false, true, false, true, false, true, false] if flags & 8 else [false, false, false]
			_check_build(stage, entry, builder, state)
		var full: Dictionary = builder.full_state()
		var prop := Node3D.new()
		stage.add_child(prop)
		builder.build(prop, full)
		var counted := _count(prop)
		all_parts += counted[0]
		all_triangles += counted[1]
		prop.free()
		# Timing: base at most 2.5 s, each upgrade at most 0.8 s, all within 4.5 s.
		var beats: Array = builder.beats(full)
		var total := 0.0
		for beat: Dictionary in beats:
			total += float(beat.time)
			_check(float(beat.time) <= (Builder.BASE_MAX if beat.beat == "base" else Builder.UPGRADE_MAX), "%s's %s beat is short enough: %.2f" % [entry.id, beat.beat, beat.time])
		_check(beats[0].beat == "base" and total <= TOTAL_MAX, "%s plays every upgrade within %.1f s: %.2f" % [entry.id, TOTAL_MAX, total])
		_check(beats.size() == 1 + int(full.get("together", false)) + int(full.get("hard", false)) + int(full.get("top", false)), "%s adds one beat per earned upgrade" % entry.id)
		for beat: Dictionary in beats: _check(entry.keepsake.sounds.has(beat.beat), "%s has a sound for its %s beat" % [entry.id, beat.beat])
		_check_tap_parts(stage, entry, builder, full)
		# Warm-up: every look it draws is a feature key the GL warm-up compiles.
		for look: Material in builder.materials():
			var key := GlWarmup.material_key(look as BaseMaterial3D)
			_check(warm.has(key), "%s draws a look the warm-up compiles: %s" % [entry.id, key])
		# Outline: one draw, the shared veil.
		var outline_root := Node3D.new()
		stage.add_child(outline_root)
		var veil := Parts.outline(outline_root, builder, entry.id + "|test", [[true, false], [false, true]])
		var meshes := outline_root.find_children("*", "MeshInstance3D", true, false)
		_check(veil.mesh.get_surface_count() == 1 and veil.material_override == Parts.ghost() and meshes.filter(func(node: Node) -> bool: return (node as MeshInstance3D).material_override == Parts.ghost()).size() == 1, "%s's outline is one merged mesh with the shared veil" % entry.id)
		_check(meshes.size() == 3, "%s's outline has one dot per stage" % entry.id)
		outline_root.free()
	print("KEEPSAKE PROPS: all eleven with every upgrade: %d parts, %d triangles before folding" % [all_parts, all_triangles])
	_check(all_triangles <= 32000, "All eleven with every upgrade stay under 32,000 triangles: %d" % all_triangles)
	_check(Primitives.changed_shared_looks().is_empty(), "No keepsake changes a shared look in place: %s" % [Primitives.changed_shared_looks()])
	stage.free()
	print("KEEPSAKE PROPS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Home's keepsakes, then any registered chapter's not on Home yet (a new
## chapter not released), held to the same budget before it ships.
func _every_keepsake() -> Array:
	var result: Array = States.entries().duplicate()
	var seen: Array = result.map(func(entry: Dictionary) -> String: return entry.id)
	for key: String in Index.keys():
		var level := key.get_slice("@", 0)
		if seen.has(level) or Index.data(key).home_keepsake.is_empty(): continue
		seen.append(level)
		result.append({"id": level, "keepsake": Index.data(key).home_keepsake, "hard": true, "together": true})
	return result

func _count(node: Node) -> Array:
	var parts := 0
	var triangles := 0
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (child as MeshInstance3D).mesh
		if mesh == null: continue
		parts += mesh.get_surface_count()
		triangles += mesh.get_faces().size() / 3
	return [parts, triangles]

func _check_build(stage: Node3D, entry: Dictionary, builder: RefCounted, state: Dictionary) -> void:
	var prop := Node3D.new()
	stage.add_child(prop)
	var parts: Dictionary = builder.build(prop, state)
	var label := "%s %s" % [entry.id, state]
	var counted := _count(prop)
	_check(counted[0] <= MAX_PARTS and counted[1] <= MAX_TRIANGLES, "%s stays within %d parts and %d triangles: %s" % [label, MAX_PARTS, MAX_TRIANGLES, counted])
	var moving := parts.values().filter(func(part: Variant) -> bool: return part is Node)
	_check(moving.size() <= MAX_MOVING, "%s moves at most %d parts: %d" % [label, MAX_MOVING, moving.size()])
	_check(prop.find_children("*", "", true, false).all(func(node: Node) -> bool: return node.get_script() == null), "%s carries no script, so its still parts fold" % label)
	# Its pieces stay inside its ground: the footing under, the together piece beside, the top above.
	var area: Rect2 = builder.footprint().grow(0.06)
	var outside: Array = []
	for node: Node in prop.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box: AABB = prop.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		for corner: Vector2 in [Vector2(box.position.x, box.position.z), Vector2(box.end.x, box.end.z)]:
			if not area.has_point(corner): outside.append(str(mesh.name))
	_check(outside.is_empty(), "%s keeps every piece inside its ground %s: %s" % [label, area, outside])
	if state.get("hard", false): _check(prop.find_child("Footing", true, false) != null, "%s stands on its footing" % label)
	prop.free()

## A tap only moves the parts build() returned (and their own pieces) or parts
## made for the tap; with Reduce motion it never builds a Tween.
func _check_tap_parts(stage: Node3D, entry: Dictionary, builder: RefCounted, state: Dictionary) -> void:
	var prop := Node3D.new()
	stage.add_child(prop)
	var parts: Dictionary = builder.build(prop, state)
	for reduced: bool in [false, true]:
		var anim := Anim.new()
		anim.reduced = reduced
		anim.fx = Node3D.new()
		prop.add_child(anim.fx)
		var holder := Node.new()
		stage.add_child(holder)
		var tween := holder.create_tween().set_parallel(true)
		if not reduced: anim.tween = tween
		for beat: Dictionary in builder.beats(state): builder.play(str(beat.beat), anim, parts, state)
		var owned: Array = parts.values().filter(func(part: Variant) -> bool: return part is Node)
		var strays: Array = []
		for node: Variant in anim.touched:
			if anim.spawned.has(node): continue
			if owned.has(node) or owned.has((node as Node).get_parent()): continue
			strays.append(str((node as Node).name))
		_check(strays.is_empty(), "%s's tap moves only its moving parts: %s" % [entry.id, strays])
		_check(anim.spawned.all(func(part: Node) -> bool: return anim.fx.is_ancestor_of(part) or owned.any(func(own: Node) -> bool: return own.is_ancestor_of(part))), "%s makes its tap parts under the tap node or a moving part" % entry.id)
		if reduced: _check(not tween.is_valid() or not tween.is_running() or tween.get_total_elapsed_time() == 0.0, "%s with Reduce motion builds no motion" % entry.id)
		tween.kill()
		holder.free()
		anim.fx.free()
	prop.free()

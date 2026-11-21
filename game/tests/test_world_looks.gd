extends "res://tests/test_world_fingerprint.gd"
## Every chapter world stays cheap to draw on a phone, however rich its
## scenery: the static fold (kit/static_batch.gd) folds plain scenery into a
## few batches, whatever its colours (a palette batch draws them as vertex
## colours) and however it is stretched, so a new prop or colour costs no
## draw call.
## - Shown and folded, each chapter stage draws at most MOST_DRAWS meshes and
##   MOST_TRIANGLES triangles: one budget for every chapter, what the
##   heaviest stage shipped (Turn of the Tide's second stage) with room to
##   spare. Draws and triangles are what a frame costs a phone (the renderer
##   draws no shadows); a stage within both runs like the stages already
##   shipped. Frame times are measured on rendered runs, not here.
## - Each stage grounds its pieces and props (kit/contact_shadows.gd): every
##   floor is a ground, what stands still on it is baked into it, and what
##   moves draws in one MultiMesh.
## - Driven through its fixture scenarios, Turn of the Tide @2 (not pinned by
##   the world fingerprint) changes no cached look in place.

## The most meshes a chapter stage draws, shown and folded (each visible
## mesh surface and overlay; a label or a multimesh is one). Turn of the
## Tide's second stage drew 672 before the palette fold and draws 525 now;
## every other stage draws at most 141 (Conservatory).
const MOST_DRAWS := 580
## The most triangles a chapter stage's visible meshes hold (Turn of the
## Tide's second stage: 213,204).
const MOST_TRIANGLES := 240000

func _suite() -> String:
	return "world_looks"

func _run() -> void:
	for key: String in Registry.keys():
		var definition := Registry.definition(key)
		if definition.is_empty() or definition.get("stages", []).is_empty(): continue
		for index in range(definition.stages.size()):
			await _census(key, definition, index)
	var key := "turn-of-the-tide@2"
	var stages := _snapshots(key)
	_check(stages.size() == 2, key + ": both stages replay from their fixtures")
	_passes(key, false, stages)
	_check(Primitives.changed_shared_looks().is_empty(), key + ": its scenarios change no cached look in place: %s" % [Primitives.changed_shared_looks()])
	print("WORLD LOOKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Turn of the Tide @2 has no replay golden chain yet: its stage fixtures.
func _native_chain(key: String) -> Dictionary:
	var spec := super._native_chain(key)
	if not spec.is_empty() or key != "turn-of-the-tide@2": return spec
	var stages: Array = []
	for stage_id: String in ["set-the-tide", "slack-water"]:
		var prefix := "journey/turn-of-the-tide-v2-" + stage_id
		stages.append([prefix + "-a.json", prefix + "-b.json", prefix + "-checkpoint.json"])
	return {"stages": stages}

## Shows a stage as a chapter screen does, lets it settle (a world places its
## bubbles, then folds, in its first frames) and counts what it draws.
func _census(key: String, definition: Dictionary, index: int) -> void:
	var viewport := _viewport()
	viewport.size = Vector2i(2400, 1080)
	var world: Node3D = Registry.world_script(key).new()
	_mount(viewport, world, false)
	world.load_level(definition)
	var stage: Dictionary = definition.stages[index]
	world.show_stage(stage)
	for _frame in range(3): await process_frame
	if world._folds_static_scenery(): world._fold_static_scenery()
	var label := "%s stage %d" % [key, index + 1]
	_check(not world._folds_static_scenery() or world.terrain.has_meta(Batch.FOLDED_META), label + ": its scenery folds")
	# Grounding: still things baked into their floors, live ones in one draw.
	var shadows: Node3D = world.get("contact_shadows")
	for _frame in range(120):
		if shadows == null or shadows.settled(): break
		await process_frame
	var cost := drawn(world)
	var baked: int = shadows.baked_roots().size() if shadows != null else 0
	var overlays: int = shadows.overlays().size() if shadows != null else 0
	_check(shadows != null and shadows.find_children("*", "MultiMeshInstance3D", true, false).size() == 1 and baked > 0 and overlays > 0, label + ": bakes what stands on its floors (%d roots on %d floors) and draws what moves in one MultiMesh" % [baked, overlays])
	_check(_floors_grounded(world, stage, definition).is_empty(), label + ": every floor is a ground its things are baked into: %s" % [_floors_grounded(world, stage, definition)])
	print("LOOKS|%s|draws %d|triangles %d|baked %d|floors %d|live %d" % [label, cost.draws, cost.triangles, baked, overlays, shadows.shown() if shadows != null else 0])
	_check(cost.draws <= MOST_DRAWS, label + ": draws at most %d meshes (%d)" % [MOST_DRAWS, cost.draws])
	_check(cost.triangles <= MOST_TRIANGLES, label + ": draws at most %d triangles (%d)" % [MOST_TRIANGLES, cost.triangles])
	viewport.free()

const Batch = preload("res://presentation/kit/static_batch.gd")
const ContactShadows = preload("res://presentation/kit/contact_shadows.gd")

## The floors of the stage with no ground at their height over any of their
## spots (a world that lays its floors its own way must register them with
## ContactShadows.ground()).
func _floors_grounded(world: Node3D, stage: Dictionary, definition: Dictionary) -> Array[String]:
	var grounds: Array[Node3D] = []
	for found: Node in world.get_tree().get_nodes_in_group(ContactShadows.GROUND_GROUP):
		if world.is_ancestor_of(found): grounds.append(found as Node3D)
	var missing: Array[String] = []
	for island: Dictionary in world.get("current_level").get("islands", stage.get("islands", definition.get("islands", []))):
		var r: Array = island.rect_cm
		var height := float(island.get("height_cm", 0)) / 100.0
		var found := false
		for step in range(25):
			var spot := world.global_transform * Vector3(lerpf(float(r[0]), float(r[2]), 0.1 + 0.2 * (step % 5)) / 100.0, height, lerpf(float(r[1]), float(r[3]), 0.1 + 0.2 * (step / 5)) / 100.0)
			for ground: Node3D in grounds:
				var local := ground.global_transform.affine_inverse() * spot
				if absf(local.y) < 0.03 and ContactShadows.holds(ground, Vector2(local.x, local.z)): found = true
			if found: break
		if not found: missing.append(str(island.id))
	return missing

## What a world draws a frame, everything shown in view or not: {draws,
## triangles}. An upper bound on the renderer's own count, which leaves out
## what is off screen.
static func drawn(world: Node) -> Dictionary:
	var draws := 0
	var triangles := 0
	var shapes: Dictionary = {}
	for node: Node in world.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if not geometry.is_visible_in_tree(): continue
		if geometry.material_overlay != null: draws += 1
		if node is MeshInstance3D:
			var mesh := (node as MeshInstance3D).mesh
			if mesh == null: continue
			draws += mesh.get_surface_count()
			triangles += _triangles(mesh, shapes)
		elif node is MultiMeshInstance3D:
			var many := (node as MultiMeshInstance3D).multimesh
			if many == null or many.mesh == null: continue
			draws += 1
			var count := many.visible_instance_count if many.visible_instance_count >= 0 else many.instance_count
			triangles += _triangles(many.mesh, shapes) * count
		else: draws += 1
	return {"draws": draws, "triangles": triangles}

## A mesh's triangles, counted once per mesh in shapes.
static func _triangles(mesh: Mesh, shapes: Dictionary) -> int:
	if shapes.has(mesh): return shapes[mesh]
	var total := 0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		total += ((indices as PackedInt32Array).size() if indices != null and not (indices as PackedInt32Array).is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	shapes[mesh] = total
	return total

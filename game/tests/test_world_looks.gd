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
	if world.has_method("show_stage"): world.show_stage(stage)
	else: world.present_stage(stage)
	for _frame in range(3): await process_frame
	if world._folds_static_scenery(): world._fold_static_scenery()
	var label := "%s stage %d" % [key, index + 1]
	_check(not world._folds_static_scenery() or world.terrain.has_meta(Batch.FOLDED_META), label + ": its scenery folds")
	var cost := drawn(world)
	print("LOOKS|%s|draws %d|triangles %d" % [label, cost.draws, cost.triangles])
	_check(cost.draws <= MOST_DRAWS, label + ": draws at most %d meshes (%d)" % [MOST_DRAWS, cost.draws])
	_check(cost.triangles <= MOST_TRIANGLES, label + ": draws at most %d triangles (%d)" % [MOST_TRIANGLES, cost.triangles])
	viewport.free()

const Batch = preload("res://presentation/kit/static_batch.gd")

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

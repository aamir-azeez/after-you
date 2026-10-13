extends SceneTree
## Scenery lint. Every prop in content/dressing, on every stage it shows on:
##  - stands off every walkable route, island, stair and drop whose walking
##    space it would share (flat decals excepted),
##  - stays clear of every pad, lever, switch, goal and start,
##  - never hides a spirit or a control from the chapter camera: a prop of
##    height h at base b hides ground at y0 behind it, swept along the view
##    direction (-3, -10)/13 per metre of height between b - y0 - spirit and
##    b + h - y0 (every chapter camera sits at offset (3, 13, 10)),
##  - and the built dressing has no collision or physics bodies.
const Registry = preload("res://services/chapter_registry.gd")
const Catalog = preload("res://content/dressing/catalog.gd")
const Props = preload("res://presentation/kit/props.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
const LightCatalog = preload("res://core/lighthouse/stage_catalog.gd")
const LighthouseWorld = preload("res://presentation/lighthouse_world.gd")
const LIGHTHOUSE := "sleeping-lighthouse@1"
const SPIRIT := 1.0
## About a spirit's body radius beyond the rectangle its centre walks in.
const MARGIN := 0.12
const VIEW := Vector2(-3.0, -10.0) / 13.0
## Two same-facing faces closer than this (metres) z-fight on some depth
## buffers at the chapter camera's distance; real gaps are a few millimetres.
const COPLANAR := 0.003
## Overlaps smaller than this (square metres) never show.
const MIN_OVERLAP := 0.0001
const ALIGNED := 0.9999
## In-world text has one home: the kit's speech bubble (kit/label_bubble.gd,
## LabelBubble.create) for levers, switches and places, and the kit's badge
## (kit/badges.gd, Badges.make) over spirits. No other presentation file
## builds its own Label3D, TextMesh or text plate.
const WORLD_TEXT_KIT := ["res://presentation/kit/label_bubble.gd", "res://presentation/kit/badges.gd"]
## Worlds still moving their own in-world text onto the kit: none left.
const WORLD_TEXT_PENDING := []
## Quads that carry no text, each with its reason. A label plate never belongs here.
const QUAD_USES := {
	"res://presentation/seed_visual.gd": "the seed's soft glow halo",
	"res://presentation/home_keepsake_display.gd": "the keepsake slot marks",
}## Chapters still being built in another session: reported, never failed.
const ADVISORY_KEYS := []
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _run() -> void:
	for key: String in Catalog.keys():
		_check(key == LIGHTHOUSE or key in Registry.keys(), "Dressing is filed under a registered chapter key: " + key)
		var data := Catalog.for_key(key)
		for stage: Variant in data.get("props", {}).keys():
			_check(stage == "*" or stage in _stage_ids(key), "Dressing stage exists in %s: %s" % [key, stage])
		for stage_id: String in _stage_ids(key):
			_lint(key, stage_id, _stage_view(key, stage_id), data)
	_check_built_worlds()
	_check_coplanar_worlds()
	_check_world_text_kit()
	print("DRESSING LINT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _stage_ids(key: String) -> Array:
	if key == LIGHTHOUSE: return LightCatalog.STAGE_IDS.duplicate()
	var result: Array = []
	for stage: Dictionary in Registry.definition(key).stages: result.append(str(stage.id))
	return result

func _stage_view(key: String, stage_id: String) -> Dictionary:
	if key == LIGHTHOUSE: return LightCatalog.definition(stage_id)
	return CooperativeCatalog.stage_definition(Registry.definition(key), stage_id)

func _rect(r: Array) -> Rect2:
	return Rect2(Vector2(float(r[0]), float(r[1])) / 100.0, Vector2(float(r[2] - r[0]), float(r[3] - r[1])) / 100.0)

func _heights(view: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for island: Dictionary in view.get("islands", []): result[str(island.id)] = float(island.get("height_cm", 0)) / 100.0
	return result

## Walking spaces: {rect, y, rise, name}. Stairs span their whole rise.
func _walkable(view: Dictionary) -> Array:
	var spaces: Array = []
	for island: Dictionary in view.get("islands", []):
		spaces.append({"rect": _rect(island.rect_cm), "y": float(island.get("height_cm", 0)) / 100.0, "rise": 0.0, "name": "island " + str(island.id)})
	for bridge: Dictionary in view.get("bridges", []):
		spaces.append({"rect": _rect(bridge.rect_cm), "y": float(bridge.get("height_cm", 0)) / 100.0, "rise": 0.0, "name": "route " + str(bridge.id)})
	for stair: Dictionary in view.get("stairs", []):
		var low := minf(float(stair.from_height_cm), float(stair.to_height_cm)) / 100.0
		spaces.append({"rect": _rect(stair.rect_cm), "y": low, "rise": absf(float(stair.to_height_cm - stair.from_height_cm)) / 100.0, "name": "stair " + str(stair.id)})
	return spaces

## Interactive places: pads, levers, switches, goals, starts, drops, optics.
func _controls(view: Dictionary, heights: Dictionary) -> Array:
	var found: Array = []
	_collect(view, heights, found, "")
	for drop: Dictionary in view.get("drops", []):
		found.append({"rect": _rect(drop.rect_cm), "y": float(heights.get(str(drop.get("surface_id", "")), 0.0)), "name": "drop " + str(drop.get("id", ""))})
	var starts: Dictionary = view.get("starts", {}) if view.get("starts") is Dictionary else {}
	for slot: String in starts:
		var start: Variant = starts[slot]
		var at: Array = start.position_cm if start is Dictionary else start
		found.append({"rect": Rect2(Vector2(float(at[0]), float(at[1])) / 100.0 - Vector2.ONE * 0.3, Vector2.ONE * 0.6), "y": float(heights.get(str(start.get("surface_id", "")), 0.0)) if start is Dictionary else 0.0, "name": "start " + slot})
	return found

func _collect(value: Variant, heights: Dictionary, found: Array, path: String) -> void:
	if value is Dictionary:
		if value.has("position_cm") and value.position_cm is Array and value.position_cm.size() == 2:
			var radius := float(value.get("radius_cm", 30)) / 100.0
			var at := Vector2(float(value.position_cm[0]), float(value.position_cm[1])) / 100.0
			found.append({"rect": Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), "y": float(heights.get(str(value.get("surface_id", "")), 0.0)), "name": "%s %s" % [path, value.get("id", "")]})
		for child: Variant in value:
			if str(child) != "starts": _collect(value[child], heights, found, str(child))
	elif value is Array:
		for item: Variant in value: _collect(item, heights, found, path)

func _lint(key: String, stage_id: String, view: Dictionary, data: Dictionary) -> void:
	var heights := _heights(view)
	var spaces := _walkable(view)
	var controls := _controls(view, heights)
	for spec: Dictionary in Props.expand(Catalog.stage_props(data, stage_id)):
		var label := "%s %s %s at %s" % [key, stage_id, spec.get("kind", "?"), spec.get("at", spec.get("from", spec.get("rect", "")))]
		if not _check(_known(spec), "Dressing prop kind exists: " + label): continue
		var extent := Props.extent(spec)
		var surface := str(spec.get("surface", ""))
		_check(surface.is_empty() or heights.has(surface), "Dressing surface exists on this stage: %s (%s)" % [label, surface])
		var base := float(heights.get(surface, 0.0)) + float(extent.base)
		var top := base + float(extent.height)
		var footprint: Rect2 = extent.rect
		var inner := footprint.grow(-0.01)
		if not bool(extent.flat):
			for space: Dictionary in spaces:
				if bool(extent.get("wall", false)) and _on_back_wall(footprint, base, space): continue
				var shares := top > float(space.y) + 0.02 and base < float(space.y) + float(space.rise) + SPIRIT
				_check(not (shares and inner.intersects(space.rect)), "Prop stands on a walkable %s: %s" % [space.name, label])
		for item: Dictionary in controls:
			_check(not (top > float(item.y) and base < float(item.y) + SPIRIT and inner.intersects(item.rect.grow(0.1))), "Prop covers %s: %s" % [item.name, label])
		if top - float(heights.get(surface, 0.0)) <= Props.LOW or bool(extent.flat): continue
		for target: Dictionary in spaces + controls:
			# A wall-hung prop sits above head height against its own room's back wall.
			if bool(extent.get("wall", false)) and _on_back_wall(footprint, base, target): continue
			if _hides(footprint, base, top, target):
				_check(false, "Prop hides %s from the camera: %s" % [target.name, label])
				break

func _on_back_wall(footprint: Rect2, base: float, target: Dictionary) -> bool:
	var rect: Rect2 = target.rect
	return base >= float(target.y) + 1.1 and footprint.position.x >= rect.position.x - 0.05 and footprint.end.x <= rect.end.x + 0.05 and footprint.position.y <= rect.position.y + 0.25

## The prop's view shadow at the target's height overlaps the target.
func _hides(footprint: Rect2, base: float, top: float, target: Dictionary) -> bool:
	var y0 := float(target.y)
	var near := maxf(0.0, base - y0 - SPIRIT - float(target.get("rise", 0.0)))
	var far := top - y0
	if far <= 0.0: return false
	var goal: Rect2 = target.rect.grow(MARGIN)
	var step := near
	while step <= far + 0.001:
		if Rect2(footprint.position + VIEW * step, footprint.size).grow(-0.01).intersects(goal): return true
		step += 0.05
	return false

func _known(spec: Dictionary) -> bool:
	var holder := Node3D.new()
	var prop := Props.build(spec, holder, 0.0, true)
	var known := prop != null
	holder.free()
	return known

## Builds each dressed world and proves the scenery has no physics.
func _check_built_worlds() -> void:
	for key: String in Catalog.keys():
		var world: Node3D = LighthouseWorld.new() if key == LIGHTHOUSE else Registry.world_script(key).new()
		root.add_child(world)
		world.set_process(false)
		for stage_id: String in _stage_ids(key):
			if key == LIGHTHOUSE: world.load_level(LightCatalog.definition(stage_id))
			else:
				if world.chapter_definition.is_empty(): world.load_level(Registry.definition(key))
				for stage: Dictionary in Registry.definition(key).stages:
					if stage.id == stage_id: world.show_stage(stage)
			var dressed: Array = world.terrain.find_children("*", "Node3D", true, false).filter(func(node: Node) -> bool: return node.has_meta("dressing_kind"))
			var expected := Props.expand(Catalog.stage_props(Catalog.for_key(key), stage_id)).size()
			_check(dressed.size() == expected, "Every dressing prop is built: %s %s (%d of %d)" % [key, stage_id, dressed.size(), expected])
			var bodies: Array = world.terrain.find_children("*", "CollisionObject3D", true, false) + world.terrain.find_children("*", "CollisionShape3D", true, false)
			_check(bodies.is_empty(), "Dressing adds no collision: %s %s" % [key, stage_id])
			# Fading every floor and restoring it must never reach a shared material.
			if world.has_method("_set_cutaway"):
				var before := _shared_looks()
				world._set_cutaway(world.terrain, true)
				world._set_cutaway(world.terrain, false)
				_check(_shared_looks() == before, "Cutaway leaves shared scenery materials unchanged: %s %s" % [key, stage_id])
		world.free()

## Builds every chapter world, dressed or not, stage by stage, and flags
## z-fighting: two opaque faces of different looks that face the same way,
## lie within COPLANAR of each other and overlap. Fix the geometry (an offset,
## a thinner or thicker piece, or one face removed), never the draw order.
func _check_coplanar_worlds() -> void:
	for key: String in [LIGHTHOUSE] + Array(Registry.keys()):
		var world: Node3D = LighthouseWorld.new() if key == LIGHTHOUSE else Registry.world_script(key).new()
		root.add_child(world)
		world.set_process(false)
		if key != LIGHTHOUSE: world.load_level(Registry.definition(key))
		var reported: Dictionary = {}
		for stage_id: String in _stage_ids(key):
			if key == LIGHTHOUSE: world.load_level(LightCatalog.definition(stage_id))
			elif world.has_method("show_stage"):
				for stage: Dictionary in Registry.definition(key).stages:
					if stage.id == stage_id: world.show_stage(stage)
			var found := coplanar_pairs(world)
			if "_water" in world: _check(world.has_method("water_levels"), "A world with moving water lists its water levels for the sweep: " + key)
			if world.has_method("water_levels"): found.append_array(water_pairs(world))
			for finding: String in found:
				# Scenery shared by several stages is reported once.
				if reported.has(finding): continue
				reported[finding] = true
				var message := "Coplanar faces z-fight in %s %s: %s" % [key, stage_id, finding]
				if key in ADVISORY_KEYS: print("ADVISORY " + message)
				else: _check(false, message)
			_check(world.terrain.find_children("*", "MeshInstance3D", true, false).size() > 20, "The coplanar sweep sees the built scenery: %s %s" % [key, stage_id])
		world.free()

## Water that rises and falls is drawn without writing depth, so an opaque
## face lying on one of its faces shows through it unevenly. A world with such
## water lists each body's display heights. Every crossing is kept first and
## the scenery swept again, as kept marks only exist once kept; then every
## height of every body is swept, pairing each water face with the opaque faces.
static func water_pairs(world: Node3D) -> Array[String]:
	var latched: Array = []
	for route: Dictionary in world.chapter_definition.get("bridges", []): latched.append(str(route.id))
	world.present_history({"mechanisms": {"latched_bridges": latched}})
	var found := coplanar_pairs(world)
	var levels: Dictionary = world.water_levels()
	for body: String in levels:
		var water: Node3D = world._water.get(body)
		if not is_instance_valid(water): continue
		var resting := float(water.get_meta("shown"))
		for value: String in levels[body]:
			world._set_water(body, float(levels[body][value]), true)
			for finding: String in coplanar_pairs(world, water):
				var line := "%s water at %s: %s" % [body, value, finding]
				if line not in found: found.append(line)
		world._set_water(body, resting, true)
	return found

## Every z-fighting pair among a world's static scenery (spirits excluded).
## With a `water` body, only pairs of one of its faces and one opaque face.
static func coplanar_pairs(world: Node3D, water: Node3D = null) -> Array[String]:
	var skip: Array = world.actors.values() if "actors" in world else []
	var faces: Array = [[], [], []]
	for node: Node in world.terrain.find_children("*", "MeshInstance3D", true, false):
		if _under_any(node, skip): continue
		_faces(node as MeshInstance3D, world, faces)
	if water != null:
		for node: Node in water.get_children():
			if node is MeshInstance3D: _water_faces(node as MeshInstance3D, world, faces)
	var found: Array[String] = []
	for axis in range(3):
		var list: Array = faces[axis]
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.at < b.at)
		for i in range(list.size()):
			var a: Dictionary = list[i]
			for j in range(i + 1, list.size()):
				var b: Dictionary = list[j]
				if b.at - a.at > COPLANAR: break
				if a.sign != b.sign or a.node == b.node or a.look == b.look: continue
				if water != null and a.has("water") == b.has("water"): continue
				var overlap: Rect2 = a.rect.intersection(b.rect)
				if overlap.get_area() < MIN_OVERLAP: continue
				found.append("%s and %s (%s%s at %.4f and %.4f, overlap %.0f cm2)" % [_path(a.node, world), _path(b.node, world), "+" if a.sign > 0 else "-", "xyz"[axis], a.at, b.at, overlap.get_area() * 10000.0])
	return found

## A node's own name, or "~" for an engine-numbered anonymous one.
static func _label(node: Node) -> String:
	return "~" if str(node.name).begins_with("@") else str(node.name)

static func _under_any(node: Node, roots: Array) -> bool:
	for candidate: Node in roots:
		if candidate == node or candidate.is_ancestor_of(node): return true
	return false

## A readable name for an anonymous mesh: its parent, shape, size and colour.
static func _path(node: MeshInstance3D, world: Node3D) -> String:
	var parent := node.get_parent()
	var size: Vector3 = (node.mesh as BoxMesh).size if node.mesh is BoxMesh else Vector3((node.mesh as CylinderMesh).bottom_radius, (node.mesh as CylinderMesh).height, (node.mesh as CylinderMesh).top_radius) if node.mesh is CylinderMesh else node.mesh.get_aabb().size
	var at := (world.global_transform.affine_inverse() * node.global_transform).origin
	return "%s/%s %s %.3fx%.3fx%.3f #%s at (%.2f, %.3f, %.2f)" % [_label(parent) if parent != world.terrain else "", _label(node), "box" if node.mesh is BoxMesh else "cylinder" if node.mesh is CylinderMesh else "mesh", size.x, size.y, size.z, (node.material_override as StandardMaterial3D).albedo_color.to_html(false), at.x, at.y, at.z]

## Axis-aligned flat faces of a box, or the caps of an upright cylinder, in
## world space: {at, sign, rect (the other two axes), node, look}.
static func _faces(node: MeshInstance3D, world: Node3D, faces: Array) -> void:
	var mat := node.material_override as StandardMaterial3D
	if mat == null or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or mat.albedo_color.a < 1.0: return
	var look := "%s|%s|%s|%s" % [mat.albedo_color.to_html(), mat.emission_enabled, mat.emission.to_html() if mat.emission_enabled else "", mat.vertex_color_use_as_albedo]
	var shape := world.global_transform.affine_inverse() * node.global_transform
	if node.mesh is BoxMesh:
		for column in range(3):
			var axis := shape.basis[column].normalized()
			if absf(axis.x) < ALIGNED and absf(axis.y) < ALIGNED and absf(axis.z) < ALIGNED: return
		var box := shape * AABB(-(node.mesh as BoxMesh).size * 0.5, (node.mesh as BoxMesh).size)
		for axis in range(3):
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			var rect := Rect2(Vector2(box.position[u], box.position[v]), Vector2(box.size[u], box.size[v]))
			# Only +x, +y and +z faces ever face the chapter camera at (3, 13, 10).
			faces[axis].append({"at": box.end[axis], "sign": 1, "rect": rect, "node": node, "look": look})
	elif node.mesh is CylinderMesh:
		var up := shape.basis.y.normalized()
		if absf(up.y) < ALIGNED: return
		var cylinder := node.mesh as CylinderMesh
		var half := cylinder.height * 0.5 * shape.basis.y.length()
		var center := shape.origin
		# A cap overlaps another face where its inscribed square does.
		var radius := cylinder.top_radius if up.y > 0.0 else cylinder.bottom_radius
		if radius <= 0.0: return
		var side := Vector2(shape.basis.z.length(), shape.basis.x.length()) * radius * 1.41421356
		faces[1].append({"at": center.y + half, "sign": 1, "rect": Rect2(Vector2(center.z, center.x) - side * 0.5, side), "node": node, "look": look})

## The camera-facing faces of a water mesh, whatever it is built from: one per
## triangle that faces +x, +y or +z, as that triangle's bounding rectangle.
static func _water_faces(node: MeshInstance3D, world: Node3D, faces: Array) -> void:
	var mat := node.material_override as StandardMaterial3D
	var look := "water|" + (mat.albedo_color.to_html() if mat != null else "")
	var shape := world.global_transform.affine_inverse() * node.global_transform
	var turn := shape.basis.inverse().transposed()
	for surface in range(node.mesh.get_surface_count()):
		var arrays := node.mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var order := PackedInt32Array(range(points.size()))
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array and not (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty(): order = arrays[Mesh.ARRAY_INDEX]
		for i in range(0, order.size() - 2, 3):
			var normal := (turn * normals[order[i]]).normalized()
			for axis in range(3):
				if normal[axis] < ALIGNED: continue
				var u := (axis + 1) % 3
				var v := (axis + 2) % 3
				var corner := shape * points[order[i]]
				var low := Vector2(corner[u], corner[v])
				var high := low
				for k in range(1, 3):
					var point := shape * points[order[i + k]]
					low = Vector2(minf(low.x, point[u]), minf(low.y, point[v]))
					high = Vector2(maxf(high.x, point[u]), maxf(high.y, point[v]))
				faces[axis].append({"at": corner[axis], "sign": 1, "rect": Rect2(low, high - low), "node": node, "look": look, "water": true})

func _shared_looks() -> Array:
	var looks: Array = []
	for mat: StandardMaterial3D in Primitives.shared_materials():
		looks.append([mat.albedo_color, mat.transparency, mat.emission_enabled, mat.emission, mat.emission_energy_multiplier])
	return looks

## Every presentation script builds in-world text only through the kit.
func _check_world_text_kit() -> void:
	var files := _scripts("res://presentation")
	_check(files.size() > 20, "The world text sweep sees the presentation scripts")
	for path: String in files:
		if path in WORLD_TEXT_KIT or path in WORLD_TEXT_PENDING: continue
		var source := FileAccess.get_file_as_string(path)
		for maker: String in ["Label3D.new()", "TextMesh.new()"]:
			_check(not source.contains(maker), "%s builds its own in-world text (%s). Use the kit: LabelBubble.create(parent, anchor, values, selected) from res://presentation/kit/label_bubble.gd for a control or place, or Badges.make(spirit) from res://presentation/kit/badges.gd for a spirit." % [path, maker])
		if source.contains("QuadMesh.new()"):
			_check(QUAD_USES.has(path), "%s builds a QuadMesh. A label plate comes with LabelBubble.create (res://presentation/kit/label_bubble.gd); a quad that carries no text goes in QUAD_USES in tests/test_dressing_lint.gd with its reason." % path)
	for path: String in WORLD_TEXT_PENDING:
		_check(FileAccess.file_exists(path), "A pending world text file still exists (drop it from WORLD_TEXT_PENDING): " + path)

func _scripts(folder: String) -> Array[String]:
	var result: Array[String] = []
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(".gd"): result.append(folder.path_join(file))
	for child: String in DirAccess.get_directories_at(folder):
		result.append_array(_scripts(folder.path_join(child)))
	return result

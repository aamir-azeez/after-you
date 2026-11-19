extends RefCounted
## World kit: how a world's water looks, held by kit/water_bodies.gd (its
## `look`) and driven only through that kit's own steps, so every world that
## hosts the water kit gets it with no code of its own. The values live in
## content/water/looks.gd; the shader is kit/water_surface.gdshader.
##
## - Each body's surface (and its walled stubs' floods) draws with one
##   ShaderMaterial: soft ripples, a soft foam band where the water meets
##   what stands in it, a shade darker as it deepens, clear enough to show the
##   seabed while thin, rings and glints.
## - The seabed: a sheet under each body that shows it (its wet cells only, so
##   it never runs under a floor), in the dressing's "seabed" style.
## - The foam reads one small edge map per body and level: the share of solid
##   ground round each spot, blurred, worked out once per stage build from the
##   water's own wet cells and the footprints of what crosses that level
##   (walls, stones, posts), and shared through kit/definition_geometry.gd.
## - Rings: what registers with ripple_from() (boats that ride the water,
##   floats) makes rings while it stands at the water; a pip only while it is
##   in or on the water at its own spot: wading, or on a stepping stone that
##   stands in it (content/water/looks.gd). The spots are worked out each
##   snapshot and written to the shader only when they change; the rings
##   themselves move in the shader.
## - Its clock moves only in advance(), so a held world or Reduce motion shows
##   still water; nothing reads TIME.
##
## Visual only: nothing here feeds a simulation, a recording, a checkpoint or
## a sound. Per frame it writes one float per material and allocates nothing.
const Looks = preload("res://content/water/looks.gd")
const SHADER := preload("res://presentation/kit/water_surface.gdshader")
const DefinitionGeometry = preload("res://presentation/kit/definition_geometry.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const Look = preload("res://presentation/kit/look.gd")
const DressingCatalog = preload("res://content/dressing/catalog.gd")
const PropStyles = preload("res://content/dressing/prop_styles.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")

## The edge map's raster (metres a cell) before it is blurred, and the mip
## of it the shader reads (1: 8 cm cells, each the share of solid in it; the
## shader reads its own mips too, for the foam's wider reach).
const RASTER := 0.04
const EDGE_MIP := 1
## The map reaches this far past the water on every side (a multiple of the
## blurrier mip's cell, so every mip is whole).
const MAP_MARGIN := 0.32
## Thin things (a post, a pile) count at least this wide, so they keep a band.
const THINNEST := 0.10
## Where a ring source looks for open water, in steps of Looks.RING_REACH.
const AROUND: Array[Vector2] = [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(0.7, 0.7), Vector2(-0.7, 0.7), Vector2(0.7, -0.7), Vector2(-0.7, -0.7)]
## Meshes looked at between two build steps while finding what stands in the water.
const MESHES_PER_STEP := 400
## A round thing marks only its rim, this wide (metres).
const RIM := 0.04
## Anything wider than this both ways is a floor or a whole-stage mesh, not
## something standing in the water.
const WIDEST := 1.0
## The seabed sheet stands this far above the seabed, clear of a pit floor's
## faces and of the walls' feet.
const BED_LIFT := 0.006
## The slope texture: pixels a side, and the noise it is made from.
const RIPPLE_PX := 128

const BASE_COLOR := &"base_color"
const EDGES := &"edges"
const EDGE_RECT := &"edge_rect"
const RIPPLES := &"ripples"
const CLOCK := &"clock"
const OFFSET := &"offset_xz"
const DEPTH := &"depth_m"
const FLOOR_ON := &"floor_on"
const DETAIL := &"detail"
const SPARKLES := &"sparkles"
const WARM := &"warm"
const LAMPS := &"lamps"
const LAMP_COUNT := &"lamp_count"
const RINGS := &"rings"
const RING_COUNT := &"ring_count"

## The world that holds the water kit (terrain, dressing, actors,
## reduced_motion, displayed_stage_id, _build_step).
var host: Node3D
## The kit's clock (seconds): moves only in advance(), unless motion is reduced.
var clock := 0.0
## Per body id: {"materials" (the sheet's and its floods'), "levels" (value ->
## level), "maps" (value -> {"texture", "image", "rect"}), "shown" (the value
## whose map is set), "footings" (value -> [[foot, top]]: the round things
## standing in the water at that level, which a pip may stand on), "floor",
## "rings", "sparkles", "bed" (node or null)}.
var bodies: Dictionary = {}
var _seabed := 0.0
var _switches: Dictionary = {}
## Things that make rings at the water: [node, strength, height (how far
## above or below the level it still does), pip (judged at its own spot)].
var _sources: Array = []
## Ring spots worked out, and the ones last written (both kept at 8 long).
var _spots := PackedVector4Array()
var _written := PackedVector4Array()
var _spot_count := 0
var _written_count := -1
var _quality := ""
var _warm := -1.0

func _init(world: Node3D) -> void:
	host = world
	_spots.resize(8)
	_written.resize(8)

## A new stage: forgets the last one's bodies and sources, and takes the
## block's add-on switches.
func start(block: Dictionary) -> void:
	bodies.clear()
	_sources.clear()
	_spot_count = 0
	_written_count = -1
	_quality = ""
	_warm = -1.0
	_seabed = float(block.get("seabed", 0.0))
	_switches = Looks.SWITCHES.duplicate()
	var asked: Variant = block.get("look", {})
	if asked is Dictionary:
		for key: String in asked:
			if _switches.has(key): _switches[key] = bool(asked[key])

## Makes `node` a source of rings while it stands at the water (within
## Looks.RING_REACH of open water and `height` of its level), until the next
## stage: the one hook boats and floats register with.
func ripple_from(node: Node3D, strength: float = 1.0, height: float = Looks.FLOAT_HEIGHT) -> void:
	_add_source(node, strength, height, false)

func _add_source(node: Node3D, strength: float, height: float, pip: bool) -> void:
	if not is_instance_valid(node): return
	for source: Array in _sources:
		if source[0] == node: return
	_sources.append([node, strength, height, pip])

## One body's surface: its material, and its seabed sheet when it shows one:
## over the body's rectangles, less `holes` (the basins standing in it).
func dress(id: String, body: Dictionary, sheet: MeshInstance3D, holes: Array) -> void:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	# Labels, faded floors and the spout draw over the water, never under it.
	material.render_priority = -2
	var color: Color = body.get("color", Color(0.25, 0.42, 0.47, 0.84))
	var tint := color.lerp(Looks.PASTEL_TINT, Looks.PASTEL)
	tint.a = color.a
	material.set_shader_parameter(BASE_COLOR, tint)
	material.set_shader_parameter(RIPPLES, ripple_texture())
	material.set_shader_parameter(EDGES, open_texture())
	material.set_shader_parameter(CLOCK, clock)
	material.set_shader_parameter(&"clear_from", Looks.CLEAR_FROM)
	material.set_shader_parameter(&"clear_to", Looks.CLEAR_TO)
	material.set_shader_parameter(&"clear_alpha", Looks.CLEAR_ALPHA)
	material.set_shader_parameter(&"deep_alpha", Looks.DEEP_ALPHA)
	var shows := {}
	for key: String in _switches: shows[key] = bool(body.get(key, _switches[key]))
	material.set_shader_parameter(FLOOR_ON, 1.0 if shows.floor else 0.0)
	material.set_shader_parameter(SPARKLES, 1.0 if shows.sparkles else 0.0)
	sheet.material_override = material
	var entry := {"materials": [material], "levels": body.get("levels", {}), "level": 0.0, "maps": {}, "footings": {}, "shown": "", "floor": shows.floor, "rings": shows.rings, "sparkles": shows.sparkles, "bed": null}
	bodies[id] = entry
	if shows.floor: entry.bed = _bed(body.get("rects", []), holes)

## The material a walled stub's flood draws with: its body's, with no edges
## (it fills a walled pit) and its own place in the plan.
func flood_material(id: String, offset: Vector2) -> Material:
	var entry: Dictionary = bodies.get(id, {})
	if entry.is_empty(): return null
	var material := (entry.materials[0] as ShaderMaterial).duplicate() as ShaderMaterial
	material.set_shader_parameter(EDGES, open_texture())
	material.set_shader_parameter(OFFSET, offset)
	entry.materials.append(material)
	return material

## A body's shown level changed: how deep it reads, and the edge map of the
## nearest of its levels.
func show_level(id: String, level: float) -> void:
	var entry: Dictionary = bodies.get(id, {})
	if entry.is_empty(): return
	entry.level = level
	for material: ShaderMaterial in entry.materials: material.set_shader_parameter(DEPTH, maxf(level - _seabed, 0.0))
	_pick_map(entry, level)

func _pick_map(entry: Dictionary, level: float) -> void:
	var maps: Dictionary = entry.maps
	if maps.is_empty(): return
	var nearest := ""
	var gap := INF
	for value: String in maps:
		var away := absf(float(entry.levels[value]) - level)
		if away < gap:
			gap = away
			nearest = value
	if nearest == entry.shown: return
	entry.shown = nearest
	var map: Dictionary = maps[nearest]
	# Floods keep their open edges: only the sheet reads the map.
	var sheet: ShaderMaterial = entry.materials[0]
	sheet.set_shader_parameter(EDGES, map.texture)
	sheet.set_shader_parameter(EDGE_RECT, map.rect)

## The edge maps of every body at each of its levels, and the lamps the glints
## warm by. Call once the walls that hold the water stand; `skip` are nodes
## of the water's own (the bodies' roots, the walled stubs' floods). Await it.
func build_edges(roots: Dictionary, skip: Array = []) -> void:
	if bodies.is_empty(): return
	var standing: Array = await _standing_boxes(roots.values() + skip)
	await host._build_step()
	for id: String in bodies:
		var root: Node3D = roots.get(id)
		var sheet := root.get_node_or_null("Water") as MeshInstance3D if is_instance_valid(root) else null
		if sheet == null or sheet.mesh == null: continue
		var entry: Dictionary = bodies[id]
		var wet := _wet_rects(sheet.mesh)
		if wet.is_empty(): continue
		var rect := _map_rect(wet)
		var done := {}
		for value: String in entry.levels:
			var level := float(entry.levels[value])
			# What crosses this level stands in the water: a box, or a round
			# thing (a stone, a post) as the disc it is.
			var solids: Array[Rect2] = []
			var rounds: Array[Rect2] = []
			var footings: Array = []
			for item: Array in standing:
				var box: AABB = item[0]
				if box.position.y >= level or box.end.y <= level: continue
				var foot := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
				if not foot.intersects(rect): continue
				(rounds if item[1] else solids).append(_at_least(foot, THINNEST))
				if item[1]: footings.append([foot, box.end.y])
			entry.footings[value] = footings
			var key := [&"water_edges", wet, rect, solids, rounds]
			if not done.has(key):
				if not DefinitionGeometry.has(key):
					DefinitionGeometry.keep(key, _edge_map(rect, wet, solids, rounds))
					await host._build_step()
				done[key] = DefinitionGeometry.kept(key)
			entry.maps[value] = done[key]
		entry.shown = ""
		_pick_map(entry, float(entry.level))
		await host._build_step()
	_set_lamps()

## Each frame the world animates: the water's clock. Allocates nothing.
func advance(delta: float) -> void:
	if bodies.is_empty() or host.reduced_motion or delta <= 0.0: return
	clock += delta
	for id: String in bodies:
		for material: ShaderMaterial in bodies[id].materials: material.set_shader_parameter(CLOCK, clock)

## Each snapshot: the graphics quality, how warm the light makes the glints,
## and where rings spread.
func present() -> void:
	if bodies.is_empty(): return
	var quality := GraphicsPolicy.normalize(host.call("graphics_quality") if host.has_method("graphics_quality") else null)
	if quality != _quality:
		_quality = quality
		_set_all(DETAIL, 1.0 if GraphicsPolicy.water_detail(quality) else 0.0)
		_written_count = -1
	var warm := float(Look.preset(str(host.call("look_name")) if host.has_method("look_name") else "").get("glints", 0.0))
	if warm != _warm:
		_warm = warm
		_set_all(WARM, warm)
	_find_spots(GraphicsPolicy.water_rings(quality))
	if _spot_count == _written_count and _spots == _written: return
	_written_count = _spot_count
	for index in range(8): _written[index] = _spots[index]
	for entry: Dictionary in bodies.values():
		for material: ShaderMaterial in entry.materials:
			material.set_shader_parameter(RINGS, _written)
			material.set_shader_parameter(RING_COUNT, _spot_count if entry.rings else 0)

## The kit's shown ring spots (x, z, phase, strength), for tests and captures.
func ring_spots() -> PackedVector4Array:
	return _written.slice(0, maxi(_written_count, 0))

func _set_all(param: StringName, value: Variant) -> void:
	for entry: Dictionary in bodies.values():
		for material: ShaderMaterial in entry.materials: material.set_shader_parameter(param, value)

## Every source standing at the water, at most `cap`, a spot each (spots
## closer than Looks.RING_MERGE share one), positions to the nearest 5 cm so a
## pip shifting on the spot writes nothing.
func _find_spots(cap: int) -> void:
	# The pips make rings too, whenever the world has made them.
	var actors: Variant = host.get("actors")
	if actors is Dictionary:
		for slot: Variant in actors:
			if actors[slot] is Node3D: _add_source(actors[slot], 0.9, 0.0, true)
	_spot_count = 0
	for index in range(8): _spots[index] = Vector4.ZERO
	for source: Array in _sources:
		if _spot_count >= cap: break
		var node: Node3D = source[0]
		if not is_instance_valid(node) or not node.visible or not node.is_inside_tree(): continue
		var at: Vector3 = host.terrain.to_local(node.global_position)
		var plan := Vector2(snappedf(at.x, 0.05), snappedf(at.z, 0.05))
		if not (_pip_in_water(at) if source[3] else _at_water(plan, at.y, float(source[2]))): continue
		var merged := false
		for index in range(_spot_count):
			if Vector2(_spots[index].x, _spots[index].y).distance_to(plan) < Looks.RING_MERGE: merged = true
		if merged: continue
		# Each spot keeps its own beat, from where it is.
		var phase := fposmod(sin(plan.x * 12.9898 + plan.y * 78.233) * 43758.5453, 1.0)
		_spots[_spot_count] = Vector4(plan.x, plan.y, phase, float(source[1]))
		_spot_count += 1

## Whether a point (terrain metres) at height y stands at the water of a body
## that shows rings: within `height` of its level and reach of open water.
func _at_water(plan: Vector2, y: float, height: float) -> bool:
	for id: String in bodies:
		var entry: Dictionary = bodies[id]
		if not entry.rings or str(entry.shown).is_empty(): continue
		if absf(y - float(entry.level)) > height: continue
		var map: Dictionary = entry.maps[entry.shown]
		for offset: Vector2 in AROUND:
			if _solid_at(map, plan + offset * Looks.RING_REACH) < 0.5: return true
	return false

## Whether a pip standing at `at` (terrain metres) is in or on the water of a
## body that shows rings, at its own spot: open water under it with its feet
## at the surface or under it, or on the top of a stone standing in the
## water not far above it (content/water/looks.gd).
func _pip_in_water(at: Vector3) -> bool:
	var plan := Vector2(at.x, at.z)
	for id: String in bodies:
		var entry: Dictionary = bodies[id]
		if not entry.rings or str(entry.shown).is_empty(): continue
		var level := float(entry.level)
		if at.y <= level + Looks.PIP_SURFACE and _solid_at(entry.maps[entry.shown], plan) < 0.5: return true
		for footing: Array in entry.footings.get(entry.shown, []):
			var top := float(footing[1])
			if absf(at.y - top) > Looks.PIP_FOOTING or top - level > Looks.PIP_RISE: continue
			# Inside its disc (an ellipse if stretched).
			var foot: Rect2 = footing[0]
			if ((plan - foot.get_center()) / (foot.size * 0.5)).length_squared() <= 1.0: return true
	return false

## The share of solid ground at a point of a map (1 off the map).
static func _solid_at(map: Dictionary, plan: Vector2) -> float:
	var image: Image = map.image
	var rect: Vector4 = map.rect
	var i := int((plan.x - rect.x) / rect.z * image.get_width())
	var j := int((plan.y - rect.y) / rect.w * image.get_height())
	if i < 0 or j < 0 or i >= image.get_width() or j >= image.get_height(): return 1.0
	return image.get_pixel(i, j).r

## The lamps of the stage's dressing (lanterns and lamp posts), at most 8: the
## glints by them warm while the light's "glints" is above 0.
func _set_lamps() -> void:
	var kinds: Array = []
	for style: Dictionary in PropStyles.SLOTS.get("lamp", {}).values(): kinds.append(str(style.get("kind", "")))
	var spots := PackedVector4Array()
	spots.resize(8)
	var count := 0
	var dressing: Variant = host.get("dressing")
	if dressing is Dictionary:
		for spec: Dictionary in DressingCatalog.stage_props(dressing, str(host.get("displayed_stage_id"))):
			if count >= 8: break
			if str(spec.get("kind", "")) not in kinds or not spec.get("at") is Array: continue
			var at := Vector2(float(spec.at[0]), float(spec.at[1])) / 100.0
			var near := false
			for index in range(count): near = near or Vector2(spots[index].x, spots[index].y).distance_to(at) < 0.3
			if near: continue
			spots[count] = Vector4(at.x, at.y, 1.0, 0.0)
			count += 1
	_set_all(LAMPS, spots)
	_set_all(LAMP_COUNT, count)

# --- Building ---

## The seabed sheet under a body's rectangles (cm) less `holes`, at the
## seabed, tiled in the dressing's style. Under a floor it stands inside the
## floor's walls, so it shows only under water and under floors on piers.
## Static: it never moves.
func _bed(rects: Array, holes: Array) -> MeshInstance3D:
	var key := [&"water_bed", rects, holes]
	if not DefinitionGeometry.has(key): DefinitionGeometry.keep(key, _bed_mesh(rects, holes))
	var mesh: Mesh = DefinitionGeometry.kept(key)
	if mesh == null: return null
	var bed := MeshInstance3D.new()
	bed.name = "Seabed"
	bed.mesh = mesh
	bed.material_override = bed_material(_seabed_style())
	bed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bed.position = Vector3(0.0, _seabed + BED_LIFT, 0.0)
	host.terrain.add_child(bed)
	return bed

## The dressing's seabed pick, or the default.
func _seabed_style() -> String:
	var dressing: Variant = host.get("dressing")
	var picked := str((dressing as Dictionary).get("seabed", "")) if dressing is Dictionary else ""
	return picked if Looks.SEABEDS.has(picked) else Looks.DEFAULT_SEABED

static func _top_triangles(mesh: Mesh) -> PackedVector3Array:
	var found := PackedVector3Array()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index in range(0, verts.size() - 2, 3):
		if normals[index].y > 0.9: found.append_array([verts[index], verts[index + 1], verts[index + 2]])
	return found

## Flat quads at 0 over `rects` (cm) less `holes`, with the floor's tiling in
## their UVs.
static func _bed_mesh(rects: Array, holes: Array) -> Mesh:
	var pieces: Array = rects.duplicate()
	for hole: Array in holes:
		var cut: Array = []
		for piece: Array in pieces:
			# Only the part of the hole inside this piece cuts it.
			var inside := [maxf(piece[0], hole[0]), maxf(piece[1], hole[1]), minf(piece[2], hole[2]), minf(piece[3], hole[3])]
			if inside[0] >= inside[2] or inside[1] >= inside[3]: cut.append(piece)
			else: cut.append_array(Primitives.rect_minus_hole(piece, inside))
		pieces = cut
	if pieces.is_empty(): return null
	var shape := SurfaceTool.new()
	shape.begin(Mesh.PRIMITIVE_TRIANGLES)
	for piece: Array in pieces:
		var a := Vector2(float(piece[0]), float(piece[1])) / 100.0
		var b := Vector2(float(piece[2]), float(piece[3])) / 100.0
		# Wound to face up (Godot draws a, b, c with (a - c) x (a - b) toward the eye).
		for corner: Vector2 in [a, Vector2(b.x, a.y), b, a, b, Vector2(a.x, b.y)]:
			shape.set_normal(Vector3.UP)
			shape.set_uv(corner / Looks.TILE_M)
			shape.add_vertex(Vector3(corner.x, 0.0, corner.y))
	return shape.commit()

## The rectangles a body's surface covers (terrain metres), from its mesh.
static func _wet_rects(mesh: Mesh) -> Array[Rect2]:
	var key := [&"water_wet", mesh]
	if DefinitionGeometry.has(key): return DefinitionGeometry.kept(key)
	var tops := _top_triangles(mesh)
	var found: Array[Rect2] = []
	for index in range(0, tops.size(), 3):
		var rect := Rect2(Vector2(tops[index].x, tops[index].z), Vector2.ZERO).expand(Vector2(tops[index + 1].x, tops[index + 1].z)).expand(Vector2(tops[index + 2].x, tops[index + 2].z))
		if rect not in found: found.append(rect)
	return DefinitionGeometry.keep(key, found)

## The map's window round the wet rectangles, on the blurrier mip's grid.
static func _map_rect(wet: Array[Rect2]) -> Rect2:
	var whole := wet[0]
	for rect: Rect2 in wet: whole = whole.merge(rect)
	var cell := RASTER * float(1 << (EDGE_MIP + 2))
	var x0 := floorf((whole.position.x - MAP_MARGIN) / cell) * cell
	var z0 := floorf((whole.position.y - MAP_MARGIN) / cell) * cell
	var x1 := ceilf((whole.end.x + MAP_MARGIN) / cell) * cell
	var z1 := ceilf((whole.end.y + MAP_MARGIN) / cell) * cell
	return Rect2(x0, z0, x1 - x0, z1 - z0)

static func _at_least(rect: Rect2, size: float) -> Rect2:
	var grow := Vector2(maxf(size - rect.size.x, 0.0), maxf(size - rect.size.y, 0.0)) * 0.5
	return Rect2(rect.position - grow, rect.size + grow * 2.0)

## Every shown mesh under the terrain that is not water (terrain space), for
## the edge maps: what crosses a level stands in the water there. Each is
## [box, round (a cylinder or a sphere)]. Await it.
func _standing_boxes(water_nodes: Array) -> Array:
	var found: Array = []
	var terrain: Node3D = host.terrain
	var into: Transform3D = terrain.global_transform.affine_inverse()
	var skip := {}
	for node: Variant in water_nodes:
		if node is Node3D: skip[node] = true
	for entry: Dictionary in bodies.values():
		if entry.bed != null: skip[entry.bed] = true
	var seen := 0
	for node: Node in terrain.find_children("*", "MeshInstance3D", true, false):
		seen += 1
		if seen % MESHES_PER_STEP == 0: await host._build_step()
		var mesh := node as MeshInstance3D
		if mesh.mesh == null: continue
		var shown := true
		var walk: Node = mesh
		while walk != terrain and walk != null:
			if skip.has(walk) or (walk is Node3D and not (walk as Node3D).visible):
				shown = false
				break
			walk = walk.get_parent()
		if not shown: continue
		# A mesh its shader places (route barriers, pair tags) is not its box,
		# and anything wide both ways is a floor the water already ends at.
		if mesh.material_override is ShaderMaterial: continue
		var box: AABB = into * (mesh.global_transform * mesh.get_aabb())
		if box.size.x > WIDEST and box.size.z > WIDEST: continue
		found.append([box, mesh.mesh is CylinderMesh or mesh.mesh is SphereMesh or mesh.mesh is CapsuleMesh])
	return found

## One edge map: solid everywhere but the wet rectangles, solid again under
## each footprint (a disc for a round one), then averaged into EDGE_MIP's
## cells (each the share of solid in it) with its own mips for the shader's
## wider reads. {"texture", "image" (the averaged cells), "rect" (Vector4 x0,
## z0, w, d)}.
static func _edge_map(rect: Rect2, wet: Array[Rect2], solids: Array[Rect2], rounds: Array[Rect2]) -> Dictionary:
	var width := roundi(rect.size.x / RASTER)
	var depth := roundi(rect.size.y / RASTER)
	var raster := Image.create(width, depth, false, Image.FORMAT_L8)
	raster.fill(Color.WHITE)
	for each: Rect2 in wet: raster.fill_rect(_cells(each, rect), Color.BLACK)
	for each: Rect2 in solids: raster.fill_rect(_cells(each, rect), Color.WHITE)
	for each: Rect2 in rounds:
		# A round thing's edge (an ellipse if stretched), a raster row at a
		# time: what the water meets is its rim, so foam rings it.
		var middle := each.get_center()
		var half := each.size * 0.5
		var inner := half - Vector2(RIM, RIM)
		var y := each.position.y + RASTER * 0.5
		while y < each.end.y:
			var t := (y - middle.y) / half.y
			var across := half.x * sqrt(maxf(1.0 - t * t, 0.0))
			var u := (y - middle.y) / maxf(inner.y, 0.001)
			var hollow := inner.x * sqrt(maxf(1.0 - u * u, 0.0)) if inner.x > 0.0 and absf(u) < 1.0 else 0.0
			if hollow <= 0.0: raster.fill_rect(_cells(Rect2(middle.x - across, y - RASTER * 0.5, across * 2.0, RASTER), rect), Color.WHITE)
			else:
				raster.fill_rect(_cells(Rect2(middle.x - across, y - RASTER * 0.5, across - hollow, RASTER), rect), Color.WHITE)
				raster.fill_rect(_cells(Rect2(middle.x + hollow, y - RASTER * 0.5, across - hollow, RASTER), rect), Color.WHITE)
			y += RASTER
	raster.generate_mipmaps()
	var from := raster.get_mipmap_offset(EDGE_MIP)
	var to := raster.get_mipmap_offset(EDGE_MIP + 1)
	var cells := Image.create_from_data(width >> EDGE_MIP, depth >> EDGE_MIP, false, Image.FORMAT_L8, raster.get_data().slice(from, to))
	var shown := cells.duplicate() as Image
	shown.generate_mipmaps()
	return {"texture": ImageTexture.create_from_image(shown), "image": cells, "rect": Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y)}

static func _cells(each: Rect2, rect: Rect2) -> Rect2i:
	var from := Vector2i(roundi((each.position.x - rect.position.x) / RASTER), roundi((each.position.y - rect.position.y) / RASTER))
	var to := Vector2i(roundi((each.end.x - rect.position.x) / RASTER), roundi((each.end.y - rect.position.y) / RASTER))
	return Rect2i(from, to - from)

# --- Shared textures (kept for the session in DefinitionGeometry) ---

## The ripple slopes: a seamless soft noise as slopes in RG (0.5 is flat).
static func ripple_texture() -> Texture2D:
	var key := [&"water_ripples", RIPPLE_PX]
	if DefinitionGeometry.has(key): return DefinitionGeometry.kept(key)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.044
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	var image := noise.get_seamless_image(RIPPLE_PX, RIPPLE_PX, false, false, 0.1, true)
	image.convert(Image.FORMAT_RGBA8)
	image.bump_map_to_normal_map(1.5)
	image.convert(Image.FORMAT_RG8)
	image.generate_mipmaps()
	return DefinitionGeometry.keep(key, ImageTexture.create_from_image(image))

## Open water with nothing standing in it: an edge map of one empty cell.
static func open_texture() -> Texture2D:
	var key := [&"water_open"]
	if DefinitionGeometry.has(key): return DefinitionGeometry.kept(key)
	var image := Image.create(1, 1, false, Image.FORMAT_L8)
	image.fill(Color.BLACK)
	return DefinitionGeometry.keep(key, ImageTexture.create_from_image(image))

## The seabed's look in a style of Looks.SEABEDS: one tile, mottled, its
## edge lined when the style has lines, with its pebbles, seamless.
static func bed_material(style: String) -> StandardMaterial3D:
	var key := [&"water_seabed", style]
	if DefinitionGeometry.has(key): return DefinitionGeometry.kept(key)
	var look: Dictionary = Looks.SEABEDS.get(style, Looks.SEABEDS[Looks.DEFAULT_SEABED])
	var px := 64
	var image := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var ground: Color = look.ground
	var light: Color = look.light
	for j in range(px):
		for i in range(px):
			var n := sin(i * 0.9 + j * 0.37) * sin(j * 0.71 - i * 0.23)
			var color := ground.lerp(light, 0.18 * maxf(n, 0.0))
			if look.has("lines") and (i < 2 or j < 2): color = look.lines
			image.set_pixel(i, j, color)
	var colors: Array = look.get("pebble_colors", [])
	# The first four lie where the board's floor had them; the rest seeded.
	var placed: Array = [[18, 22], [44, 40], [30, 52], [52, 12]]
	var random := RandomNumberGenerator.new()
	random.seed = 11
	for index in range(int(look.get("pebbles", 0))):
		var at: Array = placed[index] if index < placed.size() else [random.randi_range(0, px - 1), random.randi_range(0, px - 1)]
		var size := 3 if index < placed.size() else random.randi_range(2, 4)
		var color: Color = colors[index % colors.size()] if not colors.is_empty() else ground.darkened(0.2)
		for dj in range(-size, size + 1):
			for di in range(-size - 1, size + 2):
				if di * di + dj * dj * 2 <= size * size: image.set_pixel(posmod(int(at[0]) + di, px), posmod(int(at[1]) + dj, px), color)
	image.generate_mipmaps()
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.roughness = 0.9
	return DefinitionGeometry.keep(key, material)

extends SceneTree
## How the water looks (presentation/kit/water_look.gd), on Turn of the Tide
## and on a bare host with every add-on switched off:
## - every body and walled stub's flood draws with the water shader; a body
##   that shows its floor has a seabed sheet in the dressing's style, laid only
##   under its own water, and the open sea (its "floor": false) has none;
## - how deep it reads follows the shown level, and the foam's edge map
##   follows it: the stepping stones stand in the water at low and are under
##   it at high, and open water reads open;
## - rings spread from the moored boats and from a pip on a stepping stone at
##   half (or wading on one at high), never from a pip on a quay, a terrace
##   or a jetty at any level, at
##   most GraphicsPolicy.water_rings() spots, written only when they change;
## - the clock moves only in advance() and holds under Reduce motion;
## - with the block's add-ons off, or no floor, rings or lamps, nothing is
##   built for them and nothing fails;
## - every seabed style makes a material, and nothing in the simulation reads
##   the look.
const TideCatalog = preload("res://core/journey/stage_catalog.gd")
const JourneyCatalog = preload("res://core/journey/stage_catalog.gd")
const World = preload("res://presentation/tide_world.gd")
const WaterBodies = preload("res://presentation/kit/water_bodies.gd")
const WaterLook = preload("res://presentation/kit/water_look.gd")
const Looks = preload("res://content/water/looks.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const Dressing = preload("res://content/dressing/catalog.gd")
const SHADER := preload("res://presentation/kit/water_surface.gdshader")
var checks := 0
var failures := 0

## The least a host of the water kit gives it.
class BareHost extends Node3D:
	var terrain: Node3D
	var chapter_definition := {"islands": [], "bridges": [], "stairs": [], "stages": []}
	var reduced_motion := false
	var dressing := {}
	func _init() -> void:
		terrain = Node3D.new()
		add_child(terrain)
	func _build_step() -> void:
		pass

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var level := TideCatalog.definition("turn-of-the-tide@1")
	await _tide(level)
	await _bare()
	_styles()
	_policy()
	_visual_only()
	print("WATER LOOK: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _tide(level: Dictionary) -> void:
	var checkpoint := JourneyCatalog.initial_checkpoint(level)
	var world: Node3D = World.new()
	root.add_child(world)
	world.reduced_motion = true
	world.set_process(false)
	world.load_level(level)
	world.show_stage(level.stages[0])
	world.present_history(checkpoint)
	var waters: WaterBodies = world.waters
	var look: WaterLook = waters.look
	var seabed := waters.seabed()
	for id: String in waters.bodies:
		var sheet := (waters.bodies[id] as Node3D).get_node("Water") as MeshInstance3D
		var material := sheet.material_override as ShaderMaterial
		_check(material != null and material.shader == SHADER, "Water body %s draws with the water shader" % id)
	for flood: Dictionary in waters.floods.values():
		var fill := (flood.node as Node3D).get_child(0) as MeshInstance3D
		_check((fill.material_override as ShaderMaterial).shader == SHADER and (fill.material_override as ShaderMaterial).get_shader_parameter(&"edges") == WaterLook.open_texture(), "A walled stub's flood draws as water with no foam edges")
	# Seabeds: under the harbour and the chamber, in the dressing's style; none under the open sea.
	var style := str(world.dressing.get("seabed", ""))
	_check(style == "sand", "Turn of the Tide's dressing picks the sandy seabed")
	for id: String in ["harbour", "chamber"]:
		var bed: MeshInstance3D = look.bodies[id].bed
		_check(bed != null and bed.material_override == WaterLook.bed_material(style) and is_equal_approx(bed.position.y, seabed + WaterLook.BED_LIFT), "%s shows its seabed just above the seabed" % id)
		if bed == null: continue
		# Over the body's own rectangles, less the basins standing in it.
		var body := waters.body_data(id)
		var outside := 0
		var verts: PackedVector3Array = bed.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for index in range(0, verts.size(), 3):
			var middle := (verts[index] + verts[index + 1] + verts[index + 2]) / 3.0 * 100.0
			var mine := WaterBodies.covered(middle.x, middle.z, body.rects)
			if not bool(body.get("basin", false)) and WaterBodies.covered(middle.x, middle.z, waters.basin_rects()): mine = false
			if not mine: outside += 1
		_check(outside == 0, "%s's seabed lies under its own water and no basin's (%d)" % [id, outside])
	_check(look.bodies.sea.bed == null and _param(waters, "sea", &"floor_on") == 0.0, "The open sea switches its floor off: no seabed, its tint only")
	# Depth and edges follow the level.
	var harbour := "harbour"
	_check(is_equal_approx(_param(waters, harbour, &"depth_m"), waters.rest_level(harbour) - seabed), "The harbour reads as deep as its level stands over the seabed")
	var low_map: Variant = _param(waters, harbour, &"edges")
	var stone := _stone(world)
	var stones := Vector2(stone.x, stone.y)
	var maps: Dictionary = look.bodies[harbour].maps
	_check(maps.size() == 3, "The harbour keeps an edge map for each of its levels")
	_check(stones.is_finite(), "A stepping stone stands in the harbour")
	if stones.is_finite():
		_check(_rim(maps.low, stone) > 0.35 and _rim(maps.high, stone) < 0.1, "The stepping stones stand in the water at low (foam rings their rims) and lie under it at high: %.2f, %.2f" % [_rim(maps.low, stone), _rim(maps.high, stone)])
	var open := _open_spot(maps.high)
	_check(open.is_finite() and WaterLook._solid_at(maps.high, open) < 0.05, "Open water reads open in the edge map")
	waters.set_level(harbour, float(waters.levels_of(harbour).high), true)
	_check(is_equal_approx(_param(waters, harbour, &"depth_m"), float(waters.levels_of(harbour).high) - seabed) and _param(waters, harbour, &"edges") != low_map, "At high the harbour reads deeper and its foam follows the high edges")
	waters.set_level(harbour, float(waters.levels_of(harbour).low), true)
	# Rings: the moored boats ride the water.
	look.present()
	var spots := look.ring_spots()
	var boats := 0
	for boat: Node3D in world._boats:
		for spot: Vector4 in spots:
			if Vector2(spot.x, spot.y).distance_to(Vector2(boat.position.x, boat.position.z)) < 0.06: boats += 1
	_check(world._boats.size() > 0 and boats == world._boats.size(), "Rings spread from every moored boat (%d of %d)" % [boats, world._boats.size()])
	_check(_param(waters, harbour, &"ring_count") == spots.size(), "The harbour's shader gets the ring spots")
	var written: Variant = _param(waters, harbour, &"rings")
	look.present()
	_check(is_same(_param(waters, harbour, &"rings"), written), "Spots that did not change are not written again")
	# A pip spreads rings only in or on the water: on a stepping stone at half
	# (the board's frame), whose top stands as far above the water as the
	# terrace floor beside it, or wading on one under the water at high. Never
	# on a quay or a terrace beside the water or on a jetty over it, at any
	# level; far above the water, none.
	var pip: Node3D = world.actors.values()[0]
	var kept := pip.global_position
	var top := _stone_top(world)
	# Spots (cm) just inside each floor's edge, open harbour within reach.
	var dry := {"on the west quay beside the water": [-132, -254, _height(level, "w-quay")],
		"on the west terrace beside the water": [-132, 100, _height(level, "w-terrace")],
		"on the first jetty over the water": [-64, -352, _height(level, "jetty-1")]}
	for value: String in ["low", "half", "high"]:
		waters.set_level(harbour, float(waters.levels_of(harbour)[value]), true)
		pip.global_position = kept + Vector3(0, 5.0, 0)
		look.present()
		var none := look.ring_spots().size()
		for where: String in dry:
			var at: Array = dry[where]
			pip.global_position = world.terrain.to_global(Vector3(at[0] / 100.0, at[2], at[1] / 100.0))
			look.present()
			_check(look.ring_spots().size() == none, "A pip %s at %s spreads no rings: %s" % [where, value, look.ring_spots()])
		pip.global_position = world.terrain.to_global(Vector3(stones.x, top, stones.y)) if stones.is_finite() else kept
		look.present()
		var on_stone := false
		for spot: Vector4 in look.ring_spots(): on_stone = on_stone or Vector2(spot.x, spot.y).distance_to(stones) < 0.06
		# At high the stones lie under the water, so a pip on one wades.
		if value == "low": _check(not on_stone, "A pip on a stepping stone at low, far above the water, spreads none")
		else: _check(look.ring_spots().size() == none + 1 and on_stone, "A pip on a stepping stone at %s spreads rings: %s" % [value, look.ring_spots()])
	pip.global_position = kept + Vector3(0, 5.0, 0)
	look.present()
	_check(look.ring_spots().size() == spots.size(), "A pip far above the water spreads none")
	pip.global_position = kept
	waters.set_level(harbour, float(waters.levels_of(harbour).low), true)
	# The low quality draws at most four spots.
	world.apply_graphics_quality("low")
	look.present()
	_check(look.ring_spots().size() <= 4 and _param(waters, harbour, &"detail") == 0.0, "Low draws one ripple layer and at most four ring spots")
	world.apply_graphics_quality("balanced")
	look.present()
	_check(_param(waters, harbour, &"detail") == 1.0, "Balanced draws both ripple layers again")
	# The clock moves only with the world, never under Reduce motion.
	var before := look.clock
	waters.advance(0.5)
	_check(look.clock == before, "Under Reduce motion the water holds still")
	world.reduced_motion = false
	waters.advance(0.5)
	_check(is_equal_approx(look.clock, before + 0.5) and is_equal_approx(_param(waters, harbour, &"clock"), look.clock), "The water's clock moves with the world's frames")
	# Dusk warms the glints by the lamps.
	_check(_param(waters, harbour, &"warm") == float(preload("res://presentation/kit/look.gd").preset(world.look_name()).get("glints", 0.0)), "The glints are as warm as the light says")
	_check(int(_param(waters, harbour, &"lamp_count")) > 0, "The harbour's lamps warm the glints near them")
	world.queue_free()
	await process_frame

## A stepping stone in the harbour: its middle (terrain metres) and its
## radius, or NaN.
func _stone(world: Node3D) -> Vector3:
	for node: Node in world.terrain.find_children("SteppingStone*", "MeshInstance3D", true, false):
		var stone := node as MeshInstance3D
		if not stone.is_visible_in_tree() and not stone.visible: continue
		var at: Vector3 = world.terrain.to_local(stone.global_position)
		if world.waters.body_of([int(at.x * 100.0) - 1, int(at.z * 100.0) - 1, int(at.x * 100.0) + 1, int(at.z * 100.0) + 1]) != "harbour": continue
		return Vector3(at.x, at.z, (stone.mesh as CylinderMesh).bottom_radius)
	return Vector3(NAN, NAN, NAN)

## The top (terrain metres) of the stepping stone _stone() finds, or NaN.
func _stone_top(world: Node3D) -> float:
	var found := _stone(world)
	for node: Node in world.terrain.find_children("SteppingStone*", "MeshInstance3D", true, false):
		var stone := node as MeshInstance3D
		var at: Vector3 = world.terrain.to_local(stone.global_position)
		if Vector2(at.x, at.z).distance_to(Vector2(found.x, found.y)) < 0.01: return at.y + (stone.mesh as CylinderMesh).height * 0.5
	return NAN

## A floor or crossing's walking height (metres) in the definition.
func _height(level: Dictionary, id: String) -> float:
	for item: Dictionary in level.islands + level.bridges:
		if item.id == id: return float(item.get("height_cm", 0)) / 100.0
	return NAN

## The most solid share round a stone's rim in a map.
func _rim(map: Dictionary, stone: Vector3) -> float:
	var most := 0.0
	for k in range(8):
		var angle := TAU * float(k) / 8.0
		most = maxf(most, WaterLook._solid_at(map, Vector2(stone.x, stone.y) + Vector2(cos(angle), sin(angle)) * stone.z))
	return most

func _open_spot(map: Dictionary) -> Vector2:
	var image: Image = map.image
	var rect: Vector4 = map.rect
	for j in range(image.get_height()):
		for i in range(image.get_width()):
			if image.get_pixel(i, j).r == 0.0:
				var ok := true
				for dj in range(-2, 3):
					for di in range(-2, 3):
						ok = ok and image.get_pixel(clampi(i + di, 0, image.get_width() - 1), clampi(j + dj, 0, image.get_height() - 1)).r == 0.0
				if ok: return Vector2(rect.x + (i + 0.5) * rect.z / image.get_width(), rect.y + (j + 0.5) * rect.w / image.get_height())
	return Vector2(NAN, NAN)

func _param(waters: WaterBodies, id: String, name: StringName) -> Variant:
	var sheet := (waters.bodies[id] as Node3D).get_node("Water") as MeshInstance3D
	return (sheet.material_override as ShaderMaterial).get_shader_parameter(name)

## A water block with every add-on off, on a host with no dressing, lamps or pips.
func _bare() -> void:
	var host := BareHost.new()
	root.add_child(host)
	var block := {"seabed": -0.5, "rate": 1.0, "wall_top": 0.4, "inset": 0, "bounds": [-500, -500, 500, 500],
		"bodies": [{"id": "pond", "node": "Pond", "selector": "", "rest": "still", "rects": [[-300, -200, 300, 200]], "levels": {"still": 0.0}, "color": Color(0.3, 0.5, 0.5, 0.85)}],
		"marks": {}, "stone": Color.GRAY, "coping": Color.GRAY, "pit_floor": Color.GRAY, "plinth": Color.GRAY, "fender": Color.GRAY, "piers": [],
		"look": {"floor": false, "rings": false, "sparkles": false}}
	var waters := WaterBodies.new(host)
	waters.start({}, block)
	await waters.build_bodies()
	await waters.look.build_edges(waters.bodies)
	var pond: Node3D = waters.bodies.pond
	var material := (pond.get_node("Water") as MeshInstance3D).material_override as ShaderMaterial
	_check(waters.look.bodies.pond.bed == null and host.terrain.find_children("Seabed", "", true, false).is_empty() and material.get_shader_parameter(&"floor_on") == 0.0 and material.get_shader_parameter(&"sparkles") == 0.0, "A block that switches its add-ons off builds no seabed and draws no glints")
	var boat := Node3D.new()
	host.terrain.add_child(boat)
	waters.ripple_from(boat)
	waters.occupy(PackedVector2Array(), {}, true)
	_check(int(material.get_shader_parameter(&"ring_count")) == 0, "A block with rings off draws none, even with a float on it")
	_check(int(material.get_shader_parameter(&"lamp_count")) == 0, "No dressing, no lamps: the glints stay cool")
	_check(WaterLook._solid_at(waters.look.bodies.pond.maps.still, Vector2.ZERO) < 0.05, "The middle of a plain pond reads open water")
	waters.advance(0.25)
	_check(is_equal_approx(waters.look.clock, 0.25), "A bare host's water still moves with its frames")
	# Turned back on with no floor under the dressing: the default sand.
	block.look = {}
	waters.start({}, block)
	await waters.build_bodies()
	_check(waters.look.bodies.pond.bed != null and waters.look.bodies.pond.bed.material_override == WaterLook.bed_material(Looks.DEFAULT_SEABED), "With no seabed pick, a floor shows the default sand")
	host.queue_free()
	await process_frame

func _styles() -> void:
	var seen := {}
	for style: String in Looks.SEABEDS:
		var material := WaterLook.bed_material(style)
		_check(material.albedo_texture != null and material.albedo_texture.get_width() == 64, "Seabed style %s makes its tile" % style)
		seen[material] = true
	_check(seen.size() == Looks.SEABEDS.size(), "Each seabed style looks its own")
	_check(Looks.SEABEDS.keys() == preload("res://content/dressing/prop_styles.gd").SLOTS.seabed.keys(), "The seabed look slot offers exactly the styles the water has")

func _policy() -> void:
	_check(GraphicsPolicy.water_rings("low") == 4 and GraphicsPolicy.water_rings("balanced") == 8 and GraphicsPolicy.water_rings("high") == 8, "Low draws four ring spots, the rest eight")
	_check(not GraphicsPolicy.water_detail("low") and GraphicsPolicy.water_detail("balanced"), "Low leaves out the second ripple layer")

## Nothing in the simulation, recordings or checkpoints reads the look.
func _visual_only() -> void:
	var found: Array = []
	for folder: String in ["res://core", "res://services"]:
		_walk(folder, found)
	_check(found.is_empty(), "Only presentation reads the water look: %s" % [found])

func _walk(path: String, found: Array) -> void:
	for name: String in DirAccess.get_directories_at(path): _walk(path.path_join(name), found)
	for name: String in DirAccess.get_files_at(path):
		if not name.ends_with(".gd"): continue
		var source := FileAccess.get_file_as_string(path.path_join(name))
		if "load(\"res://presentation/kit/water_look.gd\")" in source or "load(\"res://content/water/looks.gd\")" in source: found.append(path.path_join(name))

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

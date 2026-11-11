extends RefCounted
## World kit: a world's moving water, built from the chapter's water block
## (the descriptor's "water" file under content/water/). Everything a body of
## water needs comes from that data and the chapter definition: the water
## itself, the parapets on every floor edge that faces it, the sea walls where
## it ends in view, the walls round every crossing it can stand over while
## open (with a flood in a walled stub while it is shut), and the locks
## (kit/water_locks.gd) at every opening, from the same plan. Visual only:
## nothing here feeds back into a simulation, a recording or a checkpoint.
##
## Each body is one mesh of its surface and the outer faces of its sides,
## under a root that moves and stretches with the level, so the water always
## reaches down to the seabed. No face stands inside the water, where it would
## show through the surface as a band. Meshes and wall layouts depend only on
## the definition and the block, so they are worked out once per definition and
## shared (kit/definition_geometry.gd).
##
## The kit is a helper the world holds, never a node, and has no _process:
## everything it builds sits under the world's terrain, and the world calls it
## from its own build, present and frame steps, in this order:
##   start(stage, block, standing)  before the shared stage build (crossings read walled)
##   await build_bodies()       after the floors
##   await build_walls()        parapets, sea walls, walled crossings and floods
##   holds_water(node)          any wall of the world's own that holds water back
##   await build_locks(path)    last: the doors, spillways and walls at openings
##   present_controls(...)      each snapshot: where each body is going
##   show_floods(decks)         each snapshot, once the decks show or hide
##   occupy(spirits, routes)    each snapshot: walls fade, doors dip
##   advance(delta)             each frame: water, then doors, then fading walls
## A staged build gives the frame back through the world's _build_step.
const Primitives = preload("res://presentation/kit/primitives.gd")
const DefinitionGeometry = preload("res://presentation/kit/definition_geometry.gd")
const WaterLocks = preload("res://presentation/kit/water_locks.gd")
const WallFade = preload("res://presentation/kit/wall_fade.gd")
## Water grid lines worked out between two build steps.
const LINES_PER_STEP := 8
## Wall layout samples (4 cm apart) worked out between two build steps.
const WALL_SAMPLES_PER_STEP := 48

## The world that holds the kit: its terrain, chapter_definition,
## reduced_motion and _build_step.
var host: Node3D
## The chapter's water block; {} when it has none.
var water: Dictionary = {}
## Each body's root by body id, built for the shown stage. Its metas: "target"
## (the level it is going to), "shown" (where it stands this frame) and, while
## a closing crossing paces it, "rate".
var bodies: Dictionary = {}
## Crossings that may be open while their water stands above the deck: walled
## and kept out of the water, a sealed pit that stays dry (a walled stub floods
## while shut). Worked out by start(), before the shared stage build.
var walled: Array[String] = []
## Of those, the crossings walled only because they can be kept (entered while
## open, so walked later even when the water covers them).
var kept_walled: Array[String] = []
## Walled stubs read covered while shut: id -> {"node" (a unit box of the water
## it sits in, stretched from the seabed to that water's level), "body" (that
## water's root), "water" (its body id), "key" (its pit's area id in the plan)}.
var floods: Dictionary = {}
## Every wall built to hold water back (terrain space), for the locks' plan.
var walls: Array[AABB] = []
## What holds the water at each opening in the shown stage.
var locks: WaterLocks
## Clears the walls in front of a spirit on a walled stub.
var fade: WallFade
var _stage: Dictionary = {}
## Crossings that stand in the water as they are, never walled (stepping
## stones, under water when it rises over them).
var _standing: Array = []
## The levels the locks read, refilled in place (lock_levels).
var _lock_targets: Dictionary = {}
var _lock_shown: Dictionary = {}
## Things that ride a body's level: [body id, Callable(level)].
var _riders: Array = []

func _init(world: Node3D) -> void:
	host = world

# --- Data ---

## Starts a stage: forgets the last stage's water and works out which
## crossings it walls. `standing`: crossings that stand in the water as they
## are (stepping stones), never walled. Call before the shared stage build,
## which reads walled.
func start(stage: Dictionary, block: Dictionary, standing: Array = []) -> void:
	water = block
	_stage = stage
	_standing = standing
	bodies.clear()
	floods.clear()
	walls.clear()
	_riders.clear()
	locks = null
	fade = WallFade.new()
	walled.clear()
	kept_walled.clear()
	if water.is_empty(): return
	walled = _walled_routes(stage)
	kept_walled = _keepable_routes(stage, walled)
	walled.append_array(kept_walled)

func seabed() -> float:
	return float(water.get("seabed", 0.0))

func wall_top() -> float:
	return float(water.get("wall_top", 0.0))

func body_data(id: String) -> Dictionary:
	for body: Dictionary in water.get("bodies", []):
		if str(body.id) == id: return body
	return {}

## A body's levels by value, as the block gives them.
func levels_of(id: String) -> Dictionary:
	return body_data(id).get("levels", {})

## The level a body rests at while no control moves it.
func rest_level(id: String) -> float:
	var body := body_data(id)
	return float(body.levels[body.rest])

## The levels the walls carry marks for: the first body's.
func mark_levels() -> Dictionary:
	var all: Array = water.get("bodies", [])
	return {} if all.is_empty() else all[0].levels

## The highest any body ever stands.
func highest() -> float:
	var top := -INF
	for body: Dictionary in water.get("bodies", []):
		for level: float in body.levels.values(): top = maxf(top, level)
	return top

## Rectangles of the bodies that stand in walls of their own (a basin): cut
## out of every other body, and never walled by parapets.
func basin_rects() -> Array:
	var found: Array = []
	for body: Dictionary in water.get("bodies", []):
		if bool(body.get("basin", false)): found.append_array(body.rects)
	return found

## The bodies that are not basins, in block order.
func open_bodies() -> Array:
	return water.get("bodies", []).filter(func(body: Dictionary) -> bool: return not bool(body.get("basin", false)))

## The body (never a basin) a rectangle's centre lies strictly inside: its id,
## or "" when none.
func body_of(rect: Array) -> String:
	return body_at(water, rect)

## body_of for a water block.
static func body_at(block: Dictionary, rect: Array) -> String:
	var x := float(rect[0] + rect[2]) * 0.5
	var z := float(rect[1] + rect[3]) * 0.5
	for body: Dictionary in block.get("bodies", []):
		if bool(body.get("basin", false)): continue
		for region: Array in body.rects:
			if _inside([x, z], region): return str(body.id)
	return ""

## Every height each body can stand at in the shown stage: each value of the
## control that moves it, or where it rests while no control here does.
## {body id: {value: level}}.
func water_levels() -> Dictionary:
	var controls: Array = []
	for control: Dictionary in _stage.get("controls", []): controls.append(str(control.get("id", "")))
	var found := {}
	for body: Dictionary in water.get("bodies", []):
		found[str(body.id)] = body.levels if str(body.selector) in controls else {str(body.rest): body.levels[body.rest]}
	return found

static func _inside(at: Array, rect: Array) -> bool:
	return float(at[0]) > float(rect[0]) and float(at[0]) < float(rect[2]) and float(at[1]) > float(rect[1]) and float(at[1]) < float(rect[3])

## Whether a point (cm) lies in one of `regions`, edges included.
static func covered(x: float, z: float, regions: Array) -> bool:
	for region: Array in regions:
		if x >= region[0] and x <= region[2] and z >= region[1] and z <= region[3]: return true
	return false

static func low_cm(route: Dictionary) -> int:
	if route.has("axis"): return mini(int(route.from_height_cm), int(route.to_height_cm))
	return int(route.get("height_cm", 0))

static func is_stub(route: Dictionary) -> bool:
	return str(route.get("to_surface", "")) == str(route.get("id", ""))

static func gate_for_stage(stage: Dictionary, id: String) -> Dictionary:
	for item: Dictionary in stage.get("gates", []):
		if item.route_id == id: return item
	return {}

## Values a predicate needs outright (through "all" only) of one control.
static func control_marks(predicate: Dictionary, control: String) -> Array:
	var found: Array = []
	if str(predicate.get("control_id", "")) == control: found.append(str(predicate.get("value", "")))
	for child: Dictionary in predicate.get("all", []):
		for value: String in control_marks(child, control):
			if value not in found: found.append(value)
	return found

func _route(id: String) -> Dictionary:
	var definition: Dictionary = host.chapter_definition
	for route: Dictionary in definition.get("bridges", []) + definition.get("stairs", []):
		if route.id == id: return route
	return {}

func _stands_in_water(route: Dictionary) -> bool:
	return str(route.id) in _standing

## Crossings in this stage that can stand open while their water rises above
## the deck: every always-open crossing below the water's highest level, and
## every gated one whose gate does not tie it to values of its water's control
## that leave its deck dry. Never one standing in the water.
func _walled_routes(stage: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var definition: Dictionary = host.chapter_definition
	for route: Dictionary in definition.get("bridges", []) + definition.get("stairs", []):
		if _stands_in_water(route): continue
		var body := body_data(body_of(route.rect_cm))
		if body.is_empty(): continue
		var levels: Dictionary = body.levels
		var low := float(low_cm(route)) / 100.0
		var top := -INF
		for level: float in levels.values(): top = maxf(top, level)
		if low >= top: continue
		var gate := gate_for_stage(stage, str(route.id))
		if gate.is_empty(): continue
		var marks := control_marks(gate.get("when", {}), str(body.selector))
		var dry := not marks.is_empty()
		for value: String in marks:
			if float(levels[value]) >= low: dry = false
		if not dry: result.append(str(route.id))
	return result

## Crossings that can be kept (entered while open in this stage or an earlier
## one, so walked later even when the water covers them) whose deck this
## stage's water can stand over, not already walled: walled too, so a kept one
## walked under the water's level stays dry behind its walls.
func _keepable_routes(stage: Dictionary, already: Array[String]) -> Array[String]:
	var definition: Dictionary = host.chapter_definition
	var latched: Array = []
	for earlier: Dictionary in definition.get("stages", []):
		latched.append_array(earlier.get("entry_latch_routes", []))
		if str(earlier.get("id", "")) == str(stage.get("id", "")): break
	# The water this stage can show: a body moves only if its control is here.
	var controls: Array = []
	for control: Dictionary in stage.get("controls", []): controls.append(str(control.id))
	var result: Array[String] = []
	for route: Dictionary in definition.get("bridges", []):
		var id := str(route.id)
		if id in already or id not in latched or _stands_in_water(route): continue
		var body := body_data(body_of(route.rect_cm))
		var gate := gate_for_stage(stage, id)
		if body.is_empty() or (not gate.is_empty() and gate.get("when", {}).is_empty()): continue
		var shown: Array = body.levels.values() if str(body.selector) in controls else [body.levels[body.rest]]
		var high := -INF
		for level: float in shown: high = maxf(high, level)
		if high > float(low_cm(route)) / 100.0: result.append(id)
	return result

# --- Bodies ---

## Every body of the block, in its order, each at the level it rests at. A
## body that is not a basin leaves out every island, every basin and every
## walled crossing; a basin leaves out only the islands. Await it.
func build_bodies() -> void:
	var islands: Array = host.chapter_definition.get("islands", []).map(func(island: Dictionary) -> Array: return island.rect_cm)
	var cut: Array = basin_rects()
	for id: String in walled: cut.append(_route(id).rect_cm)
	for body: Dictionary in water.get("bodies", []):
		var root := await build_body(str(body.node), body.rects, ([] if bool(body.get("basin", false)) else cut) + islands, body.color)
		# Shown before it is listed: nothing rides a body while it is built.
		root.set_meta("target", rest_level(str(body.id)))
		_show(root, rest_level(str(body.id)))
		bodies[str(body.id)] = root
		await host._build_step()

## One body of water named `name` over `regions` ([x0, z0, x1, z1] cm), minus
## every rectangle of `holes`, coloured `color`, under the world's terrain. The
## sides that face the camera (east and south) stop the block's "inset" short
## of each hole and of the end of the body: inside the wall that holds the
## water back, or behind the sea wall past it, and never on a wall's inner
## face, where the two would fight over the same pixels. Returns its root.
## Await it.
func build_body(name: String, regions: Array, holes: Array, color: Color) -> Node3D:
	var inset := int(water.get("inset", 0))
	var cut: Array = []
	for rect: Array in holes: cut.append([int(rect[0]) - inset, int(rect[1]) - inset, rect[2], rect[3]])
	var key := [&"water_surface", regions, cut, inset]
	if not DefinitionGeometry.has(key): DefinitionGeometry.keep(key, await _surface(regions, cut, inset))
	var mesh: Mesh = DefinitionGeometry.kept(key)
	var root := Node3D.new()
	root.name = name
	host.terrain.add_child(root)
	if mesh != null:
		var surface := Primitives.fresh_material(color, 0.35)
		# Labels, faded floors and the spout draw over the water, never under it.
		surface.render_priority = -2
		var sheet := Primitives.mesh_node(mesh, surface, Vector3.ZERO, root)
		sheet.name = "Water"
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root

## The mesh of a body's surface and outer sides (see build_body), or null when
## it has no face. A staged build gets the frame back between grid lines. Await it.
func _surface(regions: Array, holes: Array, inset: int) -> Mesh:
	var xs: Array = []
	var zs: Array = []
	for rect: Array in regions + holes:
		for x: int in [rect[0], rect[2]]:
			if x not in xs: xs.append(x)
		for z: int in [rect[1], rect[3]]:
			if z not in zs: zs.append(z)
	for region: Array in regions:
		if int(region[2]) - inset not in xs: xs.append(int(region[2]) - inset)
		if int(region[3]) - inset not in zs: zs.append(int(region[3]) - inset)
	xs.sort()
	zs.sort()
	# wet[zi][xi]: whether the cell between those grid lines holds water. A cell
	# within `inset` of where the body ends to its east or south stays dry.
	var wet: Array = []
	for zi in range(zs.size() - 1):
		if zi % LINES_PER_STEP == 0: await host._build_step()
		var row: Array[bool] = []
		for xi in range(xs.size() - 1):
			var east := float(xs[xi + 1] + inset)
			var south := float(zs[zi + 1] + inset)
			var x := float(xs[xi] + xs[xi + 1]) * 0.5
			var z := float(zs[zi] + zs[zi + 1]) * 0.5
			row.append(_wet(x, z, regions, holes) and covered(east, z, regions) and covered(x, south, regions) and covered(east, south, regions))
		wet.append(row)
	var shape := SurfaceTool.new()
	shape.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := 0
	# The surface, one quad per run of wet cells along each row.
	for zi in range(wet.size()):
		if zi % LINES_PER_STEP == 0: await host._build_step()
		var start := -1
		for xi in range(xs.size()):
			var here: bool = xi < xs.size() - 1 and wet[zi][xi]
			if here and start < 0: start = xi
			if not here and start >= 0:
				var x0 := float(xs[start]) / 100.0
				var x1 := float(xs[xi]) / 100.0
				var z0 := float(zs[zi]) / 100.0
				var z1 := float(zs[zi + 1]) / 100.0
				_quad(shape, [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)], Vector3.UP)
				faces += 1
				start = -1
	# Sides only where water meets something else, merged along each grid line.
	for along_x: bool in [true, false]:
		var lines: Array = zs if along_x else xs
		var cells: Array = xs if along_x else zs
		for line in range(lines.size()):
			if line % LINES_PER_STEP == 0: await host._build_step()
			var start := 0
			var facing := 0
			for cell in range(cells.size()):
				var side := 0
				if cell < cells.size() - 1:
					var before: bool = line > 0 and (wet[line - 1][cell] if along_x else wet[cell][line - 1])
					var after: bool = line < lines.size() - 1 and (wet[line][cell] if along_x else wet[cell][line])
					side = 1 if before and not after else -1 if after and not before else 0
				if side == facing: continue
				if facing != 0:
					var at := float(lines[line]) / 100.0
					var a := float(cells[start]) / 100.0
					var b := float(cells[cell]) / 100.0
					if along_x: _quad(shape, [Vector3(a, -1, at), Vector3(b, -1, at), Vector3(b, 0, at), Vector3(a, 0, at)], Vector3(0, 0, facing))
					else: _quad(shape, [Vector3(at, -1, a), Vector3(at, -1, b), Vector3(at, 0, b), Vector3(at, 0, a)], Vector3(facing, 0, 0))
					faces += 1
				start = cell
				facing = side
	return shape.commit() if faces > 0 else null

## One flat quad of water, its corners in order round it, wound to face along
## `normal` (Godot draws a triangle a, b, c whose (a - c) x (a - b) faces the eye).
static func _quad(shape: SurfaceTool, corners: Array, normal: Vector3) -> void:
	var a: Vector3 = corners[0]
	var b: Vector3 = corners[1]
	var c: Vector3 = corners[2]
	if (a - c).cross(a - b).dot(normal) < 0.0: corners.reverse()
	for index: int in [0, 1, 2, 0, 2, 3]:
		shape.set_normal(normal)
		shape.add_vertex(corners[index])

static func _wet(x: float, z: float, regions: Array, holes: Array) -> bool:
	var inside := false
	for region: Array in regions:
		if x > region[0] and x < region[2] and z > region[1] and z < region[3]: inside = true
	if not inside: return false
	for hole: Array in holes:
		if x > hole[0] and x < hole[2] and z > hole[1] and z < hole[3]: return false
	return true

# --- Levels ---

## Calls `follow` with a body's level whenever its shown level changes: a
## boat that rides the water, a mast that keeps clear of it. Riders last until
## the next start(). A rider that `sways` (a boat bobbing) is also called by
## bob() each frame the world animates.
func ride(body: String, follow: Callable, sways: bool = false) -> void:
	_riders.append([body, follow, sways])

## Calls every swaying rider with its body's shown level.
func bob() -> void:
	for rider: Array in _riders:
		if not rider[2]: continue
		var root: Node3D = bodies.get(rider[0])
		if is_instance_valid(root): (rider[1] as Callable).call(float(root.get_meta("shown")))

## Where each body heads from a snapshot's controls: the level of its
## control's value, or where it rests while no control names one.
func present_controls(controls: Dictionary, immediate: bool) -> void:
	for body: Dictionary in water.get("bodies", []):
		var levels: Dictionary = body.levels
		set_level(str(body.id), float(levels.get(str(controls.get(str(body.selector), str(body.rest))), levels[body.rest])), immediate)

func set_level(id: String, level: float, immediate: bool) -> void:
	var root: Node3D = bodies.get(id)
	if not is_instance_valid(root): return
	root.set_meta("target", level)
	if immediate or host.reduced_motion: _show(root, level)

func _show(root: Node3D, level: float) -> void:
	root.set_meta("shown", level)
	root.position.y = level
	root.scale.y = maxf(level - seabed(), 0.02)
	var id := ""
	for key: String in bodies:
		if bodies[key] == root: id = key
	for rider: Array in _riders:
		if rider[0] == id: (rider[1] as Callable).call(level)
	for flood: String in floods:
		if floods[flood].body == root: _fill(floods[flood], level)

## Stretches a flood from the seabed to its water's `level`, as _show does a body.
func _fill(flood: Dictionary, level: float) -> void:
	(flood.node as Node3D).position.y = level
	(flood.node as Node3D).scale.y = maxf(level - seabed(), 0.02)

## Tide rules: while a crossing closes (route id -> ticks left before it shuts,
## from the snapshot), the water still moving slows to reach its new level as
## the crossing shuts, so the warning is the water rising over it; nothing
## closing, it moves at the block's rate.
func pace_closing(closing: Dictionary) -> void:
	for root: Node3D in bodies.values():
		if not is_instance_valid(root): continue
		var shown := float(root.get_meta("shown"))
		var target := float(root.get_meta("target"))
		var rate := INF
		for id: String in closing:
			var deck := float(_route(id).get("height_cm", 0)) / 100.0
			if shown < deck and deck <= target: rate = minf(rate, (deck - shown) / (maxf(float(closing[id]), 1.0) / 30.0))
		if rate < INF: root.set_meta("rate", maxf(rate, 0.01))
		elif root.has_meta("rate"): root.remove_meta("rate")

## Moves every body toward its target, then the doors against the water shown
## this frame, then the fading walls. Returns whether any water flowed. Only
## work that moves: a resting harbour does none.
func advance(delta: float) -> bool:
	var flowing := false
	for root: Node3D in bodies.values():
		if not is_instance_valid(root): continue
		var target := float(root.get_meta("target"))
		var shown := float(root.get_meta("shown"))
		if not is_equal_approx(shown, target):
			_show(root, move_toward(shown, target, float(root.get_meta("rate", float(water.get("rate", 1.0)))) * maxf(delta, 0.0)))
			flowing = true
		elif root.has_meta("rate"): root.remove_meta("rate")
	# The doors move after the water, against the water shown this frame.
	if is_instance_valid(locks) and (flowing or locks.moving()): locks.advance(delta, lock_levels("shown"))
	return flowing

## Fading walls ease toward their targets (call it each frame, after the water).
func advance_fade(delta: float) -> void:
	if fade != null and fade.moving(): fade.advance(delta)

# --- Walls ---

## Parapets on every floor edge that faces water, sea walls where water ends in
## view, then the walls round every walled crossing. Await it.
func build_walls() -> void:
	await _build_parapets()
	await host._build_step()
	await _build_sea_walls()
	await host._build_step()
	await _build_route_walls()

## A wall that holds water back, for the locks' plan. Every wall's parent sits
## at the terrain's origin, so its own transform places it.
func holds_water(wall: MeshInstance3D) -> void:
	walls.append(wall.transform * wall.get_aabb())

func _box(size: Vector3, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	return Primitives.mesh_node(Primitives.cached_box(size), Primitives.shared_material(color), at, parent)

## Bands at every water mark between `bottom` and `top` (world heights) around a
## wall block of `footprint` (metres) centred at `center` (world), under
## `parent` whose origin is `origin_y` above the ground. A wall run along x (or
## z) keeps its bands a little short of its own ends, clear of the walls it meets.
func mark_bands(center: Vector3, footprint: Vector2, bottom: float, top: float, parent: Node3D, origin_y: float = 0.0, run_along: int = -1) -> void:
	var grow := Vector2(-0.008 if run_along == 0 else 0.05, -0.008 if run_along == 1 else 0.05)
	var levels := mark_levels()
	var colors: Dictionary = water.get("marks", {})
	for value: String in colors:
		var level: float = levels[value]
		if level <= bottom + 0.03 or level >= top - 0.03: continue
		var band := _box(Vector3(footprint.x + grow.x, 0.036, footprint.y + grow.y), colors[value], Vector3(center.x, level - 0.012 - origin_y, center.z), parent)
		band.name = "WaterMark_" + value
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## A wall piece along one edge: [from, to] in cm along the edge, short of
## each end by `trim` cm so it never shares a face with what it meets.
func _edge_box(run: Array, edge: float, outward: float, along_x: bool, thickness: float, bottom: float, top: float, color: Color, parent: Node3D, trim: float = 0.0) -> MeshInstance3D:
	var length := float(run[1] - run[0] - 2.0 * trim) / 100.0
	var middle := float(run[0] + run[1]) / 200.0
	var off := edge / 100.0 + outward * thickness * 0.5
	var size := Vector3(length, top - bottom, thickness) if along_x else Vector3(thickness, top - bottom, length)
	var at := Vector3(middle, (top + bottom) * 0.5, off) if along_x else Vector3(off, (top + bottom) * 0.5, middle)
	return _box(size, color, at, parent)

## A stone wall from `bottom` to the block's wall top with a coping stone,
## both holding water, and the water marks along it.
func _capped_wall(run: Array, edge: float, outward: float, along_x: bool, thickness: float, bottom: float, parent: Node3D, trim: float, name: String, coping_name: String) -> Array[MeshInstance3D]:
	var top := wall_top()
	var wall := _edge_box(run, edge, outward, along_x, thickness, bottom, top, water.stone, parent, trim)
	wall.name = name
	var coping := _edge_box(run, edge, outward, along_x, thickness + 0.05, top, top + 0.05, water.coping, parent, trim)
	coping.position += (Vector3(0, 0, -outward * 0.025) if along_x else Vector3(-outward * 0.025, 0, 0))
	coping.name = coping_name
	holds_water(wall)
	holds_water(coping)
	return [wall, coping]

## Every beach and terrace edge that faces water gets a parapet to just above
## the highest water, with a coping stone; crossing mouths stay open, so a
## flooded crossing shows as water in the gap. Floors above every water get a
## timber fender instead. Await it.
func _build_parapets() -> void:
	var root := Node3D.new()
	root.name = "Parapets"
	host.terrain.add_child(root)
	for wall: Array in (await _wall_layout()).parapets:
		var run: Array = wall[0]
		var edge: float = wall[1]
		var outward: float = wall[2]
		var along_x: bool = wall[3]
		var height: float = wall[4]
		if height >= highest(): _edge_box(run, edge, outward, along_x, 0.10, height - 0.16, height - 0.03, water.fender, root, 0.6).name = "QuayFender"
		else:
			var pieces := _capped_wall(run, edge, outward, along_x, 0.09, height - 0.20, root, 0.6, "Parapet", "ParapetCoping")
			var size := (pieces[0].mesh as BoxMesh).size
			mark_bands(pieces[0].position, Vector2(size.x, size.z), height - 0.20, wall_top(), root, 0.0, 0 if along_x else 1)
		await host._build_step()

## Where a body of water ends in view against open air or another water, a
## sea wall to above the highest water holds it: no water ever shows a bare
## face. Between two waters the earlier body's side builds it. Await it.
func _build_sea_walls() -> void:
	var root := Node3D.new()
	root.name = "SeaWalls"
	host.terrain.add_child(root)
	for wall: Array in (await _wall_layout()).sea_walls:
		var run: Array = wall[0]
		var edge: float = wall[1]
		var outward: float = wall[2]
		var along_x: bool = wall[3]
		var out := Vector3(0, 0, outward * 0.015) if along_x else Vector3(outward * 0.015, 0, 0)
		var piece := _edge_box(run, edge, outward, along_x, 0.12, seabed(), wall_top(), water.stone, root, 0.6)
		piece.position += out
		piece.name = "SeaWall"
		var coping := _edge_box(run, edge, outward, along_x, 0.17, wall_top(), wall_top() + 0.05, water.coping, root, 0.6)
		coping.position += out + (Vector3(0, 0, -outward * 0.025) if along_x else Vector3(-outward * 0.025, 0, 0))
		holds_water(piece)
		holds_water(coping)
		var size := (piece.mesh as BoxMesh).size
		mark_bands(piece.position, Vector2(size.x, size.z), seabed(), wall_top(), root, 0.0, 0 if along_x else 1)
		await host._build_step()

## Every parapet and sea-wall run, in build order: {"parapets": [[run, edge,
## outward, along_x, height]], "sea_walls": [[run, edge, outward, along_x]]}.
## Worked out once per definition and block, an island at a time (a staged
## build gives the frame back between islands). Await it.
func _wall_layout() -> Dictionary:
	var definition: Dictionary = host.chapter_definition
	var islands: Array = definition.get("islands", [])
	var routes: Array = definition.get("bridges", []) + definition.get("stairs", [])
	var key := [&"water_wall_layout", islands, routes, water]
	if DefinitionGeometry.has(key): return DefinitionGeometry.kept(key)
	var holes: Array = basin_rects()
	for island: Dictionary in islands: holes.append(island.rect_cm)
	var found: Array = []
	for island: Dictionary in islands:
		found.append_array(await _island_parapet_runs(island, holes, routes))
		await host._build_step()
	var sea_walls: Array = await _sea_wall_runs(holes)
	await host._build_step()
	return DefinitionGeometry.keep(key, {"parapets": found, "sea_walls": sea_walls})

## One island's parapet runs, in _wall_layout order, a side at a time. An
## island on piers, or inside a basin, has none. Await it.
func _island_parapet_runs(island: Dictionary, holes: Array, routes: Array) -> Array:
	var found: Array = []
	var r: Array = island.rect_cm
	if str(island.id) in water.get("piers", []): return found
	for basin: Array in basin_rects():
		if r[0] >= basin[0] and r[1] >= basin[1] and r[2] <= basin[2] and r[3] <= basin[3]: return found
	var height := float(island.get("height_cm", 0)) / 100.0
	var waters: Array = []
	for body: Dictionary in open_bodies(): waters.append_array(body.rects)
	var route_rects: Array = []
	for route: Dictionary in routes: route_rects.append(route.rect_cm)
	for side in range(4):
		var along_x := side < 2
		var edge := float(r[1] if side == 0 else r[3] if side == 1 else r[0] if side == 2 else r[2])
		var outward := -1.0 if side == 0 or side == 2 else 1.0
		var start := float(r[0] if along_x else r[1]) - 8.0
		var finish := float(r[2] if along_x else r[3]) + 8.0
		# Every sample lies on one line beside the edge: only the rectangles
		# that line crosses can hold a sample, so only their spans along it
		# are tested (the same strict test as _inside).
		var line := edge + outward * 6.0
		var mouths := _spans_on_line(route_rects, along_x, line)
		var wet := _spans_on_line(waters, along_x, line)
		var dry := _spans_on_line(holes, along_x, line)
		var runs: Array = []
		var t := start + 2.0
		while t <= finish - 2.0:
			var kind := "dry"
			if _in_spans(t, mouths): kind = "mouth"
			elif _in_spans(t, wet) and not _in_spans(t, dry): kind = "wall"
			if runs.is_empty() or runs[-1][2] != kind: runs.append([t - 2.0, t + 2.0, kind])
			else: runs[-1][1] = t + 2.0
			t += 4.0
		for run: Array in runs:
			if run[2] == "wall": found.append([run, edge, outward, along_x, height])
		await host._build_step()
	return found

## Every sea-wall run, in _wall_layout order, giving a staged build the frame
## back every WALL_SAMPLES_PER_STEP samples. Only inside the block's bounds.
## Await it.
func _sea_wall_runs(holes: Array) -> Array:
	var bounds: Array = water.bounds
	var found: Array = []
	var earlier: Array = []
	var sampled := 0
	for each: Dictionary in open_bodies():
		var body: Array = each.rects
		for region: Array in body:
			for side in range(4):
				var along_x := side < 2
				var edge := float(region[1] if side == 0 else region[3] if side == 1 else region[0] if side == 2 else region[2])
				var outward := -1.0 if side == 0 or side == 2 else 1.0
				var start := float(region[0] if along_x else region[1])
				var finish := float(region[2] if along_x else region[3])
				var runs: Array = []
				# Inside and outside samples each lie on one line beside the edge
				# (see _spans_on_line): the same tests on the rectangles it crosses.
				var inner := edge - outward * 2.0
				var outer := edge + outward * 2.0
				var wet_in := _spans_on_line(body, along_x, inner)
				var dry_in := _spans_on_line(holes, along_x, inner)
				var blocked: Array = _spans_on_line(body, along_x, outer) + _spans_on_line(holes, along_x, outer)
				# An earlier body's side builds the wall between the two waters.
				if not earlier.is_empty(): blocked += _spans_on_line(earlier, along_x, outer)
				var t := start + 2.0
				while t <= finish - 2.0:
					var wall := _in_spans(t, wet_in) and not _in_spans(t, dry_in) and not _in_spans(t, blocked)
					var view: Array = [t, edge] if along_x else [edge, t]
					if float(view[0]) < float(bounds[0]) or float(view[0]) > float(bounds[2]) or float(view[1]) < float(bounds[1]) or float(view[1]) > float(bounds[3]): wall = false
					if wall and not runs.is_empty() and float(runs[-1][1]) >= t - 2.0: runs[-1][1] = t + 2.0
					elif wall: runs.append([t - 2.0, t + 2.0])
					t += 4.0
					sampled += 1
					if sampled % WALL_SAMPLES_PER_STEP == 0: await host._build_step()
				for run: Array in runs: found.append([run, edge, outward, along_x])
		earlier.append_array(body)
	return found

## The spans, along a line of constant z (along_x) or x at `line` cm, of the
## rectangles [x0, z0, x1, z1] that line passes strictly inside, as [from, to]
## along it: a point t on the line is inside such a rectangle exactly when
## from < t < to (as _inside).
static func _spans_on_line(rects: Array, along_x: bool, line: float) -> Array:
	var spans: Array = []
	for rect: Array in rects:
		if along_x and line > float(rect[1]) and line < float(rect[3]): spans.append([float(rect[0]), float(rect[2])])
		elif not along_x and line > float(rect[0]) and line < float(rect[2]): spans.append([float(rect[1]), float(rect[3])])
	return spans

static func _in_spans(t: float, spans: Array) -> bool:
	for span: Array in spans:
		if t > span[0] and t < span[1]: return true
	return false

## Walled crossings: masonry along the sides that do not meet their floors, a
## floor in the pit and a plinth under each stair. The pit is sealed (walls,
## and floors at its mouths), so the water round it never stands in it; only a
## walled stub fills, with its own flood while shut. The sides toward the
## camera (east and south) of a walled stub fade while a spirit stands on it.
## Await it.
func _build_route_walls() -> void:
	var definition: Dictionary = host.chapter_definition
	var root := Node3D.new()
	root.name = "WalledCrossings"
	host.terrain.add_child(root)
	for id: String in walled:
		await host._build_step()
		var route := _route(id)
		var r: Array = route.rect_cm
		var stub := is_stub(route)
		var floors: Array = []
		var front: Array = []
		for surface: Variant in [route.get("from_surface", ""), route.get("to_surface", "")]:
			if str(surface) == id: continue
			for item: Dictionary in definition.get("islands", []) + definition.get("bridges", []):
				if item.id == surface: floors.append(item.rect_cm)
		for side in range(4):
			var along_x := side < 2
			var edge := float(r[1] if side == 0 else r[3] if side == 1 else r[0] if side == 2 else r[2])
			var outward := -1.0 if side == 0 or side == 2 else 1.0
			var mouth := false
			for floor: Array in floors:
				var touches := absf(float(floor[3] if outward < 0 else floor[1]) - edge) <= 2.0 if along_x else absf(float(floor[2] if outward < 0 else floor[0]) - edge) <= 2.0
				var overlaps := float(floor[0]) < float(r[2]) and float(floor[2]) > float(r[0]) if along_x else float(floor[1]) < float(r[3]) and float(floor[3]) > float(r[1])
				if touches and overlaps: mouth = true
			if mouth: continue
			var run: Array = [float(r[0]) - 9.0, float(r[2]) + 9.0] if along_x else [float(r[1]) - 9.0, float(r[3]) + 9.0]
			var pieces := _capped_wall(run, edge, outward, along_x, 0.09, seabed(), root, 0.0, "CrossingWall_" + id, "CrossingCoping")
			var size := (pieces[0].mesh as BoxMesh).size
			var before := root.get_child_count()
			mark_bands(pieces[0].position, Vector2(size.x, size.z), seabed(), wall_top(), root, 0.0, 0 if along_x else 1)
			# The sides toward the camera stand in front of a spirit on a
			# walled stub: those fade while one stands there.
			if outward > 0.0 and stub:
				var nodes: Array = [pieces[0], pieces[1]]
				for index in range(before, root.get_child_count()): nodes.append(root.get_child(index))
				front.append_array(nodes)
		var center := Vector3(float(r[0] + r[2]) * 0.5 / 100.0, 0, float(r[1] + r[3]) * 0.5 / 100.0)
		var width := float(r[2] - r[0]) / 100.0
		var depth := float(r[3] - r[1]) / 100.0
		_box(Vector3(width, 0.04, depth), (water.pit_floor as Color).darkened(0.2), center + Vector3(0, seabed() + 0.02, 0), root).name = "PitFloor"
		if stub:
			_build_flood(id, route, center, width, depth)
			# A spirit on it stands below its coping: the walls toward the camera
			# fade while one stands there. A wall across the gap to a neighbour
			# never hides it from the follow camera's height.
			fade.add(r, front)
		if route.has("axis"):
			var top := float(low_cm(route)) / 100.0 - 0.12
			var plinth := _box(Vector3(width - 0.04, top - seabed(), depth - 0.04), (water.plinth as Color).darkened(0.08), center + Vector3(0, (top + seabed()) * 0.5, 0), root)
			plinth.name = "StairPlinth"
			holds_water(plinth)

## A walled stub still reads covered while its gate is shut, as it would
## standing in the open water: its pit fills to the level of the water round
## it, and empties while it is open (show_floods). The locks' plan gives its
## pit that water while flooded, so a door at its mouth holds the flood off
## the floor beside it.
func _build_flood(id: String, route: Dictionary, center: Vector3, width: float, depth: float) -> void:
	var body_id := body_of(route.rect_cm)
	var body: Node3D = bodies.get(body_id)
	if not is_instance_valid(body): return
	var sheet := body.get_node_or_null("Water") as MeshInstance3D
	var flood := Node3D.new()
	flood.name = "FloodedStub_" + id
	flood.position = Vector3(center.x, 0, center.z)
	flood.visible = false
	host.terrain.add_child(flood)
	# Its sides toward the camera stand 3 cm inside the pit, clear of the faces
	# of its frame and pit floor.
	var fill := Primitives.mesh_node(Primitives.box_mesh(Vector3(width - 0.03, 1.0, depth - 0.03)), sheet.material_override if sheet != null else Primitives.fresh_material(body_data(body_id).color), Vector3(-0.015, -0.5, -0.015), flood)
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	floods[id] = {"node": flood, "body": body, "water": body_id, "key": "crossing:" + id}
	_fill(floods[id], float(body.get_meta("shown")))

## A walled stub's flood shows while its deck is hidden (its gate shut).
func show_floods(decks: Dictionary) -> void:
	for id: String in floods:
		floods[id].node.visible = not (decks.has(id) and decks[id].visible)

# --- Locks ---

## Places the doors, spillways and walls from this stage's water, over three
## build steps: the plan, the runs (from the stage's bake at `bake_path`),
## then the pieces. Await it.
func build_locks(bake_path: String) -> void:
	var stage_plan := plan()
	await host._build_step()
	WaterLocks.load_runs(stage_plan, bake_path)
	await host._build_step()
	locks = WaterLocks.new()
	locks.build(stage_plan, host.terrain)

## This stage's water for the locks kit: every floor, sunken crossing (a pit
## sealed by its walls, dry in every state but a walled stub's, flooded with
## its water in a copy of each) and body of water (basins first, as the first
## matching area wins), the walkways, the walls built to hold water, and every
## set of levels the controls can show.
func plan() -> Dictionary:
	var definition: Dictionary = host.chapter_definition
	var areas: Array = []
	for island: Dictionary in definition.get("islands", []):
		areas.append({"id": "island:" + str(island.id), "kind": "floor", "rects": [island.rect_cm], "height": float(island.get("height_cm", 0)) / 100.0})
	for id: String in walled: areas.append({"id": "crossing:" + id, "kind": "pit", "rects": [_route(id).rect_cm]})
	var all: Array = water.get("bodies", [])
	for body: Dictionary in all.filter(func(each: Dictionary) -> bool: return bool(each.get("basin", false))) + open_bodies():
		areas.append({"id": str(body.id), "kind": "water", "rects": body.rects})
	var mouths: Array = []
	for route: Dictionary in definition.get("bridges", []) + definition.get("stairs", []):
		mouths.append({"id": str(route.id), "rect": route.rect_cm})
	var states: Array = []
	_states(water_levels(), all, 0, {}, states)
	return {"areas": areas, "bounds": water.bounds, "mouths": mouths, "walls": walls.duplicate(), "states": states, "seabed": seabed(), "wall_top": wall_top()}

## Every combination of the bodies' levels, the first body outermost; after
## each, the same levels with every walled stub shut and flooded.
func _states(levels: Dictionary, all: Array, index: int, dry: Dictionary, states: Array) -> void:
	if index == all.size():
		var state := dry.duplicate()
		states.append(state)
		if floods.is_empty(): return
		var flooded := state.duplicate()
		for id: String in floods: flooded[floods[id].key] = state[floods[id].water]
		states.append(flooded)
		return
	var id := str(all[index].id)
	for level: float in (levels[id] as Dictionary).values():
		dry[id] = level
		_states(levels, all, index + 1, dry, states)
	dry.erase(id)

## The levels for the locks, from each body's "target" (where it is going) or
## "shown" (where it stands this frame) meta; a flooded walled stub stands at
## its water's, a dry one at the seabed (dry to the locks), every other walled
## crossing stays dry. Refills one dictionary per meta with the same keys in
## the same order, so it allocates nothing and equal levels hash the same.
func lock_levels(meta: String) -> Dictionary:
	var levels: Dictionary = _lock_targets if meta == "target" else _lock_shown
	for body: String in bodies: levels[body] = float(bodies[body].get_meta(meta))
	for id: String in floods:
		levels[floods[id].key] = levels[floods[id].water] if (floods[id].node as Node3D).visible else seabed()
	return levels

## Where the spirits stand (plan cm) and which crossings are open, from the
## snapshot: the walls in front of a spirit on a walled stub fade, and a door
## dips while one stands in its mouth. Immediate snaps.
func occupy(spirits: PackedVector2Array, routes: Dictionary, immediate: bool) -> void:
	if fade != null: fade.occupy(spirits, immediate)
	if not is_instance_valid(locks): return
	locks.present(lock_levels("target"), immediate)
	locks.occupy(spirits, routes, immediate)
	# A door that must rise stands clear of the water shown now at once.
	if locks.moving(): locks.advance(0.0, lock_levels("shown"))

## The kit's nodes that move, stretch, show, hide or fade: never folded.
func moving_nodes() -> Array:
	var found: Array = bodies.values()
	for flood: Dictionary in floods.values(): found.append(flood.node)
	if fade != null: found.append_array(fade.meshes())
	return found

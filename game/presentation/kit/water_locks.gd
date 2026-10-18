extends Node3D
## World kit: what holds a world's water back. Wherever water can stand over a
## walkway's floor, or two waters meet at a walkway, a small timber sluice door
## stands across the opening between capped posts: raised just above the
## higher water while the two sides differ, sunk out of sight while they
## match. Where two waters meet away from a walkway and one always stands
## higher, a stone spillway with a thin sheet of water; anywhere else water
## would stand over a floor or end against open air, a plain capped wall.
##
## Everything is placed from the world's water plan, once per stage: the runs
## come from find_runs() (cached per plan), then build() makes the pieces.
## present() takes the levels shown and only sets door targets, and returns at
## once while they are the same as last time; advance() moves doors while they
## travel and does nothing once they rest. occupy() takes where the spirits
## stand: a door that is up dips while one stands in its mouth, so a spirit
## never walks through it. Walls and spillway stones are plain
## leaves under a "WaterLockStone" sibling, which a world folds with its
## static scenery (nothing holds it); each opening's doors and posts are one
## mesh, and the water sheets, under this node.
##
## A piece beside a floor or open air stands on the dry side, so the water
## ends at its face. A piece between two waters stands on their shared line,
## each water ending inside it.
##
## The plan (plan positions in cm, heights in metres):
##   "areas": [{"id", "kind": "water" | "pit" | "floor", "rects": [[x0, z0, x1, z1], ...],
##             "height" (floor only)}]
##       First match wins; a point in no area is open air. A pit is a sunken
##       crossing that is dry while open and holds water while shut.
##   "bounds": [x0, z0, x1, z1]   only edges inside this window count
##   "mouths": [{"id", "rect"}]    walkways: an edge whose water side lies in one
##       gets a door; elsewhere water over a floor gets a wall
##   "walls": [AABB, ...]          walls already holding water (world space)
##   "states": [{area id: level}]  every set of levels the world can show; a
##       pit missing from a state is dry
##   "seabed", "wall_top"          the water floor and the height walls reach
const Primitives = preload("res://presentation/kit/primitives.gd")
const DOOR := "door"
const SPILL := "spill"
const WALL := "wall"
const TIMBER := Color("a07a55")
const TIMBER_DARK := Color("7a5d45")
const CREAM := Color("f3e6c8")
const STONE := Color("b8a283")
const COPING := Color("dccaa4")
const SHEET := Color("cfe7ea")
## Door thickness and post width across the run (m).
const THICKNESS := 0.08
const POST := 0.12
## A post stands this far above its doors, under a cap this much wider than it.
const POST_RISE := 0.05
const CAP_OVERHANG := 0.04
## No single door is wider than this (m); a wider opening gets several.
const DOOR_WIDTH := 0.70
## A door stands this far above the highest water it holds, never above the walls.
const FREEBOARD := 0.05
## A sunk door's top sits this far under the lower side.
const SINK := 0.08
## How fast a door rises or sinks (m a second).
const TRAVEL := 1.4
## How fast a door dips for a spirit in its mouth, and rises again once it
## leaves (m a second): the tallest door (about 0.85 m) in about 0.2 s.
const DIP_TRAVEL := 5.0
## A spirit counts as standing in a door's mouth within this far of the door
## (cm), on either side, so one stepping in or waiting at it never stands in
## the raised door.
const DIP_REACH := 45.0
## A door's top never stands less than this above the water it holds, even
## while the water and the door are moving.
const MARGIN := 0.02
## Levels this close count as level; runs shorter than this (cm) are slivers.
const LEVEL := 0.01
const SLIVER := 4.0
## Walls are looked up by tiles this many cm across.
const TILE := 64.0
const NEVER := 0
const AT_TIMES := 1
const ALWAYS := 2
## Runs cached per plan: the same chapter stage always finds the same runs.
static var _found: Dictionary = {}
static var _opening_meshes: Dictionary = {}
static var _door_material_cache: StandardMaterial3D

## The pieces, in build order: {"kind", "a", "b", "along_x", "line", "from",
## "to" (cm), "top" (m, the wall already there), "mouth" (walkway id or ""),
## "shift" (cm off the line toward the dry side), "base" (m, where it stands),
## and for a door "shut" (its top while up) and "ends" (whether each end needs
## its own post), for a spillway "lip"}.
var runs: Array = []
## How many present() calls had new levels to work out. A call with the same
## levels as the last returns before any work.
var updates := 0
## How many frames advance() worked; a resting harbour adds none.
var frames := 0
var _kinds: Dictionary = {}
var _heights: Dictionary = {}
var _seabed := 0.0
## Per opening: {"run", "door": its MeshInstance3D, "y": target top, "up":
## whether the levels want it up, "low": its sunk top, "dipped": whether a
## spirit stands in its mouth, "easing": whether it travels at DIP_TRAVEL}
var _doors: Array = []
## Per spillway: {"run", "sheet": MeshInstance3D, "low": m, "falling"}
var _sheets: Array = []
var _moving := false
var _levels_seen := 0

## Builds the pieces for `plan` under `parent`: this node and its
## "WaterLockStone" sibling. Call once per stage, after find_runs(plan) if the
## world wants to spread the work over frames.
func build(plan: Dictionary, parent: Node3D) -> void:
	name = "WaterLocks"
	_seabed = float(plan.seabed)
	for area: Dictionary in plan.areas:
		_kinds[str(area.id)] = str(area.kind)
		_heights[str(area.id)] = float(area.get("height", 0.0))
	parent.add_child(self)
	var stone := Node3D.new()
	stone.name = "WaterLockStone"
	parent.add_child(stone)
	runs = find_runs(plan)
	for run: Dictionary in runs:
		match str(run.kind):
			DOOR: _build_door(run)
			SPILL: _build_spill(run, stone)
			WALL: _build_wall(run, float(plan.wall_top), stone)

## The plan rectangles (cm) the pieces stand on, in run order: [x0, z0, x1, z1].
func footprints() -> Array:
	var found: Array = []
	for run: Dictionary in runs:
		var half := (POST if str(run.kind) == DOOR else _width(str(run.kind))) * 50.0
		var line := float(run.line) + float(run.shift)
		found.append([float(run.from), line - half, float(run.to), line + half] if run.along_x else [line - half, float(run.from), line + half, float(run.to)])
	return found

static func _width(kind: String) -> float:
	match kind:
		WALL: return 0.11
		SPILL: return 0.13
	return THICKNESS

# --- Placement ---

## Every piece the plan needs: the edges some state leaves unheld, merged
## along each line, with their kind and everything their build needs. Pure:
## the same plan gives the same runs, worked out once.
static func find_runs(plan: Dictionary) -> Array:
	var key := plan.hash()
	if _found.has(key): return _found[key]
	var areas: Array = plan.areas
	var bounds: Array = plan.bounds
	var seabed := float(plan.seabed)
	var kinds := {}
	var heights := {}
	for area: Dictionary in areas:
		kinds[str(area.id)] = str(area.kind)
		heights[str(area.id)] = float(area.get("height", 0.0))
	var xs: Array = [float(bounds[0]), float(bounds[2])]
	var zs: Array = [float(bounds[1]), float(bounds[3])]
	for area: Dictionary in areas:
		for rect: Array in area.rects: _cut(rect, bounds, xs, zs)
	for mouth: Dictionary in plan.mouths: _cut(mouth.rect, bounds, xs, zs)
	xs.sort()
	zs.sort()
	# Each cell holds its area's index in `areas`, or -1 for open air.
	var width := xs.size() - 1
	var cells := PackedInt32Array()
	cells.resize(width * (zs.size() - 1))
	cells.fill(-1)
	# Last area first, so the first area that holds a cell has the last word.
	for index in range(areas.size() - 1, -1, -1):
		for rect: Array in areas[index].rects:
			var x0 := xs.bsearch(clampf(float(rect[0]), float(bounds[0]), float(bounds[2])))
			var x1 := xs.bsearch(clampf(float(rect[2]), float(bounds[0]), float(bounds[2])))
			var z0 := zs.bsearch(clampf(float(rect[1]), float(bounds[1]), float(bounds[3])))
			var z1 := zs.bsearch(clampf(float(rect[3]), float(bounds[1]), float(bounds[3])))
			for zi in range(z0, z1):
				for xi in range(x0, x1): cells[zi * width + xi] = index
	# Per area index (open air last, so index -1 reads it): its id, whether it
	# holds water, whether a floor.
	var ids := PackedStringArray()
	var wet := PackedByteArray()
	var floors := PackedByteArray()
	for area: Dictionary in areas + [{"id": "", "kind": ""}]:
		ids.append(str(area.id))
		wet.append(1 if _holds_water(str(area.id), kinds) else 0)
		floors.append(1 if str(area.kind) == "floor" else 0)
	# Each area's level in every state, so an edge reads two columns.
	var columns := {}
	var states: Array = plan.states
	for id: String in ids:
		var column := PackedFloat32Array()
		column.resize(states.size())
		if _holds_water(id, kinds):
			for index in range(states.size()): column[index] = float(states[index].get(id, seabed))
		else:
			column.fill(_level(id, {}, kinds, heights, seabed))
		columns[id] = column
	var walls := _wall_tiles(plan.walls)
	# Unheld elementary edges, grouped by line and kind so neighbours merge.
	var lines := {}
	var unheld_seen := {}
	for zi in range(zs.size() - 1):
		for xi in range(width):
			var here_index := cells[zi * width + xi]
			for across: bool in [true, false]:
				var xj := xi + (1 if across else 0)
				var zj := zi + (0 if across else 1)
				if xj >= width or zj >= zs.size() - 1: continue
				var there_index := cells[zj * width + xj]
				if here_index == there_index or not (wet[here_index] or wet[there_index]): continue
				if floors[here_index] and floors[there_index]: continue
				var here := ids[here_index]
				var there := ids[there_index]
				var along_x := not across
				var line := float(xs[xi + 1]) if across else float(zs[zi + 1])
				var from := float(zs[zi]) if across else float(xs[xi])
				var to := float(zs[zi + 1]) if across else float(xs[xi + 1])
				var middle := Vector2(line, (from + to) * 0.5) if across else Vector2((from + to) * 0.5, line)
				var edge := {"a": here, "b": there, "along_x": along_x, "line": line, "from": from, "to": to, "top": _wall_top(walls, middle, seabed), "mouth": ""}
				# Whether the edge is ever unheld depends only on its sides and the wall there.
				var seen := Vector3i(here_index, there_index, roundi(float(edge.top) * 1000.0))
				if not unheld_seen.has(seen): unheld_seen[seen] = _unheld(edge, columns, kinds, seabed)
				var unheld: int = unheld_seen[seen]
				if unheld == NEVER: continue
				if unheld == AT_TIMES and not here.is_empty() and not there.is_empty():
					var wet_side := 1.0 if _holds_water(there, kinds) else -1.0
					edge.mouth = _mouth_at(middle + (Vector2(wet_side, 0) if across else Vector2(0, wet_side)), plan.mouths)
				var kind := _kind(edge, unheld, kinds)
				edge["kind"] = kind
				edge["shift"] = _shift(kind, _holds_water(here, kinds), _holds_water(there, kinds), floors[here_index] or floors[there_index])
				edge["base"] = _base(here, there, kinds, heights, seabed)
				# Doors keep their sides and walkway; walls and spillways only their line and side.
				var group := "%s|%d|%s|%s|%s|%s" % [along_x, roundi(line), kind, edge.shift, edge.base, ("%s|%s|%s" % [here, there, edge.mouth]) if kind != WALL else ""]
				if not lines.has(group): lines[group] = []
				lines[group].append(edge)
	var found: Array = []
	var groups := lines.keys()
	groups.sort()
	for group: String in groups:
		var edges: Array = lines[group]
		edges.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p.from) < float(q.from))
		var run: Dictionary = edges[0].duplicate()
		for index in range(1, edges.size() + 1):
			if index < edges.size() and absf(float(edges[index].from) - float(run.to)) < 0.5:
				run.to = edges[index].to
				run.top = minf(float(run.top), float(edges[index].top))
				continue
			if float(run.to) - float(run.from) >= SLIVER:
				_finish(run, columns, kinds, walls, plan)
				found.append(run)
			if index < edges.size(): run = edges[index].duplicate()
	_found[key] = found
	return found

## What a run's piece needs at build time, from the levels in every state: a
## door's shut height and which of its ends no wall already closes, a
## spillway's lip.
static func _finish(run: Dictionary, columns: Dictionary, kinds: Dictionary, walls: Dictionary, plan: Dictionary) -> void:
	var seabed := float(plan.seabed)
	var side_a: PackedFloat32Array = columns[run.a]
	var side_b: PackedFloat32Array = columns[run.b]
	match str(run.kind):
		DOOR:
			var highest := seabed
			for index in range(side_a.size()):
				if _differs(run, side_a[index], side_b[index], kinds, seabed): highest = maxf(highest, maxf(side_a[index], side_b[index]))
			run["shut"] = minf(highest + FREEBOARD, float(plan.wall_top))
			var ends: Array[bool] = []
			for end: float in [0.0, (float(run.to) - float(run.from))]:
				var at := _on_run(run, end, 0.0)
				ends.append(_wall_top(walls, Vector2(at.x, at.z) * 100.0, seabed) < float(run.shut))
			run["ends"] = ends
		SPILL:
			var lip := INF
			for index in range(side_a.size()): lip = minf(lip, maxf(side_a[index], side_b[index]) - 0.03)
			run["lip"] = lip
		WALL:
			# Beside a floor it stands in the water, reaching just under the
			# lowest water it ever holds.
			if kinds.get(run.a, "") == "floor" or kinds.get(run.b, "") == "floor":
				var wet: PackedFloat32Array = side_b if kinds.get(run.a, "") == "floor" else side_a
				var lowest := INF
				for level: float in wet: lowest = minf(lowest, level)
				run.base = maxf(lowest - 0.05, seabed)

## Where a piece stands (m): on a dry side's floor (just into it), since the
## floor's own block holds the water below it; between waters or beside open
## air, on the seabed.
static func _base(a: String, b: String, kinds: Dictionary, heights: Dictionary, seabed: float) -> float:
	for side: String in [a, b]:
		if kinds.get(side, "") == "floor": return float(heights[side]) - 0.03
	return seabed

## How far (cm) a piece stands off its line: half its width and half a
## centimetre. A door, and a wall against open air, stand on the dry side, so
## the water ends at their face; a wall beside a floor stands on the water
## side, as a parapet does, so the walkway keeps its width, overlapping the
## floor's edge by half a centimetre so the water ends inside it. Between two
## waters a piece stands on the line.
static func _shift(kind: String, wet_a: bool, wet_b: bool, beside_floor: bool) -> float:
	if wet_a == wet_b: return 0.0
	var half := (POST if kind == DOOR else _width(kind)) * 50.0 + 0.5
	# A wall beside a floor reaches half a centimetre over the floor's edge, so
	# the water ends inside it whichever side the water lies on.
	if kind == WALL and beside_floor: half = -(half - 1.0)
	return half if wet_a else -half

static func _cut(rect: Array, bounds: Array, xs: Array, zs: Array) -> void:
	for x: float in [float(rect[0]), float(rect[2])]:
		var at := clampf(x, float(bounds[0]), float(bounds[2]))
		if at not in xs: xs.append(at)
	for z: float in [float(rect[1]), float(rect[3])]:
		var at := clampf(z, float(bounds[1]), float(bounds[3]))
		if at not in zs: zs.append(at)

static func _holds_water(id: String, kinds: Dictionary) -> bool:
	var kind := str(kinds.get(id, ""))
	return kind == "water" or kind == "pit"

static func _mouth_at(at: Vector2, mouths: Array) -> String:
	for mouth: Dictionary in mouths:
		var r: Array = mouth.rect
		if at.x > float(r[0]) and at.x < float(r[2]) and at.y > float(r[1]) and at.y < float(r[3]): return str(mouth.id)
	return ""

## Walls by tile (Vector2i -> [AABB]), each grown 3 cm, so a point checks
## only the walls near it.
static func _wall_tiles(walls: Array) -> Dictionary:
	var tiles := {}
	for box: AABB in walls:
		var grown := box.grow(0.03)
		for tx in range(floori(grown.position.x * 100.0 / TILE), floori(grown.end.x * 100.0 / TILE) + 1):
			for tz in range(floori(grown.position.z * 100.0 / TILE), floori(grown.end.z * 100.0 / TILE) + 1):
				var key := Vector2i(tx, tz)
				if not tiles.has(key): tiles[key] = []
				tiles[key].append(grown)
	return tiles

## The tallest wall already standing on a plan point (cm), or the seabed.
static func _wall_top(tiles: Dictionary, at: Vector2, seabed: float) -> float:
	var top := seabed
	for box: AABB in tiles.get(Vector2i(floori(at.x / TILE), floori(at.y / TILE)), []):
		if at.x / 100.0 >= box.position.x and at.x / 100.0 <= box.end.x and at.y / 100.0 >= box.position.z and at.y / 100.0 <= box.end.z:
			top = maxf(top, box.end.y - 0.03)
	return top

## Whether some state leaves an edge unheld: NEVER, AT_TIMES (and level in
## others) or ALWAYS. `columns`: per area id (and "" for open air), its level
## in every state.
static func _unheld(edge: Dictionary, columns: Dictionary, kinds: Dictionary, seabed: float) -> int:
	var unheld := false
	var level := false
	var side_a: PackedFloat32Array = columns[edge.a]
	var side_b: PackedFloat32Array = columns[edge.b]
	var kind_a := str(kinds.get(edge.a, ""))
	var kind_b := str(kinds.get(edge.b, ""))
	var water_a := kind_a == "water"
	var water_b := kind_b == "water"
	var pit_a := kind_a == "pit"
	var pit_b := kind_b == "pit"
	var top := float(edge.top)
	# _differs, with the sides' kinds read once.
	for index in range(side_a.size()):
		var a := side_a[index]
		var b := side_b[index]
		var wet_a := water_a or (pit_a and a > seabed + LEVEL)
		var wet_b := water_b or (pit_b and b > seabed + LEVEL)
		var high := maxf(a if wet_a else seabed, b if wet_b else seabed)
		if (wet_a or wet_b) and high > minf(a, b) + LEVEL and top < high - LEVEL: unheld = true
		else: level = true
		if unheld and level: break
	if not unheld: return NEVER
	return AT_TIMES if level else ALWAYS

## Whether water on one side stands above the other where nothing holds it,
## for these two levels. A pit holds water only above the seabed.
static func _differs(edge: Dictionary, a: float, b: float, kinds: Dictionary, seabed: float) -> bool:
	return _held(edge, a, b, kinds, seabed) > -INF

## The surface of the water that stands above the other side with nothing
## holding it, for these two levels; -INF when none does.
static func _held(edge: Dictionary, a: float, b: float, kinds: Dictionary, seabed: float) -> float:
	var kind_a := str(kinds.get(edge.a, ""))
	var kind_b := str(kinds.get(edge.b, ""))
	var wet_a := kind_a == "water" or (kind_a == "pit" and a > seabed + LEVEL)
	var wet_b := kind_b == "water" or (kind_b == "pit" and b > seabed + LEVEL)
	if not wet_a and not wet_b: return -INF
	var high := maxf(a if wet_a else seabed, b if wet_b else seabed)
	return high if high > minf(a, b) + LEVEL and float(edge.top) < high - LEVEL else -INF

## DOOR where a walkway meets an edge whose sides are level at times, SPILL
## between two waters that always differ, else WALL.
static func _kind(edge: Dictionary, unheld: int, kinds: Dictionary) -> String:
	if str(edge.a).is_empty() or str(edge.b).is_empty(): return WALL
	if not str(edge.mouth).is_empty() and unheld == AT_TIMES: return DOOR
	var floor_side: bool = kinds.get(edge.a, "") == "floor" or kinds.get(edge.b, "") == "floor"
	return WALL if floor_side or unheld == AT_TIMES else SPILL

static func _level(id: String, state: Dictionary, kinds: Dictionary, heights: Dictionary, seabed: float) -> float:
	match str(kinds.get(id, "")):
		"water", "pit": return float(state.get(id, seabed))
		"floor": return float(heights.get(id, 0.0))
	return seabed

# --- Pieces ---

## A point on the run's line `along` cm from its start, at height y.
static func _on_run(run: Dictionary, along: float, y: float) -> Vector3:
	var line := (float(run.line) + float(run.get("shift", 0.0))) / 100.0
	var at := (float(run.from) + along) / 100.0
	return Vector3(at, y, line) if run.along_x else Vector3(line, y, at)

static func _length(run: Dictionary) -> float:
	return (float(run.to) - float(run.from)) / 100.0

## A stone box along the run, 0.6 cm short of each end so its faces never
## meet what stands there.
func _stone_box(run: Dictionary, bottom: float, top: float, thickness: float, color: Color, piece: String, stone: Node3D) -> MeshInstance3D:
	var length := _length(run) - 0.012
	var size := Vector3(length, top - bottom, thickness) if run.along_x else Vector3(thickness, top - bottom, length)
	var node := Primitives.mesh_node(Primitives.box_mesh(size), Primitives.shared_material(color), _on_run(run, _length(run) * 50.0, (top + bottom) * 0.5), stone)
	node.name = piece
	return node

## A plain wall with a coping stone, to the height the world's walls reach.
func _build_wall(run: Dictionary, top: float, stone: Node3D) -> void:
	_stone_box(run, float(run.base), top, _width(WALL), STONE, "LockWall", stone)
	_stone_box(run, top, top + 0.045, _width(WALL) + 0.05, COPING, "LockWallCoping", stone)

## A stone lip just under the higher water, and a thin sheet falling from it
## to the lower side.
func _build_spill(run: Dictionary, stone: Node3D) -> void:
	_stone_box(run, float(run.base), float(run.lip), _width(SPILL), STONE, "Spillway", stone)
	var length := _length(run) - 0.04
	var sheet := Primitives.mesh_node(Primitives.box_mesh(Vector3(length, 1.0, 0.012) if run.along_x else Vector3(0.012, 1.0, length)), Primitives.shared_material(SHEET, 0.3), Vector3.ZERO, self)
	sheet.name = "SpillSheet"
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheet.visible = false
	_sheets.append({"run": run, "sheet": sheet, "low": INF, "falling": false})

## The opening's doors: short timber doors side by side (none wider than
## DOOR_WIDTH), each with a small cream knob on its top rail, a capped stone
## post between two and at each end no wall already closes. Doors and posts
## are one mesh that rises and sinks, so nothing is left standing in a walkway
## while the doors are down, and the opening is a single draw.
func _build_door(run: Dictionary) -> void:
	var length := _length(run)
	var count := maxi(1, ceili(length / DOOR_WIDTH))
	var posts := PackedFloat32Array()
	for index in range(count + 1):
		if (index == 0 and not run.ends[0]) or (index == count and not run.ends[1]): continue
		# Half a centimetre inside the opening, clear of what stands at its ends.
		posts.append(clampf(length * float(index) / float(count), POST * 0.5 + 0.005, length - POST * 0.5 - 0.005) - length * 0.5)
	var door := MeshInstance3D.new()
	door.name = "LockDoor"
	door.mesh = _opening_mesh(length, count, posts, float(run.shut) - float(run.base))
	door.material_override = _door_material()
	door.position = _on_run(run, length * 50.0, 0.0)
	# Local +x runs along the run: +x, or +z for a run along z.
	if not run.along_x: door.rotation.y = -PI / 2.0
	add_child(door)
	var entry := {"run": run, "door": door, "y": float(run.shut), "up": true, "low": _seabed, "dipped": false, "easing": false}
	_doors.append(entry)
	_place_door(entry, float(run.shut))

## A door's top at `top`. A door that rests sunk under the lower side is hidden.
func _place_door(entry: Dictionary, top: float) -> void:
	var door: MeshInstance3D = entry.door
	door.position.y = top
	door.visible = top >= float(entry.run.shut) - 0.001 or not is_equal_approx(top, float(entry.y))

static func _door_material() -> StandardMaterial3D:
	if _door_material_cache == null:
		_door_material_cache = StandardMaterial3D.new()
		_door_material_cache.vertex_color_use_as_albedo = true
		_door_material_cache.roughness = 0.9
	return _door_material_cache

## One opening (top at y 0, hanging down `height`, centred on x 0 along x):
## `count` doors with soft plank grooves, a rounded timber top rail and a
## small cream knob each, and a capped stone post at each x in `posts`,
## standing a little above the doors. Shared by every opening of the same shape.
static func _opening_mesh(length: float, count: int, posts: PackedFloat32Array, height: float) -> ArrayMesh:
	var key := "%d|%d|%d|%s" % [roundi(length * 1000.0), count, roundi(height * 1000.0), Array(posts).map(func(x: float) -> int: return roundi(x * 1000.0))]
	if _opening_meshes.has(key): return _opening_meshes[key]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var span := length / float(count)
	var width := span - POST - 0.03
	for index in range(count):
		var middle := -length * 0.5 + span * (float(index) + 0.5)
		_box(tool, Vector3(width, height - 0.03, THICKNESS), Vector3(middle, -(height + 0.03) * 0.5, 0), TIMBER)
		var planks := maxi(2, roundi(width / 0.12))
		for plank in range(1, planks):
			var x := middle - width * 0.5 + width * float(plank) / float(planks)
			for face: float in [-1.0, 1.0]:
				_box(tool, Vector3(0.012, height - 0.06, 0.004), Vector3(x, -(height + 0.03) * 0.5, face * (THICKNESS * 0.5 + 0.002)), TIMBER_DARK)
		_round_cap(tool, width, Vector3(middle, -0.03, 0), TIMBER_DARK)
		_box(tool, Vector3(0.05, 0.035, 0.05), Vector3(middle, 0.03, 0), CREAM)
	for x: float in posts:
		_box(tool, Vector3(POST, height + POST_RISE, POST), Vector3(x, (POST_RISE - height) * 0.5, 0), STONE)
		_box(tool, Vector3(POST + CAP_OVERHANG, 0.035, POST + CAP_OVERHANG), Vector3(x, POST_RISE + 0.0175, 0), COPING)
	var mesh := tool.commit()
	_opening_meshes[key] = mesh
	return mesh

## A half-round cap along x on top of the door, ends closed.
static func _round_cap(tool: SurfaceTool, width: float, base: Vector3, color: Color) -> void:
	var radius := THICKNESS * 0.5 + 0.008
	var steps := 8
	var half := width * 0.5
	for index in range(steps):
		var a0 := PI * float(index) / float(steps)
		var a1 := PI * float(index + 1) / float(steps)
		var p0 := Vector3(0, sin(a0) * radius, cos(a0) * radius)
		var p1 := Vector3(0, sin(a1) * radius, cos(a1) * radius)
		var n0 := Vector3(0, sin(a0), cos(a0))
		var n1 := Vector3(0, sin(a1), cos(a1))
		var quad := [base + p0 + Vector3(-half, 0, 0), base + p0 + Vector3(half, 0, 0), base + p1 + Vector3(half, 0, 0), base + p1 + Vector3(-half, 0, 0)]
		var normals := [n0, n0, n1, n1]
		var order: Array = [0, 1, 2, 0, 2, 3]
		if ((quad[0] as Vector3) - (quad[2] as Vector3)).cross((quad[0] as Vector3) - (quad[1] as Vector3)).dot(n0 + n1) < 0.0: order = [0, 2, 1, 0, 3, 2]
		for at: int in order:
			tool.set_color(color)
			tool.set_normal(normals[at])
			tool.add_vertex(quad[at])
		for end: float in [-half, half]:
			var tri := [base + Vector3(end, 0, 0), base + p0 + Vector3(end, 0, 0), base + p1 + Vector3(end, 0, 0)]
			var normal := Vector3(signf(end), 0, 0)
			var t_order: Array = [0, 1, 2]
			if ((tri[0] as Vector3) - (tri[2] as Vector3)).cross((tri[0] as Vector3) - (tri[1] as Vector3)).dot(normal) < 0.0: t_order = [0, 2, 1]
			for at: int in t_order:
				tool.set_color(color)
				tool.set_normal(normal)
				tool.add_vertex(tri[at])

static func _box(tool: SurfaceTool, size: Vector3, center: Vector3, color: Color) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)],
		[Vector3.LEFT, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)],
		[Vector3.UP, Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z)],
		[Vector3.DOWN, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z)],
		[Vector3.BACK, Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)],
		[Vector3.FORWARD, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)],
	]
	for face: Array in faces:
		var normal: Vector3 = face[0]
		var corners: Array = [face[1], face[2], face[3], face[4]]
		var a: Vector3 = corners[0]
		var b: Vector3 = corners[1]
		var c: Vector3 = corners[2]
		# Godot draws a triangle a, b, c whose (a - c) x (a - b) faces the eye.
		if (a - c).cross(a - b).dot(normal) < 0.0: corners.reverse()
		for index: int in [0, 1, 2, 0, 2, 3]:
			tool.set_color(color)
			tool.set_normal(normal)
			tool.add_vertex(center + (corners[index] as Vector3))

# --- Showing a state ---

## Sets each door's target for these levels ({area id: level m}; a pit
## missing is dry): raised while the sides differ, else sunk under the lower
## side. Returns at once when the levels are the same as last time; immediate
## (pass it for reduced motion too) skips the travel.
func present(levels: Dictionary, immediate: bool = false) -> void:
	var levels_key := levels.hash()
	if levels_key == _levels_seen and updates > 0:
		if immediate and _moving: _settle()
		return
	_levels_seen = levels_key
	updates += 1
	for entry: Dictionary in _doors:
		var run: Dictionary = entry.run
		var a := _level(str(run.a), levels, _kinds, _heights, _seabed)
		var b := _level(str(run.b), levels, _kinds, _heights, _seabed)
		entry.up = _differs(run, a, b, _kinds, _seabed)
		entry.low = maxf(minf(a, b) - SINK, _seabed)
		_retarget(entry)
	for spill: Dictionary in _sheets:
		var run: Dictionary = spill.run
		var a := _level(str(run.a), levels, _kinds, _heights, _seabed)
		var b := _level(str(run.b), levels, _kinds, _heights, _seabed)
		var low := minf(a, b)
		# Water only falls while the higher side stands over the lip.
		var falling := maxf(a, b) > float(run.lip) + 0.005
		if is_equal_approx(low, float(spill.low)) and falling == bool(spill.falling): continue
		spill.low = low
		spill.falling = falling
		var sheet: MeshInstance3D = spill.sheet
		var fall := float(run.lip) - low
		sheet.visible = falling and fall > LEVEL
		var toward_b := Vector3(0, 0, 1) if run.along_x else Vector3(1, 0, 0)
		var lower_side := toward_b if b < a else -toward_b
		sheet.position = _on_run(run, _length(run) * 50.0, float(run.lip) - fall * 0.5) + lower_side * (_width(SPILL) * 0.5 + 0.01)
		sheet.scale = Vector3(1, maxf(fall, 0.01), 1)
	if immediate: _settle()

## Tells the doors where the spirits stand (plan cm): a door that is up dips
## while a spirit stands in its mouth (within DIP_REACH of the door, either
## side), and rises again once it leaves. Only doors that are up are checked,
## with a squared-distance test; call it with each snapshot. Immediate (pass it
## for reduced motion) skips the easing.
func occupy(spirits: PackedVector2Array, immediate: bool = false) -> void:
	for entry: Dictionary in _doors:
		var dipped := false
		if bool(entry.up):
			for at: Vector2 in spirits:
				if _in_mouth(entry.run, at):
					dipped = true
					break
		if dipped == bool(entry.dipped): continue
		entry.dipped = dipped
		entry.easing = _retarget(entry)
	if immediate and _moving: _settle()

## Whether a point (plan cm) lies within DIP_REACH of a door's run.
static func _in_mouth(run: Dictionary, at: Vector2) -> bool:
	var line := float(run.line)
	var across := (at.y if run.along_x else at.x) - line
	var along := at.x if run.along_x else at.y
	var outside := maxf(float(run.from) - along, along - float(run.to))
	return across * across + maxf(outside, 0.0) * maxf(outside, 0.0) <= DIP_REACH * DIP_REACH

## A door's target from what the levels want and whether a spirit stands in
## it; whether that target moved.
func _retarget(entry: Dictionary) -> bool:
	var target := float(entry.run.shut) if bool(entry.up) and not bool(entry.dipped) else float(entry.low)
	if is_equal_approx(target, float(entry.y)): return false
	entry.y = target
	_moving = true
	return true

## Moves every door toward its target, never letting it stand below the
## water it holds now: `shown` is each area's level as the water is shown this
## frame (as present()'s levels). A door that must rise jumps to just above
## that water, and one that must sink waits until its two sides are level.
## A door dipped for a spirit (occupy()) sinks and rises at DIP_TRAVEL instead.
## Returns whether any door still moves. A world calls it only on frames where
## its water or a door moves (moving()), so a resting harbour does no work.
func advance(delta: float, shown: Dictionary) -> bool:
	frames += 1
	var still := false
	var step := TRAVEL * maxf(delta, 0.0)
	for entry: Dictionary in _doors:
		var run: Dictionary = entry.run
		var door: MeshInstance3D = entry.door
		var top := door.position.y
		var target := float(entry.y)
		var easing := bool(entry.easing)
		var travel := DIP_TRAVEL * maxf(delta, 0.0) if easing else step
		var next := minf(target, top + travel) if target > top else maxf(target, top - travel)
		if not easing and not bool(entry.dipped):
			var a := _level(str(run.a), shown, _kinds, _heights, _seabed)
			var b := _level(str(run.b), shown, _kinds, _heights, _seabed)
			# Never above its shut height, which may stand under the margin where
			# the walls are low, so a held door still comes to rest. A door dipped
			# for a spirit, or easing back up after one, is not held.
			next = maxf(next, minf(_held(run, a, b, _kinds, _seabed) + MARGIN, float(run.shut)))
		if not is_equal_approx(next, top): _place_door(entry, next)
		if not is_equal_approx(next, target): still = true
		elif easing: entry.easing = false
	_moving = still
	return still

func _settle() -> void:
	for entry: Dictionary in _doors:
		_place_door(entry, float(entry.y))
		entry.easing = false
	_moving = false

func moving() -> bool:
	return _moving

## Per door, in build order, from what the levels and spirits want (a door
## told to sink may still be held up by the water for a moment): "shut" (up),
## "dipped" (sunk for a spirit in its mouth) or "open" (sunk, its two sides
## level).
func door_states() -> Array:
	var found: Array = []
	for entry: Dictionary in _doors: found.append("open" if not bool(entry.up) else "dipped" if bool(entry.dipped) else "shut")
	return found

## Per door, in build order: its MeshInstance3D.
func door_nodes() -> Array:
	var found: Array = []
	for entry: Dictionary in _doors: found.append(entry.door)
	return found

extends RefCounted
## World kit: route barriers, the physical reasons a pip is refused. Each
## comes from the stage's own data, so a level author writes nothing:
##  - owner gates: a small picket gate in the owner's colour at every end of an
##    owned crossing (a bridge, stair, rope walk or stub) that lands on a floor.
##    It stands open while its owner (live or the memory) is on the crossing or
##    within OPEN_CM of that end, shut otherwise. While both pips stand there
##    the owner wins: the gate stays open and the other pip still rattles it.
##  - stair gates: two posts, a bar and a hanging chain at the foot and head of
##    a stair, shown while the stair is closed and gone once it opens. A world
##    that draws a closed stair itself (a folding stair, steps under water)
##    leaves it out with skip().
##  - zone edges: a low rope (or a rail: the level's "barrier" look) along every edge of
##    an access zone that faces floor at the zone's height. Each stretch drops
##    while the zone's owner is within OPEN_CM of it, so the owner walks through.
##  - locks: a small padlock over an owned lever, switch or pad while the other
##    pip stands at it, and a lock ring round the rolling ball while the second
##    pip may not push it yet (before Take over).
## present() works the shown pieces out from the snapshot alone, so live play,
## the memory and every replay show the same. A refusal the screen found
## (presentation/barrier_refusals.gd, in the snapshot's "refused") wiggles the
## barrier the pip pushed into, on this kit's own clock (moving(), advance()),
## and only while it wiggles.
##
## Presentation only: built from the hashed stage and fed the snapshot;
## nothing here feeds the simulation, a recording or a checkpoint. Cost: one
## mesh and one material per stage, all pieces in it (pair_tags' pattern: one
## draw call however many gates). A piece a slot does not show folds to a point
## in the shader (route_barriers.gdshader); present() sets the slots' states
## only when they change. The ball's lock ring is one plain node per ball with
## a kit-cached mesh and look (Primitives, released through SessionRelease).
## The layout functions are static and read only stage data, so the screen's
## refusal finder and the tests use the very same rules.
const OwnerMark = preload("res://presentation/kit/owner_mark.gd")
const FloorSpots = preload("res://presentation/kit/floor_spots.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const Props = preload("res://presentation/kit/props.gd")
const Navigation = preload("res://core/cooperative/navigation.gd")
const PropStyles = preload("res://content/dressing/prop_styles.gd")
const SHADER := preload("res://presentation/kit/route_barriers.gdshader")

## What a refusal or a barrier is about.
const OWNER := &"owner"
const STAIR := &"stair"
const ZONE := &"zone"
const LOCK := &"lock"
## Layers, as bits of a slot's mask (the shader's UV2.y).
const POSTS := 1
const SHUT := 2
const OPEN := 4
const CHAIN := 8
const ROPE := 16
const PADLOCK := 32
## The shader keeps this many slots; past it a stage warns and the rest share the last.
const MAX_SLOTS := 96
## A gate opens while its owner is on its crossing or this close (cm, across
## the floor) to its end: past a spirit's radius (12 cm) and several ticks of
## walking (8 cm a tick), so neither the live spirit nor the memory ever
## reaches a shut gate. A zone's stretch of rope drops while its owner is this
## close to it.
const OPEN_CM := 90
const ROPE_OPEN_CM := 70
## Height (cm) within which a spirit counts as at a gate's floor.
const NEAR_HEIGHT_CM := 40
## A floor counts as landing at a crossing's end when it lies this close (m)
## past the end, at this height (m).
const LANDING_REACH := 0.04
const LANDING_HEIGHT := 0.03
## Pieces (metres). Posts stand just outside a crossing's width on its floor.
const POST := 0.06
const POST_TALL := 0.42
## A post in the stage's way steps out this far at a time, at most this often.
const POST_STEP := 0.03
const POST_STEPS := 14
const NO_SHIFT := [0.0, 0.0]
const CAP := Vector3(0.08, 0.024, 0.08)
const PICKET := Vector3(0.034, 0.26, 0.026)
const PICKET_STEP := 0.06
const RAIL := Vector3(0.0, 0.022, 0.02)
const RAIL_HEIGHTS := [0.07, 0.2]
## The broad cap along a leaf's top: its height and depth.
const LEAF_CAP := Vector3(0.0, 0.022, 0.05)
## A shut leaf stands this far onto its crossing from the crossing's end; an
## open leaf lies along the crossing's side this far inside it (a spirit's
## centre keeps 12 cm in from the side, so it never meets an open leaf).
const LEAF_ON := 0.03
const LEAF_IN := 0.014
## An open half is at most this long.
const OPEN_LEAF := 0.34
## A bridge's shut halves turn this far (radians) onto the deck from its end.
const SHUT_ANGLE := 0.55
## A stair gate's bar and chain.
const BAR_HEIGHT := 0.36
const BAR := 0.05
## The bar's stripes, red and cream in turn.
const BAR_STRIPES := 5
const BAR_RED := Props.ROOF
const CHAIN_TOP := 0.26
const CHAIN_SAG := 0.11
const LINK := 0.032
const CHAIN_LINKS := 11
## A zone edge: its stretch length and how finely its edge is sampled.
const SPAN := 0.6
const EDGE_STEP := 0.04
## How a zone edge looks, by the level's "barrier" look slot (content/dressing/
## prop_styles.gd: each style names one of these). A rope: timber posts and a
## sagging rope in the owner's colour. A rail: dark posts capped in the owner's
## colour, a timber beam and a band of the owner's colour on it. A new look
## is one entry here and one style there.
const EDGE_LOOKS := {
	&"rope": {"post": Vector3(0.05, 0.25, 0.05), "post_colour": Props.TIMBER, "capped": false, "beam": 0.0, "rope": 0.032, "rope_height": 0.19, "sag": 0.03},
	&"rail": {"post": Vector3(0.06, 0.3, 0.06), "post_colour": Props.TIMBER_DARK, "capped": true, "beam": 0.055, "rope": 0.0},
}
const DEFAULT_EDGE := &"rope"
## A padlock over a control: its height over the control's floor point by
## kind, and its parts.
const LOCK_LIFT := {&"lever": 0.5, &"selector": 0.5, &"pad": 0.5}
## Beside the control toward the camera's side, so the pip standing there
## never hides it.
const LOCK_SIDE := Vector3(0.34, 0.0, 0.12)
const LOCK_BODY := Vector3(0.15, 0.13, 0.06)
const SHACKLE := 0.026
## Colours.
const TIMBER := Props.TIMBER
const TIMBER_DARK := Props.TIMBER_DARK
const CREAM := Color("efe4c8")
const IRON := Color("6f6a62")
const BRASS := Color("c49a52")
## A wiggle: full strength at a refusal, gone after WIGGLE_SECONDS; the
## shader's lean and shake rate.
const WIGGLE_SECONDS := 0.4
const WIGGLE_LEAN := 0.12
const WIGGLE_RATE := 42.0
## The lock ring round a ball: this far out from it, its tube this thick.
const BALL_RING_OUT := 0.07
const BALL_RING_COLOUR := Color("6d6a64")
## How high a ball's centre is drawn over its floor (cooperative_world draws it there too).
const BALL_LIFT := 0.2

var _world: Node3D
## Crossings whose closed state the world draws itself: route id -> why.
var _skips: Dictionary = {}
var _layout: Dictionary = {}
var _node: MeshInstance3D
var _material: ShaderMaterial
var _states := PackedVector4Array()
var _masks := PackedInt32Array()
## Slots wiggling now: slot -> seconds left.
var _wiggles: Dictionary = {}
var _clock := 0.0
## The last tick whose refusals were acted on.
var _event_tick := -1
const NO_EVENTS := []
var _reduced_motion := false
## The ball lock rings: prop id -> node, and each ball's radius (m).
var _rings: Dictionary = {}
var _ring_radius: Dictionary = {}

func _init(world: Node3D = null) -> void:
	_world = world

## A new stage: what was built before goes (its node went with the terrain).
func clear() -> void:
	_skips.clear()
	_layout = {}
	_node = null
	_material = null
	_states = PackedVector4Array()
	_masks = PackedInt32Array()
	_wiggles.clear()
	_clock = 0.0
	_event_tick = -1
	_rings.clear()
	_ring_radius.clear()

## Leaves out the stair gate of `route_id`: the world draws its closed state
## itself (`why`, for tests). Owner gates stay.
func skip(route_id: String, why: String = "") -> void:
	_skips[route_id] = why

## The routes skipped this stage: route id -> why.
func skips() -> Dictionary:
	return _skips.duplicate()

func set_reduced_motion(on: bool) -> void:
	_reduced_motion = on

# --- Layout (static: stage data only) --------------------------------------------

## The stage's barriers from its merged view: {mouths, spans, locks}.
## mouths: one per crossing end that lands on a floor and needs a gate:
##   {route, kind (&"bridge" or &"stair"), owner ("" or a slot), stair_gate,
##    at (floor point of the end's middle, m), along (Vector2: from the floor
##    into the crossing), half (half its width, m), rect (the crossing, m),
##    low and high (its height range, cm), slot}.
## spans: one per stretch of zone edge: {zone, owner, a, b (Vector3 ends, m), slot}.
## locks: one per owned control: {id, kind (&"lever", &"selector", &"pad"),
##   owner, entity, slot}.
static func layout(view: Dictionary, skips: Dictionary = {}) -> Dictionary:
	var floors := floors_of(view)
	var mouths: Array = []
	var slot := 0
	for kind: String in ["bridges", "stairs"]:
		for route: Dictionary in view.get(kind, []):
			var owner := _owner(route)
			var stair_gate := kind == "stairs" and not skips.has(str(route.id))
			if owner.is_empty() and not stair_gate: continue
			for mouth: Dictionary in mouths_of(route, floors):
				mouth.merge({"route": str(route.id), "kind": &"stair" if kind == "stairs" else &"bridge", "owner": owner, "stair_gate": stair_gate, "slot": slot})
				mouths.append(mouth)
				slot += 1
	var spans: Array = []
	for zone: Dictionary in view.get("access_zones", []):
		var owner := _owner(zone)
		if owner.is_empty(): continue
		for pair: Array in zone_edges(zone, view, floors):
			spans.append({"zone": str(zone.get("id", "")), "owner": owner, "a": pair[0], "b": pair[1], "slot": slot})
			slot += 1
	var locks: Array = []
	for entry: Array in [["levers", &"lever"], ["controls", &"selector"], ["pressure_pads", &"pad"]]:
		for entity: Dictionary in view.get(entry[0], []):
			var owner := _owner(entity)
			if owner.is_empty() or not entity.has("position_cm"): continue
			var kind: StringName = entry[1]
			if kind == &"lever" and str(entity.get("kind", "")) == "selector": kind = &"selector"
			locks.append({"id": str(entity.id), "kind": kind, "owner": owner, "entity": entity, "slot": slot})
			slot += 1
	return {"mouths": mouths, "spans": spans, "locks": locks, "slots": slot}

static func _owner(thing: Dictionary) -> String:
	var owner := str(thing.get("owner_slot", ""))
	return owner if owner in ["p0", "p1"] else ""

## Every floor of the view, crossings included: {rect (m), y (m), id, crossing, stair}.
static func floors_of(view: Dictionary) -> Array:
	var found: Array = []
	for island: Dictionary in view.get("islands", []): found.append({"rect": FloorSpots.rect_of(island.rect_cm), "rect_cm": island.rect_cm, "y": float(island.get("height_cm", 0)) / 100.0, "id": str(island.id), "crossing": false, "stair": {}})
	for route: Dictionary in view.get("bridges", []): found.append({"rect": FloorSpots.rect_of(route.rect_cm), "y": float(route.get("height_cm", 0)) / 100.0, "id": str(route.id), "crossing": true, "stair": {}})
	for stair: Dictionary in view.get("stairs", []): found.append({"rect": FloorSpots.rect_of(stair.rect_cm), "y": float(stair.get("from_height_cm", 0)) / 100.0, "id": str(stair.id), "crossing": true, "stair": stair})
	return found

## The floor of `floors` other than `except` under `point` at height `y` (m), or "".
static func _floor_at(floors: Array, point: Vector2, y: float, except: String = "") -> String:
	for f: Dictionary in floors:
		if f.id == except or not (f.rect as Rect2).has_point(point): continue
		var height := float(f.y)
		if not (f.stair as Dictionary).is_empty(): height = float(Navigation.stair_height(f.stair, Vector2i(roundi(point.x * 100.0), roundi(point.y * 100.0)))) / 100.0
		if absf(height - y) <= LANDING_HEIGHT: return str(f.id)
	return ""

## A crossing's edges that land on a floor of `floors` (where the engine lets
## a pip step on or off): {at, along, half, rect, low, high, floor (the id it
## lands on), end}. A stair is entered only at its foot (end 0) and head (end
## 1), along its axis; a bridge at any of its four edges, end 0 to 3 for west,
## east, north and south (a harbour stub opens on its long side).
static func mouths_of(route: Dictionary, floors: Array) -> Array:
	var rect := FloorSpots.rect_of(route.rect_cm)
	var low := float(route.get("from_height_cm", route.get("height_cm", 0)))
	var high := float(route.get("to_height_cm", route.get("height_cm", low)))
	var stair := route.has("axis")
	var edges: Array = [[Vector2(rect.position.x, rect.get_center().y), Vector2.RIGHT, rect.size.y], [Vector2(rect.end.x, rect.get_center().y), Vector2.LEFT, rect.size.y], [Vector2(rect.get_center().x, rect.position.y), Vector2(0, 1), rect.size.x], [Vector2(rect.get_center().x, rect.end.y), Vector2(0, -1), rect.size.x]]
	if stair: edges = edges.slice(0, 2) if str(route.axis) == "x" else edges.slice(2, 4)
	var found: Array = []
	for end in range(edges.size()):
		var centre: Vector2 = edges[end][0]
		var along: Vector2 = edges[end][1]
		var half := float(edges[end][2]) * 0.5
		var height := (high if stair and end == 1 else low) / 100.0
		var across := Vector2(along.y, -along.x)
		var lands := ""
		for share: float in [0.0, -0.6, 0.6]:
			if lands.is_empty(): lands = _floor_at(floors, centre - along * LANDING_REACH + across * half * share, height, str(route.id))
		if not lands.is_empty(): found.append({"at": Vector3(centre.x, height, centre.y), "along": along, "half": half, "rect": rect, "low": minf(low, high), "high": maxf(low, high), "end": end, "floor": lands})
	return found

## The stretches of a zone's edge that face floor at its height: [[a, b], ...]
## (Vector3, m), each at most SPAN long. A stretch that faces another zone of
## the same owner is left out.
static func zone_edges(zone: Dictionary, view: Dictionary, floors: Array) -> Array:
	var rect := FloorSpots.rect_of(zone.rect_cm)
	var y := 0.0
	for f: Dictionary in floors:
		if f.id == str(zone.get("surface_id", "")): y = float(f.y)
	var own: Array = []
	for other: Dictionary in view.get("access_zones", []):
		if other != zone and _owner(other) == _owner(zone): own.append(FloorSpots.rect_of(other.rect_cm))
	var found: Array = []
	for edge: Array in [[rect.position, Vector2(rect.end.x, rect.position.y), Vector2(0, -1)], [Vector2(rect.position.x, rect.end.y), rect.end, Vector2(0, 1)], [rect.position, Vector2(rect.position.x, rect.end.y), Vector2(-1, 0)], [Vector2(rect.end.x, rect.position.y), rect.end, Vector2(1, 0)]]:
		var from: Vector2 = edge[0]
		var to: Vector2 = edge[1]
		var out: Vector2 = edge[2]
		var length := from.distance_to(to)
		var count := maxi(1, int(round(length / EDGE_STEP)))
		var run_start := -1.0
		for index in range(count + 1):
			var t := (float(index) + 0.5) / float(count) if index < count else 2.0
			var faces := false
			if t <= 1.0:
				var outside := from.lerp(to, t) + out * LANDING_REACH
				faces = not _floor_at(floors, outside, y).is_empty() and not own.any(func(r: Rect2) -> bool: return r.has_point(outside))
			if faces and run_start < 0.0: run_start = float(index) / float(count)
			elif not faces and run_start >= 0.0:
				var run_end := minf(float(index) / float(count), 1.0)
				var pieces := maxi(1, ceili((run_end - run_start) * length / SPAN))
				for piece in range(pieces):
					var a := from.lerp(to, lerpf(run_start, run_end, float(piece) / float(pieces)))
					var b := from.lerp(to, lerpf(run_start, run_end, float(piece + 1) / float(pieces)))
					found.append([Vector3(a.x, y, a.y), Vector3(b.x, y, b.y)])
				run_start = -1.0
	return found

# --- States (static: snapshot alone) ------------------------------------------------

## Each slot's shown layers for snapshot `state`.
static func masks_of(layout: Dictionary, state: Dictionary) -> PackedInt32Array:
	var masks := PackedInt32Array()
	masks.resize(int(layout.get("slots", 0)))
	var routes: Dictionary = state.get("bridges", {})
	var players: Dictionary = state.get("players", {})
	for mouth: Dictionary in layout.get("mouths", []):
		var open := bool(routes.get(mouth.route, false))
		var mask := 0
		if mouth.stair_gate and not open: mask |= POSTS | CHAIN
		if not str(mouth.owner).is_empty() and open: mask |= POSTS | (OPEN if owner_at_mouth(mouth, players.get(mouth.owner)) else SHUT)
		masks[mouth.slot] = mask
	for span: Dictionary in layout.get("spans", []):
		masks[span.slot] = POSTS | (0 if _near_span(span, players.get(span.owner)) else ROPE)
	for lock: Dictionary in layout.get("locks", []):
		masks[lock.slot] = PADLOCK if not locked_by(lock, players).is_empty() else 0
	return masks

## Whether the owner `player` (a snapshot player, cm) opens `mouth`: on its
## crossing, or within OPEN_CM of its end, at its height.
static func owner_at_mouth(mouth: Dictionary, player: Variant) -> bool:
	if not player is Dictionary or not player.has("x"): return false
	var at := Vector2(float(player.x), float(player.z)) / 100.0
	var height := float(player.get("height", 0))
	var rect: Rect2 = mouth.rect
	if rect.grow(0.04).has_point(at) and height >= float(mouth.low) - NEAR_HEIGHT_CM and height <= float(mouth.high) + NEAR_HEIGHT_CM: return true
	var end: Vector3 = mouth.at
	return at.distance_to(Vector2(end.x, end.z)) * 100.0 <= OPEN_CM and absf(height - end.y * 100.0) <= NEAR_HEIGHT_CM

static func _near_span(span: Dictionary, player: Variant) -> bool:
	if not player is Dictionary or not player.has("x"): return false
	var a: Vector3 = span.a
	var b: Vector3 = span.b
	if absf(float(player.get("height", 0)) - a.y * 100.0) > NEAR_HEIGHT_CM: return false
	var at := Vector2(float(player.x), float(player.z)) / 100.0
	var nearest := Geometry2D.get_closest_point_to_segment(at, Vector2(a.x, a.z), Vector2(b.x, b.z))
	return at.distance_to(nearest) * 100.0 <= ROPE_OPEN_CM

## The slot of the pip (not the owner) standing at `lock`'s control, or "".
static func locked_by(lock: Dictionary, players: Dictionary) -> String:
	for slot: String in players:
		if slot == lock.owner: continue
		if at_control(lock.entity, players[slot]): return slot
	return ""

## Whether `player` stands at `entity` the way its owner would work it: within
## its radius on its floor (its height, for a control with no floor of its own).
static func at_control(entity: Dictionary, player: Variant) -> bool:
	if not player is Dictionary or not player.has("x"): return false
	if entity.has("surface_id"):
		if str(player.get("surface_id", "")) != str(entity.surface_id): return false
	elif absf(float(player.get("height", 0)) - float(entity.get("height_cm", 0))) > NEAR_HEIGHT_CM: return false
	var position: Array = entity.position_cm
	return Vector2(float(player.x), float(player.z)).distance_to(Vector2(float(position[0]), float(position[1]))) <= float(entity.get("radius_cm", 40))

## What refuses `slot`'s step from `player` (cm) along `push` (a unit Vector2)
## by a rule the barriers show, given the snapshot's open routes: {kind (OWNER,
## STAIR or ZONE), id} or {} for none (a gap, water, a wall, nothing). The
## engine's own reach: a spirit's centre stops `radius` short of floor it may
## not use, so the probe looks one step past that.
static func refusal(view: Dictionary, routes: Dictionary, player: Dictionary, slot: String, push: Vector2, radius: int, step: int) -> Dictionary:
	var at := Vector2(float(player.x), float(player.z))
	var height := float(player.get("height", 0))
	var probe := at + push * float(radius + step)
	var moved := at + push * float(step)
	for kind: String in ["bridges", "stairs"]:
		for route: Dictionary in view.get(kind, []):
			var r: Array = route.rect_cm
			if not Rect2(float(r[0]), float(r[1]), float(r[2] - r[0]), float(r[3] - r[1])).has_point(probe): continue
			var low := float(route.get("from_height_cm", route.get("height_cm", 0)))
			var high := float(route.get("to_height_cm", route.get("height_cm", low)))
			var near := height >= minf(low, high) - 4.0 and height <= maxf(low, high) + 4.0
			if kind == "stairs": near = absf(height - low) <= 4.0 or absf(height - high) <= 4.0
			if not near: continue
			var open := bool(routes.get(str(route.id), false))
			var owner := _owner(route)
			if open and not owner.is_empty() and owner != slot: return {"kind": OWNER, "id": str(route.id)}
			if not open and kind == "stairs": return {"kind": STAIR, "id": str(route.id)}
	for zone: Dictionary in view.get("access_zones", []):
		var owner := _owner(zone)
		if owner.is_empty() or owner == slot or str(zone.get("surface_id", "")) != str(player.get("surface_id", "")): continue
		var r: Array = zone.rect_cm
		var closest := Vector2(clampf(moved.x, float(r[0]), float(r[2])), clampf(moved.y, float(r[1]), float(r[3])))
		if closest.distance_to(moved) < float(radius): return {"kind": ZONE, "id": str(zone.get("id", ""))}
	return {}

# --- Building ---------------------------------------------------------------------

## Works out the stage's barriers from `view` and draws them under the world's
## terrain. Call after the world's skip()s, before the ownership marks are
## placed (they keep clear of the barriers through _pair_keep_clear).
func build(view: Dictionary) -> void:
	# The stage's own things a gate's posts may stand in, gathered before the
	# layout so they hold none of the barriers themselves.
	var scenery: Array = FloorSpots.stage_things(view) if _world == null else FloorSpots.scenery(view, _world, 0.0)
	_layout = layout(view, _skips)
	var slots := int(_layout.slots)
	if slots > MAX_SLOTS: push_warning("RouteBarriers: %d slots on one stage; past %d they share the last" % [slots, MAX_SLOTS])
	_masks = PackedInt32Array()
	_masks.resize(slots)
	_states.resize(MAX_SLOTS)
	_states.fill(Vector4.ZERO)
	if slots == 0: return
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var look := _edge_look()
	_note_clashes(scenery)
	for mouth: Dictionary in _layout.mouths: _gate(tool, mouth)
	for span: Dictionary in _layout.spans: _edge(tool, span, look)
	for lock: Dictionary in _layout.locks: _padlock(tool, lock, _anchor(lock.entity))
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"wiggle_lean", WIGGLE_LEAN)
	_material.set_shader_parameter(&"wiggle_rate", WIGGLE_RATE)
	_material.set_shader_parameter(&"clock", 0.0)
	_material.set_shader_parameter(&"states", _states)
	_node = MeshInstance3D.new()
	_node.name = "RouteBarriers"
	_node.mesh = tool.commit()
	_node.material_override = _material
	_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.get("terrain").add_child(_node)

## Notes in each gate's "clash" what its posts run into among the stage's own
## things (FloorSpots.scenery: controls, the goal, stairs, obstacles, drops,
## the world's keep-clear), so a level that puts a lever in a gate's way is
## named by the tests. Marks and pair tags come later and keep clear of the
## gates themselves.
func _note_clashes(things: Array) -> void:
	for mouth: Dictionary in _layout.mouths:
		var at: Vector3 = mouth.at
		var along := Vector2(mouth.along)
		var across := Vector2(along.y, -along.x)
		var clash: Array = []
		# A post in the stage's way (a gauge, a lever) steps out from the
		# crossing a little at a time until it stands clear.
		var shifts: Array = [0.0, 0.0]
		for index in range(2):
			var side := -1.0 if index == 0 else 1.0
			var hits: Array = []
			for step in range(POST_STEPS + 1):
				shifts[index] = float(step) * POST_STEP
				mouth["post_shift"] = shifts
				hits = _post_clash(mouth, side, things, at.y)
				if hits.is_empty(): break
			for what: String in hits:
				if what not in clash: clash.append(what)
		mouth["clash"] = clash

## What the post on `side` of `mouth` stands in among `things`.
static func _post_clash(mouth: Dictionary, side: float, things: Array, y: float) -> Array:
	var post := post_of(mouth, side)
	var rect := Rect2(post - Vector2.ONE * POST * 0.5, Vector2.ONE * POST)
	var found: Array = []
	for thing: Dictionary in things:
		if str(thing.get("what", "")) == "stair " + str(mouth.route): continue
		if thing.has("y") and absf(float(thing.y) - y) > FloorSpots.SAME_FLOOR: continue
		if FloorSpots.hits(rect, thing): found.append(str(thing.what))
	return found

## Where a control's padlock hangs from: the world's floor point of it.
func _anchor(entity: Dictionary) -> Vector3:
	if _world != null and _world.has_method(&"_pair_control_anchor"): return _world.call(&"_pair_control_anchor", entity)
	return Vector3(float(entity.position_cm[0]) / 100.0, 0.0, float(entity.position_cm[1]) / 100.0)

## Posts at both sides of the end, a shut leaf across it (two halves meeting
## in the middle), the same halves swung open along the crossing's sides, and
## for a stair gate a bar and a hanging chain between the posts.
func _gate(tool: SurfaceTool, mouth: Dictionary) -> void:
	var at: Vector3 = mouth.at
	var along := Vector3(mouth.along.x, 0, mouth.along.y)
	var across := Vector3(mouth.along.y, 0, -mouth.along.x)
	var half := float(mouth.half)
	var slot := int(mouth.slot)
	var colour := OwnerMark.color(str(mouth.owner)) if not str(mouth.owner).is_empty() else CREAM
	var post_at: Array[Vector3] = []
	for side: float in [-1.0, 1.0]:
		var flat := post_of(mouth, side)
		var foot := Vector3(flat.x, at.y, flat.y)
		post_at.append(foot)
		_piece(tool, foot + Vector3(0, POST_TALL * 0.5, 0), Vector3(POST, POST_TALL, POST), along, TIMBER, slot, POSTS, at.y)
		_piece(tool, foot + Vector3(0, POST_TALL + CAP.y * 0.5, 0), CAP, along, TIMBER_DARK, slot, POSTS, at.y)
	if not str(mouth.owner).is_empty():
		# Open, a bridge's halves lie along its sides just inside it; a stair's
		# lie back along its floor, clear of the treads.
		var swing := along if mouth.kind == &"bridge" else -along
		for side: float in [-1.0, 1.0]:
			# A shut half: from its post's side of the end to the middle, just on
			# the crossing, so the floor beside it stays free for marks and tags.
			var hinge := at + across * side * half + along * LEAF_ON
			# A bridge's halves meet in a shallow V on the deck, so a gate seen
			# nearly edge on from the camera still shows its pickets.
			var angle := SHUT_ANGLE if mouth.kind == &"bridge" else 0.0
			var inward := (-across * side) * cos(angle) + along * sin(angle)
			_leaf(tool, hinge, inward, (half - 0.004) / cos(angle), Vector3.UP.cross(inward).normalized() * -side, colour, slot, SHUT, at.y)
			_leaf(tool, hinge - across * side * LEAF_IN, swing, open_length(half), across, colour, slot, OPEN, at.y)
	if mouth.stair_gate:
		# A painted bar in red and cream stripes across the top, and the chain below.
		for stripe in range(BAR_STRIPES):
			var from := post_at[0].lerp(post_at[1], float(stripe) / float(BAR_STRIPES)) + Vector3(0, BAR_HEIGHT, 0)
			var to := post_at[0].lerp(post_at[1], float(stripe + 1) / float(BAR_STRIPES)) + Vector3(0, BAR_HEIGHT, 0)
			_bar(tool, from, to, BAR, BAR_RED if stripe % 2 == 0 else CREAM, slot, CHAIN, at.y)
		var previous := post_at[0] + Vector3(0, CHAIN_TOP, 0)
		for index in range(1, CHAIN_LINKS + 1):
			var t := float(index) / float(CHAIN_LINKS)
			var point := post_at[0].lerp(post_at[1], t) + Vector3(0, CHAIN_TOP - CHAIN_SAG * sin(PI * t), 0)
			_bar(tool, previous, point, LINK, IRON, slot, CHAIN, at.y)
			previous = point

## One gate leaf from `hinge` along `run` for `length`: pickets on two rails,
## facing `normal`, under a broad cap rail that reads from the chapter
## camera's height.
func _leaf(tool: SurfaceTool, hinge: Vector3, run: Vector3, length: float, normal: Vector3, colour: Color, slot: int, layer: int, floor_y: float) -> void:
	for height: float in RAIL_HEIGHTS:
		_bar(tool, hinge + Vector3(0, height, 0), hinge + run * length + Vector3(0, height, 0), RAIL.y, colour.darkened(0.12), slot, layer, floor_y, RAIL.z)
	var count := maxi(2, int(floor(length / PICKET_STEP)))
	for index in range(count):
		var centre := hinge + run * (length * (float(index) + 0.5) / float(count)) + Vector3(0, 0.012 + PICKET.y * 0.5, 0) + normal * 0.004
		_piece(tool, centre, PICKET, normal, colour, slot, layer, floor_y)
	var top := Vector3(0, 0.012 + PICKET.y + LEAF_CAP.y * 0.5, 0) + normal * 0.004
	_bar(tool, hinge + top, hinge + run * length + top, LEAF_CAP.y, colour.lightened(0.18), slot, layer, floor_y, LEAF_CAP.z)

## A zone edge stretch in `look` (EDGE_LOOKS): a post at each end and the
## rope or beam between.
func _edge(tool: SurfaceTool, span: Dictionary, look: Dictionary) -> void:
	var a: Vector3 = span.a
	var b: Vector3 = span.b
	var slot := int(span.slot)
	var colour := OwnerMark.color(str(span.owner))
	var run := (b - a).normalized()
	var post: Vector3 = look.post
	for end: Vector3 in [a, b]:
		_piece(tool, end + Vector3(0, post.y * 0.5, 0), post, run, look.post_colour, slot, POSTS, a.y)
		# Capped posts wear the owner's colour on top, to read over pale stone.
		if look.capped: _piece(tool, end + Vector3(0, post.y + CAP.y * 0.5, 0), CAP, run, colour, slot, POSTS, a.y)
	var beam := float(look.beam)
	if beam > 0.0:
		_bar(tool, a + Vector3(0, post.y - beam * 0.5, 0), b + Vector3(0, post.y - beam * 0.5, 0), beam, TIMBER, slot, ROPE, a.y)
		_bar(tool, a + Vector3(0, post.y + 0.009, 0), b + Vector3(0, post.y + 0.009, 0), 0.018, colour, slot, ROPE, a.y, beam * 1.1)
	var rope := float(look.rope)
	if rope <= 0.0: return
	var height := float(look.rope_height)
	var previous := a + Vector3(0, height, 0)
	for index in range(1, 5):
		var t := float(index) / 4.0
		var point := a.lerp(b, t) + Vector3(0, height - float(look.sag) * sin(PI * t), 0)
		_bar(tool, previous, point, rope, colour, slot, ROPE, a.y)
		previous = point

## The zone edge look the level picks: its world's "barrier" style (the
## dressing's look slot, content/dressing/prop_styles.gd), as an EDGE_LOOKS entry.
func _edge_look() -> Dictionary:
	var style := str(_world.call(&"_barrier_style")) if _world != null and _world.has_method(&"_barrier_style") else ""
	var edge := StringName(str(PropStyles.SLOTS.barrier.get(style, {}).get("edge", DEFAULT_EDGE)))
	return EDGE_LOOKS.get(edge, EDGE_LOOKS[DEFAULT_EDGE])

## A padlock over a control: a brass body and an iron shackle.
func _padlock(tool: SurfaceTool, lock: Dictionary, anchor: Vector3) -> void:
	var lift := float(LOCK_LIFT.get(lock.kind, 0.5))
	var centre := anchor + LOCK_SIDE + Vector3(0, lift, 0)
	var slot := int(lock.slot)
	_piece(tool, centre, LOCK_BODY, Vector3.BACK, BRASS, slot, PADLOCK, anchor.y)
	var top := centre + Vector3(0, LOCK_BODY.y * 0.5, 0)
	var width := LOCK_BODY.x * 0.62
	for side: float in [-1.0, 1.0]:
		_bar(tool, top + Vector3(side * width * 0.5, 0, 0), top + Vector3(side * width * 0.5, 0.05, 0), SHACKLE, IRON, slot, PADLOCK, anchor.y)
	_bar(tool, top + Vector3(-width * 0.5 - SHACKLE * 0.5, 0.05, 0), top + Vector3(width * 0.5 + SHACKLE * 0.5, 0.05, 0), SHACKLE, IRON, slot, PADLOCK, anchor.y)

## A box `size` (x across, y up, z along `facing`) centred at `centre`.
static func _piece(tool: SurfaceTool, centre: Vector3, size: Vector3, facing: Vector3, colour: Color, slot: int, layer: int, floor_y: float) -> void:
	var forward := Vector3(facing.x, 0, facing.z).normalized()
	if forward.is_zero_approx(): forward = Vector3.BACK
	var side := Vector3.UP.cross(forward).normalized()
	_cuboid(tool, Transform3D(Basis(side, Vector3.UP, forward), centre), size, colour, slot, layer, floor_y)

## A bar of square section `width` (or `depth` deep) from one point to another.
static func _bar(tool: SurfaceTool, from: Vector3, to: Vector3, width: float, colour: Color, slot: int, layer: int, floor_y: float, depth: float = -1.0) -> void:
	var run := to - from
	var length := run.length()
	if length < 0.0005: return
	var along := run / length
	var helper := Vector3.UP if absf(along.y) < 0.9 else Vector3.BACK
	var side := helper.cross(along).normalized()
	var up := along.cross(side).normalized()
	_cuboid(tool, Transform3D(Basis(side, up, along), (from + to) * 0.5), Vector3(depth if depth > 0.0 else width, width, length), colour, slot, layer, floor_y)

## A box of `size` placed by `shape` (its basis columns unit length), every
## vertex carrying its slot and layer (UV2) and its height over `floor_y` (UV.y).
static func _cuboid(tool: SurfaceTool, shape: Transform3D, size: Vector3, colour: Color, slot: int, layer: int, floor_y: float) -> void:
	var half := size * 0.5
	tool.set_color(colour)
	tool.set_uv2(Vector2(float(mini(slot, MAX_SLOTS - 1)), float(layer)))
	for axis in range(3):
		for sign: float in [-1.0, 1.0]:
			var normal := Vector3.ZERO
			normal[axis] = sign
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			var corners: Array[Vector3] = []
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var local := Vector3.ZERO
				local[axis] = half[axis] * sign
				local[u] = half[u] * corner.x
				local[v] = half[v] * corner.y
				corners.append(shape * local)
			var world_normal := (shape.basis * normal).normalized()
			var order := [0, 2, 1, 0, 3, 2] if sign > 0.0 else [0, 1, 2, 0, 2, 3]
			tool.set_normal(world_normal)
			for index: int in order:
				tool.set_uv(Vector2(0.0, maxf(corners[index].y - floor_y, 0.0)))
				tool.add_vertex(corners[index])

# --- Presenting -----------------------------------------------------------------------

## Shows snapshot `state`: each slot's pieces, and a wiggle at each refusal it
## names (its "refused" and "locked", from presentation/barrier_refusals.gd).
## A tick shown again (the memory wait shows its last tick once more at the
## ring) starts nothing new. Returns the tick's new pushes, for the world to
## bump its spirits.
func present(state: Dictionary) -> Array:
	_present_rings(state)
	var tick := int(state.get("tick", -1))
	var fresh: Array = state.get("refused", NO_EVENTS) if tick != _event_tick else NO_EVENTS
	var locks: Array = state.get("locked", NO_EVENTS) if tick != _event_tick else NO_EVENTS
	if not fresh.is_empty() or not locks.is_empty(): _event_tick = tick
	if _material == null or _layout.is_empty(): return fresh
	var masks := masks_of(_layout, state)
	var changed := masks != _masks
	_masks = masks
	if not _reduced_motion:
		for event: Variant in fresh + locks:
			if event is Dictionary: changed = _wiggle(event, state) or changed
	if changed: _write_states()
	return fresh

func _write_states() -> void:
	for slot in range(mini(_masks.size(), MAX_SLOTS)):
		var state := _states[slot]
		_states[slot] = Vector4(float(_masks[slot]), state.y, state.z, state.w)
	_material.set_shader_parameter(&"states", _states)

## Starts the wiggle of the barrier `event` names nearest its pip. True when one starts.
func _wiggle(event: Dictionary, state: Dictionary) -> bool:
	var player: Variant = state.get("players", {}).get(str(event.get("slot", "")))
	if not player is Dictionary: return false
	var at := Vector2(float(player.x), float(player.z)) / 100.0
	var push: Vector2 = event.get("push", Vector2.ZERO)
	var best := -1
	var best_distance := INF
	for mouth: Dictionary in _layout.mouths if str(event.kind) in [OWNER, STAIR] else []:
		if mouth.route != str(event.id): continue
		var distance := at.distance_to(Vector2(mouth.at.x, mouth.at.z))
		if distance < best_distance:
			best = mouth.slot
			best_distance = distance
	for span: Dictionary in _layout.spans if str(event.kind) == ZONE else []:
		if span.zone != str(event.id): continue
		var distance := at.distance_to(Geometry2D.get_closest_point_to_segment(at, Vector2(span.a.x, span.a.z), Vector2(span.b.x, span.b.z)))
		if distance < best_distance:
			best = span.slot
			best_distance = distance
	for lock: Dictionary in _layout.locks if str(event.kind) == LOCK else []:
		if lock.id == str(event.id): best = lock.slot
	if best < 0 or best >= MAX_SLOTS: return false
	# A barrier shakes back and forth along the push; a padlock side to side.
	if push.is_zero_approx(): push = Vector2.RIGHT
	_wiggles[best] = WIGGLE_SECONDS
	var current := _states[best]
	_states[best] = Vector4(current.x, 1.0, push.x, push.y)
	return true

## Something wiggles: the world calls advance() each frame until it stops.
func moving() -> bool:
	return not _wiggles.is_empty()

func advance(delta: float) -> void:
	if _wiggles.is_empty() or _material == null: return
	_clock += maxf(delta, 0.0)
	for slot: int in _wiggles.keys():
		var left := float(_wiggles[slot]) - delta
		var current := _states[slot]
		if left <= 0.0:
			_wiggles.erase(slot)
			_states[slot] = Vector4(current.x, 0.0, 0.0, 0.0)
		else:
			_wiggles[slot] = left
			_states[slot] = Vector4(current.x, left / WIGGLE_SECONDS, current.z, current.w)
	if _wiggles.is_empty(): _clock = 0.0
	_material.set_shader_parameter(&"clock", _clock)
	_material.set_shader_parameter(&"states", _states)

# --- The ball's lock ring -------------------------------------------------------------

## A lock ring for each rolling ball (`balls`: prop id -> its node), built
## hidden beside it under `parent`.
func build_rings(balls: Dictionary, radii: Dictionary, parent: Node3D) -> void:
	for id: String in balls:
		var radius := float(radii.get(id, 0.2))
		var ring := Primitives.mesh_node(Primitives.cached_shape(Primitives.ring_mesh(radius + BALL_RING_OUT)), Primitives.shared_material(BALL_RING_COLOUR), Vector3.ZERO, parent)
		ring.name = "BallLock_" + id
		ring.visible = false
		_rings[id] = ring
		_ring_radius[id] = radius

## Shows a ball's lock ring while the second pip may not push it yet: in the
## second turn, until it takes the ball over.
func _present_rings(state: Dictionary) -> void:
	if _rings.is_empty(): return
	var second := str(state.get("role", "")) == "b"
	for id: String in _rings:
		var ring: MeshInstance3D = _rings[id]
		if not is_instance_valid(ring): continue
		var prop: Variant = state.get("props", {}).get(id)
		var locked: bool = second and prop is Dictionary and str(prop.get("status", "")) in ["free", "offered"]
		ring.visible = locked
		# Round the ball's middle (the world draws a ball's centre BALL_LIFT up).
		if locked: ring.position = Vector3(float(prop.x) / 100.0, float(prop.get("height", 0)) / 100.0 + BALL_LIFT, float(prop.z) / 100.0)

# --- Reading ----------------------------------------------------------------------

## The stage's layout ({} before build()).
func placed() -> Dictionary:
	return _layout

## Each slot's shown layers now.
func masks() -> PackedInt32Array:
	return _masks

## Nodes that change after the build (the ball rings): kept out of the static fold.
func moving_nodes() -> Array:
	var found: Array = []
	if is_instance_valid(_node): found.append(_node)
	for ring: Variant in _rings.values():
		if is_instance_valid(ring): found.append(ring)
	return found

## Where a gate's post on side (-1 or 1) of its end stands (m, across the
## floor): just outside the crossing's width, on its floor.
static func post_of(mouth: Dictionary, side: float) -> Vector2:
	var along := Vector2(mouth.along)
	var across := Vector2(along.y, -along.x)
	var shift := float((mouth.get("post_shift", NO_SHIFT) as Array)[0 if side < 0.0 else 1])
	return Vector2(mouth.at.x, mouth.at.z) + across * side * (float(mouth.half) + POST * 0.5 + 0.006 + shift) - along * (POST * 0.5)

## How long an open half of a gate `half` wide at its end is.
static func open_length(half: float) -> float:
	return minf(half, OPEN_LEAF)

## What marks and pair tags keep clear of: each gate's posts and its leaves
## (shut on the crossing; a stair's open halves on the floor before it), each
## zone edge's line, as discs and rects on their floors (FloorSpots data).
func discs() -> Array:
	var found: Array = []
	for mouth: Dictionary in _layout.get("mouths", []):
		var at: Vector3 = mouth.at
		var along := Vector2(mouth.along)
		var across := Vector2(along.y, -along.x)
		var half := float(mouth.half)
		var end := Vector2(at.x, at.z)
		for side: float in [-1.0, 1.0]:
			var post := post_of(mouth, side)
			# A small disc: marks and tags keep their own gap (FloorSpots, 2 to
			# 5 cm) past it, which already clears the post's corners.
			found.append({"centre": post, "radius": POST * 0.25, "y": at.y, "what": "a post of the gate at %s" % mouth.route})
			if mouth.kind == &"stair" and not str(mouth.owner).is_empty():
				var hinge := end + across * side * (half - LEAF_IN)
				found.append({"rect": Rect2(hinge, Vector2.ZERO).expand(hinge - along * open_length(half)).grow(RAIL.z), "y": at.y, "what": "the open gate at %s" % mouth.route})
		# The shut leaf on the crossing, a bridge's V reaching further in.
		var depth := LEAF_CAP.z * 0.5 + 0.004 + (half * tan(SHUT_ANGLE) * 0.5 if mouth.kind == &"bridge" else 0.0)
		var line := end + along * (LEAF_ON + depth - LEAF_CAP.z * 0.5 - 0.004)
		var extent := (across * half).abs() + (along * depth).abs()
		found.append({"rect": Rect2(line - extent, extent * 2.0), "y": at.y, "what": "the gate at %s" % mouth.route})
	for span: Dictionary in _layout.get("spans", []):
		var a: Vector3 = span.a
		var b: Vector3 = span.b
		var low := Vector2(minf(a.x, b.x), minf(a.z, b.z))
		var high := Vector2(maxf(a.x, b.x), maxf(a.z, b.z))
		found.append({"rect": Rect2(low, high - low).grow(0.03), "y": a.y, "what": "the edge of zone %s" % span.zone})
	return found

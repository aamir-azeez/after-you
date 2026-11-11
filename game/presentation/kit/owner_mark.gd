extends RefCounted
## World kit: the ownership marks that say which spirit a lever, a stair, a
## pad, a crossing or a zone belongs to. The first spirit's mark is a gold
## diamond and the second's a teal ring, so shape repeats what colour says.
##
## The marks come from the stage itself: build(view) marks every lever,
## selector, mirror, pad, stair, owned crossing, zone, handoff and source
## region whose owner_slot names a spirit, and nothing without one. KINDS says
## where each kind's mark wants to sit (how far from its anchor and how
## high); a mark that would land on a stair, a control, the goal, the handoff,
## scenery, a floor cable or another mark is moved to the nearest clear spot
## on its floor by the same helper and avoid list the pair tags use
## (kit/floor_spots.gd), never closer to what it marks than its kind's place. A world supplies the floor point of a
## control (_pair_control_anchor) and of a stair's foot (_mark_stair), says
## which goals carry a mark (_marks_goal) and which crossings
## (_marks_route_owner), and names scenery to keep clear of (keep_clear,
## _pair_keep_clear). A mark the world draws itself (a bucket's, a stand
## spot's) goes through mark() or record() before build(), and build() then
## leaves that control alone. Each world keeps one of these (cooperative_world's
## owner_marks) and starts it over with each stage.
##
## Heights: a mark's top stays under a spirit's ground shadow
## (SpiritVisual.SHADOW_TOP) and clear of a crossing's remembered footsteps
## and of a cable meeting it, at least 3 mm from either (test_dressing_lint
## COPLANAR), so nothing z-fights.
##
## Presentation only: built from the hashed stage, and nothing here feeds the
## simulation, a recording or a checkpoint. placed() lists what was marked as
## plain data for tests.
##
## Cost: every mark is a plain leaf with a kit-cached mesh and look
## (Primitives, released through SessionRelease), so the world's static fold
## (kit/static_batch.gd) folds it into the batch of its colour that the stage
## draws anyway: marks add no draw call of their own. Nothing here runs per
## frame. A mark node is never given metadata, a script or children, and this
## object never holds one; only a mark its world holds or hangs on something
## that moves (a bucket) stays out of the fold.
const Primitives = preload("res://presentation/kit/primitives.gd")
const FloorSpots = preload("res://presentation/kit/floor_spots.gd")
const GOLD := Color("f4c38d")
const TEAL := Color("91d6c6")
## The diamond's side: turned 45 degrees it reaches REACH from its centre
## along x and z, and anything meeting a mark at its height stops there.
const SIDE := 0.17
const REACH := SIDE * 0.7072
const THICKNESS := 0.018
## The ring: Primitives.ring_mesh of this radius (its tube 5 cm across).
const RING_RADIUS := 0.13
## A crossing's end marks' centres sit this high above its floor plane.
const ROUTE_LIFT := 0.025
## Where each kind of mark sits: "reach" metres from its anchor along the way
## the caller says is away (toward the camera unless it says otherwise) and
## "lift" metres above the anchor (the mark's centre).
const KINDS := {
	## Beside a lever, valve or selector, in front of its post.
	&"lever": {"reach": 0.33, "lift": 0.025},
	## In front of a mirror's hand wheel.
	&"mirror": {"reach": 0.35, "lift": 0.025},
	## In front of a goal cradle (a lantern, a window).
	&"goal": {"reach": 0.42, "lift": 0.025},
	## On the floor before a stair's foot, away from the stair.
	&"stair": {"reach": 0.24, "lift": 0.03},
	## Before a rope ladder's foot, past its roll.
	&"ladder": {"reach": 0.36, "lift": 0.03},
	## On a pressure pad's disc, under its rim.
	&"pad": {"reach": 0.0, "lift": 0.06},
	## On a hanging bucket's floor (its rim sits lower than a pad's).
	&"bucket": {"reach": 0.0, "lift": 0.058},
	## On a waiting region's centre.
	&"endpoint": {"reach": 0.0, "lift": 0.025},
	## At each side of a handoff ring.
	&"handoff": {"reach": 0.6, "lift": 0.03},
	## Beyond each end of an owned crossing (route_ends()).
	&"route_end": {"reach": 0.18, "lift": ROUTE_LIFT},
	## Along an owned zone's middle (zone()); tops 2 cm up, under a shadow.
	&"zone": {"reach": 0.0, "lift": 0.011},
	## A stand spot's own small mark (kit/stand_spot.gd builds it with spot()).
	&"spot": {"reach": 0.0, "lift": 0.0},
}
## A zone's marks: the first this far in from its west edge, then one every
## ZONE_STEP_CM. Its edge strip runs a centimetre short of the zone's ends, so
## it never shares a face with a bed or wall drawn on a neighbouring rectangle.
const ZONE_FIRST_CM := 24
const ZONE_STEP_CM := 64
const ZONE_EDGE := Vector3(0.0, 0.018, 0.035)
const ZONE_EDGE_LIFT := 0.012
## A mark keeps this far from what it avoids; a moved mark looks this far out
## in steps of MOVE_STEP.
const CLEAR := 0.02
const MOVE_STEP := 0.06
const MOVE_RINGS := 14
## Two marks of one owner on one floor closer than this (about a mark's
## width and a gap) become one mark at their middle: one mark for the spot.
## Marks of different owners never merge; they keep apart.
const MERGE := 0.36
## Kinds a mark that sits on its own control or region: never moved.
const ON_ITS_OWN := [&"pad", &"bucket", &"endpoint", &"zone", &"spot"]

## The world whose terrain the marks lie on.
var _world: Node3D
var _keep_clear: Array[Rect2] = []
var _placed: Array[Dictionary] = []
## Each placed mark's node when the kit drew it under the terrain (else null).
var _nodes: Array = []

func _init(world: Node3D = null) -> void:
	_world = world

## A new stage: what was marked before goes (its nodes went with the terrain).
func clear() -> void:
	_placed.clear()
	_nodes.clear()

## Marks keep `edge` clear of `rect` (terrain space, x and z): scenery at a
## mark's height.
func keep_clear(rect: Rect2, edge: float = 0.02) -> void:
	_keep_clear.append(rect.grow(edge))

## The colour of a slot's mark.
static func color(slot: String) -> Color:
	return GOLD if slot == "p0" else TEAL

## A mark the world draws itself, exactly where it says (`anchor` in
## `parent`'s space, `away` the way it steps off): build() then leaves `id` be.
func mark(slot: String, kind: StringName, id: String, anchor: Vector3, parent: Node3D, away: Vector3 = Vector3.BACK) -> void:
	var spec: Dictionary = KINDS[kind]
	_put(slot, kind, id, anchor + (away * float(spec.reach) + Vector3(0, float(spec.lift), 0)), parent, [])

## Marks every owned thing of the stage `view` that its world has not marked
## itself, each where its kind wants it or at the nearest clear spot.
func build(view: Dictionary) -> void:
	var terrain: Node3D = _world.get("terrain")
	var done: Dictionary = {}
	for mark: Dictionary in _placed: done[str(mark.id)] = true
	var floors := FloorSpots.floors_of(view)
	var things := FloorSpots.scenery(view, _world, reach_of("p1"))
	for rect: Rect2 in _keep_clear: things.append({"rect": rect, "what": "the world's scenery"})
	# Cables and ropes lying on the floor at a mark's height; a crossing's end
	# marks are where its cables end, so only other marks keep off them.
	var cables: Array = _world.call(&"floor_cables")
	var wanted: Array = []
	for zone: Dictionary in view.get("access_zones", []):
		if _owned(zone) and not done.has(str(zone.get("id", ""))): _zone(str(zone.owner_slot), str(zone.get("id", "")), zone.rect_cm, float(_world.call(&"_surface_height", str(zone.surface_id))), terrain)
	for pad: Dictionary in view.get("pressure_pads", []):
		if _owned(pad) and not done.has(str(pad.id)): wanted.append([pad.owner_slot, &"pad", pad.id, _world.call(&"_pair_control_anchor", pad), Vector3.BACK])
	var endpoint: Dictionary = view.get("source_policy", {}).get("endpoint", {})
	if _owned(endpoint): wanted.append([endpoint.owner_slot, &"endpoint", endpoint.get("id", "endpoint"), _world.call(&"_pair_control_anchor", endpoint), Vector3.BACK])
	for lever: Dictionary in view.get("levers", []):
		if _owned(lever) and not done.has(str(lever.id)): wanted.append([lever.owner_slot, &"lever", lever.id, _world.call(&"_pair_control_anchor", lever), Vector3.BACK])
	for control: Dictionary in view.get("controls", []):
		if _owned(control) and not done.has(str(control.id)): wanted.append([control.owner_slot, &"mirror" if str(control.get("kind", "")) == "mirror" else &"lever", control.id, _world.call(&"_pair_control_anchor", control), Vector3.BACK])
	for stair: Dictionary in view.get("stairs", []):
		if not _owned(stair) or done.has(str(stair.id)): continue
		var foot: Dictionary = _world.call(&"_mark_stair", stair)
		wanted.append([stair.owner_slot, foot.get("kind", &"stair"), stair.id, foot.anchor, foot.away, foot.get("head", null)])
	for route: Dictionary in view.get("bridges", []):
		if not _owned(route) or done.has(str(route.id)) or not _world.call(&"_marks_route_owner", route): continue
		var height := Vector3(0, float(route.get("height_cm", route.get("from_height_cm", 0))) / 100.0, 0)
		var ends := route_ends_of(route, view.get("islands", []))
		# The end points are the marks' own places already.
		wanted.append([route.owner_slot, &"route_end", route.id, ends[0] + height, Vector3.ZERO])
		wanted.append([route.owner_slot, &"route_end", route.id, ends[1] + height, Vector3.ZERO])
	var handoff: Variant = view.get("handoff")
	if handoff is Dictionary and handoff.has("position_cm"):
		var at: Vector3 = _world.call(&"_pair_control_anchor", handoff)
		wanted.append(["p0", &"handoff", "handoff", at, Vector3.LEFT])
		wanted.append(["p1", &"handoff", "handoff", at, Vector3.RIGHT])
	var goal: Dictionary = view.get("goal", {})
	if _owned(goal) and _world.call(&"_marks_goal", goal): wanted.append([goal.owner_slot, &"goal", goal.get("id", "goal"), _world.call(&"_pair_control_anchor", goal), Vector3.BACK])
	for want: Array in wanted:
		var slot := str(want[0])
		var kind: StringName = want[1]
		var id := str(want[2])
		var spec: Dictionary = KINDS[kind]
		var reach := float(spec.reach) if kind != &"route_end" else 0.0
		var anchor: Vector3 = want[3]
		var place: Vector3 = anchor + (want[4] as Vector3) * reach
		# A stair without room at its foot is marked at its head instead; a
		# control without room in front of it, behind it.
		var ends: Array = [place]
		if want.size() > 5 and want[5] is Vector3: ends.append(want[5])
		elif reach > 0.0 and kind != &"handoff": ends.append(anchor - (want[4] as Vector3) * reach)
		var clash: Array = []
		if kind not in ON_ITS_OWN:
			var size := Vector2.ONE * reach_of(slot) * 2.0
			# Its own control, goal or handoff only as close as the kind's place
			# beside it: a moved mark never slides under what it marks.
			# (A few millimetres less, so the kind's place itself never touches it.)
			var own_room := maxf(reach - reach_of(slot) - CLEAR - 0.005, 0.0)
			var own := things.map(func(thing: Dictionary) -> Dictionary: return _within(thing, own_room) if str(thing.get("owner", "")) == id else thing)
			if kind != &"route_end": own.append_array(cables)
			var spot := FloorSpots.find({"size": size, "ends": ends, "on_crossing": true, "gap": CLEAR, "step": MOVE_STEP, "rings": MOVE_RINGS, "fine": true}, floors, own, discs())
			place = spot.at
			clash = spot.clash
			var other := _merge_with(slot, ends[0], place, float(spec.lift))
			if other >= 0:
				_merge(other, id, ends[0], size, floors, own, float(spec.lift))
				continue
		_put(slot, kind, id, place + Vector3(0, float(spec.lift), 0), terrain, clash)

## The placed mark of `slot` on this floor within MERGE of where a new mark
## wants to be (`wanted`) or was found room (`found`); -1 when none.
func _merge_with(slot: String, wanted: Vector3, found: Vector3, lift: float) -> int:
	for index in range(_placed.size()):
		var mark: Dictionary = _placed[index]
		var at: Vector3 = mark.at
		if mark.slot != slot or absf(at.y - found.y - lift) >= 0.1: continue
		if FloorSpots.flat(at).distance_to(FloorSpots.flat(wanted)) < MERGE or FloorSpots.flat(at).distance_to(FloorSpots.flat(found)) < MERGE: return index
	return -1

## Mark `index` takes in `id` too: a mark that sits on its own control stays
## where it is; any other moves to the clear spot nearest the middle of where
## it is and where `id`'s mark wanted to be.
func _merge(index: int, id: String, wanted: Vector3, size: Vector2, floors: Array, things: Array, lift: float) -> void:
	var mark: Dictionary = _placed[index]
	mark["also"] = (mark.get("also", []) as Array) + [id]
	var node: Variant = _nodes[index]
	if mark.kind in ON_ITS_OWN or not node is Node3D: return
	var at: Vector3 = mark.at
	var middle := Vector3((at.x + wanted.x) * 0.5, at.y - lift, (at.z + wanted.z) * 0.5)
	var others := discs()
	others.remove_at(index)
	var spot := FloorSpots.find({"size": size, "ends": [middle], "on_crossing": true, "gap": CLEAR, "step": MOVE_STEP, "rings": MOVE_RINGS, "fine": true}, floors, things.filter(func(thing: Dictionary) -> bool: return str(thing.get("owner", "")) != str(mark.id)), others)
	mark.at = (spot.at as Vector3) + Vector3(0, lift, 0)
	mark.clash = spot.clash
	(node as Node3D).position = mark.at

## How far a slot's mark reaches from its centre: the diamond's corner, the ring's rim.
static func reach_of(slot: String) -> float:
	return REACH if slot == "p0" else RING_RADIUS + 0.025

static func _owned(thing: Dictionary) -> bool:
	return thing.has("owner_slot") and str(thing.owner_slot) in ["p0", "p1"]

## `thing`, a disc, no wider than `radius`.
static func _within(thing: Dictionary, radius: float) -> Dictionary:
	var small := thing.duplicate()
	small.radius = minf(float(thing.radius), radius)
	return small

## The marks placed so far, as discs for the floor helper and the pair tags.
func discs() -> Array:
	return _placed.map(func(mark: Dictionary) -> Dictionary: return {"centre": FloorSpots.flat(mark.at), "radius": reach_of(str(mark.slot)), "y": (mark.at as Vector3).y, "what": "%s mark %s" % [mark.kind, mark.id]})

## Where a crossing's end marks go, on its floor plane (y 0): before and past
## its two ends the way it joins its floors. A crossing runs west to east
## unless only its north and south ends land on the islands it joins
## (from_surface, to_surface of `islands`); then the end on from_surface comes
## first. A stair keeps its west and east
## ends. Cables and tags that meet a crossing's mark start from here.
static func route_ends_of(route: Dictionary, islands: Array) -> Array[Vector3]:
	var across := route_end_points(route.rect_cm)
	if route.has("axis"): return across
	var rects: Dictionary = {}
	for island: Dictionary in islands: rects[str(island.id)] = FloorSpots.rect_of(island.rect_cm)
	var from: Variant = rects.get(str(route.get("from_surface", "")))
	var to: Variant = rects.get(str(route.get("to_surface", "")))
	if from == null or to == null or _joins(across, from, to): return across
	var along := route_end_points(route.rect_cm, true)
	if not _joins(along, from, to): return across
	# The end on the floor it starts from first, as west comes first across.
	if not (from as Rect2).has_point(FloorSpots.flat(along[0])): along.reverse()
	return along

static func _joins(ends: Array[Vector3], a: Rect2, b: Rect2) -> bool:
	var first := FloorSpots.flat(ends[0])
	var second := FloorSpots.flat(ends[1])
	return (a.has_point(first) and b.has_point(second)) or (a.has_point(second) and b.has_point(first))

## A crossing over `rect_cm`'s end marks' places on its floor plane (y 0):
## before its west end and past its east end, or with `north_south` before
## its north end and past its south end.
static func route_end_points(rect_cm: Array, north_south: bool = false) -> Array[Vector3]:
	var reach := float(KINDS[&"route_end"].reach)
	if north_south:
		var across := float(rect_cm[0] + rect_cm[2]) * 0.5 / 100.0
		return [Vector3(across, 0, float(rect_cm[1]) / 100.0 - reach), Vector3(across, 0, float(rect_cm[3]) / 100.0 + reach)]
	var middle := float(rect_cm[1] + rect_cm[3]) * 0.5
	return [Vector3(float(rect_cm[0]) / 100.0, 0, middle / 100.0) + Vector3(-reach, 0, 0), Vector3(float(rect_cm[2] + int(roundf(reach * 100.0))) / 100.0, 0, middle / 100.0)]

## An owned zone over `rect_cm` on a floor `floor_y` high: marks along its
## middle and a strip of the owner's colour along its north edge.
func _zone(slot: String, id: String, rect_cm: Array, floor_y: float, parent: Node3D) -> void:
	var lift := float(KINDS[&"zone"].lift)
	for x in range(int(rect_cm[0]) + ZONE_FIRST_CM, int(rect_cm[2]), ZONE_STEP_CM):
		var at := Vector3(float(x) / 100.0, floor_y + lift, float(rect_cm[1] + rect_cm[3]) / 200.0)
		# A mark inside scenery to keep clear of steps along the zone to its nearer side.
		for rect: Rect2 in _keep_clear:
			var room := rect.grow(REACH + CLEAR)
			if room.has_point(Vector2(at.x, at.z)): at.x = room.position.x if at.x < room.get_center().x else room.end.x
		_put(slot, &"zone", id, at, parent, [])
	var edge := Primitives.cached_box(Vector3(float(rect_cm[2] - rect_cm[0]) / 100.0 - 0.01, ZONE_EDGE.y, ZONE_EDGE.z))
	Primitives.mesh_node(edge, Primitives.shared_material(color(slot)), Vector3(float(rect_cm[0] + rect_cm[2]) / 200.0, floor_y + ZONE_EDGE_LIFT, float(rect_cm[1]) / 100.0), parent)

## Records a mark another kit piece drew itself (a stand spot's), for placed();
## build() then leaves `id` be.
func record(slot: String, kind: StringName, id: String, at: Vector3, parent: Node3D, clash: Array = []) -> void:
	_placed.append({"slot": slot, "kind": kind, "id": id, "at": on_floor(_world, at, parent), "clash": clash})
	_nodes.append(null)

## What this stage marked: {slot, kind, id, at (terrain space), clash (what a
## mark could not keep clear of; empty when clear), also (ids a merged mark
## stands for too)} per mark.
func placed() -> Array[Dictionary]:
	return _placed.duplicate()

func _put(slot: String, kind: StringName, id: String, at: Vector3, parent: Node3D, clash: Array) -> void:
	var node := shape(slot, at, parent)
	record(slot, kind, id, at, parent, clash)
	if _world != null and parent == _world.get("terrain"): _nodes[-1] = node

## A mark of `slot` at `at` in `parent`: the diamond or the ring.
static func shape(slot: String, at: Vector3, parent: Node3D) -> MeshInstance3D:
	if slot == "p0": return diamond(Primitives.cached_box(Vector3(SIDE, THICKNESS, SIDE)), Primitives.shared_material(GOLD), at, parent)
	return Primitives.mesh_node(Primitives.cached_shape(Primitives.ring_mesh(RING_RADIUS)), Primitives.shared_material(TEAL), at, parent)

## A diamond: `box` (a flat square box) turned 45 degrees.
static func diamond(box: Mesh, look: Material, at: Vector3, parent: Node3D) -> MeshInstance3D:
	var node := Primitives.mesh_node(box, look, at, parent)
	node.rotation.y = PI / 4.0
	return node

## A stand spot's mark (kit/stand_spot.gd), `room` metres of disc around its
## centre at most, `thickness` tall, its top at `top`: the diamond `side`
## across at most, or the ring `ring_outer` across with a `ring_tube` tube.
static func spot(slot: String, room: float, side: float, ring_outer: float, ring_tube: float, thickness: float, top: float, look: Material, parent: Node3D) -> MeshInstance3D:
	var at := Vector3(0, top - thickness * 0.5, 0)
	if slot == "p0":
		# A diamond reaches its side times 0.7072 from its centre.
		var fit := minf(side, room / 0.7072)
		return diamond(Primitives.cached_shape(Primitives.box_mesh(Vector3(fit, thickness, fit))), look, at, parent)
	var ring := TorusMesh.new()
	ring.outer_radius = minf(ring_outer, room)
	ring.inner_radius = ring.outer_radius - ring_tube
	ring.rings = 24
	ring.ring_segments = 8
	var node := Primitives.mesh_node(Primitives.cached_shape(ring), look, at, parent)
	# A flat ring: the torus's tube is as tall as it is wide.
	node.scale.y = thickness / ring_tube
	return node

## `at` in `parent`'s space, in the space of `world`'s terrain it stands on.
static func on_floor(world: Node3D, at: Vector3, parent: Node3D) -> Vector3:
	var terrain: Variant = world.get("terrain") if world != null else null
	var node: Node3D = parent
	var point := at
	while node != null and node != terrain:
		point = node.transform * point
		node = node.get_parent() as Node3D
	return point

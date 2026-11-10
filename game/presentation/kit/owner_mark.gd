extends RefCounted
## World kit: the ownership marks that say which spirit a lever, a stair, a
## pad, a crossing or a zone belongs to. The first spirit's mark is a gold
## diamond and the second's a teal ring, so shape repeats what colour says.
##
## A level author says only what is marked and whose it is:
## mark(slot, kind, id, anchor, parent). KINDS decides how far from the anchor
## and how high the mark sits for each kind, so every lever's mark sits the
## same way, every stair's, every pad's. route_ends() and zone() place the
## marks a crossing or a zone gets. Each world keeps one of these
## (cooperative_world's owner_marks) and starts it over with each stage.
##
## Heights: a mark's top stays under a spirit's ground shadow
## (SpiritVisual.SHADOW_TOP) and clear of a crossing's remembered footsteps
## and of a cable meeting it, at least 3 mm from either (test_dressing_lint
## COPLANAR), so nothing z-fights. A world whose scenery lies at a mark's
## height somewhere names that rectangle with keep_clear(), and a floor mark
## inside it steps to the rectangle's nearer side.
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
## A keep_clear() rectangle stays this far from a mark's edge.
const CLEAR := 0.01

## The world whose `terrain` keep_clear() rectangles lie on.
var _world: Node3D
var _keep_clear: Array[Rect2] = []
var _placed: Array[Dictionary] = []

func _init(world: Node3D = null) -> void:
	_world = world

## A new stage: what was marked before goes (its nodes went with the terrain).
func clear() -> void:
	_placed.clear()

## Floor marks inside `rect` (terrain space, x and z) step to its nearer side
## along x, `edge` plus a mark's reach clear of it.
func keep_clear(rect: Rect2, edge: float = 0.02) -> void:
	_keep_clear.append(rect.grow(edge + REACH + CLEAR))

## The colour of a slot's mark.
static func color(slot: String) -> Color:
	return GOLD if slot == "p0" else TEAL

## Marks `id` (a lever, a stair, a pad...) as `slot`'s: a `kind` of KINDS at
## `anchor` in `parent`'s space, `away` the way it steps off its anchor.
func mark(slot: String, kind: StringName, id: String, anchor: Vector3, parent: Node3D, away: Vector3 = Vector3.BACK) -> void:
	var spec: Dictionary = KINDS[kind]
	# One offset added once, so the mark lands where a hand-placed one did.
	_put(slot, kind, id, anchor + (away * float(spec.reach) + Vector3(0, float(spec.lift), 0)), parent)

## Both ends of an owned crossing over `rect_cm` (along x): one before its west
## end and one past its east end, on its floor plane.
func route_ends(slot: String, id: String, rect_cm: Array, parent: Node3D) -> void:
	for at: Vector3 in route_end_points(rect_cm): _put(slot, &"route_end", id, at + Vector3(0, float(KINDS[&"route_end"].lift), 0), parent)

## Where a crossing over `rect_cm` (along x) has its end marks, on its floor
## plane (y 0): [before its west end, past its east end]. Cables and tags that
## meet a crossing's mark start from here.
static func route_end_points(rect_cm: Array) -> Array[Vector3]:
	var middle := float(rect_cm[1] + rect_cm[3]) * 0.5
	var reach := float(KINDS[&"route_end"].reach)
	return [Vector3(float(rect_cm[0]) / 100.0, 0, middle / 100.0) + Vector3(-reach, 0, 0), Vector3(float(rect_cm[2] + int(roundf(reach * 100.0))) / 100.0, 0, middle / 100.0)]

## A world that raises a crossing after building it (its deck and end marks
## with it) says so, so placed() keeps telling where the marks are.
func lifted(id: String, by: float) -> void:
	for mark: Dictionary in _placed:
		if mark.id == id and mark.kind == &"route_end": mark.at += Vector3(0, by, 0)

## An owned zone over `rect_cm` on a floor `floor_y` high: marks along its
## middle and a strip of the owner's colour along its north edge.
func zone(slot: String, id: String, rect_cm: Array, floor_y: float, parent: Node3D) -> void:
	var lift := float(KINDS[&"zone"].lift)
	for x in range(int(rect_cm[0]) + ZONE_FIRST_CM, int(rect_cm[2]), ZONE_STEP_CM):
		_put(slot, &"zone", id, Vector3(float(x) / 100.0, floor_y + lift, float(rect_cm[1] + rect_cm[3]) / 200.0), parent)
	var edge := Primitives.cached_box(Vector3(float(rect_cm[2] - rect_cm[0]) / 100.0 - 0.01, ZONE_EDGE.y, ZONE_EDGE.z))
	Primitives.mesh_node(edge, Primitives.shared_material(color(slot)), Vector3(float(rect_cm[0] + rect_cm[2]) / 200.0, floor_y + ZONE_EDGE_LIFT, float(rect_cm[1]) / 100.0), parent)

## Records a mark another kit piece drew itself (a stand spot's), for placed().
func record(slot: String, kind: StringName, id: String, at: Vector3, parent: Node3D) -> void:
	_placed.append({"slot": slot, "kind": kind, "id": id, "at": _on_floor(at, parent)})

## What this stage marked: {slot, kind, id, at (terrain space)} per mark.
func placed() -> Array[Dictionary]:
	return _placed.duplicate()

func _put(slot: String, kind: StringName, id: String, at: Vector3, parent: Node3D) -> void:
	if not _keep_clear.is_empty() and _world != null and parent == _world.get("terrain"):
		for rect: Rect2 in _keep_clear:
			if rect.has_point(Vector2(at.x, at.z)): at.x = rect.position.x if at.x < rect.get_center().x else rect.end.x
	shape(slot, at, parent)
	record(slot, kind, id, at, parent)

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

## `at` in `parent`'s space, in the space of the terrain it stands on.
func _on_floor(at: Vector3, parent: Node3D) -> Vector3:
	var terrain: Variant = _world.get("terrain") if _world != null else null
	var node: Node3D = parent
	var point := at
	while node != null and node != terrain:
		point = node.transform * point
		node = node.get_parent() as Node3D
	return point

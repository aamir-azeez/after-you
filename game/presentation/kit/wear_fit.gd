extends RefCounted
## How a hat and a leaf share the head, and how a hat makes way for a carried
## seed or lens. One place for these rules: presentation/pip_outfit.gd asks it
## when it dresses a pip and while the pip carries, and tests/test_wear_fit.gd
## checks every hat against every leaf with the same numbers.
##
## Leaf size: each leaf (the plain leaf, a sprig, an earned leaf, a leaf item)
## is measured from its own solid geometry under the pip's leaf, in the leaf's
## space (its stalk the origin, up along the leaf): how high it stands and how
## far it reaches to either side. Its size class is the first of CLASSES whose
## CLASS_LIMITS hold both. Nobody sets a class by hand.
##
## A hat declares (content/cosmetics/index.gd) how the leaf meets it,
## "leaf_mode", and the largest class it takes, "leaf_max":
## - covers: the leaf hides under it.
## - pokes_through: the leaf stays where it grows, through a real notch or
##   hole. A bigger leaf sits on the hat instead, raised by the hat's
##   "leaf_lift", or hides when the hat has no lift.
## - sits_on_top: the leaf is raised by "leaf_lift" onto the hat. A bigger
##   leaf hides.
## decide() is that table; nothing else picks.
##
## Carrying: a hat whose geometry would come within CLEARANCE of the carried
## seed or lens, anywhere the head and the carried thing move, is put away
## while the pip carries (carry_clashes); so is a leaf that would, anywhere in
## its roll (leaf_carry_clashes). The carried thing never moves for a
## cosmetic.
##
## Measurements are cached per leaf and per hat for the session (no GPU
## resources, but released with the other wear caches through
## kit/session_release.gd so a long session starts clean).
const Look = preload("res://presentation/spirit_look.gd")
const SpiritIdle = preload("res://presentation/spirit_idle.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const SCRIPT_PATH := "res://presentation/kit/wear_fit.gd"
const SPIRIT_PATH := "res://presentation/spirit_visual.gd"

## One pip width: the head, the pip's widest part, across (metres). The
## concept notes give every size and gap in pip widths.
const PIP_WIDTH := Look.HEAD_HALF.x * 2.0
## The least gap kept between a hat and a leaf through the leaf's whole
## motion, and between a shown hat and a carried seed or lens.
const CLEARANCE := 0.04 * PIP_WIDTH
## Beside the leaf a hat's brim or lip stands at most this high over the head.
const LIP_LIMIT := 0.06 * PIP_WIDTH
## "Beside the leaf": within this far of the stalk, across the head's top.
const LEAF_SECTOR := 0.2 * PIP_WIDTH

const SMALL := "small"
const MEDIUM := "medium"
const TALL := "tall"
const CLASSES: Array[String] = [SMALL, MEDIUM, TALL]
## Each class's largest half width (x), height over the stalk (y) and depth
## to front or back (z), in pip widths. A leaf past MEDIUM's is TALL; TALL's
## numbers are only the room a hat cuts for it (leaf_in_the_way).
const CLASS_LIMITS := {SMALL: Vector3(0.11, 0.30, 0.14), MEDIUM: Vector3(0.24, 0.46, 0.26), TALL: Vector3(0.32, 0.62, 0.3)}

const COVERS := "covers"
const POKES_THROUGH := "pokes_through"
const SITS_ON_TOP := "sits_on_top"
const MODES: Array[String] = [COVERS, POKES_THROUGH, SITS_ON_TOP]

## Parts drawn on top that are not solid: a glow, a beam, sparkles, a falling
## effect (kit/fall_effect.gd). They neither size a leaf nor meet a hat.
const NOT_SOLID: Array[String] = ["Halo", "Beam", "Stars", "Fall"]

## How far the head and a carried thing move apart while carried: the head's
## largest tilt (radians; a glance, the idle sway and the release settle,
## spirit_visual.gd _apply_pose) and the carried thing's wobble and the head's
## lift (metres, carry_anchor_position, spirit_idle.gd BREATH_HEAD_LIFT).
const CARRY_TILT := 0.06 + 0.018 + 0.065
const CARRY_WOBBLE := 0.022 + 0.004 + 0.004

## How finely leaf_in_the_way turns a leaf through its roll, and how far a
## stalk reaches into the head under it (spirit_meshes.gd _leaf).
const ROLL_STEPS := 24
const STALK_DEPTH := 0.02
## How square the cut outline is (2 an ellipse, higher nearer a box).
const KEEP_OUT_POWER := 4.0
## How finely a leaf is turned through its roll against a carried thing.
const CARRY_ROLLS := 12

static var _leaf_classes: Dictionary = {}
static var _roll := Vector2.ZERO
static var _carry: Dictionary = {}
static var _leaf_carry: Dictionary = {}

## Lets go of the kept measurements (at shutdown).
static func release_cached() -> void:
	_leaf_classes.clear()
	_carry.clear()
	_leaf_carry.clear()

static func _keep() -> void:
	SessionRelease.on_exit(Callable(load(SCRIPT_PATH), "release_cached"))

# --- Leaf size -------------------------------------------------------------

## The leaf's size class, measured the first time from `leaf` (the pip's leaf,
## dressed as `key`: a leaf item id, or "" for the plain leaf) and kept.
static func leaf_class(key: String, leaf: MeshInstance3D) -> String:
	var found: Variant = _leaf_classes.get(key)
	if found != null: return found
	var made := class_of(measure(leaf))
	_leaf_classes[key] = made
	_keep()
	return made

## The size class of leaf item `id` ("" the plain leaf) without a pip at hand
## (the Wardrobe's preview): measured once on a pip dressed in it alone, then
## kept with the classes measured on real pips.
static func class_for(id: String) -> String:
	var found: Variant = _leaf_classes.get(id)
	if found != null: return found
	var pip: Node3D = load(SPIRIT_PATH).new()
	if not id.is_empty(): pip.wear({"leaf": id})
	# A leaf the pip may not wear (not released) is not kept under its id.
	var worn: bool = id.is_empty() or pip.outfit().get("leaf") == id
	var made := leaf_class(id, pip.sprout) if worn else class_of(measure(pip.sprout))
	pip.free()
	return made

## `outfit` as a preview shows it: without its hat when that hat would hide
## the worn leaf, so a leaf being looked at always shows (the Wardrobe).
static func shown_with(outfit: Dictionary) -> Dictionary:
	var hat := str(outfit.get("hat", ""))
	if hat.is_empty() or not outfit.has("leaf"): return outfit
	if bool(decide(hat, class_for(str(outfit.leaf))).show): return outfit
	var shown := outfit.duplicate()
	shown.erase("hat")
	return shown

## The leaf's half width (x), its height over the stalk (y) and its depth to
## front or back (z), in pip widths, from every solid vertex under it in its
## own space.
static func measure(leaf: MeshInstance3D) -> Vector3:
	var reach := Vector3.ZERO
	for part: MeshInstance3D in solid_meshes(leaf):
		var place := relative(leaf, part)
		for vertex: Vector3 in vertices(part.mesh):
			var point := place * vertex
			reach = Vector3(maxf(reach.x, absf(point.x)), maxf(reach.y, point.y), maxf(reach.z, absf(point.z)))
	return reach / PIP_WIDTH

## The first class whose limits hold `size` (pip widths).
static func class_of(size: Vector3) -> String:
	for name: String in [SMALL, MEDIUM]:
		var limit: Vector3 = CLASS_LIMITS[name]
		if size.x <= limit.x and size.y <= limit.y and size.z <= limit.z: return name
	return TALL

static func rank(name: String) -> int:
	return CLASSES.find(name)

# --- Hat and leaf ------------------------------------------------------------

## What happens to a leaf of class `leaf` under the hat `hat_id` ("" for no
## hat): {"show": bool, "lift": metres}.
static func decide(hat_id: String, leaf: String) -> Dictionary:
	if hat_id.is_empty(): return {"show": true, "lift": 0.0}
	return rule(Catalog.leaf_mode(hat_id), Catalog.leaf_max(hat_id), Catalog.leaf_lift(hat_id), leaf)

## The table itself, for a hat that takes the leaf in `mode`, up to class
## `largest`, raising it `lift` metres when it sits on the hat.
static func rule(mode: String, largest: String, lift: float, leaf: String) -> Dictionary:
	var fits := rank(leaf) <= rank(largest)
	match mode:
		COVERS: return {"show": false, "lift": 0.0}
		POKES_THROUGH:
			if fits: return {"show": true, "lift": 0.0}
			return {"show": lift > 0.0, "lift": lift}
		SITS_ON_TOP: return {"show": fits, "lift": lift}
	# A hat that declares nothing leaves the leaf as it grows.
	return {"show": true, "lift": lift}

## The range of the leaf's roll about its stalk against the head (radians,
## positive leaning away from the head's middle) on top of its rest lean,
## over every motion it has: the idle sway or the doze droop, the startled
## wake's jolt, the walking step and the release settle (spirit_visual.gd
## _apply_pose; tests/test_wear_fit.gd checks a pip never leaves it).
static func leaf_roll() -> Vector2:
	if _roll != Vector2.ZERO: return _roll
	var jolt := Vector2.ZERO
	for step in range(201):
		var p := float(step) / 200.0
		var value := sin(p * TAU * 1.5) * (1.0 - p)
		jolt = Vector2(minf(jolt.x, value), maxf(jolt.y, value))
	# Loaded, not preloaded: spirit_visual.gd dresses through pip_outfit.gd, which reads this file.
	var spirit: Dictionary = (load(SPIRIT_PATH) as Script).get_script_constant_map()
	var walk := float(spirit.LEAF_STEP_ROLL) + float(spirit.SETTLE_SWING) * float(spirit.LEAF_SETTLE)
	_roll = Vector2(-SpiritIdle.LEAF_SWAY + SpiritIdle.WAKE_LEAF * jolt.x - walk, maxf(SpiritIdle.LEAF_SWAY, SpiritIdle.DOZE_LEAF_DROOP) + SpiritIdle.WAKE_LEAF * jolt.y + walk)
	return _roll

## Whether head-space `point` is in the way of a leaf of class `largest`
## growing in its own place, anywhere in its roll (leaf_roll), with CLEARANCE
## to spare: inside that class's limits about the stalk, its outline across
## and up rounded (KEEP_OUT_POWER) the way leaves taper, turned through the
## roll. A hat builder cuts its notch where this holds; tests/test_wear_fit.gd
## checks the real leaves against the real notch.
static func leaf_in_the_way(point: Vector3, largest: String) -> bool:
	var limit: Vector3 = CLASS_LIMITS[largest] * PIP_WIDTH + Vector3.ONE * CLEARANCE
	var from := point - (Look.LEAF_PIVOT - Look.HEAD_CENTER)
	if from.length() > limit.length(): return false
	var roll := leaf_roll()
	for step in range(ROLL_STEPS + 1):
		var turn := Look.LEAF_LEAN + lerpf(roll.x, roll.y, float(step) / float(ROLL_STEPS))
		var leaf := from.rotated(Vector3.BACK, -turn)
		if absf(leaf.z) > limit.z or leaf.y < -STALK_DEPTH - CLEARANCE or leaf.y > limit.y: continue
		var up := (leaf.y + STALK_DEPTH + CLEARANCE) / (limit.y + STALK_DEPTH + CLEARANCE) * 2.0 - 1.0
		if pow(absf(leaf.x) / limit.x, KEEP_OUT_POWER) + pow(absf(up), KEEP_OUT_POWER) <= 1.0: return true
	return false

# --- Carrying ------------------------------------------------------------------

## Where the carried seed or lens of `radius` sits in the upper body's space
## (spirit_visual.gd carry_anchor_position, before its wobble and hop).
static func carry_centre(radius: float) -> Vector3:
	return Vector3(0.0, float(load(SPIRIT_PATH).carry_height(radius)), 0.0)

## Whether the hat `hat_id`, whose solid parts are `parts` (MeshInstance3D
## under `body`, the pip's upper body), comes too near a carried thing of
## `radius` as the head tilts and the thing wobbles. Kept per hat and radius.
static func carry_clashes(hat_id: String, body: Node3D, parts: Array, radius: float) -> bool:
	var key := "%s:%.3f" % [hat_id, radius]
	var found: Variant = _carry.get(key)
	if found != null: return found
	var made := carry_gap(body, parts, radius) < CLEARANCE
	_carry[key] = made
	_keep()
	return made

## The least gap between `parts` and a carried thing of `radius`, through the
## head's tilt either way and the thing's wobble (metres; INF with no parts).
## A part on the head is taken at the head's rest place, then tilted about
## its centre; a part on the body stays put.
static func carry_gap(body: Node3D, parts: Array, radius: float) -> float:
	var gap := INF
	for part: MeshInstance3D in parts:
		var head := _head_of(body, part)
		var points := vertices(part.mesh)
		for tilt: float in ([-CARRY_TILT, 0.0, CARRY_TILT] if head != null else [0.0]):
			var place := relative(body, part)
			if head != null: place = Transform3D(Basis(Vector3.BACK, tilt), Look.HEAD_CENTER) * relative(head, part)
			gap = minf(gap, _gap_to(points, place, radius, gap))
	return gap

## Whether the leaf dressed as `key` (`leaf`, the pip's leaf), raised `lift`,
## comes too near a carried thing of `radius` anywhere in its roll as the head
## tilts and the thing wobbles (all at their worst at once): nearer than
## CLEARANCE, and more than CLEARANCE nearer than the pip's own plain leaf
## comes where it grows, the game's own look and so the baseline (a sprig, the
## same shape, never clashes). Kept per leaf, lift and radius.
static func leaf_carry_clashes(key: String, leaf: MeshInstance3D, lift: float, radius: float) -> bool:
	var cache := "%s:%.3f:%.3f" % [key, lift, radius]
	var found: Variant = _leaf_carry.get(cache)
	if found != null: return found
	var made := leaf_carry_gap(leaf_points(leaf), lift, radius) < carry_allowance(radius)
	_leaf_carry[cache] = made
	_keep()
	return made

## The least gap a leaf must keep from a carried thing of `radius`, measured
## at the worst: CLEARANCE, or a CLEARANCE inside the plain leaf's own gap
## where it grows when that is less.
static func carry_allowance(radius: float) -> float:
	var key := "plain:%.3f" % radius
	var found: Variant = _leaf_carry.get(key)
	if found == null:
		const Meshes = preload("res://presentation/spirit_meshes.gd")
		found = minf(CLEARANCE, leaf_carry_gap(vertices(Meshes.leaf()), 0.0, radius) - CLEARANCE)
		_leaf_carry[key] = found
		_keep()
	return found

## Every solid triangle's corners under `leaf`, in the leaf's own space.
static func leaf_points(leaf: MeshInstance3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	for part: MeshInstance3D in solid_meshes(leaf):
		var place := relative(leaf, part)
		for point: Vector3 in vertices(part.mesh): points.append(place * point)
	return points

## The least gap between a leaf's triangles (`points`, leaf space) and a
## carried thing of `radius`, through the leaf's roll and the head's tilt,
## the leaf raised `lift` (metres).
static func leaf_carry_gap(points: PackedVector3Array, lift: float, radius: float) -> float:
	var roll := leaf_roll()
	var gap := INF
	for tilt: float in [-CARRY_TILT, 0.0, CARRY_TILT]:
		var head := Transform3D(Basis(Vector3.BACK, tilt), Look.HEAD_CENTER)
		for step in range(CARRY_ROLLS + 1):
			var turn := Look.LEAF_LEAN + lerpf(roll.x, roll.y, float(step) / float(CARRY_ROLLS))
			var place := head * Transform3D(Basis(Vector3.BACK, turn), Look.LEAF_PIVOT - Look.HEAD_CENTER + Vector3(0.0, lift, 0.0))
			gap = minf(gap, _gap_to(points, place, radius, gap))
	return gap

## The least gap from triangles `points` placed by `place` to a
## carried thing of `radius`, less its wobble: worked in the triangles' own
## space, and skipped (INF) when their box is already farther than `beaten`.
static func _gap_to(points: PackedVector3Array, place: Transform3D, radius: float, beaten: float) -> float:
	if points.is_empty(): return INF
	if not place.basis.get_scale().is_equal_approx(Vector3.ONE):
		# A scaled part is measured where it is drawn.
		var placed := PackedVector3Array()
		for point: Vector3 in points: placed.append(place * point)
		return _gap_to(placed, Transform3D.IDENTITY, radius, beaten)
	var centre := place.affine_inverse() * carry_centre(radius)
	var box := AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points: box = box.expand(point)
	var outside := (centre - centre.clamp(box.position, box.end)).length()
	if outside - radius - CARRY_WOBBLE >= beaten: return INF
	var gap := INF
	for index in range(0, points.size() - 2, 3):
		gap = minf(gap, closest_on_triangle(centre, points[index], points[index + 1], points[index + 2]).distance_to(centre) - radius - CARRY_WOBBLE)
	return gap

## The head `part` hangs from, or null for a part on the body.
static func _head_of(body: Node3D, part: Node) -> Node3D:
	var node := part
	while node != null and node != body:
		if node.name == "Head": return node as Node3D
		node = node.get_parent()
	return null

# --- Geometry --------------------------------------------------------------------

## The solid meshes at and under `node` (skipping NOT_SOLID parts and what
## hangs from them).
static func solid_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node.name in NOT_SOLID: return found
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null: found.append(node)
	for child: Node in node.get_children(): found.append_array(solid_meshes(child))
	return found

## `node`'s transform in `top`'s space, by its parents (in a tree or not).
static func relative(top: Node3D, node: Node3D) -> Transform3D:
	var place := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != top:
		if at is Node3D: place = (at as Node3D).transform * place
		at = at.get_parent()
	return place

## Every triangle's three corners in order, from all of a mesh's surfaces.
static func vertices(mesh: Mesh) -> PackedVector3Array:
	var points := PackedVector3Array()
	if mesh == null: return points
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var corners: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices is PackedInt32Array and not (indices as PackedInt32Array).is_empty():
			for index: int in indices: points.append(corners[index])
		else: points.append_array(corners)
	return points

## The point of triangle a b c nearest to p. A triangle with no area (a
## sphere's pole, a blade's pointed tip) is taken as its edges, so the answer
## is never NaN, which would quietly reset a running minimum.
static func closest_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	if ab.cross(ac).length_squared() < 1e-16:
		var best := Geometry3D.get_closest_point_to_segment(p, a, b)
		for edge: Vector3 in [Geometry3D.get_closest_point_to_segment(p, a, c), Geometry3D.get_closest_point_to_segment(p, b, c)]:
			if edge.distance_squared_to(p) < best.distance_squared_to(p): best = edge
		return best
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0: return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3: return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0: return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6: return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0: return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0: return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denominator := 1.0 / (va + vb + vc)
	return a + ab * (vb * denominator) + ac * (vc * denominator)

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
## - pokes_through: the leaf stays where it grows, beside the hat (a hat on
##   the head's far side, such as the Paper boat). A bigger leaf sits on the
##   hat instead, raised by the hat's "leaf_lift", or hides when the hat has no
##   lift. No hat is cut open for the leaf.
## - sits_on_top: the hat is whole and the leaf comes out of its top, raised
##   by "leaf_lift" on a short stem (the caps). A bigger leaf hides.
## decide() is that table; nothing else picks. The hats players owned before
## the fit (Straw hat, fruit hoods, Blossom crown) keep the leaf as it was,
## by the owner's choice (tests/test_wear_fit.gd OWNER_KEPT).
##
## Measurements are cached per leaf for the session (no GPU
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
## motion.
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
## to front or back (z), in pip widths. A leaf past MEDIUM's is TALL.
const CLASS_LIMITS := {SMALL: Vector3(0.11, 0.30, 0.14), MEDIUM: Vector3(0.24, 0.46, 0.26)}

const COVERS := "covers"
const POKES_THROUGH := "pokes_through"
const SITS_ON_TOP := "sits_on_top"
const MODES: Array[String] = [COVERS, POKES_THROUGH, SITS_ON_TOP]

## Parts drawn on top that are not solid: a glow, a beam, sparkles, a falling
## effect (kit/fall_effect.gd). They neither size a leaf nor meet a hat.
const NOT_SOLID: Array[String] = ["Halo", "Beam", "Stars", "Fall"]

static var _leaf_classes: Dictionary = {}
static var _roll := Vector2.ZERO

## Lets go of the kept measurements (at shutdown).
static func release_cached() -> void:
	_leaf_classes.clear()

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

# --- Parts ---------------------------------------------------------------------

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

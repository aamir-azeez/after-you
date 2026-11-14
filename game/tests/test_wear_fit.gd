extends SceneTree
## Hats, leaves and carried things on a pip (presentation/kit/wear_fit.gd):
## - every leaf (the plain leaf, the sprigs, the earned Gold leaf and Every
##   Hard, every leaf item) gets its size class from its own geometry;
## - every hat declares its way with the leaf and the largest class it takes,
##   and the runtime does what the one table says (show, raise or hide);
## - the leaf's roll against the head never leaves the range the fit sweeps;
## - every hat against every leaf, by geometry: a shown leaf keeps CLEARANCE
##   from the hat through its whole roll (a raised leaf's stalk may tuck into
##   the hat); every failing pair is named. Checked point to triangle both
##   ways and edge through triangle both ways, through a grid, so it stays
##   fast as items are added;
## - beside the leaf a hat that lets it poke through stays under LIP_LIMIT;
## - carrying a seed or lens: the carried thing sits exactly where it does on
##   a plain pip, a hat or a leaf that would come too near is put away, what
##   still shows keeps CLEARANCE through walking, turning and the release
##   settle, and it all comes back after.
const Spirit = preload("res://presentation/spirit_visual.gd")
const Outfit = preload("res://services/outfit.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const Index = preload("res://content/cosmetics/index.gd")
const Look = preload("res://presentation/spirit_look.gd")
const Meshes = preload("res://presentation/spirit_meshes.gd")
const WearFit = preload("res://presentation/kit/wear_fit.gd")
const SessionRelease = preload("res://presentation/kit/session_release.gd")

const DT := 1.0 / 60.0
## A raised leaf's stalk may stand in the hat this far from its pivot.
const STALK_TUCK := 0.045
## Steps through the leaf's roll for the pair check.
const ROLLS := 16
## The grid's cell for the pair check (metres).
const CELL := 0.05
## The whole hat by leaf check must finish within this many milliseconds.
const PAIR_BUDGET_MS := 30000
## The first carry's sums must take under this (milliseconds, a desktop run).
const FIRST_CARRY_MS := 60
## The hats that sit to one side of the leaf's root, so it grows where it
## always does, each with where it sits; a hat over the leaf's root (a cap,
## the Straw hat, a hood) is whole and raises the leaf out of its top.
const BESIDE := {
	"daisy": "a flower on the head's far front corner",
	"seashell": "a shell on the head's front side, under the leaf",
	"lantern": "hangs on the far side",
	"lighthouse_lamp": "on the head's far corner",
	"top_ten_ribbon": "a rosette on the far front corner",
	"paper_boat": "on the head's far side, its end raised away from the leaf",
	"flower_pot": "on the head's far side, leaning away from the leaf",
	"tea_cup": "on the head's far side",
	"wave_cap": "the waves run across the far side of the head",
	"glass_house": "on the head's far side",
}
## Leaves the fit must class as these.
const EXPECTED := {"": WearFit.SMALL, "sprig_coral": WearFit.SMALL, "gold_leaf": WearFit.SMALL, "every_hard": WearFit.SMALL, "apple_leaf": WearFit.TALL}

var checks := 0
var failures := 0
var _hats: Array[String] = []
var _leaves: Array[String] = [""]

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _run() -> void:
	Outfit.show_unreleased = true
	for id: String in Catalog.ids():
		if Catalog.slot(id) == "hat": _hats.append(id)
		elif Catalog.slot(id) == "leaf": _leaves.append(id)
	_declarations()
	_table()
	_classes()
	_roll_range()
	_pairs()
	_lips()
	_preview()
	_carrying()
	_leaves_carrying()
	_first_carry_time()
	_released()
	for child: Node in root.get_children():
		if child is Spirit: child.free()
	print("WEAR FIT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _spirit(outfit: Dictionary = {}) -> Node3D:
	var spirit: Node3D = Spirit.new(Look.PEACH)
	root.add_child(spirit)
	spirit.wear(outfit)
	spirit.advance_motion(Vector3.ZERO, 0.001, true)
	return spirit

func _declarations() -> void:
	for id: String in Catalog.ids():
		var mode := Catalog.leaf_mode(id)
		if Catalog.slot(id) == "hat":
			_check(mode in WearFit.MODES, "%s (hat) declares its way with the leaf: %s" % [id, mode])
			_check(Catalog.leaf_max(id) in WearFit.CLASSES, "%s takes leaves up to a known class: %s" % [id, Catalog.leaf_max(id)])
			if mode == WearFit.SITS_ON_TOP: _check(Catalog.leaf_lift(id) > 0.0, "%s raises the leaf it sits on top" % id)
		else: _check(mode.is_empty(), "%s is not a hat and declares no leaf way" % id)
	for file: Script in Index.ITEMS:
		_check(not (file.DATA as Dictionary).has("leaf_class"), "%s sets no leaf class by hand" % file.DATA.id)
	# No hat is cut open for the leaf: a hat over the leaf's place raises it out
	# of its top; only hats that sit beside the leaf leave it where it grows.
	for id: String in _hats:
		if Catalog.leaf_mode(id) == WearFit.POKES_THROUGH: _check(BESIDE.has(id), "%s leaves the leaf where it grows, so it must sit beside it (BESIDE)" % id)
	for id: String in BESIDE: _check(Catalog.leaf_mode(id) == WearFit.POKES_THROUGH, "%s, beside the leaf, leaves it where it grows" % id)

## The one table, for every way and class.
func _table() -> void:
	for largest: String in WearFit.CLASSES:
		for leaf: String in WearFit.CLASSES:
			var fits := WearFit.rank(leaf) <= WearFit.rank(largest)
			_check(WearFit.rule(WearFit.COVERS, largest, 0.05, leaf) == {"show": false, "lift": 0.0}, "A covering hat hides a %s leaf" % leaf)
			_check(WearFit.rule(WearFit.SITS_ON_TOP, largest, 0.05, leaf) == {"show": fits, "lift": 0.05}, "A hat up to %s raises a %s leaf onto it, or hides it" % [largest, leaf])
			_check(WearFit.rule(WearFit.POKES_THROUGH, largest, 0.0, leaf) == {"show": fits, "lift": 0.0}, "A hat beside the leaf, taking up to %s, shows a %s leaf in its place, or hides it" % [largest, leaf])
			_check(WearFit.rule(WearFit.POKES_THROUGH, largest, 0.05, leaf) == ({"show": true, "lift": 0.0} if fits else {"show": true, "lift": 0.05}), "and with a lift raises a bigger one onto it")
	_check(WearFit.decide("", WearFit.TALL) == {"show": true, "lift": 0.0}, "With no hat every leaf shows where it grows")

## Classes come from geometry: measured on a pip, the same however often asked.
func _classes() -> void:
	for leaf: String in _leaves:
		var spirit := _spirit(Outfit.of(leaf, true) if not leaf.is_empty() else {})
		var size := WearFit.measure(spirit.sprout)
		var made := WearFit.class_of(size)
		_check(WearFit.leaf_class(leaf, spirit.sprout) == made, "%s's kept class is its measured class" % _name(leaf))
		print("LEAF %s: half width %.3f, height %.3f, depth %.3f pip widths -> %s" % [_name(leaf), size.x, size.y, size.z, made])
		if EXPECTED.has(leaf): _check(made == EXPECTED[leaf], "%s measures as %s: %s" % [_name(leaf), EXPECTED[leaf], made])
		spirit.free()

## Against the head, the leaf only rolls about its stalk (plus a hat's lift):
## through idle sway, walking, the release settle, a doze and the startled
## wake it stays inside WearFit.leaf_roll().
func _roll_range() -> void:
	var spirit := _spirit()
	var sweep := WearFit.leaf_roll()
	var seen := Vector2(INF, -INF)
	var place_ok := true
	for frame in range(1500):
		var step := Vector3.ZERO
		if frame >= 300 and frame < 480: step = Vector3(0.04, 0, 0)
		if frame == 480: spirit.play_carry_release()
		if frame == 600: spirit.set_pose(&"doze")
		if frame == 1000: spirit.set_pose(&"rest")
		if frame == 1001: spirit.play_wake(false)
		spirit.advance_motion(step, DT, false)
		var relative: Transform3D = spirit.head.transform.affine_inverse() * spirit.sprout.transform
		var roll := atan2(-relative.basis.y.x, relative.basis.y.y) - Look.LEAF_LEAN
		seen = Vector2(minf(seen.x, roll), maxf(seen.y, roll))
		place_ok = place_ok and relative.origin.is_equal_approx(Look.LEAF_PIVOT - Look.HEAD_CENTER)
	_check(seen.x >= sweep.x - 0.001 and seen.y <= sweep.y + 0.001, "The leaf's roll %.3f..%.3f stays in the swept range %.3f..%.3f" % [seen.x, seen.y, sweep.x, sweep.y])
	_check(seen.y - seen.x > 0.3, "and the run really moved it: %.3f" % (seen.y - seen.x))
	_check(place_ok, "Its stalk keeps its place on the head")
	spirit.free()

# --- Every hat against every leaf -------------------------------------------

## One item's solid triangles in a space, with a grid over them.
class Shape:
	var corners := PackedVector3Array()
	var points := PackedVector3Array()
	var grid: Dictionary = {}
	var bounds := AABB()

	func _init(triangles: PackedVector3Array, cell: float, inflate: float) -> void:
		corners = triangles
		var unique: Dictionary = {}
		for point: Vector3 in triangles: unique[point] = true
		for point: Variant in unique: points.append(point)
		if triangles.is_empty(): return
		bounds = AABB(triangles[0], Vector3.ZERO)
		for index in range(0, triangles.size(), 3):
			var box := AABB(triangles[index], Vector3.ZERO).expand(triangles[index + 1]).expand(triangles[index + 2]).grow(inflate)
			bounds = bounds.merge(box)
			var low := Vector3i((box.position / cell).floor())
			var high := Vector3i((box.end / cell).floor())
			for x in range(low.x, high.x + 1):
				for y in range(low.y, high.y + 1):
					for z in range(low.z, high.z + 1):
						var key := Vector3i(x, y, z)
						if not grid.has(key): grid[key] = PackedInt32Array()
						grid[key].append(index)

	## The least distance from `point` to a triangle, and whether `from`-`to`
	## passes through one (INF when nothing is near).
	func gap(point: Vector3, cell: float) -> float:
		var found: Variant = grid.get(Vector3i((point / cell).floor()))
		if found == null: return INF
		var least := INF
		for index: int in found:
			least = minf(least, point.distance_to(WearFit.closest_on_triangle(point, corners[index], corners[index + 1], corners[index + 2])))
		return least

	## Every cell the segment's box touches is searched, so a long edge
	## through a face far from its middle is still found.
	func crosses(from: Vector3, to: Vector3, cell: float) -> bool:
		var low := Vector3i((from.min(to) / cell).floor())
		var high := Vector3i((from.max(to) / cell).floor())
		var tried: Dictionary = {}
		for x in range(low.x, high.x + 1):
			for y in range(low.y, high.y + 1):
				for z in range(low.z, high.z + 1):
					var found: Variant = grid.get(Vector3i(x, y, z))
					if found == null: continue
					for index: int in found:
						if tried.has(index): continue
						tried[index] = true
						if Geometry3D.segment_intersects_triangle(from, to, corners[index], corners[index + 1], corners[index + 2]) != null: return true
		return false

## A part's solid triangles moved into a space by `place`, dropping any
## triangle wholly inside the head (hidden, so it meets nothing).
func _triangles(parts: Array, place: Callable) -> PackedVector3Array:
	var out := PackedVector3Array()
	for part: MeshInstance3D in parts:
		var to: Transform3D = place.call(part)
		var raw := WearFit.vertices(part.mesh)
		for index in range(0, raw.size() - 2, 3):
			var a := to * raw[index]
			var b := to * raw[index + 1]
			var c := to * raw[index + 2]
			if _in_head(a) and _in_head(b) and _in_head(c): continue
			out.append_array(PackedVector3Array([a, b, c]))
	return out

func _in_head(point: Vector3) -> bool:
	return Meshes.head_level(point) < 1.0

## The hat's solid triangles in head space at rest.
func _hat_shape(hat: String) -> Shape:
	var spirit := _spirit(Outfit.of(hat, true))
	var head_at := Transform3D(Basis(), Look.HEAD_CENTER).affine_inverse()
	var parts: Array = []
	for node: Node in spirit._wearing._slot_nodes.get("hat", []): parts.append_array(WearFit.solid_meshes(node))
	var triangles := _triangles(parts, func(part: Node3D) -> Transform3D:
		var head := WearFit._head_of(spirit.upper_body, part)
		return WearFit.relative(head, part) if head != null else head_at * WearFit.relative(spirit.upper_body, part))
	spirit.free()
	return Shape.new(triangles, CELL, WearFit.CLEARANCE)

## The leaf's solid triangles in its own space (the stalk at the origin).
func _leaf_triangles(leaf: String) -> PackedVector3Array:
	var spirit := _spirit(Outfit.of(leaf, true) if not leaf.is_empty() else {})
	var sprout: MeshInstance3D = spirit.sprout
	var out := PackedVector3Array()
	for part: MeshInstance3D in WearFit.solid_meshes(sprout):
		var to := WearFit.relative(sprout, part)
		for point: Vector3 in WearFit.vertices(part.mesh): out.append(to * point)
	spirit.free()
	return out

## How the leaf sits on the head at roll `roll`, raised `lift`.
func _leaf_place(roll: float, lift: float) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, Look.LEAF_LEAN + roll), Look.LEAF_PIVOT - Look.HEAD_CENTER + Vector3(0, lift, 0))

func _pairs() -> void:
	var started := Time.get_ticks_msec()
	var hats: Dictionary = {}
	for hat: String in _hats: hats[hat] = _hat_shape(hat)
	var leaves: Dictionary = {}
	for leaf: String in _leaves: leaves[leaf] = _leaf_triangles(leaf)
	var sweep := WearFit.leaf_roll()
	var failing: Array[String] = []
	var shown := 0
	var hidden := 0
	for hat: String in _hats:
		for leaf: String in _leaves:
			var outfit := {"hat": hat}
			if not leaf.is_empty(): outfit.leaf = leaf
			var spirit := _spirit(Outfit.from(outfit, true))
			var fit: Dictionary = WearFit.decide(hat, WearFit.leaf_class(leaf, spirit.sprout))
			var lift: float = spirit._wearing.leaf_lift
			var visible: bool = spirit.sprout.visible
			spirit.free()
			var art_hides := leaf.is_empty() and Catalog.art(hat).ends_with("fruit_hood.gd")
			_check(visible == (bool(fit.show) and not art_hides) and is_equal_approx(lift, float(fit.lift)), "%s with %s: the pip does what the fit says %s" % [hat, _name(leaf), fit])
			if not visible:
				hidden += 1
				continue
			shown += 1
			var gap := _gap(hats[hat], leaves[leaf], sweep, lift)
			if gap < WearFit.CLEARANCE: failing.append("%s + %s (gap %.4f)" % [hat, _name(leaf), gap])
	var took := Time.get_ticks_msec() - started
	print("PAIRS: %d hats x %d leaves, %d shown, %d hidden, %d ms" % [_hats.size(), _leaves.size(), shown, hidden, took])
	_check(failing.is_empty(), "Every shown leaf keeps %.4f clear of its hat through its roll; failing: %s" % [WearFit.CLEARANCE, ", ".join(failing)])
	_check(took < PAIR_BUDGET_MS, "The hat by leaf check stays fast: %d ms" % took)

## The least gap between the hat and the leaf, through the leaf's roll,
## raised `lift`: each leaf point to the hat's triangles, each hat point to the
## leaf's, and any edge of one through a face of the other (0 then). A raised
## leaf's stalk may tuck into the hat.
func _gap(hat: Shape, leaf_triangles: PackedVector3Array, sweep: Vector2, lift: float) -> float:
	var least := INF
	var tuck := STALK_TUCK if lift > 0.0 else 0.0
	for step in range(ROLLS + 1):
		var place := _leaf_place(lerpf(sweep.x, sweep.y, float(step) / float(ROLLS)), lift)
		var placed := PackedVector3Array()
		for point: Vector3 in leaf_triangles: placed.append(place * point)
		var leaf := Shape.new(_visible(placed, place.origin, tuck), CELL, WearFit.CLEARANCE)
		if leaf.corners.is_empty() or not leaf.bounds.intersects(hat.bounds): continue
		for point: Vector3 in leaf.points:
			if hat.bounds.has_point(point): least = minf(least, hat.gap(point, CELL))
		for point: Vector3 in hat.points:
			if leaf.bounds.has_point(point): least = minf(least, leaf.gap(point, CELL))
		for pair: Array in [[leaf, hat], [hat, leaf]]:
			var edges: Shape = pair[0]
			for index in range(0, edges.corners.size(), 3):
				for side in range(3):
					var a := edges.corners[index + side]
					var b := edges.corners[index + (side + 1) % 3]
					if (pair[1] as Shape).bounds.intersects(AABB(a, Vector3.ZERO).expand(b)) and (pair[1] as Shape).crosses(a, b, CELL): least = 0.0
	return least

## The leaf's triangles that show: not wholly in the head, and not wholly in
## the tucked stalk near `stalk`.
func _visible(triangles: PackedVector3Array, stalk: Vector3, tuck: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for index in range(0, triangles.size() - 2, 3):
		var hidden := true
		for corner in range(3):
			var point := triangles[index + corner]
			if not _in_head(point) and point.distance_to(stalk) > tuck: hidden = false
		if not hidden: out.append_array(PackedVector3Array([triangles[index], triangles[index + 1], triangles[index + 2]]))
	return out

## The Wardrobe's preview shows a leaf being looked at: a hat that would hide
## it comes off the preview; otherwise the outfit shows as worn.
func _preview() -> void:
	_check(WearFit.class_for("apple_leaf") == WearFit.TALL and WearFit.class_for("") == WearFit.SMALL, "A leaf's class is known without a pip at hand")
	_check(WearFit.shown_with({"hat": "paper_boat", "leaf": "apple_leaf"}) == {"leaf": "apple_leaf"}, "A hat that hides the leaf comes off its preview")
	_check(WearFit.shown_with({"hat": "straw_hat", "leaf": "gold_leaf"}) == {"hat": "straw_hat", "leaf": "gold_leaf"}, "A hat that shows the leaf stays on")
	_check(WearFit.shown_with({"hat": "rain_cap"}) == {"hat": "rain_cap"}, "A hat with the plain leaf stays on")

# --- The lip beside the leaf ------------------------------------------------

## A hat the leaf pokes through stands at most LIP_LIMIT over the head within
## LEAF_SECTOR of the stalk (its corners and the middles of its faces).
func _lips() -> void:
	var stalk := Vector2(Look.LEAF_PIVOT.x, Look.LEAF_PIVOT.z)
	for hat: String in _hats:
		if Catalog.leaf_mode(hat) != WearFit.POKES_THROUGH: continue
		var shape := _hat_shape(hat)
		var highest := -INF
		for index in range(0, shape.corners.size(), 3):
			var points := [shape.corners[index], shape.corners[index + 1], shape.corners[index + 2], (shape.corners[index] + shape.corners[index + 1] + shape.corners[index + 2]) / 3.0]
			for point: Vector3 in points:
				if Vector2(point.x, point.z).distance_to(stalk) > WearFit.LEAF_SECTOR or point.y < 0.0: continue
				highest = maxf(highest, point.y - _head_top(point))
		_check(highest <= WearFit.LIP_LIMIT, "%s stays under the lip limit beside the leaf: %.4f over the head (limit %.4f)" % [hat, highest, WearFit.LIP_LIMIT])

## The head's top under head-space point `point`, or its middle where it has none.
func _head_top(point: Vector3) -> float:
	var left := 1.0 - pow(absf(point.x / Look.HEAD_HALF.x), Look.HEAD_POWER) - pow(absf(point.z / Look.HEAD_HALF.z), Look.HEAD_POWER)
	return Look.HEAD_HALF.y * pow(left, 1.0 / Look.HEAD_POWER) if left > 0.0 else 0.0

# --- Carrying -----------------------------------------------------------------

## A seed and the Lighthouse's lens: the carried thing never moves for a
## hat; a hat too near it is put away while carried (the leaf back as it grows)
## and back after; a shown hat keeps clear of it.
func _carrying() -> void:
	var plain := _spirit()
	var away_count := 0
	for hat: String in _hats:
		var spirit := _spirit(Outfit.of(hat, true))
		for radius: float in [0.13, 0.25]:
			plain.reset_motion()
			spirit.reset_motion()
			for each: Node3D in [plain, spirit]:
				each.carried_radius = radius
				each.carrying_seed = true
			var same := true
			var least := INF
			var away_seen := false
			for frame in range(200):
				var step := Vector3(0.04, 0, 0) if frame < 80 else Vector3.ZERO
				if frame == 80:
					plain.play_carry_release()
					spirit.play_carry_release()
				plain.advance_motion(step, DT, false)
				spirit.advance_motion(step, DT, false)
				same = same and spirit.carry_anchor_position().is_equal_approx(plain.carry_anchor_position())
				away_seen = away_seen or spirit._wearing.hat_away
				if not spirit._wearing.hat_away: least = minf(least, _carry_gap(spirit, radius))
			_check(same, "%s never moves a carried thing of radius %.2f" % [hat, radius])
			_check(least >= WearFit.CLEARANCE, "%s shown while carrying (radius %.2f) keeps clear of it: %.4f" % [hat, radius, least])
			if away_seen:
				away_count += 1
				_check(spirit.sprout.visible and is_zero_approx(spirit._wearing.leaf_lift), "%s put away shows the leaf where it grows" % hat)
				var hat_nodes: Array = spirit._wearing._slot_nodes.get("hat", [])
				var hidden := true
				for node: Node in hat_nodes: hidden = hidden and not (node as Node3D).visible
				_check(hidden, "%s is hidden while carrying" % hat)
			spirit.carrying_seed = false
			spirit.advance_motion(Vector3.ZERO, DT, false)
			_check(not spirit._wearing.hat_away, "%s comes back when the pip lets go" % hat)
			print("CARRY %s radius %.2f: %s" % [hat, radius, "put away" if away_seen else "shown, gap %.3f" % least])
		spirit.free()
	plain.free()
	_check(away_count > 0, "Some hat is put away for a carried thing")

## The least gap between the pip's shown hat and its carried thing (global).
func _carry_gap(spirit: Node3D, radius: float) -> float:
	var centre: Vector3 = spirit.carry_anchor_position() + spirit.global_position
	var least := INF
	for node: Node in spirit._wearing._slot_nodes.get("hat", []):
		for part: MeshInstance3D in WearFit.solid_meshes(node):
			var to := part.global_transform
			var raw := WearFit.vertices(part.mesh)
			for index in range(0, raw.size() - 2, 3):
				var near := WearFit.closest_on_triangle(centre, to * raw[index], to * raw[index + 1], to * raw[index + 2])
				least = minf(least, near.distance_to(centre) - radius)
	return least

## Each leaf, alone and raised by the hats that raise it: put away when it
## would come a CLEARANCE nearer the carried thing than the plain leaf does
## (WearFit.carry_allowance), and a shown leaf never touches it through
## walking and letting go; the carried thing still. The plain leaf and a
## sprig, its own shape, are never put away.
func _leaves_carrying() -> void:
	var plain := _spirit()
	var outfits: Array[Dictionary] = []
	for leaf: String in _leaves:
		if leaf.is_empty(): continue
		outfits.append({"leaf": leaf})
		for hat: String in _hats:
			if Catalog.leaf_lift(hat) > 0.0: outfits.append({"hat": hat, "leaf": leaf})
	var away := 0
	for outfit: Dictionary in outfits:
		var spirit := _spirit(Outfit.from(outfit, true))
		for radius: float in [0.13, 0.25]:
			plain.reset_motion()
			spirit.reset_motion()
			for each: Node3D in [plain, spirit]:
				each.carried_radius = radius
				each.carrying_seed = true
			var same := true
			var least := INF
			for frame in range(160):
				var step := Vector3(0.04, 0, 0) if frame < 80 else Vector3.ZERO
				plain.advance_motion(step, DT, false)
				spirit.advance_motion(step, DT, false)
				same = same and spirit.carry_anchor_position().is_equal_approx(plain.carry_anchor_position())
				if spirit.sprout.visible: least = minf(least, _leaf_carry_gap(spirit, radius))
			if spirit._wearing.leaf_away: away += 1
			if outfit.leaf.begins_with("sprig_") and not outfit.has("hat"): _check(not spirit._wearing.leaf_away, "%s, the plain leaf's shape, is never put away" % outfit.leaf)
			_check(same, "%s never moves a carried thing of radius %.2f" % [Outfit.digest(outfit), radius])
			_check(least > 0.0, "%s's leaf shown while carrying (radius %.2f) never touches it: %.4f" % [Outfit.digest(outfit), radius, least])
			spirit.carrying_seed = false
			spirit.advance_motion(Vector3.ZERO, DT, false)
			_check(not spirit._wearing.leaf_away, "%s's leaf comes back when the pip lets go" % Outfit.digest(outfit))
		spirit.free()
	plain.free()
	print("LEAVES CARRYING: %d of %d put away for a carried thing" % [away, outfits.size() * 2])

## The least gap between the pip's shown leaf and its carried thing (global).
func _leaf_carry_gap(spirit: Node3D, radius: float) -> float:
	var centre: Vector3 = spirit.carry_anchor_position() + spirit.global_position
	var least := INF
	for part: MeshInstance3D in WearFit.solid_meshes(spirit.sprout):
		var to := part.global_transform
		var raw := WearFit.vertices(part.mesh)
		for index in range(0, raw.size() - 2, 3):
			least = minf(least, WearFit.closest_on_triangle(centre, to * raw[index], to * raw[index + 1], to * raw[index + 2]).distance_to(centre) - radius)
	return least

## The first carry after dressing does its clearance sums once, quickly
## enough not to hitch the pick up.
func _first_carry_time() -> void:
	WearFit.release_cached()
	var spirit := _spirit(Outfit.from({"hat": "glass_house", "leaf": "bud"}, true))
	var started := Time.get_ticks_usec()
	spirit.carrying_seed = true
	spirit.advance_motion(Vector3.ZERO, DT, false)
	var took := (Time.get_ticks_usec() - started) / 1000.0
	print("FIRST CARRY: %.1f ms" % took)
	_check(took < FIRST_CARRY_MS, "The first carry's sums take %.1f ms (budget %d)" % [took, FIRST_CARRY_MS])
	spirit.free()

func _released() -> void:
	_check(SessionRelease._releases.has(Callable(load(WearFit.SCRIPT_PATH), "release_cached")), "The fit's kept measurements are released at shutdown")

func _name(leaf: String) -> String:
	return "the plain leaf" if leaf.is_empty() else leaf

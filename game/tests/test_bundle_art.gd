extends SceneTree
## The bundle art (kit/bundle_art.gd): the Pouch and the Jar are built once and
## kept, every shape triangulates (the Pouch's shade once logged a failed
## triangulation on every draw), the Jar's grains stay inside its glass, the
## Pouch's grains sit in its mouth behind the cloth lip, nothing leaves the
## art's square, the four grow from the Pinch to the Basket, and a refunded
## bundle fades as one picture.
const BundleArt = preload("res://presentation/kit/bundle_art.gd")
const PollenMark = preload("res://presentation/kit/pollen_mark.gd")
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const BUNDLES := ["pinch", "pouch", "jar", "basket"]
## Area left over when a shape is cut to the one it should sit in, in the unit square.
const SLACK := 0.00002
## The sizes the game draws the art at (purchases, receipt, confirm, store) and a big one.
const SIDES := [46.0, 76.0, 84.0, 104.0, 120.0]
## Each bundle covers at least this much more than the one before it.
const GROWTH := 1.04

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)

func _run() -> void:
	BundleArt.release_cached()
	for id: String in ["pouch", "jar"]:
		var layers := BundleArt.shapes(id)
		_check(is_same(layers, BundleArt.shapes(id)), "%s is built once and kept" % id)
		for index in range(layers.size()):
			var layer: Array = layers[index]
			for points: PackedVector2Array in _polygons(layer):
				_check(_inside_square(points), "%s layer %d stays in the art's square" % [id, index])
			if layer[0] == "fill":
				var points: PackedVector2Array = layer[1]
				_check(points.size() > 2 and points[0] != points[points.size() - 1], "%s fill %d never repeats its first point" % [id, index])
				_triangulates(points, "%s fill %d" % [id, index])
			if layer[0] == "cut":
				for part: Array in layer[1]:
					if part[0] is PackedVector2Array: _triangulates(part[0], "%s cut grain piece in layer %d" % [id, index])
	_check(BundleArt.shapes("basket").is_empty() and not BundleArt._shapes.has("basket"), "Only the Pouch and the Jar keep built shapes")
	_jar()
	_pouch()
	_sizes()
	_grain_cut()
	# The kept shapes go with the session.
	await process_frame
	_check(root.get_node_or_null(SessionRelease.NODE_NAME) != null, "The kept shapes register their release")
	SessionRelease.release_all()
	_check(BundleArt._shapes.is_empty(), "Release lets go of the kept shapes")
	# Each bundle draws in a page at the sizes the game sets.
	for side: float in SIDES:
		for id: String in BUNDLES:
			var art: Control = BundleArt.new(id, side)
			_check(art.custom_minimum_size == Vector2(side, side) and art.mouse_filter == Control.MOUSE_FILTER_IGNORE and art.name == "BundleArt", "%s at %d is square at its size and takes no input" % [id, side])
			root.add_child(art)
	var faded: Control = BundleArt.faded("jar", 46.0, 0.55)
	var group := faded.get_child(0) as CanvasGroup
	_check(faded.custom_minimum_size == Vector2(46, 46) and group != null and is_equal_approx(group.self_modulate.a, 0.55) and group.modulate == Color.WHITE, "A refunded bundle fades its art as one picture")
	var inner: Control = group.get_child(0)
	_check(inner.name == "BundleArt" and inner.size == Vector2(46, 46) and inner.modulate == Color.WHITE, "The faded art draws whole inside its group")
	root.add_child(faded)
	await process_frame
	await process_frame
	for art: Node in root.get_children():
		if art is Control: art.queue_free()
	await process_frame
	print("AFTER YOU BUNDLE ART: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Every grain in the jar is inside the glass: the whole grain, or the pieces cut to it.
func _jar() -> void:
	var inside := BundleArt.jar_inside()
	var body: PackedVector2Array = BundleArt.silhouette("jar")[0]
	_check(_left_over(inside, body) < SLACK, "The jar's inside is within its glass")
	var whole := 0
	var cut := 0
	for layer: Array in BundleArt.shapes("jar"):
		if layer[0] == "grain":
			whole += 1
			var reach := _circle(layer[1], float(layer[2]) * BundleArt.GRAIN_REACH)
			_check(_left_over(reach, inside) < SLACK, "A whole grain in the jar at %s is inside the glass" % layer[1])
		elif layer[0] == "cut":
			cut += 1
			for part: Array in layer[1]:
				var outline: PackedVector2Array = part[0] if part[0] is PackedVector2Array else PollenMark._part_polygon(part, 1.0)
				_check(_left_over(outline, inside) < SLACK, "A cut grain's part in the jar stays inside the glass")
	_check(whole + cut == BundleArt.JAR_GRAINS.size() and whole > 0 and cut > 0, "The jar holds every grain, some whole and the ones at the glass cut: %d whole, %d cut" % [whole, cut])

## The pouch's grains sit in its mouth: drawn before the lip, and below the
## lip's scallops every bit of each grain is covered by what is drawn over it.
func _pouch() -> void:
	var layers := BundleArt.shapes("pouch")
	var mouth := 0
	var first_grain := -1
	var last_grain := -1
	for index in range(layers.size()):
		if layers[index][0] == "grain":
			if first_grain < 0: first_grain = index
			last_grain = index
	_check(first_grain > 0 and layers[first_grain - 1][0] == "fill", "The pouch's mouth is drawn behind its grains")
	var lip: PackedVector2Array = layers[last_grain + 1][1]
	var lip_top := 1.0
	for point: Vector2 in lip: lip_top = minf(lip_top, point.y)
	var mouth_shape: PackedVector2Array = layers[first_grain - 1][1]
	var covers: Array[PackedVector2Array] = []
	for index in range(last_grain + 1, layers.size()):
		if layers[index][0] == "fill": covers.append(layers[index][1])
	var below := PackedVector2Array([Vector2(0, BundleArt.POUCH_LIP), Vector2(1, BundleArt.POUCH_LIP), Vector2(1, 1), Vector2(0, 1)])
	for grain: Array in BundleArt.POUCH_GRAINS:
		mouth += 1
		var reach := float(grain[2]) * BundleArt.GRAIN_REACH
		var centre := Vector2(grain[0], grain[1])
		_check(centre.y + reach > lip_top, "A pouch grain's bottom is behind the lip: %s" % centre)
		var left := 0.0
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(_circle(centre, reach), below): left += _uncovered(piece, covers)
		_check(left < SLACK, "Below the lip's scallops a pouch grain is covered: %s shows %.6f" % [centre, left])
		# Above the lip the grain sits within the mouth's width.
		var shown := Geometry2D.clip_polygons(_circle(centre, reach), PackedVector2Array([Vector2(0, lip_top), Vector2(1, lip_top), Vector2(1, 1), Vector2(0, 1)]))
		for piece: PackedVector2Array in shown:
			for point: Vector2 in piece:
				_check(point.x >= _x_range(mouth_shape).x - 0.01 and point.x <= _x_range(mouth_shape).y + 0.01, "A pouch grain stays within the mouth's width: %s" % point)
	_check(mouth == 3, "The pouch shows three grains in its mouth")

## The art grows with the amount, and nothing leaves its square.
func _sizes() -> void:
	var areas := []
	for id: String in BUNDLES:
		var total := 0.0
		for points: PackedVector2Array in BundleArt.silhouette(id):
			_check(_inside_square(points), "%s's outline stays in its square" % id)
			total += absf(BundleArt.area(points))
		areas.append(total)
	print("BUNDLE AREAS ", BUNDLES, " ", areas)
	for index in range(1, areas.size()):
		_check(areas[index] >= areas[index - 1] * GROWTH, "%s covers clearly more than %s: %.3f against %.3f" % [BUNDLES[index], BUNDLES[index - 1], areas[index], areas[index - 1]])

## A grain inside the clip stays round; one outside it is left out; one across its edge is cut.
func _grain_cut() -> void:
	var square := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var inside := PollenMark.grain_cut(Vector2(5, 5), 1.0, square)
	_check(inside.size() == PollenMark._parts(Vector2(5, 5), 1.0).size() and inside.all(func(part: Array) -> bool: return part[0] is Vector2), "A grain inside the clip keeps every part round")
	_check(PollenMark.grain_cut(Vector2(20, 20), 1.0, square).is_empty(), "A grain outside the clip draws nothing")
	var across := PollenMark.grain_cut(Vector2(0, 5), 1.0, square)
	_check(across.any(func(part: Array) -> bool: return part[0] is PackedVector2Array), "A grain across the clip's edge is cut")

func _polygons(layer: Array) -> Array[PackedVector2Array]:
	var found: Array[PackedVector2Array] = []
	match layer[0]:
		"fill", "line": found.append(layer[1])
		"grain": found.append(_circle(layer[1], float(layer[2]) * BundleArt.GRAIN_REACH))
		"cut":
			for part: Array in layer[1]: found.append(part[0] if part[0] is PackedVector2Array else _circle(part[0], float(part[1])))
	return found

## Triangulates as drawn: in the unit square and at every size the game draws.
func _triangulates(points: PackedVector2Array, what: String) -> void:
	_check(not Geometry2D.triangulate_polygon(points).is_empty(), "%s triangulates" % what)
	for side: float in SIDES:
		_check(not Geometry2D.triangulate_polygon(Transform2D(0.0, Vector2(side, side), 0.0, Vector2(3, 5)) * points).is_empty(), "%s triangulates at %d" % [what, side])

## The area of `shape` that none of `covers` hides.
func _uncovered(shape: PackedVector2Array, covers: Array[PackedVector2Array]) -> float:
	var left: Array[PackedVector2Array] = [shape]
	for cover: PackedVector2Array in covers:
		var next: Array[PackedVector2Array] = []
		for piece: PackedVector2Array in left: next.append_array(Geometry2D.clip_polygons(piece, cover))
		left = next
	var total := 0.0
	for piece: PackedVector2Array in left: total += BundleArt.area(piece)
	return absf(total)

func _inside_square(points: PackedVector2Array) -> bool:
	for point: Vector2 in points:
		if point.x < 0.0 or point.y < 0.0 or point.x > 1.0 or point.y > 1.0: return false
	return true

## The area of `shape` that lies outside `container`.
func _left_over(shape: PackedVector2Array, container: PackedVector2Array) -> float:
	var total := 0.0
	for piece: PackedVector2Array in Geometry2D.clip_polygons(shape, container): total += absf(BundleArt.area(piece))
	return total

func _x_range(points: PackedVector2Array) -> Vector2:
	var span := Vector2(1.0, 0.0)
	for point: Vector2 in points: span = Vector2(minf(span.x, point.x), maxf(span.y, point.x))
	return span

func _circle(centre: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(32):
		points.append(centre + Vector2(cos(TAU * index / 32.0), sin(TAU * index / 32.0)) * radius)
	return points

extends Control
## The four bundles' art (Pollen boards 1 and 2), growing with the amount:
## a pinch of grains, a cloth pouch, a glass jar and a woven basket, each
## holding grains drawn by kit/pollen_mark.gd, the one source of the grain.
## Flat shapes with no outline, lit from the upper left like the grain.
##
## The Pouch and the Jar are built once per session in a unit square (shapes())
## and only moved and scaled when drawn, so the Geometry2D work that keeps the
## jar's grains inside its glass never runs in a draw. Drawing happens once per
## resize, never per frame; the art takes no input.
const PollenMark = preload("res://presentation/kit/pollen_mark.gd")
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const Shapes = preload("res://presentation/empty_state_art.gd")
const SCRIPT_PATH := "res://presentation/kit/bundle_art.gd"

const CLOTH := Color("efe3c6")
const CLOTH_SHADE := Color("dccaa2")
const CLOTH_MOUTH := Color("cdb88d")
const TIE := Color("e9a9a1")
const TIE_KNOT := Color("d58f87")
const GLASS := Color("dcefe9")
const GLASS_WALL := Color("bcdcd3")
const GLASS_RIM := Color("93c0b5")
const GLASS_SHINE := Color(1, 1, 1, 0.85)
const LID := Color("b4805a")
const LID_SHADE := Color("94633f")
const LID_LIGHT := Color("c8966d")
const WICKER := Color("c99358")
const WICKER_DARK := Color("a5703d")
const WICKER_RIM := Color("b37c46")

## The grain's reach past its radius: its bumps (kit/pollen_mark.gd).
const GRAIN_REACH := 1.12
## Pinch: three grains, [x, y, radius] in the unit square.
const PINCH := [[0.36, 0.62, 0.2], [0.66, 0.6, 0.19], [0.5, 0.36, 0.21]]
## Basket: the heap on top, then the woven body and its rim in front.
const BASKET_HEAP := [[0.3, 0.42], [0.45, 0.38], [0.6, 0.38], [0.73, 0.43], [0.38, 0.28], [0.53, 0.25], [0.67, 0.29], [0.46, 0.15], [0.6, 0.15]]
const BASKET_GRAIN := 0.09
const BASKET_BODY := [Vector2(0.12, 0.46), Vector2(0.88, 0.46), Vector2(0.78, 0.9), Vector2(0.22, 0.9)]
const BASKET_RIM := Rect2(0.09, 0.42, 0.82, 0.08)

## Pouch: a soft sack, its corners [x, y, rounding] clockwise from the neck.
const POUCH_BODY := [[0.585, 0.36, 0.03], [0.69, 0.44, 0.1], [0.87, 0.67, 0.2], [0.79, 0.945, 0.11], [0.21, 0.945, 0.11], [0.13, 0.67, 0.2], [0.31, 0.44, 0.1], [0.415, 0.36, 0.03]]
## The open mouth above the tie (its shadowed inside), the grains in it and
## the ruffled lip in front of them, its scallops centred on POUCH_LIP.
const POUCH_MOUTH := Rect2(0.3, 0.225, 0.4, 0.11)
const POUCH_LIP := 0.292
const POUCH_GRAINS := [[0.5, 0.175, 0.09], [0.4, 0.235, 0.088], [0.6, 0.23, 0.088]]
const POUCH_TIE := Rect2(0.385, 0.345, 0.23, 0.055)

## Jar: the glass with a short neck, its corners [x, y, rounding] clockwise.
const JAR_BODY := [[0.3, 0.2, 0.02], [0.7, 0.2, 0.02], [0.7, 0.265, 0.03], [0.79, 0.33, 0.09], [0.79, 0.94, 0.12], [0.21, 0.94, 0.12], [0.21, 0.33, 0.09], [0.3, 0.265, 0.03]]
const JAR_WALL := 0.03
## Grains fill the jar with glass showing between them, listed top row first
## so each grain's highlight stays clear of the row above; the ones against
## the glass are cut by it.
const JAR_GRAINS := [[0.4225, 0.41], [0.5775, 0.41], [0.345, 0.55], [0.5, 0.55], [0.655, 0.55], [0.4225, 0.69], [0.5775, 0.69], [0.345, 0.83], [0.5, 0.835], [0.655, 0.83]]
const JAR_GRAIN := 0.095
const JAR_LID := Rect2(0.265, 0.085, 0.47, 0.125)
const JAR_BAND := Rect2(0.285, 0.19, 0.43, 0.045)

## Built shapes by bundle: an Array of layers in the unit square, each
## ["fill", polygon, colour, smooth edge], ["line", points, colour, width],
## ["grain", centre, radius] or ["cut", kit/pollen_mark.gd grain_cut parts].
static var _shapes := {}

var bundle := "pinch"

func _init(bundle_id: String = "pinch", side: float = 96.0) -> void:
	bundle = bundle_id
	name = "BundleArt"
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	resized.connect(queue_redraw)

func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	match bundle:
		"pouch", "jar": _draw_layers(shapes(bundle), Transform2D(0.0, Vector2(s, s), 0.0, o))
		"basket": _basket(o, s)
		_: _pinch(o, s)

## The Pouch's or the Jar's layers in the unit square, built the first time and
## kept (none for the other bundles, which draw straight from their constants).
static func shapes(id: String) -> Array:
	if not _shapes.has(id):
		match id:
			"pouch": _shapes[id] = _build_pouch()
			"jar": _shapes[id] = _build_jar()
			_: return []
		SessionRelease.on_exit(Callable(load(SCRIPT_PATH), "release_cached"))
	return _shapes[id]

## The art faded to `alpha` as one picture (a refunded purchase): its layers
## fade together in a CanvasGroup, so none shows through the ones over it.
static func faded(bundle_id: String, side: float, alpha: float) -> Control:
	var holder := Control.new()
	holder.name = "BundleArtFaded"
	holder.custom_minimum_size = Vector2(side, side)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var group := CanvasGroup.new()
	group.self_modulate.a = alpha
	holder.add_child(group)
	var art: Control = load(SCRIPT_PATH).new(bundle_id, side)
	art.size = Vector2(side, side)
	group.add_child(art)
	return holder

static func release_cached() -> void:
	_shapes.clear()

## The bundle's outline in the unit square, as polygons (tests compare sizes and bounds).
static func silhouette(id: String) -> Array[PackedVector2Array]:
	var parts: Array[PackedVector2Array] = []
	match id:
		"pouch":
			parts.append(_rounded(POUCH_BODY))
			parts.append(_mouth())
			parts.append(_lip())
			for grain: Array in POUCH_GRAINS: parts.append(_circle(Vector2(grain[0], grain[1]), grain[2] * GRAIN_REACH))
		"jar":
			parts.append(_rounded(JAR_BODY))
			parts.append(Shapes.round_rect(JAR_LID, 0.035))
		"basket":
			parts.append(PackedVector2Array(BASKET_BODY))
			parts.append(Shapes.round_rect(BASKET_RIM, 0.04))
			for at: Array in BASKET_HEAP: parts.append(_circle(Vector2(at[0], at[1]), BASKET_GRAIN * GRAIN_REACH))
		_:
			for grain: Array in PINCH: parts.append(_circle(Vector2(grain[0], grain[1]), grain[2] * GRAIN_REACH))
	return _union(parts)

## The glass's inside, where the jar's grains are cut.
static func jar_inside() -> PackedVector2Array:
	return _outer(Geometry2D.offset_polygon(_rounded(JAR_BODY), -JAR_WALL))[0]

func _draw_layers(layers: Array, at: Transform2D) -> void:
	var scale := at.get_scale().x
	for layer: Array in layers:
		match layer[0]:
			"fill":
				# A smooth fill adds a one pixel edge that softens the polygon's hard edge.
				if layer[3]: Shapes.fill(self, at, layer[1], layer[2])
				else: draw_colored_polygon(at * (layer[1] as PackedVector2Array), layer[2])
			"line": Shapes.stroke(self, at, layer[1], layer[2], layer[3])
			"grain": PollenMark.draw_grain(self, at * (layer[1] as Vector2), float(layer[2]) * scale)
			"cut": PollenMark.draw_cut(self, layer[1], at)

func _grain(at: Vector2, radius: float) -> void:
	PollenMark.draw_grain(self, at, radius)

func _pinch(o: Vector2, s: float) -> void:
	for grain: Array in PINCH: _grain(o + Vector2(grain[0], grain[1]) * s, s * grain[2])

func _basket(o: Vector2, s: float) -> void:
	# A heap of grains on top, then the woven basket in front of them.
	for at: Array in BASKET_HEAP: _grain(o + Vector2(at[0], at[1]) * s, s * BASKET_GRAIN)
	var body := PackedVector2Array()
	for corner: Vector2 in BASKET_BODY: body.append(o + corner * s)
	draw_colored_polygon(body, WICKER)
	for row in range(1, 5):
		var y := 0.46 + row * 0.088
		var inset := (y - 0.46) / 0.44 * 0.1
		draw_line(o + Vector2(0.12 + inset, y) * s, o + Vector2(0.88 - inset, y) * s, WICKER_DARK, maxf(1.0, s * 0.018), true)
	for column in range(1, 7):
		var x := 0.12 + column * 0.76 / 7.0
		draw_line(o + Vector2(x, 0.47) * s, o + Vector2(lerpf(x, 0.5, 0.2), 0.89) * s, Color(WICKER_DARK, 0.55), maxf(1.0, s * 0.012), true)
	var rim := StyleBoxFlat.new()
	rim.bg_color = WICKER_RIM
	rim.set_corner_radius_all(int(s * 0.04))
	rim.anti_aliasing = true
	draw_style_box(rim, Rect2(o + BASKET_RIM.position * s, BASKET_RIM.size * s))

## A soft drawstring sack: grains in its open mouth behind a cloth lip, a pink
## tie round the neck, the body shaded on the right and below, away from the light.
static func _build_pouch() -> Array:
	var layers := []
	var body := _rounded(POUCH_BODY)
	layers.append(_layer_fill(_mouth(), CLOTH_MOUTH))
	for grain: Array in POUCH_GRAINS: layers.append(["grain", Vector2(grain[0], grain[1]), grain[2]])
	var lip := _lip()
	layers.append(_layer_fill(lip, CLOTH))
	# The ruffle's fold where it gathers into the tie, so the lip reads on a cream card.
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(lip, PackedVector2Array([Vector2(0.3, 0.323), Vector2(0.7, 0.323), Vector2(0.7, 0.37), Vector2(0.3, 0.37)])):
		layers.append(_layer_fill(piece, CLOTH_SHADE))
	layers.append(_layer_fill(body, CLOTH))
	# The shade: the body less a copy moved up and left leaves a crescent on the right.
	var moved := Transform2D(0.0, Vector2(-0.085, -0.04)) * body
	for piece: PackedVector2Array in _outer(Geometry2D.clip_polygons(body, moved)): layers.append(_layer_fill(piece, CLOTH_SHADE))
	# Two gathers falling from the tie.
	layers.append(["line", PackedVector2Array([Vector2(0.45, 0.41), Vector2(0.43, 0.47), Vector2(0.405, 0.52)]), CLOTH_SHADE, 0.014])
	layers.append(["line", PackedVector2Array([Vector2(0.55, 0.41), Vector2(0.57, 0.46), Vector2(0.595, 0.5)]), CLOTH_SHADE, 0.014])
	layers.append(_layer_fill(Shapes.round_rect(POUCH_TIE, 0.025), TIE))
	layers.append(_layer_fill(_circle(POUCH_TIE.get_center() + Vector2(0.0, 0.004), 0.034), TIE_KNOT))
	return layers

## A glass jar full of grains: the grains are cut to the glass's inside, the
## rim and a tall shine sit over them, a pink band and a wooden lid on top.
static func _build_jar() -> Array:
	var layers := []
	var body := _rounded(JAR_BODY)
	var inside := jar_inside()
	layers.append(_layer_fill(body, GLASS_WALL))
	layers.append(_layer_fill(inside, GLASS, false))
	for at: Array in JAR_GRAINS:
		var centre := Vector2(at[0], at[1])
		if Geometry2D.clip_polygons(_circle(centre, JAR_GRAIN * GRAIN_REACH), inside).is_empty():
			layers.append(["grain", centre, JAR_GRAIN])
		else: layers.append(["cut", PollenMark.grain_cut(centre, JAR_GRAIN, inside)])
	# The inner rim covers the grains' cut edges; the outer rim is the glass's outline.
	layers.append(["line", _closed(inside), GLASS_WALL, 0.014])
	layers.append(["line", _closed(body), GLASS_RIM, 0.018])
	layers.append(_layer_fill(Shapes.round_rect(Rect2(0.258, 0.38, 0.03, 0.36), 0.014), GLASS_SHINE))
	layers.append(_layer_fill(_circle(Vector2(0.273, 0.785), 0.015), GLASS_SHINE))
	layers.append(["line", PackedVector2Array([Vector2(0.75, 0.45), Vector2(0.751, 0.62), Vector2(0.747, 0.8)]), Color(1, 1, 1, 0.4), 0.012])
	layers.append(_layer_fill(Shapes.round_rect(JAR_BAND, 0.02), TIE))
	layers.append(_layer_fill(Shapes.round_rect(JAR_LID, 0.035), LID))
	layers.append(_layer_fill(Shapes.round_rect(Rect2(JAR_LID.position.x, JAR_LID.end.y - 0.035, JAR_LID.size.x, 0.035), 0.016), LID_SHADE))
	layers.append(_layer_fill(Shapes.round_rect(Rect2(JAR_LID.position.x + 0.04, JAR_LID.position.y + 0.022, 0.15, 0.022), 0.01), LID_LIGHT))
	return layers

## The mouth's opening: a flat oval behind the grains.
static func _mouth() -> PackedVector2Array:
	return Shapes.ellipse(POUCH_MOUTH.get_center(), POUCH_MOUTH.size * 0.5)

## The lip: the mouth's front, gathered into a ruffle of soft scallops over the grains' lower edge.
static func _lip() -> PackedVector2Array:
	var lip: Array[PackedVector2Array] = [PackedVector2Array([Vector2(0.315, POUCH_LIP), Vector2(0.685, POUCH_LIP), Vector2(0.615, 0.37), Vector2(0.385, 0.37)])]
	for index in range(7): lip.append(_circle(Vector2(lerpf(0.33, 0.67, index / 6.0), POUCH_LIP), 0.03))
	return _union(lip)[0]

static func _layer_fill(points: PackedVector2Array, colour: Color, smooth := true) -> Array:
	return ["fill", points, colour, smooth]

## A closed outline through `corners` ([x, y, rounding]), each corner rounded
## by a curve that starts `rounding` before it (at most half of either side).
## Never repeats its first point, so it always triangulates.
static func _rounded(corners: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := corners.size()
	for index in range(count):
		var here := Vector2(corners[index][0], corners[index][1])
		var before := Vector2(corners[posmod(index - 1, count)][0], corners[posmod(index - 1, count)][1])
		var after := Vector2(corners[(index + 1) % count][0], corners[(index + 1) % count][1])
		var reach := minf(float(corners[index][2]), minf(here.distance_to(before), here.distance_to(after)) * 0.5)
		if reach <= 0.0:
			points.append(here)
			continue
		var start := here + (before - here).normalized() * reach
		var end := here + (after - here).normalized() * reach
		for step in range(7):
			var t := step / 6.0
			var point := start.lerp(here, t).lerp(here.lerp(end, t), t)
			# Corners that meet half way share a point: keep it once.
			if points.is_empty() or not point.is_equal_approx(points[points.size() - 1]): points.append(point)
	if points.size() > 1 and points[0].is_equal_approx(points[points.size() - 1]): points.remove_at(points.size() - 1)
	return points

static func _circle(centre: Vector2, radius: float) -> PackedVector2Array:
	return Shapes.ellipse(centre, Vector2(radius, radius))

static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var line := points.duplicate()
	line.append(points[0])
	return line

static func _union(parts: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var merged: Array[PackedVector2Array] = [parts[0]]
	for index in range(1, parts.size()):
		var next: Array[PackedVector2Array] = [parts[index]]
		for shape: PackedVector2Array in merged:
			var outer := _outer(Geometry2D.merge_polygons(next[0], shape))
			if outer.size() == 1: next[0] = outer[0]
			else: next.append(shape)
		merged = next
	return merged

## Geometry2D's results without their holes, largest first: a hole winds the
## other way round from the outline it sits in.
static func _outer(pieces: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var kept: Array[PackedVector2Array] = []
	for piece: PackedVector2Array in pieces:
		if piece.size() > 2: kept.append(piece)
	kept.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool: return absf(area(a)) > absf(area(b)))
	var outer: Array[PackedVector2Array] = []
	for piece: PackedVector2Array in kept:
		if signf(area(piece)) == signf(area(kept[0])): outer.append(piece)
	return outer

## The signed area of a closed outline (its sign is its winding).
static func area(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(points.size()):
		var next := points[(index + 1) % points.size()]
		total += points[index].x * next.y - next.x * points[index].y
	return total * 0.5

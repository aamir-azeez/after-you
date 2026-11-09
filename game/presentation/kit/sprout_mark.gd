extends Control
## The duel energy sprout, and the one place it is drawn (ENERGY-PLAN.md
## "Colours for the build", boards 10): the HUD seed's style, a curved stem
## and two rounded leaves. Full, the leaves run from a fresh spring green to a
## deeper one with a pale vein, and on the meter a faint light sits behind;
## empty, the same shape is a quiet outline. One mark draws a whole row of
## sprouts (the meter, the refill card's energy line, the Full Journey perk),
## the first `lit` of them full.
##
## The outlines are built once in the picture's 40 unit frame and only moved
## and scaled when drawn. A row draws once per resize or count, never per frame,
## and takes no input. The cost chip (kit/energy_chip.gd) draws its sprout with
## draw_sprout().

## The colours (owner, 2026-11-09).
const LEAF_LIGHT := Color("d9f59d")
const LEAF_DEEP := Color("8fca5c")
const STEM := Color("7fae55")
const VEIN := Color(0.949, 1.0, 0.847, 0.8)
const GLOW := Color(0.914, 1.0, 0.769, 0.55)
const EMPTY := Color("5f8478")
## The picture's frame, and its lines' widths in it.
const FRAME := 40.0
const STEM_WIDTH := 3.2
const EMPTY_STEM_WIDTH := 3.0
const EMPTY_WIDTH := 2.4
const VEIN_WIDTH := 1.4
const STEPS := 10
const GLOW_STEPS := 24

## The picture's paths (kit-energy.js), as cubic curves (start, then three points per curve).
const LEFT_LEAF := [Vector2(20, 21), Vector2(9, 21), Vector2(4, 14), Vector2(5, 7), Vector2(13, 6), Vector2(20, 11), Vector2(20, 21)]
const RIGHT_LEAF := [Vector2(20, 19), Vector2(30, 19), Vector2(36, 12), Vector2(35, 5), Vector2(26, 4), Vector2(20, 9), Vector2(20, 19)]
const VEIN_PATH := [Vector2(8, 9), Vector2(12, 10), Vector2(16, 14), Vector2(19, 19)]
const STEM_PATH := [Vector2(20, 36), Vector2(19, 27), Vector2(20, 20)]

## Built once when this file loads: [left leaf, its colours, right leaf, its colours, vein, stem].
static var _shape: Array = _build()

var lit := 0
var count := 1
var side := 24.0
var gap := 4.0
var glow := false

## A row of `total` sprouts `sprout` pixels square, `gap` apart, the first `full` of them full.
## `light`: the faint light behind the full ones (the meter's own, never on a chip).
static func row(full: int, total: int, sprout: float, row_gap: float = 4.0, light: bool = false) -> Control:
	var mark: Control = load("res://presentation/kit/sprout_mark.gd").new()
	mark.name = "SproutRow"
	mark.side = sprout
	mark.gap = row_gap
	mark.glow = light
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.resized.connect(mark.queue_redraw)
	mark.show_count(full, total)
	return mark

## One sprout `sprout` pixels square.
static func make(full: bool, sprout: float, light: bool = false) -> Control:
	return row(1 if full else 0, 1, sprout, 0.0, light)

## Shows `full` of `total` lit; draws again only when either changed.
func show_count(full: int, total: int) -> void:
	var next_total := maxi(total, 0)
	var next_lit := clampi(full, 0, next_total)
	if next_total == count and next_lit == lit and custom_minimum_size.x > 0.0: return
	count = next_total
	lit = next_lit
	custom_minimum_size = Vector2(count * side + maxi(count - 1, 0) * gap, side)
	queue_redraw()

func _draw() -> void:
	var top := (size.y - side) * 0.5
	for index in range(count):
		draw_sprout(self, Rect2(Vector2(index * (side + gap), top), Vector2(side, side)), index < lit, glow)

## Draws one sprout into `canvas` (any CanvasItem, in its own draw) inside `box`.
static func draw_sprout(canvas: CanvasItem, box: Rect2, full: bool, light: bool = false) -> void:
	var scale := box.size.x / FRAME
	var at := Transform2D(0.0, Vector2(scale, scale), 0.0, box.position)
	if not full:
		canvas.draw_polyline(at * (_shape[5] as PackedVector2Array), EMPTY, maxf(1.0, EMPTY_STEM_WIDTH * scale), true)
		for leaf: int in [0, 2]:
			var ring: PackedVector2Array = at * (_shape[leaf] as PackedVector2Array)
			ring.append(ring[0])
			canvas.draw_polyline(ring, EMPTY, maxf(1.0, EMPTY_WIDTH * scale), true)
		return
	if light: _glow(canvas, at * Vector2(20, 16), 19.0 * scale)
	var stem: PackedVector2Array = at * (_shape[5] as PackedVector2Array)
	var width := maxf(1.0, STEM_WIDTH * scale)
	canvas.draw_polyline(stem, STEM, width, true)
	canvas.draw_circle(stem[0], width * 0.5, STEM, true, -1.0, true)
	for leaf: int in [0, 2]: _edged(canvas, at * (_shape[leaf] as PackedVector2Array), _shape[leaf + 1])
	canvas.draw_polyline(at * (_shape[4] as PackedVector2Array), VEIN, maxf(1.0, VEIN_WIDTH * scale), true)

## The faint light: a disc from GLOW in the middle to nothing at its edge.
static func _glow(canvas: CanvasItem, centre: Vector2, radius: float) -> void:
	var clear := Color(GLOW, 0.0)
	for step in range(GLOW_STEPS):
		var a := TAU * step / GLOW_STEPS
		var b := TAU * (step + 1) / GLOW_STEPS
		canvas.draw_primitive(PackedVector2Array([centre, centre + Vector2.from_angle(a) * radius, centre + Vector2.from_angle(b) * radius]), PackedColorArray([GLOW, clear, clear]), PackedVector2Array())

## A filled leaf with a soft one pixel edge, a colour per point.
static func _edged(canvas: CanvasItem, points: PackedVector2Array, colours: PackedColorArray) -> void:
	canvas.draw_polygon(points, colours)
	var ring := points.duplicate()
	ring.append(points[0])
	var ring_colours := colours.duplicate()
	ring_colours.append(colours[0])
	canvas.draw_polyline_colors(ring, ring_colours, 1.0, true)

static func _build() -> Array:
	var shapes := []
	for leaf: Array in [LEFT_LEAF, RIGHT_LEAF]:
		var outline := _curves(leaf)
		shapes.append(outline)
		shapes.append(_leaf_colours(outline))
	var vein := _curves(VEIN_PATH)
	vein.append(VEIN_PATH[3])
	shapes.append(vein)
	var stem := PackedVector2Array()
	for step in range(STEPS + 1):
		var t := float(step) / STEPS
		stem.append(STEM_PATH[0].lerp(STEM_PATH[1], t).lerp(STEM_PATH[1].lerp(STEM_PATH[2], t), t))
	shapes.append(stem)
	return shapes

## The leaf's gradient across its own box, top left light to bottom right deep, as the picture's objectBoundingBox gradient.
static func _leaf_colours(outline: PackedVector2Array) -> PackedColorArray:
	var low := outline[0]
	var high := outline[0]
	for point: Vector2 in outline:
		low = low.min(point)
		high = high.max(point)
	var span := (high - low).max(Vector2.ONE)
	var colours := PackedColorArray()
	for point: Vector2 in outline:
		var at := (point - low) / span
		colours.append(LEAF_LIGHT.lerp(LEAF_DEEP, clampf((at.x + at.y) * 0.5, 0.0, 1.0)))
	return colours

## Points along cubic curves given as a start and three points per curve; the
## closing point is left out, so an outline never repeats its first point.
static func _curves(points: Array) -> PackedVector2Array:
	var outline := PackedVector2Array()
	for start in range(0, points.size() - 1, 3):
		var a: Vector2 = points[start]
		var b: Vector2 = points[start + 1]
		var c: Vector2 = points[start + 2]
		var d: Vector2 = points[start + 3]
		for step in range(STEPS):
			var t := float(step) / STEPS
			var u := 1.0 - t
			outline.append(a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t)
	return outline

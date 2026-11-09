extends Control
## The Fruit mark, and the one place it is drawn (Fruits board 1, icon C). Up
## to SMALL pixels it is a flat Fruit: the HUD seed picture's own stem, leaf
## and body outlines at the same tilt, in the Fruit's rose. Above that it is
## the game's own render of the Fruit (the carried seed's mesh in the rose
## tint, lit by Home's day light), a picture in assets/store/. Every Fruit icon
## in the game is one of these, made with make() or beside() here or through
## kit/currency_mark.gd; test_pollen_mark.gd fails if the Fruit's colours are
## drawn anywhere else. Change the Fruit here and it changes everywhere.
##
## The flat Fruit's outlines are built once in a unit frame and only moved and
## scaled when drawn. A mark draws once per resize, never per frame, and picks
## flat or rendered from the size it is drawn at.

## Beside an amount the Fruit is sized as the Pollen grain is
## (kit/pollen_mark.gd BESIDE), so the two marks read alike in one row.
const BESIDE := 0.92
## The largest side drawn flat; anything bigger draws the render.
const SMALL := 26.0
const RENDER := "res://assets/store/fruit-rose.png"
## Where the render's stem leaves the Fruit, in the render's own pixels (below
## its leaf): art that hangs the Fruit from a stalk joins it here.
const RENDER_STEM := Vector2(57, 44)

## The Fruit's rose: the flat body's light and deep ends (its gradient) and
## the seed's own green for the stem and leaf. Other Fruit art (the Apple hood)
## takes its colours from here.
const ROSE_LIGHT := Color("f8bcc8")
const ROSE_DEEP := Color("c25f7a")
const GREEN := Color("a2bd81")

## The seed picture's frame (its viewBox) and its tilt, in its own units.
const FRAME := Rect2(-36, -60, 85, 100)
const TILT := 14.4
## The outlines, as the picture draws them: the body and the leaf as cubic
## curves (start, then three points per curve), the stem as one quadratic.
const BODY := [Vector2(0, -34), Vector2(30, -34), Vector2(36, -6), Vector2(30, 18), Vector2(22, 44), Vector2(-22, 44), Vector2(-30, 18), Vector2(-36, -6), Vector2(-30, -34), Vector2(0, -34)]
const LEAF := [Vector2(4, -58), Vector2(22, -70), Vector2(38, -62), Vector2(34, -44), Vector2(18, -36), Vector2(4, -42), Vector2(4, -58)]
const STEM := [Vector2(-4, -30), Vector2(-8, -46), Vector2(4, -58)]
const STEM_WIDTH := 7.0
## The body's gradient runs between these two points, before the tilt.
const GRADIENT_FROM := Vector2(-32, -36)
const GRADIENT_TO := Vector2(32, 40)
const STEPS := 10

## Built once when this file loads, in a unit frame (the picture's height is
## 1, its middle at the origin): [body, body colours, leaf, stem].
static var _flat: Array = _build()

## The render, loaded with the mark (never in a draw) and shared through the
## resource cache; null until a mark is made.
var _render: Texture2D

## A mark sized for an amount set at `font_size`, to sit in the same row.
static func beside(font_size: int) -> Control:
	return make(roundf(font_size * BESIDE))

## A mark `side` pixels square.
static func make(side: float) -> Control:
	var mark: Control = load("res://presentation/kit/fruit_mark.gd").new()
	mark.name = "FruitMark"
	mark.custom_minimum_size = Vector2(side, side)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.accessibility_name = "Fruits"
	# The render is drawn well below its own size at most sizes.
	mark.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mark._render = render()
	return mark

## The Fruit's render (assets/store/), for art that draws it with draw_render.
static func render() -> Texture2D:
	return load(RENDER) as Texture2D

## Whether a mark `side` pixels tall draws the flat Fruit (else the render).
static func is_flat(side: float) -> bool:
	return side <= SMALL

func _draw() -> void:
	var side := minf(size.x, size.y)
	if side <= 0.0: return
	if is_flat(side): draw_flat(self, size * 0.5, side)
	elif _render != null: draw_render(self, _render, Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side)))

## Draws the flat Fruit `height` pixels tall round `centre` into `canvas`
## (any CanvasItem, in its own draw).
static func draw_flat(canvas: CanvasItem, centre: Vector2, height: float) -> void:
	var at := Transform2D(0.0, Vector2(height, height), 0.0, centre)
	var stem: PackedVector2Array = at * (_flat[3] as PackedVector2Array)
	var width := maxf(1.0, STEM_WIDTH / FRAME.size.y * height)
	canvas.draw_polyline(stem, GREEN, width, true)
	for end: Vector2 in [stem[0], stem[stem.size() - 1]]: canvas.draw_circle(end, width * 0.5, GREEN, true, -1.0, true)
	_edged(canvas, at * (_flat[2] as PackedVector2Array), PackedColorArray([GREEN]))
	_edged(canvas, at * (_flat[0] as PackedVector2Array), _flat[1])

## Draws `picture` (render()) fitted inside `box`, centred, keeping its shape.
static func draw_render(canvas: CanvasItem, picture: Texture2D, box: Rect2) -> void:
	var shape := picture.get_size()
	var scale := minf(box.size.x / shape.x, box.size.y / shape.y)
	var drawn := shape * scale
	canvas.draw_texture_rect(picture, Rect2(box.position + (box.size - drawn) * 0.5, drawn), false)

## The box, `side` pixels square, that draw_render fits a picture of
## `picture_size` (render()) into so that its stem (RENDER_STEM) lies at `stem`.
static func hung_box(picture_size: Vector2, stem: Vector2, side: float) -> Rect2:
	var scale := minf(side / picture_size.x, side / picture_size.y)
	return Rect2(stem - (Vector2(side, side) - picture_size * scale) * 0.5 - RENDER_STEM * scale, Vector2(side, side))

## A filled outline with a soft one pixel edge, in one colour or one per point.
static func _edged(canvas: CanvasItem, points: PackedVector2Array, colours: PackedColorArray) -> void:
	if colours.size() == 1: canvas.draw_colored_polygon(points, colours[0])
	else: canvas.draw_polygon(points, colours)
	var ring := points.duplicate()
	ring.append(points[0])
	if colours.size() == 1:
		canvas.draw_polyline(ring, colours[0], 1.0, true)
		return
	var ring_colours := colours.duplicate()
	ring_colours.append(colours[0])
	canvas.draw_polyline_colors(ring, ring_colours, 1.0, true)

static func _build() -> Array:
	var body := _curves(BODY)
	var colours := PackedColorArray()
	var span := GRADIENT_TO - GRADIENT_FROM
	for point: Vector2 in body:
		colours.append(ROSE_LIGHT.lerp(ROSE_DEEP, clampf((point - GRADIENT_FROM).dot(span) / span.length_squared(), 0.0, 1.0)))
	var stem := PackedVector2Array()
	for step in range(STEPS + 1):
		var t := float(step) / STEPS
		stem.append(STEM[0].lerp(STEM[1], t).lerp(STEM[1].lerp(STEM[2], t), t))
	var placed := Transform2D(0.0, Vector2.ONE / FRAME.size.y, 0.0, -FRAME.get_center() / FRAME.size.y) * Transform2D(deg_to_rad(TILT), Vector2.ZERO)
	return [placed * body, colours, placed * _curves(LEAF), placed * stem]

## Points along cubic curves given as a start and three points per curve; the
## closing point is left out, so the outline never repeats its first point.
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

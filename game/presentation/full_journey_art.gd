extends Control
## The Pollen bag on the "Your monthly Pollen arrived" card (pollen-concepts
## board 3): a cream sack tied with a pink ribbon, grains heaped in its open
## top. Flat shapes drawn once per change, never per frame, and no input.
##
## The Pollen grain itself is never drawn here. Every grain comes from
## PollenMark (presentation/kit/pollen_mark.gd), through grain() and
## draw_grains() below.
## PollenMark: the kit file lands on main with branch pollen-mark. Until then
## these two leave the grain's space empty. Once it lands, replace MARK_PATH's
## load with `const PollenMark = preload(MARK_PATH)` and call it directly.
const MARK_PATH := "res://presentation/kit/pollen_mark.gd"

## The bag: a cream sack with a darker fold, tied with a pink ribbon.
const SACK := Color("efe2c4")
const SACK_SHADE := Color("dccaa3")
const TIE := Color("e6a3a0")

## The PollenMark grain, `side` pixels square, or an empty space the same size
## while the kit is not in this build.
static func grain(side: float) -> Control:
	if ResourceLoader.exists(MARK_PATH): return load(MARK_PATH).make(side)
	var space := Control.new()
	space.name = "PollenMark"
	space.custom_minimum_size = Vector2(side, side)
	space.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return space

## Grains of `radius` at `centres`, drawn by PollenMark into `canvas` (nothing
## while the kit is not in this build).
static func draw_grains(canvas: CanvasItem, centres: Array[Vector2], radius: float) -> void:
	if not ResourceLoader.exists(MARK_PATH): return
	var mark: Script = load(MARK_PATH)
	for centre: Vector2 in centres: mark.draw_grain(canvas, centre, radius)

## The bag picture, `side` pixels square.
static func bag(side: float) -> Control:
	var art: Control = load("res://presentation/full_journey_art.gd").new()
	art.name = "PollenBag"
	art.custom_minimum_size = Vector2(side, side)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art

func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	# The sack: a rounded body widening to the bottom, a neck under the tie.
	var body := PackedVector2Array()
	for point: Vector2 in [Vector2(0.36, 0.42), Vector2(0.64, 0.42), Vector2(0.76, 0.58), Vector2(0.84, 0.76), Vector2(0.82, 0.9),
			Vector2(0.72, 0.97), Vector2(0.28, 0.97), Vector2(0.18, 0.9), Vector2(0.16, 0.76), Vector2(0.24, 0.58)]:
		body.append(p.call(point.x, point.y))
	draw_colored_polygon(body, SACK)
	# A soft fold down the right side gives it some shape.
	var fold := PackedVector2Array([p.call(0.6, 0.48), p.call(0.66, 0.44), p.call(0.78, 0.62), p.call(0.84, 0.8), p.call(0.8, 0.92), p.call(0.7, 0.96), p.call(0.66, 0.8)])
	draw_colored_polygon(fold, SACK_SHADE)
	# The open top, gathered under the tie.
	draw_colored_polygon(PackedVector2Array([p.call(0.3, 0.3), p.call(0.7, 0.3), p.call(0.64, 0.42), p.call(0.36, 0.42)]), SACK)
	# The ribbon round the neck.
	draw_rect(Rect2(p.call(0.33, 0.37), Vector2(0.34, 0.06) * s), TIE)
	draw_circle(p.call(0.34, 0.4), s * 0.045, TIE, true, -1.0, true)
	# Grains heaped in the open top, from PollenMark.
	var heap: Array[Vector2] = [p.call(0.38, 0.26), p.call(0.62, 0.26), p.call(0.5, 0.2), p.call(0.44, 0.13), p.call(0.58, 0.14)]
	draw_grains(self, heap, s * 0.1)

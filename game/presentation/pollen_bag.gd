extends Control
## The Pollen bag on the "Your monthly Pollen arrived" card (pollen-concepts
## board 3): a cream sack tied with a pink ribbon, grains heaped in its open
## top. Flat shapes drawn once per change, never per frame, and no input.
##
## The grains heaped in its top come from PollenMark, the one place the
## Pollen grain is drawn.
const PollenMark = preload("res://presentation/kit/pollen_mark.gd")

## The bag: a cream sack with a darker fold, tied with a pink ribbon.
const SACK := Color("efe2c4")
const SACK_SHADE := Color("dccaa3")
const TIE := Color("e6a3a0")

## The bag picture, `side` pixels square.
static func bag(side: float) -> Control:
	var art: Control = load("res://presentation/pollen_bag.gd").new()
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
	for centre: Vector2 in [Vector2(0.38, 0.26), Vector2(0.62, 0.26), Vector2(0.5, 0.2), Vector2(0.44, 0.13), Vector2(0.58, 0.14)]:
		PollenMark.draw_grain(self, p.call(centre.x, centre.y), s * 0.1)

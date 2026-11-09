extends Control
## The Sunshine sun, and the one place it is drawn (Fruits boards 6a and 7):
## - LINE: a ring with eight short rays in one ink, the line icon the Sunshine
##   button, the history tag and the in-play pill wear;
## - ART: the big warm sun of the Sunshine card, a filled disc that runs from
##   a pale middle to a deeper rim, with thick rounded rays around it.
## Every sun in the game is made here with make() or beside(), so it looks the
## same on every surface. It draws once per resize, never per frame, and takes
## no input.

const LINE := "line"
const ART := "art"
## The art sun's middle, rim and rays (warm, never the Pollen grain's own colours).
const SUN_LIGHT := Color("fff2b8")
const SUN_DEEP := Color("f7c65a")
const RAY := Color("f1b24f")
## Beside an amount or a line of words, sized as the currency marks are.
const BESIDE := 0.92
const RAYS := 8
const STEPS := 40

var style := LINE
var ink := Color.WHITE

## A sun `side` pixels square: `kind` LINE (in `colour`) or ART.
static func make(side: float, kind: String = LINE, colour: Color = Color.WHITE) -> Control:
	var mark: Control = load("res://presentation/kit/sun_mark.gd").new()
	mark.name = "SunMark"
	mark.style = kind
	mark.ink = colour
	mark.custom_minimum_size = Vector2(side, side)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.resized.connect(mark.queue_redraw)
	return mark

## A line sun sized for words set at `font_size`, to sit in the same row.
static func beside(font_size: int, colour: Color) -> Control:
	return make(roundf(font_size * BESIDE), LINE, colour)

func _draw() -> void:
	var side := minf(size.x, size.y)
	if side <= 0.0: return
	var middle := size * 0.5
	if style == ART: _art(middle, side * 0.5)
	else: _line(middle, side * 0.5)

## The ring and its rays, the stroke scaled with the size.
func _line(middle: Vector2, half: float) -> void:
	var width := maxf(1.2, half * 0.16)
	draw_arc(middle, half * 0.42, 0.0, TAU, STEPS, ink, width, true)
	for index in range(RAYS):
		var way := Vector2.RIGHT.rotated(TAU * index / RAYS)
		draw_line(middle + way * half * 0.68, middle + way * half * 0.95, ink, width, true)

## The filled disc, its light falling to the rim, and thick rounded rays.
func _art(middle: Vector2, half: float) -> void:
	var radius := half * 0.62
	var width := half * 0.1
	for index in range(RAYS):
		var way := Vector2.RIGHT.rotated(TAU * (index + 0.5) / RAYS)
		var from := middle + way * half * 0.76
		var to := middle + way * half * 0.95
		draw_line(from, to, RAY, width, true)
		for end: Vector2 in [from, to]: draw_circle(end, width * 0.5, RAY, true, -1.0, true)
	var points := PackedVector2Array()
	var colours := PackedColorArray()
	var light := middle + Vector2(-radius, -radius) * 0.35
	for step in range(STEPS):
		var point := middle + Vector2.RIGHT.rotated(TAU * step / STEPS) * radius
		points.append(point)
		colours.append(SUN_LIGHT.lerp(SUN_DEEP, clampf(point.distance_to(light) / (radius * 1.6), 0.0, 1.0)))
	draw_polygon(points, colours)
	# The disc's soft inner light, drawn as a smaller pale disc.
	draw_circle(light.lerp(middle, 0.4), radius * 0.45, Color(SUN_LIGHT, 0.55), true, -1.0, true)

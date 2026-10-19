extends Control
## A turn ending's round badge (turn_endings.gd): the spirit's head drawn flat
## with the ending's expression (empty_state_art.gd, the game's own face
## shapes), sitting half under a wavy water line when the ending says so, with
## a few bubbles. Drawn once; nothing moves, so Reduce motion needs nothing.
##   var badge := EndingBadge.new(); badge.setup(ending, 118.0)
const Art = preload("res://presentation/empty_state_art.gd")
const RIM := Color("2a6d70")
const POOL := Color("3f8f92")
const WATER := Color("5fb3b3")
const LINE := Color("a8e0da")
const BUBBLE := Color("eceddb")

var _ending: Dictionary = {}

func setup(ending: Dictionary, diameter: float) -> void:
	_ending = ending
	custom_minimum_size = Vector2(diameter, diameter)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5
	var center := size * 0.5
	draw_circle(center, radius, RIM)
	draw_circle(center, radius * 0.93, POOL)
	# The head about 1.25 radii wide, a little low so the water takes its chin.
	var scale := radius * 0.62 / (Art.Look.HEAD_HALF.x * Art.UNIT)
	var at := Transform2D(0.0, Vector2(scale, scale), 0.0, center + Vector2(0.0, radius * 0.08) - Art.HEAD * scale)
	Art.spirit(self, at, {"color": str(_ending.get("color", "peach")), "eyes": str(_ending.get("badge", "dot"))}, true)
	if bool(_ending.get("water", false)):
		var level := center.y + radius * 0.30
		draw_colored_polygon(_water(center, radius * 0.93, level), Color(WATER, 0.82))
		draw_polyline(_wave(center, radius * 0.93, level), LINE, maxf(2.0, radius * 0.05), true)
	for spec: Array in [[0.55, -0.62, 0.07], [0.68, -0.40, 0.05], [0.40, -0.80, 0.04]]:
		draw_arc(center + Vector2(float(spec[0]), float(spec[1])) * radius, float(spec[2]) * radius, 0.0, TAU, 16, Color(BUBBLE, 0.9), maxf(1.5, radius * 0.025), true)

## The wavy water line across the disc at `level`.
func _wave(center: Vector2, radius: float, level: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var half := sqrt(maxf(radius * radius - pow(level - center.y, 2.0), 0.0))
	for index in range(25):
		var x := lerpf(center.x - half, center.x + half, float(index) / 24.0)
		points.append(Vector2(x, level + sin(float(index) / 24.0 * TAU * 2.0) * radius * 0.035))
	return points

## The water below the wave: the wave left to right, then the disc's lower
## arc from its right end round the bottom back to the left.
func _water(center: Vector2, radius: float, level: float) -> PackedVector2Array:
	var points := _wave(center, radius, level)
	var start := asin(clampf((level - center.y) / radius, -1.0, 1.0))
	for index in range(1, 24):
		var angle := lerpf(start, PI - start, float(index) / 24.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points

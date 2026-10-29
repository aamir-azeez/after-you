extends Control
## The Pollen mark, and the one place it is drawn: a soft gold grain with
## little bumps round its edge, a highlight and a few dimples, as the owner's
## Pollen board draws it (pollen-concepts board-1, "Soft gold, little bumps
## round the edge"). Every Pollen icon in the game is one of these, made with
## make(SIZE) or drawn with draw_grain(); test_pollen_mark.gd fails if a Pollen
## colour is drawn anywhere else. Change the grain here and it changes everywhere.
##
## Flat shapes, no outline and no texture, so it is sharp at every size and
## costs one draw per change, never per frame.

## Beside an amount the grain is sized from the amount's font: its digits
## stand about 0.7 of the font size tall, and the grain is about 1.3 times
## that, so it reads as part of the line, centred on the digits, and never
## reaches past the line into a rule or a row above or below.
const BESIDE := 0.92
const BODY := Color("f5c95e")
const SHADE := Color("e7ac45")
const BUMP := Color("eab44c")
const DIMPLE := Color("dc9f3b")
const HIGHLIGHT := Color("fff3cc")
const BUMPS := 18
const DIMPLES := [Vector2(0.28, -0.12), Vector2(0.42, 0.28), Vector2(-0.06, 0.38), Vector2(-0.4, 0.12), Vector2(0.08, -0.48), Vector2(0.12, 0.08)]

## A mark sized for an amount set at `font_size`, to sit in the same row.
static func beside(font_size: int) -> Control:
	return make(roundf(font_size * BESIDE))

## A mark `side` pixels square.
static func make(side: float) -> Control:
	var mark: Control = load("res://presentation/kit/pollen_mark.gd").new()
	mark.name = "PollenMark"
	mark.custom_minimum_size = Vector2(side, side)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.accessibility_name = "Pollen"
	return mark

func _draw() -> void:
	# The bumps reach about 1.12 of the grain's radius, so the grain is sized to fit inside.
	draw_grain(self, size * 0.5, minf(size.x, size.y) * 0.5 / 1.12)

## Draws one grain of radius `radius` round `centre` into `canvas` (any CanvasItem, in its own draw).
static func draw_grain(canvas: CanvasItem, centre: Vector2, radius: float) -> void:
	for index in range(BUMPS):
		var angle := TAU * index / BUMPS + 0.12
		canvas.draw_circle(centre + Vector2(cos(angle), sin(angle)) * radius * 0.97, radius * 0.15, BUMP, true, -1.0, true)
	canvas.draw_circle(centre, radius, SHADE, true, -1.0, true)
	canvas.draw_circle(centre + Vector2(-0.07, -0.08) * radius, radius * 0.9, BODY, true, -1.0, true)
	for index in range(DIMPLES.size()):
		canvas.draw_circle(centre + DIMPLES[index] * radius, radius * (0.07 if index == 5 else 0.085), Color(DIMPLE, 0.85), true, -1.0, true)
	var light := centre + Vector2(-0.32, -0.38) * radius
	canvas.draw_set_transform(light, deg_to_rad(-28.0), Vector2(1.0, 0.6))
	canvas.draw_circle(Vector2.ZERO, radius * 0.3, HIGHLIGHT, true, -1.0, true)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

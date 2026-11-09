extends StyleBox
## A control that can't be used yet, as the race picker boards draw it: a
## dashed rounded edge and no fill (a chapter's greyed "No times yet", a Race
## greyed by the race limit or a check). grey() gives a button this look for
## its disabled state, with the theme's greyed ink. Drawn only when the button
## redraws, from a few lines; nothing per frame.
const UiTokens = preload("res://presentation/ui_tokens.gd")
## Segments per rounded corner.
const CORNER_STEPS := 5

var color := UiTokens.SECONDARY_BORDER
var radius := 14.0
var dash := 6.0
var gap := 4.0
var width := 1.5

## Gives `button` the dashed greyed look while it is disabled.
static func grey(button: Button, corner: float = 14.0) -> void:
	var box: StyleBox = load("res://presentation/kit/dashed_box.gd").new()
	box.radius = corner
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	button.add_theme_stylebox_override("disabled", box)
	button.add_theme_color_override("font_disabled_color", UiTokens.DISABLED_TEXT)
	button.add_theme_color_override("icon_disabled_color", UiTokens.DISABLED_TEXT)

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var path := outline(rect.grow(-width * 0.5), radius)
	var on := true
	var left := dash
	for index in range(path.size()):
		var a: Vector2 = path[index]
		var b: Vector2 = path[(index + 1) % path.size()]
		var length := a.distance_to(b)
		var at := 0.0
		while at < length:
			var step := minf(left, length - at)
			if on: RenderingServer.canvas_item_add_line(to_canvas_item, a.lerp(b, at / length), a.lerp(b, (at + step) / length), color, width, true)
			at += step
			left -= step
			if left <= 0.0:
				on = not on
				left = dash if on else gap

## The rounded rectangle's edge, clockwise from the top left corner's left end.
static func outline(rect: Rect2, corner: float, steps: int = CORNER_STEPS) -> PackedVector2Array:
	var r := minf(corner, minf(rect.size.x, rect.size.y) * 0.5)
	var centres := [rect.position + Vector2(r, r), Vector2(rect.end.x - r, rect.position.y + r), rect.end - Vector2(r, r), Vector2(rect.position.x + r, rect.end.y - r)]
	var points := PackedVector2Array()
	for side in range(4):
		for step in range(steps + 1):
			var angle := deg_to_rad(180.0 + 90.0 * side + 90.0 * step / steps)
			points.append(centres[side] + Vector2(cos(angle), sin(angle)) * r)
	return points

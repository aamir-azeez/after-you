extends Button
## Square play control on a Play Solo chapter card: the card's only tap and focus
## target. Lighter teal fill (cream stays the screen's single primary), a filled cream
## triangle optically nudged right, and brighter fills while hovered or pressed.
const FILL := Color("2f5d52")
const FILL_HOVER := Color("3a6b5f")
const FILL_PRESSED := Color("4a7c6f")
const TRIANGLE := Color("eceddb")
const RING := Color("a6d9c4")
## Locked squares sit back with darker fills; the lock itself stays full cream.
const LOCKED_FILL := Color("223f3b")
const LOCKED_HOVER := Color("2a4a45")
const LOCKED_PRESSED := Color("33554f")
const LOCK_TINT := TRIANGLE
## Completed cards are brighter, so their square steps up to stay distinct.
const DONE_FILL := Color("3b7062")
const DONE_HOVER := Color("467c6e")
const DONE_PRESSED := Color("528a7b")
const RADIUS := 16
## Locked Full Journey chapters show this instead of the triangle; the tap still
## runs the chapter's own access flow.
const LOCK_ICON = preload("res://assets/ui/social/lock.svg")
var locked := false:
	set(value):
		locked = value
		_apply_fills()
		queue_redraw()
var completed := false:
	set(value):
		if completed == value: return
		completed = value
		_apply_fills()

func _init(side: float = 64.0) -> void:
	text = ""
	custom_minimum_size = Vector2(side, side)
	size_flags_horizontal = Control.SIZE_SHRINK_END
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	focus_mode = Control.FOCUS_ALL
	# A drag that starts here still reaches the scroll list; its scroll notification
	# cancels the pending press, so only a short tap opens the chapter.
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_fills()
	var ring := _rounded(Color.TRANSPARENT)
	ring.border_color = RING
	ring.set_border_width_all(2)
	ring.set_expand_margin_all(3)
	add_theme_stylebox_override("focus", ring)

func _apply_fills() -> void:
	var base := LOCKED_FILL if locked else DONE_FILL if completed else FILL
	var hover := LOCKED_HOVER if locked else DONE_HOVER if completed else FILL_HOVER
	var pressed := LOCKED_PRESSED if locked else DONE_PRESSED if completed else FILL_PRESSED
	var fills := {"normal": base, "hover": hover, "pressed": pressed, "hover_pressed": pressed, "disabled": base}
	for state: String in fills:
		add_theme_stylebox_override(state, _rounded(fills[state]))

func _rounded(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(RADIUS)
	return style

func _draw() -> void:
	if locked:
		var side := minf(size.x, size.y) * 0.42
		draw_texture_rect(LOCK_ICON, Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side)), false, LOCK_TINT)
		return
	# Equilateral triangle, about 40% of the side tall. Its centroid sits just right of
	# the centre so it reads as centred rather than leaning left.
	var height := minf(size.x, size.y) * 0.40
	var width := height * 0.866
	var middle := size.y * 0.5
	var left := size.x * 0.5 + width * 0.05 - width / 3.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(left, middle - height * 0.5),
		Vector2(left + width, middle),
		Vector2(left, middle + height * 0.5)]), TRIANGLE)

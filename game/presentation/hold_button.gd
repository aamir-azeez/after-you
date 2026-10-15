extends Button
## A button that acts while it is held, by any finger. A plain Button hears
## only the first finger (the one Android also turns into a mouse), so a press
## made while another finger steers the stick would be missed. This one keeps
## its own set of fingers and the mouse, and lets go of all of them when it is
## hidden or disabled, so a hold can never stick on.

var _touches: Dictionary = {}
var _mouse := false

## True while at least one finger or the mouse holds the button down.
func held() -> bool:
	return is_visible_in_tree() and not disabled and (not _touches.is_empty() or _mouse)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed: _touches[event.index] = true
		else: _touches.erase(event.index)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse = event.pressed

func release() -> void:
	_touches.clear()
	_mouse = false

func _notification(what: int) -> void:
	if what in [NOTIFICATION_VISIBILITY_CHANGED, NOTIFICATION_EXIT_TREE, NOTIFICATION_DISABLED]: release()

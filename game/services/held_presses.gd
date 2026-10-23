extends RefCounted
## The touches and the left mouse button now held down, from the input events
## a node sees. A finger resting still sends no events, so "no input for a
## while" alone does not mean the player is idle (Home's warm-ups ask this).
var _held: Dictionary = {}

func track(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled: _held[event.index] = true
		else: _held.erase(event.index)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: _held[-1] = true
		else: _held.erase(-1)

func any() -> bool:
	return not _held.is_empty()

## A release can be lost while the app is away.
func clear() -> void:
	_held.clear()

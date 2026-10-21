extends Node
## Internal child of a screen (see SafeArea.watch). Calls the screen's relayout
## when the viewport size changes (rotation, multi-window, resizing) and when the
## app comes back to the foreground, where the cutout can have moved without a
## size change, and when SafeArea.poll sees the cutout move after a half turn.
## Never per frame.
const NAME := "SafeAreaWatch"
const GROUP := &"safe_area_watch"

var relayout: Callable

func _enter_tree() -> void:
	add_to_group(GROUP)
	if not get_viewport().size_changed.is_connected(_changed): get_viewport().size_changed.connect(_changed)

func _exit_tree() -> void:
	if get_viewport().size_changed.is_connected(_changed): get_viewport().size_changed.disconnect(_changed)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]: _changed.call_deferred()

func relayout_now() -> void:
	_changed()

func _changed() -> void:
	if relayout.is_valid(): relayout.call()

extends Node
## Internal child of a screen (see SafeArea.watch). Calls the screen's relayout
## when the viewport size changes (rotation, multi-window, resizing) and when the
## app comes back to the foreground, where the cutout can have moved without a
## size change. Never per frame.
const NAME := "SafeAreaWatch"

var relayout: Callable

func _enter_tree() -> void:
	if not get_viewport().size_changed.is_connected(_changed): get_viewport().size_changed.connect(_changed)

func _exit_tree() -> void:
	if get_viewport().size_changed.is_connected(_changed): get_viewport().size_changed.disconnect(_changed)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]: _changed.call_deferred()

func _changed() -> void:
	if relayout.is_valid(): relayout.call()

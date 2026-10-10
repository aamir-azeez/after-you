extends Node
## Optional native invite-link inbox. The native side validates and keeps at most one link
## in memory; this side takes it once, validates it again and never logs it.
const ShareCodes = preload("res://services/share_codes.gd")
## {"ok":true,"type":"friend","id":bare} for a valid invite link, {"ok":false,...} otherwise.
signal received(result: Dictionary)

var _native: Object
var _connected := false

func _ready() -> void:
	# Cold start: the launch link is already waiting in the native inbox.
	poll.call_deferred()

func _connect_native() -> bool:
	if _connected: return true
	if _native == null:
		if not Engine.has_singleton("AfterYouAndroid"): return false
		_native = Engine.get_singleton("AfterYouAndroid")
	# An older native plugin without the inbox stays unused.
	if not _native.has_signal("invite_link_available"): return false
	_native.connect("invite_link_available", _on_link_available)
	_connected = true
	return true

## Takes the pending native link, if any. Taking clears it, so each link arrives once.
func poll() -> void:
	if not is_inside_tree() or not _connect_native(): return
	# JNI singleton methods dispatch through callv, not Object.has_method.
	var value: Variant = _native.callv("invite_link_take", [])
	if not value is String or value.is_empty(): return
	received.emit(ShareCodes.parse_link(value))

func _on_link_available() -> void:
	poll.call_deferred()

func _notification(what: int) -> void:
	# Warm start: the native hint is skipped while paused, so resuming polls as well.
	if what == NOTIFICATION_APPLICATION_RESUMED: poll.call_deferred()

func _exit_tree() -> void:
	if _connected and is_instance_valid(_native) and _native.is_connected("invite_link_available", _on_link_available):
		_native.disconnect("invite_link_available", _on_link_available)
	_connected = false

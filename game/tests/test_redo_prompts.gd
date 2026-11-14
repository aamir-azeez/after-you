extends SceneTree
## Redo requests on this phone (concept boards claude-20261011/redo-concepts):
## the nudge once a turn after 8 tries or 5 minutes, Home's Not now, the redo
## alerts question asked once, the room list's redo field, and the turn's chip.
const RedoPrompts = preload("res://services/redo_prompts.gd")
const Inbox = preload("res://services/room_inbox_client.gd")
const ChapterControls = preload("res://presentation/chapter_controls.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_nudge()
	_home_and_alerts()
	_inbox_field()
	await _chip()
	print("REDO PROMPTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _path() -> String:
	return "user://redo-prompts-test-" + Crypto.new().generate_random_bytes(6).hex_encode() + ".json"

func _nudge() -> void:
	var path := _path()
	var prompts: RefCounted = RedoPrompts.new(path)
	var key := RedoPrompts.turn_key("room:abc:0:1:b")
	_check(key.length() == 24 and key == RedoPrompts.turn_key("room:abc:0:1:b"), "A turn's key is short and stable")
	_check(not prompts.nudge_due(key, 7, 1000), "Seven tries in the first minute: no nudge yet")
	_check(prompts.nudge_due(key, 8, 1010), "Eight tries: the nudge is due")
	prompts.mark_nudged(key)
	_check(not prompts.nudge_due(key, 12, 5000), "Once a turn: never again for the same turn")
	var other := RedoPrompts.turn_key("room:abc:0:2:b")
	_check(not prompts.nudge_due(other, 2, 2000) and not prompts.nudge_due(other, 3, 2299), "Under five minutes on a new turn: none")
	_check(prompts.nudge_due(other, 3, 2300), "Five minutes after this phone first started the turn: due")
	var again: RefCounted = RedoPrompts.new(path)
	_check(not again.nudge_due(key, 20, 9000) and again.nudge_due(other, 3, 2300), "What showed survives a restart; the turn's first start too")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var damaged := _path()
	var file := FileAccess.open(damaged, FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	_check(not RedoPrompts.new(damaged).alerts_asked(), "A damaged file reads as empty")
	for name: String in [damaged, damaged + ".unreadable"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(name))

func _home_and_alerts() -> void:
	var path := _path()
	var prompts: RefCounted = RedoPrompts.new(path)
	var key := RedoPrompts.request_key("40173cc9d5bee436613f7a", 3, 0)
	_check(not prompts.dismissed(key), "A new request's card shows")
	prompts.dismiss(key)
	_check(prompts.dismissed(key) and not prompts.dismissed(RedoPrompts.request_key("40173cc9d5bee436613f7a", 5, 0)), "Not now puts away only that request")
	_check(not prompts.alerts_asked(), "The redo alerts question has not been asked")
	prompts.note_alerts_asked()
	var again: RefCounted = RedoPrompts.new(path)
	_check(again.dismissed(key) and again.alerts_asked(), "Both are kept on this phone")
	for index in range(RedoPrompts.MAX_KEPT + 5): again.dismiss("room-%d" % index)
	_check(not again.dismissed(key) and again.dismissed("room-%d" % (RedoPrompts.MAX_KEPT + 4)), "Only the newest requests are kept")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _inbox_field() -> void:
	var base := {"room_id":"rrrrrrrrrrrrrrrrrrrrrr","family":"relay","api_version":2,"chapter":{"id":"relay-isles","version":2},"membership":{"host_id":"aaaaaaaaaaaaaaaaaaaaaa","guest_id":"bbbbbbbbbbbbbbbbbbbbbb","you_are_host":true},"status":"waiting_for_their_turn","revision":3,"remote_activity_sequence":2,"activity_at":"2026-11-13T13:00:00.000Z"}
	_check(Inbox.valid_server_room(base), "A room without a request is as before")
	var asked := base.duplicate(true)
	asked.redo = {"state": "asked_you", "stage_index": 0}
	_check(Inbox.valid_server_room(asked), "A room in play carries its request")
	for bad: Variant in ["asked_you", {"state": "maybe", "stage_index": 0}, {"state": "kept", "stage_index": -1}, {"state": "kept", "stage_index": 0, "extra": 1}]:
		var wrong := base.duplicate(true)
		wrong.redo = bad
		_check(not Inbox.valid_server_room(wrong), "A malformed request fails the page: " + str(bad))
	var client: RefCounted = Inbox.new(null, func() -> Dictionary: return {})
	var shown: Dictionary = client._normalize_room(asked)
	_check(shown.get("redo") == {"state": "asked_you", "stage_index": 0} and Inbox.valid_room(shown), "The kept room carries it and stays valid")
	_check(not client._normalize_room(base).has("redo"), "and a room without one has none")

func _chip() -> void:
	var controls: CanvasLayer = ChapterControls.new()
	root.add_child(controls)
	await process_frame
	_check(not controls.redo_chip.visible, "The chip hides until a second turn offers it")
	var taps := [0]
	controls.redo_chip_pressed.connect(func() -> void: taps[0] += 1)
	controls.show_redo_chip(PlayerCopy.REDO_ASK)
	controls.show_tries(7)
	await process_frame
	_check(controls.redo_chip.visible and controls.redo_chip.text == "Ask for a redo" and controls.redo_chip.mouse_filter == Control.MOUSE_FILTER_STOP, "Ask for a redo takes a tap")
	_check(controls.redo_chip.position.x > controls.try_pill.position.x + controls.try_pill.size.x and absf(controls.redo_chip.get_rect().get_center().y - controls.try_pill.get_rect().get_center().y) < 2.0, "It sits after the try pill, on its line")
	controls.redo_chip.pressed.emit()
	_check(taps[0] == 1, "A tap is reported once")
	controls.show_redo_chip(PlayerCopy.REDO_KEPT % "Sam", null, false)
	_check(controls.redo_chip.text == "Sam kept their turn" and controls.redo_chip.mouse_filter == Control.MOUSE_FILTER_IGNORE and controls.redo_chip.focus_mode == Control.FOCUS_NONE, "What became of it only reports")
	controls.show_redo_chip("")
	_check(not controls.redo_chip.visible, "Empty hides it")
	controls.queue_free()
	await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

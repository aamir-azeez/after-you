extends SceneTree
## Closing and removing rooms from the room hub: which rooms offer it, the
## confirm step, the request each choice sends, and that a removed room stays
## gone from every list the hub merges.
const Hub = preload("res://presentation/room_hub_screen.gd")
const InboxClient = preload("res://services/room_inbox_client.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Main = preload("res://main.gd")
const Save = preload("res://services/local_save.gd")
const Fakes = preload("res://tests/test_relay_online.gd")
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const FRIEND := "bbbbbbbbbbbbbbbbbbbbbb"

class Inbox extends RefCounted:
	var rooms: Array = []
	var unconfirmed: Array = []
	func view() -> Dictionary: return {"rooms": rooms, "stale": false, "error": ""}
	func unread(_room: Dictionary) -> bool: return false
	func confirmed(room: Dictionary) -> bool: return not unconfirmed.has(room.get("room_id"))
	func confirm_room_rendered(_version: int, _id: String) -> bool: return false
	func refresh() -> bool: return true

class Api extends Node:
	var base_url := "https://removal.example.test"
	var player_id := ME
	var device_token := "token"
	var busy := false

var checks := 0
var failures := 0
var paths: Array[String] = []
var page: Dictionary = {}
var local_rooms: Array = []

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _hub_choices()
	await _inbox_memory()
	await _main_requests()
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("ROOM REMOVAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _room(id: String, status: String, members: Array = [ME, FRIEND], version: int = 2) -> Dictionary:
	var key: String = Registry.offered_keys()[0]
	return {"api_version": version, "room_id": id, "chapter_key": key, "chapter_title": str(Registry.descriptor(key).title), "member_ids": members, "status": status,
		"revision": 1, "remote_activity_sequence": 0, "activity_at": 0, "family": "relay"}

func _card_buttons(hub: Node) -> Dictionary:
	var result := {}
	for card: Node in hub._rooms_list.get_children():
		var button := card.find_child("RemoveRoom", true, false) as Button
		var title := ""
		for label: Label in card.find_children("*", "Label", true, false):
			if label.text in ["Waiting for a friend", "Your turn", "Waiting for their turn", "Completed", "Closed", "Unavailable"]: title = label.text
		result[title] = button
	return result

func _hub_choices() -> void:
	var inbox := Inbox.new()
	inbox.rooms = [_room("waiting", "waiting_for_friend", [ME]), _room("guest", "your_turn", [FRIEND, ME]), _room("done", "completed"),
		_room("closed", "closed"), _room("cached", "waiting_for_their_turn"), _room("story", "unavailable", [], 3)]
	inbox.unconfirmed = ["cached"]
	var hub := Hub.new()
	hub.client = inbox
	var requests: Array = []
	hub.room_remove_requested.connect(func(room: Dictionary, action: String): requests.append([room.room_id, action]))
	root.add_child(hub)
	for i in range(3): await process_frame
	var buttons := _card_buttons(hub)
	var waiting: Button = buttons.get("Waiting for a friend")
	var guest: Button = buttons.get("Your turn")
	var closed: Button = buttons.get("Closed")
	_check(waiting != null and waiting.tooltip_text == "Close room" and waiting.accessibility_name == "Close room", "A hosted room still in play offers Close room")
	_check(guest != null and guest.tooltip_text == "Close room", "A guest in a room still in play is offered Close room too, since it ends for both")
	_check(closed != null and closed.tooltip_text == "Remove from list", "A room the other player closed offers Remove from list")
	_check(buttons.has("Waiting for their turn") and buttons["Waiting for their turn"] == null, "A room the latest server list has not confirmed offers no removal")
	_check(buttons.get("Unavailable") != null and buttons["Unavailable"].tooltip_text == "Remove from list", "An unavailable room can be taken off the list")
	_check(waiting != null and waiting.custom_minimum_size.x >= 48 and waiting.custom_minimum_size.y >= 48, "The remove control is touch sized")
	var closed_card: Node = closed.get_parent() if closed != null else null
	var closed_open: Button = null
	if closed_card != null:
		for button: Button in closed_card.find_children("*", "Button", true, false):
			if button.text == "Open": closed_open = button
	_check(closed_open != null and closed_open.disabled, "A closed room shows Closed and cannot be opened")
	# Confirm step: Cancel and Android Back change nothing; confirming emits once.
	waiting.pressed.emit()
	await process_frame
	var modal: Control = hub.find_child("RoomRemoveModal", true, false)
	_check(modal != null and _label(modal, "Close this room?") and _label(modal, "Your invitation stops working, and any turn you saved here is deleted. You can't undo this."), "Close asks first and says what is deleted")
	(modal.find_child("ModalCancel", true, false) as Button).pressed.emit()
	await process_frame
	_check(requests.is_empty() and hub.find_child("RoomRemoveModal", true, false) == null, "Cancel closes the question without a request")
	guest.pressed.emit()
	await process_frame
	modal = hub.find_child("RoomRemoveModal", true, false)
	_check(modal != null and _label(modal, "Close this room?") and _label(modal, "The room closes for both of you, and its saved turns are deleted. You can't undo this."), "Closing a shared room says it closes for both players")
	hub.go_back()
	await process_frame
	_check(requests.is_empty() and hub.find_child("RoomRemoveModal", true, false) == null and is_instance_valid(hub), "Android Back closes the question and keeps the hub")
	guest.pressed.emit()
	await process_frame
	(hub.find_child("RoomRemoveModal", true, false).find_child("ModalConfirm", true, false) as Button).pressed.emit()
	await process_frame
	_check(requests == [["guest", "close"]], "Confirming Close room asks the app to close the room")
	closed.pressed.emit()
	await process_frame
	(hub.find_child("RoomRemoveModal", true, false).find_child("ModalConfirm", true, false) as Button).pressed.emit()
	await process_frame
	_check(requests.back() == ["closed", "leave"], "Removing a room the other player closed drops its link")
	hub._select_tab("Completed")
	await process_frame
	var done: Button = _card_buttons(hub).get("Completed")
	_check(done != null and done.tooltip_text == "Remove from list", "The Completed tab offers Remove from list")
	done.pressed.emit()
	await process_frame
	modal = hub.find_child("RoomRemoveModal", true, false)
	_check(modal != null and _label(modal, "Remove this room?") and _label(modal, "Your friend keeps the room and its replay."), "Removing a finished room says the friend keeps it")
	var confirm := modal.find_child("ModalConfirm", true, false) as Button
	_check(confirm.text == "Remove", "The confirm button for a finished room reads Remove")
	confirm.pressed.emit()
	await process_frame
	_check(requests.back() == ["done", "hide"], "Removing a finished room only takes it off this list")
	hub.set_removing(true)
	await process_frame
	done = _card_buttons(hub).get("Completed")
	_check(done != null and done.disabled, "Remove controls wait while a request runs")
	hub.queue_free()
	await process_frame

func _label(node: Node, text: String) -> bool:
	for label: Label in node.find_children("*", "Label", true, false):
		if label.text == text: return true
	return false

func identity() -> Dictionary: return {"ready": true, "player_id": ME, "epoch": 1}
func inbox_transport(_method: int, _path: String, _body: Dictionary) -> Dictionary: return {"ok": true, "data": page.duplicate(true)}
func local_history() -> Array: return local_rooms.duplicate(true)

func _server(id: String, status: String) -> Dictionary:
	return {"room_id": id, "family": "relay", "api_version": 2, "chapter": {"id": "relay-isles", "version": 2},
		"membership": {"host_id": null if status == "closed" else ME, "guest_id": null if status == "closed" else FRIEND, "you_are_host": true},
		"status": status, "revision": null if status == "closed" else 3, "remote_activity_sequence": 0, "activity_at": null}

func _inbox_memory() -> void:
	var api := Api.new()
	api.base_url += str(Time.get_ticks_usec())
	root.add_child(api)
	var closed_id := "c".repeat(22)
	var done_id := "d".repeat(22)
	page = {"schema_version": 1, "rooms": [_server(closed_id, "closed"), _server(done_id, "completed")]}
	_check(InboxClient.valid_page(page), "The inbox accepts a room another player closed")
	var client := InboxClient.new(api, identity, inbox_transport)
	client.local = local_history
	local_rooms = [_room(done_id, "completed", [ME])]
	_check(not client.confirmed({"api_version": 2, "room_id": closed_id}), "Nothing is confirmed before a server read")
	_check(await client.refresh(), "The inbox reads the closed room")
	_check(client.confirmed({"api_version": 2, "room_id": closed_id}) and client.view().rooms.any(func(r: Dictionary) -> bool: return r.status == "closed"), "A server-listed closed room is confirmed and shown as closed")
	client.hide(client.view().rooms.filter(func(r: Dictionary) -> bool: return r.room_id == done_id)[0])
	_check(not client.view().rooms.any(func(r: Dictionary) -> bool: return r.room_id == done_id), "A hidden finished room leaves the list while the server still links it")
	client.forget(2, closed_id)
	page.rooms = [_server(done_id, "completed")]
	await client.refresh()
	_check(client.view().rooms.is_empty(), "A forgotten closed room and a hidden finished room stay off the list after a refresh")
	var restarted := InboxClient.new(api, identity, inbox_transport)
	restarted.local = local_history
	_check(restarted.view().rooms.is_empty(), "Both stay off the list after a restart")
	var replayed := _server(done_id, "your_turn")
	replayed.remote_activity_sequence = 1
	page.rooms = [replayed]
	await restarted.refresh()
	_check(restarted.view().rooms.any(func(r: Dictionary) -> bool: return r.room_id == done_id), "New activity from the friend brings a hidden room back")
	var config := ConfigFile.new()
	if config.load(InboxClient.CACHE_PATH) == OK:
		config.erase_section(restarted._cache_section())
		config.save(InboxClient.CACHE_PATH)
	api.queue_free()
	await process_frame

func _main_requests() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var app := Main.new()
	var path := "user://room-removal-%s.json" % Crypto.new().generate_random_bytes(8).hex_encode()
	paths.append(path)
	app.saves = Save.new(path)
	app.saves.data.settings.sound = false
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.api.queue_free()
	var api := Fakes.FakeApi.new()
	api.player_id = Fakes.HOST
	api.base_url += str(Time.get_ticks_usec())
	app.add_child(api)
	app.api = api
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.identity_data = {"player_id": Fakes.HOST, "device_token": "synthetic-device-token"}
	var live := "e".repeat(22)
	var gone := "f".repeat(22)
	var rooms := [_server(live, "your_turn"), _server(gone, "closed")]
	rooms[0].membership.host_id = Fakes.HOST
	var answers := {}
	api.responder = func(request: Dictionary) -> Dictionary:
		if request.path == "/v1/room-inbox": return {"ok": true, "data": {"schema_version": 1, "rooms": rooms.duplicate(true)}}
		var key: String = str(request.method) + " " + str(request.path)
		return answers.get(key, {"ok": false, "status": 404, "code": "not_found", "error": "Unexpected synthetic request"})
	app._show_rooms()
	for i in range(20):
		await process_frame
		if is_instance_valid(app.room_hub_screen) and app.room_inbox != null and not app.room_inbox.stale: break
	var hub: Node = app.room_hub_screen
	_check(is_instance_valid(hub) and app.mode == "rooms", "Main opens the hub")
	if not is_instance_valid(hub): return
	# Closing: the room is erased for both, then forgotten here.
	answers["%d /v2/rooms/%s" % [HTTPClient.METHOD_DELETE, live]] = {"ok": true, "data": {"deleted": true}}
	api.calls.clear()
	await app._remove_room_from_hub(app.room_inbox.view().rooms.filter(func(r: Dictionary) -> bool: return r.room_id == live)[0], "close")
	_check(api.calls.size() == 1 and api.calls[0].method == HTTPClient.METHOD_DELETE and api.calls[0].path == "/v2/rooms/" + live, "Close room sends one DELETE for that room")
	_check(not app.room_inbox.view().rooms.any(func(r: Dictionary) -> bool: return r.room_id == live), "A closed room leaves the hub at once")
	# A room the other player already closed: DELETE finds nothing, so only the link goes.
	answers["%d /v2/rooms/%s" % [HTTPClient.METHOD_DELETE, gone]] = {"ok": false, "status": 404, "code": "room_not_found", "error": "gone"}
	answers["%d /v2/rooms/%s/leave" % [HTTPClient.METHOD_POST, gone]] = {"ok": true, "data": {"schema_version": 1, "removed": true}}
	api.calls.clear()
	await app._remove_room_from_hub({"api_version": 2, "room_id": gone, "status": "your_turn"}, "close")
	_check(api.calls.size() == 2 and api.calls[1].path == "/v2/rooms/" + gone + "/leave" and api.calls[1].body == {"schema_version": 1}, "Closing a room that is already gone falls back to leaving it")
	_check(not app.room_inbox.view().rooms.any(func(r: Dictionary) -> bool: return r.room_id == gone), "The gone room leaves the hub")
	# A close that arrives after the last turn keeps the finished room.
	var late := "g".repeat(22)
	answers["%d /v2/rooms/%s" % [HTTPClient.METHOD_DELETE, late]] = {"ok": false, "status": 409, "code": "room_finished", "error": "This room has just finished, so it was kept."}
	await app._remove_room_from_hub({"api_version": 2, "room_id": late, "status": "your_turn"}, "close")
	_check(hub._notice.visible and hub._notice.text == "This room has just finished, so it was kept.", "A refused close says why and keeps the hub")
	_check(app.mode == "rooms" and is_instance_valid(app.room_hub_screen), "The hub stays open after a refused close")
	# Taking a finished room off the list sends nothing.
	api.calls.clear()
	await app._remove_room_from_hub({"api_version": 2, "room_id": late, "status": "completed", "remote_activity_sequence": 0}, "hide")
	_check(api.calls.is_empty(), "Removing a finished room from the list sends no request")
	app._close_room_hub()
	api.responder = Callable()
	viewport.queue_free()
	await process_frame
	await process_frame

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

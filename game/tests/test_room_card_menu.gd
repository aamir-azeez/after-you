extends SceneTree
## A finished room's "..." menu on the room hub's Completed tab: its rows by
## what the server offers, where it opens, how it closes, the Leave room
## confirm card (both-left text included), the Hidden rooms section with Show
## again, and the outlined hub tabs that never wrap.
const Hub = preload("res://presentation/room_hub_screen.gd")
const InboxClient = preload("res://services/room_inbox_client.gd")
const Registry = preload("res://services/chapter_registry.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const RoomCardMenu = preload("res://presentation/room_card_menu.gd")
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
	var base_url := "https://room-menu.example.test"
	var player_id := ME
	var device_token := "token"
	var busy := false

var checks := 0
var failures := 0
var page: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _rows_by_offer()
	await _anchoring_and_closing()
	await _menu_survives_rebuilds()
	await _leave_card()
	await _hidden_section()
	await _tabs()
	print("ROOM CARD MENU: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _room(id: String, status: String, version: int = 2, extra: Dictionary = {}) -> Dictionary:
	var key: String = Registry.offered_keys()[0]
	var room := {"api_version": version, "room_id": id, "chapter_key": key, "chapter_title": str(Registry.descriptor(key).title), "member_ids": [ME, FRIEND], "status": status,
		"revision": 1, "remote_activity_sequence": 0, "activity_at": 0, "family": "relay"}
	room.merge(extra, true)
	return room

func _hub(client: RefCounted) -> Node:
	var hub := Hub.new()
	hub.client = client
	hub.display_name = func(member: String) -> String: return "" if member == ME else "Sam"
	root.add_child(hub)
	hub._select_tab("Completed")
	for i in range(3): await process_frame
	return hub

func _menu_button(hub: Node, id: String) -> Button:
	var action: Button = hub.room_action(id)
	return action.get_parent().find_child("RoomMenu", false, false) as Button if action != null else null

func _open(hub: Node, id: String) -> CanvasLayer:
	var button := _menu_button(hub, id)
	if button == null: return null
	button.pressed.emit()
	await process_frame
	return hub.room_menu()

func _ids(menu: CanvasLayer) -> Array:
	return menu.rows.map(func(row: Button) -> String: return str(row.get_meta("menu_id"))) if menu != null else []

func _rows_by_offer() -> void:
	var inbox := Inbox.new()
	inbox.rooms = [_room("done", "completed"), _room("legacy", "completed", 1), _room("cached", "completed"), _room("story", "completed", 3)]
	inbox.unconfirmed = ["cached"]
	var hub: Node = await _hub(inbox)
	var watch: Button = hub.room_action("done")
	var dots := _menu_button(hub, "done")
	_check(dots != null and watch != null and dots.get_index() == watch.get_index() + 1, "The ... button sits right after Watch replay")
	_check(dots != null and dots.get_parent().find_child("RemoveRoom", false, false) == null, "A finished room has no trash button")
	_check(dots != null and is_equal_approx(dots.size.y, watch.size.y) and is_equal_approx(dots.size.x, dots.size.y), "The ... button is square and as tall as Watch replay")
	_check(dots != null and dots.get_theme_stylebox("normal").bg_color == watch.get_theme_stylebox("normal").bg_color and dots.get_theme_stylebox("normal").border_color == watch.get_theme_stylebox("normal").border_color, "The ... button has Watch replay's fill and border")
	_check(dots != null and dots.accessibility_name.begins_with(PlayerCopy.ROOM_MENU), "Screen readers hear More options")
	var ids := ["done", "legacy", "cached", "story"]
	var expected := [["hide"], ["hide"], ["hide"], ["hide"]]
	for index in range(4):
		var menu := await _open(hub, ids[index])
		_check(_ids(menu) == expected[index], "Without the server's offer the menu only hides: " + ids[index])
		if menu != null: menu.close()
		await process_frame
	hub.set_leave_finished(true)
	await process_frame
	expected = [["hide", "leave_finished"], ["hide", "leave_finished"], ["hide"], ["hide"]]
	for index in range(4):
		var menu := await _open(hub, ids[index])
		_check(_ids(menu) == expected[index], "With the offer, confirmed relay and legacy rooms can be left; unconfirmed and Story rooms only hide: " + ids[index])
		if index == 0 and menu != null:
			var hide: Button = menu.rows[0]
			var leave: Button = menu.rows[1]
			_check(_text(hide, "RowTitle") == PlayerCopy.ROOM_HIDE and _text(hide, "RowDetail") == PlayerCopy.ROOM_HIDE_DETAIL, "Hide from my list says it is only on this phone")
			_check(_text(leave, "RowTitle") == PlayerCopy.ROOM_LEAVE and _text(leave, "RowDetail") == PlayerCopy.ROOM_LEAVE_DETAIL, "Leave room says what it deletes")
			_check((leave.find_child("RowTitle", true, false) as Label).get_theme_color("font_color") == RoomCardMenu.DANGER_TEXT and (hide.find_child("RowTitle", true, false) as Label).get_theme_color("font_color") == RoomCardMenu.CREAM, "Leave room is soft pink; Hide is cream")
			_check((hide.find_child("RowIcon", true, false) as TextureRect).texture == Hub.HIDE_ICON and (leave.find_child("RowIcon", true, false) as TextureRect).texture == Hub.LEAVE_ICON, "Each row has its icon")
		if menu != null: menu.close()
		await process_frame
	hub.queue_free()
	await process_frame

func _text(row: Node, node_name: String) -> String:
	var label := row.find_child(node_name, true, false) as Label
	return label.text if label != null else ""

func _anchoring_and_closing() -> void:
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1560, 720), Vector2i(800, 360)]:
		root.size = size
		var inbox := Inbox.new()
		inbox.rooms = [_room("done", "completed")]
		var hub: Node = await _hub(inbox)
		hub.set_leave_finished(true)
		for i in range(2): await process_frame
		var button := _menu_button(hub, "done")
		var menu := await _open(hub, "done")
		await process_frame
		var rect: Rect2 = menu.panel_rect() if menu != null else Rect2()
		var anchor := Rect2(button.get_global_transform_with_canvas().origin, button.size)
		var label := " at %dx%d" % [size.x, size.y]
		_check(menu != null and is_equal_approx(rect.end.x, anchor.end.x), "The menu's right edge lines up with the button's" + label)
		if size.y >= 720: _check(menu != null and not menu.above and rect.position.y >= anchor.end.y and rect.position.y <= anchor.end.y + RoomCardMenu.POINTER + 1.0, "The menu opens directly under the button" + label)
		_check(menu != null and root.get_visible_rect().encloses(rect), "The menu stays inside the window" + label)
		var tip: Vector2 = menu.pointer.polygon[2] if menu != null else Vector2.ZERO
		_check(menu != null and absf(tip.x - anchor.get_center().x) <= 1.0, "The pointer points at the button" + label)
		_check(menu != null and menu.shade.color.a > 0.0 and menu.shade.color.a < 0.5, "The rest of the screen dims slightly" + label)
		# A tap outside closes it and keeps the hub.
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = Vector2(4, 4)
		if menu != null: menu._on_shade_input(click)
		await process_frame
		_check(hub.room_menu() == null and is_instance_valid(hub), "An outside tap closes the menu" + label)
		menu = await _open(hub, "done")
		var closed_hub := [false]
		hub.closed.connect(func(): closed_hub[0] = true)
		hub.go_back()
		await process_frame
		_check(hub.room_menu() == null and not closed_hub[0], "Back closes the menu first and keeps the hub" + label)
		menu = await _open(hub, "done")
		var escape := InputEventAction.new()
		escape.action = "ui_cancel"
		escape.pressed = true
		root.push_input(escape)
		await process_frame
		await process_frame
		_check(hub.room_menu() == null, "Escape closes the menu" + label)
		# Opened from the keyboard, the first row takes focus and rows wrap.
		menu = RoomCardMenu.open(button, hub._menu_rows(inbox.rooms[0]), true)
		hub._menu = menu
		await process_frame
		_check(menu.rows[0].has_focus() and menu.rows[1].focus_neighbor_bottom == menu.rows[1].get_path_to(menu.rows[0]), "Keys reach the rows and wrap around" + label)
		menu.close()
		await process_frame
		_check(button.has_focus(), "Closing from the keyboard gives focus back to the ... button" + label)
		hub.queue_free()
		await process_frame
	root.size = Vector2i(1280, 720)

## The Leave offer arriving and a refresh that changes a card both rebuild the
## cards; an open menu holds that rebuild, so it stays open and a tap on it never
## reaches the card underneath. The cards are drawn once it closes.
func _menu_survives_rebuilds() -> void:
	var inbox := Inbox.new()
	inbox.rooms = [_room("done", "completed"), _room("next", "completed")]
	var hub: Node = await _hub(inbox)
	var opened: Array = []
	var requests: Array = []
	hub.room_open_requested.connect(func(room: Dictionary, _source: Control): opened.append(room.room_id))
	hub.room_remove_requested.connect(func(room: Dictionary, action: String): requests.append([room.room_id, action]))
	var watch: Button = hub.room_action("done")
	var menu := await _open(hub, "done")
	_check(_ids(menu) == ["hide"], "Before the offer the menu only hides")
	hub.set_leave_finished(true)
	await process_frame
	_check(hub.room_menu() == menu and is_instance_valid(watch) and hub.room_action("done") == watch, "The Leave offer arriving keeps the open menu and its card")
	inbox.rooms[1] = _room("next", "completed", 2, {"remote_activity_sequence": 3, "activity_at": 9})
	hub._render()
	await process_frame
	_check(hub.room_menu() == menu and hub.room_action("done") == watch, "A refresh that changes a card keeps the open menu and its card")
	# A real tap on the Hide row goes to the menu, never to Watch replay beneath it.
	var row: Button = menu.rows[0]
	var spot: Vector2 = row.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = spot
		click.global_position = spot
		root.push_input(click)
		await process_frame
	await process_frame
	await process_frame
	_check(requests == [["done", "hide"]] and opened.is_empty(), "The tap picks the row and no card under it: " + str(requests) + " " + str(opened))
	_check(hub.room_menu() == null and not is_instance_valid(watch), "Once the menu closes the cards are drawn again")
	var fresh := await _open(hub, "done")
	_check(_ids(fresh) == ["hide", "leave_finished"], "The redrawn card's menu has the offer that arrived")
	if fresh != null: fresh.close()
	hub.queue_free()
	await process_frame

func _leave_card() -> void:
	var inbox := Inbox.new()
	inbox.rooms = [_room("done", "completed"), _room("alone", "completed", 2, {"partner_left": true})]
	var hub: Node = await _hub(inbox)
	hub.set_leave_finished(true)
	await process_frame
	var requests: Array = []
	hub.room_remove_requested.connect(func(room: Dictionary, action: String): requests.append([room.room_id, action]))
	var menu := await _open(hub, "done")
	menu.rows[1].pressed.emit()
	await process_frame
	await process_frame
	var modal: Control = hub.find_child("RoomLeaveModal", true, false)
	var title := str(inbox.rooms[0].chapter_title)
	_check(modal != null and _label(modal, PlayerCopy.ROOM_LEAVE_TITLE) and _label(modal, PlayerCopy.ROOM_LEAVE_SUBTITLE % [title, "Sam"]), "The card names the room and the friend")
	_check(modal != null and _label(modal, PlayerCopy.ROOM_LEAVE_BODY % "Sam") and _label(modal, PlayerCopy.ROOM_LEAVE_PHONE), "The card says what is deleted, what Sam keeps and that the phone's replay stays")
	var line: Node = modal.find_child("LeavePhoneLine", true, false) if modal != null else null
	if line != null:
		var icon := line.find_child("PhoneIcon", true, false) as Control
		var words: Label = null
		for child: Node in line.get_children(): if child is Label: words = child
		_check(absf(icon.get_global_rect().get_center().y - words.get_global_rect().get_center().y) <= 1.0, "The phone icon is centred on its line")
	var cancel := modal.find_child("ModalCancel", true, false) as Button
	var confirm := modal.find_child("ModalConfirm", true, false) as Button
	_check(cancel.text == "Cancel" and not cancel.has_theme_stylebox_override("normal") and confirm.text == PlayerCopy.ROOM_LEAVE and confirm.has_theme_stylebox_override("normal") and confirm.get_theme_stylebox("normal").bg_color == Color("e9b3aa"), "Cancel is the cream button and Leave room the pink one")
	_check(cancel.has_focus(), "The safe choice takes focus")
	_check(is_equal_approx(cancel.size.y, confirm.size.y), "Both buttons are the same height")
	cancel.pressed.emit()
	await process_frame
	_check(requests.is_empty(), "Cancel leaves nothing")
	menu = await _open(hub, "done")
	menu.rows[1].pressed.emit()
	await process_frame
	(hub.find_child("RoomLeaveModal", true, false).find_child("ModalConfirm", true, false) as Button).pressed.emit()
	await process_frame
	_check(requests == [["done", "leave_finished"]], "Leave room asks the app to leave")
	menu = await _open(hub, "alone")
	menu.rows[1].pressed.emit()
	await process_frame
	modal = hub.find_child("RoomLeaveModal", true, false)
	_check(modal != null and _label(modal, PlayerCopy.ROOM_LEAVE_BODY_LAST % "Sam") and not _label(modal, PlayerCopy.ROOM_LEAVE_BODY % "Sam"), "When the friend already left, the card says the room is deleted for good")
	hub.go_back()
	await process_frame
	_check(hub.find_child("RoomLeaveModal", true, false) == null and is_instance_valid(hub), "Back closes the card")
	hub.queue_free()
	await process_frame

func identity() -> Dictionary: return {"ready": true, "player_id": ME, "epoch": 1}
func inbox_transport(_method: int, _path: String, _body: Dictionary) -> Dictionary: return {"ok": true, "data": page.duplicate(true)}

func _server(id: String, sequence: int = 0) -> Dictionary:
	return {"room_id": id, "family": "relay", "api_version": 2, "chapter": {"id": "relay-isles", "version": 2},
		"membership": {"host_id": ME, "guest_id": FRIEND, "you_are_host": true},
		"status": "completed", "revision": 3, "remote_activity_sequence": sequence, "activity_at": null}

func _hidden_section() -> void:
	var api := Api.new()
	api.base_url += str(Time.get_ticks_usec())
	root.add_child(api)
	var kept := "k".repeat(22)
	var tidy := "t".repeat(22)
	var gone := "g".repeat(22)
	page = {"schema_version": 1, "rooms": [_server(kept), _server(tidy), _server(gone)]}
	var client := InboxClient.new(api, identity, inbox_transport)
	await client.refresh()
	var hub: Node = await _hub(client)
	hub.room_remove_requested.connect(func(room: Dictionary, action: String):
		if action == "hide": client.hide(room)
		hub.show_notice(""))
	hub.room_show_requested.connect(func(room: Dictionary):
		client.show_again(room)
		hub.show_notice(""))
	_check(hub.find_child("HiddenRoomsFold", true, false) == null, "No Hidden rooms line while nothing is hidden")
	var menu := await _open(hub, tidy)
	menu.rows[0].pressed.emit()
	await process_frame
	client.forget(2, gone)
	hub._render()
	await process_frame
	var fold := hub.find_child("HiddenRoomsFold", true, false) as Button
	_check(fold != null and fold.text == PlayerCopy.ROOM_HIDDEN_FOLD % 1, "Hiding a room adds Hidden rooms · 1; a room left for good is not counted")
	_check(fold != null and fold.get_theme_color("font_color") == Hub.WARM and fold.icon == Hub.FOLD_CLOSED_ICON, "The fold line is warm yellow with a closed chevron")
	_check(hub.find_child("HiddenRoom", true, false) == null, "Hidden rooms start folded")
	_check(_card_ids(hub) == [kept], "The hidden room left the list")
	fold.pressed.emit()
	await process_frame
	var hidden_card: Node = hub.find_child("HiddenRoom", true, false)
	_check(hidden_card != null and _label(hidden_card, PlayerCopy.ROOM_HIDDEN_LINE % "Sam") and (hidden_card as Control).modulate.a < 1.0, "Unfolded, the hidden room shows dimmed with who and where")
	_check((hub.find_child("HiddenRoomsFold", true, false) as Button).icon == Hub.FOLD_OPEN_ICON, "The chevron turns when unfolded")
	var show := hidden_card.find_child("ShowAgain", true, false) as Button if hidden_card != null else null
	if show != null: show.pressed.emit()
	await process_frame
	_check(hub.find_child("HiddenRoomsFold", true, false) == null and _card_ids(hub).has(tidy), "Show again puts the room back and the section goes")
	# A hidden room comes back on its own with new activity.
	client.hide(client.view().rooms.filter(func(r: Dictionary) -> bool: return r.room_id == tidy)[0])
	_check(client.hidden_rooms().size() == 1, "Hidden again")
	page.rooms = [_server(kept), _server(tidy, 2)]
	await client.refresh()
	_check(client.hidden_rooms().is_empty() and client.view().rooms.any(func(r: Dictionary) -> bool: return r.room_id == tidy), "New activity brings a hidden room back and out of the section")
	hub.queue_free()
	var config := ConfigFile.new()
	if config.load(InboxClient.CACHE_PATH) == OK:
		config.erase_section(client._cache_section())
		config.save(InboxClient.CACHE_PATH)
	api.queue_free()
	await process_frame

func _card_ids(hub: Node) -> Array:
	var ids := []
	for room: Variant in hub._visible_rooms: ids.append(room.room_id)
	return ids

func _tabs() -> void:
	for size: Vector2i in [Vector2i(800, 360), Vector2i(1280, 720), Vector2i(1560, 720)]:
		root.size = size
		var inbox := Inbox.new()
		for index in range(12): inbox.rooms.append(_room("r%021d" % index, "your_turn"))
		var hub: Node = await _hub(inbox)
		hub._select_tab("Your rooms")
		for i in range(3): await process_frame
		var label := " at %dx%d" % [size.x, size.y]
		var tops := {}
		var fits := true
		for tab_name: String in ["Your rooms", "Friends", "Completed"]:
			var tab: Button = hub._tab_buttons[tab_name]
			tops[tab.global_position.y] = true
			var font := tab.get_theme_font("font")
			var style := tab.get_theme_stylebox("normal")
			var needed := font.get_string_size(tab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, tab.get_theme_font_size("font_size")).x + style.get_minimum_size().x
			if tab.size.x + 0.5 < needed or tab.size.y > 60.0 or tab.get_global_rect().end.x > root.get_visible_rect().end.x: fits = false
		var yours: Button = hub._tab_buttons["Your rooms"]
		_check(yours.text == "Your rooms · 12" and fits and tops.size() == 1, "Every tab fits on one line, Your rooms · 12 included" + label)
		var plain: Button = hub._tab_buttons["Completed"]
		var outline := plain.get_theme_stylebox("normal") as StyleBoxFlat
		_check(outline != null and outline.border_width_top > 0 and outline.bg_color.a > 0.0, "An unselected tab has its own outline and background" + label)
		var selected := yours.get_theme_stylebox("normal") as StyleBoxFlat
		_check(selected != null and selected.bg_color == Color("3a6b5f"), "The selected tab keeps its filled look" + label)
		hub.queue_free()
		await process_frame
	root.size = Vector2i(1280, 720)

func _label(node: Node, text: String) -> bool:
	for found: Label in node.find_children("*", "Label", true, false):
		if found.text == text: return true
	return false

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

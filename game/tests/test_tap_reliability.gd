extends SceneTree
## One finger tap, one action. A real fingertip never lands still: Android
## forwards every sub-pixel move (project.godot turns its own slop off for the
## pinch and stick controls), so each tap here wobbles by a few pixels the way
## a thumb does. Taps go through the engine's own input path: screen touches
## enter through Input.parse_input_event and its mouse emulation, with
## Input.emulate_touch_from_mouse on so this headless display reports a
## touchscreen and ScrollContainer runs its touch drag.
## Covers: lists that scroll (the 0.6.0 regression), the room hub and Friends
## refreshing under a finger, the shared chapter picker, Home, dialogs, a long
## frame between press and release, and focus held elsewhere.

const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const FakeApi = preload("res://tests/fake_rooms_api.gd")
const Hub = preload("res://presentation/room_hub_screen.gd")
const Friends = preload("res://presentation/friends_screen.gd")
const Controls = preload("res://presentation/control_theme.gd")
const TouchInput = preload("res://presentation/touch_input.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const ActionButtons = preload("res://presentation/action_buttons.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Thumbs = preload("res://services/chapter_thumbnail_catalog.gd")
const PhotoStrip = preload("res://presentation/reaction_photo_strip.gd")
const Session = preload("res://services/relay_online_session.gd")
const BusyTapGate = preload("res://presentation/busy_tap_gate.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

## A thumb's wobble during a tap: out a few pixels and partly back.
const WOBBLES := [
	[Vector2(0, 0.5)],
	[Vector2(1, 1)],
	[Vector2(0, 3), Vector2(1, -1)],
	[Vector2(4, -2)],
	[Vector2(2, 3), Vector2(-1, 2), Vector2(1, 1)],
]

class Inbox extends RefCounted:
	var rooms: Array = []
	var refreshes := 0
	func view() -> Dictionary: return {"rooms": rooms, "stale": false, "error": ""}
	func unread(_room: Dictionary) -> bool: return false
	func confirm_room_rendered(_version: int, _id: String) -> bool: return false
	func refresh() -> bool:
		refreshes += 1
		return true

class FriendsStub extends RefCounted:
	signal released
	var busy := false
	var last_error := ""
	var page: Dictionary = {}
	var due := false
	var hold := false
	var joins: Array = []
	func join_friend(row: Dictionary) -> Dictionary:
		joins.append(row.player_id)
		return {"room_id": "joined"}
	func context() -> Dictionary: return {"base_url": "https://friends.invalid", "player_id": "OOOOOOOOOOOOOOOOOOOOOO"}
	func view() -> Dictionary: return page
	func refresh_due(_manual: bool = false) -> bool: return due
	func refresh_wait_ms(_manual: bool = false) -> int: return 0
	func join_wait_ms() -> int: return 0
	func refresh(_manual: bool = false) -> bool:
		due = false
		if hold:
			busy = true
			await released
			busy = false
		return true

## A server whose answers wait while `hold` is on, as on a slow phone network.
class HeldApi extends Node:
	signal release
	var player_id := "HHHHHHHHHHHHHHHHHHHHHH"
	var device_token := "synthetic-device-token"
	var base_url := "https://tap-replays.invalid"
	var busy := false
	var hold := false
	func configured() -> bool: return true
	func request_json(method: int, path: String, _body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		while hold: await release
		if path == "/v2/capabilities": return {"ok": true, "status": 200, "data": {"api_version": 2, "recording_version": 2, "simulation_version": 2, "mutations_enabled": true, "validation": "structural_client_replay_required", "chapters": []}}
		if method == HTTPClient.METHOD_GET and path == "/v2/rooms": return {"ok": true, "status": 200, "data": {"rooms": []}}
		return {"ok": false, "status": 404, "code": "not_found", "error": "Synthetic missing feature."}

class SessionStore extends RefCounted:
	var values: Dictionary = {}
	func load_scope(scope: String) -> Dictionary: return {"ok": true, "found": values.has(scope), "value": values.get(scope, {}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		values[scope] = JSON.parse_string(JSON.stringify(value))
		return {"ok": true}

class PhotoControllerStub extends RefCounted:
	func invalidate_identity() -> void: pass

class NicknameStub extends RefCounted:
	func display_name(_server: String, _owner: String, friend: String, _fallback: String = "") -> String: return "Pal " + friend.substr(0, 2)
	func nickname(_server: String, _owner: String, _friend: String) -> String: return ""

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var original_touch := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	_check(DisplayServer.is_touchscreen_available(), "This display reports a touchscreen once touch emulation is on")
	_deadzone()
	await _list_taps()
	await _hub()
	await _friends()
	await _photo_bubble()
	await _dialog()
	await _long_frame()
	await _focus_elsewhere()
	await _home()
	await _home_after_replays()
	Input.emulate_touch_from_mouse = original_touch
	print("AFTER YOU TAP RELIABILITY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _deadzone() -> void:
	# About 10 dp of finger travel, in canvas units: a 420 dpi phone drawn at
	# 1.5 physical pixels per unit waits 18 units; limits hold at the extremes.
	_check(TouchInput.deadzone_for(420, 1.5) == 18, "A 420 dpi phone at 1.5x waits about 10 dp (18 units)")
	_check(TouchInput.deadzone_for(160, 1.0) == 10, "A 160 dpi screen at 1x waits 10 units")
	_check(TouchInput.deadzone_for(96, 1.0) == TouchInput.MIN_DEADZONE, "A low-density desktop keeps the minimum slop")
	_check(TouchInput.deadzone_for(640, 0.5) == TouchInput.MAX_DEADZONE, "A dense screen drawn small is capped")
	_check(TouchInput.deadzone_for(0, 0.0) >= TouchInput.MIN_DEADZONE, "An unknown density or scale still gets a slop")
	_check(int(ProjectSettings.get_setting(TouchInput.SCROLL_DEADZONE_SETTING)) >= TouchInput.MIN_DEADZONE, "The project default slop is set for every list")
	var installed := TouchInput.install(root)
	var scroll := ScrollContainer.new()
	_check(scroll.scroll_deadzone == installed and installed >= TouchInput.MIN_DEADZONE, "A list built after install starts with the slop")
	scroll.free()


func _list_taps() -> void:
	var made := _touch_list()
	var host: Control = made[0]
	var scroll: ScrollContainer = made[1]
	var buttons: Array = made[2]
	var taps: Array = made[3]
	await _settle()
	_check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, "The list overflows, so it can scroll")
	_check(scroll.scroll_deadzone >= TouchInput.MIN_DEADZONE, "touch_scroll gives the list a finger's slop")
	var every_once := true
	for wobble: Array in WOBBLES:
		taps[0] = 0
		await _tap(root, (buttons[2] as Control).get_global_rect().get_center(), wobble)
		every_once = every_once and taps[0] == 1 and scroll.scroll_vertical == 0
	_check(every_once, "A wobbling tap on a button in a scrolling list presses it exactly once and does not scroll")
	taps[0] = 0
	await _tap(root, (buttons[2] as Control).get_global_rect().get_center(), [Vector2(0, -40), Vector2(0, -40), Vector2(0, -40)])
	_check(taps[0] == 0 and scroll.scroll_vertical > 0, "A real drag from the same button still scrolls and presses nothing")
	await _rest(scroll)
	scroll.scroll_vertical = 0
	await _settle()
	# Negative control: the engine default (no slop) loses the same taps.
	scroll.scroll_deadzone = 0
	var lost := 0
	for wobble: Array in WOBBLES:
		taps[0] = 0
		await _tap(root, (buttons[2] as Control).get_global_rect().get_center(), wobble)
		if taps[0] == 0: lost += 1
		scroll.scroll_vertical = 0
		await _settle()
	_check(lost == WOBBLES.size(), "Without the slop every wobbling tap is lost (the 0.6.0 behaviour)")
	host.queue_free()
	await _settle()


func _touch_list() -> Array:
	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(100, 100)
	scroll.size = Vector2(600, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.add_child(scroll)
	scroll.scroll_deadzone = 0
	Controls.touch_scroll(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var taps := [0]
	var buttons: Array = []
	for index: int in range(10):
		var button := Button.new()
		button.text = "Open %d" % index
		button.custom_minimum_size = Vector2(300, 60)
		button.pressed.connect(func(): taps[0] += 1)
		list.add_child(button)
		buttons.append(button)
	return [host, scroll, buttons, taps]


func _hub() -> void:
	var inbox := Inbox.new()
	var keys: Array = Registry.keys()
	for index: int in range(6):
		var key: String = keys[index % keys.size()]
		inbox.rooms.append({"api_version": 2, "room_id": "room-%d" % index, "chapter_key": key, "chapter_title": str(Registry.descriptor(key).title), "member_ids": ["me", "friend"], "status": "your_turn" if index % 2 == 0 else "waiting_for_their_turn", "part": 1, "stage_count": 2})
	var chapters: Array[Dictionary] = []
	for key: String in keys:
		chapters.append({"key": key, "title": str(Registry.descriptor(key).title), "stage_count": 2})
	var hub := Hub.new()
	hub.client = inbox
	hub.set_chapters(chapters)
	hub.display_name = func(member: String) -> String: return "" if member == "me" else "Sam"
	hub.thumbnail_for = func(key: String) -> String: return Thumbs.path(key)
	var opened: Array = []
	var picked: Array = []
	hub.room_open_requested.connect(func(room: Dictionary, _source: Control): opened.append(room.room_id))
	hub.chapter_picked.connect(func(key: String): picked.append(key))
	root.add_child(hub)
	await _settle()
	await _settle()
	var first := _room_action(hub, "room-0")
	_check(first != null and hub._rooms_scroll.scroll_deadzone >= TouchInput.MIN_DEADZONE, "The hub's room list has a finger's slop")
	if first == null:
		hub.queue_free()
		return
	await _tap(root, first.get_global_rect().get_center(), WOBBLES[4])
	_check(opened == ["room-0"], "A wobbling tap on a room card opens that room once")
	# A refresh that brings the same rooms keeps the same cards.
	opened.clear()
	hub.refresh()
	await _settle()
	_check(_room_action(hub, "room-0") == first and is_instance_valid(first), "A refresh with unchanged rooms keeps the drawn cards")
	# A refresh lands while the finger is down: the card stays until release.
	first = _room_action(hub, "room-0")
	if first == null:
		hub.queue_free()
		return
	var at := first.get_global_rect().get_center()
	_touch(root, at, true)
	_move(root, at + Vector2(1, 2), Vector2(1, 2))
	inbox.rooms[0] = inbox.rooms[0].duplicate(true)
	inbox.rooms[0].part = 2
	inbox.rooms.append({"api_version": 2, "room_id": "room-new", "chapter_key": keys[0], "chapter_title": "New", "member_ids": ["me", "friend"], "status": "your_turn", "part": 1, "stage_count": 2})
	hub.refresh()
	await _settle()
	_check(is_instance_valid(first) and first.is_inside_tree() and first.is_pressed(), "A refresh with news waits while a finger is on a card")
	_touch(root, at + Vector2(1, 2), false)
	await _settle()
	await _settle()
	_check(opened == ["room-0"], "The tap made during the refresh opens its room exactly once")
	_check(not is_instance_valid(first) or not first.is_inside_tree(), "The held-back refresh redraws right after the release")
	_check(_room_action(hub, "room-new") != null and _room_action(hub, "room-0") != null, "The redraw shows the refreshed rooms")
	# The shared chapter picker inside the hub.
	hub.open_chapter_picker()
	await _settle()
	await _settle()
	var picker: ScrollContainer = hub._picker
	_check(picker != null and picker.scroll_deadzone >= TouchInput.MIN_DEADZONE, "The chapter picker has a finger's slop")
	if picker != null:
		var open := (picker.grid.get_child(0) as Control).find_child("ChapterOpen", true, false) as Button
		_check(open != null, "The first chapter card has its open button")
		if open != null:
			await _tap(root, open.get_global_rect().get_center(), WOBBLES[2])
			_check(picked.size() == 1, "A wobbling tap on a chapter card picks it exactly once")
	hub.queue_free()
	await _settle()


func _room_action(hub: Node, room_id: String) -> Button:
	var room_index := -1
	for index: int in range(hub._visible_rooms.size()):
		if hub._visible_rooms[index].room_id == room_id: room_index = index
	if room_index < 0: return null
	var cards: Array = []
	for child: Node in hub._rooms_list.get_children():
		if not child.is_queued_for_deletion(): cards.append(child)
	if room_index >= cards.size(): return null
	for button: Button in (cards[room_index] as Node).find_children("*", "Button", true, false):
		if button.name != "RemoveRoom": return button
	return null


func _friends() -> void:
	var stub := FriendsStub.new()
	var people: Array = []
	for index: int in range(6):
		people.append({"player_id": "F%d" % index + "Q".repeat(20), "status": "accepted", "online": index % 2 == 0, "expires_after_seconds": 40 if index % 2 == 0 else 0, "join_available": false, "request_id": ""})
	stub.page = {"friends": people, "friend_code": "ABCD1234", "shared_room": null}
	var screen: CanvasLayer = Friends.new()
	screen.client = stub
	screen.nickname_store = NicknameStub.new()
	root.add_child(screen)
	await _settle()
	await _settle()
	var remove := _visible_remove(screen)
	_check(remove != null, "A Remove friend action is visible")
	if remove == null:
		screen.close()
		await _settle()
		return
	# Each read counts an online friend's lease down; that is never drawn.
	for peer: Dictionary in people:
		if peer.online: peer.expires_after_seconds = 31
	stub.due = true
	await screen._refresh()
	await _settle()
	_check(is_instance_valid(remove) and remove.is_inside_tree(), "A refresh that only moves an online friend's lease keeps the drawn page")
	# A tap while the list refresh is still out runs once it lands.
	var rename := _visible_button(screen, "Edit nickname")
	_check(rename != null, "An Edit nickname action is visible")
	if rename != null:
		stub.due = true
		stub.hold = true
		screen._refresh()
		await _settle()
		_check(stub.busy, "The list refresh is out")
		await _tap(root, rename.get_global_rect().get_center(), WOBBLES[1])
		_check(not is_instance_valid(screen._modal), "The tap waits for the refresh")
		stub.hold = false
		stub.released.emit()
		await _settle()
		_check(is_instance_valid(screen._modal), "The tap made during the refresh opens the nickname editor once it lands")
		if is_instance_valid(screen._modal): screen._close_modal(false)
		await _settle()
	remove = _visible_remove(screen)
	if remove == null:
		screen.close()
		await _settle()
		return
	# A friend comes online while the finger is on Remove: the page waits.
	var at := remove.get_global_rect().get_center()
	_touch(root, at, true)
	_move(root, at + Vector2(-1, 2), Vector2(-1, 2))
	people[1] = people[1].duplicate(true)
	people[1].online = not people[1].online
	screen._next_local_refresh = 0
	await _settle()
	await _settle()
	_check(is_instance_valid(remove) and remove.is_inside_tree() and remove.is_pressed(), "A presence change waits while a finger is on a friend's button")
	_touch(root, at + Vector2(-1, 2), false)
	await _settle()
	_check(not screen._remove.is_empty(), "That tap still opens the Remove confirmation, once")
	var confirm_shown := false
	for label: Label in screen.find_children("*", "Label", true, false):
		if label.text == "Remove friend?": confirm_shown = true
	_check(confirm_shown and not screen._render_waiting, "The page redraws after the release")
	screen._remove = {}
	# Join stays live during the refresh too, and joins the friend once.
	people[0] = people[0].duplicate(true)
	people[0].join_available = true
	people[0].request_id = "share-1"
	screen._render()
	await _settle()
	var join := _visible_button_text(screen, "Join")
	_check(join != null, "A Join action is visible")
	if join != null:
		stub.due = true
		stub.hold = true
		screen._refresh()
		await _settle()
		_check(not join.disabled, "Join stays live while the list refresh is out")
		await _tap(root, join.get_global_rect().get_center(), WOBBLES[2])
		_check(stub.joins.is_empty(), "The Join tap waits for the refresh")
		stub.hold = false
		stub.released.emit()
		await _settle()
		_check(stub.joins == [people[0].player_id], "The Join tap made during the refresh joins that friend once")
	if is_instance_valid(screen): screen.close()
	await _settle()


func _visible_remove(screen: Node) -> Button:
	return _visible_button(screen, "Remove friend")


func _visible_button_text(screen: Node, text: String) -> Button:
	for button: Button in screen.find_children("*", "Button", true, false):
		if button.text == text and not button.is_queued_for_deletion() and button.is_visible_in_tree(): return button
	return null


func _visible_button(screen: Node, tip: String) -> Button:
	var inner: ScrollContainer = null
	for node: Node in screen._scroll.find_children("*", "ScrollContainer", true, false): inner = node
	if inner == null: return null
	for button: Button in inner.find_children("*", "Button", true, false):
		if button.tooltip_text == tip and not button.is_queued_for_deletion() and inner.get_global_rect().encloses(button.get_global_rect()): return button
	return null


func _photo_bubble() -> void:
	# Replay photo bubbles follow the spirits every frame. Their Edit and
	# Report buttons must survive that, or no tap on them could ever finish.
	var strip: Control = PhotoStrip.new()
	strip.controller_override = PhotoControllerStub.new()
	strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(strip)
	strip.show()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 1, 6)
	camera.current = true
	var actor := Node3D.new()
	root.add_child(actor)
	var bubble := VBoxContainer.new()
	bubble.set_meta("player_slot", "p0")
	var edit := Button.new()
	edit.text = "Edit"
	edit.custom_minimum_size = Vector2(72, 48)
	var taps := [0]
	edit.pressed.connect(func(): taps[0] += 1)
	bubble.add_child(edit)
	strip.add_child(bubble)
	bubble.size = PhotoStrip.BUBBLE_SIZE
	strip._bubbles.append(bubble)
	var safe := Rect2(Vector2.ZERO, Vector2(root.size))
	strip.position_over_spirits(camera, {"p0": actor}, safe)
	await _settle()
	_check(bubble.visible, "The bubble shows above its spirit")
	var at := edit.get_global_rect().get_center()
	_touch(root, at, true)
	for _frame: int in range(4):
		strip.position_over_spirits(camera, {"p0": actor}, safe)
		await process_frame
	_move(root, at + Vector2(1, 1), Vector2(1, 1))
	strip.position_over_spirits(camera, {"p0": actor}, safe)
	_touch(root, at + Vector2(1, 1), false)
	await _settle()
	_check(taps[0] == 1, "A tap on a photo bubble's button lasts through the per-frame placement")
	strip.queue_free()
	camera.queue_free()
	actor.queue_free()
	await _settle()


func _dialog() -> void:
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var confirmed := [0]
	var modal: Control = InGameModal.open(host, "TapModal", "Remove this room?", "")
	var confirm: Button = modal.add_actions("Remove", func(): confirmed[0] += 1)
	await _settle()
	await _tap(root, confirm.get_global_rect().get_center(), WOBBLES[3])
	_check(confirmed[0] == 1, "A wobbling tap on a dialog's main action runs it exactly once")
	var closed := [0]
	modal.closed.connect(func(): closed[0] += 1)
	var cancel := modal.find_child("ModalCancel", true, false) as Button
	await _tap(root, cancel.get_global_rect().get_center(), WOBBLES[1])
	_check(closed[0] == 1 and confirmed[0] == 1, "A tap on Cancel closes the dialog once and runs nothing else")
	host.queue_free()
	await _settle()


func _long_frame() -> void:
	# A chapter build or a proof check can hold the main thread between the
	# press and the release. Buttons act on release, and a late release still
	# counts as the same tap.
	var shared := ActionButtons.create("continue", func(): pass)
	_check(shared.action_mode == BaseButton.ACTION_MODE_BUTTON_RELEASE, "Shared actions fire on release, so a drag can still scroll a list")
	shared.free()
	var host := Button.new()
	host.text = "Slow"
	host.position = Vector2(200, 200)
	host.size = Vector2(240, 60)
	var taps := [0]
	host.pressed.connect(func(): taps[0] += 1)
	root.add_child(host)
	await _settle()
	var at := host.get_global_rect().get_center()
	_touch(root, at, true)
	_move(root, at + Vector2(2, 1), Vector2(2, 1))
	OS.delay_msec(450)
	await process_frame
	OS.delay_msec(450)
	await process_frame
	_touch(root, at + Vector2(2, 1), false)
	await _settle()
	_check(taps[0] == 1, "A tap held across two long frames still presses once")
	host.queue_free()
	await _settle()


func _focus_elsewhere() -> void:
	var host := VBoxContainer.new()
	host.position = Vector2(200, 200)
	root.add_child(host)
	var counts := [0, 0]
	var first := Button.new()
	first.text = "First"
	first.custom_minimum_size = Vector2(240, 60)
	first.focus_mode = Control.FOCUS_ALL
	first.pressed.connect(func(): counts[0] += 1)
	host.add_child(first)
	var second := Button.new()
	second.text = "Second"
	second.custom_minimum_size = Vector2(240, 60)
	second.focus_mode = Control.FOCUS_ALL
	second.pressed.connect(func(): counts[1] += 1)
	host.add_child(second)
	await _settle()
	second.grab_focus()
	await _tap(root, first.get_global_rect().get_center(), WOBBLES[2])
	_check(counts == [1, 0], "Keyboard focus on another button does not swallow the first tap")
	host.queue_free()
	await _settle()


func _home() -> void:
	var path := "user://tap-reliability-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var storage := Storage.new(path)
	storage.data.settings.sound = false
	storage.data.settings.haptics = false
	_check(storage.flush(), "Prepare an isolated muted save")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var app := Main.new()
	app.saves = storage
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	var api := FakeApi.new()
	app.add_child(api)
	app.api = api
	app.identity_loading = false
	await _settle()
	for label: String in ["Play Solo", "Replays", "Settings"]:
		app._show_home()
		await _settle()
		var button := _home_button(app, label)
		_check(button != null, "Home shows " + label)
		if button == null: continue
		var count := [0]
		button.pressed.connect(func(): count[0] += 1)
		await _tap(viewport, button.get_global_rect().get_center(), WOBBLES[4])
		_check(count[0] == 1 and app.mode != "home", "A wobbling tap on Home's %s acts once" % label)
	# Play Solo: the store reports on every launch and resume, mostly with
	# nothing new. A card under a finger must survive that report.
	app.journey_flow.show_journey()
	await _settle()
	await _settle()
	var picker: ScrollContainer = app.journey_flow.picker
	var open: Button = null
	if picker != null:
		open = (picker.grid.get_child(0) as Control).find_child("ChapterOpen", true, false) as Button
		if picker.chosen.is_connected(app.journey_flow.open_solo_chapter): picker.chosen.disconnect(app.journey_flow.open_solo_chapter)
	_check(open != null, "Play Solo shows a chapter card")
	if open != null:
		var opens := [0]
		open.pressed.connect(func(): opens[0] += 1)
		var at := open.get_global_rect().get_center()
		_touch(viewport, at, true)
		_move(viewport, at + Vector2(1, 2), Vector2(1, 2))
		app._customer_info_changed({})
		await _settle()
		_check(is_instance_valid(open) and open.is_inside_tree() and open.is_pressed(), "A store report with no change in access keeps the Play Solo cards")
		_touch(viewport, at + Vector2(1, 2), false)
		await _settle()
		_check(opens[0] == 1, "The chapter card tapped during the store report opens once")
	app._show_home()
	await _settle()
	viewport.queue_free()
	await _settle()
	await create_timer(0.15).timeout
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)


## Home > Replays > Back > Play with your friend while a finished room's replay
## save still holds the room session (it runs after Watch replay or after that
## room's play, and outlives the Replays screen). The first tap registers at
## once, its button saying so, and the hub opens when the save ends with no
## second tap, whether the tap came at once or a moment later. A save that
## outlasts the wait says why. Before, the tap did nothing and said nothing.
func _home_after_replays() -> void:
	for delay_s: float in [0.0, 0.4, -1.0]:
		var case := "at once" if delay_s == 0.0 else ("after a moment" if delay_s > 0.0 else "past the wait")
		var path := "user://tap-replays-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
		var storage := Storage.new(path)
		storage.data.settings.sound = false
		storage.data.settings.haptics = false
		_check(storage.flush(), "Prepare an isolated muted save")
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1280, 720)
		viewport.handle_input_locally = true
		root.add_child(viewport)
		var app := Main.new()
		app.saves = storage
		viewport.add_child(app)
		app.set_process(false)
		app.set_physics_process(false)
		app.api.queue_free()
		var api := HeldApi.new()
		app.add_child(api)
		app.api = api
		app.identity_read_state = Main.IdentityReadState.LOADED
		app.identity_data = {"player_id": api.player_id, "device_token": api.device_token}
		app.identity_loading = false
		app.relay_session = Session.new(api, app._relay_identity, SessionStore.new())
		await _settle()
		app._show_home()
		await _settle()
		api.hold = true
		app.replays_flow.save_finished_replay("RRRRRRRRRRRRRRRRRRRRRR")
		await _settle()
		_check(app.relay_session.busy(), "A finished room's replay save holds the room session (%s)" % case)
		var replays := _home_button(app, "Replays")
		if replays != null: await _tap(viewport, replays.get_global_rect().get_center(), WOBBLES[1])
		_check(app.mode == "collection", "Home's Replays opens Replays (%s): %s" % [case, app.mode])
		var back := _home_button(app, "Back")
		if back != null: await _tap(viewport, back.get_global_rect().get_center(), WOBBLES[1])
		_check(app.mode == "home", "Back from Replays goes Home (%s): %s" % [case, app.mode])
		if delay_s > 0.0: await create_timer(delay_s).timeout
		if delay_s < 0.0:
			app.room_hub_flow._gate = BusyTapGate.new(app.overlay)
			app.room_hub_flow._gate.wait_ms = 300
		app.toast.visible = false
		var play := _home_button(app, "Play with your friend")
		_check(play != null, "Home shows Play with your friend (%s)" % case)
		if play == null:
			viewport.queue_free()
			await _settle()
			continue
		await _tap(viewport, play.get_global_rect().get_center(), WOBBLES[2])
		_check(app.mode == "home" and play.text == PlayerCopy.HUB_OPENING, "The first tap registers while the save runs: Play with your friend reads Opening… (%s): %s / %s" % [case, play.text, app.mode])
		if delay_s < 0.0:
			await create_timer(0.6).timeout
			_check(app.mode == "home" and not app.room_hub_flow.is_open() and app.toast.visible and app.toast.text == PlayerCopy.ROOMS_API_DA75E6F7A674, "A save that outlasts the wait says why: " + app.toast.text)
			_check(play.text == "Play with your friend", "The button reads as usual again")
		api.hold = false
		api.release.emit()
		for _frame: int in range(8): await process_frame
		if delay_s >= 0.0:
			_check(app.mode == "rooms" and app.room_hub_flow.is_open(), "The hub opens when the save ends, with no second tap (%s): %s" % [case, app.mode])
		app.room_hub_flow.drop()
		viewport.queue_free()
		await _settle()
		await create_timer(0.15).timeout
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)


func _home_button(app: Node, label: String) -> Button:
	for button: Button in app.overlay.find_children("*", "Button", true, false):
		if button.text == label or button.tooltip_text == label: return button
	return null


## A finger tap at `at` that wobbles through `wobble` before lifting.
func _tap(target: Viewport, at: Vector2, wobble: Array = []) -> void:
	_touch(target, at, true)
	var point := at
	for step: Vector2 in wobble:
		point += step
		_move(target, point, step)
	_touch(target, point, false)
	await _settle()


func _touch(target: Viewport, at: Vector2, pressed: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = at
	touch.pressed = pressed
	if target == root:
		Input.parse_input_event(touch)
		Input.flush_buffered_events()
		return
	# Inside a SubViewport: the engine's order, the emulated mouse then the touch.
	var mouse := InputEventMouseButton.new()
	mouse.position = at
	mouse.global_position = at
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	mouse.pressed = pressed
	target.push_input(mouse, true)
	target.push_input(touch, true)


func _move(target: Viewport, at: Vector2, relative: Vector2) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = at
	drag.relative = relative
	drag.velocity = relative * 60.0
	if target == root:
		Input.parse_input_event(drag)
		Input.flush_buffered_events()
		return
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.relative = relative
	motion.velocity = relative * 60.0
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	target.push_input(motion, true)
	target.push_input(drag, true)


func _rest(scroll: ScrollContainer) -> void:
	var last := -1
	var steady := 0
	for _frame: int in range(300):
		await process_frame
		if not is_instance_valid(scroll): return
		steady = steady + 1 if scroll.scroll_vertical == last else 0
		if steady >= 3: return
		last = scroll.scroll_vertical


func _settle() -> void:
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

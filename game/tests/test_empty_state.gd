extends SceneTree
## Empty-list art: it shows only while a list is empty and leaves with the
## first item, draws on layout changes and never on idle frames, stays cheap for
## the Friends page that rebuilds on each poll, fits its list at 1280x720 and at
## the 1600x720 logical size of small phones, and never covers the status lines
## placed with it. Stub clients only; no network.

const ControlTheme = preload("res://presentation/control_theme.gd")
const EmptyState = preload("res://presentation/empty_state.gd")
const Art = preload("res://presentation/empty_state_art.gd")
const Hub = preload("res://presentation/room_hub_screen.gd")
const Registry = preload("res://services/chapter_registry.gd")
const FriendsClient = preload("res://services/friends_client.gd")
const FriendsScreen = preload("res://presentation/friends_screen.gd")
const Nicknames = preload("res://services/friend_nicknames.gd")
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const FakeApi = preload("res://tests/fake_rooms_api.gd")
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"
const PEER := "dddddddddddddddddddddd"
## List areas measured on the real screens: room hub column, Friends list,
## Replays Together and Solo, each at 1280x720 and 1600x720.
const AREAS: Array[Vector2] = [Vector2(710, 566), Vector2(847, 566), Vector2(639, 367), Vector2(1236, 375), Vector2(1556, 380), Vector2(1236, 544), Vector2(1556, 544)]
const PlayerCopy = preload("res://presentation/player_copy.gd")

class Inbox extends RefCounted:
	var rooms: Array = []
	func view() -> Dictionary: return {"rooms": rooms, "stale": false, "error": ""}
	func unread(_room: Dictionary) -> bool: return false
	func confirm_room_rendered(_version: int, _id: String) -> bool: return false
	func refresh() -> bool: return true

class ApiStub extends Node:
	var base_url := "https://empty-state.invalid"
	var player_id := OWNER
	var device_token := "test-only"
	var busy := false

var checks := 0
var failures := 0
var friends: Array = []
var page_ready := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1600, 720)
	_island_walk()
	await _layouts()
	await _room_hub()
	await _friends()
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720)]: await _replays(viewport_size)
	print("AFTER YOU EMPTY STATE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _frames(count: int) -> void:
	for i in range(count): await process_frame

func _empties(node: Node) -> Array[Node]:
	return node.find_children("EmptyState", "", true, false).filter(func(found: Node) -> bool: return not found.is_queued_for_deletion())

func _layouts() -> void:
	for art: String in EmptyState.SPOTS:
		for area: Vector2 in AREAS:
			var context := "%s in %s" % [art, area]
			var scroll := ScrollContainer.new()
			scroll.size = area
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			root.add_child(scroll)
			var list := VBoxContainer.new()
			list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.add_child(list)
			var status := Label.new()
			status.text = "Saving replays…"
			list.add_child(status)
			var below: Button = null
			if art == "replays_together":
				below = Button.new()
				below.text = "Refresh shared rooms"
				below.custom_minimum_size.y = 52
			var empty: Control = ControlTheme.empty_state(list, art, PlayerCopy.EMPTY_ROOMS_TITLE, PlayerCopy.EMPTY_ROOMS_TEXT, below)
			await _frames(3)
			var box := empty.get_global_rect()
			var geo: Dictionary = empty._layout()
			_check(scroll.get_v_scroll_bar().max_value <= scroll.size.y + 0.5, context + ": the art never makes the empty list scroll")
			_check(box.size.y >= area.y - status.size.y - 12.0, context + ": the art takes the list's blank space")
			_check(not status.get_global_rect().intersects(box), context + ": the status line stays clear of the art")
			var texts: Array[Control] = [empty.title, empty.line]
			if below != null: texts.append(below)
			_check(below == null or below.get_parent() == empty, context + ": the screen's own button moves under the text")
			var art_rects: Array[Rect2] = []
			for card: Rect2 in geo.cards: art_rects.append(Rect2(card.position + box.position, card.size))
			if geo.has("picture"): art_rects.append(Rect2(geo.picture.position + box.position, geo.picture.size))
			_check(geo.cards.size() >= EmptyState.SPOTS[art].get("rows", []).size(), context + ": every row with a scene is shown")
			for index: int in range(texts.size()):
				var rect := texts[index].get_global_rect()
				_check(rect.size.y > 0 and box.grow(0.5).encloses(rect), context + ": text stays inside the art's box: " + texts[index].name)
				for other: int in range(index + 1, texts.size()):
					_check(not rect.intersects(texts[other].get_global_rect()), context + ": text lines never overlap")
				for art_rect: Rect2 in art_rects:
					_check(not rect.intersects(art_rect), context + ": text never sits on a ghost card or picture")
			_check(empty.mouse_filter == Control.MOUSE_FILTER_IGNORE and empty.title.mouse_filter == Control.MOUSE_FILTER_IGNORE, context + ": taps pass through to the list")
			var drawn: int = empty.draw_count
			_check(drawn >= 1, context + ": the art was drawn")
			await _frames(30)
			_check(empty.draw_count == drawn, context + ": idle frames draw nothing (%d -> %d)" % [drawn, empty.draw_count])
			scroll.size = area - Vector2(40, 0)
			await _frames(2)
			_check(empty.draw_count > drawn, context + ": a resize redraws the art")
			scroll.free()

func _room_hub() -> void:
	root.size = Vector2i(1280, 720)
	var key: String = Registry.keys()[0]
	var chapters: Array[Dictionary] = [{"key": key, "title": str(Registry.descriptor(key).title), "stage_count": 2}]
	var inbox := Inbox.new()
	var hub := Hub.new()
	hub.client = inbox
	hub.set_chapters(chapters)
	hub.display_name = func(_member: String) -> String: return ""
	root.add_child(hub)
	await _frames(3)
	hub.refresh()
	await _frames(3)
	var found := _empties(hub._rooms_list)
	_check(found.size() == 1 and found[0].art == "rooms", "Your rooms with no rooms shows the rooms art once")
	hub._select_tab("Completed")
	await _frames(3)
	found = _empties(hub._rooms_list)
	_check(found.size() == 1 and found[0].art == "rooms_completed", "Completed with no rooms shows its own art")
	hub._select_tab("Your rooms")
	inbox.rooms.append({"api_version": 2, "room_id": "room-a", "chapter_key": key, "chapter_title": "A journey", "member_ids": ["me", "friend"], "status": "your_turn", "part": 1, "stage_count": 2})
	hub._render()
	await _frames(3)
	_check(_empties(hub._rooms_list).is_empty() and hub.room_action("room-a") != null, "The first room replaces the art with its card")
	hub.queue_free()
	await _frames(2)

func _friends() -> void:
	var api := ApiStub.new()
	root.add_child(api)
	var client := FriendsClient.new(api, func() -> Dictionary: return {"ready": true, "player_id": OWNER, "epoch": 1}, func(method: int, path: String, _body: Dictionary) -> Dictionary:
		if method == HTTPClient.METHOD_GET and path == "/v1/friends":
			if not page_ready: return {"ok": false, "error": "offline"}
			return {"ok": true, "data": {"schema_version": 1, "friend_code": OWNER, "refresh_after_seconds": 30, "shared_room": null, "friends": friends.duplicate(true)}}
		return {"ok": true, "data": {}})
	var screen := FriendsScreen.new()
	screen.client = client
	screen.nickname_store = Nicknames.new("user://empty-state-nicks-%d.json" % Time.get_ticks_usec())
	root.add_child(screen)
	await _frames(2)
	screen._render()
	await _frames(2)
	_check(client.view().is_empty() and _empties(screen).is_empty(), "Before the first page loads Friends shows Refreshing, not the art")
	page_ready = true
	await _reload(client, screen)
	await _frames(3)
	var found := _empties(screen)
	_check(found.size() == 1 and found[0].art == "friends", "A loaded page with no friends shows the friends art once")
	# The page is rebuilt on each poll that changes it; the art must not add to that.
	var started := Time.get_ticks_usec()
	for i in range(200):
		var holder := VBoxContainer.new()
		ControlTheme.empty_state(holder, "friends", "No friends yet", "Share your friend code and they show up here.")
		holder.free()
	var each := (Time.get_ticks_usec() - started) / 200.0
	_check(each < 500.0, "Building and freeing the art costs %.0f us, well under a frame" % each)
	started = Time.get_ticks_usec()
	for i in range(20): screen._render()
	await _frames(1)
	print("NOTE friends render with art: %.0f us each" % ((Time.get_ticks_usec() - started) / 20.0))
	friends.append({"player_id": PEER, "request_id": "eeeeeeeeeeeeeeeeeeeeee", "status": "incoming", "online": false, "expires_after_seconds": 0, "join_available": false})
	await _reload(client, screen)
	_check(_empties(screen).is_empty(), "The first friend (a request) replaces the art")
	screen.queue_free()
	api.queue_free()
	await _frames(2)

func _reload(client: RefCounted, screen: Node) -> void:
	for i in range(30):
		if not client.busy: break
		await process_frame
	client._next_refresh = 0
	client._next_manual_refresh = 0
	client._retry_until = 0
	await client.refresh(true)
	screen._render()
	await _frames(3)

## The Solo scene's spirit, memory and footprints all stand on the block's top face.
func _island_walk() -> void:
	for row: Array in Art.SCENES.footprints:
		if row[0] != "walk": continue
		var top := Art.block_top(row[1])
		var points := Art.walk_points(row[1], row[2])
		for key: String in ["you", "memory"]:
			var reach: float = Art.FOOT_REACH * (Art.WALKER_SIZE if key == "you" else Art.MEMORY_SIZE)
			for offset: Vector2 in [Vector2.ZERO, Vector2(-reach, 0), Vector2(reach, 0)]:
				_check(Geometry2D.is_point_in_polygon(points[key] + offset, top), "The %s stands with both feet on the island's top face" % key)
		for step: Vector2 in points.steps:
			for side: float in [-3.0, 3.0]:
				_check(Geometry2D.is_point_in_polygon(step + Vector2(0, side), top), "Every footprint lies on the island's top face")

func _replays(viewport_size: Vector2i) -> void:
	var context := " at " + str(viewport_size)
	var path := "user://empty-state-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var storage := Storage.new(path)
	storage.data.settings.sound = false
	var viewport := SubViewport.new()
	viewport.size = viewport_size
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
	await _frames(3)
	app.replays_flow.show_collection()
	for i in range(600):
		await process_frame
		if app.replays_flow.solo_replays != null and not app.replays_flow.solo_replays.scan_pending(): break
	app.replays_flow.show_collection()
	await _frames(3)
	var found := _empties(app.overlay)
	_check(found.size() == 1 and found[0].art == "replays_solo" and found[0].line.text == PlayerCopy.EMPTY_SOLO_TEXT, "Solo with nothing saved shows the solo art" + context)
	if found.size() == 1:
		_check(found[0].size.x >= EmptyState.SIDE_MIN_WIDTH and found[0]._layout().has("panel"), "The wide Replays page puts the scene and text in the preview card's place" + context)
		_check(app.ui.get_global_rect().grow(0.5).encloses(found[0].get_global_rect()), "The solo art stays on screen" + context)
	api.player_id = OWNER
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.replays_flow.show_shared_replays()
	for i in range(600):
		await process_frame
		if app.shared_replays != null and not app.shared_replays.local_loading(): break
	app.replays_flow._draw_shared_replay_empty("Saving replays…")
	await _frames(3)
	found = _empties(app.overlay)
	_check(found.size() == 1 and found[0].art == "replays_together", "Together with nothing saved shows the together art" + context)
	var status: Label = null
	var refresh: Button = null
	for label: Label in app.overlay.find_children("*", "Label", true, false):
		if label.text == "Saving replays…": status = label
	for button: Button in app.overlay.find_children("*", "Button", true, false):
		if button.text == "Refresh shared rooms": refresh = button
	if found.size() == 1 and status != null and refresh != null:
		var art: Rect2 = found[0].get_global_rect()
		_check(not art.intersects(status.get_global_rect()) and refresh.get_parent() == found[0], "The saving line stays clear of the art, and Refresh sits by the text" + context)
		_check(app.ui.get_global_rect().grow(0.5).encloses(art), "The together art stays on screen" + context)
	else:
		_check(false, "The saving line, Refresh and the art are all present" + context)
	viewport.queue_free()
	await _frames(2)
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + description)

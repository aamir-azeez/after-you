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

## Long enough to wrap to two or three lines, as a translation might.
const LONG_TEXT := "Host a room and it waits here for your friend, who can join from their own list of rooms whenever they are ready."

class Inbox extends RefCounted:
	var rooms: Array = []
	var stale := false
	var error := ""
	var hidden: Array = []
	func view() -> Dictionary: return {"rooms": rooms, "stale": stale, "error": error}
	func hidden_rooms() -> Array: return hidden
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
	await _duel_columns()
	await _room_hub()
	await _friends()
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720)]: await _replays(viewport_size)
	print("AFTER YOU EMPTY STATE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _frames(count: int) -> void:
	for i in range(count): await process_frame

func _empties(node: Node) -> Array[Node]:
	return node.find_children("EmptyState", "", true, false).filter(func(found: Node) -> bool: return not found.is_queued_for_deletion())

## The Duels lobby's two empty lists at 1280x720: Open duels, a narrow column
## above the Race a recorded run card, and Your duels beside it. Every version
## the owner may pick fits its list whole, with no scroll and no card cut off.
const OPEN_AREA := Vector2(352, 290)
const YOURS_AREA := Vector2(814, 420)
const OPEN_ARTS := ["open_a", "open_b", "open_c"]
const YOURS_ARTS := ["duels_f"]

func _duel_columns() -> void:
	for art: String in OPEN_ARTS + YOURS_ARTS:
		_check(EmptyState.SPOTS.has(art), "the Duels lobby's %s art exists" % art)
		if not EmptyState.SPOTS.has(art): continue
		var narrow := art in OPEN_ARTS
		_check(not narrow or EmptyState.SPOTS[art].card == "friend", "%s draws the narrow round card the column has room for" % art)
		var scroll := ScrollContainer.new()
		scroll.size = OPEN_AREA if narrow else YOURS_AREA
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		root.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)
		var empty: Control = ControlTheme.empty_state(list, art, "" if narrow else PlayerCopy.DUELS_EMPTY_TITLE, PlayerCopy.DUELS_OPEN_EMPTY_B if narrow else PlayerCopy.DUELS_NO_DUELS)
		await _frames(3)
		_check(empty.get_combined_minimum_size().y <= scroll.size.y + 0.5 and scroll.get_v_scroll_bar().max_value <= scroll.size.y + 0.5, "%s fits its column without a scroll: %s" % [art, empty.get_combined_minimum_size()])
		var geo: Dictionary = empty._layout()
		for card: Rect2 in geo.cards: _check(card.end.x <= scroll.size.x + 0.5, "%s keeps its cards inside the column" % art)
		_check(empty.line.get_global_rect().end.y <= scroll.get_global_rect().end.y + 0.5, "%s keeps its line above whatever sits under the column" % art)
		scroll.queue_free()
		await process_frame

func _layouts() -> void:
	for art: String in EmptyState.SPOTS:
		for case: int in range(AREAS.size() * 2):
			var area := AREAS[case % AREAS.size()]
			var text := PlayerCopy.EMPTY_ROOMS_TEXT if case < AREAS.size() else LONG_TEXT
			# Replays is the only list with a wide layout, from 1000 px (REPLAY_SPLIT_MIN_WIDTH).
			var wide: bool = Art.CARDS[EmptyState.SPOTS[art].card].get("preview", false) and area.x >= 956.0
			var context := "%s in %s%s" % [art, area, " (long text)" if case >= AREAS.size() else ""]
			var scroll := ScrollContainer.new()
			scroll.size = area
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			root.add_child(scroll)
			var list := VBoxContainer.new()
			list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			list.size_flags_vertical = Control.SIZE_EXPAND_FILL
			scroll.add_child(list)
			var status := Label.new()
			status.text = "Saving replays…"
			list.add_child(status)
			var below: Button = null
			if art == "replays_together":
				below = Button.new()
				below.text = "Refresh shared rooms"
				below.custom_minimum_size.y = 52
			var empty: Control = ControlTheme.empty_state(list, art, PlayerCopy.EMPTY_ROOMS_TITLE, text, below, wide)
			await _frames(3)
			var box := empty.get_global_rect()
			var geo: Dictionary = empty._layout()
			# The owner's text never makes the list scroll; a much longer line may,
			# but it is never cut off (checked below).
			if case < AREAS.size(): _check(scroll.get_v_scroll_bar().max_value <= scroll.size.y + 0.5, context + ": the art never makes the empty list scroll")
			_check(box.size.y >= area.y - status.size.y - 12.0, context + ": the art takes the list's blank space")
			_check(not status.get_global_rect().intersects(box), context + ": the status line stays clear of the art")
			var texts: Array[Control] = [empty.title, empty.line]
			if below != null: texts.append(below)
			_check(below == null or below.get_parent() == empty, context + ": the screen's own button moves under the text")
			var art_rects: Array[Rect2] = []
			for card: Rect2 in geo.cards: art_rects.append(Rect2(card.position + box.position, card.size))
			if geo.has("picture"):
				art_rects.append(Rect2(geo.picture.position + box.position, geo.picture.size))
				var inner: Rect2 = geo.panel.grow(-16.0)
				art_rects.append(Rect2(inner.position.x + box.position.x, inner.end.y - 50.0 + box.position.y, inner.size.x, 50.0))
			_check(geo.has("panel") == (wide and EmptyState.SPOTS[art].has("preview")), context + ": the preview card shows only in the screen's wide layout")
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
	inbox.stale = true
	var hub := Hub.new()
	hub.client = inbox
	hub.set_chapters(chapters)
	hub.display_name = func(_member: String) -> String: return ""
	root.add_child(hub)
	await _frames(3)
	hub.refresh()
	await _frames(3)
	var found := _empties(hub._rooms_list)
	_check(found.size() == 1 and not found[0].title.visible and found[0].line.visible and found[0].line.text == PlayerCopy.EMPTY_ROOMS_LOADING, "Before the first fetch the art says the rooms are loading, never that there are none")
	inbox.error = "Rooms unavailable"
	hub._render()
	await _frames(3)
	found = _empties(hub._rooms_list)
	_check(found.size() == 1 and not found[0].title.visible and not found[0].line.visible and "Rooms unavailable" in hub._notice.text, "Offline the art stays without a line, under the notice that says why")
	# Saved rooms shown while no fetch can run: the notice says so, and an empty
	# tab's art adds no line of its own (not "Loading", not "No rooms yet").
	inbox.error = ""
	inbox.rooms.append({"api_version": 2, "room_id": "room-saved", "chapter_key": key, "chapter_title": "A journey", "member_ids": ["me", "friend"], "status": "your_turn", "part": 1, "stage_count": 2})
	hub._select_tab("Completed")
	await _frames(3)
	found = _empties(hub._rooms_list)
	_check(found.size() == 1 and not found[0].title.visible and not found[0].line.visible and "Displaying saved rooms when offline" in hub._notice.text, "With saved rooms shown offline an empty tab's art has no line under the notice")
	inbox.rooms.clear()
	hub._select_tab("Your rooms")
	inbox.stale = false
	hub._render()
	await _frames(3)
	found = _empties(hub._rooms_list)
	_check(found.size() == 1 and found[0].art == "rooms" and found[0].title.visible and found[0].title.text == PlayerCopy.EMPTY_ROOMS_TITLE, "Once the list has loaded with no rooms, the art says there are none yet")
	hub._select_tab("Completed")
	await _frames(3)
	found = _empties(hub._rooms_list)
	_check(found.size() == 1 and found[0].art == "rooms_completed", "Completed with no rooms shows its own art")
	inbox.hidden = [{"api_version": 2, "room_id": "room-hidden", "chapter_key": key, "chapter_title": "A journey", "member_ids": ["me", "friend"], "status": "completed", "part": 1, "stage_count": 2}]
	hub._render()
	await _frames(3)
	_check(_empties(hub._rooms_list).is_empty() and hub._rooms_list.find_child("HiddenRoomsFold", true, false) != null, "Completed with only hidden rooms shows their section, not art saying nothing is finished")
	inbox.hidden = []
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
		_check(found[0].title.visible and found[0].title.text == PlayerCopy.EMPTY_SOLO_TITLE, "A finished scan that found nothing says there are no replays yet" + context)
		_check(found[0].wide and found[0]._layout().has("panel"), "The wide Replays page puts the scene and text in the preview card's place" + context)
		_check(app.ui.get_global_rect().grow(0.5).encloses(found[0].get_global_rect()), "The solo art stays on screen" + context)
	# A scan that could check nothing: replays may exist, so the art's line is
	# that error, shown once, and never "No replays yet".
	app.replays_flow.solo_replays.last_error = "Saved replays could not be checked."
	app.replays_flow.show_collection()
	await _frames(3)
	found = _empties(app.overlay)
	_check(found.size() == 1 and not found[0].title.visible and found[0].line.text == "Saved replays could not be checked." and _labels(app.overlay, "Saved replays could not be checked.") == 1 and _label(app.overlay, PlayerCopy.EMPTY_SOLO_TEXT) == null, "When nothing could be checked Solo's art carries the error instead of 'No replays yet'" + context)
	app.replays_flow.solo_replays.last_error = ""
	api.player_id = OWNER
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.replays_flow.show_shared_replays()
	for i in range(600):
		await process_frame
		if app.shared_replays != null and not app.shared_replays.local_loading(): break
	# A refresh starting, or a finished room still being saved: the art stays,
	# its line is that status, and it never says nothing is saved.
	for step: Array in [[PlayerCopy.MAIN_2CEDB8F94036, false, ""], ["Saving replays…", true, "chapter:" + PEER]]:
		app.replays_flow._shared_wanted_room = step[2]
		app.replays_flow._draw_shared_replay_empty(step[0], step[1])
		await _frames(3)
		found = _empties(app.overlay)
		var busy_refresh := _button(app.overlay, "Refresh shared rooms")
		_check(found.size() == 1 and not found[0].title.visible and found[0].line.text == step[0] and busy_refresh != null and busy_refresh.get_parent() == found[0], "While busy Together keeps the art with its status line and Refresh, and no 'nothing saved' title: " + step[0] + context)
		_check(_label(app.overlay, PlayerCopy.EMPTY_TOGETHER_TEXT) == null and _labels(app.overlay, step[0]) == 1, "The status shows once and the nothing-saved line not at all: " + step[0] + context)
	# A save that failed leaves nothing pending: the art comes back under its error.
	app.replays_flow._shared_wanted_room = ""
	app.replays_flow._draw_shared_replay_empty("Could not save replays")
	await _frames(3)
	found = _empties(app.overlay)
	var status := _label(app.overlay, "Could not save replays")
	var refresh := _button(app.overlay, "Refresh shared rooms")
	_check(found.size() == 1 and found[0].art == "replays_together" and status != null and refresh != null, "With nothing saved and nothing pending Together shows the together art" + context)
	if found.size() == 1 and status != null and refresh != null:
		var art: Rect2 = found[0].get_global_rect()
		_check(not art.intersects(status.get_global_rect()) and refresh.get_parent() == found[0], "The error line stays clear of the art, and Refresh sits by the text" + context)
		_check(app.ui.get_global_rect().grow(0.5).encloses(art), "The together art stays on screen" + context)
	viewport.queue_free()
	await _frames(2)
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func _label(node: Node, text: String) -> Label:
	for label: Label in node.find_children("*", "Label", true, false):
		if label.text == text: return label
	return null

func _labels(node: Node, text: String) -> int:
	return node.find_children("*", "Label", true, false).filter(func(label: Node) -> bool: return (label as Label).text == text and (label as Label).is_visible_in_tree()).size()

func _button(node: Node, text: String) -> Button:
	for button: Button in node.find_children("*", "Button", true, false):
		if button.text == text and not button.is_queued_for_deletion(): return button
	return null

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + description)

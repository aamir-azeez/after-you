extends SceneTree

const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const Levels = preload("res://core/levels.gd")
const Catalog = preload("res://services/licenses.gd")
const FakeApi = preload("res://tests/fake_rooms_api.gd")
const Shared = preload("res://services/shared_replay_collection.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const SHARED_ROOM := "RRRRRRRRRRRRRRRRRRRRRR"

class Memory extends RefCounted:
	var values: Dictionary = {}
	func load_scope(scope: String) -> Dictionary:
		return {"ok": true, "found": values.has(scope), "value": values.get(scope, {}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> bool:
		values[scope] = value.duplicate(true)
		return true

var checks := 0
var failures := 0
var gesture_skips := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := "user://scroll-lists-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var storage := Storage.new(path)
	storage.data.settings.sound = false
	storage.data.settings.haptics = false
	_check(storage.flush(), "Prepare an isolated muted save")
	var saved_bytes := FileAccess.get_file_as_string(path)
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
	app.identity_read_state = Main.IdentityReadState.UNCHECKED
	var before_identity := api.calls.size()
	app._show_shared_replays()
	_check(api.calls.size() == before_identity and app.shared_replays == null, "An unverified identity cannot load or refresh a shared collection")
	api.player_id = OWNER
	app.identity_read_state = Main.IdentityReadState.LOADED
	_check(app._relay_identity().ready, "Shared-list fixture uses an explicitly loaded owner and device binding")
	var original_touch_emulation := Input.emulate_touch_from_mouse
	# In Godot 4.7.2, base DisplayServer::is_touchscreen_available() uses this
	# supported Input flag, and Headless does not override it. This activates
	# ScrollContainer's real native drag logic; no control methods/signals are
	# called directly to simulate scrolling. Android finger input remains a
	# separate integration check of the platform's touch-to-mouse event stream.
	Input.emulate_touch_from_mouse = true
	var can_drag := DisplayServer.is_touchscreen_available()
	if not can_drag:
		gesture_skips += 1
		print("SCROLL GESTURE SKIPPED: this DisplayServer does not expose touch emulation; Android drag verification is still required")
	await _input_route(app, viewport, can_drag)
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720)]:
		viewport.size = size
		await _settle()
		await _screens(app, viewport, api, can_drag)
	Input.emulate_touch_from_mouse = original_touch_emulation
	_check(Input.emulate_touch_from_mouse == original_touch_emulation, "Restore the process input setting")
	_check(FileAccess.get_file_as_string(path) == saved_bytes, "List inspection and gestures never modify the isolated save on disk")
	for request: Dictionary in api.calls:
		_check(request.method == HTTPClient.METHOD_GET and request.body.is_empty(), "Only synthetic read requests reach the fake API")
	_check(api.calls.size() == 16 and api.responses.is_empty(), "Exactly eight explicit list/collection GETs run per viewport size without leaving queued responses")
	viewport.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU SCROLL LISTS: %d checks, %d failures, %d gesture skips" % [checks, failures, gesture_skips])
	# Missing gesture coverage is incomplete validation, not a passing suite.
	quit(1 if failures > 0 or gesture_skips > 0 else 0)


func _input_route(app: Node, viewport: SubViewport, can_drag: bool) -> void:
	var card: VBoxContainer = app._card(700)
	var list: VBoxContainer = app._scroll_list(card)
	var scroll := list.get_parent() as ScrollContainer
	var activations := [0]
	var received := {"presses": 0, "motions": 0, "starts": 0}
	scroll.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			received.presses += 1
		if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			received.motions += 1)
	scroll.scroll_started.connect(func(): received.starts += 1)
	for index: int in range(8):
		list.add_child(app._list_button("Synthetic action %d" % (index + 1), func(): activations[0] += 1, false))
	await _settle()
	var rows := _rows(scroll)
	_check(rows.size() == 8, "The input fixture uses eight actual application list buttons")
	if rows.size() != 8:
		return
	var point := rows[0].get_global_rect().get_center()
	_pointer(viewport, point, true)
	_pointer(viewport, point, false)
	_check(activations[0] == 1, "A real viewport press/release invokes the row callback exactly once")
	_check(received.presses == 1, "A row press bubbles through its containers to ScrollContainer")
	if can_drag:
		await _drag(viewport, rows[2].get_global_rect().get_center(), Vector2(0, -130))
		_check(received.motions > 0 and received.starts == 1, "Dragging a row reaches the native scroll gesture and emits one scroll_started")
		_check(scroll.scroll_vertical > 0, "Dragging a row moves the actual ScrollContainer")
		_check(activations[0] == 1, "Native scroll cancellation prevents the drag from activating a row")
		# Negative control: recreating the former STOP setting must block the
		# same viewport route. This guards against a test that bypasses buttons.
		scroll.scroll_vertical = 0
		await _settle()
		var blocker: Button = rows[2]
		blocker.mouse_filter = Control.MOUSE_FILTER_STOP
		var previous_starts: int = received.starts
		var previous_presses: int = received.presses
		await _drag(viewport, blocker.get_global_rect().get_center(), Vector2(0, -130))
		_check(received.presses == previous_presses and received.starts == previous_starts and scroll.scroll_vertical == 0,
			"The former STOP filter reproduces the blocked row gesture through the same viewport")
		blocker.mouse_filter = Control.MOUSE_FILTER_PASS
	# Taps after scrolling still reach each callback once, including the last
	# row. This uses real pointer routing rather than emitting pressed.
	var before_taps: int = activations[0]
	for row: Button in rows:
		scroll.ensure_control_visible(row)
		await _settle()
		point = row.get_global_rect().get_center()
		_pointer(viewport, point, true)
		_pointer(viewport, point, false)
	_check(activations[0] == before_taps + 8, "Every row remains tappable exactly once after scrolling")


func _screens(app: Node, viewport: SubViewport, api: Node, can_drag: bool) -> void:
	var titles: Array[String] = []
	var empty_titles: Array[String] = []
	var rooms: Array[Dictionary] = []
	var replays := {}
	# These dictionaries are layout data only. They are never passed to replay
	# simulation or counted as gameplay/recording-validity evidence.
	for index: int in range(8):
		var level: Dictionary = Levels.get_level(index)
		titles.append(level.title)
		rooms.append({"room_id": "synthetic-list-%d" % index, "level_id": level.id, "active_role": "complete"})
		replays[level.id] = {"b": {"layout_fixture": true}}
	app.saves.data.room = {"room_id": "synthetic-collection"}
	app.saves.data.attempts = {}
	app.saves.data.replays = {}
	app._show_collection()
	await _inspect(app, viewport, empty_titles, "Complete your first island", "Back", "Empty solo collection", can_drag)
	app.saves.data.replays = replays
	app._show_collection()
	await _inspect(app, viewport, titles, "", "Back", "Eight-island solo collection", can_drag)
	for count: int in [0, 8]:
		api.responses.append({"ok": true, "data": {"rooms": rooms if count else []}})
		await app._show_saved_rooms()
		var expected: Array[String] = []
		if count:
			for title: String in titles:
				expected.append(title + " · Ready to replay")
		await _inspect(app, viewport, expected, "Create an island room" if not count else "", "Back", "Saved rooms %d" % count, can_drag)
		_check(api.responses.is_empty(), "Saved-room request consumes only its own fixture")
		await _shared_screens(app, viewport, api, count, can_drag)
	var license_titles: Array[String] = []
	for entry: Dictionary in Catalog.entries():
		license_titles.append(entry.title)
	app._show_licenses()
	await _inspect(app, viewport, license_titles, "", "Back to settings", "Bundled license catalog", can_drag)


func _shared_screens(app: Node, viewport: SubViewport, api: Node, count: int, can_drag: bool) -> void:
	# The collection now has separate room and memory menus and explicit refresh.
	# Its real verifier requires complete records, unlike the layout-only solo
	# fixture above. Eight historical attempts reuse an authentic First Light pair.
	var pair := {
		"a": JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-a.json")),
		"b": JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-b.json"))}
	var metadata := {"room_id": SHARED_ROOM, "host_id": OWNER, "guest_id": GUEST, "level_id": "first-light", "attempt": 0, "first_player_id": OWNER, "active_role": "a", "recordings": {}}
	var rooms: Array = []
	for index in range(count):
		var room := metadata.duplicate(true)
		room.room_id = SHARED_ROOM if index == 0 else "S" + str(index).pad_zeros(21)
		rooms.append(room)
	app.saves.data.room = {}
	app.shared_replays = Shared.new(api, app._relay_identity, Memory.new(), Memory.new())
	var before: int = api.calls.size()
	app._show_shared_replays()
	_check(api.calls.size() == before, "Opening Shared replays only reads owner-scoped local data")
	api.responses.append({"ok": true, "data": {"rooms": rooms}})
	api.responses.append({"ok": true, "data": {"rooms": []}})
	await app._refresh_shared_replay_rooms()
	var expected: Array[String] = []
	for index in range(count): expected.append("Earlier islands · Shared room " + str(index + 1))
	await _inspect(app, viewport, expected, PlayerCopy.MAIN_87534286A315 if not count else "", "Back", "Shared rooms %d" % count, can_drag)
	_check(api.calls.size() == before + 2 and api.responses.is_empty(), "Explicit shared-room refresh consumes one legacy and one chapter response")
	if count == 0:
		_check(app.shared_replays._remember_room(metadata, "legacy"), "Empty-memory case has a valid participant-owned room")
	app._show_shared_replay_room("legacy:" + SHARED_ROOM)
	var islands: Array = []
	for index in range(count):
		var island := metadata.duplicate(true)
		island.attempt = index
		island.active_role = "complete"
		island.recordings = pair.duplicate(true)
		islands.append(island)
	api.responses.append({"ok": true, "data": {"islands": islands}})
	await app._refresh_shared_replay_memories()
	expected.clear()
	for index in range(count): expected.append("First Light · On this device")
	await _inspect(app, viewport, expected, "No completed stages" if not count else "", "Back to shared rooms", "Shared memories %d" % count, can_drag)
	_check(api.calls.size() == before + 3 and api.responses.is_empty(), "Memory refresh consumes only the selected room's response")
	_check(app.shared_replays.memories("legacy:" + SHARED_ROOM).size() == count, "Every displayed shared row came through actual replay verification")


func _inspect(app: Node, viewport: SubViewport, expected: Array[String], empty_text: String, back_text: String, context: String, can_drag: bool) -> void:
	await _settle()
	context += " at " + str(viewport.size)
	var lists: Array[Node] = app.overlay.find_children("*", "ScrollContainer", true, false)
	_check(lists.size() == 1, context + " has exactly one bounded scrolling list")
	if lists.size() != 1:
		return
	var scroll := lists[0] as ScrollContainer
	var area := Rect2(Vector2.ZERO, Vector2(viewport.size))
	_check(area.grow(0.5).encloses(scroll.get_global_rect()), context + " list fits the viewport")
	var rows := _rows(scroll)
	var actual: Array[String] = []
	for row: Button in rows:
		actual.append(row.text)
		_check(row.mouse_filter == Control.MOUSE_FILTER_PASS, context + " row permits parent gesture handling")
	_check(actual == expected, context + " contains every expected row once in order")
	var back: Button = null
	for button: Button in app.overlay.find_children("*", "Button", true, false):
		if button.text == back_text:
			back = button
	_check(back != null and not scroll.is_ancestor_of(back) and area.grow(0.5).encloses(back.get_global_rect()), context + " keeps Back visible outside the list")
	if not empty_text.is_empty():
		var found_empty := false
		for label: Label in scroll.find_children("*", "Label", true, false):
			found_empty = found_empty or empty_text in label.text
		_check(found_empty, context + " explains the empty state inside the list")
		return
	_check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, context + " overflowing rows really scroll")
	if can_drag and rows.size() >= 3:
		# Exercise the real list, retaining callbacks. An accidental activation
		# destroys its overlay; validity/parent checks catch that without invoking
		# any deliberately seeded replay or synthetic room callback ourselves.
		var list_id := scroll.get_instance_id()
		await _drag(viewport, rows[2].get_global_rect().get_center(), Vector2(0, -130))
		var retained := is_instance_valid(scroll) and scroll.is_inside_tree() and scroll.get_instance_id() == list_id
		_check(retained, context + " drag does not launch a row or replace the current menu")
		if not retained:
			return
		_check(scroll.scroll_vertical > 0, context + " viewport drag scrolls over actual row controls")
	if not rows.is_empty():
		scroll.ensure_control_visible(rows[-1])
		await _settle()
		_check(scroll.get_global_rect().grow(0.5).encloses(rows[-1].get_global_rect()), context + " final row can be brought fully into view")


func _rows(scroll: ScrollContainer) -> Array[Button]:
	var result: Array[Button] = []
	for row: Button in scroll.find_children("*", "Button", true, false):
		result.append(row)
	return result


func _pointer(viewport: SubViewport, position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	viewport.push_input(event, true)


func _drag(viewport: SubViewport, start: Vector2, distance: Vector2) -> void:
	_pointer(viewport, start, true)
	for step: int in range(1, 9):
		var event := InputEventMouseMotion.new()
		event.position = start + distance * float(step) / 8.0
		event.global_position = event.position
		event.relative = distance / 8.0
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		viewport.push_input(event, true)
	_pointer(viewport, start + distance, false)
	await _settle()


func _settle() -> void:
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

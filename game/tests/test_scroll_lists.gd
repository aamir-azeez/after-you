extends SceneTree

const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const Levels = preload("res://core/levels.gd")
const Catalog = preload("res://services/licenses.gd")
const Chapters = preload("res://services/chapter_registry.gd")
const FakeApi = preload("res://tests/fake_rooms_api.gd")
const Shared = preload("res://services/shared_replay_collection.gd")
const OnlineSession = preload("res://services/relay_online_session.gd")
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

class LobbyMemory extends RefCounted:
	var values: Dictionary = {}
	func load_scope(scope: String) -> Dictionary:
		return {"ok":true,"found":values.has(scope),"value":values.get(scope,{}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		values[scope]=value.duplicate(true)
		return {"ok":true}

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
	app.relay_session=OnlineSession.new(api,app._relay_identity,LobbyMemory.new())
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
	viewport.size = Vector2i(960, 540)
	await _journey_rows(app, viewport, can_drag)
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720)]:
		viewport.size = size
		await _settle()
		await _screens(app, viewport, api, can_drag)
	Input.emulate_touch_from_mouse = original_touch_emulation
	_check(Input.emulate_touch_from_mouse == original_touch_emulation, "Restore the process input setting")
	_check(FileAccess.get_file_as_string(path) == saved_bytes, "List inspection and gestures never modify the isolated save on disk")
	for request: Dictionary in api.calls:
		_check(request.method == HTTPClient.METHOD_GET and request.body.is_empty(), "Only synthetic read requests reach the fake API")
	_check(api.calls.size() == 24 and api.responses.is_empty(), "Exactly twelve explicit list/collection GETs run per viewport size without leaving queued responses")
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
	await _inspect(app, viewport, empty_titles, "Finish your first island", "Back", "Empty solo collection", can_drag, [], false, true)
	app.saves.data.replays = replays
	app._show_collection()
	await _inspect(app, viewport, titles, "", "Back", "Eight-island solo collection", can_drag, [], false, true)
	for count: int in [0, 8]:
		api.responses.append({"ok":true,"data":{"api_version":2,"recording_version":2,"simulation_version":2,"mutations_enabled":true,"validation":"structural_client_replay_required","chapters":[]}})
		api.responses.append({"ok":true,"data":{"rooms":[]}})
		api.responses.append({"ok": true, "data": {"rooms": rooms if count else []}})
		await app._show_saved_rooms()
		var expected: Array[String] = []
		if count:
			for title: String in titles:
				expected.append(title + " · Ready to replay")
		await _inspect(app, viewport, expected, "No recent rooms" if not count else "", "Back", "Saved rooms %d" % count, can_drag)
		_check(api.responses.is_empty(), "Saved-room request consumes only its own fixture")
		await _shared_screens(app, viewport, api, count, can_drag)
	var license_titles: Array[String] = []
	for entry: Dictionary in Catalog.entries():
		license_titles.append(entry.title)
	app._show_licenses()
	await _inspect(app, viewport, license_titles, "", "Back to settings", "Bundled license catalog", can_drag)


func _journey_rows(app: Node, viewport: SubViewport, can_drag: bool) -> void:
	app._show_journey()
	await _settle()
	var lists: Array[Node] = app.overlay.find_children("*", "ScrollContainer", true, false)
	_check(lists.size() == 1, "Journey chapters use one bounded list at small landscape size")
	if lists.size() != 1: return
	var scroll := lists[0] as ScrollContainer
	# Earlier islands sits in the fixed tab row. Each chapter card, Lighthouse
	# included, is one whole-card tap target that opens it solo; it has no label.
	var cards: Array[Button] = []
	for button: Button in scroll.find_children("*", "Button", true, false):
		if button.has_meta("completion_chapter"): cards.append(button)
	_check(_rows(scroll).is_empty() and cards.size() == scroll.find_children("*", "Button", true, false).size(), "The chapter grid holds only whole-card targets, with no labelled buttons")
	_check(cards.size() == Chapters.keys().size() + 1, "Journey includes every chapter plus Lighthouse")
	var choices := {}
	for card: Button in cards:
		var choice := str(card.get_meta("completion_chapter", "")) + ":" + str(card.get_meta("completion_variant", ""))
		choices[choice] = int(choices.get(choice, 0)) + 1
	var overlay_labels: Array[String] = []
	for button: Button in app.overlay.find_children("*", "Button", true, false): overlay_labels.append(button.text)
	_check(overlay_labels.count("Story") == 0 and overlay_labels.count("Earlier islands") == 1, "Production omits Story and retains exactly one Earlier islands action")
	_check(choices.get("sleeping-lighthouse@1:solo", 0) == 1, "Journey retains the separate Lighthouse card")
	for key: String in Chapters.keys():
		_check(choices.get(key + ":solo", 0) == 1 and choices.get(key + ":friend", 0) == 0, "Each bundled chapter has exactly one solo card and no Together: " + key)
	_check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(scroll.get_global_rect()), "Journey list fits the small viewport")
	_check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, "The complete chapter chooser genuinely overflows its list")
	for card: Button in cards:
		var panel := card.get_parent() as Control
		_check(card.mouse_filter == Control.MOUSE_FILTER_PASS and panel.has_meta("chapter_key") and card.get_global_rect().is_equal_approx(panel.get_global_rect()), "Each card target fills its card and passes drags on: " + str(panel.name))
	if can_drag:
		# A drag may start on the picture or on the text; neither opens a chapter.
		for card: Button in cards:
			var panel := card.get_parent() as Control
			for part: String in ["LevelPicture", "LevelTitle"]:
				scroll.scroll_vertical = 0
				await _settle()
				scroll.ensure_control_visible(card)
				await _settle()
				_check(scroll.get_global_rect().grow(0.5).encloses(card.get_global_rect()), "Each chapter card is visible before dispatching its drag: " + str(panel.name))
				var previous := scroll.scroll_vertical
				var distance := Vector2(0, -110 if previous == 0 else 110)
				await _drag(viewport, (panel.find_child(part, true, false) as Control).get_global_rect().get_center(), distance)
				var retained: bool = is_instance_valid(scroll) and scroll.is_inside_tree() and app.mode == "journey" and app.relay_child == null
				_check(retained, "Dragging a chapter card leaves the real chapter menu open: " + part)
				if not retained: return
				_check(scroll.scroll_vertical != previous and card.get_draw_mode() != BaseButton.DRAW_PRESSED,"Each chapter card routes an actual viewport drag into native scrolling and drops its pressed look: " + part)
		# The peeking row is where a drag naturally starts. Pressing it must not
		# jump the list before the finger moves.
		scroll.scroll_vertical = 0
		await _settle()
		var peeking: Button = null
		for card: Button in cards:
			var rect := card.get_global_rect()
			if rect.intersects(scroll.get_global_rect()) and not scroll.get_global_rect().grow(0.5).encloses(rect): peeking = card
		_check(peeking != null, "A chapter card peeks below the visible rows")
		if peeking != null:
			var start := Vector2(peeking.get_global_rect().get_center().x, scroll.get_global_rect().end.y - 12.0)
			_pointer(viewport, start, true)
			await _settle()
			_check(scroll.scroll_vertical == 0, "Pressing a peeking card leaves the list where it was")
			for step: int in range(1, 9):
				var motion := InputEventMouseMotion.new()
				motion.position = start + Vector2(0, -15.0 * step)
				motion.global_position = motion.position
				motion.relative = Vector2(0, -15)
				motion.button_mask = MOUSE_BUTTON_MASK_LEFT
				viewport.push_input(motion, true)
			_pointer(viewport, start + Vector2(0, -120), false)
			await _settle()
			_check(app.mode == "journey" and app.relay_child == null and scroll.scroll_vertical > 0, "Dragging up from the peeking card scrolls without opening it")
	var earlier: Button
	for button: Button in app.overlay.find_children("*", "Button", true, false):
		if button.text == "Earlier islands": earlier = button
	_check(earlier != null, "Journey retains its direct Earlier islands action")
	if earlier != null:
		# The tab stays fixed above the grid, reachable at any scroll position.
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await _settle()
		_check(not scroll.is_ancestor_of(earlier) and not earlier.disabled and earlier.get_global_rect().end.y <= scroll.get_global_rect().position.y + 0.5 and Rect2(Vector2.ZERO,Vector2(viewport.size)).encloses(earlier.get_global_rect()), "The Earlier islands tab stays fully reachable above the scrolled chapter grid")
		var point := earlier.get_global_rect().get_center()
		_pointer(viewport,point,true)
		_pointer(viewport,point,false)
		await _settle()
		_check(app.mode == "earlier_islands" and app.relay_child == null, "A real viewport tap opens Earlier islands from the scrolled Journey list")


func _shared_screens(app: Node, viewport: SubViewport, api: Node, count: int, can_drag: bool) -> void:
	# Together now opens straight into a room's parts view; "Choose another room"
	# switches rooms and an explicit refresh still discovers them. Its real
	# verifier requires complete records, unlike the layout-only solo fixture
	# above. Eight historical rooms reuse an authentic First Light pair.
	var pair := {
		"a": JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-a.json")),
		"b": JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-b.json"))}
	var metadata := {"room_id": SHARED_ROOM, "host_id": OWNER, "guest_id": GUEST, "level_id": "first-light", "attempt": 0, "first_player_id": OWNER, "active_role": "a", "recordings": {}}
	var rooms: Array = []
	for index in range(count):
		var room := metadata.duplicate(true)
		room.room_id = SHARED_ROOM if index == 0 else "S" + str(index).pad_zeros(21)
		room.active_role = "complete"
		room.recordings = pair.duplicate(true)
		rooms.append(room)
	app.saves.data.room = {}
	app.shared_replays = Shared.new(api, app._relay_identity, Memory.new(), Memory.new())
	var before: int = api.calls.size()
	app._show_shared_replays()
	_check(api.calls.size() == before, "Opening Shared replays only reads owner-scoped local data")
	_check(app.mode == "shared_replays", "With nothing saved yet Together shows its empty state, not a room list")
	api.responses.append({"ok": true, "data": {"rooms": rooms}})
	api.responses.append({"ok": true, "data": {"rooms": []}})
	await app._refresh_shared_replay_rooms()
	_check(api.calls.size() == before + 2 and api.responses.is_empty(), "Explicit shared-room refresh consumes one legacy and one chapter response")
	var area := Rect2(Vector2.ZERO, Vector2(viewport.size))
	if count == 0:
		await _settle()
		var context := "Shared empty at %s" % str(viewport.size)
		var lists: Array[Node] = _scrollers(app)
		_check(lists.size() == 1, context + " uses one bounded scroller")
		if lists.size() == 1: _check(area.grow(0.5).encloses((lists[0] as Control).get_global_rect()), context + " list fits the viewport")
		_check(_label_contains(app.overlay, PlayerCopy.MAIN_87534286A315), context + " explains that nothing is saved yet")
		var refresh := _find_button(app.overlay, "Refresh shared rooms")
		var home_back := _find_button(app.overlay, "Back")
		_check(refresh != null and home_back != null and area.grow(0.5).encloses(home_back.get_global_rect()), context + " keeps Refresh and a Home-going Back reachable")
		_check(app.shared_replays._remember_room(metadata, "legacy"), "Empty-memory case has a valid participant-owned room")
	else:
		_check(app.mode == "shared_memories" and app.shared_replay_room == "legacy:" + SHARED_ROOM, "Refresh lands straight in the most recent room's parts view")
		var selectors: Array[Node] = app.overlay.find_children("*", "OptionButton", true, false)
		_check(selectors.size() == 1 and (selectors[0] as OptionButton).item_count == count, "Choose another room lists every room that still has a saved replay")
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
	await _inspect_memories(app, viewport, count, can_drag)
	_check(api.calls.size() == before + 3 and api.responses.is_empty(), "Memory refresh consumes only the selected room's response")
	_check(app.shared_replays.memories("legacy:" + SHARED_ROOM).size() == count, "Every displayed shared row came through actual replay verification")


func _scrollers(app: Node) -> Array[Node]:
	var lists: Array[Node] = []
	for node: Node in app.overlay.find_children("*", "ScrollContainer", true, false):
		var in_popup := false
		var ancestor := node.get_parent()
		while ancestor != null:
			if ancestor is Popup: in_popup = true; break
			ancestor = ancestor.get_parent()
		if not in_popup: lists.append(node)
	return lists


func _label_contains(node: Node, text: String) -> bool:
	for label: Label in node.find_children("*", "Label", true, false):
		if text in label.text: return true
	return false


func _inspect(app: Node, viewport: SubViewport, expected: Array[String], empty_text: String, back_text: String, context: String, can_drag: bool, card_actions: Array[String] = [], replay_actions: bool = false, two_column: bool = false) -> void:
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
	if two_column:
		# The Replays view pairs a scrolling row list with a preview card. Row
		# title controls carry a marker so Play and preview actions are not
		# mistaken for list rows.
		var tagged: Array[Button] = []
		for button: Button in scroll.find_children("*", "Button", true, false):
			if button.has_meta("replay_row"): tagged.append(button)
		rows = tagged
		_check_replay_rows(app, rows, context)
	var footer: Array[Button] = []
	if not card_actions.is_empty():
		# The shared replay card deliberately scrolls its heading, replay list
		# and footer together. Direct stack buttons are actions, not replay rows.
		rows.clear()
		var delete_count := 0
		for button: Button in scroll.find_children("*", "Button", true, false):
			if button.get_parent() == scroll.get_child(0):
				footer.append(button)
			elif replay_actions and button.get_parent() is HBoxContainer and button != button.get_parent().get_child(0):
				delete_count += 1
				_check(button.text == "Delete" or button.tooltip_text.begins_with("Delete"), context + " each secondary replay action identifies deletion")
				_check(button.mouse_filter == Control.MOUSE_FILTER_PASS, context + " deletion action permits parent gesture handling")
			else: rows.append(button)
		_check(delete_count == (expected.size() if replay_actions else 0), context + " has exactly one deletion action per saved replay")
		var actual_footer: Array[String] = []
		for button: Button in footer: actual_footer.append(button.text)
		_check(actual_footer == card_actions, context + " retains every footer action once in order")
		var panel: Control = scroll.get_parent().get_parent()
		_check(app.ui.get_global_rect().grow(0.5).encloses(panel.get_global_rect()), context + " entire bounded replay panel fits the safe screen")
	var actual: Array[String] = []
	for row: Button in rows:
		actual.append(row.text)
		_check(row.mouse_filter == Control.MOUSE_FILTER_PASS, context + " row permits parent gesture handling")
	_check(actual == expected, context + " contains every expected row once in order")
	var back: Button = null
	for button: Button in app.overlay.find_children("*", "Button", true, false):
		if button.text == back_text:
			back = button
	if card_actions.is_empty():
		_check(back != null and not scroll.is_ancestor_of(back) and area.grow(0.5).encloses(back.get_global_rect()), context + " keeps Back visible outside the list")
	else:
		_check(back != null and not back.disabled and scroll.is_ancestor_of(back), context + " keeps an enabled Back in the single bounded scroller")
		for button: Button in footer:
			scroll.ensure_control_visible(button)
			await _settle()
			_check(scroll.get_global_rect().grow(0.5).encloses(button.get_global_rect()) and area.grow(0.5).encloses(button.get_global_rect()), context + " footer action is fully reachable: " + button.text)
		scroll.scroll_vertical = 0
		await _settle()
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
		scroll.ensure_control_visible(rows[2])
		await _settle()
		_check(scroll.get_global_rect().grow(0.5).encloses(rows[2].get_global_rect()), context + " row is visible before the actual viewport drag")
		var before_scroll := scroll.scroll_vertical
		await _drag(viewport, rows[2].get_global_rect().get_center(), Vector2(0, -130))
		var retained := is_instance_valid(scroll) and scroll.is_inside_tree() and scroll.get_instance_id() == list_id
		_check(retained, context + " drag does not launch a row or replace the current menu")
		if not retained:
			return
		_check(scroll.scroll_vertical > before_scroll, context + " viewport drag scrolls over actual row controls")
	if not rows.is_empty():
		scroll.ensure_control_visible(rows[-1])
		await _settle()
		_check(scroll.get_global_rect().grow(0.5).encloses(rows[-1].get_global_rect()), context + " final row can be brought fully into view")


func _inspect_memories(app: Node, viewport: SubViewport, count: int, can_drag: bool) -> void:
	# The redesigned Together memories view pairs a part list with a preview card
	# and keeps room-level actions in an Options popup, while Back stays in the
	# fixed header. This verifies scrolling, Back reachability, exact room
	# selection, the preview delete and the Options actions without weakening the
	# original intent.
	await _settle()
	var context := "Shared memories %d at %s" % [count, str(viewport.size)]
	var lists: Array[Node] = []
	for node: Node in app.overlay.find_children("*", "ScrollContainer", true, false):
		var ancestor := node.get_parent()
		var in_popup := false
		while ancestor != null:
			if ancestor is Popup: in_popup = true; break
			ancestor = ancestor.get_parent()
		if not in_popup: lists.append(node)
	_check(lists.size() == 1, context + " has exactly one bounded scrolling list")
	if lists.size() != 1: return
	var scroll := lists[0] as ScrollContainer
	var area := Rect2(Vector2.ZERO, Vector2(viewport.size))
	_check(area.grow(0.5).encloses(scroll.get_global_rect()), context + " list fits the viewport")
	var rows: Array[Button] = []
	for button: Button in scroll.find_children("*", "Button", true, false):
		if button.has_meta("replay_row"): rows.append(button)
	_check(rows.size() == count, context + " lists exactly one row per saved memory")
	for row: Button in rows:
		_check(row.text == "First Light", context + " each memory row shows its stage title")
		_check(row.mouse_filter == Control.MOUSE_FILTER_PASS, context + " memory row permits parent gesture handling")
	var back: Button = null
	for button: Button in app.overlay.find_children("*", "Button", true, false):
		if button.text == "Back": back = button
	_check(back != null and not scroll.is_ancestor_of(back) and not back.disabled and area.grow(0.5).encloses(back.get_global_rect()), context + " keeps Back reachable outside the list")
	if count == 0:
		var explained := false
		for label: Label in scroll.find_children("*", "Label", true, false):
			explained = explained or "No completed stages" in label.text
		_check(explained, context + " explains the empty state inside the list")
		_check(not _label_contains(scroll, PlayerCopy.MAIN_4CACA12BCD58), context + " has no selection hint while there is nothing to select")
		var empty_options := _find_button(scroll, "Options")
		_check(empty_options != null, context + " offers Options even when empty")
		if empty_options != null:
			_check(empty_options.size.x < scroll.size.x * 0.5 and empty_options.size.y >= 48, context + " sizes Options to its label rather than the full width")
		return
	_check(_label_contains(scroll, PlayerCopy.MAIN_4CACA12BCD58), context + " explains selection once there are stages to select")
	_check_replay_rows(app, rows, context)
	# Side by side, the preview card sits beside the scrolling list and stays
	# put; stacked, it scrolls with the list. Either way its actions stay in view.
	var side_by_side: bool = app.ui.size.x >= app.REPLAY_SPLIT_MIN_WIDTH
	var watch := _find_button(app.overlay, "Watch replay")
	_check(watch != null, context + " offers a dominant Watch replay for the selected memory")
	if watch != null:
		_check(app.ui.get_global_rect().grow(0.5).encloses(watch.get_global_rect()), context + " Watch replay is fully inside the safe screen")
		if side_by_side: _check(not scroll.is_ancestor_of(watch), context + " preview card stays fixed beside the scrolling list")
	var deletes := 0
	for button: Button in app.overlay.find_children("*", "Button", true, false):
		if button.tooltip_text.begins_with("Delete replay:"): deletes += 1
	_check(deletes == 1, context + " exposes exactly one delete for the selected memory")
	var options := _find_button(app.overlay, "Options")
	_check(options != null, context + " offers Options for room-level actions")
	if options != null:
		options.pressed.emit()
		await _settle()
		_check(_find_button(app.ui, "Refresh memories") != null and _find_button(app.ui, "Sync photos") != null and _find_button(app.ui, "Find more rooms") != null, context + " Options holds Refresh memories, Sync photos and Find more rooms")
		var modal: Node = app.ui.find_child("SharedReplayOptions", true, false)
		if modal != null: modal.close()
		await _settle()
	_check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, context + " overflowing rows really scroll")
	if can_drag and rows.size() >= 3:
		var list_id := scroll.get_instance_id()
		scroll.ensure_control_visible(rows[2])
		await _settle()
		var before_scroll := scroll.scroll_vertical
		await _drag(viewport, rows[2].get_global_rect().get_center(), Vector2(0, -130))
		var retained := is_instance_valid(scroll) and scroll.is_inside_tree() and scroll.get_instance_id() == list_id
		_check(retained, context + " drag does not launch a memory or replace the view")
		if retained: _check(scroll.scroll_vertical > before_scroll, context + " viewport drag scrolls over actual memory rows")
	scroll.ensure_control_visible(rows[-1])
	await _settle()
	_check(scroll.get_global_rect().grow(0.5).encloses(rows[-1].get_global_rect()), context + " final memory row can be brought into view")


func _check_replay_rows(app: Node, titles: Array[Button], context: String) -> void:
	# Replay rows: the heading-font title starts flush with its caption, the
	# art fills its rounded frame, and Play keeps its own height.
	for title: Button in titles:
		var caption := title.get_parent().get_child(1) as Label
		_check(caption != null and is_zero_approx(title.get_theme_stylebox("normal").content_margin_left) and is_equal_approx(title.get_global_rect().position.x, caption.get_global_rect().position.x), context + " row title starts flush with its caption")
		_check(title.get_theme_font("font") == app.title_font and title.size.y >= 48, context + " row title uses the heading font and a full touch target")
		var rowbox := title.get_parent().get_parent()
		var frame := rowbox.get_child(0) as PanelContainer
		var picture: Control = frame.get_child(0) as Control if frame != null and frame.get_child_count() > 0 else null
		_check(picture != null and picture.get_global_rect().is_equal_approx(frame.get_global_rect()), context + " row art fills its rounded frame edge to edge")
		for child: Node in rowbox.get_children():
			var play := child as Button
			if play != null and play.text == "Play":
				_check(play.size.y >= 48 and play.size.y <= play.get_combined_minimum_size().y + 0.5, context + " row Play keeps its own height instead of stretching")


func _find_button(node: Node, text: String) -> Button:
	for button: Button in node.find_children("*", "Button", true, false):
		if button.text == text: return button
	return null


func _rows(scroll: ScrollContainer) -> Array[Button]:
	var result: Array[Button] = []
	for row: Button in scroll.find_children("*", "Button", true, false):
		if not row.text.is_empty(): result.append(row)
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

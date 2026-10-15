extends SceneTree
## Touch drag versus tap across the app's scrolling lists and its themed
## dropdowns. A drag that starts on a control inside a list scrolls that list
## and never activates the control; a short tap still activates it once.
## Input goes through real viewport routing: on the root window, screen touches
## enter through Input.parse_input_event and the engine's own mouse emulation;
## for the full app inside a SubViewport, the same mouse-then-touch event pairs
## are pushed in the order the engine produces them. Turning on
## Input.emulate_touch_from_mouse makes this headless display report a
## touchscreen, which enables ScrollContainer's native drag handling.

const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const FakeApi = preload("res://tests/fake_rooms_api.gd")
const Hub = preload("res://presentation/room_hub_screen.gd")
const Picker = preload("res://presentation/chapter_picker.gd")
const Friends = preload("res://presentation/friends_screen.gd")
const Controls = preload("res://presentation/control_theme.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Thumbs = preload("res://services/chapter_thumbnail_catalog.gd")
const Licenses = preload("res://services/licenses.gd")
const FRIENDS_OWNER := "OOOOOOOOOOOOOOOOOOOOOO"

class Inbox extends RefCounted:
	var rooms: Array = []
	func view() -> Dictionary: return {"rooms": rooms, "stale": false, "error": ""}
	func unread(_room: Dictionary) -> bool: return false
	func confirm_room_rendered(_version: int, _id: String) -> bool: return false
	func refresh() -> bool: return true

class FriendsStub extends RefCounted:
	var busy := false
	var last_error := ""
	var page: Dictionary = {}
	func context() -> Dictionary: return {"base_url": "https://friends.invalid", "player_id": "OOOOOOOOOOOOOOOOOOOOOO"}
	func view() -> Dictionary: return page
	func refresh_due(_manual: bool = false) -> bool: return false
	func refresh_wait_ms(_manual: bool = false) -> int: return 0
	func join_wait_ms() -> int: return 0
	func refresh(_manual: bool = false) -> bool: return true

class NicknameStub extends RefCounted:
	func display_name(_server: String, _owner: String, friend: String, _fallback: String = "") -> String: return "Pal " + friend.substr(0, 2)
	func nickname(_server: String, _owner: String, _friend: String) -> String: return ""

class SharedStub extends RefCounted:
	var listed: Array = []
	func rooms() -> Array: return listed
	func memories(_key: String, _local: bool = false) -> Array: return [{"id": "kept"}]
	func updated_at(_room: Dictionary) -> int: return 0

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var original_touch_emulation := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	var can_drag := DisplayServer.is_touchscreen_available()
	_check(can_drag, "This display reports a touchscreen once touch emulation is on; drag gestures are exercised")
	if can_drag:
		await _adoption()
		await _hub()
		await _friends()
		await _app()
	Input.emulate_touch_from_mouse = original_touch_emulation
	_check(Input.emulate_touch_from_mouse == original_touch_emulation, "Restore the process input setting")
	print("AFTER YOU TOUCH SCROLLING: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _adoption() -> void:
	# A synthetic list proves the shared helper on its own: rows added after it
	# runs still pass drags up, including through a panel card, while a text
	# field keeps its own gestures.
	var host := Control.new()
	host.size = Vector2(1280, 720)
	host.theme = Theme.new()
	host.theme.default_font = preload("res://assets/fonts/nunito.ttf")
	host.theme.default_font_size = 20
	Controls.install_buttons(host.theme)
	root.add_child(host)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(100, 100)
	scroll.size = Vector2(600, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.add_child(scroll)
	Controls.touch_scroll(scroll)
	Controls.touch_scroll(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var taps := [0]
	var cards: Array[PanelContainer] = []
	var buttons: Array[Button] = []
	var labels: Array[Label] = []
	for index: int in range(10):
		var card := PanelContainer.new()
		list.add_child(card)
		var row := HBoxContainer.new()
		card.add_child(row)
		var label := Label.new()
		label.text = "Row %d" % index
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button := Button.new()
		button.text = "Open %d" % index
		button.custom_minimum_size = Vector2(140, 52)
		button.pressed.connect(func(): taps[0] += 1)
		row.add_child(button)
		cards.append(card)
		buttons.append(button)
		labels.append(label)
	var field := LineEdit.new()
	list.add_child(field)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 40
	list.add_child(spacer)
	await _settle()
	var adopted := true
	for control: Control in cards + buttons:
		adopted = adopted and control.mouse_filter == Control.MOUSE_FILTER_PASS
	_check(adopted and spacer.mouse_filter == Control.MOUSE_FILTER_PASS, "Rows added after touch_scroll pass drags up, including panel cards and spacers")
	_check(field.mouse_filter == Control.MOUSE_FILTER_STOP, "A text field inside the list keeps its own gestures")
	_check(scroll.child_entered_tree.get_connections().size() == 1, "Repeated touch_scroll calls do not stack watchers")
	_check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, "The synthetic list overflows")
	await _drag(root, buttons[1].get_global_rect().get_center(), Vector2(0, -120))
	_check(scroll.scroll_vertical > 0 and taps[0] == 0, "Touch drag from a button inside a panel card scrolls without pressing it")
	await _rest(scroll)
	var before := scroll.scroll_vertical
	await _drag(root, labels[3].get_global_rect().get_center(), Vector2(0, -90))
	_check(scroll.scroll_vertical > before and taps[0] == 0, "Touch drag from a card's text scrolls the list")
	await _rest(scroll)
	scroll.scroll_vertical = 0
	await _settle()
	await _tap(root, buttons[0].get_global_rect().get_center())
	_check(taps[0] == 1, "A short touch tap still presses the button exactly once")
	# Negative control: the panel's default STOP filter blocks the same drag.
	cards[2].mouse_filter = Control.MOUSE_FILTER_STOP
	await _drag(root, labels[2].get_global_rect().get_center(), Vector2(0, -120))
	_check(scroll.scroll_vertical == 0, "Restoring a panel's STOP filter reproduces the blocked drag")
	cards[2].mouse_filter = Control.MOUSE_FILTER_PASS
	host.queue_free()
	await _settle()


func _hub() -> void:
	var inbox := Inbox.new()
	var keys: Array = Registry.keys()
	for index: int in range(8):
		var key: String = keys[index % keys.size()]
		inbox.rooms.append({"api_version": 2, "room_id": "room-%d" % index, "chapter_key": key, "chapter_title": str(Registry.descriptor(key).title), "member_ids": ["me", "friend"], "status": "your_turn" if index % 2 == 0 else "waiting_for_their_turn", "part": 1, "stage_count": 2})
	# The fixture keeps the hub's minimal chapter shape: key, title and stage count.
	var chapters: Array[Dictionary] = []
	for key: String in keys:
		chapters.append({"key": key, "title": str(Registry.descriptor(key).title), "stage_count": 2})
	var hub := Hub.new()
	hub.client = inbox
	hub.set_chapters(chapters)
	hub.display_name = func(member: String) -> String: return "" if member == "me" else "Sam"
	hub.thumbnail_for = func(key: String) -> String: return Thumbs.path(key)
	var opened := [0]
	var hosted: Array = []
	var picked: Array[String] = []
	hub.room_open_requested.connect(func(_room: Dictionary, _source: Control): opened[0] += 1)
	hub.host_requested.connect(func(key: String, _visibility: String, _source: Control): hosted.append(key))
	hub.chapter_picked.connect(func(key: String): picked.append(key))
	root.add_child(hub)
	await _settle()
	await _settle()
	var choice: Button = hub._chapter_choice
	_check(hub.find_children("*", "OptionButton", true, false).is_empty() and choice != null and choice.text == str(chapters[0].title), "The hub names its chapter on a button instead of a dropdown")
	_check(choice.mouse_filter == Control.MOUSE_FILTER_PASS and choice.size.y >= 48.0, "The chapter button passes drags up and keeps a full touch target")
	# Tap: the shared chapter picker replaces the hub as a page.
	await _tap(root, choice.get_global_rect().get_center())
	await _settle()
	var page: Control = hub._picker_page
	var picker: Picker = hub._picker
	_check(page != null and page.visible and not hub._layout.visible and picker != null and picker.get_script() == Picker, "A tap opens the shared chapter picker as a page")
	if picker == null:
		hub.queue_free()
		return
	var cards: Array = picker.grid.get_children()
	_check(cards.size() == chapters.size(), "One card per chapter")
	_check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(picker.get_global_rect()), "The picker fits the window")
	var bar := picker.get_v_scroll_bar()
	_check(bar.max_value > bar.page, "Long chapter lists scroll inside the picker")
	var buttons_ok := true
	for card: Control in cards:
		var open := card.find_child("ChapterOpen", true, false) as Button
		buttons_ok = buttons_ok and open != null and open.get_meta("completion_variant") == "friend" and open.mouse_filter == Control.MOUSE_FILTER_PASS and open.accessibility_name.ends_with(" · Host a room")
	_check(buttons_ok, "Every card has one friend-marked button that passes drags")
	# Drag over a card's button: the list scrolls and nothing is chosen.
	var first_open := (cards[0] as Control).find_child("ChapterOpen", true, false) as Button
	picker.scroll_vertical = 0
	await _settle()
	await _drag(root, first_open.get_global_rect().get_center(), Vector2(0, -120))
	_check(picker.scroll_vertical > 0, "A touch drag that starts on a chapter button scrolls the picker")
	_check(page.visible and picked.is_empty() and hub.selected_key() == str(chapters[0].key), "That drag keeps the picker open and chooses nothing")
	await _rest(picker)
	var mouse_before := picker.scroll_vertical
	await _mouse_drag(root, picker.get_global_rect().get_center(), Vector2(0, 80))
	_check(picker.scroll_vertical < mouse_before and picked.is_empty() and page.visible, "A mouse-emulated drag scrolls the picker back without choosing")
	await _rest(picker)
	# Tap a fully visible card other than the current one.
	var target: Button = null
	for card: Control in cards:
		var open := card.find_child("ChapterOpen", true, false) as Button
		if card.get_meta("chapter_key") != hub.selected_key() and picker.get_global_rect().grow(0.5).encloses(open.get_global_rect()): target = open; break
	_check(target != null, "A different chapter's button is fully visible")
	if target != null:
		var key := str(target.get_meta("completion_chapter"))
		await _tap(root, target.get_global_rect().get_center())
		await _settle()
		_check(picked == [key] and hub.selected_key() == key, "A short tap on a card chooses that chapter once")
		_check(hub._hero_title.text == str(Registry.descriptor(key).title) and choice.text == hub._hero_title.text, "The hub's picture and button follow the chosen chapter")
		_check(not page.visible and hub._layout.visible, "Choosing returns to the hub")
	# Reopening reuses the cards and starts at the current chapter.
	var built: Node = cards[0]
	await _tap(root, choice.get_global_rect().get_center())
	await _settle()
	await _settle()
	var current: Control = picker.card_for(hub.selected_key())
	_check(page.visible and is_instance_valid(built) and picker.grid.get_child(0) == built, "Reopening the picker reuses its cards")
	_check(current != null and picker.get_global_rect().grow(0.5).encloses(current.get_global_rect()), "The reopened picker starts at the current chapter")
	# Back, Escape and Android Back close it without choosing.
	var back := _find_button(page, "Back")
	await _tap(root, back.get_global_rect().get_center())
	await _settle()
	_check(not page.visible and picked.size() == 1, "The page's Back returns to the hub without choosing")
	await _tap(root, choice.get_global_rect().get_center())
	await _settle()
	_action("ui_cancel", true)
	_action("ui_cancel", false)
	await _settle()
	_check(not page.visible and hub._layout.visible, "ui_cancel closes the picker")
	await _tap(root, choice.get_global_rect().get_center())
	await _settle()
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _settle()
	_check(not page.visible and picked.size() == 1 and is_instance_valid(hub), "Android Back closes the picker without choosing and keeps the hub")
	# Keyboard and gamepad: accept opens it with focus on the current chapter,
	# and accepting a chapter chooses it and returns focus to the button.
	choice.grab_focus()
	_action("ui_accept", true)
	_action("ui_accept", false)
	await _settle()
	await _settle()
	var focused := root.gui_get_focus_owner()
	_check(page.visible and focused != null and focused.name == "ChapterOpen" and focused.get_meta("completion_chapter") == hub.selected_key(), "ui_accept opens the picker with focus on the current chapter")
	_action("ui_down", true)
	_action("ui_down", false)
	await _settle()
	var next := root.gui_get_focus_owner()
	_check(next != null and next != focused and next.name == "ChapterOpen", "Arrow keys move between chapter buttons")
	_action("ui_accept", true)
	_action("ui_accept", false)
	await _settle()
	_check(next != null and hub.selected_key() == str(next.get_meta("completion_chapter")) and not page.visible and choice.has_focus(), "Accept chooses the focused chapter and focus returns to the chapter button")
	_check(hosted.is_empty(), "Choosing never hosts by itself")
	var host_button: Button = null
	for button: Button in hub._right_column.find_children("*", "Button", true, false):
		if button.text == "Host a room": host_button = button
	host_button.pressed.emit()
	_check(hosted == [hub.selected_key()], "Host a room hosts the chosen chapter")
	# A drag that starts on the chapter button scrolls the host column and
	# leaves the picker closed. Extra content makes the column overflow.
	var filler := Control.new()
	filler.custom_minimum_size.y = 420
	hub._right_column.add_child(filler)
	await _settle()
	var column := hub._right_scroll
	column.scroll_vertical = 0
	await _settle()
	_check(column.get_v_scroll_bar().max_value > column.get_v_scroll_bar().page, "The host column overflows for the drag check")
	_check(column.get_global_rect().encloses(choice.get_global_rect()), "The chapter button is visible in the host column")
	await _drag(root, choice.get_global_rect().get_center(), Vector2(0, -100))
	_check(column.scroll_vertical > 0 and not page.visible, "A touch drag from the chapter button scrolls the host column and opens nothing")
	await _rest(column)
	column.ensure_control_visible(host_button)
	await _settle()
	var column_before := column.scroll_vertical
	var hosted_before := hosted.size()
	await _drag(root, host_button.get_global_rect().get_center(), Vector2(0, 80 if column_before > 0 else -80))
	_check(column.scroll_vertical != column_before and hosted.size() == hosted_before, "A drag from Host a room scrolls the column without hosting")
	await _rest(column)
	column.scroll_vertical = 0
	await _settle()
	await _mouse_drag(root, choice.get_global_rect().get_center(), Vector2(0, -100))
	_check(column.scroll_vertical > 0 and not page.visible, "A mouse-emulated drag from the chapter button behaves the same")
	await _rest(column)
	hub._right_column.remove_child(filler)
	filler.queue_free()
	column.scroll_vertical = 0
	await _settle()
	# Layout holds at phone sizes, with the picker inside the safe margins.
	for size: Vector2i in [Vector2i(1560, 720), Vector2i(1280, 720), Vector2i(800, 360)]:
		root.size = size
		await _settle()
		hub.open_chapter_picker()
		await _settle()
		await _settle()
		# The window's stretch keeps a short landscape screen wide in layout units.
		var screen := root.get_visible_rect()
		var inside := picker.get_global_rect()
		_check(screen.encloses(inside) and screen.encloses(back.get_global_rect()) and back.get_global_rect().end.y <= inside.position.y, "The picker and its Back fit at " + str(size))
		var overflow := false
		for card: Control in picker.grid.get_children():
			overflow = overflow or card.get_global_rect().end.x > inside.end.x + 0.5
		_check(not overflow and picker.grid.columns == (2 if screen.size.x >= 1100.0 else 1), "Cards stay inside the picker, in two columns when they fit, at " + str(size))
		hub.close_chapter_picker()
	root.size = Vector2i(1280, 720)
	await _settle()
	# Rooms list: drags from a card's text and from its action scroll the list.
	var rooms := hub._rooms_scroll
	_check(rooms.get_v_scroll_bar().max_value > rooms.get_v_scroll_bar().page, "Eight rooms overflow the rooms list")
	var heading: Label = null
	for label: Label in hub._rooms_list.find_children("*", "Label", true, false):
		if rooms.get_global_rect().encloses(label.get_global_rect()) and label.get_theme_font_size("font_size") == 24: heading = label; break
	if heading != null:
		await _drag(root, heading.get_global_rect().get_center(), Vector2(0, -100))
		_check(rooms.scroll_vertical > 0 and opened[0] == 0, "A drag from a room card's title scrolls the rooms list")
	await _rest(rooms)
	var room_button: Button = null
	for button: Button in hub._rooms_list.find_children("*", "Button", true, false):
		if rooms.get_global_rect().encloses(button.get_global_rect()) and not button.disabled: room_button = button; break
	var rooms_before := rooms.scroll_vertical
	await _drag(root, room_button.get_global_rect().get_center(), Vector2(0, 90))
	_check(rooms.scroll_vertical < rooms_before and opened[0] == 0, "A drag from a room's action scrolls without opening the room")
	await _rest(rooms)
	await _tap(root, room_button.get_global_rect().get_center())
	_check(opened[0] == 1, "A short tap on that action opens the room once")
	hub.queue_free()
	await _settle()


func _friends() -> void:
	var stub := FriendsStub.new()
	var friends: Array = []
	for index: int in range(8):
		friends.append({"player_id": "F%d" % index + "Q".repeat(20), "status": "accepted", "online": index % 2 == 0, "join_available": false, "request_id": ""})
	stub.page = {"friends": friends, "friend_code": "ABCD1234", "shared_room": null}
	var screen: CanvasLayer = Friends.new()
	screen.client = stub
	screen.nickname_store = NicknameStub.new()
	var closes := [0]
	screen.closed.connect(func(): closes[0] += 1)
	root.add_child(screen)
	await _settle()
	await _settle()
	var outer: ScrollContainer = screen._scroll
	var inner: ScrollContainer = null
	for node: Node in outer.find_children("*", "ScrollContainer", true, false): inner = node
	_check(inner != null, "The friend list scrolls inside the page")
	if inner == null:
		screen.queue_free()
		return
	_check(inner.get_v_scroll_bar().max_value > inner.get_v_scroll_bar().page, "Eight friends overflow the friend list")
	var name_label: Label = null
	for label: Label in inner.find_children("*", "Label", true, false):
		if label.text == "Pal " + str(friends[1].player_id).substr(0, 2) and inner.get_global_rect().encloses(label.get_global_rect()): name_label = label; break
	_check(name_label != null, "A friend's name is visible")
	if name_label != null:
		var card := _panel_ancestor(name_label)
		_check(card != null and card.mouse_filter == Control.MOUSE_FILTER_PASS, "Friend cards pass drags up to their list")
		await _drag(root, name_label.get_global_rect().get_center(), Vector2(0, -100))
		_check(inner.scroll_vertical > 0 and screen._remove.is_empty() and closes[0] == 0, "A drag from a friend's name scrolls the friend list")
		await _rest(inner)
		inner.scroll_vertical = 0
		await _settle()
		# Negative control: the card's former STOP filter blocks that drag.
		if card != null:
			card.mouse_filter = Control.MOUSE_FILTER_STOP
			await _drag(root, name_label.get_global_rect().get_center(), Vector2(0, -100))
			_check(inner.scroll_vertical == 0, "The former STOP card reproduces the blocked friend-list drag")
			card.mouse_filter = Control.MOUSE_FILTER_PASS
	# A drag that starts on a friend's code also scrolls, and copies nothing.
	var copies: Array = []
	screen.clipboard_copy = func(text: String) -> void: copies.append(text)
	var row_code: Button = null
	for button: Button in inner.find_children("FriendRowCode", "Button", true, false):
		if inner.get_global_rect().encloses(button.get_global_rect()): row_code = button; break
	_check(row_code != null and row_code.mouse_filter == Control.MOUSE_FILTER_PASS, "A friend's code is a pass-through tap target")
	if row_code != null:
		inner.scroll_vertical = 0
		await _settle()
		await _drag(root, row_code.get_global_rect().get_center(), Vector2(0, -100))
		_check(inner.scroll_vertical > 0 and copies.is_empty(), "A drag from a friend's code scrolls the friend list without copying")
		await _rest(inner)
		inner.scroll_vertical = 0
		await _settle()
	# The page itself scrolls from a drag on the code card when it overflows.
	var content: Control = screen._content
	content.custom_minimum_size.y = outer.size.y + 360.0
	await _settle()
	_check(outer.get_v_scroll_bar().max_value > outer.get_v_scroll_bar().page, "The Friends page overflows for the drag check")
	var code_label: Label = null
	for label: Label in outer.find_children("*", "Label", true, false):
		if label.text == "Your friend code": code_label = label
	if code_label != null:
		outer.ensure_control_visible(code_label)
		await _settle()
		var page_before := outer.scroll_vertical
		await _drag(root, code_label.get_global_rect().get_center(), Vector2(0, -100 if page_before == 0 else 100))
		_check(outer.scroll_vertical != page_before, "A drag from the friend-code card scrolls the Friends page")
	await _rest(outer)
	outer.scroll_vertical = 0
	await _settle()
	# A short tap on a row action still works.
	var remove: Button = null
	for button: Button in inner.find_children("*", "Button", true, false):
		if button.tooltip_text == "Remove friend" and inner.get_global_rect().encloses(button.get_global_rect()): remove = button; break
	_check(remove != null, "A Remove friend action is visible")
	if remove != null:
		await _tap(root, remove.get_global_rect().get_center())
		_check(not screen._remove.is_empty(), "A short tap on Remove friend opens its confirmation")
	screen.close()
	await _settle()


func _panel_ancestor(node: Node) -> PanelContainer:
	var parent := node.get_parent()
	while parent != null:
		if parent is PanelContainer: return parent
		parent = parent.get_parent()
	return null


func _app() -> void:
	var path := "user://touch-scrolling-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var storage := Storage.new(path)
	storage.data.settings.sound = false
	storage.data.settings.haptics = false
	_check(storage.flush(), "Prepare an isolated muted save")
	var saved_bytes := FileAccess.get_file_as_string(path)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 540)
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
	await _account(app, viewport, api)
	viewport.size = Vector2i(1280, 720)
	await _settle()
	await _settings(app, viewport)
	await _licenses(app, viewport)
	await _room_selector(app, viewport)
	_check(FileAccess.get_file_as_string(path) == saved_bytes, "Gestures never modify the isolated save on disk")
	viewport.queue_free()
	await _settle()
	await create_timer(0.15).timeout
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)


func _account(app: Node, viewport: SubViewport, api: Node) -> void:
	app._show_account()
	await _settle()
	await _settle()
	_check(app.mode == "account", "Account & recovery opens")
	var scroll: ScrollContainer = app._bounded_card_scroll
	_check(scroll != null and scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, "Account & recovery overflows its bounded card at this height")
	if scroll == null: return
	var passing := true
	for button: BaseButton in scroll.find_children("*", "BaseButton", true, false):
		passing = passing and button.mouse_filter == Control.MOUSE_FILTER_PASS
	_check(passing, "Every Account & recovery action passes drags to its card")
	var hosting := _find_button(scroll, "Check hosting access")
	_check(hosting != null and scroll.get_global_rect().encloses(hosting.get_global_rect()), "Check hosting access is visible")
	if hosting == null: return
	var calls: int = api.calls.size()
	await _drag(viewport, hosting.get_global_rect().get_center(), Vector2(0, -120))
	_check(scroll.scroll_vertical > 0, "A touch drag from an account action scrolls the card")
	_check(app.mode == "account" and api.calls.size() == calls and is_instance_valid(scroll) and scroll.is_inside_tree(), "That drag does not run the action")
	await _rest(scroll)
	scroll.scroll_vertical = 0
	await _settle()
	hosting.mouse_filter = Control.MOUSE_FILTER_STOP
	await _drag(viewport, hosting.get_global_rect().get_center(), Vector2(0, -120))
	_check(scroll.scroll_vertical == 0 and app.mode == "account", "The former STOP action reproduces the owner's blocked Account drag")
	hosting.mouse_filter = Control.MOUSE_FILTER_PASS
	await _mouse_drag(viewport, hosting.get_global_rect().get_center(), Vector2(0, -120))
	_check(scroll.scroll_vertical > 0 and app.mode == "account", "A mouse-emulated drag from the action scrolls too")
	await _rest(scroll)
	var details := _find_button(scroll, "Show my recovery details")
	scroll.ensure_control_visible(details)
	await _settle()
	await _tap(viewport, details.get_global_rect().get_center())
	_check(app.mode == "recovery_details", "A short tap still opens recovery details")


func _settings(app: Node, viewport: SubViewport) -> void:
	app._show_settings()
	await _settle()
	var lists: Array[Node] = app.overlay.find_children("*", "ScrollContainer", true, false)
	_check(lists.size() == 1, "Settings has one scrolling list")
	if lists.size() != 1: return
	var scroll := lists[0] as ScrollContainer
	var account := _find_button(scroll, "Account & recovery")
	_check(account != null and account.mouse_filter == Control.MOUSE_FILTER_PASS, "Settings links pass drags to the list")
	if account == null: return
	scroll.ensure_control_visible(account)
	await _settle()
	var before := scroll.scroll_vertical
	_check(before > 0, "The Account & recovery link sits below the first screen of settings")
	await _drag(viewport, account.get_global_rect().get_center(), Vector2(0, 110))
	_check(scroll.scroll_vertical < before and app.mode == "settings", "A drag from a settings link scrolls without opening it")
	await _rest(scroll)
	scroll.ensure_control_visible(account)
	await _settle()
	await _tap(viewport, account.get_global_rect().get_center())
	_check(app.mode == "account", "A short tap on the link opens Account & recovery")


func _licenses(app: Node, viewport: SubViewport) -> void:
	# The list the owner reported as working uses the same path.
	app._show_licenses()
	await _settle()
	var lists: Array[Node] = app.overlay.find_children("*", "ScrollContainer", true, false)
	if lists.size() != 1:
		_check(false, "Licenses has one scrolling list")
		return
	var scroll := lists[0] as ScrollContainer
	var row := _find_button(scroll, str(Licenses.entries()[2].title))
	await _drag(viewport, row.get_global_rect().get_center(), Vector2(0, -110))
	_check(scroll.scroll_vertical > 0 and app.mode == "licenses", "A drag from a license row scrolls the list")
	await _rest(scroll)
	row = _find_button(scroll, str(Licenses.entries()[0].title))
	scroll.ensure_control_visible(row)
	await _settle()
	await _tap(viewport, row.get_global_rect().get_center())
	_check(app.mode == "license_text", "A short tap still opens a license")


func _room_selector(app: Node, viewport: SubViewport) -> void:
	# "Choose another room" uses the same themed selector. It is built here in a
	# scrolling card with enough rows to overflow; its own room switch is
	# replaced by a counter so only the gesture is observed.
	var shared := SharedStub.new()
	for index: int in range(12):
		shared.listed.append({"family": "legacy", "room_id": "R%021d" % index, "title": "Room %d" % index, "host_id": "host", "guest_id": "guest"})
	app.shared_replays = shared
	app.replay_partner_label = func(_friend: String) -> String: return "Sam"
	var list: VBoxContainer = app._scroll_list(app._card(700))
	app._add_shared_room_selector(list)
	var fillers := [0]
	for index: int in range(6):
		list.add_child(app._button("Filler %d" % index, func(): fillers[0] += 1, false))
	await _settle()
	var options: Array[Node] = list.find_children("*", "OptionButton", true, false)
	_check(options.size() == 1, "The room selector is built")
	if options.size() != 1: return
	var option := options[0] as OptionButton
	for connection: Dictionary in option.item_selected.get_connections(): option.item_selected.disconnect(connection.callable)
	var chosen: Array[int] = []
	option.item_selected.connect(func(index: int): chosen.append(index))
	var scroll := list.get_parent() as ScrollContainer
	_check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, "The selector's card list overflows")
	await _drag(viewport, option.get_global_rect().get_center(), Vector2(0, -100))
	_check(scroll.scroll_vertical > 0 and Controls.choice_list(option) == null and not option.get_popup().visible, "A drag from Choose another room scrolls its list and opens nothing")
	await _rest(scroll)
	scroll.scroll_vertical = 0
	await _settle()
	await _tap(viewport, option.get_global_rect().get_center())
	var choices := Controls.choice_list(option)
	_check(choices != null and choices.rows.size() == 12, "A tap opens every room in the in-page list")
	if choices == null: return
	_check(choices.layer > 1, "The room list draws above the app's interface layer")
	await _settle()
	await _drag(viewport, choices.rows[1].get_global_rect().get_center(), Vector2(0, -100))
	_check(choices.scroll.scroll_vertical > 0 and chosen.is_empty() and Controls.choice_list(option) == choices, "A drag over the room list scrolls it and chooses nothing")
	await _rest(choices.scroll)
	var target := _visible_row(choices, option.selected)
	_check(target != null, "A different room row is fully visible")
	if target != null:
		var index := int(target.get_meta("choice_index"))
		await _tap(viewport, target.get_global_rect().get_center())
		_check(chosen == [index] and option.selected == index and Controls.choice_list(option) == null, "A short tap chooses that room once")
	_check(fillers[0] == 0, "No gesture pressed a neighbouring action")


func _visible_row(list: Controls.ChoiceList, skip: int = -1) -> Button:
	var view := list.scroll.get_global_rect().grow(0.5)
	for row: Button in list.rows:
		if int(row.get_meta("choice_index")) != skip and view.encloses(row.get_global_rect()): return row
	return null


func _find_button(node: Node, text: String) -> Button:
	for button: Button in node.find_children("*", "Button", true, false):
		if button.text == text: return button
	return null


func _touch(target: Viewport, at: Vector2, pressed: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = at
	touch.pressed = pressed
	if target == root:
		Input.parse_input_event(touch)
		Input.flush_buffered_events()
		return
	# The engine's order for an emulated touch: the mouse event, then the touch.
	var mouse := InputEventMouseButton.new()
	mouse.position = at
	mouse.global_position = at
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	mouse.pressed = pressed
	target.push_input(mouse, true)
	target.push_input(touch, true)


func _touch_move(target: Viewport, at: Vector2, relative: Vector2) -> void:
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


func _tap(target: Viewport, at: Vector2) -> void:
	# A fingertip wobbles a few pixels; Android forwards every move.
	_touch(target, at, true)
	_touch_move(target, at + Vector2(2, 1), Vector2(2, 1))
	_touch_move(target, at + Vector2(1, 3), Vector2(-1, 2))
	_touch(target, at + Vector2(1, 3), false)
	await _settle()


func _drag(target: Viewport, start: Vector2, distance: Vector2) -> void:
	_touch(target, start, true)
	for step: int in range(1, 9):
		_touch_move(target, start + distance * float(step) / 8.0, distance / 8.0)
	_touch(target, start + distance, false)
	await _settle()


func _mouse_drag(target: Viewport, start: Vector2, distance: Vector2) -> void:
	# Mouse-only path, as a desktop pointer or a platform's emulated stream.
	var press := InputEventMouseButton.new()
	press.position = start
	press.global_position = start
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	target.push_input(press, true)
	for step: int in range(1, 9):
		var motion := InputEventMouseMotion.new()
		motion.position = start + distance * float(step) / 8.0
		motion.global_position = motion.position
		motion.relative = distance / 8.0
		motion.velocity = motion.relative * 60.0
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		target.push_input(motion, true)
	var release := press.duplicate() as InputEventMouseButton
	release.position = start + distance
	release.global_position = release.position
	release.button_mask = 0
	release.pressed = false
	target.push_input(release, true)
	await _settle()


func _action(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	root.push_input(event)


func _rest(scroll: ScrollContainer) -> void:
	# Let a released fling decelerate fully before the next measurement.
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

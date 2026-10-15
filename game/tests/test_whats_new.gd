extends SceneTree
## What's new in the app: the one-time Home card after an update, the Settings
## row and its page, Back from both, the layout on short wide screens, and taps
## that wobble the way a thumb does.
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const Changelog = preload("res://services/changelog.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

const WOBBLE := [Vector2(2, 3), Vector2(-1, 2), Vector2(1, 1)]
## 1600x720 is the layout an 800x360 window gets from the canvas_items/expand
## stretch; 1560x720 is a 2340x1080 phone.
const SIZES := [Vector2i(1560, 720), Vector2i(1600, 720)]

var checks := 0
var failures := 0
var _paths: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var original_touch := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	var current := Changelog.current_version()
	await _fresh_install(current)
	await _upgrade_without_key(current)
	await _upgrade_with_key()
	await _downgrade(current)
	await _waits_for_other_things()
	await _settings_row()
	await _card_to_full_page()
	for size: Vector2i in SIZES:
		await _layout(size)
	await _finger_on_home()
	Input.emulate_touch_from_mouse = original_touch
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU WHATS NEW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

## A save path; `saved` writes a save first, as an earlier version would have.
func _storage(saved: Variant = null) -> Storage:
	var path := "user://whats-new-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	_paths.append(path)
	var storage := Storage.new(path)
	storage.data.settings.sound = false
	storage.data.settings.haptics = false
	if saved is Dictionary:
		storage.data.merge(saved, true)
		_check(storage.flush(), "Prepare an earlier version's save")
	return storage

func _boot(storage: Storage, size: Vector2i = Vector2i(1560, 720), processing: bool = false) -> Array:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var app := Main.new()
	app.saves = storage
	viewport.add_child(app)
	app.set_process(processing)
	app.set_physics_process(false)
	app.identity_loading = false
	await _settle()
	return [viewport, app]

func _close(made: Array) -> void:
	(made[0] as Node).queue_free()
	await _settle()
	await create_timer(0.1).timeout

func _card(app: Node) -> Control:
	var card := app.ui.get_node_or_null("WhatsNewCard") as Control
	return card if card != null and not card.is_queued_for_deletion() else null

func _saved_key(storage: Storage) -> Variant:
	var loaded := Storage.new(storage.path)
	loaded.load_data()
	return loaded.data.get(Changelog.SAVE_KEY)

func _fresh_install(current: String) -> void:
	var storage := _storage()
	var made := await _boot(storage, Vector2i(1560, 720), true)
	var app: Node = made[1]
	for frame: int in range(10): await process_frame
	_check(app.mode == "home" and _card(app) == null, "A fresh install's first run shows no card")
	_check(app.saves.data.get(Changelog.SAVE_KEY) == current, "A fresh install remembers this version")
	_check(not FileAccess.file_exists(storage.path), "Remembering it writes nothing at launch")
	# The first ordinary save keeps the version, so the next launch stays quiet.
	_check(app.saves.update_values({}), "An ordinary save goes through")
	_check(_saved_key(storage) == current, "The first ordinary save stores the seen version")
	await _close(made)

func _upgrade_without_key(current: String) -> void:
	var storage := _storage({"completed": {"first-steps@1": true}})
	var made := await _boot(storage, Vector2i(1560, 720), true)
	var app: Node = made[1]
	for frame: int in range(10): await process_frame
	var card := _card(app)
	_check(card != null, "A save from before the card gets the card on Home")
	if card != null:
		_check(_has_label(card, PlayerCopy.WHATS_NEW_IN % current), "The card is titled with this version")
		_check(not _has_label_prefix(card, "Version "), "One version needs no heading per version")
		var entries := Changelog.load_entries(Changelog.channel(app.config))
		_check(not entries.is_empty() and _has_label(card, entries[0].paragraphs[0]), "The card shows this version's notes")
		var close := card.find_child("ModalCancel", true, false) as Button
		_check(close != null and close.text == "Close", "The card has a Close button")
		if close != null: await _tap(made[0], close.get_global_rect().get_center(), WOBBLE)
	_check(_card(app) == null and app.mode == "home", "Close dismisses the card and stays on Home")
	_check(_saved_key(storage) == current, "Closing the card stores the seen version")
	app._show_home()
	for frame: int in range(10): await process_frame
	_check(_card(app) == null, "The card does not come back in the same session")
	await _close(made)
	var again := await _boot(Storage.new(storage.path), Vector2i(1560, 720), true)
	for frame: int in range(10): await process_frame
	_check(_card(again[1]) == null, "The card does not come back on the next launch")
	await _close(again)

func _upgrade_with_key() -> void:
	var storage := _storage({Changelog.SAVE_KEY: "0.5.1"})
	var made := await _boot(storage)
	var app: Node = made[1]
	app._service_whats_new()
	await _settle()
	var card := _card(app)
	var expected := Changelog.since(Changelog.load_entries(Changelog.channel(app.config)), "0.5.1", Changelog.current_version())
	_check(card != null and expected.size() == Changelog.MAX_CARD_ENTRIES, "An update across several versions shows the card")
	if card != null:
		for entry: Dictionary in expected:
			_check(_has_label(card, PlayerCopy.WHATS_NEW_VERSION % entry.version), "The card heads each newer version: " + str(entry.version))
		_check(not _has_label(card, PlayerCopy.WHATS_NEW_VERSION % "0.5.1"), "The version already seen is left out")
		# Android Back closes the card like its Close button.
		app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		await _settle()
		_check(_card(app) == null and app.mode == "home", "Android Back closes the card")
	_check(_saved_key(storage) == Changelog.current_version(), "Back also stores the seen version")
	await _close(made)

func _downgrade(current: String) -> void:
	var storage := _storage({Changelog.SAVE_KEY: "99.0.0"})
	var made := await _boot(storage)
	var app: Node = made[1]
	app._service_whats_new()
	await _settle()
	_check(_card(app) == null, "A downgrade shows no card")
	_check(app.saves.data.get(Changelog.SAVE_KEY) == current, "A downgrade remembers this version")
	await _close(made)

func _waits_for_other_things() -> void:
	var storage := _storage({Changelog.SAVE_KEY: "0.6.0"})
	var made := await _boot(storage)
	var app: Node = made[1]
	# A waiting invite link goes first (its retry time keeps it from opening here).
	app.invite_link_pending = "x".repeat(22)
	app.invite_link_expires_ms = Time.get_ticks_msec() + 600000
	app.invite_link_retry_ms = Time.get_ticks_msec() + 600000
	app._service_whats_new()
	await _settle()
	_check(_card(app) == null, "The card waits while an invite link is waiting")
	app.invite_link_pending = ""
	app.notification_route_busy = true
	app._service_whats_new()
	await _settle()
	_check(_card(app) == null, "The card waits while a notification opens its room")
	app.notification_route_busy = false
	app._toast("Your save loaded from its backup.")
	app._service_whats_new()
	await _settle()
	_check(_card(app) == null, "The card waits while a message is on screen")
	app.toast_time = 0.0
	var other := _other_modal(app)
	app._service_whats_new()
	await _settle()
	_check(_card(app) == null, "The card never opens over another pop-up")
	other.close()
	await _settle()
	app._show_settings()
	app._service_whats_new()
	await _settle()
	_check(_card(app) == null, "The card only opens on Home")
	app._show_home()
	app._service_whats_new()
	await _settle()
	_check(_card(app) != null, "Back on Home with nothing else waiting, the card opens")
	# A screen change from outside, such as a notification, takes the card away.
	app._show_settings()
	app._service_whats_new()
	await _settle()
	_check(_card(app) == null, "Leaving Home closes the card")
	await _close(made)

func _other_modal(app: Node) -> Control:
	return load("res://presentation/in_game_modal.gd").open(app.ui, "OtherModal", "Other")

func _settings_row() -> void:
	var made := await _boot(_storage())
	var app: Node = made[1]
	app._show_settings()
	await _settle()
	var row := _button(app.overlay, PlayerCopy.WHATS_NEW)
	_check(row != null, "Settings has a What's new row")
	if row == null:
		await _close(made)
		return
	var scroll := row.get_parent()
	while scroll != null and not scroll is ScrollContainer: scroll = scroll.get_parent()
	if scroll is ScrollContainer:
		(scroll as ScrollContainer).ensure_control_visible(row)
		await _settle()
	var presses := [0]
	row.pressed.connect(func(): presses[0] += 1)
	await _tap(made[0], row.get_global_rect().get_center(), WOBBLE)
	_check(presses[0] == 1 and app.mode == "whats_new", "A wobbling tap on What's new opens its page once")
	var entries := Changelog.load_entries(Changelog.channel(app.config))
	var headings := 0
	for entry: Dictionary in entries:
		if _has_label(app.overlay, PlayerCopy.WHATS_NEW_VERSION % entry.version): headings += 1
	_check(entries.size() >= 2 and headings == entries.size(), "The page lists every version's notes (%d of %d)" % [headings, entries.size()])
	var back := _button(app.overlay, "Back")
	_check(back != null, "The page has Back")
	if back != null: await _tap(made[0], back.get_global_rect().get_center(), WOBBLE)
	_check(app.mode == "settings", "Back from What's new returns to Settings")
	app._show_whats_new()
	await _settle()
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _settle()
	_check(app.mode == "settings", "Android Back from What's new returns to Settings")
	await _close(made)

func _card_to_full_page() -> void:
	var storage := _storage({Changelog.SAVE_KEY: "0.6.0"})
	var made := await _boot(storage)
	var app: Node = made[1]
	app._service_whats_new()
	await _settle()
	var card := _card(app)
	var all := card.find_child("ModalConfirm", true, false) as Button if card != null else null
	_check(all != null and all.text == PlayerCopy.WHATS_NEW_SEE_ALL, "The card offers See all changes")
	if all != null:
		var presses := [0]
		all.pressed.connect(func(): presses[0] += 1)
		await _tap(made[0], all.get_global_rect().get_center(), WOBBLE)
		_check(presses[0] == 1 and app.mode == "whats_new" and _card(app) == null, "A wobbling tap on See all changes opens the full page once")
	_check(_saved_key(storage) == Changelog.current_version(), "Opening the full page stores the seen version")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _settle()
	_check(app.mode == "home", "Back from the page opened by the card returns Home")
	app._service_whats_new()
	await _settle()
	_check(_card(app) == null, "The card stays gone after the full page")
	await _close(made)

func _layout(size: Vector2i) -> void:
	var made := await _boot(_storage({Changelog.SAVE_KEY: "0.5.0"}), size)
	var app: Node = made[1]
	var screen := Rect2(Vector2.ZERO, Vector2(size))
	app._service_whats_new()
	for frame: int in range(4): await process_frame
	var card := _card(app)
	_check(card != null, "The card opens at " + str(size))
	if card != null:
		var panel := card.find_child("ModalPanel", true, false) as Control
		var scroll := card.find_child("WhatsNewCardScroll", true, false) as ScrollContainer
		var close := card.find_child("ModalCancel", true, false) as Control
		var all := card.find_child("ModalConfirm", true, false) as Control
		_check(panel != null and screen.encloses(panel.get_global_rect()), "The card fits on screen at " + str(size))
		_check(close != null and all != null and screen.encloses(close.get_global_rect()) and screen.encloses(all.get_global_rect()), "Both card buttons are on screen at " + str(size))
		_check(close != null and all != null and not close.get_global_rect().intersects(all.get_global_rect()), "The card buttons don't overlap at " + str(size))
		_check(close != null and close.size.y >= 48.0 and all.size.y >= 48.0, "The card buttons are full touch height at " + str(size))
		if scroll != null:
			var bar := scroll.get_v_scroll_bar()
			_check(bar.max_value > bar.page, "Three versions of notes scroll inside the card at " + str(size))
			_check(scroll.get_global_rect().end.y <= close.get_global_rect().position.y, "The notes scroll above the buttons, never under them, at " + str(size))
		else:
			_check(false, "The card notes sit in a scroll list")
		card.close()
		await _settle()
	app._show_whats_new()
	for frame: int in range(4): await process_frame
	var page := app.overlay.find_child("WhatsNewScroll", true, false) as ScrollContainer
	var back := _button(app.overlay, "Back")
	_check(page != null and screen.encloses(page.get_global_rect()), "The full page fits on screen at " + str(size))
	_check(back != null and screen.encloses(back.get_global_rect()) and page != null and back.get_global_rect().end.y <= page.get_global_rect().position.y, "Back stays above the scrolling notes at " + str(size))
	if page != null:
		var widest := 0.0
		for label: Label in page.find_children("*", "Label", true, false):
			widest = maxf(widest, label.get_global_rect().end.x)
		_check(widest <= page.get_global_rect().end.x + 0.5, "No line runs past the page edge at " + str(size))
		var longest := 0.0
		for label: Label in page.find_children("*", "Label", true, false):
			if label.autowrap_mode != TextServer.AUTOWRAP_OFF: longest = maxf(longest, label.size.x)
		_check(longest > 0.0 and longest <= 900.5, "Notes keep a reading width on wide screens at " + str(size))
		var bar := page.get_v_scroll_bar()
		_check(bar.max_value > bar.page, "The full list scrolls at " + str(size))
	await _close(made)

func _finger_on_home() -> void:
	var made := await _boot(_storage({Changelog.SAVE_KEY: "0.6.1"}))
	var viewport: SubViewport = made[0]
	var app: Node = made[1]
	app._whats_new_due = false
	app._show_home()
	await _settle()
	var solo := _button(app.overlay, "Play Solo")
	_check(solo != null, "Home shows Play Solo")
	if solo == null:
		await _close(made)
		return
	var opens := [0]
	solo.pressed.connect(func(): opens[0] += 1)
	var at := solo.get_global_rect().get_center()
	_touch(viewport, at, true)
	_move(viewport, at + Vector2(1, 2), Vector2(1, 2))
	app._whats_new_due = true
	app._service_whats_new()
	await _settle()
	_check(_card(app) == null and solo.is_pressed(), "The card waits while a finger is on a Home button")
	_touch(viewport, at + Vector2(1, 2), false)
	await _settle()
	_check(opens[0] == 1 and app.mode == "journey", "That tap still opens Play Solo once")
	app._service_whats_new()
	await _settle()
	_check(_card(app) == null, "Away from Home the card keeps waiting")
	app._show_home()
	app._service_whats_new()
	await _settle()
	_check(_card(app) != null, "Back on Home, the card opens")
	await _close(made)

func _button(node: Node, text: String) -> Button:
	for button: Button in node.find_children("*", "Button", true, false):
		if (button.text == text or button.tooltip_text == text) and button.is_visible_in_tree(): return button
	return null

func _has_label(node: Node, text: String) -> bool:
	for label: Label in node.find_children("*", "Label", true, false):
		if label.text == text: return true
	return false

func _has_label_prefix(node: Node, prefix: String) -> bool:
	for label: Label in node.find_children("*", "Label", true, false):
		if label.text.begins_with(prefix): return true
	return false

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
	var mouse := InputEventMouseButton.new()
	mouse.position = at
	mouse.global_position = at
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	mouse.pressed = pressed
	target.push_input(mouse, true)
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = at
	touch.pressed = pressed
	target.push_input(touch, true)

func _move(target: Viewport, at: Vector2, relative: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.relative = relative
	motion.velocity = relative * 60.0
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	target.push_input(motion, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = at
	drag.relative = relative
	drag.velocity = relative * 60.0
	target.push_input(drag, true)

func _settle() -> void:
	await process_frame
	await process_frame

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

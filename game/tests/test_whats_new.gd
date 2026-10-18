extends SceneTree
## What's new in the app: the Home button, its dot and tip after an update until
## the card is opened, the card from Home and from Settings, its link to every
## release's notes (none on iOS), Back, the layout at phone sizes, and taps that
## wobble the way a thumb does. Nothing opens on its own.
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const Changelog = preload("res://services/changelog.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PlatformSupport = preload("res://services/platform_support.gd")

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
	await _update(current)
	await _quiet_launches(current)
	await _settings_row(current)
	await _release_link()
	await _ios_card()
	await _card_rules()
	for size: Vector2i in SIZES:
		await _layout(size)
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

func _pill(app: Node) -> Button:
	return app.overlay.get_node_or_null("HomeWhatsNew") as Button

func _marked(pill: Node) -> bool:
	for name: String in ["WhatsNewDot", "WhatsNewPointer", "WhatsNewTip"]:
		var mark := pill.get_node_or_null(name) if pill != null else null
		if mark == null or mark.is_queued_for_deletion(): return false
	return true

func _saved_key(storage: Storage) -> Variant:
	var loaded := Storage.new(storage.path)
	loaded.load_data()
	return loaded.data.get(Changelog.SAVE_KEY)

func _entry(app: Node) -> Dictionary:
	var entries := Changelog.load_entries(Changelog.channel(app.config))
	return entries[0] if not entries.is_empty() else {}

func _fresh_install(current: String) -> void:
	var storage := _storage()
	var made := await _boot(storage, Vector2i(1560, 720), true)
	var app: Node = made[1]
	for frame: int in range(10): await process_frame
	_check(app.mode == "home" and _card(app) == null, "A fresh install's first run shows no card")
	_check(_pill(app) != null and _pill(app).is_visible_in_tree(), "Home always has the What's new button")
	_check(not _marked(_pill(app)) and not app.whats_new_unseen(), "A fresh install has no dot and no tip")
	_check(app.saves.data.get(Changelog.SAVE_KEY) == current, "A fresh install remembers this version")
	_check(not FileAccess.file_exists(storage.path), "Remembering it writes nothing at launch")
	# The first ordinary save keeps the version, so the next launch stays quiet.
	_check(app.saves.update_values({}), "An ordinary save goes through")
	_check(_saved_key(storage) == current, "The first ordinary save stores the seen version")
	await _close(made)

func _update(current: String) -> void:
	var storage := _storage({"completed": {"first-steps@1": true}})
	var made := await _boot(storage, Vector2i(1560, 720), true)
	var app: Node = made[1]
	for frame: int in range(15): await process_frame
	app._show_home()
	for frame: int in range(10): await process_frame
	var pill := _pill(app)
	_check(_card(app) == null, "Nothing pops up on Home after an update")
	_check(app.whats_new_unseen() and _marked(pill), "After an update the button has its dot and tip")
	var tip := pill.get_node_or_null("WhatsNewTip") if pill != null else null
	_check(tip != null and _has_label(tip, PlayerCopy.WHATS_NEW_TIP % current), "The tip names this version")
	_check(_saved_key(storage) == null, "The notes stay unseen in the save until the card opens")
	# Older saves with a seen version from before this one get the marks too.
	var older := await _boot(_storage({Changelog.SAVE_KEY: "0.5.1"}))
	_check(_marked(_pill(older[1])), "An update from an older seen version shows the dot and tip")
	await _close(older)
	if pill == null:
		await _close(made)
		return
	var presses := [0]
	pill.pressed.connect(func(): presses[0] += 1)
	await _tap(made[0], pill.get_global_rect().get_center(), WOBBLE)
	var card := _card(app)
	_check(presses[0] == 1 and card != null, "A wobbling tap on the button opens the card once")
	_check(not app.whats_new_unseen() and not _marked(pill) and _saved_key(storage) == current, "Opening the card clears the dot and tip and stores the version")
	_check(is_instance_valid(pill) and pill.is_inside_tree() and pill == _pill(app), "Home keeps the same button; nothing is rebuilt under the finger")
	if card != null:
		var entry := _entry(app)
		_check(_has_label(card, PlayerCopy.WHATS_NEW) and _has_label(card, PlayerCopy.WHATS_NEW_VERSION % current), "The card says What's new and names this version")
		var lines := 0
		for item: Dictionary in entry.get("highlights", []):
			if _has_label(card, str(item.text)): lines += 1
		_check(lines > 0 and lines == entry.highlights.size(), "The card lists this version's highlights")
		for text: String in entry.get("paragraphs", []):
			_check(not _has_label(card, text), "The card leaves the long notes out")
		_check(card.find_children("*", "ScrollContainer", true, false).is_empty(), "The card never needs to scroll")
		var got := card.find_child("WhatsNewGotIt", true, false) as Button
		_check(got != null and got.text == PlayerCopy.WHATS_NEW_GOT_IT, "The card has Got it")
		if got != null: await _tap(made[0], got.get_global_rect().get_center(), WOBBLE)
	_check(_card(app) == null and app.mode == "home", "Got it closes the card and stays on Home")
	_check(_pill(app) != null and _pill(app).is_visible_in_tree() and not _marked(_pill(app)), "The button stays, without the dot")
	await _tap(made[0], pill.get_global_rect().get_center(), WOBBLE)
	_check(_card(app) != null and presses[0] == 2, "The card opens again from the button")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _settle()
	_check(_card(app) == null and app.mode == "home", "Android Back closes the card")
	await _close(made)
	var again := await _boot(Storage.new(storage.path), Vector2i(1560, 720), true)
	for frame: int in range(10): await process_frame
	_check(_card(again[1]) == null and not _marked(_pill(again[1])), "The next launch has no dot and no card")
	await _close(again)

func _quiet_launches(current: String) -> void:
	for saved: String in [current, "99.0.0"]:
		var made := await _boot(_storage({Changelog.SAVE_KEY: saved}))
		var app: Node = made[1]
		_check(not _marked(_pill(app)) and not app.whats_new_unseen(), "No dot when the saved version is " + saved)
		_check(app.saves.data.get(Changelog.SAVE_KEY) == current, "The version on record is this one after launching with " + saved)
		await _close(made)
	var odd := await _boot(_storage({Changelog.SAVE_KEY: "0.6.0"}))
	var odd_app: Node = odd[1]
	odd_app.saves.data[Changelog.SAVE_KEY] = [1]
	odd_app._remember_whats_new()
	_check(odd_app.saves.data.get(Changelog.SAVE_KEY) == current, "A recorded version that is not a string is replaced by this one when the notes are opened")
	await _close(odd)

func _settings_row(current: String) -> void:
	var storage := _storage({Changelog.SAVE_KEY: "0.6.0"})
	var made := await _boot(storage)
	var app: Node = made[1]
	app.settings_flow.show_settings("about")
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
	_check(presses[0] == 1 and _card(app) != null and app.mode == "settings", "A wobbling tap on the Settings row opens the same card once, over Settings")
	_check(not app.whats_new_unseen() and _saved_key(storage) == current, "Opening it from Settings also counts as seen")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _settle()
	_check(_card(app) == null and app.mode == "settings", "Android Back closes the card and stays in Settings")
	app._show_home()
	await _settle()
	_check(not _marked(_pill(app)), "Home has no dot after the card was opened from Settings")
	await _close(made)

func _release_link() -> void:
	var made := await _boot(_storage())
	var app: Node = made[1]
	var opened: Array[String] = []
	app.external_link_opener = func(url: String) -> void: opened.append(url)
	app._open_whats_new_card()
	await _settle()
	var card := _card(app)
	var all := card.find_child("WhatsNewSeeAll", true, false) as Button if card != null else null
	_check(all != null and all.text == PlayerCopy.WHATS_NEW_SEE_ALL, "The card offers See all changes")
	if all != null:
		await _tap(made[0], all.get_global_rect().get_center(), WOBBLE)
		_check(opened == [Changelog.RELEASES_URL] and Changelog.RELEASES_URL == "https://github.com/aamir-azeez/after-you/releases", "See all changes opens the GitHub releases page once")
		_check(_card(app) == null and app.mode == "home", "The card closes behind the link")
	_check(app.mode == "home" and app.overlay.find_child("WhatsNewScroll", true, false) == null, "There is no in-app changelog page")
	await _close(made)

func _ios_card() -> void:
	PlatformSupport.override_platform = PlatformSupport.IOS
	var made := await _boot(_storage())
	var app: Node = made[1]
	app._open_whats_new_card()
	await _settle()
	var card := _card(app)
	_check(card != null, "iOS builds have the card")
	if card != null:
		_check(card.find_child("WhatsNewSeeAll", true, false) == null, "iOS builds don't link to the GitHub releases")
		var got := card.find_child("WhatsNewGotIt", true, false) as Control
		var buttons := card.find_child("WhatsNewHighlights", true, false)
		_check(got != null and buttons != null and got.get_parent().get_child_count() == 1, "Got it is the iOS card's only button")
	PlatformSupport.override_platform = ""
	await _close(made)

func _card_rules() -> void:
	var made := await _boot(_storage())
	var app: Node = made[1]
	app._show_journey()
	app._open_whats_new_card()
	await _settle()
	_check(_card(app) == null, "The card only opens from Home or Settings")
	app._show_home()
	app._open_whats_new_card()
	app._open_whats_new_card()
	await _settle()
	var cards := 0
	for child: Node in app.ui.get_children():
		if str(child.name).begins_with("WhatsNewCard") and not child.is_queued_for_deletion(): cards += 1
	_check(cards == 1, "Opening twice still shows one card")
	# A screen change from outside, such as a notification, takes the card away.
	app._show_journey()
	app._service_whats_new()
	await _settle()
	_check(_card(app) == null, "Leaving the screen that opened it closes the card")
	await _close(made)

func _layout(size: Vector2i) -> void:
	var made := await _boot(_storage({Changelog.SAVE_KEY: "0.5.0"}), size)
	var app: Node = made[1]
	var screen := Rect2(Vector2.ZERO, Vector2(size))
	app._show_home()
	for frame: int in range(4): await process_frame
	var pill := _pill(app)
	var settings := app.overlay.get_node_or_null("HomeSettings") as Control
	var menu := app.overlay.get_node_or_null("HomeMenu") as Control
	var explore := _button(app.overlay, "Explore")
	_check(pill != null and settings != null and menu != null, "Home has the What's new button, Settings and its menu at " + str(size))
	if pill == null or settings == null or menu == null:
		await _close(made)
		return
	var box := pill.get_global_rect()
	_check(screen.encloses(box) and box.size.y >= 54.0, "The button is on screen at full touch height at " + str(size))
	_check(is_equal_approx(settings.get_global_rect().position.x - box.end.x, 16.0) and is_equal_approx(box.position.y, settings.get_global_rect().position.y), "The button sits 16 left of Settings, level with it, at " + str(size))
	_check(not box.intersects(menu.get_global_rect()) and (explore == null or not box.intersects(explore.get_global_rect())), "The button keeps clear of the Home menu and Explore at " + str(size))
	var tip := pill.get_node_or_null("WhatsNewTip") as Control
	_check(tip != null and screen.encloses(tip.get_global_rect()) and tip.get_global_rect().position.y >= box.end.y, "The tip sits on screen under the button at " + str(size))
	_check(tip != null and tip.mouse_filter == Control.MOUSE_FILTER_IGNORE, "The tip never takes a tap")
	var presses := [0]
	pill.pressed.connect(func(): presses[0] += 1)
	await _tap(made[0], box.get_center(), WOBBLE)
	for frame: int in range(4): await process_frame
	var card := _card(app)
	_check(presses[0] == 1 and card != null, "A wobbling tap on the button opens the card once at " + str(size))
	if card != null:
		var panel := card.find_child("ModalPanel", true, false) as Control
		var got := card.find_child("WhatsNewGotIt", true, false) as Control
		var all := card.find_child("WhatsNewSeeAll", true, false) as Control
		_check(panel != null and screen.encloses(panel.get_global_rect()), "The card fits on screen without scrolling at " + str(size))
		_check(got != null and all != null and screen.encloses(got.get_global_rect()) and screen.encloses(all.get_global_rect()), "Both card buttons are on screen at " + str(size))
		_check(got != null and all != null and not got.get_global_rect().intersects(all.get_global_rect()) and all.get_global_rect().position.x < got.get_global_rect().position.x, "See all changes sits left of Got it, apart, at " + str(size))
		_check(got != null and got.size.y >= 48.0 and all.size.y >= 48.0, "The card buttons are full touch height at " + str(size))
		var bottom := 0.0
		var list := card.find_child("WhatsNewHighlights", true, false)
		if list != null:
			for label: Label in list.find_children("*", "Label", true, false): bottom = maxf(bottom, label.get_global_rect().end.y)
		_check(list != null and bottom > 0.0 and got != null and bottom <= got.get_global_rect().position.y, "The highlights end above the buttons at " + str(size))
	await _close(made)

func _button(node: Node, text: String) -> Button:
	for button: Button in node.find_children("*", "Button", true, false):
		if (button.text == text or button.tooltip_text == text or (button.text.is_empty() and button.accessibility_name == text)) and button.is_visible_in_tree(): return button
	return null

func _has_label(node: Node, text: String) -> bool:
	for label: Label in node.find_children("*", "Label", true, false):
		if label.text == text: return true
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

extends SceneTree
## What's new in the app: the Home button, its dot and tip after an update until
## the card is opened, the card from Home and from Settings, its Earlier versions
## list (built when opened, rows that open their highlights, Back to the card),
## its link to every release's notes at the end of that list (none on iOS), Back,
## the layout at phone sizes, and taps that wobble the way a thumb does. Nothing
## opens on its own.
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const Changelog = preload("res://services/changelog.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const WhatsNewCard = preload("res://presentation/whats_new_card.gd")
const WhatsNewHistory = preload("res://presentation/whats_new_history.gd")

const WOBBLE := [Vector2(2, 3), Vector2(-1, 2), Vector2(1, 1)]
## 1600x720 is the layout an 800x360 window gets from the canvas_items/expand
## stretch; 1560x720 is a 2340x1080 phone; 1280x720 is a 16:9 phone.
const SIZES := [Vector2i(1560, 720), Vector2i(1600, 720), Vector2i(1280, 720)]

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
	await _earlier_versions()
	await _broken_archive()
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
	return app.overlay.find_child("HomeWhatsNew", true, false) as Button

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
	_check(card != null and card.find_child("WhatsNewSeeAll", true, false) == null, "See all changes is not on the card itself")
	var more := card.find_child("WhatsNewEarlier", true, false) as Button if card != null else null
	if more != null: await _tap(made[0], more.get_global_rect().get_center(), WOBBLE)
	var all := card.find_child("WhatsNewSeeAll", true, false) as Button if card != null else null
	_check(all != null and all.text == PlayerCopy.WHATS_NEW_SEE_ALL, "Earlier versions ends with See all changes")
	if all != null:
		var scroll := card.find_child("WhatsNewEarlierScroll", true, false) as ScrollContainer
		scroll.ensure_control_visible(all)
		await _settle()
		await _tap(made[0], all.get_global_rect().get_center(), WOBBLE)
		_check(opened == [Changelog.RELEASES_URL] and Changelog.RELEASES_URL == "https://github.com/aamir-azeez/after-you/releases", "See all changes opens the GitHub releases page once")
		_check(_card(app) == null and app.mode == "home", "The card closes behind the link")
	_check(app.mode == "home" and app.overlay.find_child("WhatsNewScroll", true, false) == null, "Earlier versions lives in the card, not on a page of its own")
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
		var got := card.find_child("WhatsNewGotIt", true, false) as Control
		var more := card.find_child("WhatsNewEarlier", true, false) as Control
		_check(got != null and more != null and got.get_parent() == more.get_parent() and got.get_parent().get_child_count() == 2, "The iOS card has the same footer as every build: Earlier versions and Got it")
		WhatsNewCard.show_earlier(card, func() -> Array: return Changelog.earlier_entries(Changelog.current_version()), Callable())
		await _settle()
		_check(card.find_child("WhatsNewEarlierList", true, false) != null, "iOS builds have Earlier versions")
		_check(card.find_child("WhatsNewSeeAll", true, false) == null, "iOS builds don't link to the GitHub releases, on the card or in the list")
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
	var settings := app.overlay.find_child("HomeSettings", true, false) as Control
	var menu := app.overlay.get_node_or_null("HomeMenu") as Control
	var invite := app.overlay.find_child("HomeInvite", true, false) as Control
	_check(pill != null and settings != null and menu != null and invite != null, "Home has the What's new button, Settings and its menu at " + str(size))
	if pill == null or settings == null or menu == null or invite == null:
		await _close(made)
		return
	var box := pill.get_global_rect()
	_check(screen.encloses(box) and box.size.y >= 48.0, "The button is on screen at full touch height at " + str(size))
	_check(box.end.x < settings.get_global_rect().position.x and absf(box.get_center().y - settings.get_global_rect().get_center().y) <= 1.0, "The button sits left of Settings in the panel's bottom row at " + str(size))
	_check(menu.is_ancestor_of(pill) and box.position.y >= invite.get_global_rect().end.y, "The button is in the Home menu, under Invite your friends, at " + str(size))
	var tip := pill.get_node_or_null("WhatsNewTip") as Control
	_check(tip != null and screen.encloses(tip.get_global_rect()) and tip.get_global_rect().position.x >= box.end.x and not tip.get_global_rect().intersects(invite.get_global_rect()) and not tip.get_global_rect().intersects(settings.get_global_rect()), "The tip sits on screen beside the button, clear of Invite and Settings, at " + str(size))
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
		var all := card.find_child("WhatsNewEarlier", true, false) as Control
		_check(panel != null and screen.encloses(panel.get_global_rect()), "The card fits on screen without scrolling at " + str(size))
		_check(got != null and all != null and screen.encloses(got.get_global_rect()) and screen.encloses(all.get_global_rect()), "Both card buttons are on screen at " + str(size))
		_check(got != null and all != null and not got.get_global_rect().intersects(all.get_global_rect()) and all.get_global_rect().position.x < got.get_global_rect().position.x, "Earlier versions sits left of Got it, apart, at " + str(size))
		_check(got != null and got.size.y >= 48.0 and all.size.y >= 48.0, "The card buttons are full touch height at " + str(size))
		var bottom := 0.0
		var list := card.find_child("WhatsNewHighlights", true, false)
		if list != null:
			for label: Label in list.find_children("*", "Label", true, false): bottom = maxf(bottom, label.get_global_rect().end.y)
		_check(list != null and bottom > 0.0 and got != null and bottom <= got.get_global_rect().position.y, "The highlights end above the buttons at " + str(size))
		if all != null:
			await _tap(made[0], all.get_global_rect().get_center(), WOBBLE)
			await _settle()
			var scroll := card.find_child("WhatsNewEarlierScroll", true, false) as Control
			var back := card.find_child("WhatsNewBack", true, false) as Control
			var close := card.find_child("ModalClose", true, false) as Control
			_check(panel != null and screen.encloses(panel.get_global_rect()), "The Earlier versions card stays on screen at " + str(size))
			_check(scroll != null and scroll.size.y >= 200.0 and panel.get_global_rect().encloses(scroll.get_global_rect()), "The list has room to scroll inside the card at " + str(size))
			_check(back != null and close != null and screen.encloses(back.get_global_rect()) and back.size.y >= 48.0 and close.size.y >= 48.0, "Back and Close are on screen at full touch height at " + str(size))
			var row := _rows(card)[0] if not _rows(card).is_empty() else null
			_check(row != null and row.size.y >= 48.0 and scroll.get_global_rect().encloses(row.get_global_rect()), "The first version row shows at full touch height at " + str(size))
	await _close(made)

## Every version the app knows on this build, newest first.
func _all_entries() -> Array:
	return Changelog.load_entries(Changelog.GITHUB)

func _rows(card: Node) -> Array[Button]:
	var rows: Array[Button] = []
	var list := card.find_child("WhatsNewVersions", true, false) if card != null else null
	if list == null: return rows
	for button: Node in list.find_children("WhatsNewVersionRow", "Button", true, false): rows.append(button)
	return rows

func _details(row: Control) -> Control:
	return row.get_parent().get_node_or_null("WhatsNewVersionHighlights") as Control

func _earlier_versions() -> void:
	var made := await _boot(_storage({Changelog.SAVE_KEY: "0.6.0"}), Vector2i(1280, 720), true)
	var app: Node = made[1]
	app._show_home()
	await _settle()
	app._open_whats_new_card()
	await _settle()
	var card := _card(app)
	var more := card.find_child("WhatsNewEarlier", true, false) as Button if card != null else null
	_check(more != null and more.text == PlayerCopy.WHATS_NEW_EARLIER, "The card offers Earlier versions")
	_check(card != null and card.find_child("WhatsNewEarlierList", true, false) == null, "The list is not built until it is opened")
	if more == null:
		await _close(made)
		return
	var presses := [0]
	more.pressed.connect(func(): presses[0] += 1)
	await _tap(made[0], more.get_global_rect().get_center(), WOBBLE)
	var view := card.find_child("WhatsNewEarlierList", true, false) as Control
	var body := card.find_child("WhatsNewCardBody", true, false) as Control
	_check(presses[0] == 1 and view != null and view.is_visible_in_tree() and not body.visible, "A wobbling tap on Earlier versions turns the card into the list once")
	_check(card.title_label.text == PlayerCopy.WHATS_NEW_EARLIER_TITLE and not card.subtitle_label.visible, "The list has its own title and no version line")
	var back := card.find_child("WhatsNewBack", true, false) as Button
	_check(back != null and not back.has_focus(true) and not more.has_focus(true), "A tap draws no focus ring on the back arrow")
	var earlier := Changelog.earlier_entries(Changelog.current_version())
	var rows := _rows(card)
	_check(not earlier.is_empty() and rows.size() == earlier.size(), "The list has a row for every earlier version (%d)" % rows.size())
	var ordered := rows.size() == earlier.size()
	for index: int in range(mini(rows.size(), earlier.size())):
		var entry: Dictionary = earlier[index]
		if not _has_label(rows[index], WhatsNewHistory.version_text(entry.version)) or not _has_label(rows[index], WhatsNewHistory.date_text(entry.date)): ordered = false
	_check(ordered, "Rows show each version and its date, newest first")
	_check(not earlier.is_empty() and earlier[-1].version == "0.1.3" and _has_label(rows[-1], "Version 0.1.3") and _has_label(rows[-1], "14 Sep 2026"), "The list reaches back to the first release, 0.1.3 on 14 Sep 2026")
	var preview := -1
	for index: int in range(earlier.size()):
		if earlier[index].version == "0.2.0-preview9": preview = index
	_check(preview >= 0 and preview < rows.size() and _has_label(rows[preview], "Version 0.2.0 preview 9") and _has_label(rows[preview], "15 Sep 2026"), "A preview build has its own row: Version 0.2.0 preview 9")
	_check(WhatsNewHistory.version_text("0.2.0-preview9") == PlayerCopy.WHATS_NEW_VERSION_PREVIEW % ["0.2.0", 9] and WhatsNewHistory.version_text("0.4.16") == PlayerCopy.WHATS_NEW_VERSION % "0.4.16", "Row lines come from the player copy")
	var built := 0
	for row: Button in rows:
		if _details(row) != null: built += 1
	_check(built == 0, "No version's highlights are built before its row opens")
	var scroll := card.find_child("WhatsNewEarlierScroll", true, false) as ScrollContainer
	# A drag across the rows scrolls the list and opens nothing.
	var start := rows[2].get_global_rect().get_center()
	_touch(made[0], start, true)
	var point := start
	for step: int in range(12):
		point += Vector2(0, -14)
		_move(made[0], point, Vector2(0, -14))
		await process_frame
	_touch(made[0], point, false)
	await _settle()
	built = 0
	for row: Button in rows:
		if _details(row) != null: built += 1
	_check(scroll.scroll_vertical > 0 and built == 0, "A drag that starts on a row scrolls the list and opens nothing")
	await _rest(scroll)
	scroll.scroll_vertical = 0
	await _settle()
	var first := rows[0]
	await _tap(made[0], first.get_global_rect().get_center(), WOBBLE)
	await _settle()
	var details := _details(first)
	var lines := 0
	for item: Dictionary in earlier[0].highlights:
		if details != null and _has_label(details, str(item.text)): lines += 1
	_check(details != null and details.is_visible_in_tree() and lines == earlier[0].highlights.size(), "A wobbling tap on a row opens that version's highlights")
	_check(details != null and details.find_children("*", "PanelContainer", true, false).size() == earlier[0].highlights.size(), "Each highlight has its icon tile, as on the card")
	_check(_details(rows[1]) == null, "Opening one row builds only that row")
	await _tap(made[0], first.get_global_rect().get_center(), WOBBLE)
	_check(details != null and not details.visible and _details(first) == details, "A second tap closes the row and keeps what it built")
	await _tap(made[0], first.get_global_rect().get_center(), WOBBLE)
	_check(details.visible, "A third tap opens it again")
	_check(back != null and back.is_visible_in_tree() and card.find_child("WhatsNewGift", true, false).visible == false, "The list has a back arrow where the gift was")
	await _tap(made[0], back.get_global_rect().get_center(), WOBBLE)
	_check(_card(app) == card and body.visible and not view.visible and _has_label(card, PlayerCopy.WHATS_NEW_VERSION % Changelog.current_version()) and not back.visible, "A wobbling tap on the back arrow returns to the card")
	_check(not more.has_focus(true), "A tap back draws no focus ring on Earlier versions")
	await _tap(made[0], more.get_global_rect().get_center(), WOBBLE)
	_check(card.find_children("WhatsNewEarlierList", "", true, false).size() == 1 and view.visible and details.visible, "Opening the list again reuses it, with the open row still open")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _settle()
	_check(_card(app) == card and body.visible and not view.visible and app.mode == "home", "Android Back from the list returns to the card")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _settle()
	_check(_card(app) == null and app.mode == "home", "Android Back from the card closes it")
	# Escape walks back the same way.
	app._open_whats_new_card()
	await _settle()
	card = _card(app)
	WhatsNewCard.show_earlier(card, func() -> Array: return earlier, Callable())
	await _settle()
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	made[0].push_input(escape)
	await _settle()
	_check(_card(app) == card and (card.find_child("WhatsNewCardBody", true, false) as Control).visible, "Escape from the list returns to the card")
	# Close works from the list, and opening twice never stacks.
	WhatsNewCard.show_earlier(card, func() -> Array: return earlier, Callable())
	app._open_whats_new_card()
	await _settle()
	var cards := 0
	for child: Node in app.ui.get_children():
		if str(child.name).begins_with("WhatsNewCard") and not child.is_queued_for_deletion(): cards += 1
	_check(cards == 1 and _card(app) == card, "Opening What's new while the list shows keeps one card")
	var close := card.find_child("ModalClose", true, false) as Button
	await _tap(made[0], close.get_global_rect().get_center(), WOBBLE)
	_check(_card(app) == null and app.mode == "home", "Close shuts the card from the list")
	await _close(made)

## A broken archive only hides the older rows: the card and the file's versions stay.
func _broken_archive() -> void:
	var path := "user://whats-new-archive-" + Crypto.new().generate_random_bytes(6).hex_encode() + ".json"
	_paths.append(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{\"schema_version\": 1, \"entries\": [{\"version\": \"bad\"}]}")
	file.close()
	var made := await _boot(_storage())
	var app: Node = made[1]
	var entries := _all_entries()
	var card := WhatsNewCard.open(app.ui, entries[0], func() -> Array: return Changelog.earlier_entries(entries[0].version, Changelog.PATH, path), Callable())
	await _settle()
	var lines := 0
	for item: Dictionary in entries[0].highlights:
		if _has_label(card, str(item.text)): lines += 1
	_check(lines == entries[0].highlights.size(), "With a broken archive the card still lists this version's highlights")
	WhatsNewCard.show_earlier(card, func() -> Array: return Changelog.earlier_entries(entries[0].version, Changelog.PATH, path), Callable())
	await _settle()
	_check(_rows(card).size() == entries.size() - 1, "With a broken archive the list keeps the file's earlier versions")
	card.close(false)
	await _close(made)

## Waits for a flung list to stop.
func _rest(scroll: ScrollContainer) -> void:
	var last := -1
	for frame: int in range(240):
		await process_frame
		if scroll.scroll_vertical == last: return
		last = scroll.scroll_vertical

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

extends SceneTree

const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const Catalog = preload("res://services/licenses.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _settle() -> void:
	await process_frame
	await process_frame


func _button(node: Node, caption: String) -> Button:
	for candidate: Button in node.find_children("*", "Button", true, false):
		if candidate.text == caption:
			return candidate
	return null


func _scroll(node: Node) -> ScrollContainer:
	for candidate: ScrollContainer in node.find_children("*", "ScrollContainer", true, false):
		return candidate
	return null


func _within(control: Control, area: Rect2, description: String) -> void:
	_check(control != null and area.grow(0.5).encloses(control.get_global_rect()), description)


func _settings_fit(app: Node, area: Rect2) -> void:
	app._show_settings()
	await _settle()
	var account := _button(app.overlay, "Account & recovery")
	var licenses := _button(app.overlay, "Licenses")
	var done := _button(app.overlay, "Done")
	_within(account, area, "Account remains visible at " + str(area.size))
	_within(licenses, area, "Licenses remains visible at " + str(area.size))
	_within(done, area, "Done remains visible at " + str(area.size))
	if account == null or licenses == null:
		return
	var navigation: Array[Button] = []
	for caption: String in ["Account & recovery", "Notifications", "Tester code", "Community & privacy", "Licenses", "Done"]:
		var action := _button(app.overlay, caption)
		_within(action, area, "Settings action remains visible: " + caption)
		if action != null:
			for previous: Button in navigation:
				_check(not action.get_global_rect().intersects(previous.get_global_rect()),
					"Settings actions do not overlap: " + caption + " / " + previous.text)
			navigation.append(action)
	for toggle: CheckButton in app.overlay.find_children("*", "CheckButton", true, false):
		_within(toggle, area, "Existing settings toggle remains visible: " + toggle.text)
	licenses.pressed.emit()
	await _settle()
	_check(app.mode == "licenses", "The Settings action opens the licenses list")


func _list_fit(app: Node, entries: Array[Dictionary], area: Rect2) -> void:
	var scroll := _scroll(app.overlay)
	_within(scroll, area, "Component list is contained inside the viewport")
	_within(_button(app.overlay, "Back to settings"), area, "List Back stays outside the scrolling entries")
	if scroll == null:
		return
	var bar := scroll.get_v_scroll_bar()
	_check(bar.max_value > bar.page, "The real catalog uses a scrollable component list")
	var actual_titles: Array[String] = []
	for button: Button in scroll.find_children("*", "Button", true, false):
		actual_titles.append(button.text)
	var expected_titles: Array[String] = []
	for entry: Dictionary in entries:
		expected_titles.append(str(entry.title))
	_check(actual_titles == expected_titles, "Every catalog entry appears once in the component list")
	if not entries.is_empty():
		var last := _button(scroll, str(entries[-1].title))
		if last != null:
			scroll.ensure_control_visible(last)
			await _settle()
			_within(last, scroll.get_global_rect(), "The final catalog entry can be scrolled fully into view")
			_check(scroll.scroll_vertical > 0, "Reaching the final entry actually changes scroll position")


func _open_entry(app: Node, entry: Dictionary, area: Rect2) -> void:
	app._show_licenses()
	await _settle()
	var scroll := _scroll(app.overlay)
	var choice := _button(app.overlay, str(entry.title))
	_check(choice != null and scroll != null, "A reachable component action exists: " + str(entry.title))
	if choice == null or scroll == null:
		return
	scroll.ensure_control_visible(choice)
	await _settle()
	_within(choice, scroll.get_global_rect(), "Component action is reachable after scrolling: " + str(entry.title))
	choice.pressed.emit()
	await _settle()
	_check(app.mode == "license_text", "Selecting a component opens its notice")
	var text := app.overlay.find_child("LicenseText", true, false) as RichTextLabel
	_check(text != null, "The notice has a text surface")
	if text == null:
		return
	_within(text, area, "License text stays within the viewport")
	_within(_button(app.overlay, "Back to licenses"), area, "Text Back is visible without scrolling the notice")
	_check(text.text == str(entry.text) and not text.bbcode_enabled,
		"The selected component's entire notice is presented as plain text: " + str(entry.title))
	_check(text.selection_enabled and text.scroll_active, "Notice text permits selection and scrolling")
	text.select_all()
	_check(text.get_selected_text().replace("\r\n", "\n").strip_edges()
		== str(entry.text).replace("\r\n", "\n").strip_edges(),
		"Selecting all retains the full notice, including its final paragraph")
	text.deselect()
	var bar := text.get_v_scroll_bar()
	if bar.max_value > bar.page:
		bar.value = bar.max_value
		await _settle()
		_check(bar.value > 0 and is_equal_approx(bar.value, bar.max_value - bar.page),
			"A long notice can scroll to its actual end")
	var back := _button(app.overlay, "Back to licenses")
	if back != null:
		back.pressed.emit()
		await _settle()
		_check(app.mode == "licenses", "Text Back returns to the component list")


func _run() -> void:
	var entries: Array[Dictionary] = Catalog.entries()
	_check(not entries.is_empty(), "The bundled catalog contains notices")
	var all_files_present := true
	for path: String in Catalog.file_paths():
		all_files_present = all_files_present and FileAccess.file_exists(path)
	_check(all_files_present, "Every catalog notice is present before opening the UI")
	if entries.is_empty():
		quit(1)
		return
	var longest: Dictionary = entries[0]
	for entry: Dictionary in entries:
		if str(entry.text).length() > str(longest.text).length():
			longest = entry
	var path := "user://license-ui-test-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var saves := Storage.new(path)
	saves.data.settings.sound = false
	saves.data.settings.haptics = false
	_check(saves.flush(), "The isolated test save is prepared")
	var disk_before := FileAccess.get_file_as_string(path)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var app := Main.new()
	app.saves = saves
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	var state_before := JSON.stringify(app.saves.data)
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1560, 720), Vector2i(1280, 960)]:
		viewport.size = size
		await _settle()
		var area := Rect2(Vector2.ZERO, Vector2(size))
		await _settings_fit(app, area)
		await _list_fit(app, entries, area)
		# Verify every loop-bound action at the smallest viewport. The two other
		# shapes exercise the longest text without repeating the entire catalog.
		if size == Vector2i(1280, 720):
			for entry: Dictionary in entries:
				await _open_entry(app, entry, area)
		else:
			await _open_entry(app, longest, area)
		var back := _button(app.overlay, "Back to settings")
		if back != null:
			back.pressed.emit()
			await _settle()
		_check(app.mode == "settings", "List Back returns to Settings at " + str(size))
	app._show_license(longest)
	await _settle()
	var long_text := app.overlay.find_child("LicenseText", true, false) as RichTextLabel
	_check(long_text != null and long_text.get_v_scroll_bar().max_value > long_text.get_v_scroll_bar().page,
		"The largest real notice requires scrolling, so the long-text path is exercised")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _settle()
	_check(app.mode == "licenses", "Android Back leaves a notice for the component list")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _settle()
	_check(app.mode == "settings", "Android Back leaves the component list for Settings")
	_check(JSON.stringify(app.saves.data) == state_before, "Browsing and selecting licenses do not mutate save data")
	_check(FileAccess.get_file_as_string(path) == disk_before, "License navigation does not rewrite the saved file")
	viewport.queue_free()
	await _settle()
	await create_timer(0.5).timeout
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU LICENSES UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

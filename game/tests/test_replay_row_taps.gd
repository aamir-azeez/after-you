extends "res://tests/test_replay_loading_feedback.gd"
## Replays row tap targets through real viewport input routing. Each Solo row
## is drawn as a card; a tap anywhere on it, including its bottom fifth over
## the art and the caption, selects that replay (or opens it on a narrow
## screen), and a tap on the bottom fifth of a part chip switches the part.
## A drag that starts on a card still scrolls the list and selects nothing.
## Input is pushed as the engine's emulated mouse-then-touch pairs, with
## Input.emulate_touch_from_mouse on so ScrollContainer runs its touch drag.

func _run() -> void:
	var original_touch := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	directory = "user://replay-row-taps-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	var paths := _seed_solo()
	# A phone in landscape (canvas_items expand to 720 high), the base window,
	# and a narrow screen where a card opens the part list.
	for size: Vector2i in [Vector2i(1600, 720), Vector2i(1280, 720), Vector2i(960, 540)]:
		await _screen(size, paths)
	await _shared_card()
	Input.emulate_touch_from_mouse = original_touch
	print("REPLAY ROW TAPS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _open(size: Vector2i, paths: Dictionary) -> Array:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var app := Main.new()
	app.saves = Storage.new(directory + "/save-%d.json" % size.x)
	app.saves.data.settings.sound = false
	app.saves.data.settings.haptics = false
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.world.set_process(false)
	app.api.queue_free()
	api = FakeApi.new()
	app.add_child(api)
	app.api = api
	app.application_backgrounded = false
	app.solo_replay_index = Index.new(directory + "/index.json")
	app.solo_replay_visibility = Visibility.new(directory + "/visibility.json")
	# Layout-only earlier-island rows (never played) plus real chapter attempts.
	var replays := {}
	for index in range(4): replays[Levels.get_level(index).id] = {"b": {"layout_fixture": true}}
	app.saves.data.replays = replays
	app.solo_replays = Solo.new(paths, "")
	app._show_collection()
	await _finish_scan(app)
	await _frames(2)
	return [viewport, app]

func _screen(size: Vector2i, paths: Dictionary) -> void:
	var opened := await _open(size, paths)
	var viewport: SubViewport = opened[0]
	var app: Node = opened[1]
	var wide: bool = app.ui.size.x >= Main.REPLAY_SPLIT_MIN_WIDTH
	var count := _rows(app).size()
	_check(count >= 6, "%s: earlier-island and chapter rows are listed (%d)" % [size, count])
	if wide:
		for index in range(count):
			for spot: String in ["art", "caption", "middle"]:
				# Start from a different selection so a switch is observable.
				app._selected_solo_attempt = app._solo_collection_entries()[(index + 1) % count].duplicate(true)
				app._show_collection()
				await _frames(2)
				var card := await _visible_card(app, index)
				var at := _bottom_point(card, spot)
				_check(app._bounded_card_scroll.get_global_rect().has_point(at), "%s row %d: the bottom of the card is on screen" % [size, index])
				await _tap_at(viewport, at)
				var expected := str(app._solo_collection_entries()[index].key)
				_check(app.mode == "collection" and str(app._selected_solo_attempt.get("key", "")) == expected, "%s row %d: a tap on the bottom fifth over the %s selects it" % [size, index, spot])
		await _chips(app, viewport, size)
		await _drag_from_card(app, viewport, size)
	else:
		# Narrow: a card tap opens that attempt's part list.
		var last := count - 1
		var card := await _visible_card(app, last)
		await _tap_at(viewport, _bottom_point(card, "caption"))
		_check(app.mode == "solo_replay_attempt" and str(app._selected_solo_attempt.get("key", "")) == str(app._solo_collection_entries()[last].key), "%s: a tap on the bottom fifth of the last card opens its parts" % size)
	viewport.queue_free()
	await _frames(2)

func _chips(app: Node, viewport: SubViewport, size: Vector2i) -> void:
	# Pick a chapter attempt with more than one part and switch its parts by
	# tapping the bottom fifth of each chip.
	var entries: Array = app._solo_collection_entries()
	var multi := -1
	for index in range(entries.size()):
		if int(entries[index].get("parts", 1)) > 1: multi = index
	_check(multi >= 0, "%s: a seeded attempt has several parts" % size)
	if multi < 0: return
	app._selected_solo_attempt = entries[multi].duplicate(true)
	app._selected_solo_attempt["part"] = 0
	app._show_collection()
	await _frames(3)
	for part in range(int(entries[multi].parts) - 1, -1, -1):
		var chip := _button(app.overlay, "Part %d" % (part + 1))
		_check(chip != null and app.overlay.get_global_rect().has_point(chip.get_global_rect().end - Vector2(2, 2)), "%s: chip Part %d is fully on screen" % [size, part + 1])
		if chip == null: continue
		var rect := chip.get_global_rect()
		await _tap_at(viewport, Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.9))
		_check(int(app._selected_solo_attempt.get("part", -1)) == part, "%s: a tap on the bottom fifth of Part %d switches to it" % [size, part + 1])

func _drag_from_card(app: Node, viewport: SubViewport, size: Vector2i) -> void:
	app._selected_solo_attempt = app._solo_collection_entries()[0].duplicate(true)
	app._show_collection()
	await _frames(2)
	var scroll: ScrollContainer = app._bounded_card_scroll
	scroll.scroll_vertical = 0
	await _frames(2)
	var card: Control = _card_of(_rows(app)[2])
	var start := _bottom_point(card, "caption")
	var selected := str(app._selected_solo_attempt.get("key", ""))
	_touch_at(viewport, start, true)
	for step in range(1, 9): _move_at(viewport, start + Vector2(0, -12 * step), Vector2(0, -12))
	_touch_at(viewport, start + Vector2(0, -96), false)
	await _frames(2)
	_check(scroll.scroll_vertical > 0 and str(app._selected_solo_attempt.get("key", "")) == selected, "%s: a drag from the bottom of a card scrolls the list and selects nothing" % size)

func _shared_card() -> void:
	# The Together rows are built by the same card; its bottom fifth is a target too.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var app := Main.new()
	app.saves = Storage.new(directory + "/save-shared.json")
	app.saves.data.settings.sound = false
	viewport.add_child(app)
	app.set_process(false)
	await _frames(1)
	var opened := [0]
	var shell: Dictionary = app._begin_replay_split("together")
	var card: Dictionary = app._replay_row_card("relay-isles@2", "The Relay Isles", "Part 1 · Saved offline", false, func(): opened[0] += 1)
	shell.left.add_child(card.panel)
	await _frames(2)
	await _tap_at(viewport, _bottom_point(card.panel, "art"))
	await _tap_at(viewport, _bottom_point(card.panel, "caption"))
	_check(opened[0] == 2, "A tap on the bottom fifth of a shared replay card opens it (%d)" % opened[0])
	viewport.queue_free()
	await _frames(2)

func _visible_card(app: Node, index: int) -> Control:
	var card := _card_of(_rows(app)[index])
	app._bounded_card_scroll.ensure_control_visible(card)
	await _frames(2)
	return _card_of(_rows(app)[index])

func _card_of(title: Button) -> Control:
	var node: Node = title
	while node != null and not node is PanelContainer: node = node.get_parent()
	return node as Control

## A point in the bottom fifth of a card: over its art, its caption, or the
## middle of the text column between the title and Play.
func _bottom_point(card: Control, spot: String) -> Vector2:
	var rect := card.get_global_rect()
	var y := rect.position.y + rect.size.y * 0.9
	var title: Button = card.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.has_meta("replay_row"))[0]
	match spot:
		"art": return Vector2(rect.position.x + 60, y)
		"caption": return Vector2(title.get_global_rect().position.x + 24, y)
	return Vector2(title.get_global_rect().get_center().x, y)

func _tap_at(target: Viewport, at: Vector2) -> void:
	_touch_at(target, at, true)
	_touch_at(target, at, false)
	await _frames(2)

func _touch_at(target: Viewport, at: Vector2, pressed: bool) -> void:
	# The engine's order for an emulated touch: the mouse event, then the touch.
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

func _move_at(target: Viewport, at: Vector2, relative: Vector2) -> void:
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

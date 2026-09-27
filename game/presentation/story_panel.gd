extends CanvasLayer
## Dialogue is presented only between turns. The owner handles the local read
## marker; this component never advances a room or the shared campaign.
signal dismissal_requested(request_id: int, skipped: bool)
signal dismissed(skipped: bool, seen_saved: bool)

const ControlTheme = preload("res://presentation/control_theme.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const Spirit = preload("res://presentation/spirit_visual.gd")
const CREAM := Color("eceddb")
const GOLD := Color("f4c38d")
const BLUE := Color("a6dce0")
var text_scale := 1.0
var safe_rect_override := Rect2()
var shield: Control
var card: PanelContainer
var heading: Label
var speaker: Label
var dialogue: Label
var progress: Label
var error: Label
var scroll: ScrollContainer
var back_button: Button
var skip_button: Button
var next_button: Button
var portraits: Dictionary = {}
var role_mark: Control
var _shown_slot := "p0"
var _lines: Array = []
var _index := 0
var _open := false
var _saving := false
var _save_failed := false
var _skipped := false
var _request_id := 0
var _previous_focus: WeakRef

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	get_viewport().size_changed.connect(_layout)
	set_process_input(false)
	shield.hide()

func present(title: String, lines: Array, between_turns: bool) -> bool:
	if not is_node_ready() or _open or not between_turns or title.is_empty() or title.length() > 96 or lines.size() < 1 or lines.size() > 3:
		return false
	for line: Variant in lines:
		if not line is Dictionary or line.size() != 2 or line.get("speaker") not in ["p0", "p1"] or not line.get("text") is String or line.text.is_empty() or line.text.length() > 280:
			return false
	var focused := get_viewport().gui_get_focus_owner()
	_previous_focus = weakref(focused) if focused != null else null
	_lines = lines.duplicate(true)
	_index = 0
	_open = true
	_saving = false
	_save_failed = false
	heading.text = title
	shield.show()
	set_process_input(true)
	_show_line()
	_layout()
	next_button.grab_focus()
	return true

func is_open() -> bool:
	return _open

func resolve_dismissal(request_id: int, seen_saved: bool, error_text: String = "") -> void:
	if not _open or not _saving or request_id != _request_id: return
	_saving = false
	if seen_saved:
		_close(true)
	else:
		# A read-marker failure leaves an explicit retry, while Close still
		# lets the owner resume. No false saved/seen state is reported.
		_save_failed = true
		error.text = error_text.left(160)
		error.visible = not error_text.is_empty()
		next_button.text = "Retry"
		skip_button.text = "Close"
		_set_buttons(false)
		next_button.grab_focus()

func cancel() -> void:
	# Identity/navigation changes cancel without acknowledging story text.
	if _open:
		_skipped = true
		_close(false)

func _advance() -> void:
	if not _open or _saving: return
	if _save_failed:
		_request_dismissal(_skipped)
	elif _index + 1 < _lines.size():
		_index += 1
		_show_line()
	else:
		_request_dismissal(false)

func _back() -> void:
	if not _open or _saving or _save_failed or _index == 0: return
	_index -= 1
	_show_line()

func _skip() -> void:
	if not _open or _saving: return
	if _save_failed: _close(false)
	else: _request_dismissal(true)

func _request_dismissal(skipped: bool) -> void:
	_saving = true
	_skipped = skipped
	_request_id += 1
	_set_buttons(true)
	dismissal_requested.emit(_request_id, skipped)

func _close(seen_saved: bool) -> void:
	if not _open: return
	_open = false
	_saving = false
	shield.hide()
	set_process_input(false)
	var previous: Variant = _previous_focus.get_ref() if _previous_focus != null else null
	_previous_focus = null
	if is_instance_valid(previous) and previous is Control and previous.is_visible_in_tree(): previous.grab_focus()
	dismissed.emit(_skipped, seen_saved)

func _input(event: InputEvent) -> void:
	if not _open: return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if not event.is_echo(): _skip()
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		# Handle buttons here so gameplay listeners cannot also use the key.
		get_viewport().set_input_as_handled()
		if event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
			if event.is_echo() or _saving: return
			var focus := get_viewport().gui_get_focus_owner()
			if focus == back_button: _back()
			elif focus == skip_button: _skip()
			else: _advance()
		elif event.is_action_pressed("ui_down"):
			_scroll_dialogue(1)
		elif event.is_action_pressed("ui_up"):
			_scroll_dialogue(-1)
		elif event is InputEventKey and event.pressed and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
			_scroll_dialogue(-1 if event.keycode == KEY_PAGEUP else 1, true)
		elif event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_right"):
			get_viewport().set_input_as_handled()
			_cycle_focus(1)
		elif event.is_action_pressed("ui_focus_prev") or event.is_action_pressed("ui_left"):
			get_viewport().set_input_as_handled()
			_cycle_focus(-1)

func _scroll_dialogue(direction: int, page: bool = false) -> void:
	var amount := scroll.size.y * 0.8 if page else dialogue.get_theme_font_size("font_size") * 1.5
	scroll.scroll_vertical += roundi(direction * amount)

func _cycle_focus(direction: int) -> void:
	var available: Array[Button] = []
	for button: Button in [back_button, skip_button, next_button]:
		if not button.disabled: available.append(button)
	if available.is_empty(): return
	var index := available.find(get_viewport().gui_get_focus_owner())
	available[posmod(index + direction, available.size())].grab_focus()

func _show_line() -> void:
	var line: Dictionary = _lines[_index]
	_shown_slot = line.speaker
	role_mark.queue_redraw()
	speaker.text = "Gold" if line.speaker == "p0" else "Blue"
	speaker.add_theme_color_override("font_color", GOLD if line.speaker == "p0" else BLUE)
	dialogue.text = line.text
	progress.text = "%d / %d" % [_index + 1, _lines.size()]
	for slot: String in portraits: portraits[slot].visible = slot == line.speaker
	_set_buttons(false)
	skip_button.text = "Skip"
	next_button.text = "Continue"
	error.hide()
	scroll.scroll_vertical = 0

func _set_buttons(disabled: bool) -> void:
	back_button.disabled = disabled or _save_failed or _index == 0
	skip_button.disabled = disabled
	next_button.disabled = disabled

func _build() -> void:
	shield = Control.new()
	shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shield)
	var theme := Theme.new()
	theme.default_font = preload("res://assets/fonts/nunito.ttf")
	theme.default_font_size = 22
	theme.set_color("font_color", "Label", CREAM)
	ControlTheme.install_buttons(theme)
	shield.theme = theme
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.08, 0.08, 0.22)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shield.add_child(dim)
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", ControlTheme.rounded(Color("163c36"), 20, Color("54766a")))
	shield.add_child(card)
	# Wrapped labels settle their minimum size after the first layout. Reapply
	# the bounded card size then, including its very first presentation.
	card.minimum_size_changed.connect(_layout)
	var margin := MarginContainer.new()
	for edge: String in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 20)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	heading = Label.new()
	heading.add_theme_font_override("font", preload("res://assets/fonts/fredoka.ttf"))
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	progress = Label.new()
	top.add_child(progress)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	column.add_child(content)
	var portrait_stack := Control.new()
	portrait_stack.custom_minimum_size = Vector2(100, 100)
	content.add_child(portrait_stack)
	for slot: String in ["p0", "p1"]:
		var portrait := _portrait(GOLD if slot == "p0" else BLUE)
		portrait_stack.add_child(portrait)
		portraits[slot] = portrait
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(words)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 8)
	words.add_child(identity)
	role_mark = Control.new()
	role_mark.custom_minimum_size = Vector2(28, 28)
	role_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	role_mark.draw.connect(_draw_role_mark)
	identity.add_child(role_mark)
	speaker = Label.new()
	identity.add_child(speaker)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	words.add_child(scroll)
	dialogue = Label.new()
	dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(dialogue)
	error = Label.new()
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error.hide()
	column.add_child(error)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	back_button = _button("Back", _back)
	skip_button = _button("Skip", _skip)
	next_button = _button("Continue", _advance)
	for button: Button in [back_button, skip_button, next_button]: buttons.add_child(button)
	ControlTheme.secondary(back_button)
	ControlTheme.secondary(skip_button)
	back_button.add_theme_color_override("font_focus_color", CREAM)
	skip_button.add_theme_color_override("font_focus_color", CREAM)

func _draw_role_mark() -> void:
	var center := Vector2(14, 14)
	if _shown_slot == "p0":
		role_mark.draw_circle(center, 6, GOLD)
		for index in range(8):
			var direction := Vector2.from_angle(index * TAU / 8)
			role_mark.draw_line(center + direction * 9, center + direction * 12, GOLD, 2, true)
	else:
		role_mark.draw_circle(center, 10, BLUE)
		role_mark.draw_circle(center + Vector2(5, -3), 8, Color("163c36"))

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 52
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, ControlTheme.INK)
	button.pressed.connect(callback)
	return button

func _portrait(color: Color) -> SubViewportContainer:
	var container := SubViewportContainer.new()
	container.size = Vector2(100, 100)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.stretch = true
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.disable_3d = false
	viewport.gui_disable_input = true
	container.add_child(viewport)
	var spirit := Spirit.new(color)
	viewport.add_child(spirit)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0.60, 2.0)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.22
	camera.current = true
	viewport.add_child(camera)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.8
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	viewport.add_child(light)
	return container

func _layout() -> void:
	if not is_instance_valid(card): return
	var bounds := get_viewport().get_visible_rect()
	var safe := bounds
	if safe_rect_override.has_area(): safe = safe_rect_override.intersection(bounds)
	elif OS.has_feature("android"): safe = SafeArea.viewport_rect(Rect2(DisplayServer.get_display_safe_area()), get_viewport().get_screen_transform(), bounds)
	var scale := clampf(text_scale, 1.0, 1.5)
	heading.add_theme_font_size_override("font_size", roundi(25 * scale))
	speaker.add_theme_font_size_override("font_size", roundi(19 * scale))
	dialogue.add_theme_font_size_override("font_size", roundi(27 * scale))
	var width := minf(860, maxf(280, safe.size.x - 40))
	var height := minf(310 * scale, maxf(210, safe.size.y - 40))
	card.size = Vector2(width, height)
	card.position = Vector2(safe.get_center().x - width / 2, safe.end.y - height - 20)

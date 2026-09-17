extends CanvasLayer
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Shared chapter controls. Puzzle progression and persistence stay with the owner.
signal pause_requested
signal action_requested
signal finish_requested

const Joystick = preload("res://presentation/joystick.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const Actions = preload("res://presentation/action_buttons.gd")
const ObjectivePanel = preload("res://presentation/objective_panel.gd")
const CREAM := Color("eceddb")
const MUTED := Color("afc7bd")
var settings: Dictionary = {}
var ui: Control
var hud: Control
var overlay: Control
var stick: Control
var action_button: Button
var finish_button: Button
var pause_button: Button
var timer_label: Label
var chapter_label: Label
var hint_label: Label
var progress_label: Label
var objective_panel: PanelContainer
var turn_progress: ProgressBar
var title_font: Font
var modal_shade: ColorRect
var modal_scroll: ScrollContainer
var modal_stack: VBoxContainer

func _ready() -> void:
	_build_ui()
	get_viewport().size_changed.connect(_resize)
	_resize()

func show_play() -> void:
	overlay.visible = false
	hud.visible = true
	pause_button.visible = true
	Actions.apply(finish_button, "finish")

func show_moment(action_id: String) -> void:
	# The solved world stays visible until the player chooses to move on.
	show_play()
	stick.release()
	stick.visible = false
	action_button.visible = false
	pause_button.visible = false
	finish_button.visible = true
	finish_button.disabled = false
	Actions.apply(finish_button, action_id)

func update_state(title: String, remaining: float, state: Dictionary, interactive: bool) -> void:
	chapter_label.text = title
	timer_label.text = "%.1f" % maxf(0.0, remaining)
	turn_progress.value = clampf(20.0-remaining,0.0,20.0)
	hint_label.text = PlayerCopy.from_canonical(str(state.get("message", "")))
	var objective: Dictionary = state.get("objective_display", ObjectivePanel.legacy_progress(state, 30.0))
	objective_panel.show_objective(objective, str(state.get("progress_message", "")))
	var action: Dictionary = state.get("context_action", {})
	action_button.text = PlayerCopy.from_canonical(str(action.get("label", "Interact")))
	action_button.disabled = not bool(action.get("enabled", false))
	finish_button.disabled = not bool(state.get("can_commit", false))
	stick.visible = interactive
	action_button.visible = interactive
	finish_button.visible = interactive

func _build_ui() -> void:
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	var theme := Theme.new()
	var body := FontVariation.new()
	body.base_font = preload("res://assets/fonts/nunito.ttf")
	body.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	theme.default_font = body
	var heading := FontVariation.new()
	heading.base_font = preload("res://assets/fonts/fredoka.ttf")
	heading.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	title_font = heading
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", CREAM)
	ControlTheme.install_buttons(theme)
	ui.theme = theme
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	var brand := _label("AFTER YOU",22)
	brand.add_theme_font_override("font",title_font)
	brand.position=Vector2(36,26)
	hud.add_child(brand)
	chapter_label = _label("THE SLEEPING LIGHTHOUSE",18)
	chapter_label.add_theme_color_override("font_color",MUTED)
	chapter_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chapter_label.position = Vector2(36,61)
	hud.add_child(chapter_label)
	chapter_label.minimum_size_changed.connect(_fit_chapter_title.call_deferred)
	timer_label = _label("20.0", 25)
	timer_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	timer_label.position = Vector2(-45,26)
	timer_label.size = Vector2(90,40)
	timer_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(timer_label)
	turn_progress=ProgressBar.new()
	turn_progress.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	turn_progress.position=Vector2(-160,76)
	turn_progress.size=Vector2(320,5)
	turn_progress.max_value=20.0
	turn_progress.show_percentage=false
	turn_progress.mouse_filter=Control.MOUSE_FILTER_IGNORE
	turn_progress.add_theme_stylebox_override("background",ControlTheme.rounded(Color("35584f"),3))
	turn_progress.add_theme_stylebox_override("fill",ControlTheme.rounded(Color("f1c48a"),3))
	hud.add_child(turn_progress)
	objective_panel = ObjectivePanel.new()
	hud.add_child(objective_panel)
	_anchor_rect(objective_panel, Control.PRESET_TOP_RIGHT, Rect2(-248, 124, 224, 0))
	progress_label = objective_panel.label
	pause_button = button_for("pause", func(): pause_requested.emit())
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_button.position = Vector2(-156, 20)
	pause_button.size = Vector2(132, 50)
	hud.add_child(pause_button)
	hint_label = _label("", 21)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position = Vector2(-340, -94)
	hint_label.size = Vector2(680, 78)
	hud.add_child(hint_label)
	stick = Joystick.new()
	stick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stick.position = Vector2(28, -198)
	stick.size = Vector2(152, 152)
	hud.add_child(stick)
	action_button = button("Interact", func(): action_requested.emit())
	action_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	action_button.position = Vector2(-240, -178)
	action_button.size = Vector2(210, 64)
	hud.add_child(action_button)
	finish_button = button_for("finish", func(): finish_requested.emit())
	finish_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	finish_button.position = Vector2(-240, -100)
	finish_button.size = Vector2(210, 54)
	hud.add_child(finish_button)
	if settings.get("left_handed", false):
		_anchor_rect(stick, Control.PRESET_BOTTOM_RIGHT, Rect2(-180, -198, 152, 152))
		_anchor_rect(action_button, Control.PRESET_BOTTOM_LEFT, Rect2(28, -178, 210, 64))
		_anchor_rect(finish_button, Control.PRESET_BOTTOM_LEFT, Rect2(28, -100, 210, 54))
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(overlay)


func _anchor_rect(control: Control, preset: int, rect: Rect2) -> void:
	# Set offsets, not absolute positions, after the control has a parent.
	control.set_anchors_and_offsets_preset(preset)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y


func _resize() -> void:
	if not is_instance_valid(ui):
		return
	var viewport := get_viewport().get_visible_rect()
	var safe := viewport
	if OS.has_feature("android"):
		safe = SafeArea.viewport_rect(Rect2(DisplayServer.get_display_safe_area()), get_viewport().get_screen_transform(), viewport)
	ui.offset_left = safe.position.x - viewport.position.x
	ui.offset_top = safe.position.y - viewport.position.y
	ui.offset_right = safe.end.x - viewport.end.x
	ui.offset_bottom = safe.end.y - viewport.end.y
	if is_instance_valid(chapter_label):
		# Long stage names wrap in the title column instead of covering the
		# timer and progress text in the centre of the display.
		chapter_label.size.x = maxf(240.0, ui.size.x * 0.5 - 244.0)
		_fit_chapter_title.call_deferred()
	_resize_shade()
	_layout_card.call_deferred()


func _fit_chapter_title() -> void:
	# Wrapping recomputes its minimum height after the width/text changes.
	# Release any height retained from the earlier narrow layout so its real
	# rectangle does not invisibly cover the playfield or suppress photo bubbles.
	if is_instance_valid(chapter_label):
		chapter_label.size.y = 0.0


func _resize_shade() -> void:
	# Controls respect display cutouts; the dimming backdrop covers the whole
	# world, including those insets. Otherwise a bright side strip remains.
	if not is_instance_valid(modal_shade):
		return
	modal_shade.offset_left = -ui.offset_left
	modal_shade.offset_top = -ui.offset_top
	modal_shade.offset_right = -ui.offset_right
	modal_shade.offset_bottom = -ui.offset_bottom


func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(16)
	style.set_border_width_all(1)
	style.border_color = Color("54766a")
	return style


func _label(text: String, size: int = 20) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func button_for(action_id: String, callback: Callable) -> Button:
	return Actions.create(action_id, callback)


func button(text: String, callback: Callable, primary: bool=true) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 50
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.pressed.connect(callback)
	if not primary: ControlTheme.secondary(button)
	return button


func card(title: String, body: String) -> VBoxContainer:
	stick.release()
	hud.visible = false
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	overlay.visible = true
	modal_shade = ColorRect.new()
	modal_shade.color = Color(0.025, 0.10, 0.10, 0.73)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(modal_shade)
	_resize_shade()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 610
	panel.add_theme_stylebox_override("panel", _style(Color("163c36")))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for edge: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	modal_scroll = ScrollContainer.new()
	modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal_scroll.follow_focus = true
	margin.add_child(modal_scroll)
	modal_scroll.add_child(stack)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_stack = stack
	stack.minimum_size_changed.connect(func(): _layout_card.call_deferred())
	var heading_label := _label(title, 32)
	heading_label.add_theme_font_override("font", title_font)
	heading_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading_label.custom_minimum_size.x = 550
	stack.add_child(heading_label)
	var paragraph := _label(body, 20)
	paragraph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	paragraph.custom_minimum_size.x = 550
	paragraph.add_theme_color_override("font_color", MUTED)
	stack.add_child(paragraph)
	_layout_card.call_deferred()
	return stack

func _layout_card() -> void:
	if not is_instance_valid(modal_scroll) or not is_instance_valid(modal_stack): return
	# Long checkpoint lists scroll inside the card instead of pushing the
	# final button beyond the safe display area.
	var limit := maxf(120.0, ui.size.y - 84.0)
	var required := modal_stack.get_combined_minimum_size().y
	modal_scroll.custom_minimum_size = Vector2(566.0, minf(required, limit))

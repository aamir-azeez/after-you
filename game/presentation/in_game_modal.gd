extends Control
## Shared in-game pop-up used across After You: a dimmed backdrop that blocks
## the page behind it, a teal panel with a heading and a quiet Close button,
## optional body text or fields, and a coral Cancel beside a cream main action.
const ThemeRules = preload("res://presentation/control_theme.gd")
const CLOSE_ICON = preload("res://assets/ui/social/x.svg")
const CREAM := Color("eceddb")
const MUTED := Color("afc6be")

signal closed

var content: VBoxContainer
var heading_font: FontVariation
var _panel: PanelContainer
var _center: CenterContainer
var _opener: Control
var _closing := false

static func open(parent: Control, node_name: String, heading: String, subtitle: String = "", opener: Control = null) -> Control:
	var modal: Control = load("res://presentation/in_game_modal.gd").new()
	modal.name = node_name
	modal._opener = opener
	parent.add_child(modal)
	modal._build(heading, subtitle)
	return modal

func _build(heading: String, subtitle: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Theme.new()
	var body := FontVariation.new()
	body.base_font = preload("res://assets/fonts/nunito.ttf")
	body.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):600.0}
	theme.default_font = body
	theme.default_font_size = 20
	theme.set_color("font_color","Label",CREAM)
	ThemeRules.install_buttons(theme)
	heading_font = FontVariation.new()
	heading_font.base_font = preload("res://assets/fonts/fredoka.ttf")
	heading_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):600.0}
	var shade := ColorRect.new()
	shade.color = Color(0.02,0.08,0.08,0.74)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	_center = CenterContainer.new()
	_center.name = "ModalCenter"
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_center)
	_panel = PanelContainer.new()
	_panel.name = "ModalPanel"
	_panel.custom_minimum_size.x = clampf(get_viewport_rect().size.x - 48.0,280.0,500.0)
	var surface := ThemeRules.rounded(Color("1d4a44"),22,Color("3f6b61"))
	ThemeRules.padded(surface,26.0,22.0)
	_panel.add_theme_stylebox_override("panel",surface)
	_center.add_child(_panel)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation",10)
	_panel.add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",12)
	content.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation",2)
	header.add_child(titles)
	var title := label(heading,26,titles)
	title.add_theme_font_override("font",heading_font)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	if not subtitle.is_empty():
		label(subtitle,17,titles).add_theme_color_override("font_color",MUTED)
	var close_button := Button.new()
	close_button.name = "ModalClose"
	close_button.icon = CLOSE_ICON
	close_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_button.expand_icon = true
	close_button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	close_button.add_theme_constant_override("icon_max_width",18)
	close_button.tooltip_text = "Close"
	close_button.accessibility_name = "Close"
	close_button.custom_minimum_size = Vector2(48,48)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# A quiet chip keeps Close visible without competing with the main action.
	for state: String in ["normal","hover","pressed","hover_pressed","focus"]:
		var chip := ThemeRules.rounded(Color("2a5952") if state == "normal" else Color("356a62"),12)
		if state == "focus": chip = ThemeRules.rounded(Color.TRANSPARENT,12,CREAM)
		close_button.add_theme_stylebox_override(state,chip)
	for state: String in ["normal","hover","pressed","hover_pressed","focus"]:
		close_button.add_theme_color_override("icon_"+state+"_color",CREAM)
	close_button.pressed.connect(func(): close())
	header.add_child(close_button)

func label(text: String, size: int = 19, parent: Node = null) -> Label:
	var value := Label.new()
	value.text = text
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.add_theme_font_size_override("font_size",size)
	(parent if parent != null else content).add_child(value)
	return value

func add_actions(primary_label: String, primary: Callable, cancel_label: String = "Cancel") -> Button:
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	content.add_child(gap)
	var footer := BoxContainer.new()
	footer.vertical = _panel.custom_minimum_size.x < 360.0
	footer.add_theme_constant_override("separation",14)
	content.add_child(footer)
	var cancel := Button.new()
	cancel.name = "ModalCancel"
	cancel.text = cancel_label
	cancel.custom_minimum_size.y = 54
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func(): close())
	ThemeRules.danger(cancel)
	footer.add_child(cancel)
	var confirm := Button.new()
	confirm.name = "ModalConfirm"
	confirm.text = primary_label
	confirm.custom_minimum_size.y = 54
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(primary)
	footer.add_child(confirm)
	_trap_focus()
	return confirm

func _trap_focus() -> void:
	# Keep keyboard focus inside the modal.
	var order: Array[Control] = []
	for control: Control in find_children("*","Control",true,false):
		if control is LineEdit or control is Button: order.append(control)
	for index in range(order.size()):
		order[index].focus_next = order[index].get_path_to(order[(index + 1) % order.size()])
		order[index].focus_previous = order[index].get_path_to(order[(index - 1 + order.size()) % order.size()])

func close(restore_focus: bool = true) -> void:
	if _closing: return
	_closing = true
	var opener := _opener
	_opener = null
	queue_free()
	closed.emit()
	if restore_focus and is_instance_valid(opener) and opener.is_inside_tree(): opener.grab_focus()

func _input(event: InputEvent) -> void:
	if not _closing and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func _process(_delta: float) -> void:
	# Android's on-screen keyboard covers the bottom of the window; lift the
	# panel so a field and its buttons stay visible while typing.
	var keyboard := float(DisplayServer.virtual_keyboard_get_height())
	var window := float(DisplayServer.window_get_size().y)
	_center.offset_bottom = -(keyboard * get_viewport_rect().size.y / window) if keyboard > 0.0 and window > 0.0 else 0.0

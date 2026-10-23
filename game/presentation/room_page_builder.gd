extends RefCounted
## The room page's plain UI pieces: panel buttons and their icon looks, groups,
## the result lines under Copy and Share, the waiting heading's muted lines and
## the invitation code row. Each builds or styles nodes from its arguments only;
## the room screen (relay_preview.gd) decides what to show and wires handlers.
const ControlTheme = preload("res://presentation/control_theme.gd")
const RoomActions = preload("res://presentation/room_actions.gd")
const CREAM := Color("eceddb")
const MUTED := Color("afc7bd")

## A room panel button. The caller connects once the node exists.
static func panel_button(text: String, primary: bool) -> Button:
	# Same as the shared card button.
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 50
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	if not primary: ControlTheme.secondary(button)
	return button

## An icon on a room button, alone (icon_only, a header action) or beside its
## label; `accessible` names it.
static func icon_button(button: Button, texture: Texture2D, accessible: String, icon_only: bool = false) -> void:
	button.icon = texture
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if icon_only else HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("icon_max_width",28)
	button.add_theme_color_override("icon_normal_color",CREAM)
	button.add_theme_color_override("icon_hover_color",Color("193d39"))
	button.tooltip_text = accessible
	button.accessibility_name = accessible
	if icon_only:
		button.text = ""
		button.custom_minimum_size = Vector2(48,48)
		button.size_flags_horizontal = Control.SIZE_SHRINK_END

## A panel row's icon beside its centred label, inked like the label.
static func panel_row_look(button: Button, texture: Texture2D, cream: bool) -> void:
	if button.icon == null and texture != null:
		button.icon = texture
		button.expand_icon = false
		button.add_theme_constant_override("icon_max_width", 22)
		button.add_theme_constant_override("h_separation", 10)
		var ink := ControlTheme.INK if cream else CREAM
		for state: String in ["normal", "focus"]: button.add_theme_color_override("icon_" + state + "_color", ink)
		for state: String in ["hover", "pressed", "hover_pressed"]: button.add_theme_color_override("icon_" + state + "_color", ControlTheme.INK)
	if button.icon != null:
		ControlTheme.inset_button(button)
		ControlTheme.center_icon_label(button)

## A coral edge on a panel row that waits for this player's answer.
static func alert_outline(button: Button) -> void:
	var style := button.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	if style == null: return
	style.border_color = ControlTheme.CORAL
	style.set_border_width_all(2)
	button.add_theme_stylebox_override("normal", style)

## A column of rows `separation` apart, added to `parent`.
static func group(parent: VBoxContainer, separation: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", separation)
	parent.add_child(column)
	return column

## A result line under Copy or Share, hidden until a result arrives.
static func feedback_label(label_name: String) -> Label:
	# set_feedback shows it with its text.
	var status := _label("",17)
	status.name = label_name
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.visible = false
	return status

static func set_feedback(status: Label, text: String) -> void:
	if not is_instance_valid(status): return
	status.text = text
	status.visible = not text.is_empty()

## The waiting heading's muted lines: the sub-line, then any notices.
static func waiting_lines(parent: VBoxContainer, subline: String, whose: String, notices: PackedStringArray) -> void:
	var lines: Array[String] = []
	if not subline.is_empty(): lines.append(subline)
	lines.append_array(notices)
	for text: String in lines:
		var line := _label(text, 18 if text == subline else 16)
		if text == subline: line.name = "WaitingPartnerLine" if subline == whose else "WaitingSubline"
		line.add_theme_color_override("font_color", MUTED)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(line)

## The invitation code field showing `code`, with a labelled Copy as tall as
## the field, like the Friends screen. Copy calls `copy` with the row's result
## line. `look` is the slot's look (RoomActions.look).
static func invitation_code_row(card: Container, code_text: String, look: Dictionary, copy_code: Callable) -> void:
	var field_height: int = look.get("field", 52)
	card.add_child(_label("Invitation code",17))
	var row := HBoxContainer.new()
	row.name = "InvitationCodeRow"
	row.add_theme_constant_override("separation",8)
	card.add_child(row)
	var code := LineEdit.new()
	code.text = code_text
	# The typed room-<code> is longer than the bare code; never clip it.
	code.expand_to_text_length = true
	code.editable = false
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.custom_minimum_size.y = field_height
	code.add_theme_font_size_override("font_size",look.get("field_font", 20))
	code.add_theme_color_override("font_uneditable_color",CREAM)
	# Same field look as the Friends code fields.
	var field_style := ControlTheme.rounded(Color("14312f"),12,Color("466e63"))
	field_style.content_margin_left = 16
	field_style.content_margin_right = 16
	for state: String in ["normal","read_only"]: code.add_theme_stylebox_override(state,field_style)
	code.add_theme_stylebox_override("focus",ControlTheme.rounded(Color.TRANSPARENT,12,Color("a6d9c4")))
	code.tooltip_text = "Invitation code"
	row.add_child(code)
	var status := feedback_label("RelayCopyStatus")
	var copy := panel_button("Copy",false)
	copy.name = "CopyInvitationCode"
	copy.pressed.connect(copy_code.bind(status))
	icon_button(copy,RoomActions.ACTIONS.copy_code.icon,RoomActions.label("copy_code"))
	# A fixed 24-unit icon: an expanded icon shrank to nothing beside the centred label.
	copy.expand_icon = false
	copy.add_theme_constant_override("icon_max_width",24)
	copy.custom_minimum_size = Vector2(look.get("copy_width", 140),field_height)
	ControlTheme.inset_button(copy)
	ControlTheme.center_icon_label(copy)
	row.add_child(copy)
	card.add_child(status)

static func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

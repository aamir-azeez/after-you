extends RefCounted
## Room options' body under its friend card: section headings and rows in two
## columns. Each row is a button with an icon tile, its label, an optional line
## under the label and a chevron. The screen chooses the rows from the room
## action table (room_actions.gd) and wires each one.
const ControlTheme = preload("res://presentation/control_theme.gd")
const CHEVRON = preload("res://assets/ui/social/chevron-right.svg")
const CREAM := Color("eceddb")
const MUTED := Color("afc6be")
const MINT := Color("a6d9c4")
const CORAL := ControlTheme.CORAL
const ROW_HEIGHT := 56.0

var _columns: Array[VBoxContainer] = []

## Builds the two empty columns under `parent`. They scroll only when taller
## than max_height.
func _init(parent: VBoxContainer, max_height: float) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "RoomOptionsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	parent.add_child(scroll)
	var columns := HBoxContainer.new()
	columns.name = "RoomOptionsColumns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 22)
	scroll.add_child(columns)
	for _side in range(2):
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 8)
		columns.add_child(column)
		_columns.append(column)
	var fit := func():
		if is_instance_valid(scroll): scroll.custom_minimum_size.y = minf(columns.get_combined_minimum_size().y, maxf(120.0, max_height))
	columns.minimum_size_changed.connect(fit.call_deferred)
	fit.call_deferred()
	ControlTheme.touch_scroll(scroll)

func heading(column: int, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", MINT)
	# A heading below rows keeps a little air above it.
	if _columns[column].get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 4
		_columns[column].add_child(gap)
	_columns[column].add_child(label)
	return label

## One row. Its "title" and "subtitle" metas are the labels the screen may
## rewrite; the subtitle stays hidden while it is empty.
func row(column: int, icon: Texture2D, text: String, danger: bool = false) -> Button:
	var button := Button.new()
	button.accessibility_name = text
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = ROW_HEIGHT
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var fill := Color("24534c")
		if state == "hover": fill = Color("2c6058")
		if state in ["pressed", "hover_pressed"]: fill = Color("356a62")
		if state == "disabled": fill = Color("203f39")
		var style := ControlTheme.rounded(Color.TRANSPARENT if state == "focus" else fill, 14, Color("a6d9c4") if state == "focus" else Color.TRANSPARENT)
		button.add_theme_stylebox_override(state, style)
	var inside := HBoxContainer.new()
	inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inside.add_theme_constant_override("separation", 14)
	button.add_child(inside)
	inside.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inside.offset_left = 8
	inside.offset_right = -14
	var ink := CORAL if danger else CREAM
	var tile := PanelContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.custom_minimum_size = Vector2(40, 40)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(Color("6b3b37") if danger else Color("2f655c"), 10), 10.0, 10.0))
	inside.add_child(tile)
	var picture := TextureRect.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.texture = icon
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.self_modulate = ink
	tile.add_child(picture)
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 0)
	inside.add_child(words)
	var title := _text(text, 20, ink)
	words.add_child(title)
	var subtitle := _text("", 16, MUTED)
	subtitle.visible = false
	words.add_child(subtitle)
	var chevron := TextureRect.new()
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chevron.texture = CHEVRON
	chevron.custom_minimum_size = Vector2(20, 20)
	chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chevron.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chevron.self_modulate = MUTED
	inside.add_child(chevron)
	button.set_meta("title", title)
	button.set_meta("subtitle", subtitle)
	# A wrapped label or a shown subtitle makes the row taller.
	inside.minimum_size_changed.connect(func():
		if is_instance_valid(button): button.custom_minimum_size.y = maxf(ROW_HEIGHT, inside.get_combined_minimum_size().y + 12.0))
	_columns[column].add_child(button)
	return button

func _text(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

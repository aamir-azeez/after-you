extends RefCounted
## The Settings page's look and its shared builders: on/off settings as tiles (two to
## a row in a grid), one row builder per other kind (choice, link, action,
## info), the category rail item, the header pieces and the cream panel. presentation/settings_flow.gd puts them
## together from the rows table (presentation/settings_rows.gd); nothing here
## reads saves or knows a setting by name.
##
## Every interactive control is named by its row id (a rail item by
## "category_<id>"), so code and tests find a row with find_child(id) whatever
## its wording. Row and tile text is drawn by labels inside the control, which
## ignore the mouse, so the whole row or tile is one touch target.
const ControlTheme = preload("res://presentation/control_theme.gd")
const NUNITO := preload("res://assets/fonts/nunito.ttf")
const FREDOKA := preload("res://assets/fonts/fredoka.ttf")
const CHEVRON := preload("res://assets/ui/settings/chevron.svg")
const CHECK := preload("res://assets/ui/settings/check.svg")
const RESET := preload("res://assets/ui/settings/reset.svg")
const TRASH := preload("res://assets/ui/social/trash.svg")

## The page: dark teal behind, a cream panel, mint for on and selected.
const PAGE := Color("123a3d")
const PANEL := Color("f1efdb")
const INK := Color("173f40")
const INK_SOFT := Color("49675f")
const CREAM := Color("f1efdb")
const MUTED := Color("b4cec3")
const MINT := Color("a9dbc4")
const DIVIDER := Color("dfe2cc")
const PRESSED := Color("e6e5cd")
const SEGMENTS := Color("e4e5d0")
const FIELD := Color("e8e8d3")
const DISABLED_INK := Color("8e9c92")
## A toggle tile: a lighter cream card with a faint edge, a mint well for its icon.
const TILE := Color("fbf8ec")
const TILE_EDGE := Color("ddd6bf")
const TILE_HELD := Color("efeadb")
const ICON_WELL := Color("bfe6d5")
const TRACK_ON_EDGE := Color("7cc7a8")
const TRACK_OFF_TILE := Color("d8d3c0")
const TRACK_OFF_EDGE := Color("c4bea8")
const KNOB_OFF_TILE := Color("8a948c")
const TILE_GAP := 16
## Space inside a row; the panel's own padding plus this lines text up with the title.
const ROW_PAD := 12
const ROW_GAP := 2

static var _fonts: Dictionary = {}
static var _blank: Texture2D

static func font(weight: int, title: bool = false) -> FontVariation:
	var key := ("t" if title else "b") + str(weight)
	if not _fonts.has(key):
		var variation := FontVariation.new()
		variation.base_font = FREDOKA if title else NUNITO
		variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): float(weight)}
		_fonts[key] = variation
	return _fonts[key]

static func label(text: String, size: int, color: Color, weight: int = 500, title: bool = false) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_override("font", font(weight, title))
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func note(text: String, color: Color = INK_SOFT) -> Label:
	var result := label(text, 15, color)
	result.name = "Note"
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.visible = not text.is_empty()
	return result

static func icon(texture: Texture2D, side: float, tint: Color) -> TextureRect:
	var result := TextureRect.new()
	result.texture = texture
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.custom_minimum_size = Vector2(side, side)
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	result.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	result.modulate = tint
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func rounded(color: Color, radius: int, border: Color = Color.TRANSPARENT, border_width: int = 1) -> StyleBoxFlat:
	var style := ControlTheme.rounded(color, radius, border)
	if border.a > 0.0: style.set_border_width_all(border_width)
	return style

static func _hbox(separation: int) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box

static func _vbox(separation: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box

static func pad(child: Control, horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, horizontal)
	for side: String in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, vertical)
	margin.add_child(child)
	return margin

static func _blank_icon() -> Texture2D:
	if _blank == null:
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		_blank = ImageTexture.create_from_image(image)
	return _blank

## A row's tap surface: the cream of the panel at rest, a shade darker while
## pressed or hovered, and a mint ring for keyboard focus. A switch that is on
## keeps the panel's cream: its switch shows it.
static func _row_surface(button: BaseButton) -> void:
	var toggles := button.toggle_mode
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var fill := PRESSED if state in ["hover", "hover_pressed"] or (state == "pressed" and not toggles) else PANEL
		button.add_theme_stylebox_override(state, rounded(fill, 14))
	button.add_theme_stylebox_override("focus", rounded(Color.TRANSPARENT, 14, MINT, 2))
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

## The label and note of a row, stacked.
static func _texts(row: Dictionary, label_color: Color = INK) -> VBoxContainer:
	var texts := _vbox(ROW_GAP)
	texts.name = "Texts"
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := label(str(row.label), 20, label_color, 600)
	title.name = "Label"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(title)
	texts.add_child(note(str(row.get("note", ""))))
	return texts

## A tappable row: the button under, its content over it. The holder sizes to
## the content, and the button fills the holder.
static func _tap_row(row: Dictionary, button: BaseButton, trailing: Control) -> Control:
	var holder := MarginContainer.new()
	holder.name = str(row.id) + "Row"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.name = str(row.id)
	button.accessibility_name = str(row.label)
	_row_surface(button)
	holder.add_child(button)
	var line := _hbox(16)
	line.add_child(_texts(row))
	if trailing != null: line.add_child(trailing)
	holder.add_child(pad(line, ROW_PAD, 20))
	return holder

## An on/off setting as a tile: its icon in a mint well and a big switch on
## top, its name and note below. The whole tile is the CheckButton, so a tap
## anywhere flips it; the switch only shows the state. While a finger is down
## the tile darkens a little.
static func toggle_tile(row: Dictionary, pressed: bool, icon_texture: Texture2D) -> Control:
	var holder := MarginContainer.new()
	holder.name = str(row.id) + "Row"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var button := CheckButton.new()
	button.name = str(row.id)
	button.accessibility_name = str(row.label)
	button.accessibility_description = str(row.get("note", ""))
	for icon_name: String in ["checked", "unchecked", "checked_disabled", "unchecked_disabled", "checked_mirrored", "unchecked_mirrored", "checked_disabled_mirrored", "unchecked_disabled_mirrored"]:
		button.add_theme_icon_override(icon_name, _blank_icon())
	button.button_pressed = pressed
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_tile_surface(button, false)
	button.button_down.connect(func(): _tile_surface(button, true))
	button.button_up.connect(func(): _tile_surface(button, false))
	holder.add_child(button)
	var stack := _vbox(4)
	var top := _hbox(12)
	var well := PanelContainer.new()
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.custom_minimum_size = Vector2(46, 46)
	well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	well.add_theme_stylebox_override("panel", rounded(ICON_WELL, 23))
	var glyph := icon(icon_texture, 24, INK)
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	well.add_child(glyph)
	top.add_child(well)
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	var mark := Switch.new()
	mark.button = button
	button.toggled.connect(func(_on: bool): mark.refresh())
	top.add_child(mark)
	stack.add_child(top)
	var space := Control.new()
	space.custom_minimum_size.y = 8
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(space)
	var title := label(str(row.label), 19, INK, 700)
	title.name = "Label"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(title)
	stack.add_child(note(str(row.get("note", ""))))
	holder.add_child(pad(stack, 22, 18))
	return holder

## The tile's card: cream with a faint edge, a shade darker while held, and an
## ink ring for keyboard focus. Being on never changes the card; the switch says it.
static func _tile_surface(button: BaseButton, held: bool) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var fill := TILE_HELD if held else TILE
		var edge := Color(INK, 0.3) if state in ["hover", "hover_pressed"] and not held else TILE_EDGE
		button.add_theme_stylebox_override(state, rounded(fill, 18, edge, 2))
	button.add_theme_stylebox_override("focus", rounded(Color.TRANSPARENT, 18, INK, 2))

## Tiles two to a row. An odd last tile keeps its column's width.
static func tile_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.name = "Tiles"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", TILE_GAP)
	grid.add_theme_constant_override("v_separation", TILE_GAP)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return grid

## A soft cream fade over the panel's bottom edge while more rows lie below.
static func bottom_fade() -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(PANEL, 0.0))
	gradient.set_color(1, PANEL)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 4
	texture.height = 64
	var fade := TextureRect.new()
	fade.name = "MoreBelow"
	fade.texture = texture
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	fade.offset_top = -40
	return fade

## A row that opens something: a chevron, or a live value before it.
static func link_row(row: Dictionary, value: String = "") -> Control:
	var trailing := _hbox(10)
	var shown := label(value, 17, INK_SOFT, 600)
	shown.name = "Value"
	shown.visible = not value.is_empty()
	shown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trailing.add_child(shown)
	trailing.add_child(icon(CHEVRON, 20, INK_SOFT))
	return _tap_row(row, Button.new(), trailing)

## A row that acts in place. Its result shows in the Detail box under it.
static func action_row(row: Dictionary) -> Control:
	var block := _vbox(0)
	block.name = str(row.id) + "Block"
	block.add_child(_tap_row(row, Button.new(), null))
	var detail := _vbox(10)
	detail.name = "Detail"
	detail.mouse_filter = Control.MOUSE_FILTER_PASS
	detail.visible = false
	block.add_child(pad(detail, ROW_PAD, 0))
	block.get_child(1).name = "DetailPad"
	return block

## Something to read, not to tap.
static func info_row(row: Dictionary) -> Control:
	var texts := _texts(row, INK)
	var title: Label = texts.get_node("Label")
	if str(row.label).is_empty(): title.visible = false
	var holder := pad(texts, ROW_PAD, 16)
	holder.name = str(row.id)
	return holder

## A destructive action: a coral button in its own block, apart from the rest.
static func danger_row(row: Dictionary) -> Control:
	var button := Button.new()
	button.name = str(row.id)
	button.text = str(row.label)
	button.custom_minimum_size.y = 54
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.add_theme_font_override("font", font(700))
	button.add_theme_font_size_override("font_size", 18)
	ControlTheme.danger(button, TRASH)
	var holder := pad(button, ROW_PAD, 18)
	holder.name = str(row.id) + "Row"
	return holder

## A choice: its label and note, then the options as one segmented control,
## beside the text when the panel is wide and under it when narrow.
static func choice_row(row: Dictionary, selected: String, stacked: bool) -> Control:
	var line := BoxContainer.new()
	line.vertical = stacked
	line.add_theme_constant_override("separation", 12 if stacked else 20)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(_texts(row))
	var track := PanelContainer.new()
	track.name = str(row.id)
	var style := rounded(SEGMENTS, 16)
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: style.set_content_margin(side, 4)
	track.add_theme_stylebox_override("panel", style)
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.mouse_filter = Control.MOUSE_FILTER_PASS
	var options := _hbox(4)
	options.name = "Options"
	track.add_child(options)
	var group := ButtonGroup.new()
	for option: Array in row.options:
		var button := Button.new()
		button.name = "Option_" + str(option[0])
		button.text = str(option[1])
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = str(option[0]) == selected
		button.set_meta("value", str(option[0]))
		button.custom_minimum_size = Vector2(112, 48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.mouse_filter = Control.MOUSE_FILTER_PASS
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_font_override("font", font(700))
		button.add_theme_font_size_override("font_size", 17)
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var fill := MINT if state in ["pressed", "hover_pressed"] else PRESSED if state == "hover" else Color(SEGMENTS, 0.0)
			button.add_theme_stylebox_override(state, ControlTheme.padded(rounded(fill, 12), 14.0, 6.0))
		button.add_theme_stylebox_override("focus", ControlTheme.padded(rounded(Color.TRANSPARENT, 12, INK, 2), 14.0, 6.0))
		for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(key, INK)
		button.add_theme_color_override("font_disabled_color", DISABLED_INK)
		options.add_child(button)
	line.add_child(track)
	var holder := pad(line, ROW_PAD, 20)
	holder.name = str(row.id) + "Row"
	return holder

## The option buttons of a choice row.
static func options(choice: Control) -> Array[Button]:
	var result: Array[Button] = []
	for child: Node in choice.get_node("Options").get_children(): result.append(child as Button)
	return result

static func divider() -> Control:
	var line := ColorRect.new()
	line.name = "Divider"
	line.color = DIVIDER
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var holder := pad(line, ROW_PAD, 0)
	holder.name = "DividerRow"
	return holder

## A gap with a hairline that sets the dangerous action apart.
static func separation() -> Control:
	var gap := Control.new()
	gap.name = "Separation"
	gap.custom_minimum_size.y = 18
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap

## Small text and controls shown inline under an action row.
static func detail_text(text: String, strong: bool = false) -> Label:
	var result := label(text, 18 if strong else 16, INK if strong else INK_SOFT, 700 if strong else 500)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result

static func detail_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 52
	button.pressed.connect(callback)
	quiet_button(button)
	return button

## A secondary button that reads on cream: a soft fill and an ink edge.
static func quiet_button(button: Button) -> void:
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", font(700))
	button.add_theme_font_size_override("font_size", 17)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var fill := SEGMENTS if state == "normal" else MINT if state in ["pressed", "hover_pressed"] else PRESSED if state == "hover" else PANEL
		var edge := Color(INK, 0.35) if state != "disabled" else Color(INK, 0.15)
		button.add_theme_stylebox_override(state, ControlTheme.padded(rounded(fill, 14, edge), 18.0, 8.0))
	button.add_theme_stylebox_override("focus", ControlTheme.padded(rounded(Color.TRANSPARENT, 14, INK, 2), 18.0, 8.0))
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(key, INK)
	button.add_theme_color_override("font_disabled_color", DISABLED_INK)
	button.add_theme_color_override("icon_disabled_color", DISABLED_INK)

## A read-only field on cream (recovery details).
static func detail_field(text: String) -> LineEdit:
	var field := LineEdit.new()
	field.text = text
	field.editable = false
	field.custom_minimum_size.y = 48
	field.add_theme_font_override("font", font(600))
	field.add_theme_font_size_override("font_size", 17)
	field.add_theme_stylebox_override("normal", ControlTheme.padded(rounded(FIELD, 12, Color(INK, 0.25)), 14.0, 8.0))
	field.add_theme_stylebox_override("read_only", ControlTheme.padded(rounded(FIELD, 12, Color(INK, 0.25)), 14.0, 8.0))
	field.add_theme_stylebox_override("focus", ControlTheme.padded(rounded(Color.TRANSPARENT, 12, INK, 2), 14.0, 8.0))
	for key: String in ["font_color", "font_uneditable_color", "font_selected_color"]:
		field.add_theme_color_override(key, INK)
	field.add_theme_color_override("selection_color", Color(MINT, 0.8))
	return field

## A labelled reset in a panel's title row. Greyed while there is nothing to reset.
static func reset_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = RESET
	button.expand_icon = false
	button.add_theme_constant_override("icon_max_width", 18)
	button.add_theme_constant_override("h_separation", 8)
	button.custom_minimum_size = Vector2(0, 48)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	quiet_button(button)
	return button

## One category in the rail: its icon, name and live summary. Selected, it is a mint pill.
static func rail_item(category: Dictionary, summary: String) -> Button:
	var button := Button.new()
	button.name = "category_" + str(category.id)
	button.accessibility_name = str(category.title)
	button.custom_minimum_size = Vector2(0, 70)
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var line := _hbox(17)
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 19
	line.offset_right = -4
	line.add_child(icon(category.icon, 22, CREAM))
	var texts := _vbox(1)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name := label(str(category.title), 18, CREAM, 700)
	name.name = "Name"
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.clip_text = true
	texts.add_child(name)
	var line_two := label(summary, 14, MUTED, 500)
	line_two.name = "Summary"
	line_two.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line_two.clip_text = true
	texts.add_child(line_two)
	line.add_child(texts)
	button.add_child(line)
	return button

static func select_rail_item(button: Button, selected: bool) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var fill := MINT if selected else Color(1, 1, 1, 0.07) if state in ["hover", "pressed", "hover_pressed"] else Color(PAGE, 0.0)
		button.add_theme_stylebox_override(state, rounded(fill, 16))
	button.add_theme_stylebox_override("focus", rounded(Color.TRANSPARENT, 16, MINT if not selected else CREAM, 2))
	var line := button.get_child(0)
	(line.get_child(0) as TextureRect).modulate = INK if selected else CREAM
	var texts := line.get_child(1)
	(texts.get_node("Name") as Label).add_theme_color_override("font_color", INK if selected else CREAM)
	(texts.get_node("Summary") as Label).add_theme_color_override("font_color", INK_SOFT if selected else MUTED)
	button.set_meta("selected", selected)

static func set_rail_summary(button: Button, summary: String) -> void:
	var text := button.get_child(0).get_child(1).get_node("Summary") as Label
	if text.text != summary: text.text = summary

## Done: cream, with a check, the page's one way back.
static func style_done(button: Button) -> void:
	button.icon = CHECK
	button.add_theme_constant_override("icon_max_width", 18)
	button.add_theme_constant_override("h_separation", 12)
	button.add_theme_font_override("font", font(700))
	button.add_theme_font_size_override("font_size", 19)
	button.custom_minimum_size = Vector2(124, 52)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var fill := CREAM if state == "normal" else Color("ffffff") if state == "hover" else MINT
		button.add_theme_stylebox_override(state, ControlTheme.padded(rounded(fill, 14), 22.0, 8.0))
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(key, INK)
	ControlTheme.center_icon_label(button, 22.0)

## The cream panel's own scroll bar: thin and soft, never a default grey.
static func style_scroll(scroll: ScrollContainer, on_cream: bool) -> void:
	var bar := scroll.get_v_scroll_bar()
	var grab := Color(INK, 0.32) if on_cream else Color(CREAM, 0.3)
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 6
	bar.add_theme_stylebox_override("scroll", empty)
	bar.add_theme_stylebox_override("scroll_focus", empty)
	for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var style := rounded(grab if state == "grabber" else Color(grab, minf(1.0, grab.a + 0.2)), 3)
		style.content_margin_left = 6
		bar.add_theme_stylebox_override(state, style)

## The big switch on a toggle tile: a mint track with a dark knob on the
## right and a small check on the left when on; a pale track with a grey knob
## on the left when off; faded while disabled. The knob slides over a moment,
## or snaps under Reduce motion. Drawn, so it stays crisp at any scale.
class Switch extends Control:
	const SLIDE := 0.16
	var button: BaseButton
	## Reduce motion: the knob snaps.
	var reduced := false
	## 0 off, 1 on; between while sliding.
	var _at := -1.0
	var _tween: Tween

	func _init() -> void:
		name = "Switch"
		custom_minimum_size = Vector2(88, 48)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		_at = 1.0 if _on() else 0.0

	func _on() -> bool:
		return is_instance_valid(button) and button.button_pressed

	func _set_at(value: float) -> void:
		_at = value
		queue_redraw()

	func _draw() -> void:
		var at := clampf(_at if _at >= 0.0 else (1.0 if _on() else 0.0), 0.0, 1.0)
		var rect := Rect2(Vector2(0, (size.y - custom_minimum_size.y) * 0.5), custom_minimum_size)
		var radius := rect.size.y * 0.5
		var track := StyleBoxFlat.new()
		track.set_corner_radius_all(int(radius))
		track.anti_aliasing = true
		track.bg_color = TRACK_OFF_TILE.lerp(MINT, at)
		track.border_color = TRACK_OFF_EDGE.lerp(TRACK_ON_EDGE, at)
		track.set_border_width_all(2)
		draw_style_box(track, rect)
		var knob := radius - 5.0
		var center := Vector2(lerpf(rect.position.x + radius, rect.end.x - radius, at), rect.position.y + radius)
		draw_circle(center, knob, KNOB_OFF_TILE.lerp(INK, at), true, -1.0, true)
		if at > 0.5:
			var tick := Vector2(rect.position.x + 24.0, rect.position.y + radius)
			var ink := Color(INK, (at - 0.5) * 2.0)
			draw_polyline(PackedVector2Array([tick + Vector2(-7.0, 0.5), tick + Vector2(-2.0, 5.0), tick + Vector2(7.0, -5.0)]), ink, 2.4, true)

	## After the state changed: slide (or snap) to it, and fade while disabled.
	func refresh() -> void:
		modulate.a = 0.45 if is_instance_valid(button) and button.disabled else 1.0
		var target := 1.0 if _on() else 0.0
		if is_instance_valid(_tween): _tween.kill()
		if reduced or not is_inside_tree() or _at < 0.0:
			_set_at(target)
		elif not is_equal_approx(_at, target):
			_tween = create_tween()
			_tween.tween_method(_set_at, _at, target, SLIDE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			queue_redraw()

extends Control
## The optional turn photo card ("Polaroid"): words and actions on the left, the photo in a
## slightly tilted polaroid on the right. One component for every photo state (ask, ready,
## sent, waiting on a check, problems, loading), so the flow only fills it in. It fits a
## landscape phone without scrolling: the canvas is 720 units tall from 800x360 to 1560x720,
## and the card shrinks as a whole if a screen is ever smaller than that.
const ControlTheme = preload("res://presentation/control_theme.gd")
const PhotoDate = preload("res://presentation/photo_date.gd")
## A pen script subset to the characters a date needs (assets/fonts/pen-date-OFL.txt).
const DATE_FONT = preload("res://assets/fonts/pen-date.ttf")
const DATE_INK := Color("5b5246")
const DATE_SIZE := 42
const CARD := Color("163c36")
const BORDER := Color("2f5d55")
const CREAM := Color("ecebd9")
const BODY := Color("b9cdc5")
const SWITCH_TEXT := Color("9fbdb3")
const PAPER := Color("f7f3e6")
const DASH := Color("bdb59c")
const GLYPH := Color("9a937c")
const INK := Color("14352f")
const TILT_DEGREES := 4.0
const CARD_WIDTH := 1000.0
const PAPER_SIZE := Vector2(300, 346)
const PHOTO_INSET := 18.0
const PHOTO_SIDE := 264.0
const HOLDER_SIZE := Vector2(330, 372)
const EDGE := 24.0
const ICONS := {
	"camera": '<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>',
	"send": '<path d="M4 12l16-8-6 16-3-7z"/>',
	"retake": '<path d="M20 11a8 8 0 1 0-2.3 5.7M20 5v6h-6"/>',
}
static var _textures: Dictionary = {}

var title_label: Label
var line_label: Label
## Primary action first, then secondary actions, in one row.
var actions: HBoxContainer
## Small extra choices under the actions, such as removing a sent photo.
var extras: HBoxContainer
## The "Ask after each turn" switch and its status line.
var footer: VBoxContainer
var paper: Control
var photo_view: TextureRect
var placeholder: Control
## The handwritten date on the bottom strip, when the photo has a capture time.
var date_label: Label
var reduced_motion := false
var _panel: PanelContainer
var _left: VBoxContainer

func build(title: String, line: String, title_font: Font = null) -> void:
	name = "PhotoCard"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.name = "PhotoCardPanel"
	var style := ControlTheme.rounded(CARD, 26, BORDER)
	style.set_border_width_all(2)
	ControlTheme.padded(style, 44.0, 40.0)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel) # Centred and, only if needed, shrunk by _fit.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_panel.add_child(row)
	_left = VBoxContainer.new()
	_left.add_theme_constant_override("separation", 0)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_left)
	title_label = _text(title, 40, CREAM)
	title_label.name = "PhotoTitle"
	if title_font != null: title_label.add_theme_font_override("font", title_font)
	_left.add_child(title_label)
	line_label = _text(line, 22, BODY)
	line_label.name = "PhotoLine"
	_left.add_child(_gap(10))
	_left.add_child(line_label)
	_left.add_child(_gap(30))
	actions = HBoxContainer.new()
	actions.name = "PhotoActions"
	actions.add_theme_constant_override("separation", 14)
	_left.add_child(actions)
	extras = HBoxContainer.new()
	extras.name = "PhotoExtras"
	extras.add_theme_constant_override("separation", 14)
	_left.add_child(extras)
	footer = VBoxContainer.new()
	footer.name = "PhotoFooter"
	footer.add_theme_constant_override("separation", 4)
	_left.add_child(footer)
	row.add_child(_polaroid())
	resized.connect(_fit)
	_panel.minimum_size_changed.connect(_fit.call_deferred)
	_fit.call_deferred()

## Shows the JPEG in the polaroid; empty or unreadable bytes keep the camera placeholder.
## taken_at (UTC seconds) writes the local capture date on the strip; 0 writes none.
func show_photo(bytes: PackedByteArray, settle: bool = false, taken_at: int = 0) -> bool:
	var texture := texture_from_jpeg(bytes)
	if texture == null: return false
	photo_view.texture = texture
	photo_view.visible = true
	placeholder.visible = false
	var date := PhotoDate.local(taken_at)
	if not date.is_empty(): _write_date(date)
	if settle and not reduced_motion:
		# A short settle as the photo lands. Reduced motion keeps the still tilt.
		paper.rotation_degrees = 0.0
		paper.scale = Vector2(0.94, 0.94)
		var tween := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(paper, "rotation_degrees", TILT_DEGREES, 0.3)
		tween.tween_property(paper, "scale", Vector2.ONE, 0.3)
	return true

func add_primary(text: String, callback: Callable, icon: String = "", node_name: String = "") -> Button:
	var button := _button(text, callback, true, icon, node_name)
	actions.add_child(button)
	return button

func add_secondary(text: String, callback: Callable, node_name: String = "") -> Button:
	var button := _button(text, callback, false, "", node_name)
	actions.add_child(button)
	return button

## A square icon action, such as retaking the photo. The label stays as its tooltip and name.
func add_icon(icon: String, label: String, callback: Callable, node_name: String = "") -> Button:
	var button := _button("", callback, false, icon, node_name)
	button.tooltip_text = label
	button.accessibility_name = label
	button.custom_minimum_size = Vector2(58, 58)
	button.add_theme_constant_override("icon_max_width", 26)
	actions.add_child(button)
	return button

func add_extra(text: String, callback: Callable, node_name: String = "") -> Button:
	if extras.get_child_count() == 0: _gap_before(extras, 16)
	var button := _button(text, callback, false, "", node_name)
	button.custom_minimum_size.y = 46
	button.add_theme_font_size_override("font_size", 18)
	extras.add_child(button)
	return button

## The "Ask after each turn" switch: on means the card opens after each shared turn. A toggle
## button keeps the switch art left of its words, as in the approved card.
func add_switch(text: String, pressed: bool) -> Button:
	if footer.get_child_count() == 0: _gap_before(footer, 22)
	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.text = text
	toggle.button_pressed = pressed
	toggle.icon = switch_icon(pressed)
	toggle.toggled.connect(func(on: bool): toggle.icon = switch_icon(on))
	toggle.mouse_filter = Control.MOUSE_FILTER_PASS
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	toggle.custom_minimum_size.y = 44
	toggle.add_theme_font_size_override("font_size", 19)
	toggle.add_theme_constant_override("h_separation", 12)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		toggle.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		toggle.add_theme_color_override(key, SWITCH_TEXT)
	for key: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		toggle.add_theme_color_override(key, Color.WHITE)
	footer.add_child(toggle)
	return toggle

func add_status() -> Label:
	var status := _text("", 17, BODY)
	footer.add_child(status)
	return status

static func texture_from_jpeg(bytes: PackedByteArray) -> Texture2D:
	if bytes.is_empty() or bytes.size() > 160 * 1024:
		return null
	var image := Image.new()
	if image.load_jpg_from_buffer(bytes) != OK or image.get_width() > 960 or image.get_height() > 960:
		return null
	return ImageTexture.create_from_image(image)

func _polaroid() -> Control:
	var holder := Control.new()
	holder.name = "PolaroidHolder"
	holder.custom_minimum_size = HOLDER_SIZE
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	paper = Panel.new()
	paper.name = "Polaroid"
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sheet := StyleBoxFlat.new()
	sheet.bg_color = PAPER
	sheet.set_corner_radius_all(8)
	sheet.shadow_color = Color(0, 0, 0, 0.28)
	sheet.shadow_size = 14
	sheet.shadow_offset = Vector2(0, 6)
	paper.add_theme_stylebox_override("panel", sheet)
	paper.size = PAPER_SIZE
	paper.position = (HOLDER_SIZE - PAPER_SIZE) * 0.5
	paper.pivot_offset = PAPER_SIZE * 0.5
	paper.rotation_degrees = TILT_DEGREES
	holder.add_child(paper)
	var window := Control.new()
	window.name = "PhotoWindow"
	window.clip_contents = true
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.position = Vector2(PHOTO_INSET, PHOTO_INSET)
	window.size = Vector2(PHOTO_SIDE, PHOTO_SIDE)
	paper.add_child(window)
	photo_view = TextureRect.new()
	photo_view.name = "LocalReactionPreview"
	photo_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	photo_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	photo_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo_view.size = window.size
	photo_view.visible = false
	window.add_child(photo_view)
	placeholder = Placeholder.new()
	placeholder.name = "PhotoPlaceholder"
	placeholder.size = window.size
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(placeholder)
	var glyph := TextureRect.new()
	glyph.texture = _icon("camera", 2.8)
	glyph.modulate = GLYPH
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.size = glyph.texture.get_size()
	glyph.position = (window.size - glyph.size) * 0.5
	placeholder.add_child(glyph)
	return holder

## One Label on the paper, so it turns with the polaroid's tilt. Built once; never redrawn.
func _write_date(text: String) -> void:
	if date_label == null:
		date_label = Label.new()
		date_label.name = "PolaroidDate"
		date_label.add_theme_font_override("font", DATE_FONT)
		date_label.add_theme_font_size_override("font_size", DATE_SIZE)
		date_label.add_theme_color_override("font_color", DATE_INK)
		date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		date_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		date_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var strip_top := PHOTO_INSET + PHOTO_SIDE
		date_label.position = Vector2(0, strip_top)
		date_label.size = Vector2(PAPER_SIZE.x, PAPER_SIZE.y - strip_top)
		paper.add_child(date_label)
	date_label.text = text

func _fit() -> void:
	if not is_instance_valid(_panel): return
	var width := clampf(size.x - EDGE * 2.0, 0.0, CARD_WIDTH)
	if width > 0.0: _panel.custom_minimum_size.x = width
	var needed := _panel.get_combined_minimum_size()
	if needed.x <= 0.0 or needed.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0: return
	var room := size - Vector2(EDGE, EDGE) * 2.0
	var shrink := minf(1.0, minf(room.x / needed.x, room.y / needed.y))
	_panel.size = needed
	_panel.position = ((size - needed) * 0.5).round()
	_panel.pivot_offset = needed * 0.5
	_panel.scale = Vector2(shrink, shrink)

func _button(text: String, callback: Callable, primary: bool, icon: String, node_name: String) -> Button:
	var button := Button.new()
	button.text = text
	if not node_name.is_empty(): button.name = node_name
	button.custom_minimum_size.y = 58
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(callback)
	if not primary: ControlTheme.secondary(button)
	if not icon.is_empty():
		button.icon = _icon(icon, 1.15)
		button.add_theme_constant_override("h_separation", 10)
		var tint := INK if primary else CREAM
		for key: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
			button.add_theme_color_override(key, tint)
	return button

func _text(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 420
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = not value.is_empty()
	return label

func _gap_before(section: Control, height: float) -> void:
	var gap := _gap(height)
	_left.add_child(gap)
	_left.move_child(gap, section.get_index())

func _gap(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap

## Line icons drawn white so a button's icon colours tint them. Built once per size.
static func _icon(key: String, scale: float) -> Texture2D:
	var cache_key := "%s@%.2f" % [key, scale]
	if not _textures.has(cache_key):
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">%s</svg>' % ICONS[key]
		var image := Image.new()
		image.load_svg_from_string(svg, scale)
		_textures[cache_key] = ImageTexture.create_from_image(image)
	return _textures[cache_key]

static func switch_icon(on: bool) -> Texture2D:
	var cache_key := "switch-on" if on else "switch-off"
	if not _textures.has(cache_key):
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="50" height="29" viewBox="0 0 50 29"><rect width="50" height="29" rx="14.5" fill="%s"/><circle cx="%s" cy="14.5" r="10.5" fill="%s"/></svg>' % (["#7fc4ad", "35.5", "#14352f"] if on else ["#3f6f64", "14.5", "#b9cdc5"])
		var image := Image.new()
		image.load_svg_from_string(svg, 1.0)
		_textures[cache_key] = ImageTexture.create_from_image(image)
	return _textures[cache_key]

## The empty photo window: a dashed frame the camera glyph sits in.
class Placeholder extends Control:
	func _draw() -> void:
		var inset := 3.0
		var box := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
		var corners := [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]
		for index: int in corners.size():
			draw_dashed_line(corners[index], corners[(index + 1) % corners.size()], DASH, 2.5, 9.0)

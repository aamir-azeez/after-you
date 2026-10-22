extends CanvasLayer
## Typing on a phone held sideways: the on screen keyboard covers most of the
## screen, and the field being typed in is small or hidden under it. While the
## keyboard is up, this layer dims the page and shows that field large in the
## space above the keyboard, with the field's own label as its title.
##
## One layer per viewport (install), hooked to the viewport's focus, so no
## screen registers its fields: any editable LineEdit that takes focus counts.
## A field may name its title and a note shown under it (describe); without one
## the title is its accessibility name, then its placeholder.
##
## The real field keeps focus and the keyboard. The large copy only shows what
## the field holds (text or its secret dots, placeholder, caret, selection), so
## typing, max length, paste, Enter and every text_changed check stay the
## field's own, with one source of truth.
##
## Nothing runs while no field has focus. While one has, a tick ten times a
## second reads the keyboard height. A desktop has no on screen keyboard and
## nothing shows. A press on the dim closes the keyboard: the field lets go of
## focus. A field that leaves the tree (a screen change, a rebuilt page) takes
## the copy away at once; a field that takes its place brings it back.
const SafeArea = preload("res://presentation/safe_area.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const FREDOKA = preload("res://assets/fonts/fredoka.ttf")

const NAME := "KeyboardFocus"
## Above every screen and its menus (room hub 60, choice lists one over their
## host), under the toast and the chapter loading card (90).
const LAYER := 80
const INSTALLED_META := &"keyboard_focus"
const TITLE_META := &"keyboard_focus_title"
const NOTE_META := &"keyboard_focus_note"
const POLL_SECONDS := 0.1
## A keyboard covering less than this many canvas units leaves the page as it
## is (a hardware keyboard's strip, a keyboard still sliding in).
const MIN_COVER := 100.0
const WIDTH := 860.0
const EDGE := 12.0
const PANEL_FILL := Color("1d4a44")
const PANEL_BORDER := Color("3f6b61")
const FIELD_FILL := Color("123533")

## Tests and captures: the keyboard's height in canvas units, used instead of
## the platform's (desktop included) while 0 or more. -1 clears it.
static var _simulated := -1.0

var _target: WeakRef = null
var _timer: Timer
var _area: Control
var _panel: PanelContainer
var _title: Label
var _copy: LargeField
var _note: Label

## Puts the one layer in `viewport` and returns it. A second call returns the
## same layer. The layer arrives at the end of the frame (the viewport may be
## busy adding the screen that asked).
static func install(viewport: Viewport) -> CanvasLayer:
	var existing: Variant = viewport.get_meta(INSTALLED_META) if viewport.has_meta(INSTALLED_META) else null
	if existing is CanvasLayer and is_instance_valid(existing): return existing
	var layer: CanvasLayer = load("res://presentation/keyboard_focus.gd").new()
	layer.name = NAME
	viewport.set_meta(INSTALLED_META, layer)
	viewport.add_child.call_deferred(layer, false, Node.INTERNAL_MODE_BACK)
	return layer

static func simulate(cover: float) -> void:
	_simulated = cover

## Whether this build watches for a keyboard at all: a phone, or a simulation.
static func watching() -> bool:
	return _simulated >= 0.0 or PlatformSupport.is_phone()

## The title and an optional note (a counter, say) shown with the large field.
## The note's words and colour follow the label as it changes.
static func describe(field: LineEdit, title: String, note: Label = null) -> void:
	field.set_meta(TITLE_META, title)
	if note != null: field.set_meta(NOTE_META, weakref(note))

static func title_of(field: LineEdit) -> String:
	var named := str(field.get_meta(TITLE_META, ""))
	if not named.is_empty(): return named
	if not field.accessibility_name.is_empty(): return field.accessibility_name
	return field.placeholder_text

static func note_of(field: LineEdit) -> Label:
	var held: Variant = field.get_meta(NOTE_META) if field.has_meta(NOTE_META) else null
	if not held is WeakRef: return null
	var note: Variant = (held as WeakRef).get_ref()
	return note as Label if is_instance_valid(note) else null

## A field the player types in: an editable, focusable LineEdit on screen.
static func eligible(control: Control) -> bool:
	if not control is LineEdit or not is_instance_valid(control) or not control.is_inside_tree(): return false
	var field := control as LineEdit
	return field.editable and field.focus_mode != Control.FOCUS_NONE and field.is_visible_in_tree()

## The keyboard's cover of `viewport` in canvas units: DisplayServer reports
## physical pixels of the window.
static func cover(viewport: Viewport) -> float:
	if _simulated >= 0.0: return _simulated
	if not PlatformSupport.is_phone(): return 0.0
	return cover_units(float(DisplayServer.virtual_keyboard_get_height()), float(DisplayServer.window_get_size().y), viewport.get_visible_rect().size.y)

static func cover_units(native_height: float, window_height: float, visible_height: float) -> float:
	if native_height <= 0.0 or window_height <= 0.0: return 0.0
	return minf(native_height * visible_height / window_height, visible_height)

## The field shown large now, or null.
func target() -> LineEdit:
	var field: Variant = _target.get_ref() if _target != null else null
	return field as LineEdit if is_instance_valid(field) else null

## True while the large field shows.
func showing() -> bool:
	return visible

func _ready() -> void:
	layer = LAYER
	visible = false
	# Typing goes on in a paused tree too.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_timer = Timer.new()
	_timer.wait_time = POLL_SECONDS
	_timer.timeout.connect(poll)
	add_child(_timer)
	get_viewport().gui_focus_changed.connect(_focus_changed)

func _build() -> void:
	var page := Control.new()
	page.name = "KeyboardFocusPage"
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)
	var shade := ColorRect.new()
	shade.name = "KeyboardFocusShade"
	shade.color = Color(0.02, 0.08, 0.08, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	SafeArea.bleed(shade)
	shade.gui_input.connect(_shade_input)
	page.add_child(shade)
	_area = Control.new()
	_area.name = "KeyboardFocusArea"
	_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_area)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area.add_child(center)
	_panel = PanelContainer.new()
	_panel.name = "KeyboardFocusPanel"
	_panel.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(PANEL_FILL, 22, PANEL_BORDER), 26.0, 20.0))
	center.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)
	_title = Label.new()
	_title.name = "KeyboardFocusTitle"
	var heading := FontVariation.new()
	heading.base_font = FREDOKA
	heading.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	_title.add_theme_font_override("font", heading)
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", ThemeRules.CREAM)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_title)
	var box := PanelContainer.new()
	box.name = "KeyboardFocusBox"
	var box_style := ThemeRules.rounded(FIELD_FILL, 14, ThemeRules.CREAM)
	box_style.set_border_width_all(2)
	box.add_theme_stylebox_override("panel", ThemeRules.padded(box_style, 20.0, 12.0))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(box)
	_copy = LargeField.new()
	_copy.name = "KeyboardFocusField"
	box.add_child(_copy)
	_note = Label.new()
	_note.name = "KeyboardFocusNote"
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_note.add_theme_font_size_override("font_size", 17)
	column.add_child(_note)

func _focus_changed(_control: Control) -> void:
	if watching(): poll()

## Reads focus and the keyboard once, and shows, refreshes or hides the large
## field. The tick calls it; tests call it to step. Returns whether it shows.
func poll() -> bool:
	if not is_inside_tree(): return false
	var focused := get_viewport().gui_get_focus_owner()
	var field := focused as LineEdit if watching() and eligible(focused) else null
	if field != target(): _follow(field)
	if field == null:
		_timer.stop()
		_hide()
		return false
	if _timer.is_stopped(): _timer.start()
	var covered := cover(get_viewport())
	if covered < MIN_COVER:
		_hide()
		return false
	_show(field, covered)
	return true

func _follow(field: LineEdit) -> void:
	var old := target()
	if old != null:
		if old.text_changed.is_connected(_typed): old.text_changed.disconnect(_typed)
		if old.tree_exiting.is_connected(_left): old.tree_exiting.disconnect(_left)
	_target = weakref(field) if field != null else null
	if field != null:
		field.text_changed.connect(_typed)
		field.tree_exiting.connect(_left)

## Typing shows at once, with any note the field's own handlers just changed.
func _typed(_text: String) -> void:
	if visible: poll()

## A field freed or moved off screen takes the copy with it now; whatever takes
## focus next brings it back on its own.
func _left() -> void:
	_follow(null)
	_hide()

func _show(field: LineEdit, covered: float) -> void:
	var viewport := get_viewport()
	var shown := viewport.get_visible_rect()
	var safe := SafeArea.rect(viewport)
	var bottom := maxf(covered, shown.end.y - safe.end.y)
	_set_offsets(_area, Vector4(safe.position.x - shown.position.x + EDGE, safe.position.y - shown.position.y + EDGE, safe.end.x - shown.end.x - EDGE, -bottom - EDGE))
	var free_height := shown.size.y - bottom - (safe.position.y - shown.position.y) - EDGE * 2.0
	var title := title_of(field)
	_title.text = title
	_title.visible = not title.is_empty()
	var note := note_of(field)
	_note.visible = note != null and not note.text.is_empty()
	if _note.visible:
		_note.text = note.text
		_note.add_theme_color_override("font_color", note.get_theme_color("font_color"))
	# Room for the panel's padding, the title and the note; the field takes
	# the rest, between a size that reads at a glance and one that fits.
	var around := 40.0 + 24.0 + (44.0 if _title.visible else 0.0) + (34.0 if _note.visible else 0.0)
	var text_size := clampi(int((free_height - around) / 1.4), 24, 44)
	_panel.custom_minimum_size.x = clampf(safe.size.x - EDGE * 2.0 - 48.0, 280.0, WIDTH)
	_copy.placeholder_hidden = title == field.placeholder_text
	_copy.show_field(field, text_size)
	visible = true

func _hide() -> void:
	visible = false

func _shade_input(event: InputEvent) -> void:
	var press := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if not press or not visible: return
	get_viewport().set_input_as_handled()
	var field := target()
	if field != null and field.has_focus(): field.release_focus()
	_hide()

static func _set_offsets(control: Control, edges: Vector4) -> void:
	if edges.is_equal_approx(Vector4(control.offset_left, control.offset_top, control.offset_right, control.offset_bottom)): return
	control.offset_left = edges.x
	control.offset_top = edges.y
	control.offset_right = edges.z
	control.offset_bottom = edges.w

## The large copy of a field: its words in its own font and colours, the caret
## where the field's caret is, the selection behind, and the end of a long line
## scrolled into view around the caret. Draws only when something changed.
class LargeField extends Control:
	var font_size := 40
	var placeholder_hidden := false
	var shown_text := ""
	var placeholder := ""
	var caret := 0
	var selection := Vector2i(-1, -1)
	var _font: Font
	var _colors: Array[Color] = []

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func show_field(field: LineEdit, text_size: int) -> void:
		var text := field.text
		if field.secret: text = field.secret_character.left(1).repeat(text.length()) if not field.secret_character.is_empty() else text
		var seen := Vector2i(field.get_selection_from_column(), field.get_selection_to_column()) if field.has_selection() else Vector2i(-1, -1)
		var font := field.get_theme_font("font")
		var colors: Array[Color] = [field.get_theme_color("font_color"), field.get_theme_color("font_placeholder_color"), field.get_theme_color("caret_color"), field.get_theme_color("selection_color")]
		var hint := "" if placeholder_hidden else field.placeholder_text
		if text == shown_text and hint == placeholder and field.caret_column == caret and seen == selection and text_size == font_size and font == _font and colors == _colors: return
		shown_text = text
		placeholder = hint
		caret = clampi(field.caret_column, 0, text.length())
		selection = seen
		font_size = text_size
		_font = font
		_colors = colors
		custom_minimum_size.y = ceilf(_font.get_height(font_size)) + 4.0
		queue_redraw()

	func _draw() -> void:
		if _font == null: return
		var line := _font.get_height(font_size)
		var top := (size.y - line) * 0.5
		var baseline := top + _font.get_ascent(font_size)
		if shown_text.is_empty():
			if not placeholder.is_empty(): draw_string(_font, Vector2(0.0, baseline), placeholder, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _colors[1])
			draw_rect(Rect2(0.0, top, 3.0, line), _colors[2])
			return
		var full := _width(shown_text)
		var at := _width(shown_text.left(caret))
		# Keep the caret in view, a little in from the right edge.
		var room := 6.0
		var scroll := clampf(at - size.x + room, 0.0, maxf(0.0, full - size.x + room))
		if selection.x >= 0:
			var from := _width(shown_text.left(selection.x)) - scroll
			var to := _width(shown_text.left(selection.y)) - scroll
			draw_rect(Rect2(from, top, to - from, line), _colors[3])
		draw_string(_font, Vector2(-scroll, baseline), shown_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _colors[0])
		draw_rect(Rect2(at - scroll, top, 3.0, line), _colors[2])

	func _width(text: String) -> float:
		return _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

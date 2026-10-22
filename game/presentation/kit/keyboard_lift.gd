extends CanvasLayer
## Keyboard lift: the field a player types in shows large above the on screen
## keyboard. On a phone held sideways the keyboard covers most of the screen,
## so the field itself is small or hidden under it.
##
## Usage, one line for every LineEdit a player types in:
##   KeyboardLift.attach(field)                     # titled by its accessibility name, then its placeholder
##   KeyboardLift.attach(field, "Friend code")      # titled by its own label's words
##   KeyboardLift.attach(field, title, counter)     # and a Label (a counter) shown under it
## A read only field (editable = false) needs nothing. tests/test_keyboard_lift_wired.gd
## fails for a LineEdit or TextEdit made with neither.
##
## While an attached field has focus and the keyboard is up, one layer in the
## field's viewport dims the page and draws a large copy of the field, centred
## in the space above the keyboard: its words (or secret dots), placeholder,
## caret and selection, with the title above and the note below.
##
## The real field keeps focus and the keyboard. The copy only shows what the
## field holds, so typing, max length, paste, Enter and every text_changed
## check stay the field's own: one source of truth, no second editor.
##
## Cost: nothing at all until an attached field takes focus (the layer is made
## then, once per viewport). While one has focus, a timer ten times a second
## reads the keyboard height; the copy redraws and relays out only when
## something it shows changed. A desktop has no on screen keyboard: nothing is
## made, nothing shows.
##
## It always clears: when the keyboard goes down (Back, Enter), focus leaves
## the field (a tap outside, another control), the field leaves the tree or
## hides (a screen change, a rebuilt page), or the app is paused or loses
## focus. A press outside the card also reaches what it landed on, so a Save or
## Join button showing through the dim works on the first tap. A tap on the
## copy puts the caret there.
const SafeArea = preload("res://presentation/safe_area.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const FREDOKA = preload("res://assets/fonts/fredoka.ttf")

const NAME := "KeyboardLift"
## Above every screen and its menus (room hub 60, choice lists one over their
## host), under the toast and the chapter loading card (90).
const LAYER := 80
const LAYER_META := &"keyboard_lift_layer"
const FIELD_META := &"keyboard_lift"
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
var _paused := false
var _timer: Timer
var _area: Control
var _panel: PanelContainer
var _title: Label
var _copy: LargeField
var _note: Label

# --- The API -----------------------------------------------------------------

## Wires `field` for the lift and returns it. `title` names it above the copy
## (empty: its accessibility name, then its placeholder); `note` is a Label
## whose words and colour show under the copy. A second call updates both.
static func attach(field: LineEdit, title: String = "", note: Label = null) -> LineEdit:
	var known := field.has_meta(FIELD_META)
	field.set_meta(FIELD_META, {"title": title, "note": weakref(note) if note != null else null})
	if not known: field.focus_entered.connect(func() -> void: _woken(field))
	return field

static func attached(field: Control) -> bool:
	return field is LineEdit and field.has_meta(FIELD_META)

## An attached field the player can type in now: editable, focusable, shown.
static func eligible(control: Control) -> bool:
	if not is_instance_valid(control) or not attached(control) or not control.is_inside_tree(): return false
	var field := control as LineEdit
	return field.editable and field.focus_mode != Control.FOCUS_NONE and field.is_visible_in_tree()

static func title_of(field: LineEdit) -> String:
	var named := str((field.get_meta(FIELD_META) as Dictionary).get("title", "")) if field.has_meta(FIELD_META) else ""
	if not named.is_empty(): return named
	if not field.accessibility_name.is_empty(): return field.accessibility_name
	return field.placeholder_text

static func note_of(field: LineEdit) -> Label:
	if not field.has_meta(FIELD_META): return null
	var held: Variant = (field.get_meta(FIELD_META) as Dictionary).get("note")
	var note: Variant = (held as WeakRef).get_ref() if held is WeakRef else null
	return note as Label if is_instance_valid(note) else null

static func simulate(cover_units: float) -> void:
	_simulated = cover_units

## Whether this build watches for a keyboard at all: a phone, or a simulation.
static func watching() -> bool:
	return _simulated >= 0.0 or PlatformSupport.is_phone()

## The keyboard's cover of `viewport` in canvas units (0 without one). The
## in-game modal lifts its card by the same amount.
static func cover(viewport: Viewport) -> float:
	if _simulated >= 0.0: return _simulated
	if not PlatformSupport.is_phone(): return 0.0
	return cover_units(float(DisplayServer.virtual_keyboard_get_height()), float(DisplayServer.window_get_size().y), viewport.get_visible_rect().size.y)

## DisplayServer reports physical pixels of the window; controls use canvas units.
static func cover_units(native_height: float, window_height: float, visible_height: float) -> float:
	if native_height <= 0.0 or window_height <= 0.0: return 0.0
	return minf(native_height * visible_height / window_height, visible_height)

## The layer of `viewport`, made on first use, or null when there is none yet.
static func layer_of(viewport: Viewport) -> CanvasLayer:
	var held: Variant = viewport.get_meta(LAYER_META) if viewport.has_meta(LAYER_META) else null
	return held as CanvasLayer if is_instance_valid(held) else null

static func _woken(field: LineEdit) -> void:
	if not watching() or not field.is_inside_tree(): return
	var viewport := field.get_viewport()
	var layer := layer_of(viewport)
	if layer == null:
		layer = load("res://presentation/kit/keyboard_lift.gd").new()
		layer.name = NAME
		viewport.set_meta(LAYER_META, layer)
		# The viewport may be busy adding the screen that gave the focus; the
		# layer reads focus as it arrives.
		viewport.add_child.call_deferred(layer, false, Node.INTERNAL_MODE_BACK)
	elif layer.is_inside_tree():
		layer.poll()

# --- The layer ---------------------------------------------------------------

## The field shown large now, or null.
func target() -> LineEdit:
	var field: Variant = _target.get_ref() if _target != null else null
	return field as LineEdit if is_instance_valid(field) else null

func showing() -> bool:
	return visible

func ticking() -> bool:
	return _timer != null and not _timer.is_stopped()

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
	# Focus moving to any other control takes the copy away at once.
	get_viewport().gui_focus_changed.connect(_focus_moved)
	poll()

func _build() -> void:
	var page := Control.new()
	page.name = "KeyboardLiftPage"
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)
	var shade := ColorRect.new()
	shade.name = "KeyboardLiftShade"
	shade.color = Color(0.02, 0.08, 0.08, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Draws only: a press outside the card goes on to the page (_input).
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	SafeArea.bleed(shade)
	page.add_child(shade)
	_area = Control.new()
	_area.name = "KeyboardLiftArea"
	_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_area)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area.add_child(center)
	_panel = PanelContainer.new()
	_panel.name = "KeyboardLiftPanel"
	_panel.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(PANEL_FILL, 22, PANEL_BORDER), 26.0, 20.0))
	center.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)
	_title = Label.new()
	_title.name = "KeyboardLiftTitle"
	var heading := FontVariation.new()
	heading.base_font = FREDOKA
	heading.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	_title.add_theme_font_override("font", heading)
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", ThemeRules.CREAM)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_title)
	var box := PanelContainer.new()
	box.name = "KeyboardLiftBox"
	var box_style := ThemeRules.rounded(FIELD_FILL, 14, ThemeRules.CREAM)
	box_style.set_border_width_all(2)
	box.add_theme_stylebox_override("panel", ThemeRules.padded(box_style, 20.0, 12.0))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(box)
	_copy = LargeField.new()
	_copy.name = "KeyboardLiftField"
	_copy.gui_input.connect(_copy_input)
	box.add_child(_copy)
	_note = Label.new()
	_note.name = "KeyboardLiftNote"
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_note.add_theme_font_size_override("font_size", 17)
	column.add_child(_note)

## Reads focus and the keyboard once, and shows, refreshes or hides the copy.
## The timer and the field's signals call it; tests call it to step. Returns
## whether the copy shows.
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
	if _paused or covered < MIN_COVER:
		_hide()
		return false
	_show(field, covered)
	return true

## Listens to one field at a time; the last one's connections go first.
func _follow(field: LineEdit) -> void:
	var old := target()
	if old != null:
		for pair: Array in _listened(old):
			if (pair[0] as Signal).is_connected(pair[1]): (pair[0] as Signal).disconnect(pair[1])
	_target = weakref(field) if field != null else null
	if field != null:
		for pair: Array in _listened(field):
			if not (pair[0] as Signal).is_connected(pair[1]): (pair[0] as Signal).connect(pair[1])

func _listened(field: LineEdit) -> Array:
	return [[field.text_changed, _typed], [field.focus_exited, _recheck], [field.visibility_changed, _recheck], [field.tree_exiting, _left]]

func _focus_moved(_control: Control) -> void:
	poll()

## Typing shows at once, with any note the field's own handlers just changed.
func _typed(_text: String) -> void:
	if visible: poll()

## Focus gone or the field hidden: read again now, not at the next tick.
func _recheck() -> void:
	poll()

## The field leaving the tree (a screen change, a rebuilt page) takes the copy
## now; a field that takes focus next brings it back on its own.
func _left() -> void:
	_follow(null)
	_hide()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_paused = true
			_hide()
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			_paused = false
			if is_inside_tree() and _timer != null: poll()

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
		var ink := note.get_theme_color("font_color")
		if not _note.has_theme_color_override("font_color") or _note.get_theme_color("font_color") != ink: _note.add_theme_color_override("font_color", ink)
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

static func _press(event: InputEvent) -> bool:
	if event is InputEventMouseButton: return (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	return event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed

## A press outside the card closes the keyboard and is not used up: the same
## press reaches the button, field or page under it. On Android one tap comes
## as an emulated mouse press and a touch; the first closes, the second finds
## nothing showing.
func _input(event: InputEvent) -> void:
	if not visible or not _press(event): return
	var at: Vector2 = (event as InputEventMouseButton).position if event is InputEventMouseButton else (event as InputEventScreenTouch).position
	if _panel.get_global_rect().has_point(at): return
	var field := target()
	_hide()
	if field != null and field.has_focus(): field.release_focus()

## A tap on the copy puts the field's caret there, and tells the keyboard, as
## a tap on the field itself does (its suggestions work at the caret).
func _copy_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not _press(event): return
	var field := target()
	if field == null: return
	var column := _copy.column_at((event as InputEventMouseButton).position.x)
	field.deselect()
	field.caret_column = column
	if PlatformSupport.is_phone() and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) and field.virtual_keyboard_enabled:
		DisplayServer.virtual_keyboard_show(field.text, field.get_global_rect(), field.virtual_keyboard_type as DisplayServer.VirtualKeyboardType, field.max_length, column, column)
	poll()

static func _set_offsets(control: Control, edges: Vector4) -> void:
	if edges.is_equal_approx(Vector4(control.offset_left, control.offset_top, control.offset_right, control.offset_bottom)): return
	control.offset_left = edges.x
	control.offset_top = edges.y
	control.offset_right = edges.z
	control.offset_bottom = edges.w

## The large copy of a field: its words in its own font and colours, the caret
## where the field's caret is, the selection behind, and a long line scrolled
## to keep the caret in view. Redraws only when something it shows changed.
class LargeField extends Control:
	var font_size := 40
	var placeholder_hidden := false
	var shown_text := ""
	var placeholder := ""
	var caret := 0
	var selection := Vector2i(-1, -1)
	var _font: Font
	var _ink := Color.WHITE
	var _hint_ink := Color.WHITE
	var _caret_ink := Color.WHITE
	var _selection_ink := Color.WHITE
	var _scroll := 0.0

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func show_field(field: LineEdit, text_size: int) -> void:
		var text := field.text
		if field.secret and not field.secret_character.is_empty(): text = field.secret_character.left(1).repeat(text.length())
		var seen := Vector2i(field.get_selection_from_column(), field.get_selection_to_column()) if field.has_selection() else Vector2i(-1, -1)
		var font := field.get_theme_font("font")
		var ink := field.get_theme_color("font_color")
		var hint_ink := field.get_theme_color("font_placeholder_color")
		var caret_ink := field.get_theme_color("caret_color")
		var selection_ink := field.get_theme_color("selection_color")
		var hint := "" if placeholder_hidden else field.placeholder_text
		var at := clampi(field.caret_column, 0, text.length())
		if text == shown_text and hint == placeholder and at == caret and seen == selection and text_size == font_size and font == _font and ink == _ink and hint_ink == _hint_ink and caret_ink == _caret_ink and selection_ink == _selection_ink: return
		shown_text = text
		placeholder = hint
		caret = at
		selection = seen
		_font = font
		_ink = ink
		_hint_ink = hint_ink
		_caret_ink = caret_ink
		_selection_ink = selection_ink
		if text_size != font_size or custom_minimum_size.y == 0.0:
			font_size = text_size
			custom_minimum_size.y = ceilf(_font.get_height(font_size)) + 4.0
		queue_redraw()

	func _draw() -> void:
		if _font == null: return
		var line := _font.get_height(font_size)
		var top := (size.y - line) * 0.5
		var baseline := top + _font.get_ascent(font_size)
		if shown_text.is_empty():
			_scroll = 0.0
			if not placeholder.is_empty(): draw_string(_font, Vector2(0.0, baseline), placeholder, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _hint_ink)
			draw_rect(Rect2(0.0, top, 3.0, line), _caret_ink)
			return
		var full := _width(shown_text)
		var at := _width(shown_text.left(caret))
		# Keep the caret in view, a little in from the right edge.
		var room := 6.0
		_scroll = clampf(at - size.x + room, 0.0, maxf(0.0, full - size.x + room))
		if selection.x >= 0:
			var from := _width(shown_text.left(selection.x)) - _scroll
			var to := _width(shown_text.left(selection.y)) - _scroll
			draw_rect(Rect2(from, top, to - from, line), _selection_ink)
		draw_string(_font, Vector2(-_scroll, baseline), shown_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _ink)
		draw_rect(Rect2(at - _scroll, top, 3.0, line), _caret_ink)

	## The column nearest `x` (this control's own units) as last drawn.
	func column_at(x: float) -> int:
		if _font == null or shown_text.is_empty(): return 0
		var best := 0
		var gap := INF
		for column in range(shown_text.length() + 1):
			var off := absf(_width(shown_text.left(column)) - _scroll - x)
			if off < gap:
				gap = off
				best = column
		return best

	func _width(text: String) -> float:
		return _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

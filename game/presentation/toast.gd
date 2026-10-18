extends CanvasLayer
## The app's one pop-up: a cream card near the top of the screen that says a
## short line for SHOW_SEC and then goes.
##
## - It draws above every screen (Friends is layer 50, the room hub 60) and below
##   the version badge (100). Only its action button takes input, so the page
##   or chapter under it keeps every tap and drag.
## - post() shows a line at once, replacing the one showing. A line with an
##   action (a "View") is the one worth keeping: a plain line that replaces it
##   holds it, and it comes back for at least HELD_MIN_SEC once that line goes.
##   A newer action line drops the held one. Nothing else queues.
## - A line with an icon is friend news: it gets the icon and a bar that drains
##   while it shows. Other lines look as the pop-up always has, centred text.
## - It sits inside the safe area. While `in_header` says so (Friends is up) it
##   sits in the page's header row, so the page under it never moves.
## - With Reduce motion it shows and goes at once and the bar stays hidden;
##   otherwise it fades in and out over FADE_SEC.
## Main owns the one instance (Main.toast) and sets `theme`, `reduced_motion`
## and `in_header`.
const SafeArea = preload("res://presentation/safe_area.gd")
const FRIENDS_ICON = preload("res://assets/ui/social/users.svg")
const LAYER := 90
const CREAM := Color("eceddb")
const INK := Color("193d39")
## The draining bar: the mint of the app, a step darker so it reads on cream.
const BAR := Color("86c2ac")
const ICON_DISC := Color("d2e4da")
const SHOW_SEC := 6.0
const HELD_MIN_SEC := 3.0
const FADE_SEC := 0.18
const FONT_SIZE := 18
## Width and distance from the top of the safe area, in the default spot and in a header row.
const WIDTH := 700.0
const TOP := 112.0
const HEADER_WIDTH := 520.0
const HEADER_TOP := 22.0
const HEIGHT := 60.0
const SIDE_GAP := 16.0
const ICON_SIZE := 36.0
## Between the icon, the line and the button.
const GAP := 14.0
const BAR_HEIGHT := 4.0
## The bar keeps this far from the card's sides, inside its rounded corners.
const BAR_INSET := 8.0

## The line showing now, or the last one shown ("" before the first).
var text := ""
## The fonts and colours of the screens; Main passes its own.
var theme: Theme:
	set(value):
		theme = value
		if is_instance_valid(_root): _root.theme = value
## Returns true while the player asked for less motion.
var reduced_motion: Callable
## Returns true while the screen up has a header row the pop-up sits in.
var in_header: Callable
## The card; exposed for layout checks.
var card: Panel
var label: Label
var _root: Control
var _icon_disc: Panel
var _icon: TextureRect
var _action: Button
var _bar: ColorRect
## {text, icon, action_text, action, left, total}; empty while nothing shows.
var _current: Dictionary = {}
var _held: Dictionary = {}
var _header := false
## Fade direction: 1 while appearing, -1 while going, 0 at rest.
var _fade := 0

## Built at once, so a line posted before the pop-up enters the tree (a test's
## Main) is kept and shows when it does.
func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	_root.name = "Toast"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = theme
	add_child(_root)
	card = Panel.new()
	card.name = "ToastCard"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = CREAM
	style.set_corner_radius_all(12)
	style.shadow_color = Color(0, 0, 0, 0.22)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 3)
	card.add_theme_stylebox_override("panel", style)
	_root.add_child(card)
	_icon_disc = Panel.new()
	_icon_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_disc.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	var disc := StyleBoxFlat.new()
	disc.bg_color = ICON_DISC
	disc.set_corner_radius_all(int(ICON_SIZE / 2.0))
	_icon_disc.add_theme_stylebox_override("panel", disc)
	card.add_child(_icon_disc)
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_icon.modulate = INK
	_icon.position = Vector2(8, 8)
	_icon.size = Vector2(ICON_SIZE - 16, ICON_SIZE - 16)
	_icon_disc.add_child(_icon)
	label = Label.new()
	label.name = "ToastText"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", INK)
	card.add_child(label)
	_action = Button.new()
	_action.name = "ToastAction"
	_action.custom_minimum_size = Vector2(84, 40)
	_action.focus_mode = Control.FOCUS_NONE
	_action.add_theme_font_size_override("font_size", FONT_SIZE)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var outline := StyleBoxFlat.new()
		outline.bg_color = Color(INK, 0.12 if state in ["pressed", "hover_pressed"] else 0.06 if state == "hover" else 0.0)
		outline.set_corner_radius_all(10)
		outline.set_border_width_all(2)
		outline.border_color = INK
		outline.content_margin_left = 16
		outline.content_margin_right = 16
		_action.add_theme_stylebox_override(state, outline)
		_action.add_theme_color_override("font_color" if state == "normal" else "font_" + state + "_color", INK)
	_action.pressed.connect(_act)
	card.add_child(_action)
	_bar = ColorRect.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.color = BAR
	card.add_child(_bar)

func _ready() -> void:
	SafeArea.watch(self, _place)
	_place()

## Shows `line` now. `icon` marks friend news; `action_text` with `action` adds
## a button that runs `action` once and closes the pop-up.
func post(line: String, icon: Texture2D = null, action_text: String = "", action: Callable = Callable()) -> void:
	if line.is_empty(): return
	var entry := {"text": line, "icon": icon, "action_text": action_text if action.is_valid() else "", "action": action, "left": SHOW_SEC, "total": SHOW_SEC}
	if not entry.action_text.is_empty(): _held = {}
	elif _showing() and not _current.action_text.is_empty() and _current.text != line:
		_held = _current.duplicate()
		_held.left = maxf(_held.left, HELD_MIN_SEC)
	_show(entry)

## Closes the pop-up at once and forgets any held line.
func dismiss() -> void:
	_held = {}
	_current = {}
	_fade = 0
	_root.modulate.a = 1.0
	visible = false

## Hands over the plain line showing now and stops showing it; a held View
## line comes back. "" when the line showing has an action or none shows.
func take_plain() -> String:
	if not _showing() or not _current.action_text.is_empty(): return ""
	var line: String = _current.text
	_current = {}
	if _held.is_empty():
		dismiss()
	else:
		var held := _held
		_held = {}
		_show(held)
	return line

## Drops every line with an action (shown or held), as when the player who
## got them is no longer the one signed in. Plain lines stay.
func drop_actions() -> void:
	_held = {}
	if showing() and not _current.action_text.is_empty(): dismiss()

## True while a line shows (or fades out).
func showing() -> bool:
	return visible and not _current.is_empty()

func _showing() -> bool:
	return showing() and _current.left > 0.0

func _show(entry: Dictionary) -> void:
	var appearing := not _showing()
	var was_visible := visible
	_current = entry
	text = entry.text
	visible = true
	if appearing and not _reduced():
		# A line that arrives while the last one fades out fades back in from there.
		if not was_visible: _root.modulate.a = 0.0
		_fade = 1
	else:
		_root.modulate.a = 1.0
		_fade = 0
	var news: bool = entry.icon != null
	_icon_disc.visible = news
	_icon.texture = entry.icon
	label.text = entry.text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if news else HORIZONTAL_ALIGNMENT_CENTER
	_action.visible = not entry.action_text.is_empty()
	_action.text = entry.action_text
	_action.accessibility_name = "%s: %s" % [entry.action_text, entry.text] if _action.visible else ""
	_place()

func _act() -> void:
	if not _showing(): return
	var action: Callable = _current.action
	dismiss()
	if action.is_valid(): action.call()

func _reduced() -> bool:
	return reduced_motion.is_valid() and reduced_motion.call() == true

## Sizes the card for its line and sets it in the safe area.
func _place() -> void:
	if not is_inside_tree() or _current.is_empty(): return
	var safe := SafeArea.rect(get_viewport())
	_header = in_header.is_valid() and in_header.call() == true
	var width := minf(HEADER_WIDTH, safe.size.x * 0.42) if _header else minf(WIDTH, safe.size.x - SIDE_GAP * 2.0)
	var news := _icon_disc.visible
	var left := 12.0 if news else 20.0
	var right := 12.0 if _action.visible else 20.0
	var text_width := width - left - right
	var button := _action.get_combined_minimum_size()
	if news: text_width -= ICON_SIZE + GAP
	if _action.visible: text_width -= button.x + GAP
	text_width = maxf(text_width, 40.0)
	var font := label.get_theme_font("font")
	var text_height := ceilf(font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, text_width, FONT_SIZE).y)
	var height := maxf(HEIGHT, text_height + 24.0)
	card.size = Vector2(width, height)
	card.position = Vector2(safe.position.x + roundf((safe.size.x - width) * 0.5), safe.position.y + (HEADER_TOP if _header else TOP))
	# Placed by hand, not by a container. A wrapping label keeps the height it
	# measured at its last width as its minimum, so it gets the new width and
	# measures again before its height is set.
	_icon_disc.position = Vector2(left, roundf((height - ICON_SIZE) * 0.5))
	label.position = Vector2(left + (ICON_SIZE + GAP if news else 0.0), roundf((height - text_height) * 0.5))
	label.size = Vector2(text_width, label.size.y)
	label.update_minimum_size()
	label.size = Vector2(text_width, text_height)
	_action.size = button
	_action.position = Vector2(width - right - button.x, roundf((height - button.y) * 0.5))
	_draw_bar()

func _draw_bar() -> void:
	var drains: bool = not _current.is_empty() and _current.icon != null and not _reduced()
	_bar.visible = drains
	if not drains: return
	var fraction := clampf(_current.left / maxf(_current.total, 0.001), 0.0, 1.0)
	_bar.position = Vector2(BAR_INSET, card.size.y - BAR_HEIGHT)
	_bar.size = Vector2(roundf((card.size.x - BAR_INSET * 2.0) * fraction), BAR_HEIGHT)

func _process(delta: float) -> void:
	if not visible or _current.is_empty(): return
	if _fade != 0:
		if _reduced():
			_root.modulate.a = 1.0 if _fade > 0 else 0.0
		else:
			_root.modulate.a = clampf(_root.modulate.a + float(_fade) * delta / FADE_SEC, 0.0, 1.0)
		if _fade > 0 and _root.modulate.a >= 1.0: _fade = 0
		elif _fade < 0 and _root.modulate.a <= 0.0:
			dismiss()
			return
	if _fade < 0: return
	_current.left -= delta
	if _header != (in_header.is_valid() and in_header.call() == true): _place()
	_draw_bar()
	if _current.left > 0.0: return
	if not _held.is_empty():
		var held := _held
		_held = {}
		_show(held)
	elif _reduced():
		dismiss()
	else:
		_fade = -1

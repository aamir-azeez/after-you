extends Node
## The display name prompt (layout A): the in-game modal with the player's pip
## beside the field. The pip is the real 3D one (presentation/kit/
## spirit_preview.gd): drag to spin it, hold to squeeze it. A name tag above it
## shows what others will see as the choice changes.
##
## Three choices, all on one card:
## - type a name (1 to 18 characters; the counter and the error line say what
##   the rules want; services/display_names.gd);
## - "Keep me anonymous": others see the anonymous name made from the player id;
## - "Use my Play Games name" / "Use my Game Center name": shown only while the
##   platform is signed in. The name is read from the platform only when this
##   row is picked, then copied once through the same rules.
##
## The platform row follows the platform while the card is open: a sign-in that
## finishes after the card opened adds the row under the anonymous one, and a
## sign-out takes it away (a platform choice falls back to the typed name, which
## may be empty). Neither moves focus or the choice; a change that lands while a
## finger is down on the card waits for the release, so that tap still counts.
##
## The prompt keeps no state of its own beyond the open card. `context`:
##   edit (bool): opened from Friends to change the name (its own title);
##   own (Dictionary): DisplayNames.own() for this player;
##   anonymous (String): this player's anonymous name;
##   platform (Callable () -> String, or String): the platform row's label now,
##     or "" for none; asked when the card opens and on every platform_changed;
##   platform_changed (Signal, optional): the platform's state changed. The card
##     listens only while it is open (the connection goes with it);
##   read_platform (Callable () -> {"ok", "name"}): awaited when that row is picked;
##   save (Callable (choice, name) -> {"closed": bool, "code": String}): awaited on Save;
##   reduced_motion (bool), haptic (Callable, optional): the pip's grab tick;
##   dismissed (Callable, optional): called when the card closes with nothing saved.
const InGameModal = preload("res://presentation/in_game_modal.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DisplayNames = preload("res://services/display_names.gd")
const SpiritPreview = preload("res://presentation/kit/spirit_preview.gd")
const TouchInput = preload("res://presentation/touch_input.gd")
const KeyboardFocus = preload("res://presentation/keyboard_focus.gd")
const NUNITO = preload("res://assets/fonts/nunito.ttf")
## The tag above the pip: the world badge's cream and ink (kit/badges.gd).
const TAG_FILL := Color("e9edd6")
const TAG_INK := Color("102133")
const MUTED := Color("afc6be")
const ERROR := Color("f2b8ae")
const WIDTH := 860.0
const PIP_SIZE := Vector2(180, 236)

var modal: Control
var field: LineEdit
var tag: Label
var preview: Control
var save_button: Button
var anonymous_row: Button
var platform_row: Button
var _counter: Label
var _error: Label
var _platform_note: Label
## The rows' column, and the platform row's label as shown ("" for none).
var _column: VBoxContainer
var _platform_label := ""
## A platform change held back until the pressed button is let go, and whether
## a sign-out came while it waited.
var _platform_waiting := false
var _platform_held: BaseButton = null
var _platform_pending := ""
var _platform_drop_pending := false
var _context: Dictionary = {}
var _choice := "typed"
var _platform_name := ""
var _busy := false
var _saved := false

## Opens the prompt over `parent` and returns the modal (InGameModal).
static func open(parent: Control, context: Dictionary, opener: Control = null) -> Control:
	var prompt: Node = load("res://presentation/display_name_prompt.gd").new()
	prompt.name = "DisplayNamePrompt"
	prompt._context = context
	var heading := PlayerCopy.DISPLAY_NAME_EDIT_TITLE if context.get("edit", false) else PlayerCopy.DISPLAY_NAME_ASK
	var modal: Control = InGameModal.open(parent, "DisplayNameModal", heading, PlayerCopy.DISPLAY_NAME_ASK_NOTE, opener)
	modal.add_child(prompt)
	prompt._build(modal)
	return modal

## The choice as it stands: typed, anonymous or platform.
func choice() -> String:
	return _choice

func _build(card: Control) -> void:
	modal = card
	modal.widen(WIDTH)
	var body := HBoxContainer.new()
	body.name = "DisplayNameBody"
	body.add_theme_constant_override("separation", 22)
	modal.content.add_child(body)
	var art := VBoxContainer.new()
	# The preview frames the pip with room above its leaf; the tag sits into it.
	art.add_theme_constant_override("separation", -26)
	art.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(art)
	art.add_child(_tag())
	preview = SpiritPreview.new(bool(_context.get("reduced_motion", false)), SpiritPreview.PEACH, PIP_SIZE)
	preview.name = "DisplayNamePip"
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var haptic: Variant = _context.get("haptic")
	if haptic is Callable and haptic.is_valid(): preview.turn.grabbed.connect(haptic)
	art.add_child(preview)
	_column = VBoxContainer.new()
	var column := _column
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(column)
	column.add_child(_field())
	var under := HBoxContainer.new()
	column.add_child(under)
	_error = _small("", ERROR, under)
	_error.name = "DisplayNameError"
	_error.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_counter = _small("", MUTED, under)
	_counter.name = "DisplayNameCounter"
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Above the on screen keyboard the field shows under the card's question, with its counter.
	KeyboardFocus.describe(field, modal.title_label.text, _counter)
	anonymous_row = _row(column, "DisplayNameAnonymous", PlayerCopy.DISPLAY_NAME_ANONYMOUS, PlayerCopy.DISPLAY_NAME_ANONYMOUS_NOTE % str(_context.get("anonymous", "")))
	anonymous_row.pressed.connect(_pick.bind("anonymous"))
	var platform_label := _platform_now()
	if not platform_label.is_empty(): _add_platform(platform_label)
	var follow: Variant = _context.get("platform_changed")
	# A method of this node, not a lambda: the connection is dropped when the card is freed.
	if follow is Signal and not (follow as Signal).is_null(): (follow as Signal).connect(_platform_changed)
	save_button = modal.add_actions(PlayerCopy.DISPLAY_NAME_SAVE, _save, PlayerCopy.DISPLAY_NAME_NOT_NOW if not _context.get("edit", false) else PlayerCopy.DISPLAY_NAME_CANCEL)
	var dismissed: Variant = _context.get("dismissed")
	if dismissed is Callable and dismissed.is_valid(): modal.closed.connect(func() -> void: if not _saved: dismissed.call())
	save_button.name = "DisplayNameSave"
	var cancel: Button = modal.find_child("ModalCancel", true, false)
	# Nothing is lost by closing, so the way out is quiet, not the coral warning.
	if cancel != null: ThemeRules.secondary(cancel)
	var own: Dictionary = _context.get("own", {})
	match str(own.get("choice", "")):
		"anonymous": _choice = "anonymous"
		"platform":
			if platform_row != null and not str(own.get("name", "")).is_empty():
				_platform_name = str(own.name)
				_choice = "platform"
			else:
				field.text = str(own.get("name", ""))
		_: field.text = str(own.get("name", ""))
	_show()
	if _choice == "typed" and not _context.get("edit", false): field.grab_focus.call_deferred()

func _tag() -> Control:
	var holder := PanelContainer.new()
	holder.name = "DisplayNameTag"
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := ThemeRules.rounded(TAG_FILL, 20, TAG_INK)
	style.set_border_width_all(2)
	holder.add_theme_stylebox_override("panel", ThemeRules.padded(style, 16.0, 4.0))
	var bubble := VBoxContainer.new()
	bubble.name = "DisplayNameTagBubble"
	bubble.add_theme_constant_override("separation", -2)
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bubble.z_index = 1
	tag = Label.new()
	tag.name = "DisplayNameTagText"
	tag.add_theme_font_override("font", NUNITO)
	tag.add_theme_font_size_override("font_size", 22)
	tag.add_theme_color_override("font_color", TAG_INK)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(tag)
	bubble.add_child(holder)
	var tail := Tail.new()
	tail.custom_minimum_size = Vector2(22, 12)
	tail.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bubble.add_child(tail)
	return bubble

func _field() -> LineEdit:
	field = LineEdit.new()
	field.name = "DisplayNameField"
	field.placeholder_text = PlayerCopy.DISPLAY_NAME_FIELD
	field.max_length = DisplayNames.MAX_LENGTH + 4
	field.custom_minimum_size.y = 54
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.caret_blink = true
	field.accessibility_name = PlayerCopy.DISPLAY_NAME_FIELD
	for state: String in ["normal", "focus", "read_only"]:
		var style := ThemeRules.rounded(Color("123533"), 12, ThemeRules.CREAM if state == "focus" else Color("4f776d"))
		if state == "focus": style.set_border_width_all(2)
		field.add_theme_stylebox_override(state, ThemeRules.padded(style, 16.0, 10.0))
	field.add_theme_color_override("font_color", ThemeRules.CREAM)
	field.add_theme_color_override("caret_color", ThemeRules.CREAM)
	field.add_theme_color_override("font_placeholder_color", Color("7f9a92"))
	field.add_theme_font_size_override("font_size", 22)
	field.text_changed.connect(_typed)
	field.focus_entered.connect(func() -> void:
		if _choice != "typed" and not _busy:
			_choice = "typed"
			_show())
	field.text_submitted.connect(func(_text: String) -> void: _save())
	return field

func _small(text: String, color: Color, parent: Node) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

## One choice row: a radio dot, its title and a quiet note, as one button.
func _row(parent: Node, node_name: String, title: String, note: String) -> Button:
	var row := Button.new()
	row.name = node_name
	row.custom_minimum_size.y = 62
	row.focus_mode = Control.FOCUS_ALL
	row.accessibility_name = title
	parent.add_child(row)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 16
	line.offset_right = -16
	row.add_child(line)
	var dot := Dot.new()
	dot.name = "Dot"
	dot.custom_minimum_size = Vector2(28, 28)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(dot)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(words)
	var head := Label.new()
	head.name = "Title"
	head.text = title
	head.add_theme_font_size_override("font_size", 20)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(head)
	var small := _small(note, MUTED, words)
	small.name = "Note"
	small.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row

# --- The platform row, following the platform ----------------------------------

## The platform row's label as the platform stands now ("" for none).
func _platform_now() -> String:
	var source: Variant = _context.get("platform", "")
	if source is Callable: return str((source as Callable).call()) if (source as Callable).is_valid() else ""
	return str(source)

func _platform_changed() -> void:
	set_platform(_platform_now())

## Shows the platform row with `label`, or takes it away for "", in place under
## the anonymous row. Focus and the choice stay put; only a platform choice
## whose row goes falls back to the typed name. A change that lands while a
## finger is down on the card waits for its release: the rows shift, and the
## release would miss the button it pressed. A sign-out seen while it waits
## still drops the old account's name, even if a sign-in follows before the release.
func set_platform(label: String) -> void:
	if not is_instance_valid(modal): return
	if label == _platform_label and not _platform_waiting: return
	var held := TouchInput.held_button(modal)
	if held != null:
		if label.is_empty(): _platform_drop_pending = true
		_platform_pending = label
		_wait_for_release(held)
		return
	_stop_waiting()
	if _platform_drop_pending or label.is_empty(): _drop_platform()
	_platform_drop_pending = false
	if not label.is_empty():
		if platform_row == null: _add_platform(label)
		else:
			(platform_row.find_child("Title", true, false) as Label).text = label
			platform_row.accessibility_name = label
			_platform_label = label
	_show()
	modal.refresh_focus_order()

## The held button's release, or anything that ends its press without one
## (focus taken by another card, hidden, removed), applies the waiting change.
func _wait_for_release(held: BaseButton) -> void:
	if _platform_held == held: return
	_stop_waiting()
	_platform_held = held
	_platform_waiting = true
	for ended: Signal in [held.button_up, held.focus_exited, held.visibility_changed, held.tree_exiting]:
		ended.connect(_platform_released, CONNECT_DEFERRED)

func _stop_waiting() -> void:
	_platform_waiting = false
	var held := _platform_held
	_platform_held = null
	if not is_instance_valid(held): return
	for ended: Signal in [held.button_up, held.focus_exited, held.visibility_changed, held.tree_exiting]:
		if ended.is_connected(_platform_released): ended.disconnect(_platform_released)

func _platform_released() -> void:
	if _platform_waiting: set_platform(_platform_pending)

func _add_platform(label: String) -> void:
	platform_row = _row(_column, "DisplayNamePlatform", label, PlayerCopy.DISPLAY_NAME_PLATFORM_NOTE)
	_column.move_child(platform_row, anonymous_row.get_index() + 1)
	_platform_note = platform_row.find_child("Note", true, false)
	platform_row.pressed.connect(_pick_platform)
	_platform_label = label

func _drop_platform() -> void:
	if platform_row == null: return
	var row := platform_row
	if row.has_focus(): anonymous_row.grab_focus()
	# Out of the card now, so the focus order never reaches it again.
	_column.remove_child(row)
	row.queue_free()
	platform_row = null
	_platform_note = null
	_platform_label = ""
	# The account may be a different one when it signs in again.
	_platform_name = ""
	if _choice == "platform": _choice = "typed"

func _typed(_text: String) -> void:
	_choice = "typed"
	_error.text = ""
	_show()

func _pick(which: String) -> void:
	if _busy: return
	_choice = which
	_error.text = ""
	field.release_focus()
	_show()

## The platform name is read now, and only now; a failed read keeps the card
## as it was and says so under the row.
func _pick_platform() -> void:
	if _busy: return
	if not _platform_name.is_empty():
		_pick("platform")
		return
	var reader: Variant = _context.get("read_platform")
	if not reader is Callable or not reader.is_valid(): return
	_busy = true
	var row := platform_row
	_platform_note.text = PlayerCopy.DISPLAY_NAME_PLATFORM_READING
	var answer: Variant = await reader.call()
	if not is_inside_tree(): return
	_busy = false
	# Signed out while it read: the row is gone and the answer is dropped.
	if platform_row != row: return
	var name := DisplayNames.clean(str(answer.get("name", ""))) if answer is Dictionary and answer.get("ok", false) else ""
	if name.is_empty():
		_platform_note.text = PlayerCopy.DISPLAY_NAME_PLATFORM_FAILED
		return
	if not DisplayNames.problem(name).is_empty():
		# A gamer name the rules don't take goes into the field to edit.
		_platform_note.text = PlayerCopy.DISPLAY_NAME_PLATFORM_NOTE
		field.text = name.left(DisplayNames.MAX_LENGTH)
		_choice = "typed"
		_error.text = str(PlayerCopy.DISPLAY_NAME_ERRORS.get(DisplayNames.problem(field.text), ""))
		_show()
		return
	_platform_name = name
	_pick("platform")

## The tag, the rows, the counter and the field's look for the choice now.
func _show() -> void:
	var typed := DisplayNames.clean(field.text)
	_counter.text = PlayerCopy.DISPLAY_NAME_COUNTER % [typed.length(), DisplayNames.MAX_LENGTH]
	_counter.add_theme_color_override("font_color", ERROR if typed.length() > DisplayNames.MAX_LENGTH else MUTED)
	field.modulate.a = 1.0 if _choice == "typed" else 0.55
	_counter.modulate.a = field.modulate.a
	var anonymous := str(_context.get("anonymous", ""))
	match _choice:
		"anonymous": tag.text = anonymous
		"platform": tag.text = _platform_name
		_: tag.text = DisplayNames.short(typed) if not typed.is_empty() else anonymous
	tag.modulate.a = 0.6 if _choice == "typed" and typed.is_empty() else 1.0
	_mark(anonymous_row, _choice == "anonymous")
	if platform_row != null:
		_mark(platform_row, _choice == "platform")
		if not _platform_name.is_empty() and not _busy: _platform_note.text = _platform_name

func _mark(row: Button, on: bool) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var style := ThemeRules.rounded(ThemeRules.CHOICE_HIGHLIGHT if on or state in ["hover", "pressed", "hover_pressed"] else ThemeRules.CHOICE_PANEL, 14, ThemeRules.CREAM if on or state == "focus" else ThemeRules.CHOICE_BORDER)
		if on or state == "focus": style.set_border_width_all(2)
		row.add_theme_stylebox_override(state, style)
	(row.find_child("Dot", true, false) as Dot).on = on
	row.set_pressed_no_signal(on)

func _save() -> void:
	if _busy or not is_instance_valid(modal): return
	var name := ""
	# Nothing typed and nothing picked: the tag already shows the anonymous
	# name, so Save keeps that.
	if _choice == "typed" and DisplayNames.clean(field.text).is_empty(): _choice = "anonymous"
	match _choice:
		"typed":
			name = DisplayNames.clean(field.text)
			var wrong := DisplayNames.problem(name)
			if not wrong.is_empty():
				_error.text = str(PlayerCopy.DISPLAY_NAME_ERRORS.get(wrong, ""))
				field.grab_focus()
				return
		"platform": name = _platform_name
	var save: Variant = _context.get("save")
	if not save is Callable or not save.is_valid():
		modal.close()
		return
	_busy = true
	save_button.disabled = true
	save_button.text = PlayerCopy.DISPLAY_NAME_SAVING
	var answer: Variant = await save.call(_choice, name)
	# The card was closed while it waited (the prompt is the card's child).
	if not is_inside_tree(): return
	_busy = false
	save_button.disabled = false
	save_button.text = PlayerCopy.DISPLAY_NAME_SAVE
	if answer is Dictionary and not answer.get("closed", true):
		_error.text = str(PlayerCopy.DISPLAY_NAME_ERRORS.get(str(answer.get("code", "")), PlayerCopy.DISPLAY_NAME_ERRORS.characters))
		_show()
		return
	_saved = true
	modal.close()

## The tag's tail, pointing down at the pip.
class Tail extends Control:
	func _draw() -> void:
		var w := size.x
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w * 0.5, size.y)]), TAG_INK)
		draw_colored_polygon(PackedVector2Array([Vector2(3, 0), Vector2(w - 3, 0), Vector2(w * 0.5, size.y - 3.5)]), TAG_FILL)

## The radio dot of a choice row.
class Dot extends Control:
	var on := false:
		set(value):
			on = value
			queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		draw_arc(c, 12.0, 0.0, TAU, 40, ThemeRules.CREAM if on else ThemeRules.CHOICE_BORDER, 2.5, true)
		if on: draw_circle(c, 6.5, ThemeRules.CREAM, true, -1.0, true)

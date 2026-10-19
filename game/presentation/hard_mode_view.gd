extends RefCounted
## Hard mode's look (services/hard_mode.gd): the small hard mark beside a
## chapter's solo and together marks, the Hard chip that picks hard mode, and
## the band at the top of a hard run's end card.
##
## The end card's hook: a hard run's end card (failed or finished, solo or
## together) holds an empty VBoxContainer named "EndingExtras" between its
## band and its buttons. When `ending_extras_provider` is set, every such card
## calls it once with (extras, context), where context is
## {"kind": "failed" or "complete", "chapter_key", "together", "room_id",
## "run" (the kept run, services/hard_mode.gd run_record)}. The provider adds
## whatever it shows (end reactions) to `extras`; it must not keep the card.
const HardMode = preload("res://services/hard_mode.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const EndingBadge = preload("res://presentation/ending_badge.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const LOCK_ICON = preload("res://assets/ui/social/lock.svg")
## The solo and together marks' lit colours (home_stage.gd).
const SOLO_LIT := Color("f4c38d")
const TOGETHER_LIT := Color("91d6c6")
const DIM := Color(0.71, 0.84, 0.78, 0.38)
const BAND := Color("2b6765")
const LINE := Color("a8e0da")

## (extras: VBoxContainer, context: Dictionary) -> void; see the header.
static var ending_extras_provider: Callable

## A small peak: filled in the mode's colour once that hard play is done, an
## outline while it is open, and an outline with a lock while locked.
class Mark extends Control:
	var mode := HardMode.SOLO
	var look := HardMode.LOCKED
	var _lock: TextureRect

	func setup(for_mode: String, state: String, side: float) -> void:
		mode = for_mode
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_look(state)

	func set_look(state: String) -> void:
		look = state
		tooltip_text = (PlayerCopy.HARD_MARK_SOLO if mode == HardMode.SOLO else PlayerCopy.HARD_MARK_TOGETHER)
		if look == HardMode.LOCKED and not is_instance_valid(_lock):
			_lock = TextureRect.new()
			_lock.name = "HardLock"
			_lock.texture = LOCK_ICON
			_lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_lock.self_modulate = DIM
			add_child(_lock)
		if is_instance_valid(_lock): _lock.visible = look == HardMode.LOCKED
		_place_lock()
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED: _place_lock()

	func _place_lock() -> void:
		if not is_instance_valid(_lock): return
		var side := size.x * 0.5
		_lock.size = Vector2(side, side)
		_lock.position = Vector2(size.x - side * 0.9, size.y - side * 0.9)

	func lit() -> Color:
		return SOLO_LIT if mode == HardMode.SOLO else TOGETHER_LIT

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var peak := PackedVector2Array([Vector2(w * 0.04, h * 0.88), Vector2(w * 0.40, h * 0.18), Vector2(w * 0.56, h * 0.44), Vector2(w * 0.68, h * 0.30), Vector2(w * 0.96, h * 0.88)])
		var line := maxf(1.5, w * 0.08)
		if look == HardMode.DONE:
			draw_colored_polygon(peak, lit())
			# The snow line, so a filled peak still reads as a peak.
			draw_polyline(PackedVector2Array([Vector2(w * 0.30, h * 0.38), Vector2(w * 0.40, h * 0.46), Vector2(w * 0.48, h * 0.34)]), ControlTheme.CREAM, maxf(1.2, w * 0.06), true)
		else:
			var closed := peak.duplicate()
			closed.append(peak[0])
			draw_polyline(closed, lit() if look == HardMode.OPEN else DIM, line, true)

## One mark, named "HardMarkSolo" or "HardMarkTogether".
static func mark(mode: String, state: String, side: float = 22.0) -> Mark:
	var item := Mark.new()
	item.name = "HardMarkSolo" if mode == HardMode.SOLO else "HardMarkTogether"
	item.setup(mode, state, side)
	return item

## The chapter's marks for `modes`, side by side, named "HardMarks".
static func marks_row(states: Dictionary, side: float = 22.0, modes: Array = HardMode.MODES) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "HardMarks"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	for mode: String in modes: row.add_child(mark(mode, str(states.get(mode, HardMode.LOCKED)), side))
	return row

## Updates a marks_row in place.
static func update_row(row: Control, states: Dictionary) -> void:
	if not is_instance_valid(row): return
	for item: Node in row.get_children():
		if item is Mark: (item as Mark).set_look(str(states.get((item as Mark).mode, HardMode.LOCKED)))

## The Hard chip: a toggle drawn as the selected tab while on.
static func chip(on: bool) -> Button:
	var button := Button.new()
	button.name = "HardChip"
	button.text = PlayerCopy.HARD_CHIP
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 20)
	button.custom_minimum_size = Vector2(108, 48)
	set_chip(button, on)
	return button

static func set_chip(button: Button, on: bool) -> void:
	button.set_pressed_no_signal(on)
	if on: ControlTheme.selected_tab(button)
	else: ControlTheme.outlined_tab(button)
	button.tooltip_text = PlayerCopy.HARD_CHIP_ON if on else PlayerCopy.HARD_CHIP_OFF

## The band at the top of a hard run's end card: the badge (`badge` is a
## turn_endings.gd ending, or {} for the plain mark), its title and line,
## then the EndingExtras slot, which it returns. `card` keeps the rest.
static func add_band(card: VBoxContainer, title: String, line: String, badge: Dictionary, title_font: Font, mode: String) -> VBoxContainer:
	var band := PanelContainer.new()
	band.name = "HardBand"
	var style := ControlTheme.rounded(BAND, 16)
	style.content_margin_left = 14
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	band.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	band.add_child(row)
	if not badge.is_empty():
		var face := EndingBadge.new()
		face.setup(badge, 104.0)
		row.add_child(face)
	else:
		var holder := CenterContainer.new()
		holder.custom_minimum_size = Vector2(104, 104)
		holder.add_child(mark(mode, HardMode.DONE, 72.0))
		row.add_child(holder)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(words)
	var heading := _text(title, 32, ControlTheme.CREAM)
	heading.name = "HardTitle"
	if title_font != null: heading.add_theme_font_override("font", title_font)
	words.add_child(heading)
	if not line.is_empty():
		var detail := _text(line, 20, LINE)
		detail.name = "HardLine"
		words.add_child(detail)
	card.add_child(band)
	card.move_child(band, 0)
	var extras := VBoxContainer.new()
	extras.name = "EndingExtras"
	extras.add_theme_constant_override("separation", 8)
	card.add_child(extras)
	card.move_child(extras, 1)
	return extras

## Runs the end card hook (see the header) for a card's EndingExtras.
static func fill_extras(extras: VBoxContainer, context: Dictionary) -> void:
	if ending_extras_provider.is_valid() and is_instance_valid(extras): ending_extras_provider.call(extras, context.duplicate(true))

## The line under a failed run's title: who slipped, how, and on which stage.
static func failure_line(run: Dictionary) -> String:
	var stage := int(run.get("stage_index", 0)) + 1
	var by_friend := str(run.get("by", "")) == "friend"
	var friend := str(run.get("friend", ""))
	if friend.is_empty(): friend = PlayerCopy.HARD_FRIEND_FALLBACK
	match str(run.get("reason", "")):
		"drowned": return PlayerCopy.HARD_FRIEND_WENT_UNDER % [friend, stage] if by_friend else PlayerCopy.HARD_YOU_WENT_UNDER % stage
		"retry": return PlayerCopy.HARD_FRIEND_STARTED_OVER % [friend, stage] if by_friend else PlayerCopy.HARD_YOU_STARTED_OVER % stage
	return PlayerCopy.HARD_FRIEND_SLIPPED % [friend, stage] if by_friend else PlayerCopy.HARD_YOU_SLIPPED % stage

## The face on a failed run's band: the spirit that slipped, knocked out,
## half under water when the tide took it.
static func failure_badge(run: Dictionary) -> Dictionary:
	var friend := str(run.get("by", "")) == "friend"
	return {"badge": &"knocked_out", "color": "mint" if friend else "peach", "water": str(run.get("reason", "")) == "drowned"}

static func _text(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

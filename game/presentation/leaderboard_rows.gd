extends RefCounted
## One row of a leaderboard (presentation/leaderboard_screen.gd): the rank, the
## pair's two pips, their names or "A pair", a Gold leaf tag on a first place
## that earned it, the time, Watch on a run whose replay the server keeps, and,
## on another pair's run, Report.
##
## Pips are kit/pip_avatar.gd in still mode: one shared offscreen render per
## look, never a live view per row. Boards carry no outfits: a board is one
## public, cached answer for every reader, and looks are seen only by room
## members. So a pair shows the worlds' two pips by slot, gold and teal, and
## "Your best" shows this player's own pip (in their own look) beside a teal
## one. The hook for looks on boards: a row's `looks` (two outfits, in slot
## order) dresses its pips, once leaderboard_client keeps that field.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const Outfit = preload("res://services/outfit.gd")
const LEAF_ICON = preload("res://assets/ui/whats_new/leaf.svg")
## The worlds' pips by slot (presentation/island_world.gd GOLD and TEAL).
const FIRST_PIP := Color("f4c38d")
const SECOND_PIP := Color("91d6c6")
const PIP_SIZE := Vector2(40, 54)
const ROW_FILL := Color("173e3a")
const MINE_FILL := Color("1f4c45")
const GOLD_INK := Color("f4d77b")

## A ranked run. `report` and `watch` (Callables, may be empty) show Report and Watch; `mine` tints the row.
static func ranked(row: Dictionary, mine: bool, report: Callable, compact: bool, watch: Callable = Callable()) -> Control:
	var names: Variant = row.get("names")
	var title := PlayerCopy.LEADERBOARD_NAMES % [names[0], names[1]] if names is Array else PlayerCopy.LEADERBOARD_A_PAIR
	var box := _row(MINE_FILL if mine else ROW_FILL)
	var line: HBoxContainer = box.get_child(0)
	_rank(line, str(int(row.rank)), compact)
	_pips(line, false, row.get("looks", []))
	_name(line, title, compact)
	if row.get("gold_leaf", false): line.add_child(_gold_leaf(compact))
	_time(line, Runs.time_text(int(row.ticks)), compact)
	if watch.is_valid(): line.add_child(_text_button("LeaderboardWatch", PlayerCopy.LEADERBOARD_WATCH, watch))
	if report.is_valid(): line.add_child(_text_button("LeaderboardReport", PlayerCopy.LEADERBOARD_REPORT, report))
	box.name = "LeaderboardRow%d" % int(row.rank)
	return box

## The pinned "Your best" row: the rank when ranked, "Checking" while waiting, or neither.
static func own(ticks: int, rank: int, checking: bool, compact: bool) -> Control:
	var box := _row(MINE_FILL)
	box.name = "LeaderboardOwnRow"
	var line: HBoxContainer = box.get_child(0)
	_rank(line, str(rank) if rank > 0 else "", compact)
	_pips(line, true)
	_name(line, PlayerCopy.LEADERBOARD_YOUR_BEST, compact)
	if checking: line.add_child(_tag(PlayerCopy.LEADERBOARD_CHECKING, UiTokens.MINT, null, compact))
	_time(line, Runs.time_text(ticks), compact)
	return box

static func _row(fill: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := ThemeRules.rounded(fill, 14)
	style.content_margin_left = 14
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.alignment = BoxContainer.ALIGNMENT_BEGIN
	panel.add_child(line)
	return panel

static func _rank(line: HBoxContainer, text: String, compact: bool) -> void:
	var label := _label(text, 22 if compact else 26, UiTokens.CREAM)
	label.custom_minimum_size = Vector2(34 if compact else 44, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_child(label)

## `looks`: the pair's outfits in slot order, when a board carries them (none does yet).
static func _pips(line: HBoxContainer, own_first: bool, looks: Variant = []) -> void:
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", -8)
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pips := [PipAvatar.new(true, FIRST_PIP, PIP_SIZE, true, own_first), PipAvatar.new(true, SECOND_PIP, PIP_SIZE, true)]
	for index in range(pips.size()):
		if looks is Array and index < looks.size() and not (own_first and index == 0): pips[index].outfit = Outfit.from(looks[index])
		pair.add_child(pips[index])
	line.add_child(pair)

static func _name(line: HBoxContainer, text: String, compact: bool) -> void:
	var label := _label(text, 18 if compact else 20, UiTokens.CREAM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	line.add_child(label)

static func _time(line: HBoxContainer, text: String, compact: bool) -> void:
	var label := _label(text, 20 if compact else 22, UiTokens.CREAM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.custom_minimum_size = Vector2(76 if compact else 92, 0)
	line.add_child(label)

static func _gold_leaf(compact: bool) -> Control:
	return _tag("" if compact else PlayerCopy.LEADERBOARD_GOLD_LEAF, GOLD_INK, LEAF_ICON, compact, PlayerCopy.LEADERBOARD_GOLD_LEAF)

## A small outlined pill: an icon, a word, or both.
static func _tag(text: String, ink: Color, icon: Texture2D, compact: bool, description: String = "") -> Control:
	var panel := PanelContainer.new()
	panel.name = "LeaderboardTag"
	var style := ThemeRules.rounded(Color.TRANSPARENT, 12, ink)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.tooltip_text = description if not description.is_empty() else text
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	panel.add_child(inner)
	if icon != null:
		var mark := TextureRect.new()
		mark.texture = icon
		mark.modulate = ink
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.custom_minimum_size = Vector2(18, 18)
		inner.add_child(mark)
	if not text.is_empty(): inner.add_child(_label(text, 15 if compact else 16, ink))
	return panel

static func _text_button(node_name: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(0, 44)
	button.add_theme_font_size_override("font_size", 15)
	ThemeRules.plain_tab(button)
	button.pressed.connect(action)
	return button

static func _label(text: String, size: int, ink: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", ink)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label

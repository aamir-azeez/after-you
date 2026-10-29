extends RefCounted
## The rows of a leaderboard (presentation/leaderboard_screen.gd), in fixed
## columns so header() lines up with every row: the place (with a gold leaf
## mark on a first place that earned the Gold leaf), the pair's two pips, their
## names or "A pair", the time, Watch on a run whose replay the server keeps,
## and Report on another pair's run.
##
## Pips are kit/pip_avatar.gd in still mode: one shared offscreen render per
## look (kit/pip_snapshots.gd), never a live view per row. A pair shows the
## worlds' two pips by slot, gold and teal, each wearing what they wore when
## the run finished: a row's `looks` (two outfits in slot order, kept by
## services/leaderboard_client.gd), the default look when a board has none.
## "Your best" shows this player's own pip in their own look beside their
## partner's in the look this phone last heard for them.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const SettingsKit = preload("res://presentation/settings_kit.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const Outfit = preload("res://services/outfit.gd")
const LEAF_ICON = preload("res://assets/ui/whats_new/leaf.svg")
const WATCH_ICON = preload("res://assets/ui/play-circle.svg")
const REPORT_ICON = preload("res://assets/ui/room/flag.svg")
## The worlds' pips by slot (presentation/island_world.gd GOLD and TEAL).
const FIRST_PIP := Color("f4c38d")
const SECOND_PIP := Color("91d6c6")
const PIP_SIZE := Vector2(34, 46)
const ROW_FILL := Color("173e3a")
const ROW_EDGE := Color("21504a")
const MINE_FILL := Color("2b5d54")
const MINE_EDGE := Color("5e9686")
const HEADER_FILL := Color("1a4540")
const GOLD_INK := Color("f4d77b")
## Buttons in a row are this tall, and a row a little taller.
const TARGET := 44.0
## Column widths (wide, compact): place, pips, time, Watch.
const PLACE := Vector2(92, 64)
const PIPS := Vector2(104, 96)
const TIME := Vector2(130, 96)
const WATCH := Vector2(184, 128)
## "Your best" keeps its place narrower, beside its label.
const OWN_PLACE := 56.0

## The column headings: Place, Pair, Time.
static func header(compact: bool) -> Control:
	var box := _row(HEADER_FILL, ROW_EDGE, 32.0)
	box.name = "LeaderboardHeader"
	var line: HBoxContainer = box.get_child(0)
	_cell(line, _label(PlayerCopy.LEADERBOARD_PLACE, 17 if compact else 19, UiTokens.SOFT), _width(PLACE, compact), HORIZONTAL_ALIGNMENT_CENTER)
	# "Pair" heads the names, past the pips' column.
	line.add_child(_gap(_width(PIPS, compact)))
	var pair := _label(PlayerCopy.LEADERBOARD_PAIR, 17 if compact else 19, UiTokens.SOFT)
	pair.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(pair)
	_cell(line, _label(PlayerCopy.LEADERBOARD_TIME, 17 if compact else 19, UiTokens.SOFT), _width(TIME, compact), HORIZONTAL_ALIGNMENT_CENTER)
	line.add_child(_gap(_width(WATCH, compact) + TARGET + 8.0))
	return box

## A ranked run. `report` and `watch` (Callables, may be empty) show Report and Watch; `mine` lights the row.
static func ranked(row: Dictionary, mine: bool, report: Callable, compact: bool, watch: Callable = Callable()) -> Control:
	var box := _row(MINE_FILL if mine else ROW_FILL, MINE_EDGE if mine else ROW_EDGE, TARGET + 2.0)
	box.name = "LeaderboardRow%d" % int(row.rank)
	var line: HBoxContainer = box.get_child(0)
	_place(line, int(row.rank), bool(row.get("gold_leaf", false)), compact)
	_pips(line, false, compact, row.get("looks", []))
	_name(line, pair_title(row), compact)
	_time(line, int(row.ticks), compact)
	line.add_child(_watch(watch, compact))
	line.add_child(_report(report))
	return box

## The pinned "Your best": the place when ranked (0: none), the pair, the time and Watch. `partner_look` dresses the partner's pip.
static func own(ticks: int, rank: int, title: String, compact: bool, watch: Callable = Callable(), partner_look: Dictionary = {}) -> Control:
	var box := _row(ROW_FILL, UiTokens.SOFT, 50.0)
	box.name = "LeaderboardOwnRow"
	var line: HBoxContainer = box.get_child(0)
	line.add_child(_label(PlayerCopy.LEADERBOARD_YOUR_BEST, 22 if compact else 26, UiTokens.CREAM, true))
	var rule := ColorRect.new()
	rule.color = UiTokens.RULE.lightened(0.15)
	rule.custom_minimum_size = Vector2(2, 34)
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(rule)
	_place(line, rank, false, compact, OWN_PLACE)
	_pips(line, true, compact, [{}, partner_look])
	_name(line, title, compact)
	_time(line, ticks, compact)
	line.add_child(_watch(watch, compact))
	line.add_child(_gap(TARGET))
	return box

## "Ada and Bo", or "A pair" for a pair that keeps its names hidden.
static func pair_title(row: Dictionary) -> String:
	var names: Variant = row.get("names")
	return PlayerCopy.LEADERBOARD_NAMES % [names[0], names[1]] if names is Array and names.size() == 2 else PlayerCopy.LEADERBOARD_A_PAIR

static func _row(fill: Color, edge: Color, height: float) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := ThemeRules.rounded(fill, 12, edge)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.custom_minimum_size.y = height
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	panel.add_child(line)
	return panel

static func _width(widths: Vector2, compact: bool) -> float:
	return widths.y if compact else widths.x

static func _cell(line: HBoxContainer, label: Label, width: float, align: HorizontalAlignment) -> void:
	label.custom_minimum_size.x = width
	label.horizontal_alignment = align
	line.add_child(label)

## The place, with the gold leaf mark beside a first place that earned it ("" when 0).
static func _place(line: HBoxContainer, rank: int, gold_leaf: bool, compact: bool, width: float = 0.0) -> void:
	var cell := HBoxContainer.new()
	cell.custom_minimum_size.x = width if width > 0.0 else _width(PLACE, compact)
	cell.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.add_theme_constant_override("separation", 6)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if gold_leaf:
		var mark := TextureRect.new()
		mark.name = "LeaderboardGoldLeaf"
		mark.texture = LEAF_ICON
		mark.modulate = GOLD_INK
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.custom_minimum_size = Vector2(26, 26)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.tooltip_text = PlayerCopy.LEADERBOARD_GOLD_LEAF
		mark.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.add_child(mark)
	cell.add_child(_label(str(rank) if rank > 0 else "", 22 if compact else 24, UiTokens.CREAM, true))
	line.add_child(cell)

## `looks`: the pair's outfits in slot order ([] for none). With `own_first` the first pip is this player's own, in their own look.
static func _pips(line: HBoxContainer, own_first: bool, compact: bool, looks: Variant = []) -> void:
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 4)
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	pair.custom_minimum_size.x = _width(PIPS, compact)
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pips := [PipAvatar.new(true, FIRST_PIP, PIP_SIZE, true, own_first), PipAvatar.new(true, SECOND_PIP, PIP_SIZE, true)]
	for index in range(pips.size()):
		if looks is Array and index < looks.size() and not (own_first and index == 0): pips[index].outfit = Outfit.from(looks[index])
		pips[index].size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pair.add_child(pips[index])
	line.add_child(pair)

static func _name(line: HBoxContainer, text: String, compact: bool) -> void:
	var label := _label(text, 19 if compact else 21, UiTokens.CREAM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	line.add_child(label)

static func _time(line: HBoxContainer, ticks: int, compact: bool) -> void:
	_cell(line, _label(Runs.time_text(ticks), 22 if compact else 25, UiTokens.CREAM, true), _width(TIME, compact), HORIZONTAL_ALIGNMENT_CENTER)

## Watch, or a space as wide, so the columns stay put.
static func _watch(action: Callable, compact: bool) -> Control:
	if not action.is_valid(): return _gap(_width(WATCH, compact))
	var button := Button.new()
	button.name = "LeaderboardWatch"
	button.text = PlayerCopy.LEADERBOARD_WATCH
	button.icon = WATCH_ICON
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 26)
	button.add_theme_constant_override("h_separation", 12)
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(_width(WATCH, compact), TARGET)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 18)
	ThemeRules.outlined_tab(button)
	button.add_theme_color_override("font_color", UiTokens.CREAM)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		button.add_theme_color_override("icon_" + state + "_color", UiTokens.CREAM)
	button.pressed.connect(action)
	return button

## Report as a flag, or a space as wide.
static func _report(action: Callable) -> Control:
	if not action.is_valid(): return _gap(TARGET)
	var button := Button.new()
	button.name = "LeaderboardReport"
	button.icon = REPORT_ICON
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.tooltip_text = PlayerCopy.LEADERBOARD_REPORT
	button.accessibility_name = PlayerCopy.LEADERBOARD_REPORT
	button.add_theme_constant_override("icon_max_width", 20)
	button.custom_minimum_size = Vector2(TARGET, TARGET)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ThemeRules.plain_tab(button)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		button.add_theme_color_override("icon_" + state + "_color", UiTokens.SOFT)
	button.pressed.connect(action)
	return button

static func _gap(width: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.x = width
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap

static func _label(text: String, size: int, ink: Color, heading: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", ink)
	if heading: label.add_theme_font_override("font", SettingsKit.font(600, true))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label

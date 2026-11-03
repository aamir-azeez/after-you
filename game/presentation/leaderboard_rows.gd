extends RefCounted
## The rows of a leaderboard, in fixed columns so header() lines up with every
## row. Each ranked row has the shared core: the place (with a gold leaf mark on
## a first place that earned the Gold leaf, or on this phone a waiting run that
## would earn it), the pair's two pips, their names or "A pair", and the time.
## The caller adds the trailing cells and header() keeps their width:
## - the Fastest pair page (presentation/leaderboard_screen.gd): watch_cell, on
##   a run whose replay the server keeps, and report_cell, on another pair's run;
## - the race picker (presentation/duels/duel_race_picker.gd): race_cell.
## A run of this player's that waits for its check (services/board_status.gd
## shown_rows, `pending`) stands at the place it would get with a small clock
## beside the number, only on this phone. shown() is the one path from a board
## to the rows this phone shows, for both screens.
##
## Pips are kit/pip_avatar.gd in still mode: one shared offscreen render per
## look (kit/pip_snapshots.gd), never a live view per row. A pair shows the
## worlds' two pips by slot, gold and teal, each wearing what they wore when
## the run finished: a row's `looks` (two outfits in slot order, kept by
## services/leaderboard_client.gd), the default look when a board has none.
## "Your best" on a ranked run draws the pair exactly as its row does; on a
## run the board does not list, this player's own pip in their own look beside
## their partner's in the look this phone last heard for them.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const SettingsKit = preload("res://presentation/settings_kit.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const BoardStatus = preload("res://services/board_status.gd")
const TurnLooks = preload("res://services/turn_looks.gd")
const Outfit = preload("res://services/outfit.gd")
const LEAF_ICON = preload("res://assets/ui/whats_new/leaf.svg")
const WATCH_ICON = preload("res://assets/ui/play-circle.svg")
const REPORT_ICON = preload("res://assets/ui/room/flag.svg")
## Race wears the flag, as on the race picker boards.
const RACE_ICON = REPORT_ICON
const CLOCK_ICON = preload("res://assets/ui/social/clock.svg")
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
## Column widths (wide, compact): place, pips, time, Watch (and Race, as wide).
const PLACE := Vector2(92, 64)
const PIPS := Vector2(104, 96)
const TIME := Vector2(130, 96)
const WATCH := Vector2(184, 128)
## "Your best" keeps its place narrower, beside its label.
const OWN_PLACE := 56.0
## The space between cells in a row.
const GAP := 8.0

## This player's runs on the board (`mine`, and `mine_by_id` by entry_id) and
## the rows this phone shows for `view`, board `board` (services/board_status.gd shown_rows):
## a run of theirs waiting for its check stands at the place it would get, as
## their own pip beside their partner's last heard look, named as the board
## would name the pair. `client`: services/leaderboard_client.gd (its kept
## boards and the name choice; no request). `gone`: entry_id -> true for runs
## this screen saw fail their check.
static func shown(client: RefCounted, player_id: String, board: String, view: Dictionary, gone: Dictionary = {}) -> Dictionary:
	var mine: Array = Runs.on_board(player_id, board)
	var mine_by_id: Dictionary = {}
	for run: Dictionary in mine: mine_by_id[run.entry_id] = run
	var known := BoardStatus.pair_names(Runs.runs_of(player_id), client.kept_views(), client.show_name()) if client != null else {}
	var rows: Array = BoardStatus.shown_rows(view, mine, Time.get_unix_time_from_system(), gone, known)
	for row: Dictionary in rows:
		if row.pending: row.looks = [{}, partner_look(mine_by_id[row.entry_id])]
	return {"rows": rows, "mine": mine, "mine_by_id": mine_by_id}

## The look services/turn_looks.gd last heard for a run's partner ({} when unknown).
static func partner_look(run: Dictionary) -> Dictionary:
	var partner := str(run.get("partner", ""))
	return TurnLooks.shared().member(partner) if not partner.is_empty() else {}

## How wide the Fastest pair page's trailing cells are: Watch, then Report.
static func board_trailing(compact: bool) -> float:
	return _width(WATCH, compact) + GAP + TARGET

## How wide the race picker's trailing cell is: Race, as wide as Watch.
static func race_trailing(compact: bool) -> float:
	return _width(WATCH, compact)

## The column headings: Place, Pair, Time, then a space `trailing` wide over the caller's cells.
static func header(compact: bool, trailing: float) -> Control:
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
	line.add_child(_gap(trailing))
	return box

## A ranked run, with `trailing` (the caller's cells) after its time; `mine` lights the row.
## A `pending` row has the clock, and its first pip is this player's own.
static func ranked(row: Dictionary, mine: bool, compact: bool, trailing: Array[Control]) -> Control:
	var box := _row(MINE_FILL if mine else ROW_FILL, MINE_EDGE if mine else ROW_EDGE, TARGET + 2.0)
	box.name = "LeaderboardRow%d" % int(row.rank)
	var line: HBoxContainer = box.get_child(0)
	var pending := bool(row.get("pending", false))
	_place(line, int(row.rank), bool(row.get("gold_leaf", false)), compact, 0.0, pending)
	_pips(line, pending, compact, row.get("looks", []))
	_name(line, pair_title(row), compact)
	_time(line, int(row.ticks), compact)
	for cell: Control in trailing: line.add_child(cell)
	return box

## The pinned "Your best": the place when ranked (0: none), the pair, the time and Watch.
## `run_looks`: the ranked row's two looks, which draw the pair as that row does;
## without them the first pip is this player's own and `partner_look` dresses the other.
## `pending`: the run waits for its check, so its place has the clock.
static func own(ticks: int, rank: int, title: String, compact: bool, watch: Callable = Callable(), partner_look: Dictionary = {}, run_looks: Array = [], pending: bool = false) -> Control:
	var box := _row(ROW_FILL, UiTokens.SOFT, 50.0)
	box.name = "LeaderboardOwnRow"
	var line: HBoxContainer = box.get_child(0)
	line.add_child(_label(PlayerCopy.LEADERBOARD_YOUR_BEST, 22 if compact else 26, UiTokens.CREAM, true))
	var rule := ColorRect.new()
	rule.color = UiTokens.RULE.lightened(0.15)
	rule.custom_minimum_size = Vector2(2, 34)
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(rule)
	_place(line, rank, false, compact, OWN_PLACE, pending)
	if run_looks.size() == 2: _pips(line, false, compact, run_looks)
	else: _pips(line, true, compact, [{}, partner_look])
	_name(line, title, compact)
	_time(line, ticks, compact)
	line.add_child(watch_cell(watch, compact))
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
	line.add_theme_constant_override("separation", int(GAP))
	panel.add_child(line)
	return panel

static func _width(widths: Vector2, compact: bool) -> float:
	return widths.y if compact else widths.x

static func _cell(line: HBoxContainer, label: Label, width: float, align: HorizontalAlignment) -> void:
	label.custom_minimum_size.x = width
	label.horizontal_alignment = align
	line.add_child(label)

## The place, with the gold leaf mark beside a first place that earned it, or
## would once its check passes ("" when 0), and the clock after it while the
## run waits for its check. Leaf, place and clock together are drawn smaller in
## the compact column so they fit it.
static func _place(line: HBoxContainer, rank: int, gold_leaf: bool, compact: bool, width: float = 0.0, pending: bool = false) -> void:
	var cell := HBoxContainer.new()
	var tight := compact and gold_leaf and pending
	cell.custom_minimum_size.x = width if width > 0.0 else _width(PLACE, compact)
	cell.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.add_theme_constant_override("separation", 3 if tight else 6)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if gold_leaf:
		var mark := TextureRect.new()
		mark.name = "LeaderboardGoldLeaf"
		mark.texture = LEAF_ICON
		mark.modulate = GOLD_INK
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.custom_minimum_size = Vector2(20, 20) if tight else Vector2(26, 26)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.tooltip_text = PlayerCopy.LEADERBOARD_GOLD_LEAF
		mark.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.add_child(mark)
	cell.add_child(_label(str(rank) if rank > 0 else "", 22 if compact else 24, UiTokens.CREAM, true))
	if pending: cell.add_child(_clock(18.0 if tight else 22.0))
	line.add_child(cell)

## The small clock of a run waiting for its check, named for screen readers.
static func _clock(side: float = 22.0) -> TextureRect:
	var mark := TextureRect.new()
	mark.name = "LeaderboardWaiting"
	mark.texture = CLOCK_ICON
	mark.modulate = UiTokens.SOFT
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(side, side)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.tooltip_text = PlayerCopy.LEADERBOARD_WAITING_CHECK
	mark.accessibility_name = PlayerCopy.LEADERBOARD_WAITING_CHECK
	mark.mouse_filter = Control.MOUSE_FILTER_PASS
	return mark

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
static func watch_cell(action: Callable, compact: bool) -> Control:
	if not action.is_valid(): return _gap(_width(WATCH, compact))
	var button := _cell_button("LeaderboardWatch", PlayerCopy.LEADERBOARD_WATCH, WATCH_ICON, 26, compact)
	button.pressed.connect(action)
	return button

## Race (the race picker): a button as wide as Watch whose tap calls
## `action(button)`, and with no `action` the same button greyed and untappable. `waiting`: the run waits for its check,
## so the greyed button says so beside the clock instead.
static func race_cell(action: Callable, compact: bool, waiting: bool = false) -> Control:
	var button := _cell_button("LeaderboardRace", PlayerCopy.RACE_PICK_RACE, RACE_ICON, 20, compact)
	if waiting:
		button.name = "LeaderboardRaceWaiting"
		button.text = PlayerCopy.RACE_PICK_WAITING
		button.icon = CLOCK_ICON
		button.add_theme_font_size_override("font_size", 15)
		button.add_theme_constant_override("icon_max_width", 18)
		button.add_theme_constant_override("h_separation", 6)
		button.tooltip_text = PlayerCopy.LEADERBOARD_WAITING_CHECK
	if action.is_valid(): button.pressed.connect(action.bind(button))
	else: button.disabled = true
	return button

## A trailing cell's outlined button: cream words and icon, as wide as Watch.
static func _cell_button(node_name: String, text: String, icon: Texture2D, icon_width: int, compact: bool) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.icon = icon
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", icon_width)
	button.add_theme_constant_override("h_separation", 12)
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(_width(WATCH, compact), TARGET)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 18)
	ThemeRules.outlined_tab(button)
	button.add_theme_color_override("font_color", UiTokens.CREAM)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		button.add_theme_color_override("icon_" + state + "_color", UiTokens.CREAM)
	return button

## Report as a flag, or a space as wide.
static func report_cell(action: Callable) -> Control:
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

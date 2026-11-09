extends VBoxContainer
## The top 10 picker (race-picker board 2A): a sheet over Race a recorded run
## (presentation/in_game_modal.gd through the page's sheet(), so Back closes it
## before the page) with the chapter's Fastest pair rows, each with one Race
## button. The rows are the board's own (presentation/leaderboard_rows.gd:
## place, Gold leaf, both pips in their looks, names, time), with race_cell in
## place of Watch and Report, so the two screens can't drift apart.
##
## Every top 10 run can be raced, this pair's own included (owner, 2026-11-02).
## Greyed, untappable rows:
## - a run of this player's still waiting for its check stands at the place it
##   would get, with the clock and "Being checked": the server can't race it yet;
## - every row while the pair has its limit of ghost races going, with the
##   lobby's limit line above them (services/duels_client.gd ghost_races_full).
## An empty board says so with the board's own line and offers Our run.
##
## While duel energy is on (the page's energy_cost), each Race and Our run
## wears the cost chip (kit/energy_chip.gd) in place of the flag on a narrow
## screen, so the column keeps its width.
##
## It draws what it is given and asks for nothing: the flow
## (presentation/duels/duels_flow.gd) reads the board and races, so a tap waits
## on the page's BusyTapGate like every other Race.
const Rows = preload("res://presentation/leaderboard_rows.gd")
const Kit = preload("res://presentation/duels/duel_kit.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Icons = preload("res://presentation/kit/icons.gd")
const DashedBox = preload("res://presentation/kit/dashed_box.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")
const EnergyChip = preload("res://presentation/kit/energy_chip.gd")
const DuelModel = preload("res://services/duel_model.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
## The sheet is at most this wide, and keeps this much of the screen's height
## for its heading, column heads and edges; the rows scroll in the rest.
const SHEET_WIDTH := 1000.0
const SHEET_CHROME := 250.0
const LIST_LEAST := 140.0
const ROW_GAP := 4
## Heights the list is sized from, set before the sheet lays out (a wrapped
## line has no width yet): a row, a one or two line note, the limit bar.
const ROW_HEIGHT := Rows.TARGET + 2.0
const NOTE_HEIGHT := 56.0
const BANNER_HEIGHT := 48.0

## source: "board" (entry_id the run's) or "developer" (Our run, entry_id null).
signal race_requested(source: String, entry_id: Variant, control: Control)

var chapter_key := ""
var compact := false
## Whether starting and joining cost energy (services/duel_energy.gd): the cost chips show only then.
var energy_cost := false
## The sheet holding this picker (presentation/in_game_modal.gd).
var modal: Control
var _banner: Control
var _list: VBoxContainer
var _scroll: ScrollContainer

## Opens the picker for `chapter` over `page` (duel_page_base.gd), or null
## while another card is up. `partner`: the partner's name for the line under
## the title, "" for none.
static func open(page: CanvasLayer, chapter: String, partner: String, opener: Control = null) -> VBoxContainer:
	var title := RoomChapterTitle.title(chapter, str(Registry.descriptor(chapter).get("title", chapter)))
	var sheet: Control = page.sheet("RacePickerSheet", title, "", opener)
	if sheet == null: return null
	var picker: VBoxContainer = load("res://presentation/duels/duel_race_picker.gd").new()
	picker.name = "RacePicker"
	picker.chapter_key = chapter
	picker.compact = page.compact
	picker.energy_cost = bool(page.get("energy_cost"))
	picker._build(sheet, PlayerCopy.RACE_PICK_WITH % partner if not partner.is_empty() else PlayerCopy.DUELS_GHOST_SUBTITLE)
	return picker

func _build(sheet: Control, line: String) -> void:
	modal = sheet
	modal.widen(SHEET_WIDTH)
	# The heading row as drawn: the trophy, the chapter, then the line beside it.
	modal.heading_line(Icons.LEADERBOARD, line).name = "RacePickerLine"
	add_theme_constant_override("separation", 6)
	modal.content.add_child(self)
	_banner = VBoxContainer.new()
	add_child(_banner)
	add_child(Rows.header(compact, Rows.race_trailing(compact)))
	_scroll = ScrollContainer.new()
	_scroll.name = "RacePickerScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ThemeRules.touch_scroll(_scroll)
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.name = "RacePickerRows"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", ROW_GAP)
	_scroll.add_child(_list)
	show_loading()

func show_loading() -> void:
	_note_only(PlayerCopy.LEADERBOARD_LOADING)

func show_failed() -> void:
	_note_only(PlayerCopy.LEADERBOARD_FAILED)

## The board's rows as this phone shows them (Rows.shown): `mine_by_id` lights
## this player's; `full` greys every row under the limit line (`limit` races);
## `developer_ticks`: Our run's time for the empty board, -1 for none.
func show_board(rows: Array, mine_by_id: Dictionary, full: bool, limit: int, developer_ticks: int) -> void:
	_clear()
	if full: _banner.add_child(_limit_line(limit))
	if rows.is_empty():
		_list.add_child(Kit.wrapped(PlayerCopy.LEADERBOARD_EMPTY, 18))
		if developer_ticks > 0: _list.add_child(_our_run(developer_ticks, full))
		_fit(NOTE_HEIGHT + (ROW_GAP + ROW_HEIGHT if developer_ticks > 0 else 0.0), full)
	for row: Dictionary in rows:
		var pending := bool(row.get("pending", false))
		var race := Callable() if full or pending else func(control: Control): race_requested.emit("board", row.entry_id, control)
		var cell := Rows.race_cell(race, compact, pending)
		if not pending: _cost(cell)
		if race.is_valid(): OfflineHold.hold(cell)
		_list.add_child(Rows.ranked(row, mine_by_id.has(row.entry_id), compact, [cell]))
	if not rows.is_empty(): _fit(rows.size() * ROW_HEIGHT + (rows.size() - 1) * ROW_GAP, full)
	modal.refresh_focus_order()

func _note_only(line: String) -> void:
	_clear()
	_list.add_child(Kit.wrapped(line, 18))
	_fit(NOTE_HEIGHT, false)

func _clear() -> void:
	Kit.clear(_banner)
	Kit.clear(_list)

## The lobby's limit line, with "races" (PlayerCopy.DUELS_RACE_LIMIT), on a quiet bar.
func _limit_line(limit: int) -> Control:
	var bar := Kit.panel("RacePickerLimit", Rows.HEADER_FILL, Rows.ROW_EDGE, 10, 8.0)
	bar.add_child(Kit.wrapped(PlayerCopy.DUELS_RACE_LIMIT % limit, 17, UiTokens.CREAM))
	return bar

## Our run on an empty board, so the sheet never ends in nothing to do.
func _our_run(ticks: int, full: bool) -> Button:
	var button := Kit.button("%s  %s" % [PlayerCopy.DUELS_GHOST_DEVELOPERS, DuelModel.time_text(ticks)], Callable(), false, Rows.TARGET)
	button.name = "RacePickerOurRun"
	Kit.icon_on(button, Rows.RACE_ICON, true, 20)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.custom_minimum_size.x = 230
	if full:
		button.disabled = true
		DashedBox.grey(button)
	else:
		button.pressed.connect(func(): race_requested.emit("developer", null, button))
		OfflineHold.hold(button)
	_cost(button)
	return button

## The cost chip on a Race, while energy is on; on a narrow screen it takes the flag's place.
func _cost(button: Control) -> void:
	if not energy_cost or not button is Button: return
	if compact: (button as Button).icon = null
	EnergyChip.on_button(button, 18)

## The list is `tall`, and scrolls once that no longer fits under the sheet's
## heading (and the limit bar while `banner`).
func _fit(tall: float, banner: bool) -> void:
	var room := maxf(LIST_LEAST, get_viewport_rect().size.y - SHEET_CHROME - (BANNER_HEIGHT if banner else 0.0))
	_scroll.custom_minimum_size.y = minf(tall, room)

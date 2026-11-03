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
## It draws what it is given and asks for nothing: the flow
## (presentation/duels/duels_flow.gd) reads the board and races, so a tap waits
## on the page's BusyTapGate like every other Race.
const Rows = preload("res://presentation/leaderboard_rows.gd")
const Kit = preload("res://presentation/duels/duel_kit.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Icons = preload("res://presentation/kit/icons.gd")
const DuelModel = preload("res://services/duel_model.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
## The sheet is at most this wide, and keeps this much of the screen's height
## for its heading, column heads and edges; the rows scroll in the rest.
const SHEET_WIDTH := 1000.0
const SHEET_CHROME := 250.0
const LIST_LEAST := 140.0
const ROW_GAP := 4

## source: "board" (entry_id the run's) or "developer" (Our run, entry_id null).
signal race_requested(source: String, entry_id: Variant, control: Control)

var chapter_key := ""
var compact := false
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
	picker._build(sheet, PlayerCopy.RACE_PICK_WITH % partner if not partner.is_empty() else PlayerCopy.DUELS_GHOST_SUBTITLE)
	return picker

func _build(sheet: Control, line: String) -> void:
	modal = sheet
	modal.widen(SHEET_WIDTH)
	# The heading row as drawn: the trophy, the chapter, then the line beside it.
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 14)
	var titles: Node = modal.title_label.get_parent()
	titles.add_child(heading)
	titles.move_child(heading, 0)
	var icon := TextureRect.new()
	icon.name = "RacePickerIcon"
	icon.texture = Icons.LEADERBOARD
	icon.modulate = UiTokens.CREAM
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(28, 28)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(icon)
	modal.title_label.reparent(heading)
	modal.title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var with := Kit.text(line, 17, UiTokens.SOFT)
	with.name = "RacePickerLine"
	with.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	with.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	with.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_child(with)
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
	for row: Dictionary in rows:
		var pending := bool(row.get("pending", false))
		var race := Callable() if full or pending else func(control: Control): race_requested.emit("board", row.entry_id, control)
		_list.add_child(Rows.ranked(row, mine_by_id.has(row.entry_id), compact, [Rows.race_cell(race, compact, pending)]))
	_fit(rows.size())
	modal.refresh_focus_order()

func _note_only(line: String) -> void:
	_clear()
	_list.add_child(Kit.wrapped(line, 18))
	_fit(1)

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
	button.custom_minimum_size.x = 200
	if full: button.disabled = true
	else: button.pressed.connect(func(): race_requested.emit("developer", null, button))
	return button

## The rows scroll once ten of them no longer fit under the sheet's heading.
func _fit(count: int) -> void:
	var tall := maxf(1.0, float(count)) * (Rows.TARGET + 2.0) + maxf(0.0, float(count - 1)) * ROW_GAP
	var room := maxf(LIST_LEAST, get_viewport_rect().size.y - SHEET_CHROME - (_banner.get_combined_minimum_size().y if _banner.get_child_count() > 0 else 0.0))
	_scroll.custom_minimum_size.y = minf(tall, room)

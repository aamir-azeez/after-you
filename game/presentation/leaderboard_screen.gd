extends CanvasLayer
## Leaderboards, opened over Friends (presentation/friends_flow.gd): "Fastest
## pair", all time. The chapters down the left, each with its real capture
## (services/chapter_thumbnail_catalog.gd, loaded off the main thread by
## presentation/chapter_thumbnail_shelf.gd), and the chosen chapter's board on
## the right.
##
## One board per chapter version, shared by normal and duel runs: the top 10
## runs played together (presentation/leaderboard_rows.gd), this player's
## confirmed best pinned under them, and, under the chapters, the time of their
## newest run while its replay is being checked. Which runs are this player's
## comes from services/leaderboard_runs.gd; the board itself never names anyone
## who did not choose to show their name. It reads boards through
## services/leaderboard_client.gd only and keeps no live view of its own, so it
## costs nothing while it sits open.
##
## Refresh keeps the rows and the list where they are until the new board
## arrives; a run that was being checked and now ranks fades in. When a read
## confirms one of this player's runs in the top 10, its celebration
## (presentation/leaderboard_celebration.gd) shows over the page, once.
##
## Watch on a top 10 row fetches that run's replay and asks Friends' flow
## (watch_requested) to play it in the shared replay viewer; the page hides
## until the flow calls replay_closed(), so Back from the replay returns here.
const ThemeRules = preload("res://presentation/control_theme.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const SettingsKit = preload("res://presentation/settings_kit.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const ChapterPicker = preload("res://presentation/chapter_picker.gd")
const ThumbnailShelf = preload("res://presentation/chapter_thumbnail_shelf.gd")
const Rows = preload("res://presentation/leaderboard_rows.gd")
const Celebration = preload("res://presentation/leaderboard_celebration.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const BoardStatus = preload("res://services/board_status.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Thumbnails = preload("res://services/chapter_thumbnail_catalog.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
const BACK_ICON = preload("res://assets/ui/social/arrow-left.svg")
const REFRESH_ICON = preload("res://assets/ui/social/arrows-clockwise.svg")
const INFO_ICON = preload("res://assets/ui/social/info.svg")
## Whether the page says normal and duel runs share a board. Off until duels
## ship; the duels work turns it on behind its own flag.
static var duels_share_boards := false
const BACKGROUND := Color("123936")
const PANEL_FILL := Color("163f3b")
const PANEL_EDGE := Color("2d5a53")
const CHAPTER_FILL := Color("1b4641")
## A row that just passed its check fades in over this many seconds.
const ROW_FADE := 0.4

## A short line for the app's pop-up (presentation/toast.gd).
signal notice(text: String, news: bool)
signal closed
## A run's replay is ready: the viewer's parts (services/leaderboard_replay.gd) and its chapter key.
signal watch_requested(parts: Array, chapter_key: String)

## services/leaderboard_client.gd for the signed-in player.
var client: RefCounted
## The signed-in player, whose runs services/leaderboard_runs.gd keeps.
var player_id := ""
## func(chapter_key) -> bool: whether the chapter is listed (the free-only build hides paid ones).
var chapter_filter: Callable
## The chapter to open on ("" for the first listed).
var chapter_key := ""
## The player's Reduce motion setting, for celebrations.
var reduced_motion := false

var _root: Control
var _margin: MarginContainer
var _title: Label
var _body: BoxContainer
var _chapters: BoxContainer
var _chapter_cards: Dictionary = {}
var _side: VBoxContainer
var _checking_card: PanelContainer
var _board_scroll: ScrollContainer
var _board: VBoxContainer
var _heading: Label
var _own: VBoxContainer
var _keys: Array[String] = []
var _selected := ""
var _view: Dictionary = {}
var _state := "loading"
var _compact := false
var _stacked := false
var _alive := true
var _generation := 0
var _modal: Control
var _celebration: Control
## The checking ids each board last showed, so a run that passed since fades in.
var _was_checking: Dictionary = {}
## "" or "loading" while a Watch fetches, "watching" while its replay plays.
var _replay_state := ""

func _ready() -> void:
	layer = 60
	_keys = _listed_keys()
	_selected = chapter_key if chapter_key in _keys else _keys[0] if not _keys.is_empty() else ""
	_root = Control.new()
	_root.name = "LeaderboardScreen"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = Theme.new()
	_root.theme.default_font = SettingsKit.font(600)
	_root.theme.default_font_size = 20
	_root.theme.set_color("font_color", "Label", UiTokens.CREAM)
	ThemeRules.install_buttons(_root.theme)
	add_child(_root)
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(background)
	SafeArea.bleed(background)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	_margin.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	layout.add_child(header)
	var back := Button.new()
	back.name = "LeaderboardBack"
	back.text = PlayerCopy.LEADERBOARD_BACK
	back.custom_minimum_size = Vector2(132, 52)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ThemeRules.danger(back, BACK_ICON)
	back.pressed.connect(close)
	header.add_child(back)
	_title = _text(PlayerCopy.LEADERBOARD_FASTEST_PAIR, 54, UiTokens.CREAM, true)
	_title.name = "LeaderboardFastestPair"
	header.add_child(_title)
	var all_time := _text(PlayerCopy.LEADERBOARD_ALL_TIME, 22, UiTokens.SOFT)
	all_time.name = "LeaderboardAllTime"
	all_time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_time.size_flags_vertical = Control.SIZE_SHRINK_END
	all_time.custom_minimum_size.y = 52
	header.add_child(all_time)
	header.add_child(_icon_button(REFRESH_ICON, "Refresh", func(): _load(true)))
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_body)
	SafeArea.watch(self, _layout)
	_layout()
	if client != null: client.sync()
	_load(false)

func close() -> void:
	if not _alive: return
	_alive = false
	_generation += 1
	closed.emit()
	queue_free()

## Back (forwarded by Friends, which owns this page) leaves a celebration or
## the report question first, then the page. While a replay plays, its viewer takes Back.
func go_back() -> void:
	if _replay_state == "watching": return
	if _showing(_celebration): _celebration.go_back()
	elif _showing(_modal): _modal.go_back()
	else: close()

func _listed_keys() -> Array[String]:
	var result: Array[String] = []
	for key: String in Registry.offered_keys():
		if Runs.board_key(key).is_empty(): continue
		if chapter_filter.is_valid() and not chapter_filter.call(key): continue
		result.append(key)
	return result

func _layout() -> void:
	if not is_instance_valid(_margin): return
	var rect := get_viewport().get_visible_rect()
	var safe := SafeArea.rect(get_viewport())
	var compact := safe.size.x < 1100
	var stacked := safe.size.x < 900
	var side := SafeArea.centred(safe.size.x, 1240, 18)
	var tall := SafeArea.centred(safe.size.y, SafeArea.PAGE_HEIGHT, 12 if compact else 14)
	SafeArea.pad(_margin, rect, safe, side, tall, side, tall)
	_title.add_theme_font_size_override("font_size", 40 if compact else 50)
	if compact != _compact or stacked != _stacked or _chapters == null:
		_compact = compact
		_stacked = stacked
		_build_body()

## The chapter rail (a strip above the board on a narrow screen) and the board panel.
func _build_body() -> void:
	_clear(_body)
	var holder: BoxContainer = VBoxContainer.new() if _stacked else HBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override("separation", 12 if _stacked else 18)
	_body.add_child(holder)
	var rail := _panel("LeaderboardRail")
	rail.custom_minimum_size.x = 0.0 if _stacked else 280.0 if _compact else 330.0
	holder.add_child(rail)
	var rail_column := VBoxContainer.new()
	rail_column.add_theme_constant_override("separation", 10)
	rail.add_child(rail_column)
	if not _stacked: rail_column.add_child(_text(PlayerCopy.LEADERBOARD_CHAPTERS, 28, UiTokens.CREAM, true))
	var chapter_scroll := ScrollContainer.new()
	chapter_scroll.name = "LeaderboardChapters"
	ThemeRules.touch_scroll(chapter_scroll)
	if _stacked:
		chapter_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		chapter_scroll.custom_minimum_size.y = 76
		_chapters = HBoxContainer.new()
	else:
		chapter_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		chapter_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_chapters = VBoxContainer.new()
		_chapters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chapters.add_theme_constant_override("separation", 8)
	chapter_scroll.add_child(_chapters)
	rail_column.add_child(chapter_scroll)
	var board_panel := _panel("LeaderboardBoardPanel")
	board_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_child(board_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	board_panel.add_child(column)
	_heading = _text("", 28 if _compact else 30, UiTokens.CREAM, true)
	_heading.name = "LeaderboardChapterTitle"
	_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_heading)
	column.add_child(Rows.header(_compact))
	_board_scroll = ScrollContainer.new()
	_board_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_board_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ThemeRules.touch_scroll(_board_scroll)
	column.add_child(_board_scroll)
	_board = VBoxContainer.new()
	_board.name = "LeaderboardBoard"
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.add_theme_constant_override("separation", 0)
	_board_scroll.add_child(_board)
	_own = VBoxContainer.new()
	_own.name = "LeaderboardOwn"
	column.add_child(_own)
	# The checking card and the shared board note sit under the chapters, or
	# under the board when the chapters are a strip.
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 10)
	(column if _stacked else rail_column).add_child(_side)
	_checking_card = _checking()
	_side.add_child(_checking_card)
	if duels_share_boards: _side.add_child(_shared_note())
	_render_chapters()
	_render_board()

func _render_chapters() -> void:
	_clear(_chapters)
	_chapter_cards = {}
	for key: String in _keys:
		var card := _chapter_card(key)
		_chapters.add_child(card)
		_chapter_cards[key] = card
	_mark_chapters()

## A chapter: its capture and its name; the chosen one is mint.
func _chapter_card(key: String) -> Button:
	var button := Button.new()
	button.name = "Chapter_" + Runs.board_key(key).replace("@", "_")
	var title := RoomChapterTitle.title(key, str(Registry.descriptor(key).get("title", key)))
	button.accessibility_name = title
	button.tooltip_text = title
	button.custom_minimum_size = Vector2(230 if _stacked else 0, 64 if _stacked else 78 if _compact else 86)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func(): _choose(key))
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 6
	line.offset_right = -8
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(line)
	var picture := ChapterPicker.picture_frame(Vector2(92, 52) if _stacked else Vector2(112, 63) if _compact else Vector2(128, 72), 10)
	ThumbnailShelf.fill(picture.get_child(0) as TextureRect, Thumbnails.path(key))
	line.add_child(picture)
	var label := _text(title, 18 if _compact else 21, UiTokens.CREAM, true)
	label.name = "ChapterName"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 2
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(label)
	return button

## Restyles the cards for the chosen chapter, in place: no picture loads again.
func _mark_chapters() -> void:
	for key: String in _chapter_cards:
		var button: Button = _chapter_cards[key]
		var chosen := key == _selected
		var fill := UiTokens.MINT if chosen else CHAPTER_FILL
		for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
			var lit := fill.lightened(0.06) if state in ["hover", "hover_pressed"] and not chosen else fill
			button.add_theme_stylebox_override(state, ThemeRules.rounded(lit, 14, Color.TRANSPARENT if chosen else PANEL_EDGE))
		button.add_theme_stylebox_override("focus", ThemeRules.rounded(Color.TRANSPARENT, 14, UiTokens.CREAM))
		(button.find_child("ChapterName", true, false) as Label).add_theme_color_override("font_color", UiTokens.INK if chosen else UiTokens.CREAM)

func _choose(key: String) -> void:
	if key == _selected: return
	_selected = key
	_mark_chapters()
	_load(false)

## Shows the board of `board` (a celebration's View board).
func show_board(board: String) -> void:
	for key: String in _keys:
		if Runs.board_key(key) == board:
			_choose(key)
			return

func _load(fresh: bool) -> void:
	if client == null or _selected.is_empty():
		_state = "failed"
		_render_board()
		return
	_generation += 1
	var generation := _generation
	var board := Runs.board_key(_selected)
	# A refresh keeps the rows on screen until the new board arrives.
	var keep := _state == "ready" and str(_view.get("board", "")) == board
	if not keep:
		_state = "loading"
		_render_board()
	var answer: Dictionary = await client.board(board, fresh)
	if generation != _generation or not _alive: return
	if answer.get("ok", false):
		_view = answer.view
		_state = "ready"
	elif not keep:
		_view = {}
		_state = "failed"
	else:
		notice.emit(PlayerCopy.LEADERBOARD_FAILED, false)
	_render_board()
	_celebrate()

func _render_board() -> void:
	if not is_instance_valid(_board): return
	var offset := _board_scroll.scroll_vertical
	_clear(_board)
	_clear(_own)
	_heading.text = RoomChapterTitle.title(_selected, PlayerCopy.LEADERBOARDS) if not _selected.is_empty() else PlayerCopy.LEADERBOARDS
	_checking_card.visible = false
	if _state != "ready":
		_board.add_child(_note(PlayerCopy.LEADERBOARD_LOADING if _state == "loading" else PlayerCopy.LEADERBOARD_FAILED))
		return
	var board := Runs.board_key(_selected)
	var mine: Array = Runs.on_board(player_id, board)
	var mine_ids: Array = mine.map(func(run: Dictionary) -> String: return run.entry_id)
	var top: Array = _view.get("top", [])
	var checking: Array = _view.get("checking", [])
	var passed: Array = _was_checking.get(board, [])
	_was_checking[board] = checking.duplicate()
	if top.is_empty():
		_board.add_child(_note(PlayerCopy.LEADERBOARD_EMPTY))
		_board.add_child(_note(PlayerCopy.LEADERBOARD_RULES))
	for row: Dictionary in top:
		var is_mine: bool = row.entry_id in mine_ids
		var report := Callable() if is_mine else func(): _ask_report(board, row.entry_id)
		var line := Rows.ranked(row, is_mine, report, _compact, _watcher(row))
		_board.add_child(line)
		if row.entry_id in passed: _fade_in(line)
	_render_own(mine, top, checking)
	_keep_offset.call_deferred(offset)

func _keep_offset(offset: int) -> void:
	if is_instance_valid(_board_scroll): _board_scroll.scroll_vertical = offset

## A row that just passed its check fades into place.
func _fade_in(line: Control) -> void:
	line.modulate.a = 0.0
	line.create_tween().tween_property(line, "modulate:a", 1.0, ROW_FADE)

## Watch for a row whose replay the server keeps.
func _watcher(row: Dictionary) -> Callable:
	return (func(): _watch(row)) if row.get("replay_hash") != null else Callable()

## "Your best": this player's ranked run, else their fastest run that is not
## waiting for its check; and the checking card for their newest run while
## its replay is checked.
func _render_own(mine: Array, top: Array, checking: Array) -> void:
	var ranked_row: Dictionary = {}
	for row: Dictionary in top:
		if mine.any(func(run: Dictionary) -> bool: return run.entry_id == row.entry_id): ranked_row = row; break
	var settled: Array = mine.filter(func(run: Dictionary) -> bool: return not run.entry_id in checking)
	var eligible: Array = settled.filter(func(run: Dictionary) -> bool: return not run.assisted)
	if not ranked_row.is_empty():
		_own.add_child(Rows.own(int(ranked_row.ticks), int(ranked_row.rank), Rows.pair_title(ranked_row), _compact, _watcher(ranked_row)))
	elif not eligible.is_empty():
		_own.add_child(Rows.own(int(eligible[0].ticks), 0, "", _compact))
		# Why it has no place (services/board_status.gd): a run this new may not show in the board's copy yet.
		if BoardStatus.of_run(eligible[0], true, _view, Time.get_unix_time_from_system(), mine).state == BoardStatus.NOT_LISTED: _own.add_child(_note(PlayerCopy.LEADERBOARD_OWN_NOT_LISTED))
	elif not settled.is_empty():
		_own.add_child(Rows.own(int(settled[0].ticks), 0, "", _compact))
		_own.add_child(_note(PlayerCopy.LEADERBOARD_OWN_ASSISTED))
	elif mine.is_empty():
		_own.add_child(_note(PlayerCopy.LEADERBOARD_NO_RUN))
	var newest: Dictionary = {}
	for run: Dictionary in mine:
		if newest.is_empty() or str(run.finished_at) > str(newest.finished_at): newest = run
	if not newest.is_empty() and newest.entry_id in checking:
		(_checking_card.find_child("LeaderboardCheckingTime", true, false) as Label).text = Runs.time_text(int(newest.ticks))
		_checking_card.visible = true

## Shows a celebration waiting for this player, once the page is free for it.
func _celebrate() -> void:
	if not _alive or not visible or not _replay_state.is_empty() or _showing(_modal) or _showing(_celebration): return
	_celebration = Celebration.show_next(_root, player_id, reduced_motion)
	if _celebration != null: _celebration.view_board.connect(show_board)

## Fetches the run's replay once per tap; a second tap while it loads waits for the first.
func _watch(row: Dictionary) -> void:
	if not _replay_state.is_empty() or not _alive or client == null: return
	_replay_state = "loading"
	notice.emit(PlayerCopy.LEADERBOARD_WATCH_LOADING, false)
	var chapter := _selected
	var answer: Dictionary = await client.replay(Runs.board_key(chapter), chapter, row)
	if not _alive: return
	if not answer.get("ok", false):
		_replay_state = ""
		notice.emit(PlayerCopy.LEADERBOARD_REPLAY_FAILED, false)
		_celebrate()
		return
	_replay_state = "watching"
	visible = false
	watch_requested.emit(answer.parts, chapter)

## The replay closed (or could not open): the board shows again as it was.
func replay_closed() -> void:
	_replay_state = ""
	if not _alive: return
	visible = true
	_celebrate()

func _ask_report(board: String, entry_id: String) -> void:
	if _showing(_modal) or _showing(_celebration) or not _alive: return
	_modal = InGameModal.open(_root, "LeaderboardReportModal", PlayerCopy.LEADERBOARD_REPORT_TITLE)
	_modal.label(PlayerCopy.LEADERBOARD_REPORT_BODY)
	var confirm := func() -> void:
		_modal.close(false)
		_report(board, entry_id)
	var send: Button = _modal.add_actions(PlayerCopy.LEADERBOARD_REPORT_SEND, confirm, PlayerCopy.LEADERBOARD_REPORT_CANCEL)
	send.grab_focus()
	_modal.closed.connect(_celebrate.call_deferred)

func _report(board: String, entry_id: String) -> void:
	var answer: Dictionary = await client.report(board, entry_id)
	if not _alive: return
	notice.emit(PlayerCopy.LEADERBOARD_REPORTED if answer.get("ok", false) else PlayerCopy.LEADERBOARD_REPORT_FAILED, false)

## Takes the children out at once, so the new ones keep their names.
static func _clear(holder: Node) -> void:
	for child: Node in holder.get_children():
		holder.remove_child(child)
		child.queue_free()

static func _showing(node: Variant) -> bool:
	return is_instance_valid(node) and not node.is_queued_for_deletion()

## "Your run is being checked", the run's time, and that the best stays meanwhile.
func _checking() -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "LeaderboardChecking"
	var style := ThemeRules.rounded(Color("1d4c46"), 14, UiTokens.SECONDARY_BORDER)
	ThemeRules.padded(style, 14.0, 10.0)
	card.add_theme_stylebox_override("panel", style)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	card.add_child(line)
	var clock := Control.new()
	clock.custom_minimum_size = Vector2(30, 30)
	clock.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock.draw.connect(func() -> void:
		var middle := clock.size * 0.5
		clock.draw_arc(middle, 12.0, 0.0, TAU, 32, UiTokens.CREAM, 2.5, true)
		clock.draw_line(middle, middle + Vector2(0, -7), UiTokens.CREAM, 2.5, true)
		clock.draw_line(middle, middle + Vector2(5, 3), UiTokens.CREAM, 2.5, true))
	line.add_child(clock)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	line.add_child(words)
	var title := _text(PlayerCopy.LEADERBOARD_RUN_CHECKING, 18 if _compact else 20, UiTokens.CREAM, true)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(title)
	var time := _text("", 30, UiTokens.CREAM, true)
	time.name = "LeaderboardCheckingTime"
	words.add_child(time)
	var note := _text(PlayerCopy.LEADERBOARD_RUN_CHECKING_NOTE, 15, UiTokens.SOFT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(note)
	card.visible = false
	return card

func _shared_note() -> Control:
	var line := HBoxContainer.new()
	line.name = "LeaderboardSharedNote"
	line.add_theme_constant_override("separation", 8)
	var icon := TextureRect.new()
	icon.texture = INFO_ICON
	icon.modulate = UiTokens.SOFT
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(20, 20)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icon)
	var note := _text(PlayerCopy.LEADERBOARD_SHARED_BOARD, 15 if _compact else 16, UiTokens.SOFT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(note)
	return line

func _panel(node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	var style := ThemeRules.rounded(PANEL_FILL, 18, PANEL_EDGE)
	ThemeRules.padded(style, 12.0 if _compact else 14.0, 10.0)
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _text(value: String, font_size: int, ink: Color, heading: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ink)
	label.add_theme_font_override("font", SettingsKit.font(600, heading))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _note(text: String) -> Label:
	var label := _text(text, 16 if _compact else 18, UiTokens.MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _icon_button(icon: Texture2D, description: String, action: Callable) -> Button:
	var button := Button.new()
	button.icon = icon
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	button.tooltip_text = description
	button.accessibility_name = description
	button.custom_minimum_size = Vector2(52, 52)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_constant_override("icon_max_width", 28)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		button.add_theme_color_override("icon_" + state + "_color", UiTokens.CREAM)
	button.add_theme_stylebox_override("normal", ThemeRules.rounded(Color.TRANSPARENT, 14))
	button.add_theme_stylebox_override("hover", ThemeRules.rounded(Color("2b5550"), 14))
	button.add_theme_stylebox_override("pressed", ThemeRules.rounded(Color("2b5550"), 14))
	button.pressed.connect(action)
	return button

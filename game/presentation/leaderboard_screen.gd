extends CanvasLayer
## Leaderboards, opened over Friends (presentation/friends_flow.gd): the
## chapters down the left, the chosen chapter's board on the right.
##
## One board per chapter version, "Fastest pair", all time: the top 10 runs
## played together (presentation/leaderboard_rows.gd), this player's best
## pinned under them, and a note while their newest run is being checked.
## Which runs are this player's comes from services/leaderboard_runs.gd; the
## board itself never names anyone who did not choose to show their name.
## It reads boards through services/leaderboard_client.gd only and keeps no
## live view of its own, so it costs nothing while it sits open.
const ThemeRules = preload("res://presentation/control_theme.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const Rows = preload("res://presentation/leaderboard_rows.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
const BACK_ICON = preload("res://assets/ui/social/arrow-left.svg")
const REFRESH_ICON = preload("res://assets/ui/social/arrows-clockwise.svg")
const BACKGROUND := Color("123936")
const CARD_FILL := Color("123936")
const CARD_EDGE := Color("466e63")

## A short line for the app's pop-up (presentation/toast.gd).
signal notice(text: String, news: bool)
signal closed

## services/leaderboard_client.gd for the signed-in player.
var client: RefCounted
## The signed-in player, whose runs services/leaderboard_runs.gd keeps.
var player_id := ""
## func(chapter_key) -> bool: whether the chapter is listed (the free-only build hides paid ones).
var chapter_filter: Callable

var _root: Control
var _margin: MarginContainer
var _title: Label
var _body: BoxContainer
var _chapters: BoxContainer
var _chapter_scroll: ScrollContainer
var _board: VBoxContainer
var _heading_font: FontVariation
var _keys: Array[String] = []
var _selected := ""
var _view: Dictionary = {}
var _state := "loading"
var _compact := false
var _stacked := false
var _alive := true
var _generation := 0
var _modal: Control

func _ready() -> void:
	layer = 60
	_keys = _listed_keys()
	_selected = _keys[0] if not _keys.is_empty() else ""
	_root = Control.new()
	_root.name = "LeaderboardScreen"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = Theme.new()
	var body_font := FontVariation.new()
	body_font.base_font = preload("res://assets/fonts/nunito.ttf")
	body_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	_root.theme.default_font = body_font
	_root.theme.default_font_size = 20
	_root.theme.set_color("font_color", "Label", UiTokens.CREAM)
	_heading_font = FontVariation.new()
	_heading_font.base_font = preload("res://assets/fonts/fredoka.ttf")
	_heading_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
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
	layout.add_theme_constant_override("separation", 18)
	_margin.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	layout.add_child(header)
	header.add_child(_icon_button(BACK_ICON, "Back", close))
	_title = Label.new()
	_title.text = PlayerCopy.LEADERBOARDS
	_title.add_theme_font_override("font", _heading_font)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	header.add_child(_icon_button(REFRESH_ICON, "Refresh", func(): _load(true)))
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 18)
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

## Back (forwarded by Friends, which owns this page) closes the report question first, then the page.
func go_back() -> void:
	if is_instance_valid(_modal) and not _modal.is_queued_for_deletion(): _modal.go_back()
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
	var side := SafeArea.centred(safe.size.x, 1192, 20)
	var tall := SafeArea.centred(safe.size.y, SafeArea.PAGE_HEIGHT, 16 if compact else 20)
	SafeArea.pad(_margin, rect, safe, side, tall, side, tall)
	_title.add_theme_font_size_override("font_size", 38 if compact else 54)
	if compact != _compact or stacked != _stacked or _chapters == null:
		_compact = compact
		_stacked = stacked
		_build_body()

## The chapter list (a column, or a row above the board on a narrow screen) and the board card.
func _build_body() -> void:
	for child: Node in _body.get_children(): child.queue_free()
	var holder: BoxContainer = VBoxContainer.new() if _stacked else HBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override("separation", 14 if _stacked else 18)
	_body.add_child(holder)
	_chapter_scroll = ScrollContainer.new()
	_chapter_scroll.name = "LeaderboardChapters"
	ThemeRules.touch_scroll(_chapter_scroll)
	if _stacked:
		_chapter_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_chapter_scroll.custom_minimum_size = Vector2(0, 64)
		_chapters = HBoxContainer.new()
	else:
		_chapter_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_chapter_scroll.custom_minimum_size = Vector2(260 if _compact else 320, 0)
		_chapters = VBoxContainer.new()
	_chapters.add_theme_constant_override("separation", 8)
	_chapter_scroll.add_child(_chapters)
	holder.add_child(_chapter_scroll)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := ThemeRules.rounded(CARD_FILL, 16, CARD_EDGE)
	for side: String in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 16 if _compact else 20)
	card.add_theme_stylebox_override("panel", style)
	holder.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ThemeRules.touch_scroll(scroll)
	card.add_child(scroll)
	_board = VBoxContainer.new()
	_board.name = "LeaderboardBoard"
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.add_theme_constant_override("separation", 10)
	scroll.add_child(_board)
	_render_chapters()
	_render_board()

func _render_chapters() -> void:
	for child: Node in _chapters.get_children(): child.queue_free()
	for key: String in _keys:
		var button := Button.new()
		button.name = "Chapter_" + Runs.board_key(key).replace("@", "_")
		button.text = RoomChapterTitle.title(key, str(Registry.descriptor(key).get("title", key)))
		button.custom_minimum_size = Vector2(0, 52)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if key == _selected: ThemeRules.selected_tab(button)
		else: ThemeRules.outlined_tab(button)
		button.pressed.connect(func(): _choose(key))
		_chapters.add_child(button)

func _choose(key: String) -> void:
	if key == _selected: return
	_selected = key
	_render_chapters()
	_load(false)

func _load(fresh: bool) -> void:
	if client == null or _selected.is_empty():
		_state = "failed"
		_render_board()
		return
	_generation += 1
	var generation := _generation
	var board := Runs.board_key(_selected)
	_state = "loading"
	_render_board()
	var answer: Dictionary = await client.board(board, fresh)
	if generation != _generation or not _alive: return
	_view = answer.get("view", {}) if answer.get("ok", false) else {}
	_state = "ready" if answer.get("ok", false) else "failed"
	_render_board()

func _render_board() -> void:
	if not is_instance_valid(_board): return
	for child: Node in _board.get_children(): child.queue_free()
	var heading := Label.new()
	heading.name = "LeaderboardChapterTitle"
	heading.text = RoomChapterTitle.title(_selected, PlayerCopy.LEADERBOARDS) if not _selected.is_empty() else PlayerCopy.LEADERBOARDS
	heading.add_theme_font_override("font", _heading_font)
	heading.add_theme_font_size_override("font_size", 28 if _compact else 34)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_board.add_child(heading)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	_board.add_child(tabs)
	var fastest := _pill(PlayerCopy.LEADERBOARD_FASTEST_PAIR, true)
	fastest.name = "LeaderboardFastestPair"
	tabs.add_child(fastest)
	var all_time := _pill(PlayerCopy.LEADERBOARD_ALL_TIME, false)
	all_time.name = "LeaderboardAllTime"
	tabs.add_child(all_time)
	_board.add_child(_note(PlayerCopy.LEADERBOARD_RULES))
	if _state == "loading":
		_board.add_child(_note(PlayerCopy.LEADERBOARD_LOADING))
		return
	if _state == "failed":
		_board.add_child(_note(PlayerCopy.LEADERBOARD_FAILED))
		return
	var board := Runs.board_key(_selected)
	var mine: Array = Runs.on_board(player_id, board)
	var mine_ids: Array = mine.map(func(run: Dictionary) -> String: return run.entry_id)
	var top: Array = _view.get("top", [])
	if top.is_empty(): _board.add_child(_note(PlayerCopy.LEADERBOARD_EMPTY))
	for row: Dictionary in top:
		var is_mine: bool = row.entry_id in mine_ids
		var report := Callable() if is_mine else func(): _ask_report(board, row.entry_id)
		_board.add_child(Rows.ranked(row, is_mine, report, _compact))
	_render_own(mine, top)

## "Your best": this player's ranked run, else their fastest run that can rank, with "Checking" while it waits.
func _render_own(mine: Array, top: Array) -> void:
	var rule := ColorRect.new()
	rule.color = UiTokens.RULE
	rule.custom_minimum_size = Vector2(0, 2)
	_board.add_child(rule)
	var checking: Array = _view.get("checking", [])
	var ranked_row: Dictionary = {}
	for row: Dictionary in top:
		if mine.any(func(run: Dictionary) -> bool: return run.entry_id == row.entry_id): ranked_row = row; break
	var eligible: Array = mine.filter(func(run: Dictionary) -> bool: return not run.assisted)
	if not ranked_row.is_empty():
		_board.add_child(Rows.own(int(ranked_row.ticks), int(ranked_row.rank), false, _compact))
	elif not eligible.is_empty():
		var best: Dictionary = eligible[0]
		_board.add_child(Rows.own(int(best.ticks), 0, best.entry_id in checking, _compact))
	elif not mine.is_empty():
		_board.add_child(Rows.own(int(mine[0].ticks), 0, false, _compact))
	else:
		_board.add_child(_note(PlayerCopy.LEADERBOARD_NO_RUN))
	var newest: Dictionary = {}
	for run: Dictionary in mine:
		if newest.is_empty() or str(run.finished_at) > str(newest.finished_at): newest = run
	if not newest.is_empty() and newest.entry_id in checking:
		var line := _note(PlayerCopy.LEADERBOARD_NEWEST_CHECKING)
		line.name = "LeaderboardCheckingNote"
		_board.add_child(line)

func _ask_report(board: String, entry_id: String) -> void:
	if is_instance_valid(_modal) or not _alive: return
	_modal = InGameModal.open(_root, "LeaderboardReportModal", PlayerCopy.LEADERBOARD_REPORT_TITLE)
	_modal.label(PlayerCopy.LEADERBOARD_REPORT_BODY)
	var confirm := func() -> void:
		_modal.close(false)
		_report(board, entry_id)
	var send: Button = _modal.add_actions(PlayerCopy.LEADERBOARD_REPORT_SEND, confirm, PlayerCopy.LEADERBOARD_REPORT_CANCEL)
	send.grab_focus()

func _report(board: String, entry_id: String) -> void:
	var answer: Dictionary = await client.report(board, entry_id)
	if not _alive: return
	notice.emit(PlayerCopy.LEADERBOARD_REPORTED if answer.get("ok", false) else PlayerCopy.LEADERBOARD_REPORT_FAILED, false)

func _pill(text: String, selected: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if selected: ThemeRules.selected_tab(button)
	else: ThemeRules.plain_tab(button)
	return button

func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16 if _compact else 18)
	label.add_theme_color_override("font_color", UiTokens.MUTED)
	return label

func _icon_button(icon: Texture2D, description: String, action: Callable) -> Button:
	var button := Button.new()
	button.icon = icon
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	button.tooltip_text = description
	button.accessibility_name = description
	button.custom_minimum_size = Vector2(48, 48)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_constant_override("icon_max_width", 28)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		button.add_theme_color_override("icon_" + state + "_color", UiTokens.CREAM)
	button.add_theme_stylebox_override("normal", ThemeRules.rounded(Color.TRANSPARENT, 14))
	button.add_theme_stylebox_override("hover", ThemeRules.rounded(Color("2b5550"), 14))
	button.add_theme_stylebox_override("pressed", ThemeRules.rounded(Color("2b5550"), 14))
	if description == "Back": ThemeRules.danger(button, icon)
	button.pressed.connect(action)
	return button

extends "res://presentation/duels/duel_page_base.gd"
## Race a recorded run: one row per chapter open to you, with our own run
## (the developers' time) and the chapter's leaderboard button, the shared
## trophy and "Top 10" (race-picker board 1B). The button opens the top 10
## picker (duel_race_picker.gd) through the flow (picker_requested), and is
## greyed while the board has no times ("No times yet"); /v1/duels/ghosts only
## says whether a board has any. A race starts a ghost race with your partner,
## which the flow (duels_flow.gd) opens like any duel. Ghost races pay like
## ordinary turns together; the first win over our own run on a chapter adds a
## one time bonus, shown on the result page only, so nothing here mentions a prize.
const BusyTapGate = preload("res://presentation/busy_tap_gate.gd")
const DuelModel = preload("res://services/duel_model.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
const Icons = preload("res://presentation/kit/icons.gd")
const DashedBox = preload("res://presentation/kit/dashed_box.gd")

## source: "developer" or "board"; entry_id: the board run's, or null.
signal race_requested(chapter_key: String, source: String, entry_id: Variant, control: Control)
## The chapter's leaderboard button: open its top 10 picker.
signal picker_requested(chapter_key: String, control: Control)

## Chapter keys open to you, in the Chapters order.
var chapters: Array = []
## services/duels_client.gd ghosts(): board key -> {developer, top}; empty while loading.
var ghosts: Dictionary = {}
var failed := false
var _list: VBoxContainer
var _gate: BusyTapGate

func page_name() -> String: return "DuelGhosts"
func title_text() -> String: return PlayerCopy.DUELS_GHOST_TITLE
func subtitle_text() -> String: return PlayerCopy.DUELS_GHOST_SUBTITLE

func opened() -> void:
	_gate = BusyTapGate.new(root)

func show_ghosts(boards: Array, did_fail: bool = false) -> void:
	ghosts = {}
	for item: Dictionary in boards: ghosts[item.board] = item
	failed = did_fail
	if is_instance_valid(_list): _render()

## Our run's time on the chapter, or -1 when there is none.
func developer_ticks(key: String) -> int:
	return int(ghosts.get(key, {}).get("developer", -1))

func tap(control: Control, run: Callable) -> void:
	await _gate.tap(control, "...", Callable(), run, alive)

func _build() -> void:
	var box := Kit.panel("DuelGhostList")
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ThemeRules.touch_scroll(scroll)
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	_render()

func _render() -> void:
	Kit.clear(_list)
	if ghosts.is_empty():
		_list.add_child(Kit.wrapped(PlayerCopy.DUELS_FAILED if failed else PlayerCopy.DUELS_LOADING, 18))
		return
	for key: String in chapters:
		_list.add_child(_chapter_row(key, ghosts.get(key, {})))

func _chapter_row(key: String, ghost: Dictionary) -> Control:
	var card := Kit.panel("Ghost_" + key.replace("@", "_"), Kit.CARD_FILL, Kit.PANEL_EDGE, 14, 10.0)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	card.add_child(line)
	line.add_child(Kit.picture(key, Vector2(150, 84), 10))
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	line.add_child(column)
	column.add_child(Kit.text(RoomChapterTitle.title(key, str(Registry.descriptor(key).get("title", key))), 22, UiTokens.CREAM, true))
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 10)
	column.add_child(options)
	if int(ghost.get("developer", -1)) > 0: options.add_child(_option(key, PlayerCopy.DUELS_GHOST_DEVELOPERS, int(ghost.developer), "developer", null))
	options.add_child(_top_button(key, not (ghost.get("top", []) as Array).is_empty()))
	return card

## The chapter's leaderboard button, beside Our run: the trophy and Top 10, or
## greyed with "No times yet" while the board has none.
func _top_button(key: String, has_times: bool) -> Button:
	var button := Kit.button(PlayerCopy.RACE_PICK_TOP if has_times else PlayerCopy.RACE_PICK_NO_TIMES, Callable(), false, 48)
	button.name = "RaceTop_" + key.replace("@", "_")
	Kit.icon_on(button, Icons.LEADERBOARD, true, 22)
	button.add_theme_constant_override("h_separation", 10)
	button.custom_minimum_size.x = 128
	if has_times: button.pressed.connect(func(): picker_requested.emit(key, button))
	else:
		button.disabled = true
		DashedBox.grey(button)
		button.add_theme_font_size_override("font_size", 16)
	return button

func _option(key: String, label: String, ticks: int, source: String, entry_id: Variant) -> Control:
	var button := Kit.button("%s  %s" % [label, DuelModel.time_text(ticks)], Callable(), false, 48)
	button.name = "Race_" + source + ("_" + str(entry_id).left(6) if entry_id != null else "")
	button.custom_minimum_size.x = 190
	button.pressed.connect(func(): race_requested.emit(key, source, entry_id, button))
	return button

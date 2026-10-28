extends "res://presentation/duels/duel_page_base.gd"
## The Duels lobby, your pair's duel home (duels-concepts OWNER-CHOSEN-lobby):
## - Your party: both pips, the room boost line while it applies, and Party;
## - Open duels: challenges to your pair with Accept and Not now, and the ones
##   you sent, waiting; then Race a recorded run;
## - Your duels: running duels and ghost races as tiles with both pairs' dots
##   and times, and finished ones as result tiles.
## Start a duel sits in the header. Every request goes through the flow
## (presentation/duels/duels_flow.gd), which owns the client; this page only
## draws the lobby it is given and says what was tapped. Taps wait through a
## BusyTapGate, so a first tap always registers and a second one waits.
## The lobby is read again on open, when a page over it closes, and every
## REFRESH_SECONDS while it is in front; never per frame.
const DuelModel = preload("res://services/duel_model.gd")
const BusyTapGate = preload("res://presentation/busy_tap_gate.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
const TROPHY_ICON = preload("res://assets/ui/whats_new/star.svg")
const INFO_ICON = preload("res://assets/ui/social/info.svg")
const REFRESH_SECONDS := 30.0
const TILE_WIDTH := 268.0

signal start_requested
signal party_requested
signal ghosts_requested
## A tile's or challenge's button: "accept", "decline", "play", "open" or "result".
signal duel_action(view: Dictionary, action: String, control: Control)
signal refresh_requested

## This player's id, and func(id) -> String naming a player ("You", a friend's name or "").
var me := ""
var name_of: Callable
## The party's room boost percent this phone knows of (this player's own Full Journey).
var boost_percent := 0
var _lobby: Dictionary = {}
var _state := "loading"
var _party_box: Control
var _open_list: VBoxContainer
var _tiles: HBoxContainer
var _overlay: CanvasLayer
var _gate: BusyTapGate
var _timer: Timer
var _foreground := true

func page_name() -> String: return "DuelsScreen"
func title_text() -> String: return PlayerCopy.DUELS_TITLE
func subtitle_text() -> String: return PlayerCopy.DUELS_SUBTITLE

func header_action() -> Control:
	var start := Kit.button(PlayerCopy.DUELS_START, func(): start_requested.emit())
	start.name = "DuelsStart"
	start.icon = ARROW_ICON
	start.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	start.expand_icon = false
	start.custom_minimum_size = Vector2(260, 56)
	return start

func opened() -> void:
	_gate = BusyTapGate.new(root)
	_timer = Timer.new()
	_timer.wait_time = REFRESH_SECONDS
	_timer.timeout.connect(func() -> void: if _foreground and not Kit.showing(_overlay): refresh_requested.emit())
	add_child(_timer)
	_timer.start()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]: _foreground = false
	elif what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]: _foreground = true
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST: go_back()

func go_back() -> void:
	if Kit.showing(_overlay): _overlay.go_back()
	else: super()

## Opens a page over the lobby; it closes with the lobby, and Back reaches it first.
func open_overlay(page: CanvasLayer) -> void:
	if Kit.showing(_overlay): _overlay.close()
	_overlay = page
	page.closed.connect(func() -> void: if alive(): refresh_requested.emit())
	add_child(page)

func overlay() -> CanvasLayer:
	return _overlay if Kit.showing(_overlay) else null

## The flow's answer: a lobby (services/duels_client.gd valid_lobby), or {} with `failed`.
func show_lobby(lobby: Dictionary, failed: bool = false) -> void:
	if not lobby.is_empty():
		_lobby = lobby
		_state = "ready"
	elif _lobby.is_empty():
		_state = "failed" if failed else "loading"
	if is_instance_valid(_tiles): _render()

## A tap that waits for its work: `run` is awaited with the control holding a short label.
func tap(control: Control, run: Callable) -> void:
	await _gate.tap(control, "...", Callable(), run, alive)

func _build() -> void:
	_party_box = Kit.panel("DuelsParty", Kit.PANEL_FILL, Kit.PANEL_EDGE, 18, 16.0)
	body.add_child(_party_box)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	body.add_child(columns)
	var left := Kit.panel("DuelsOpen")
	left.custom_minimum_size.x = 330.0 if compact else 380.0
	columns.add_child(left)
	var left_column := VBoxContainer.new()
	left_column.add_theme_constant_override("separation", 10)
	left.add_child(left_column)
	left_column.add_child(Kit.text(PlayerCopy.DUELS_OPEN, 28 if compact else 32, UiTokens.CREAM, true))
	var open_scroll := ScrollContainer.new()
	open_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	open_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ThemeRules.touch_scroll(open_scroll)
	left_column.add_child(open_scroll)
	_open_list = VBoxContainer.new()
	_open_list.name = "DuelsOpenList"
	_open_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_open_list.add_theme_constant_override("separation", 10)
	open_scroll.add_child(_open_list)
	left_column.add_child(_ghost_row())
	var note := HBoxContainer.new()
	note.add_theme_constant_override("separation", 8)
	note.add_child(_icon(INFO_ICON, 20))
	note.add_child(Kit.text(PlayerCopy.DUELS_RECORDING_READY, 16, UiTokens.SOFT))
	left_column.add_child(note)
	var right := Kit.panel("DuelsYours")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	var right_column := VBoxContainer.new()
	right_column.add_theme_constant_override("separation", 10)
	right.add_child(right_column)
	right_column.add_child(Kit.text(PlayerCopy.DUELS_YOURS, 28 if compact else 32, UiTokens.CREAM, true))
	var tile_scroll := ScrollContainer.new()
	tile_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tile_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ThemeRules.touch_scroll(tile_scroll)
	right_column.add_child(tile_scroll)
	_tiles = HBoxContainer.new()
	_tiles.name = "DuelsTiles"
	_tiles.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tiles.add_theme_constant_override("separation", 12)
	tile_scroll.add_child(_tiles)
	_render()

func _render() -> void:
	_render_party()
	Kit.clear(_open_list)
	Kit.clear(_tiles)
	if _state != "ready":
		_open_list.add_child(Kit.wrapped(PlayerCopy.DUELS_LOADING if _state == "loading" else PlayerCopy.DUELS_FAILED, 18))
		return
	var open: Array = []
	var running: Array = []
	for view: Dictionary in _lobby.duels:
		if not DuelModel.shown(view): continue
		if DuelModel.section(view) == "challenge": open.append(view)
		else: running.append(view)
	# Challenges to you first, then the ones you sent.
	open.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.mine > b.mine)
	for view: Dictionary in open: _open_list.add_child(_challenge_card(view))
	if open.is_empty(): _open_list.add_child(Kit.wrapped(PlayerCopy.DUELS_NO_OPEN, 17))
	# Your move first, then running, then results.
	var order := func(view: Dictionary) -> int: return 0 if DuelModel.action(view, me) == "play" else 1 if view.status == "running" else 2
	running.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return order.call(a) < order.call(b) or (order.call(a) == order.call(b) and a.updated_ms > b.updated_ms))
	for view: Dictionary in running: _tiles.add_child(_tile(view))
	if running.is_empty():
		var empty := Kit.wrapped(PlayerCopy.DUELS_NO_DUELS, 18)
		empty.custom_minimum_size.x = 420
		_tiles.add_child(empty)

func _render_party() -> void:
	Kit.clear(_party_box)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 22)
	_party_box.add_child(line)
	line.add_child(Kit.text(PlayerCopy.DUELS_YOUR_PARTY, 30 if compact else 36, UiTokens.CREAM, true))
	var party: Dictionary = _lobby.get("party", {})
	var partner: Variant = party.get("partner") if party.get("intact", false) else null
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 18)
	pips.add_child(_named_pip(PlayerCopy.DUEL_YOU, Kit.FIRST_PIP, true))
	if partner != null: pips.add_child(_named_pip(str(name_of.call(partner)) if name_of.is_valid() else "", Kit.SECOND_PIP, false))
	line.add_child(pips)
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_child(middle)
	if partner == null:
		var waiting: Variant = party.get("invite_out")
		var invites: Array = party.get("invites_in", [])
		var words := PlayerCopy.DUELS_NO_PARTY
		if not invites.is_empty(): words = PlayerCopy.DUELS_PARTY_INVITED % str(name_of.call(invites[0]))
		elif waiting != null: words = PlayerCopy.DUELS_PARTY_WAITING % str(name_of.call(waiting))
		middle.add_child(Kit.wrapped(words, 18))
	elif boost_percent > 0:
		middle.add_child(Kit.text(PlayerCopy.DUELS_BOOST % boost_percent, 26, UiTokens.CREAM, true))
		middle.add_child(Kit.text(PlayerCopy.DUELS_BOOST_NOTE, 18, UiTokens.SOFT))
	var party_button := Kit.button(PlayerCopy.DUELS_PARTY, func(): party_requested.emit(), false, 56)
	party_button.name = "DuelsPartyButton"
	party_button.custom_minimum_size.x = 200
	party_button.icon = preload("res://assets/ui/settings/chevron.svg")
	party_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(party_button)

func _named_pip(label: String, color: Color, own: bool) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.add_child(Kit.pip(Vector2(56, 64), color, own))
	var name_label := Kit.text(label, 17)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	return column

## A challenge: the chapter, the other pair and its buttons.
func _challenge_card(view: Dictionary) -> Control:
	var card := Kit.panel("Challenge_" + str(view.duel_id).left(8), Kit.CARD_FILL, Kit.PANEL_EDGE, 14, 10.0)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	card.add_child(line)
	line.add_child(Kit.picture(view.chapter, Vector2(118, 96) if not compact else Vector2(96, 84)))
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	line.add_child(column)
	var title := Kit.text(_chapter_title(view.chapter), 21, UiTokens.CREAM, true)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(title)
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 6)
	pair.add_child(Kit.pips(Vector2(30, 40)))
	var who := Kit.text(DuelModel.pair_title(view, 1 - view.mine, name_of).replace(" + ", " and "), 17, UiTokens.SOFT)
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pair.add_child(who)
	column.add_child(pair)
	if view.mine == 1:
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 8)
		var accept := Kit.button(PlayerCopy.DUELS_ACCEPT, Callable(), true, 46)
		accept.name = "Accept"
		accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		accept.pressed.connect(func(): duel_action.emit(view, "accept", accept))
		buttons.add_child(accept)
		var later := Kit.button(PlayerCopy.DUELS_NOT_NOW, Callable(), false, 46)
		later.name = "NotNow"
		later.pressed.connect(func(): duel_action.emit(view, "decline", later))
		buttons.add_child(later)
		column.add_child(buttons)
	else:
		column.add_child(Kit.text(PlayerCopy.DUELS_WAITING_ANSWER, 16, UiTokens.MUTED))
	return card

## A running duel, ghost race or result: the chapter, whose turn it is, both
## pairs' pips, dots and times, and one button.
func _tile(view: Dictionary) -> Control:
	var action := DuelModel.action(view, me)
	var lit := action == "play"
	var card := Kit.panel("Tile_" + str(view.duel_id).left(8), Kit.CARD_FILL, Kit.HIGHLIGHT_EDGE if lit else Kit.PANEL_EDGE, 16, 10.0)
	card.custom_minimum_size.x = TILE_WIDTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)
	var picture := Kit.picture(view.chapter, Vector2(TILE_WIDTH - 20.0, 122 if compact else 140))
	picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(picture)
	var title := Kit.text(_chapter_title(view.chapter), 22, UiTokens.CREAM, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(title)
	var status := DuelModel.result_title(view, name_of) if action == "result" else DuelModel.turn_line(view, view.mine, name_of)
	column.add_child(Kit.pill(status, lit))
	var lanes := Kit.panel("Lanes", Kit.LANE_FILL, Kit.PANEL_EDGE, 12, 8.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	lanes.add_child(row)
	for index: int in [view.mine, 1 - view.mine]:
		row.add_child(_lane(view, index))
	column.add_child(lanes)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var label := PlayerCopy.DUELS_PLAY if action == "play" else PlayerCopy.DUELS_SEE_RESULT if action == "result" else PlayerCopy.DUELS_OPEN_DUEL
	var go := Kit.button(label, Callable(), lit, 52)
	go.name = "TileAction"
	go.pressed.connect(func(): duel_action.emit(view, action, go))
	column.add_child(go)
	return card

func _lane(view: Dictionary, index: int) -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 3)
	var who := Kit.text(DuelModel.pair_title(view, index, name_of), 15, UiTokens.CREAM)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.custom_minimum_size.x = 100
	column.add_child(who)
	var pips := Kit.pips(Vector2(30, 40), index == view.mine)
	if index == 1 and view.kind == "ghost": pips.modulate = Color(1, 1, 1, 0.55)
	column.add_child(pips)
	var steps := DuelModel.steps(view, index)
	column.add_child(Kit.dots(steps.x, steps.y, 10.0))
	var time := Kit.text(DuelModel.time_text(DuelModel.ticks(view, index)), 24, UiTokens.CREAM, true)
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(time)
	return column

func _ghost_row() -> Control:
	var button := Button.new()
	button.name = "DuelsRaceRecorded"
	button.custom_minimum_size = Vector2(0, 84)
	ThemeRules.secondary(button)
	button.pressed.connect(func(): ghosts_requested.emit())
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 16
	line.offset_right = -14
	line.add_theme_constant_override("separation", 14)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(line)
	line.add_child(_icon(TROPHY_ICON, 34))
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 0)
	words.add_child(Kit.text(PlayerCopy.DUELS_RACE_RECORDED, 21, UiTokens.CREAM, true))
	words.add_child(Kit.text(PlayerCopy.DUELS_RACE_RECORDED_NOTE, 16, UiTokens.SOFT))
	line.add_child(words)
	line.add_child(_icon(preload("res://assets/ui/settings/chevron.svg"), 20))
	return button

func _icon(texture: Texture2D, edge: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.modulate = UiTokens.SOFT
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(edge, edge)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

static func _chapter_title(key: String) -> String:
	return RoomChapterTitle.title(key, str(Registry.descriptor(key).get("title", key)))

extends "res://presentation/duels/duel_page_base.gd"
## The Duels lobby, your pair's duel home (duels-concepts OWNER-CHOSEN-lobby):
## - Your party: both pips, the room boost line while it applies, and Party;
## - Open duels: challenges to your pair with Accept and Not now, and the ones
##   you sent, waiting; then Public duels (while the server has them, board 1A)
##   and Race a recorded run;
## - Your duels: running duels and ghost races as tiles with both pairs' dots
##   and times, and finished ones as result tiles.
## Start a duel sits in the header. While the server charges duel energy
## (board-10-energy-lobby), the energy meter (energy_meter.gd pill, made by the
## flow) stands beside the title in place of the quiet line, and Start a duel,
## Accept and Race a recorded run wear the cost chip (kit/energy_chip.gd).
## Every request goes through the flow
## (presentation/duels/duels_flow.gd), which owns the client; this page only
## draws the lobby it is given and says what was tapped. Taps wait through a
## BusyTapGate, so a first tap always registers and a second one waits.
## The flow reads the lobby again on open, when a page over it closes, and
## once a minute while it is in front and wants_refresh() says something can
## change without this player (services/refresh_schedule.gd); never per frame.
const DuelModel = preload("res://services/duel_model.gd")
const BusyTapGate = preload("res://presentation/busy_tap_gate.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
## The leaderboard icon every screen shares (presentation/kit/icons.gd): Race a recorded run picks from the board.
const Icons = preload("res://presentation/kit/icons.gd")
const PollenMark = preload("res://presentation/kit/pollen_mark.gd")
## The party boost line's font size; its Pollen mark is sized from it.
const BOOST_FONT := 26
const TILE_WIDTH := 268.0
## The empty lobby's art (presentation/empty_state.gd SPOTS), the owner's pick.
const EMPTY_ART := "duels_f"
## The empty Open duels column's art (presentation/empty_state.gd SPOTS), the owner's pick.
const OPEN_EMPTY_ART := "open_a"
const Seats = preload("res://presentation/duels/public_seats.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")
const EnergyChip = preload("res://presentation/kit/energy_chip.gd")

signal start_requested
signal party_requested
signal ghosts_requested
signal public_requested
## A tile's or challenge's button: "accept", "decline", "play", "open" or "result".
signal duel_action(view: Dictionary, action: String, control: Control)
signal refresh_requested

## This player's id, and func(id) -> String naming a player ("You", a friend's name or "").
var me := ""
var name_of: Callable
## The party's room boost percent this phone knows of (this player's own Full Journey).
var boost_percent := 0
## Whether the server has public duels open: the Public duels row shows only then.
var public_shown := false
## The player's switch as the duels client keeps it (services/duels_client.gd public_on), set by the flow: the row's words before a lobby brings its own.
var public_on := true
## The energy meter's pill beside the title (presentation/duels/energy_meter.gd), or null while
## the server charges no energy; set by the flow before the lobby opens.
var energy_meter: Control = null
## Whether starting and joining cost energy: the cost chips show only then.
var energy_cost := false
## A line under a challenge's buttons, by duel id, kept across redraws (the partner waiting for energy).
var _notes: Dictionary = {}
var _lobby: Dictionary = {}
var _state := "loading"
var _party_box: Control
var _open_list: VBoxContainer
var _tiles: HBoxContainer
var _tile_scroll: ScrollContainer
## Holds the empty lobby's art in place of the tiles while there is no duel at all.
var _empty: VBoxContainer
## The art the empty lobby draws; EMPTY_ART unless a capture asks for another.
var empty_art := EMPTY_ART
var _overlay: CanvasLayer
var _gate: BusyTapGate
var _public_row: Button
var _public_note: Label

func page_name() -> String: return "DuelsScreen"
func title_text() -> String: return PlayerCopy.DUELS_TITLE
func subtitle_text() -> String: return PlayerCopy.DUELS_SUBTITLE

func header_action() -> Control:
	var start := Kit.button(PlayerCopy.DUELS_START, func(): start_requested.emit())
	start.name = "DuelsStart"
	Kit.icon_on(start, ARROW_ICON)
	start.custom_minimum_size = Vector2(260, 56)
	# The chip in the arrow's place, as the board draws it.
	if energy_cost: EnergyChip.on_button(start, 22)
	# Starting needs the server: greyed while the phone is offline.
	OfflineHold.hold(start)
	return start

func header_beside() -> Control:
	return energy_meter

func opened() -> void:
	_gate = BusyTapGate.new(root)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST: go_back()

func go_back() -> void:
	# A screen over Duels that takes Back itself (the community rules) closes alone.
	if back_held(): return
	if Kit.showing(_overlay): _overlay.go_back()
	else: super()

## Opens a page over the lobby; it closes with the lobby, and Back reaches it first.
func open_overlay(page: CanvasLayer) -> void:
	if Kit.showing(_overlay): _overlay.close()
	_overlay = page
	page.set("stack_layer", layer + 1)
	page.closed.connect(func() -> void: if alive(): refresh_requested.emit())
	add_child(page)

func overlay() -> CanvasLayer:
	return _overlay if Kit.showing(_overlay) else null

## Whether anything on the lobby can change without this player: a running duel or a challenge. Only then does the lobby read again on its own.
func wants_refresh() -> bool:
	if _lobby.is_empty(): return true
	if not _lobby.party.invites_in.is_empty() or _lobby.party.invite_out != null: return true
	return _lobby.duels.any(func(view: Dictionary) -> bool: return view.status in ["running", "challenged"])

## The flow's answer: a lobby (services/duels_client.gd valid_lobby), or {} with `failed`.
func show_lobby(lobby: Dictionary, failed: bool = false) -> void:
	if not lobby.is_empty():
		_lobby = lobby
		_state = "ready"
	elif _lobby.is_empty():
		_state = "failed" if failed else "loading"
	if is_instance_valid(_tiles): _render()

## Says `words` under the buttons of the challenge `duel_id` ("Maya is waiting for energy"), kept
## across the lobby's redraws until the next tap on it.
func note(duel_id: String, words: String) -> void:
	_notes[duel_id] = words
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
	left_column.add_child(_public_entry())
	left_column.add_child(_ghost_row())
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
	_tile_scroll = tile_scroll
	_empty = VBoxContainer.new()
	_empty.name = "DuelsEmpty"
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty.visible = false
	right_column.add_child(_empty)
	_tiles = HBoxContainer.new()
	_tiles.name = "DuelsTiles"
	_tiles.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tiles.add_theme_constant_override("separation", 12)
	tile_scroll.add_child(_tiles)
	_render()

func _render() -> void:
	_render_party()
	_render_public()
	Kit.clear(_open_list)
	Kit.clear(_tiles)
	Kit.clear(_empty)
	_empty.visible = false
	_tile_scroll.visible = true
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
	# No challenge: the column's own small empty art, above the Race a recorded run card and never over it.
	if open.is_empty(): ThemeRules.empty_state(_open_list, OPEN_EMPTY_ART, "", PlayerCopy.DUELS_NO_OPEN)
	# Your move first, then running, then results.
	var order := func(view: Dictionary) -> int: return 0 if DuelModel.action(view, me) == "play" else 1 if view.status == "running" else 2
	running.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return order.call(a) < order.call(b) or (order.call(a) == order.call(b) and a.updated_ms > b.updated_ms))
	for view: Dictionary in running: _tiles.add_child(_tile(view))
	if running.is_empty() and open.is_empty():
		# Nothing at all yet: the hand drawn empty art every list uses (presentation/empty_state.gd).
		_tile_scroll.visible = false
		_empty.visible = true
		ThemeRules.empty_state(_empty, empty_art, PlayerCopy.DUELS_EMPTY_TITLE, PlayerCopy.DUELS_NO_DUELS)
	elif running.is_empty():
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
	# Full Journey shows under your own pip while it counts here (boost_percent: never on iPhone).
	pips.add_child(_named_pip(PlayerCopy.DUEL_YOU, Kit.FIRST_PIP, true, boost_percent > 0))
	if partner != null: pips.add_child(_named_pip(str(name_of.call(partner)) if name_of.is_valid() else "", Kit.SECOND_PIP, false, false, party.get("partner_look", {})))
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
		# The Pollen mark (kit/pollen_mark.gd) beside the boost, sized from its line.
		var boost := HBoxContainer.new()
		boost.name = "DuelsBoost"
		boost.add_theme_constant_override("separation", 10)
		boost.add_child(PollenMark.beside(BOOST_FONT))
		boost.add_child(Kit.text(PlayerCopy.DUELS_BOOST % boost_percent, BOOST_FONT, UiTokens.CREAM, true))
		middle.add_child(boost)
		middle.add_child(Kit.text(PlayerCopy.DUELS_BOOST_NOTE, 18, UiTokens.SOFT))
	var party_button := Kit.button(PlayerCopy.DUELS_PARTY, func(): party_requested.emit(), false, 56)
	party_button.name = "DuelsPartyButton"
	party_button.custom_minimum_size.x = 200
	Kit.icon_on(party_button, preload("res://assets/ui/settings/chevron.svg"), false, 20)
	line.add_child(party_button)

func _named_pip(label: String, color: Color, own: bool, full_journey: bool = false, look: Dictionary = {}) -> Control:
	var column := VBoxContainer.new()
	# With the Full Journey tag the pip is a little smaller and the tag tucks under the name, so the row keeps its height.
	column.add_theme_constant_override("separation", -5 if full_journey else 0)
	column.add_child(Kit.pip(Vector2(50, 56) if full_journey else Vector2(56, 64), color, own, look))
	var name_label := Kit.text(label, 17)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	if full_journey:
		var tag := Kit.pill(PlayerCopy.SETTINGS_FULL_JOURNEY, true, 13)
		tag.name = "DuelsFullJourneyTag"
		column.add_child(tag)
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
	pair.add_child(Kit.pips(Vector2(30, 40), DuelModel.members(view, 1 - view.mine), me, DuelModel.looks(view, 1 - view.mine)))
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
		accept.pressed.connect(func():
			_notes.erase(view.duel_id)
			duel_action.emit(view, "accept", accept))
		if energy_cost: EnergyChip.on_button(accept, 18)
		OfflineHold.hold(accept)
		buttons.add_child(accept)
		var later := Kit.button(PlayerCopy.DUELS_NOT_NOW, Callable(), false, 46)
		later.name = "NotNow"
		later.pressed.connect(func(): duel_action.emit(view, "decline", later))
		buttons.add_child(later)
		column.add_child(buttons)
		if _notes.has(view.duel_id):
			var said := Kit.wrapped(str(_notes[view.duel_id]), 15, UiTokens.SOFT)
			said.name = "ChallengeNote"
			column.add_child(said)
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
	# Sized so a lobby with an invite and a result tile fits a phone without scrolling (tests/test_duel_page_layout.gd).
	var picture := Kit.picture(view.chapter, Vector2(TILE_WIDTH - 20.0, 106 if compact else 132))
	picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(picture)
	# A public duel's small tag on its picture (board 5C).
	if DuelModel.is_public(view):
		var tag := Seats.tag(12)
		tag.position = Vector2(8, 8)
		picture.add_child(tag)
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
	var pips: Control = Kit.pips(Vector2(30, 40), DuelModel.members(view, index), me, DuelModel.looks(view, index)) if not DuelModel.is_public(view) else _public_pips(view, index)
	if index == 1 and view.kind == "ghost": pips.modulate = Color(1, 1, 1, 0.55)
	column.add_child(pips)
	# The pair ahead shows its time after as many turns as the pair behind; its dots say how many (DuelModel.lane).
	var lane := DuelModel.lane(view, index)
	column.add_child(Kit.lane_dots(lane, TILE_WIDTH * 0.5 - 24.0, 10.0))
	# An open pair has no time yet (board 5C).
	var nobody := DuelModel.open_seats(view, index) == 2
	var time := Kit.text(PlayerCopy.PUBLIC_NOBODY_YET if nobody else DuelModel.time_text(int(lane.ticks)), 16 if nobody else 24, UiTokens.SOFT if nobody else UiTokens.CREAM, not nobody)
	time.name = "TileTime%d" % index
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(time)
	return column

## A public side on a tile: pips and dashed rings, no names (public_seats.gd).
func _public_pips(view: Dictionary, index: int) -> Control:
	var seats := Seats.view_seats(view, index, me, name_of)
	var pair := HBoxContainer.new()
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	pair.add_theme_constant_override("separation", 4)
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for slot in range(2):
		pair.add_child(Seats.seat(seats[slot], slot, 36.0, false, Callable(), 13, false))
	return pair

## The Public duels row (board 1A), above Race a recorded run: it opens the list, or while the
## player's switch is off reads "Play with players you don't know" and opens the first-time card.
func _public_entry() -> Control:
	_public_row = Button.new()
	_public_row.name = "DuelsPublic"
	_public_row.custom_minimum_size = Vector2(0, 84)
	_public_row.visible = public_shown
	ThemeRules.secondary(_public_row)
	_public_row.pressed.connect(func(): public_requested.emit())
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 12
	line.offset_right = -14
	line.add_theme_constant_override("separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_public_row.add_child(line)
	var pair := Kit.pips(Vector2(30, 38), [me, null], me, [{}, {}], -6)
	line.add_child(pair)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 0)
	words.add_child(Kit.text(PlayerCopy.PUBLIC_DUELS_ROW, 21, UiTokens.CREAM, true))
	_public_note = Kit.text(PlayerCopy.PUBLIC_DUELS_ROW_NOTE, 16, UiTokens.SOFT)
	words.add_child(_public_note)
	line.add_child(words)
	line.add_child(_icon(preload("res://assets/ui/settings/chevron.svg"), 20))
	return _public_row

## The row's words follow the player's switch: off, it invites them in.
func _render_public() -> void:
	if not is_instance_valid(_public_row): return
	_public_row.visible = public_shown
	# It reads the list from the server: greyed while the phone is offline.
	OfflineHold.hold(_public_row)
	var on: bool = _lobby.get("public", {}).get("on", public_on)
	_public_note.text = PlayerCopy.PUBLIC_DUELS_ROW_NOTE if on else PlayerCopy.PUBLIC_DUELS_ROW_OFF

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
	line.add_child(_icon(Icons.LEADERBOARD, 34))
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 0)
	var title := Kit.text(PlayerCopy.DUELS_RACE_RECORDED, 21, UiTokens.CREAM, true)
	if energy_cost:
		# The race's cost beside its title (board-10-energy-lobby).
		var line_up := HBoxContainer.new()
		line_up.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line_up.add_theme_constant_override("separation", 12)
		line_up.add_child(title)
		line_up.add_child(EnergyChip.make(20))
		words.add_child(line_up)
	else: words.add_child(title)
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

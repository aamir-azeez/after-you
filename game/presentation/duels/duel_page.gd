extends "res://presentation/duels/duel_page_base.gd"
## One duel while it runs (duels-concepts OWNER-CHOSEN-duel-in-progress): each
## pair's pips and names, whose turn it is, its step dots, "n of m steps" and
## its time so far; "Waiting does not add time." with how far ahead a pair is
## once both reach the same stage; the chapter's picture; and the card for
## your own pair's next move: Play your turn (or View turns while your partner
## plays). A ghost race shows the recorded run's whole time on the right.
## Leave duel sits under the card while your pair has not finished; once your
## pair left, the card says so and offers nothing more.
## The flow (duels_flow.gd) reads the duel again while this page is up and
## hands it in through show_duel(); nothing here polls or draws per frame.
## A public duel (boards 3 to 6) adds the PUBLIC tag, draws its seats through
## public_seats.gd (an open seat is a ring, a stranger a pip you can tap for
## their card: stranger_requested), says which spots are open on the list, and
## shows the duel extra held for you so far (`held`, from the detail read).
const DuelModel = preload("res://services/duel_model.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
const INFO_ICON = preload("res://assets/ui/social/info.svg")
const Seats = preload("res://presentation/duels/public_seats.gd")
const PollenMoney = preload("res://services/pollen_money.gd")

## Play your turn or View turns: the flow opens (or makes, or joins) the pair's room.
signal play_requested(view: Dictionary, control: Control)
signal leave_requested(view: Dictionary)
## A stranger's pip was tapped: side `index`, seat `slot` (public duels only).
signal stranger_requested(view: Dictionary, index: int, slot: int)

var me := ""
var name_of: Callable
var view: Dictionary = {}
## A public duel's held duel extra for this player (services/duels_client.gd duel `held`), {} for none.
var held: Dictionary = {}:
	set(value):
		held = value
		if is_instance_valid(_sides): _render()
var _sides: HBoxContainer
var _tag: Control
var _held: Label
var _note: Label
var _card: VBoxContainer
var _picture_holder: Control

func page_name() -> String: return "DuelPage"
func title_text() -> String: return _chapter_title()
func subtitle_text() -> String: return PlayerCopy.DUEL_IN_PROGRESS

func show_duel(next: Dictionary) -> void:
	view = next
	if is_instance_valid(_sides): _render()

func _build() -> void:
	_sides = HBoxContainer.new()
	_sides.name = "DuelSides"
	_sides.add_theme_constant_override("separation", 16)
	body.add_child(_sides)
	var info := Kit.panel("DuelInfo", Kit.PANEL_FILL, Kit.PANEL_EDGE, 14, 12.0)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	info.add_child(line)
	var icon := TextureRect.new()
	icon.texture = INFO_ICON
	icon.modulate = UiTokens.SOFT
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(26, 26)
	line.add_child(icon)
	_note = Kit.text("", 19, UiTokens.SOFT)
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(_note)
	# The duel extra your public duel turns hold until the duel ends (backend pollen/duel-pay.ts), at the line's end.
	_held = Kit.text("", 19, UiTokens.CREAM, true)
	_held.name = "DuelHeld"
	_held.visible = false
	line.add_child(_held)
	body.add_child(info)
	var bottom := HBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_theme_constant_override("separation", 16)
	body.add_child(bottom)
	_picture_holder = Control.new()
	_picture_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picture_holder.size_flags_stretch_ratio = 1.4
	bottom.add_child(_picture_holder)
	var picture := Kit.picture(str(view.get("chapter", "")), Vector2(0, 0), 18)
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picture_holder.add_child(picture)
	var card := Kit.panel("DuelTurnCard", Kit.PANEL_FILL, Kit.PANEL_EDGE, 18, 18.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(card)
	_card = VBoxContainer.new()
	_card.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.add_theme_constant_override("separation", 12)
	card.add_child(_card)
	_render()

func _render() -> void:
	if view.is_empty(): return
	set_title(_chapter_title(), PlayerCopy.DUEL_IN_PROGRESS)
	_show_tag()
	Kit.clear(_sides)
	for index: int in [view.mine, 1 - view.mine]: _sides.add_child(_side_card(index))
	var ahead := DuelModel.ahead_line(view)
	_note.text = _public_note() if DuelModel.is_public(view) and _open_anywhere() else PlayerCopy.DUEL_WAITING_NO_TIME + ("  " + ahead + "." if not ahead.is_empty() else "")
	_held.visible = int(held.get("amount", 0)) > 0 and held.get("state") == "running"
	if _held.visible: _held.text = PlayerCopy.PUBLIC_HELD_LINE % PollenMoney.grouped(int(held.amount))
	_render_card()

func _side_card(index: int) -> Control:
	var own: bool = index == view.mine
	var card := Kit.panel("DuelSide%d" % index, Kit.PANEL_FILL, Kit.PANEL_EDGE, 18, 16.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	card.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)
	left.add_child(Kit.fitted(Kit.text(DuelModel.pair_title(view, index, name_of), 30 if compact else 34, UiTokens.CREAM, true)))
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 14)
	var side: Variant = view.sides[index]
	var looks := DuelModel.looks(view, index)
	if DuelModel.is_public(view): _public_seats(pips, index)
	for slot in range(2 if not DuelModel.is_public(view) else 0):
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 0)
		column.add_child(Kit.pip(Vector2(92, 108) if not compact else Vector2(74, 88), Kit.FIRST_PIP if slot == 0 else Kit.SECOND_PIP, own and side.members[slot] == me, looks[slot]))
		var shown := ""
		if side is Dictionary and side.members[slot] != null and name_of.is_valid(): shown = str(name_of.call(side.members[slot]))
		var pip_width := 92.0 if not compact else 74.0
		var name_label := Kit.fitted(Kit.text(shown, 19), pip_width, pip_width + 40.0)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(name_label)
		pips.add_child(column)
	if index == 1 and view.kind == "ghost": pips.modulate = Color(1, 1, 1, 0.55)
	left.add_child(pips)
	var rule := ColorRect.new()
	rule.color = Kit.PANEL_EDGE
	rule.custom_minimum_size.x = 1
	row.add_child(rule)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 230 if compact else 270
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	var turn := DuelModel.turn_line(view, index, name_of)
	var lit := own and DuelModel.your_turn(view, me) and turn == PlayerCopy.DUEL_YOUR_TURN
	var pill := Kit.pill(turn, lit, 20)
	# The pill's own padding is 14 a side: a long name trims only past the column's width.
	Kit.fitted(pill.get_child(0), 0.0, right.custom_minimum_size.x - 28.0)
	pill.custom_minimum_size.x = 230
	right.add_child(pill)
	# The pair ahead shows its time after as many turns as the pair behind, and says so (DuelModel.lane).
	var lane := DuelModel.lane(view, index)
	right.add_child(Kit.lane_dots(lane, right.custom_minimum_size.x - 10.0))
	var count := Kit.text(PlayerCopy.DUEL_STEPS % [lane.played, lane.total], 19, UiTokens.SOFT)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(count)
	var label := Kit.text(_time_label(lane), 18, UiTokens.SOFT)
	label.name = "DuelTimeLabel%d" % index
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(label)
	var time := Kit.text(DuelModel.time_text(int(lane.ticks)), 50 if not compact else 42, UiTokens.CREAM, true)
	time.name = "DuelTime%d" % index
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(time)
	return card

## "Time so far", or "Time after 1 step" while the lane's time covers fewer turns than it played.
static func _time_label(lane: Dictionary) -> String:
	if not lane.compared: return PlayerCopy.DUEL_TIME_SO_FAR
	return PlayerCopy.DUEL_TIME_AFTER_ONE if int(lane.counted) == 1 else PlayerCopy.DUEL_TIME_AFTER % int(lane.counted)

func _render_card() -> void:
	Kit.clear(_card)
	var own: Dictionary = view.sides[view.mine]
	var mine_now := DuelModel.your_turn(view, me)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(Kit.pips(Vector2(56, 66), DuelModel.members(view, view.mine), me, DuelModel.looks(view, view.mine)))
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(words)
	var partner := _partner_name()
	var open_beside := DuelModel.is_public(view) and partner.is_empty()
	if own.left:
		# Your pair left: the duel goes on for the other pair, with nothing left to play here.
		words.add_child(Kit.text(PlayerCopy.DUEL_LEFT, 40, UiTokens.CREAM, true))
		words.add_child(Kit.wrapped(PlayerCopy.DUEL_RESULT_YOU_LEFT, 19))
		_card.add_child(head)
		return
	if own.finished:
		words.add_child(Kit.text(PlayerCopy.DUEL_FINISHED, 40, UiTokens.CREAM, true))
		words.add_child(Kit.wrapped(DuelModel.checking_line(view), 19))
	elif mine_now:
		words.add_child(Kit.text(PlayerCopy.DUEL_YOUR_TURN_TITLE, 46 if not compact else 38, UiTokens.CREAM, true))
		words.add_child(Kit.wrapped(_first_line(own, partner, open_beside), 20))
	else:
		words.add_child(Kit.wrapped(PlayerCopy.PUBLIC_WAITING_PARTNER if open_beside else PlayerCopy.DUEL_WAITING_TITLE % partner, 38, UiTokens.CREAM, true))
		words.add_child(Kit.wrapped(PlayerCopy.DUEL_WAITING_BODY, 19))
	_card.add_child(head)
	if not own.finished:
		var play := Kit.button(PlayerCopy.DUEL_PLAY_TURN if mine_now else PlayerCopy.DUEL_VIEW_TURNS, Callable(), mine_now, 70 if not compact else 60)
		play.name = "DuelPlay"
		Kit.icon_on(play, ARROW_ICON, false, 30)
		play.add_theme_font_size_override("font_size", 28 if mine_now else 24)
		play.pressed.connect(func(): play_requested.emit(view, play))
		_card.add_child(play)
		if mine_now:
			var turns := Kit.button(PlayerCopy.DUEL_VIEW_TURNS, Callable(), false, 60)
			turns.name = "DuelViewTurns"
			Kit.icon_on(turns, ARROW_ICON, false, 26)
			turns.pressed.connect(func(): play_requested.emit(view, turns))
			_card.add_child(turns)
		var leave := Button.new()
		leave.name = "DuelLeave"
		leave.text = PlayerCopy.DUEL_LEAVE
		leave.flat = true
		leave.custom_minimum_size = Vector2(0, 44)
		leave.add_theme_color_override("font_color", UiTokens.MUTED)
		leave.pressed.connect(func(): ask("DuelLeaveModal", PlayerCopy.DUEL_LEAVE_TITLE, PlayerCopy.DUEL_LEAVE_BODY, PlayerCopy.DUEL_LEAVE_CONFIRM, func(): leave_requested.emit(view), PlayerCopy.DUEL_LEAVE_KEEP))
		_card.add_child(leave)

## Your partner's name, "your partner", or "" while a public duel's seat beside you is open.
func _partner_name() -> String:
	return DuelModel.partner_name(view, me, name_of)

## The line under Your turn: the partner's path, the first turn, or a public duel's first step.
func _first_line(own: Dictionary, partner: String, open_beside: bool) -> String:
	if own.steps > 0 and not open_beside: return PlayerCopy.DUEL_PARTNER_LEFT_PATH % partner
	if not DuelModel.is_public(view): return PlayerCopy.DUEL_FIRST_TURN
	if open_beside: return PlayerCopy.PUBLIC_GO_FIRST
	return PlayerCopy.PUBLIC_EITHER_FIRST % partner if own.steps == 0 else PlayerCopy.DUEL_PARTNER_LEFT_PATH % partner

## A public side's seats: rings for open seats, pips with names, a stranger's pip tappable for their card.
func _public_seats(row: HBoxContainer, index: int) -> void:
	var seats := Seats.view_seats(view, index, me, name_of)
	var edge := 92.0 if not compact else 74.0
	for slot in range(2):
		var tap := func() -> void: stranger_requested.emit(view, index, slot)
		var made := Seats.seat(seats[slot], slot, edge, false, tap if DuelModel.seat_stranger(view, index, slot) else Callable(), 19)
		made.name = "DuelSeat%d_%d" % [index, slot]
		row.add_child(made)

## Whether any seat of the duel is still open on the list.
func _open_anywhere() -> bool:
	return DuelModel.open_seats(view, 0) + DuelModel.open_seats(view, 1) > 0

## The info line while spots are open: yours, the other pair's beside a named player, or the list's.
func _public_note() -> String:
	if DuelModel.open_seats(view, view.mine) == 1: return PlayerCopy.PUBLIC_NOTE_YOUR_SPOT
	var other := 1 - int(view.mine)
	if DuelModel.open_seats(view, other) == 1:
		for slot in range(2):
			if not DuelModel.seat(view, other, slot).get("open", true): return PlayerCopy.PUBLIC_NOTE_THEIR_SPOT % DuelModel.seat_name(view, other, slot, name_of)
	return PlayerCopy.PUBLIC_NOTE_SPOTS

## The PUBLIC tag after the subtitle while the duel is public.
func _show_tag() -> void:
	if not DuelModel.is_public(view) or is_instance_valid(_tag) or not is_instance_valid(_subtitle): return
	_tag = Seats.tag(15)
	_subtitle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_subtitle.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(_tag)
	_header.move_child(_tag, _subtitle.get_index() + 1)
	_header.add_child(spacer)
	_header.move_child(spacer, _tag.get_index() + 1)

func _chapter_title() -> String:
	var key := str(view.get("chapter", ""))
	return RoomChapterTitle.title(key, str(Registry.descriptor(key).get("title", key)))

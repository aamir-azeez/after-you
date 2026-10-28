extends "res://presentation/duels/duel_page_base.gd"
## One duel while it runs (duels-concepts OWNER-CHOSEN-duel-in-progress): each
## pair's pips and names, whose turn it is, its step dots, "n of m steps" and
## its time so far; "Waiting does not add time." with how far ahead a pair is
## once both reach the same stage; the chapter's picture; and the card for
## your own pair's next move: Play your turn (or View turns while your partner
## plays). A ghost race shows the recorded run's whole time on the right.
## Leave duel sits under the card while your pair has not finished.
## The flow (duels_flow.gd) reads the duel again while this page is up and
## hands it in through show_duel(); nothing here polls or draws per frame.
const DuelModel = preload("res://services/duel_model.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
const INFO_ICON = preload("res://assets/ui/social/info.svg")

## Play your turn or View turns: the flow opens (or makes, or joins) the pair's room.
signal play_requested(view: Dictionary, control: Control)
signal leave_requested(view: Dictionary)

var me := ""
var name_of: Callable
var view: Dictionary = {}
var _sides: HBoxContainer
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
	line.add_child(_note)
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
	Kit.clear(_sides)
	for index: int in [view.mine, 1 - view.mine]: _sides.add_child(_side_card(index))
	var ahead := DuelModel.ahead_line(view)
	_note.text = PlayerCopy.DUEL_WAITING_NO_TIME + ("  " + ahead + "." if not ahead.is_empty() else "")
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
	left.add_child(Kit.text(DuelModel.pair_title(view, index, name_of), 30 if compact else 34, UiTokens.CREAM, true))
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 14)
	var side: Variant = view.sides[index]
	for slot in range(2):
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 0)
		column.add_child(Kit.pip(Vector2(70, 84) if not compact else Vector2(58, 70), Kit.FIRST_PIP if slot == 0 else Kit.SECOND_PIP, own and side.members[slot] == me))
		var shown := ""
		if side is Dictionary and side.members[slot] != null and name_of.is_valid(): shown = str(name_of.call(side.members[slot]))
		var name_label := Kit.text(shown, 19)
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
	pill.custom_minimum_size.x = 230
	right.add_child(pill)
	var steps := DuelModel.steps(view, index)
	right.add_child(Kit.dots_within(steps.x, steps.y, right.custom_minimum_size.x - 10.0))
	var count := Kit.text(PlayerCopy.DUEL_STEPS % [steps.x, steps.y], 19, UiTokens.SOFT)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(count)
	var label := Kit.text(PlayerCopy.DUEL_TIME_SO_FAR, 18, UiTokens.SOFT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(label)
	var time := Kit.text(DuelModel.time_text(DuelModel.ticks(view, index)), 50 if not compact else 42, UiTokens.CREAM, true)
	time.name = "DuelTime%d" % index
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(time)
	return card

func _render_card() -> void:
	Kit.clear(_card)
	var own: Dictionary = view.sides[view.mine]
	var mine_now := DuelModel.your_turn(view, me)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(Kit.pips(Vector2(56, 66), true))
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(words)
	var partner := _partner_name()
	if own.finished:
		words.add_child(Kit.text(PlayerCopy.DUEL_FINISHED, 40, UiTokens.CREAM, true))
		words.add_child(Kit.wrapped(PlayerCopy.DUEL_CHECKING_LINE if view.kind == "friend" else "", 19))
	elif mine_now:
		words.add_child(Kit.text(PlayerCopy.DUEL_YOUR_TURN_TITLE, 46 if not compact else 38, UiTokens.CREAM, true))
		words.add_child(Kit.wrapped(PlayerCopy.DUEL_PARTNER_LEFT_PATH % partner if own.steps > 0 else PlayerCopy.DUEL_FIRST_TURN, 20))
	else:
		words.add_child(Kit.text(PlayerCopy.DUEL_WAITING_TITLE % partner, 38, UiTokens.CREAM, true))
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

func _partner_name() -> String:
	var own: Dictionary = view.sides[view.mine]
	for id: Variant in own.members:
		if id != null and id != me and name_of.is_valid(): return str(name_of.call(id))
	return PlayerCopy.DUEL_PARTNER

func _chapter_title() -> String:
	var key := str(view.get("chapter", ""))
	return RoomChapterTitle.title(key, str(Registry.descriptor(key).get("title", key)))

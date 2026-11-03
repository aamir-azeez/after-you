extends RefCounted
## The public duel cards (boards 3, 4 and 6), each a shared in-game pop-up
## (presentation/in_game_modal.gd) over a duel page's root:
## - join(): "Join beside Kite?", "Take a pair spot?" or "Join with Maya?",
##   with the duel's seats as they will be once you're in (public_seats.gd) and
##   what happens next; Not now and Join and play.
## - first_time(): the short yes or no before the list, with the one Show my
##   name switch (the leaderboard name choice, shared) right there.
## - stranger(): a player you don't know, from their pip on the duel page: who
##   they are to you, the faces card (presentation/end_reactions.gd, the same
##   one every turn's end uses), Report and Block, and Add friend once the duel
##   is over.
## - block(): what blocking does: leaving the duel when it's your partner.
## - report(): the six report reasons, as the community rules list them.
## The flow (public_duels_flow.gd) does every request; a card only says what
## was tapped. Each card closes itself before its action runs.
const Modal = preload("res://presentation/in_game_modal.gd")
const Kit = preload("res://presentation/duels/duel_kit.gd")
const Seats = preload("res://presentation/duels/public_seats.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const SafetyScreen = preload("res://presentation/safety_screen.gd")
const EndReactions = preload("res://presentation/end_reactions.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")
const FACES_ICON = preload("res://assets/ui/social/users.svg")
const NAME_ICON = preload("res://assets/ui/social/user.svg")
const FLAG_ICON = preload("res://assets/ui/room/flag.svg")
const PLAY_ICON = preload("res://assets/ui/social/arrow-right.svg")
const INFO_ICON = preload("res://assets/ui/social/info.svg")
const WIDE := 620.0

## The join card for `row` taking `seat` (0 to 3) as `joining` ("alone" or
## "party"). `names`: {title (the chapter), partner (your party partner's name)}.
## confirm() runs after the card closes.
static func join(root: Control, row: Dictionary, seat: int, joining: String, names: Dictionary, confirm: Callable) -> Control:
	var side := seat / 2
	var other_slot := 1 - seat % 2
	var sides := Seats.row_seats(row)
	var beside: Dictionary = sides[side].seats[other_slot]
	var party := joining == "party"
	var title := ""
	var line := ""
	var points: Array = []
	var chapter := str(names.get("title", ""))
	var partner := str(names.get("partner", ""))
	if party:
		var rival := _pair_name(sides[1 - side].seats)
		title = PlayerCopy.PUBLIC_JOIN_PARTY_TITLE % partner
		line = PlayerCopy.PUBLIC_JOIN_PARTY_LINE % [chapter, partner, rival]
		points.append([INFO_ICON, PlayerCopy.PUBLIC_JOIN_PARTY_STRAIGHT % partner])
		var open_beside := _lone_open(sides[1 - side].seats)
		if not open_beside.is_empty(): points.append([INFO_ICON, PlayerCopy.PUBLIC_JOIN_PARTY_OPEN % open_beside])
	elif not beside.open:
		var who := str(beside.name)
		var played: int = row.sides[side].steps
		title = PlayerCopy.PUBLIC_JOIN_BESIDE_TITLE % who
		line = PlayerCopy.PUBLIC_JOIN_BESIDE_NEXT % [chapter, who] if played == 1 else PlayerCopy.PUBLIC_JOIN_BESIDE_LINE % [chapter, who]
		points.append([FACES_ICON, PlayerCopy.PUBLIC_JOIN_BESIDE_PAIR % who])
		points.append([NAME_ICON, PlayerCopy.PUBLIC_JOIN_BESIDE_FACES % who])
	else:
		title = PlayerCopy.PUBLIC_JOIN_PAIR_TITLE
		line = PlayerCopy.PUBLIC_JOIN_PAIR_LINE % chapter
		points.append([PLAY_ICON, PlayerCopy.PUBLIC_JOIN_PAIR_FIRST])
		points.append([INFO_ICON, PlayerCopy.PUBLIC_JOIN_PAIR_WAITS])
	# The seats as they will be: you (and your partner) where the join puts you.
	var you := {"open": false, "you": true, "name": PlayerCopy.DUEL_YOU, "look": {}}
	if party:
		sides[side].seats = [you, {"open": false, "you": false, "name": partner, "look": names.get("partner_look", {})}]
	else:
		sides[side].seats[seat % 2] = you
	var modal := Modal.open(root, "PublicJoinCard", title)
	modal.widen(WIDE)
	modal.label(line, 18).add_theme_color_override("font_color", UiTokens.SOFT)
	var preview := Seats.duel(sides, 0, 40.0)
	preview.alignment = BoxContainer.ALIGNMENT_BEGIN
	modal.content.add_child(preview)
	for point: Array in points: modal.content.add_child(_point(point[0], point[1]))
	var go: Button = modal.add_actions(PlayerCopy.PUBLIC_JOIN_AND_PLAY, func() -> void:
		modal.close(false)
		confirm.call(), PlayerCopy.DUELS_NOT_NOW)
	go.name = "PublicJoinConfirm"
	OfflineHold.hold(go)
	go.grab_focus()
	return modal

## The first time the list opens with the switch off (board 6.2). `show_name`: the
## name switch as it is now. confirm(show_name) runs after the card closes.
static func first_time(root: Control, show_name: bool, confirm: Callable) -> Control:
	var modal := Modal.open(root, "PublicFirstTime", PlayerCopy.PUBLIC_FIRST_TITLE)
	modal.widen(WIDE)
	modal.label(PlayerCopy.PUBLIC_FIRST_LINE, 18).add_theme_color_override("font_color", UiTokens.SOFT)
	modal.content.add_child(_point(FACES_ICON, PlayerCopy.PUBLIC_FIRST_FACES))
	modal.content.add_child(_point(NAME_ICON, PlayerCopy.PUBLIC_FIRST_NAME))
	modal.content.add_child(_point(FLAG_ICON, PlayerCopy.PUBLIC_FIRST_REPORT))
	var row := Kit.panel("PublicShowName", Color("163f3b"), Kit.PANEL_EDGE, 12, 10.0)
	var line := HBoxContainer.new()
	row.add_child(line)
	var words := Kit.text(PlayerCopy.PUBLIC_FIRST_SHOW_NAME, 18, UiTokens.CREAM, true)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(words)
	var toggle := CheckButton.new()
	toggle.name = "PublicShowNameSwitch"
	toggle.button_pressed = show_name
	toggle.accessibility_name = PlayerCopy.PUBLIC_FIRST_SHOW_NAME
	line.add_child(toggle)
	modal.content.add_child(row)
	var go: Button = modal.add_actions(PlayerCopy.PUBLIC_TURN_ON, func() -> void:
		var named := toggle.button_pressed
		modal.close(false)
		confirm.call(named), PlayerCopy.DUELS_NOT_NOW)
	go.name = "PublicTurnOn"
	OfflineHold.hold(go)
	go.grab_focus()
	return modal

## A stranger's card (board 6.3). `who`: {name, partner (your own partner), color
## ("peach" or "mint"), look, over (the duel ended), friend_sent}. `actions`:
## {report, block, befriend, pick(face)} callables; each runs after the card closes,
## except pick, which keeps the face for your next turn in the duel's room.
static func stranger(root: Control, who: Dictionary, settings: Dictionary, actions: Dictionary) -> Control:
	var modal := Modal.open(root, "PublicStrangerCard", str(who.get("name", "")), PlayerCopy.PUBLIC_CARD_PARTNER if who.get("partner", false) else PlayerCopy.PUBLIC_CARD_OTHER)
	modal.widen(520.0)
	var pip := Kit.pip(Vector2(44, 52), Kit.FIRST_PIP if who.get("color", "peach") == "peach" else Kit.SECOND_PIP, false, who.get("look", {}))
	modal.header.add_child(pip)
	modal.header.move_child(pip, 0)
	# The faces card every turn's end uses: a face picked here goes with your next turn in this duel.
	var faces := EndReactions.attach(modal.content, {"pick": true, "run": "public-duel:" + str(who.get("duel_id", "")), "color": "peach" if who.get("color", "peach") == "mint" else "mint",
		"settings": settings, "on_pick": actions.get("pick", Callable())})
	if faces != null:
		faces.name = "PublicStrangerFaces"
		# The faces grid shows open, as the card is drawn (board 6.3); it closes with the card.
		if faces.has_method("open_faces"): faces.call_deferred("open_faces")
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	modal.content.add_child(buttons)
	var add := func(node_name: String, label: String, key: String) -> void:
		var run: Variant = actions.get(key)
		if not run is Callable or not (run as Callable).is_valid(): return
		var button := Kit.button(label, Callable(), false, 52)
		button.name = node_name
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void:
			modal.close(false)
			(run as Callable).call())
		OfflineHold.hold(button)
		buttons.add_child(button)
	add.call("PublicReport", PlayerCopy.PUBLIC_REPORT, "report")
	add.call("PublicBlock", PlayerCopy.PUBLIC_BLOCK, "block")
	if who.get("over", false) and not who.get("friend_sent", false): add.call("PublicAddFriend", PlayerCopy.PUBLIC_ADD_FRIEND, "befriend")
	modal.refresh_focus_order()
	return modal

## What a block does (board 6.4): `partner` true leaves the duel. confirm() runs after the card closes.
static func block(root: Control, name: String, partner: bool, confirm: Callable) -> Control:
	var modal := Modal.open(root, "PublicBlockCard", PlayerCopy.PUBLIC_BLOCK_TITLE % name)
	modal.widen(WIDE)
	modal.label(PlayerCopy.PUBLIC_BLOCK_LINE % [name, name], 18).add_theme_color_override("font_color", UiTokens.SOFT)
	if partner:
		modal.content.add_child(_point(INFO_ICON, PlayerCopy.PUBLIC_BLOCK_PARTNER % name))
		modal.content.add_child(_point(INFO_ICON, PlayerCopy.PUBLIC_BLOCK_PAID))
	else:
		modal.content.add_child(_point(INFO_ICON, PlayerCopy.PUBLIC_BLOCK_OTHER % name))
	modal.content.add_child(_point(INFO_ICON, PlayerCopy.PUBLIC_BLOCK_UNDO))
	var go: Button = modal.add_actions(PlayerCopy.PUBLIC_BLOCK_LEAVE if partner else PlayerCopy.PUBLIC_BLOCK, func() -> void:
		modal.close(false)
		confirm.call(), PlayerCopy.DUELS_NOT_NOW)
	go.name = "PublicBlockConfirm"
	OfflineHold.hold(go)
	return modal

## The report reasons for `name`; confirm(reason) runs after the card closes.
static func report(root: Control, name: String, confirm: Callable) -> Control:
	var modal := Modal.open(root, "PublicReportCard", PlayerCopy.PUBLIC_REPORT_TITLE % name)
	modal.widen(WIDE)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	modal.content.add_child(grid)
	for reason: Array in SafetyScreen.REASONS:
		var button := Kit.button(str(reason[0]), Callable(), false, 50)
		button.name = "Reason_" + str(reason[1])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var code := str(reason[1])
		button.pressed.connect(func() -> void:
			modal.close(false)
			confirm.call(code))
		grid.add_child(button)
	modal.refresh_focus_order()
	return modal

## One line with its small icon.
static func _point(icon: Texture2D, words: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var mark := TextureRect.new()
	mark.texture = icon
	mark.modulate = UiTokens.SOFT
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(20, 20)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(mark)
	var label := Kit.wrapped(words, 17, UiTokens.CREAM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	return line

## The other pair's words in a join line: "Kite's pair", or "the other pair" when nobody there shows a name.
static func _pair_name(seats: Array) -> String:
	for held: Dictionary in seats:
		if not held.open and str(held.name) != PlayerCopy.PUBLIC_A_PLAYER: return PlayerCopy.PUBLIC_PAIR_OF % held.name
	return PlayerCopy.PUBLIC_THE_OTHER_PAIR

## The named player whose partner seat is open on a pair, or "".
static func _lone_open(seats: Array) -> String:
	if seats.size() != 2 or seats[0].open == seats[1].open: return ""
	var taken: Dictionary = seats[1] if seats[0].open else seats[0]
	return str(taken.name)

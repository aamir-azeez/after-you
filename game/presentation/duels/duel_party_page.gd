extends "res://presentation/duels/duel_page_base.gd"
## Your duel party (the owner's party board): exactly two friends. You and a
## place for your friend ("1 of 2"), the room boost line explaining that each
## Full Journey member adds 10%, invites waiting for you with Say yes and Not
## now, and your friends list to ask from (friends only). Leave party empties
## the place. Requests go through the flow (duels_flow.gd), which hands the
## lobby back through show_party().
const BusyTapGate = preload("res://presentation/busy_tap_gate.gd")

## "invite", "accept", "dismiss", "cancel" or "leave", with the friend's id where it has one.
signal party_action(action: String, friend: String, control: Control)

var name_of: Callable
## Accepted friends: [{id, name}].
var friends: Array = []
## Whether this build names Full Journey (services/pollen_surfaces.gd).
var show_boost := true
var party: Dictionary = {}
var _top: Control
var _list: VBoxContainer
var _gate: BusyTapGate

func page_name() -> String: return "DuelParty"
func title_text() -> String: return PlayerCopy.DUELS_PARTY_TITLE
func subtitle_text() -> String: return PlayerCopy.DUELS_PARTY_SUBTITLE

func opened() -> void:
	_gate = BusyTapGate.new(root)

func show_party(next: Dictionary) -> void:
	party = next
	if is_instance_valid(_list): _render()

func set_friends(next: Array) -> void:
	friends = next
	if is_instance_valid(_list): _render()

func tap(control: Control, run: Callable) -> void:
	await _gate.tap(control, "...", Callable(), run, alive)

func _build() -> void:
	_top = Kit.panel("DuelPartyCard", Kit.PANEL_FILL, Kit.PANEL_EDGE, 20, 20.0)
	body.add_child(_top)
	var lower := Kit.panel("DuelPartyFriends")
	lower.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(lower)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	lower.add_child(column)
	column.add_child(Kit.text(PlayerCopy.DUELS_PARTY_INVITE, 28, UiTokens.CREAM, true))
	column.add_child(Kit.text(PlayerCopy.DUELS_PARTY_FRIENDS_ONLY, 17, UiTokens.SOFT))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ThemeRules.touch_scroll(scroll)
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "DuelPartyList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	_render()

func _render() -> void:
	_render_top()
	Kit.clear(_list)
	var partner: Variant = party.get("partner") if party.get("intact", false) else null
	var invites: Array = party.get("invites_in", [])
	for from: Variant in invites:
		_list.add_child(_row(str(from), PlayerCopy.DUELS_PARTY_INVITED % _name(from), [[PlayerCopy.DUELS_PARTY_SAY_YES, "accept", true], [PlayerCopy.DUELS_NOT_NOW, "dismiss", false]]))
	var shown := 0
	for friend: Dictionary in friends:
		if friend.id == partner or friend.id in invites: continue
		var asked: bool = party.get("invite_out") == friend.id
		_list.add_child(_row(friend.id, friend.name, [[PlayerCopy.DUELS_PARTY_ASKED, "cancel", false]] if asked else [[PlayerCopy.DUELS_PARTY_ASK, "invite", true]]))
		shown += 1
	if shown == 0 and invites.is_empty(): _list.add_child(Kit.wrapped(PlayerCopy.DUELS_PARTY_NO_FRIENDS, 18))

func _render_top() -> void:
	Kit.clear(_top)
	var partner: Variant = party.get("partner") if party.get("intact", false) else null
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	_top.add_child(row)
	row.add_child(_slot(PlayerCopy.DUEL_YOU, Kit.FIRST_PIP, true, true))
	row.add_child(_slot(_name(partner) if partner != null else PlayerCopy.DUELS_PARTY_EMPTY_SLOT, Kit.SECOND_PIP, false, partner != null))
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 6)
	row.add_child(words)
	words.add_child(Kit.text(PlayerCopy.DUELS_PARTY_COUNT % (2 if partner != null else 1), 34, UiTokens.CREAM, true))
	if show_boost: words.add_child(Kit.wrapped(PlayerCopy.DUELS_PARTY_BOOST_EXPLAIN, 19))
	if partner != null:
		var leave := Kit.button(PlayerCopy.DUELS_PARTY_LEAVE, Callable(), false, 52)
		leave.name = "DuelPartyLeave"
		leave.custom_minimum_size.x = 220
		leave.pressed.connect(func(): party_action.emit("leave", "", leave))
		row.add_child(leave)

func _slot(label: String, color: Color, own: bool, filled: bool) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	var pip := Kit.pip(Vector2(84, 98), color, own)
	if not filled: pip.modulate = Color(1, 1, 1, 0.3)
	column.add_child(pip)
	var name_label := Kit.text(label, 20, UiTokens.CREAM if filled else UiTokens.MUTED)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	return column

## A friend or an invite: pip, words and buttons [[label, action, primary]].
func _row(id: String, words: String, buttons: Array) -> Control:
	var card := Kit.panel("Friend_" + id.left(6), Kit.CARD_FILL, Kit.PANEL_EDGE, 14, 10.0)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	card.add_child(line)
	line.add_child(Kit.pip(Vector2(40, 48), Kit.SECOND_PIP))
	var label := Kit.text(words, 20)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(label)
	for item: Array in buttons:
		var button := Kit.button(str(item[0]), Callable(), bool(item[2]), 48)
		button.custom_minimum_size.x = 150
		var action := str(item[1])
		button.pressed.connect(func(): party_action.emit(action, id, button))
		line.add_child(button)
	return card

func _name(id: Variant) -> String:
	return str(name_of.call(id)) if id != null and name_of.is_valid() else ""

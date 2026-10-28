extends "res://presentation/duels/duel_page_base.gd"
## Start a duel: pick a friend, whose pair you challenge, and a chapter. Only
## chapters open to you are offered (services/chapter_unlocks.gd open(), Full
## Journey included); the other pair checks theirs before they accept. The
## server answers when the friend has no duel partner yet. Send challenge goes
## through the flow (duels_flow.gd) with one idempotency key per tap.
const BusyTapGate = preload("res://presentation/busy_tap_gate.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")

signal send_requested(friend: String, chapter_key: String, control: Control)

## Accepted friends who are not your partner: [{id, name}].
var friends: Array = []
## Chapter keys open to you, in the Chapters order.
var chapters: Array = []
var _friend := ""
var _chapter := ""
var _friend_list: VBoxContainer
var _chapter_list: VBoxContainer
var _send: Button
var _gate: BusyTapGate

func page_name() -> String: return "DuelChallenge"
func title_text() -> String: return PlayerCopy.DUELS_START

func opened() -> void:
	_gate = BusyTapGate.new(root)

func header_action() -> Control:
	_send = Kit.button(PlayerCopy.DUELS_SEND, Callable(), true, 56)
	_send.name = "DuelSend"
	_send.custom_minimum_size.x = 260
	_send.disabled = true
	_send.pressed.connect(func(): send_requested.emit(_friend, _chapter, _send))
	return _send

func tap(control: Control, run: Callable) -> void:
	await _gate.tap(control, "...", Callable(), run, alive)

func _build() -> void:
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	body.add_child(columns)
	_friend_list = _column(columns, PlayerCopy.DUELS_PICK_PAIR, "DuelPickPair", 0.8)
	_chapter_list = _column(columns, PlayerCopy.DUELS_PICK_CHAPTER, "DuelPickChapter", 1.2)
	_render()

func _column(parent: Control, heading: String, node_name: String, ratio: float) -> VBoxContainer:
	var box := Kit.panel(node_name)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_stretch_ratio = ratio
	parent.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	box.add_child(column)
	column.add_child(Kit.text(heading, 28, UiTokens.CREAM, true))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ThemeRules.touch_scroll(scroll)
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	return list

func _render() -> void:
	_render_friends()
	_render_chapters()

func _render_friends() -> void:
	Kit.clear(_friend_list)
	for friend: Dictionary in friends:
		_friend_list.add_child(_choice("Pair_" + str(friend.id).left(6), str(friend.name), friend.id == _friend, func(): _pick_friend(friend.id), Kit.pips(Vector2(30, 40))))
	if friends.is_empty(): _friend_list.add_child(Kit.wrapped(PlayerCopy.DUELS_NO_PAIRS, 18))
	_update_send()

func _render_chapters() -> void:
	Kit.clear(_chapter_list)
	for key: String in chapters:
		var title := RoomChapterTitle.title(key, str(Registry.descriptor(key).get("title", key)))
		_chapter_list.add_child(_choice("Chapter_" + key.replace("@", "_"), title, key == _chapter, func(): _pick_chapter(key), Kit.picture(key, Vector2(112, 63), 10)))
	_update_send()

func _update_send() -> void:
	if is_instance_valid(_send): _send.disabled = _friend.is_empty() or _chapter.is_empty()

func _pick_friend(id: String) -> void:
	_friend = id
	_render_friends()

func _pick_chapter(key: String) -> void:
	_chapter = key
	_render_chapters()

func _choice(node_name: String, label: String, chosen: bool, action: Callable, art: Control) -> Button:
	var button := Button.new()
	button.name = node_name
	button.custom_minimum_size = Vector2(0, 76)
	button.accessibility_name = label
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var fill := UiTokens.MINT if chosen else Kit.CARD_FILL
		button.add_theme_stylebox_override(state, ThemeRules.rounded(fill.lightened(0.05) if state.begins_with("hover") and not chosen else fill, 14, Color.TRANSPARENT if chosen else Kit.PANEL_EDGE))
	button.add_theme_stylebox_override("focus", ThemeRules.rounded(Color.TRANSPARENT, 14, UiTokens.CREAM))
	button.pressed.connect(action)
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 8
	line.offset_right = -8
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(line)
	line.add_child(art)
	var text := Kit.text(label, 20, UiTokens.INK if chosen else UiTokens.CREAM, true)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(text)
	return button

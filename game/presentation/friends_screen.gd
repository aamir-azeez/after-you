extends CanvasLayer
const ThemeRules = preload("res://presentation/control_theme.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const FriendsClient = preload("res://services/friends_client.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const PlayerAvatar = preload("res://presentation/player_avatar.gd")
const BACK_ICON = preload("res://assets/ui/social/arrow-left.svg")
const REFRESH_ICON = preload("res://assets/ui/social/arrows-clockwise.svg")
const COPY_ICON = preload("res://assets/ui/social/copy.svg")
const REMOVE_ICON = preload("res://assets/ui/social/minus-circle.svg")
const SHARE_ICON = preload("res://assets/ui/social/share-network.svg")
const ADD_ICON = preload("res://assets/ui/social/plus.svg")
const USERS_ICON = preload("res://assets/ui/social/users.svg")
const PENCIL_ICON = preload("res://assets/ui/social/pencil-simple.svg")
const CHECK_ICON = preload("res://assets/ui/check.svg")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const ShareCodes = preload("res://services/share_codes.gd")
const InviteShare = preload("res://services/invite_share.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const CREAM := Color("eceddb")
const MUTED := Color("afc6be")
const INK := Color("123936")
## Delay before an invite-link confirmation accepts a press.
const INVITE_CONFIRM_ARM_SEC := 0.4
## How long the icon-only Copy shows a tick after copying.
const COPY_FEEDBACK_SEC := 1.2
## The top row (friends | current room) and the bottom code row share one split, so
## the code columns line up with the panels' content edges above them.
const SPLIT_GAP := 16
const SPLIT_RATIO := 1.35
## Gap between the code columns once they stack.
const UTILITY_GAP_STACKED := 24
## Panel and field fills, shared with the clipped-code fades that blend into them.
const CARD_FILL := Color("123936")
const FIELD_FILL := Color("14312f")
## Muted code text, and its slightly brighter hover/press.
const CODE_INK := MUTED
const CODE_INK_ACTIVE := Color("d3e2dc")
## Minimum touch height of a friend row's code, which stays one text line tall.
const CODE_HIT_HEIGHT := 44.0
signal hosting_view_ready(events: Array)
signal closed
signal host_requested
signal open_requested
signal join_requested(descriptor: Dictionary)
var client: RefCounted
var event_client: RefCounted
var shareable_room: Dictionary = {}
var room_title := ""
var room_status := ""
var openable_room := false
var nickname_store: RefCounted
var _root: Control
var _margin: MarginContainer
var _content: VBoxContainer
var _context: Dictionary = {}
var _alive := true
var _foreground := true
var _busy := false
var _message := ""
var _remove: Dictionary = {}
var _code := ""
var _presence_signature := ""
var _next_local_refresh := 0
var _refresh_button: Button
var _countdown: Label
var _join_buttons: Array[Button] = []
var notification_transport: Node
var _notify_buttons: Array[Button] = []
var _compact := false
var _stacked := false
var _narrow := false
var _safe_width := 0.0
# Bottom code row (see _fit_utilities): the split container, its two slots, and
# each slot's single-line row (null when that slot has none).
var _utility_columns: BoxContainer
var _utility_slots: Array[MarginContainer] = []
var _utility_rows: Array = []
var _title: Label
var _heading_font: FontVariation
var _scroll: ScrollContainer
var _nicknames: RefCounted
var _social_events: Array[Dictionary] = []
var _notification_preferences: Dictionary = {}
var _events_supported := false
var _event_ack_pending := false
var _modal: Control
## One validated invite-link friend ID waiting for confirmation; never sent without a tap.
var _link_id := ""
## Clipboard and system share outputs; tests replace them.
var clipboard_copy: Callable = func(text: String) -> void: DisplayServer.clipboard_set(text)
var share_text: Callable = func(text: String) -> bool: return InviteShare.android_share(text)

## A friend row's code: one line of text that copies on tap. Taps land across a
## CODE_HIT_HEIGHT band from its top, so the row keeps its height.
class CodeButton extends Button:
	var hit_height := 44.0
	func _has_point(point: Vector2) -> bool:
		return Rect2(Vector2.ZERO, Vector2(size.x, maxf(size.y, hit_height))).has_point(point)

func _ready() -> void:
	layer = 50
	_context = client.context()
	_nicknames = nickname_store if nickname_store != null else FriendNicknames.new()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = Theme.new()
	var body := FontVariation.new()
	body.base_font = preload("res://assets/fonts/nunito.ttf")
	body.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):600.0}
	_root.theme.default_font = body
	_heading_font = FontVariation.new()
	_heading_font.base_font = preload("res://assets/fonts/fredoka.ttf")
	_heading_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):600.0}
	_root.theme.default_font_size = 20
	_root.theme.set_color("font_color","Label",Color("eceddb"))
	ThemeRules.install_buttons(_root.theme)
	add_child(_root)
	var background := ColorRect.new()
	background.color = Color("123936")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(background)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation",18)
	_margin.add_child(layout)
	var refresh_row := HBoxContainer.new()
	refresh_row.add_theme_constant_override("separation",14)
	layout.add_child(refresh_row)
	_icon_button(BACK_ICON,"Back",close,true,refresh_row)
	_title = _label("Friends",54,refresh_row)
	_title.add_theme_font_override("font",_heading_font)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_countdown = Label.new()
	_countdown.add_theme_color_override("font_color",MUTED)
	_refresh_button = _icon_button(REFRESH_ICON,"Refresh",func(): _refresh(true),true,refresh_row)
	refresh_row.add_child(_countdown)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	# Cards are panels, which stop a drag by default; this lets the page scroll
	# from anywhere and covers the nested friend list as it is rebuilt.
	ThemeRules.touch_scroll(_scroll)
	layout.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Fill the page height so the friend list, not empty space, takes any spare room.
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation",18)
	_scroll.add_child(_content)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_render()
	await _refresh()

func _layout() -> void:
	if not is_instance_valid(_margin): return
	var rect := get_viewport().get_visible_rect()
	var safe := rect
	if OS.has_feature("android"): safe = SafeArea.viewport_rect(Rect2(DisplayServer.get_display_safe_area()),get_viewport().get_screen_transform(),rect)
	var compact := safe.size.x < 1100
	var stacked := safe.size.x < 900
	var narrow := safe.size.x < 560
	var changed := compact != _compact or stacked != _stacked or narrow != _narrow
	_compact = compact
	_stacked = stacked
	_narrow = narrow
	var side := maxi(20,int((safe.size.x-1192)*0.5))
	_safe_width = safe.size.x - side * 2
	_margin.add_theme_constant_override("margin_left",int(safe.position.x)+side)
	_margin.add_theme_constant_override("margin_right",int(rect.end.x-safe.end.x)+side)
	_margin.add_theme_constant_override("margin_top",int(safe.position.y)+(16 if compact else 20))
	_margin.add_theme_constant_override("margin_bottom",int(rect.end.y-safe.end.y)+(16 if compact else 20))
	_title.add_theme_font_size_override("font_size",38 if compact else 54)
	_countdown.add_theme_font_size_override("font_size",16 if compact else 20)
	_countdown.visible = not narrow
	if changed: _render()
	else: _fit_utilities()

func _current() -> bool:
	return _alive and is_inside_tree() and not _context.is_empty() and client.context() == _context

func _process(_delta: float) -> void:
	if not _current(): close(); return
	if _foreground and not _busy and not client.busy and client.refresh_due(): _refresh()
	if _foreground and not _busy and Time.get_ticks_msec() >= _next_local_refresh:
		_next_local_refresh = Time.get_ticks_msec() + 500
		if _presence_key(client.view()) != _presence_signature: _render()
		_update_countdowns()
	if not _link_id.is_empty(): _offer_link()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT]: _foreground = false
	elif what in [NOTIFICATION_APPLICATION_RESUMED,NOTIFICATION_APPLICATION_FOCUS_IN]: _foreground = true
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST: close()
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_RESUMED,NOTIFICATION_APPLICATION_FOCUS_IN]: _update_countdowns()

func _update_countdowns() -> void:
	if not is_instance_valid(_refresh_button): return
	var manual_wait := ceili(float(client.refresh_wait_ms(true))/1000.0)
	var auto_wait := ceili(float(client.refresh_wait_ms())/1000.0)
	_refresh_button.tooltip_text = "Refresh" if manual_wait == 0 else "Refresh (%ds)" % manual_wait
	_refresh_button.disabled = not _foreground or _busy or client.busy or manual_wait > 0
	_countdown.text = "Refreshing…" if _busy and client.busy else "Auto-refresh in %ds" % auto_wait
	var join_wait := ceili(float(client.join_wait_ms())/1000.0)
	for button: Button in _join_buttons:
		if not is_instance_valid(button): continue
		var action: String = button.get_meta("room_action")
		button.text = action if join_wait == 0 else "%s (%ds)" % [action,join_wait]
		button.disabled = not _foreground or _busy or client.busy or join_wait > 0
	for button: Button in _notify_buttons:
		if is_instance_valid(button): button.disabled = not _foreground or _busy or event_client == null

func _presence_key(page: Dictionary) -> String:
	var values := []
	for peer: Dictionary in page.get("friends",[]): values.append([peer.player_id,peer.online,peer.join_available])
	return JSON.stringify(values)

func _label(value: String, size: int = 20, parent: Node = null) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",size)
	(parent if parent != null else _content).add_child(label)
	return label

func _button(value: String, action: Callable, enabled: bool = true, parent: Node = null) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(0,52)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.disabled = not enabled
	button.pressed.connect(action)
	button.add_theme_constant_override("outline_size",0)
	button.add_theme_constant_override("icon_max_width",28)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	for state: String in ["normal","hover","pressed","hover_pressed","focus"]:
		button.add_theme_color_override("icon_"+state+"_color",INK)
	button.add_theme_color_override("icon_disabled_color",Color("9aaaa3"))
	(parent if parent != null else _content).add_child(button)
	return button

func _secondary(button: Button, quiet: bool = false) -> void:
	for state: String in ["normal","hover","pressed","hover_pressed","disabled"]:
		var color := Color.TRANSPARENT if quiet else Color("173e3a")
		if state in ["hover","pressed","hover_pressed"]: color = Color("2b5550")
		var border := Color.TRANSPARENT if quiet else Color("718f86")
		button.add_theme_stylebox_override(state,ThemeRules.rounded(color,14,border))
		var ink := Color("78938a") if state == "disabled" else CREAM
		button.add_theme_color_override("font_color" if state == "normal" else "font_"+state+"_color",ink)
		button.add_theme_color_override("icon_"+state+"_color",ink)
	button.add_theme_color_override("icon_focus_color",CREAM)
	button.add_theme_color_override("font_focus_color",CREAM)

func _icon_button(icon: Texture2D, description: String, action: Callable, enabled: bool, parent: Node) -> Button:
	var button := _button("",action,enabled,parent)
	button.icon = icon
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	# Mipmapped icons stay crisp when the window is scaled below its design size.
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	button.tooltip_text = description
	button.accessibility_name = description
	button.custom_minimum_size = Vector2(48,48)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_secondary(button,true)
	if description in ["Back", "Decline", "Cancel request", "Remove friend"]:
		ThemeRules.danger(button,icon)
	return button

func _pad_labeled_icon(button: Button) -> void:
	ThemeRules.inset_button(button)
	ThemeRules.center_icon_label(button)

func _card(parent: Node, inset: int = 20) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := ThemeRules.rounded(CARD_FILL,16,Color("466e63"))
	style.content_margin_left = inset
	style.content_margin_right = inset
	style.content_margin_top = inset
	style.content_margin_bottom = inset
	panel.add_theme_stylebox_override("panel",style)
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",12)
	panel.add_child(content)
	return content

func _field_style(field: LineEdit) -> void:
	var style := ThemeRules.rounded(FIELD_FILL,12,Color("52776d"))
	style.content_margin_left = 16
	style.content_margin_right = 16
	field.add_theme_stylebox_override("normal",style)
	field.add_theme_stylebox_override("read_only",style)
	field.add_theme_stylebox_override("focus",ThemeRules.rounded(Color.TRANSPARENT,12,Color("a6d9c4")))
	field.add_theme_color_override("font_color",CREAM)
	field.add_theme_color_override("font_uneditable_color",CREAM)
	field.add_theme_color_override("font_placeholder_color",Color("8da69e"))
	field.add_theme_color_override("caret_color",CREAM)

func _render() -> void:
	if not is_instance_valid(_content): return
	var focus := get_viewport().gui_get_focus_owner()
	var restore_input := focus is LineEdit and focus.name == "FriendCode"
	var caret: int = focus.caret_column if restore_input else 0
	var selection_from: int = focus.get_selection_from_column() if restore_input else 0
	var selection_to: int = focus.get_selection_to_column() if restore_input else 0
	var scroll_position := _scroll.scroll_vertical
	_join_buttons.clear()
	_notify_buttons.clear()
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	if not _message.is_empty(): _label(_message)
	_add_hosting_events()
	if not _remove.is_empty():
		var confirmation := _card(_content,24)
		confirmation.get_parent().size_flags_vertical = Control.SIZE_FILL
		_label("Remove friend?",28,confirmation)
		_label(str(_remove.player_id).substr(0,8),22,confirmation)
		var choices := HBoxContainer.new()
		choices.add_theme_constant_override("separation",12)
		confirmation.add_child(choices)
		_button("Remove",func(): _act("remove",_remove),not _busy,choices)
		_secondary(_button("Cancel",func(): _remove = {}; _render(),not _busy,choices))
		_update_countdowns()
		return
	var page: Dictionary = client.view()
	_presence_signature = _presence_key(page)
	var main := BoxContainer.new()
	main.name = "FriendsAndRoom"
	main.vertical = _stacked
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation",SPLIT_GAP)
	_content.add_child(main)
	var friends := _card(main,_friends_inset())
	friends.get_parent().size_flags_stretch_ratio = SPLIT_RATIO
	friends.get_parent().custom_minimum_size.y = 270 if _compact else 386
	_label("YOUR FRIENDS",18,friends).add_theme_color_override("font_color",MUTED)
	var friend_scroll := ScrollContainer.new()
	friend_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	friend_scroll.custom_minimum_size.y = 180 if _compact else 300
	friend_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	friend_scroll.follow_focus = true
	friends.add_child(friend_scroll)
	var friend_list := VBoxContainer.new()
	friend_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friend_list.add_theme_constant_override("separation",12)
	friend_scroll.add_child(friend_list)
	# Put available rooms before requests and the lower code utility panel.
	for joinable: bool in [true,false]:
		for peer: Dictionary in page.get("friends",[]):
			if peer.join_available != joinable: continue
			_friend_row(peer,friend_list)
	if page.get("friends",[]).is_empty():
		_label("No friends yet" if not page.is_empty() else "Refreshing…",22,friend_list).add_theme_color_override("font_color",MUTED)
	_room_panel(page,main)
	var utility := _card(_content,_utility_inset())
	utility.get_parent().name = "FriendCodeUtilities"
	utility.get_parent().size_flags_vertical = Control.SIZE_FILL
	# The slots carry the side padding (see _fit_utilities), so the panel has none.
	var utility_style := utility.get_parent().get_theme_stylebox("panel") as StyleBoxFlat
	utility_style.content_margin_left = 0
	utility_style.content_margin_right = 0
	var utilities := BoxContainer.new()
	utilities.name = "FriendCodeColumns"
	utilities.vertical = _stacked
	utilities.add_theme_constant_override("separation",UTILITY_GAP_STACKED if _stacked else SPLIT_GAP)
	utility.add_child(utilities)
	_utility_columns = utilities
	_utility_slots.clear()
	_utility_rows = [null,null]
	for ratio: float in [SPLIT_RATIO,1.0]:
		var slot := MarginContainer.new()
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.size_flags_stretch_ratio = ratio
		utilities.add_child(slot)
		_utility_slots.append(slot)
	_utility_slots[0].name = "OwnCodeSlot"
	_utility_slots[1].name = "AddFriendSlot"
	if not page.is_empty():
		var own_column := VBoxContainer.new()
		own_column.add_theme_constant_override("separation",10)
		_utility_slots[0].add_child(own_column)
		_label("Your friend code",20,own_column)
		var own_row := BoxContainer.new()
		own_row.name = "OwnFriendCodeRow"
		own_row.vertical = _narrow
		own_row.add_theme_constant_override("separation",8)
		own_column.add_child(own_row)
		_utility_rows[0] = own_row
		var own := LineEdit.new()
		own.name = "OwnFriendCode"
		own.text = ShareCodes.display(ShareCodes.FRIEND,page.friend_code)
		# Clips rather than grows; Copy and Share Invite give the full code. Read-only with
		# no caret or selection, so the start of the code always shows.
		own.editable = false
		own.selecting_enabled = false
		own.focus_mode = Control.FOCUS_NONE
		own.custom_minimum_size = Vector2(120,54)
		own.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		own.add_theme_font_size_override("font_size",18 if _compact else 21)
		_field_style(own)
		own_row.add_child(own)
		_code_fade(own,FIELD_FILL)
		var code_actions := HBoxContainer.new()
		code_actions.add_theme_constant_override("separation",8)
		own_row.add_child(code_actions)
		# Icon-only outlined Copy sits left of the cream Share Invite, on one line even when narrow.
		var copy_holder: Array[Button] = []
		var copy_code := _button("",func(): _copy_code(str(page.friend_code),copy_holder[0] if not copy_holder.is_empty() else null),true,code_actions)
		copy_holder.append(copy_code)
		copy_code.name = "CopyFriendCode"
		copy_code.tooltip_text = "Copy code"
		copy_code.accessibility_name = "Copy code"
		copy_code.icon = COPY_ICON
		copy_code.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		copy_code.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		copy_code.add_theme_constant_override("icon_max_width",24)
		copy_code.custom_minimum_size = Vector2(54,54)
		copy_code.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_secondary(copy_code)
		var share_code := _button(PlayerCopy.INVITE_LINK_SHARE,func(): _share_invite(str(page.friend_code)),true,code_actions)
		share_code.name = "ShareInviteLink"
		share_code.tooltip_text = PlayerCopy.INVITE_LINK_SHARE
		# The share icon drops in the tighter compact layout.
		if not _compact: share_code.icon = SHARE_ICON
		share_code.custom_minimum_size.y = 54
		share_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _narrow else Control.SIZE_FILL
		_pad_labeled_icon(share_code)
	var add_column := VBoxContainer.new()
	add_column.add_theme_constant_override("separation",10)
	_utility_slots[1].add_child(add_column)
	_label("Friend code",20,add_column)
	var add_row := BoxContainer.new()
	add_row.name = "AddFriendRow"
	add_row.vertical = _narrow
	add_row.add_theme_constant_override("separation",10)
	add_column.add_child(add_row)
	_utility_rows[1] = add_row
	var field := LineEdit.new()
	field.name = "FriendCode"
	field.placeholder_text = "Enter friend code"
	# Long enough for friend-<id> or a pasted invite link.
	field.max_length = ShareCodes.MAX_INPUT
	field.text = _code
	field.editable = not _busy
	field.custom_minimum_size = Vector2(120,54)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_theme_font_size_override("font_size",18 if _compact else 20)
	_field_style(field)
	field.text_changed.connect(func(value: String): _code = value)
	field.text_submitted.connect(func(_value: String): _act("add"))
	add_row.add_child(field)
	if restore_input and not _busy:
		field.grab_focus()
		field.caret_column = caret
		if selection_to > selection_from: field.select(selection_from,selection_to)
	var add := _button("Add friend",func(): _act("add"),not _busy and not _code.strip_edges().is_empty(),add_row)
	field.text_changed.connect(func(value: String): add.disabled = _busy or value.strip_edges().is_empty())
	add.icon = ADD_ICON
	_secondary(add)
	_pad_labeled_icon(add)
	add.custom_minimum_size.x = 156 if _compact else 176
	add.size_flags_horizontal = Control.SIZE_SHRINK_END
	_fit_utilities()
	_scroll.set_deferred("scroll_vertical",scroll_position)
	_update_countdowns()
	if not _social_events.is_empty() and not _event_ack_pending:
		_event_ack_pending = true
		_ack_visible_events.call_deferred()

func _friends_inset() -> int:
	return 16 if _compact else 18

func _room_inset() -> int:
	return 12 if _compact else 24

func _utility_inset() -> int:
	return 12 if _compact else 22

## Side by side, the code columns use the top row's split and each top panel's
## padding, so they line up with the friends and room content. They stack (and
## each row stacks) when a single line would not fit its share.
func _fit_utilities() -> void:
	if not is_instance_valid(_utility_columns) or _utility_slots.size() != 2 or _utility_slots.any(func(slot: MarginContainer) -> bool: return not is_instance_valid(slot)): return
	# Leave room for the page scrollbar.
	var available := _safe_width - 16.0
	var share := (available - SPLIT_GAP) / (SPLIT_RATIO + 1.0)
	var shares: Array[float] = [share * SPLIT_RATIO, share]
	var insets: Array[int] = [_friends_inset(), _room_inset()]
	var needs: Array[float] = []
	for slot: MarginContainer in _utility_slots:
		var need := 0.0
		for column: Control in slot.get_children():
			for child: Control in column.get_children():
				var row := child as BoxContainer
				need = maxf(need,_line_width(row) if row != null and row in _utility_rows else child.get_combined_minimum_size().x)
		needs.append(need)
	var side_by_side := not _stacked and needs[0] + insets[0] * 2 <= shares[0] and needs[1] + insets[1] * 2 <= shares[1]
	_utility_columns.vertical = not side_by_side
	_utility_columns.add_theme_constant_override("separation",SPLIT_GAP if side_by_side else UTILITY_GAP_STACKED)
	for index in range(2):
		var inset := insets[index] if side_by_side else _utility_inset()
		_utility_slots[index].add_theme_constant_override("margin_left",inset)
		_utility_slots[index].add_theme_constant_override("margin_right",inset)
		var row := _utility_rows[index] as BoxContainer
		if row == null or not is_instance_valid(row): continue
		var room := (shares[index] if side_by_side else available) - inset * 2
		row.vertical = _narrow or _line_width(row) > room

## Width a BoxContainer needs to lay its children out on one line.
func _line_width(box: BoxContainer) -> float:
	var width := 0.0
	for child: Control in box.get_children():
		width += child.get_combined_minimum_size().x
	return width + box.get_theme_constant("separation") * maxi(0,box.get_child_count() - 1)

func _room_panel(page: Dictionary, parent: Node) -> void:
	var room := _card(parent,_room_inset())
	room.add_theme_constant_override("separation",6 if _compact else 8)
	var has_room := not shareable_room.is_empty() or openable_room
	var heading := HBoxContainer.new()
	room.add_child(heading)
	var caption := _label("CURRENT ROOM",18,heading)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.add_theme_color_override("font_color",MUTED)
	var room_actions := HBoxContainer.new() if _compact and openable_room else null
	if room_actions != null: room_actions.add_theme_constant_override("separation",8)
	if has_room:
		var host := _button("Host a room",_host,not _busy and not client.busy,room_actions if room_actions != null else heading)
		host.add_theme_font_size_override("font_size",16)
		host.custom_minimum_size = Vector2(112,48)
		host.size_flags_horizontal = Control.SIZE_SHRINK_END
		_secondary(host,true)
	var title := _label(room_title if not room_title.is_empty() and has_room else "Current room" if has_room else "No current room",28 if _compact else 34,room)
	title.add_theme_font_override("font",_heading_font)
	if not has_room:
		_label("Choose a chapter to host, then share it with friends.",20,room).add_theme_color_override("font_color",MUTED)
	if has_room and not room_status.is_empty():
		var status := HBoxContainer.new()
		status.add_theme_constant_override("separation",12)
		room.add_child(status)
		var people := TextureRect.new()
		people.texture = USERS_ICON
		people.custom_minimum_size = Vector2(28,28)
		people.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		people.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		people.self_modulate = MUTED
		status.add_child(people)
		var detail := _label(room_status,20,status)
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.add_theme_color_override("font_color",MUTED)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 0 if _compact else 6
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room.add_child(spacer)
	if not has_room: _button("Host a room",_host,not _busy and not client.busy,room)
	if room_actions != null: room.add_child(room_actions)
	if openable_room:
		var return_button := _button("Return to room",_open,not _busy and not client.busy,room_actions if room_actions != null else room)
		if room_actions != null: room_actions.move_child(return_button,0)
	if not shareable_room.is_empty():
		if FriendsClient.same_room(page.get("shared_room"),shareable_room):
			_label("Shared with friends",20,room).add_theme_color_override("font_color",MUTED)
		else:
			var share := _button("Share current room",func(): _act("share"),not _busy,room)
			share.icon = SHARE_ICON
			_secondary(share)
			_pad_labeled_icon(share)
			var scope := _label("All friends",18,room)
			scope.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			scope.add_theme_color_override("font_color",MUTED)
	if page.get("shared_room") != null:
		var unshare := _button("Stop sharing room",func(): _act("unshare"),not _busy,room)
		_secondary(unshare)

func _friend_row(peer: Dictionary, parent: Node) -> void:
	var status := "Online" if peer.online else "Offline"
	if peer.status == "incoming": status = "Friend request"
	elif peer.status == "outgoing": status = "Request sent"
	var card := _card(parent,10 if _compact else 16)
	card.get_parent().size_flags_vertical = Control.SIZE_FILL
	card.get_parent().custom_minimum_size.y = 84 if _compact else 116
	var row := BoxContainer.new()
	row.vertical = _narrow
	row.add_theme_constant_override("separation",8 if _compact else 12)
	card.add_child(row)
	var avatar := TextureRect.new()
	avatar.texture = PlayerAvatar.texture_for(str(peer.player_id))
	avatar.custom_minimum_size = Vector2(48,48) if _compact else Vector2(64,64)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(avatar)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.add_theme_constant_override("separation",5)
	row.add_child(identity)
	var shown := _display_name(str(peer.player_id))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation",6)
	identity.add_child(name_row)
	var name_size := 20 if _compact else 24
	var name_label := _label(shown,name_size,name_row)
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	name_label.add_theme_font_override("font",_heading_font)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Size the name to its text (capped) so the pencil sits right beside it and a
	# long nickname is trimmed instead of pushing the row actions off screen.
	var name_width := _heading_font.get_string_size(shown,HORIZONTAL_ALIGNMENT_LEFT,-1,name_size).x + 4.0
	# A friend with a room shows Join and Notify together, leaving less room for the name.
	var both_actions: bool = peer.status == "accepted" and peer.join_available
	var name_cap := (72.0 if both_actions else 150.0) if _compact else (120.0 if both_actions else 230.0)
	name_label.custom_minimum_size.x = minf(name_width,name_cap)
	if peer.status == "accepted":
		var opener: Array[Control] = []
		var rename := _icon_button(PENCIL_ICON,"Edit nickname",func(): _edit_nickname(peer,opener[0] if not opener.is_empty() else null),not _busy,name_row)
		opener.append(rename)
		rename.accessibility_name = "Edit nickname for %s" % shown
		rename.add_theme_constant_override("icon_max_width",20)
	# The real friend code stays on its own line so a local nickname never hides
	# the identifier players share and compare.
	# Codes fade at a clipped end (names keep their ellipsis); a tap copies the full code.
	var code_button := CodeButton.new()
	code_button.name = "FriendRowCode"
	code_button.text = ShareCodes.display(ShareCodes.FRIEND,str(peer.player_id))
	code_button.hit_height = CODE_HIT_HEIGHT
	code_button.flat = true
	code_button.clip_text = true
	code_button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	code_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	code_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	code_button.add_theme_constant_override("icon_max_width",16)
	code_button.mouse_filter = Control.MOUSE_FILTER_PASS
	code_button.focus_mode = Control.FOCUS_ALL
	code_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_button.disabled = _busy
	code_button.tooltip_text = "Copy code"
	code_button.accessibility_name = "Copy friend code for %s" % shown
	code_button.add_theme_font_size_override("font_size",14 if _compact else 16)
	for state: String in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
		code_button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	code_button.add_theme_color_override("font_color",CODE_INK)
	code_button.add_theme_color_override("font_disabled_color",CODE_INK)
	for state: String in ["hover","pressed","hover_pressed","focus"]:
		code_button.add_theme_color_override("font_"+state+"_color",CODE_INK_ACTIVE)
	for state: String in ["normal","hover","pressed","hover_pressed","focus","disabled"]:
		code_button.add_theme_color_override("icon_"+state+"_color",Color("a6edb0"))
	identity.add_child(code_button)
	code_button.pressed.connect(func(): _copy_code(str(peer.player_id),code_button,null))
	_code_fade(code_button,CARD_FILL)
	var state := HBoxContainer.new()
	# Status is display only, so taps just below the code reach its copy band.
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state.add_theme_constant_override("separation",8)
	identity.add_child(state)
	var dot := Panel.new()
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.custom_minimum_size = Vector2(10,10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel",ThemeRules.rounded(Color("a6edb0") if peer.online and peer.status == "accepted" else Color("96aaa4"),5))
	state.add_child(dot)
	var status_label := _label(status,16 if _compact else 20,state)
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.add_theme_color_override("font_color",MUTED)
	var actions := HBoxContainer.new()
	# Keep the coral remove control clear of the neighbouring room actions.
	actions.add_theme_constant_override("separation",10 if _compact else 12)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(actions)
	if peer.status == "incoming":
		var accept := _button("Accept",func(): _act("accept",peer),not _busy,actions)
		accept.custom_minimum_size.x = 112
		_icon_button(REMOVE_ICON,"Decline",func(): _act("remove",peer),not _busy,actions)
	elif peer.status == "outgoing": _icon_button(REMOVE_ICON,"Cancel request",func(): _act("remove",peer),not _busy,actions)
	else:
		var action_width := 112 if _compact else 128
		if peer.join_available:
			var join := _button("Join",func(): _act("join",peer),not _busy,actions)
			join.custom_minimum_size.x = action_width
			join.add_theme_font_size_override("font_size",18 if _compact else 22)
			join.set_meta("room_action","Join")
			_join_buttons.append(join)
		# Hosting alerts are a separate per-friend choice, so Notify stays beside Join.
		var notifying: bool = bool(_notification_preferences.get(str(peer.player_id),false))
		var notify := _button("Notifying" if notifying else "Notify",func(): _ask_hosting_alert(peer),not _busy and event_client != null,actions)
		notify.custom_minimum_size.x = action_width
		notify.add_theme_font_size_override("font_size",18 if _compact else 22)
		notify.tooltip_text = "Turn hosting alerts on or off"
		if notifying:
			ThemeRules.selected_tab(notify)
			notify.add_theme_color_override("font_disabled_color",Color("9aaaa3"))
		else: _secondary(notify)
		_notify_buttons.append(notify)
		_icon_button(REMOVE_ICON,"Remove friend",func(): _remove = peer.duplicate(true); _render(),not _busy,actions)

func _display_name(player_id: String) -> String:
	if _nicknames == null: return player_id.substr(0,8)
	return _nicknames.display_name(str(_context.get("base_url","")),str(_context.get("player_id","")),player_id)

func _ask_hosting_alert(peer: Dictionary) -> void:
	if event_client == null or not _current() or _busy or is_instance_valid(_modal): return
	var enabled: bool = bool(_notification_preferences.get(str(peer.player_id),false))
	var friend := str(peer.player_id)
	_modal = InGameModal.open(_root,"HostingAlertModal","Hosting alerts",friend.substr(0,8))
	_modal.label(("Would you like to stop alerts when %s hosts a room?" if enabled else "Do you want to be notified when %s hosts a room?") % _display_name(friend))
	if is_instance_valid(notification_transport): _modal.label("Phone notifications: Ready" if notification_transport.hosting_registered() else "Phone notifications: Not enabled")
	var confirm: Button = _modal.add_actions("Turn off" if enabled else "Notify me",func():
		_close_modal(false)
		_set_hosting_alert(peer,not enabled))
	confirm.grab_focus()

func _set_hosting_alert(peer: Dictionary, enabled: bool) -> void:
	if event_client == null or _busy or not _current(): return
	_busy = true
	_render()
	var okay: bool = await event_client.set_hosting_alert(peer,enabled)
	if not _current(): return
	if okay:
		_notification_preferences[str(peer.player_id)] = enabled
		if is_instance_valid(notification_transport): notification_transport.set_hosting_friend(str(peer.player_id),enabled,str(peer.request_id))
		_message = "Hosting alerts saved" if enabled else "Hosting alerts turned off"
	else:
		_message = "Hosting alerts could not be updated"
	_busy = false
	_render()

func _add_hosting_events() -> void:
	if _social_events.is_empty(): return
	var panel := _card(_content,16)
	panel.get_parent().size_flags_vertical = Control.SIZE_FILL
	_label("FRIENDS ARE HOSTING",18,panel).add_theme_color_override("font_color",MUTED)
	for event: Dictionary in _social_events:
		var peer := {"player_id":str(event.player_id),"request_id":str(event.request_id)}
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",10)
		panel.add_child(row)
		var detail := _label(_display_name(str(event.player_id))+" has a room ready",20,row)
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var join := _button("Join",func(): _act("join",peer),not _busy,row)
		join.custom_minimum_size.x = 120

func _ack_visible_events() -> void:
	var visible_events := _social_events.duplicate(true)
	for event: Dictionary in visible_events:
		if not _current() or not _foreground: break
		while _api_request_busy():
			await get_tree().process_frame
			if not _current(): break
		if not _current(): break
		await event_client.acknowledge_rendered(event)
	_event_ack_pending = false

func _api_request_busy() -> bool:
	if event_client == null: return true
	var request_api: Variant = event_client.get("_api")
	return event_client.busy or (is_instance_valid(request_api) and request_api.busy)

func _edit_nickname(peer: Dictionary, opener: Control = null) -> void:
	if not _current() or not _foreground or _busy or is_instance_valid(_modal): return
	var server := str(_context.get("base_url",""))
	var owner := str(_context.get("player_id",""))
	var friend := str(peer.get("player_id",""))
	_modal = InGameModal.open(_root,"NicknameModal","Friend nickname",friend.substr(0,8),opener)
	var box: VBoxContainer = _modal.content
	var field_label := _label("Nickname",17,box)
	field_label.add_theme_color_override("font_color",CREAM)
	var field := LineEdit.new()
	field.name = "FriendNickname"
	field.max_length = FriendNicknames.MAX_LENGTH
	field.placeholder_text = friend.substr(0,8)
	field.text = _nicknames.nickname(server,owner,friend)
	field.custom_minimum_size.y = 54
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.caret_blink = true
	for state: String in ["normal","focus","read_only"]:
		var style := ThemeRules.rounded(Color("123533"),12,Color("eceddb") if state == "focus" else Color("4f776d"))
		if state == "focus": style.set_border_width_all(2)
		field.add_theme_stylebox_override(state,ThemeRules.padded(style,16.0,10.0))
	field.add_theme_color_override("font_color",CREAM)
	field.add_theme_color_override("caret_color",CREAM)
	field.add_theme_color_override("font_placeholder_color",Color("7f9a92"))
	field.add_theme_font_size_override("font_size",22)
	box.add_child(field)
	var counter := _label("",15,box)
	counter.name = "NicknameCounter"
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	counter.add_theme_color_override("font_color",MUTED)
	var count := func(text: String): counter.text = "%d / %d" % [text.length(),FriendNicknames.MAX_LENGTH]
	count.call(field.text)
	field.text_changed.connect(count)
	_modal.add_actions("Save",func(): _save_nickname(server,owner,friend,field.text))
	field.text_submitted.connect(func(text: String): _save_nickname(server,owner,friend,text))
	field.grab_focus()
	field.caret_column = field.text.length()

func _save_nickname(server: String, owner: String, friend: String, text: String) -> void:
	if not is_instance_valid(_modal) or not _current(): return
	_message = "" if _nicknames.set_nickname(server,owner,friend,text) else "Nickname could not be saved"
	_close_modal(false)
	_render()

func _close_modal(restore_focus: bool = true) -> void:
	if is_instance_valid(_modal): _modal.close(restore_focus)
	_modal = null

func _share_invite(player_id: String) -> void:
	InviteShare.share(player_id,share_text,clipboard_copy)

func _copy_code(player_id: String, button: Button = null, restore: Texture2D = COPY_ICON) -> void:
	var code := ShareCodes.format(ShareCodes.FRIEND,player_id)
	if code.is_empty(): return
	clipboard_copy.call(code)
	# A brief tick on the pressed control confirms the copy instead of a message.
	if button == null or not is_instance_valid(button) or not button.is_inside_tree(): return
	button.icon = CHECK_ICON
	_place_code_fade(button)
	var shown: WeakRef = weakref(button)
	get_tree().create_timer(COPY_FEEDBACK_SEC).timeout.connect(func():
		var copied: Button = shown.get_ref()
		if copied == null: return
		copied.icon = restore
		_place_code_fade(copied))

## Fades the right end of a clipped code into background, so it reads as continuing.
## Shared by the own-code field and the friend-row codes.
func _code_fade(host: Control, background: Color) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0,Color(background,0.0))
	gradient.set_color(1,Color(background,1.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2(1,0)
	texture.width = 64
	texture.height = 4
	var fade := TextureRect.new()
	fade.name = "CodeFade"
	fade.texture = texture
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.visible = false
	fade.set_meta("fade_width",36.0 if _compact else 48.0)
	host.add_child(fade)
	host.resized.connect(_place_code_fade.bind(host))
	_place_code_fade.call_deferred(host)
	return fade

## Places a host's fade at the end of its text area, shown only while the text is clipped.
func _place_code_fade(target: Variant) -> void:
	# Deferred calls may arrive after a re-render freed the host.
	if not is_instance_valid(target): return
	var host := target as Control
	if host == null: return
	var fade := host.get_node_or_null("CodeFade") as TextureRect
	if fade == null: return
	var field := host as LineEdit
	var button := host as Button
	var style := host.get_theme_stylebox("read_only" if field != null else "normal")
	var text: String = field.text if field != null else button.text
	var font := host.get_theme_font("font")
	var text_width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,host.get_theme_font_size("font_size")).x
	var reserve := 0.0
	if button != null and button.icon != null:
		reserve = float(button.get_theme_constant("icon_max_width")) + float(button.get_theme_constant("h_separation"))
	var text_end := host.size.x - style.get_margin(SIDE_RIGHT) - reserve
	var width := minf(float(fade.get_meta("fade_width",48.0)),maxf(0.0,text_end - style.get_margin(SIDE_LEFT)))
	# Inside the field's 1-unit border; a row code has none.
	var edge := 1.0 if field != null else 0.0
	fade.position = Vector2(text_end - width,edge)
	fade.size = Vector2(width,maxf(0.0,host.size.y - edge * 2.0))
	fade.visible = style.get_margin(SIDE_LEFT) + text_width > text_end + 0.5

## Queues an invite-link friend ID from the app; the confirmation modal is the only way to add.
func confirm_invite_link(player_id: String) -> void:
	if ShareCodes.format(ShareCodes.FRIEND,player_id).is_empty(): return
	_link_id = player_id
	_offer_link()

func _offer_link() -> void:
	if _link_id.is_empty() or not _current() or not _foreground or _busy or client.busy or is_instance_valid(_modal) or not _remove.is_empty(): return
	var friend := _link_id
	_link_id = ""
	if friend == str(_context.get("player_id","")):
		_message = PlayerCopy.FRIEND_CODE_OWN
		_render()
		return
	for peer: Dictionary in client.view().get("friends",[]):
		if peer.player_id != friend: continue
		if peer.status in ["accepted","outgoing"]:
			_message = PlayerCopy.FRIEND_ALREADY_ADDED if peer.status == "accepted" else "Request sent"
			_render()
			return
	var code := ShareCodes.format(ShareCodes.FRIEND,friend)
	_modal = InGameModal.open(_root,"InviteLinkModal",PlayerCopy.INVITE_LINK_TITLE,code)
	var nickname: String = _nicknames.nickname(str(_context.get("base_url","")),str(_context.get("player_id","")),friend)
	if not nickname.is_empty(): _modal.label(PlayerCopy.INVITE_LINK_NICKNAME % nickname)
	var add: Button = _modal.add_actions("Add friend",func():
		if not is_instance_valid(_modal) or _busy: return
		var armed: Button = _modal.find_child("ModalConfirm",true,false)
		if armed == null or armed.disabled: return
		_close_modal(false)
		_code = code
		_act("add"))
	# Add friend stays the cream primary; Cancel is the outlined secondary here.
	var cancel: Button = _modal.find_child("ModalCancel",true,false)
	if cancel != null: _outlined(cancel)
	# The modal can appear right after an automatic navigation; a stray tap must not confirm.
	add.disabled = true
	var armed: WeakRef = weakref(add)
	get_tree().create_timer(INVITE_CONFIRM_ARM_SEC).timeout.connect(func():
		var button: Button = armed.get_ref()
		if button != null: button.disabled = false)
	add.grab_focus()

func _outlined(button: Button) -> void:
	_secondary(button)
	for state: String in ["normal","hover","pressed","hover_pressed","disabled"]:
		ThemeRules.padded(button.get_theme_stylebox(state),20.0,8.0)
	button.add_theme_stylebox_override("focus",ThemeRules.padded(ThemeRules.rounded(Color.TRANSPARENT,14,Color("a6d9c4")),20.0,8.0))

func _host() -> void:
	if not _current() or not _foreground or _busy or client.busy: return
	_busy = true
	host_requested.emit()
	close()

func _open() -> void:
	if not openable_room or not _current() or not _foreground or _busy or client.busy: return
	_busy = true
	open_requested.emit()
	close()

func _refresh(manual: bool = false) -> void:
	if not _current() or not _foreground or _busy: return
	# Both social reads share the list refresh deadline; cached reads must not
	# turn repeated hints or reopening this page into extra inbox requests.
	if not client.refresh_due(manual): return
	var before: Dictionary = client.view()
	_busy = true
	_update_countdowns()
	_countdown.text = "Refreshing…"
	var refreshed: bool = await client.refresh(manual)
	var social_loaded := false
	if not _current(): return
	if event_client != null and not event_client.busy and not client.busy:
		var social: Dictionary = await event_client.inbox()
		if not _current(): return
		if social.get("ok",false):
			var data: Dictionary = social.data
			social_loaded = true
			_social_events.assign(data.get("events",[]))
			_notification_preferences.clear()
			for item: Dictionary in data.get("preferences",[]): _notification_preferences[str(item.player_id)] = item.enabled
			_events_supported = true
			if is_instance_valid(notification_transport): notification_transport.sync_hosting_preferences(data.get("preferences",[]))
	_busy = false
	_message = "" if refreshed else client.last_error
	if _message.is_empty() and _foreground: _message = _change_notice(before,client.view())
	_render()
	if refreshed and social_loaded and _foreground: hosting_view_ready.emit(_social_events.duplicate(true))

func _change_notice(before: Dictionary, after: Dictionary) -> String:
	if before.is_empty(): return ""
	var prior := {}
	for peer: Dictionary in before.get("friends",[]): prior[peer.player_id] = peer
	var request := false
	var room := false
	for peer: Dictionary in after.get("friends",[]):
		var old: Dictionary = prior.get(peer.player_id,{})
		if peer.status == "incoming" and (old.get("status") != "incoming" or old.get("request_id") != peer.request_id): request = true
		if peer.join_available and (not old.get("join_available",false) or old.get("request_id") != peer.request_id): room = true
	if request and room: return "New friend request · Room available"
	return "New friend request" if request else "Room available" if room else ""

func _act(action: String, peer: Dictionary = {}) -> void:
	if not _current() or not _foreground or _busy: return
	_busy = true
	_render()
	var descriptor := {}
	match action:
		"add":
			if await client.add_friend(_code): _code = ""
		"accept": await client.accept_friend(peer)
		"remove":
			if await client.remove_friend(peer):
				if is_instance_valid(notification_transport): notification_transport.set_hosting_friend(str(peer.player_id),false)
				_nicknames.clear_friend(str(_context.get("base_url","")),str(_context.get("player_id","")),str(peer.get("player_id","")))
			_remove = {}
		"share": await client.share_room(shareable_room)
		"unshare": await client.share_room(null)
		"join": descriptor = await client.join_friend(peer)
	if not _current(): return
	if action != "join" and _foreground and client.last_error.is_empty() and client.refresh_due():
		await client.refresh()
		if not _current(): return
	_busy = false
	_message = client.last_error
	if not descriptor.is_empty() and _foreground:
		join_requested.emit(descriptor)
		close()
	else: _render()

func close() -> void:
	if not _alive: return
	_alive = false
	closed.emit()
	queue_free()

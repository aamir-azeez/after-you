extends CanvasLayer
const ThemeRules = preload("res://presentation/control_theme.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const FriendsClient = preload("res://services/friends_client.gd")
const PlayerAvatar = preload("res://presentation/player_avatar.gd")
const BACK_ICON = preload("res://assets/ui/social/arrow-left.svg")
const REFRESH_ICON = preload("res://assets/ui/social/arrows-clockwise.svg")
const COPY_ICON = preload("res://assets/ui/social/copy.svg")
const REMOVE_ICON = preload("res://assets/ui/social/minus-circle.svg")
const SHARE_ICON = preload("res://assets/ui/social/share-network.svg")
const ADD_ICON = preload("res://assets/ui/social/plus.svg")
const USERS_ICON = preload("res://assets/ui/social/users.svg")
const CREAM := Color("eceddb")
const MUTED := Color("afc6be")
const INK := Color("123936")
signal closed
signal host_requested
signal open_requested
signal join_requested(descriptor: Dictionary)
var client: RefCounted
var shareable_room: Dictionary = {}
var room_title := ""
var room_status := ""
var openable_room := false
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
var _compact := false
var _stacked := false
var _narrow := false
var _title: Label
var _heading_font: FontVariation
var _scroll: ScrollContainer

func _ready() -> void:
	layer = 50
	_context = client.context()
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
	layout.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_margin.add_theme_constant_override("margin_left",int(safe.position.x)+side)
	_margin.add_theme_constant_override("margin_right",int(rect.end.x-safe.end.x)+side)
	_margin.add_theme_constant_override("margin_top",int(safe.position.y)+(16 if compact else 20))
	_margin.add_theme_constant_override("margin_bottom",int(rect.end.y-safe.end.y)+(16 if compact else 20))
	_title.add_theme_font_size_override("font_size",38 if compact else 54)
	_countdown.add_theme_font_size_override("font_size",16 if compact else 20)
	_countdown.visible = not narrow
	if changed: _render()

func _current() -> bool:
	return _alive and is_inside_tree() and not _context.is_empty() and client.context() == _context

func _process(_delta: float) -> void:
	if not _current(): close(); return
	if _foreground and not _busy and not client.busy and client.refresh_due(): _refresh()
	if _foreground and not _busy and Time.get_ticks_msec() >= _next_local_refresh:
		_next_local_refresh = Time.get_ticks_msec() + 500
		if _presence_key(client.view()) != _presence_signature: _render()
		_update_countdowns()

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

func _icon_button(icon: Texture2D, description: String, action: Callable, enabled: bool, parent: Node) -> Button:
	var button := _button("",action,enabled,parent)
	button.icon = icon
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.tooltip_text = description
	button.accessibility_name = description
	button.custom_minimum_size = Vector2(48,48)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_secondary(button,true)
	return button

func _pad_labeled_icon(button: Button) -> void:
	ThemeRules.inset_button(button)

func _card(parent: Node, inset: int = 20) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := ThemeRules.rounded(Color("123936"),16,Color("466e63"))
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
	var style := ThemeRules.rounded(Color("14312f"),12,Color("52776d"))
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
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	if not _message.is_empty(): _label(_message)
	if not _remove.is_empty():
		var confirmation := _card(_content,24)
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
	main.add_theme_constant_override("separation",16)
	_content.add_child(main)
	var friends := _card(main,16 if _compact else 18)
	friends.get_parent().size_flags_stretch_ratio = 1.35
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
	var utility := _card(_content,12 if _compact else 22)
	utility.get_parent().name = "FriendCodeUtilities"
	var utilities := BoxContainer.new()
	utilities.vertical = _stacked
	utilities.add_theme_constant_override("separation",24)
	utility.add_child(utilities)
	if not page.is_empty():
		var own_column := VBoxContainer.new()
		own_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		own_column.add_theme_constant_override("separation",10)
		utilities.add_child(own_column)
		_label("Your friend code",20,own_column)
		var own_row := HBoxContainer.new()
		own_row.add_theme_constant_override("separation",6)
		own_column.add_child(own_row)
		var own := LineEdit.new()
		own.name = "OwnFriendCode"
		own.text = page.friend_code
		own.editable = false
		own.custom_minimum_size.y = 54
		own.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		own.add_theme_font_size_override("font_size",18 if _compact else 21)
		_field_style(own)
		own_row.add_child(own)
		_icon_button(COPY_ICON,"Copy code",func(): DisplayServer.clipboard_set(str(page.friend_code)),true,own_row)
	var add_column := VBoxContainer.new()
	add_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_column.add_theme_constant_override("separation",10)
	utilities.add_child(add_column)
	_label("Friend code",20,add_column)
	var add_row := BoxContainer.new()
	add_row.vertical = _narrow
	add_row.add_theme_constant_override("separation",10)
	add_column.add_child(add_row)
	var field := LineEdit.new()
	field.name = "FriendCode"
	field.placeholder_text = "Enter friend code"
	field.max_length = 30
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
	var add := _button("Add friend",func(): _act("add"),not _busy,add_row)
	add.icon = ADD_ICON
	_pad_labeled_icon(add)
	add.custom_minimum_size.x = 156 if _compact else 176
	add.size_flags_horizontal = Control.SIZE_SHRINK_END
	_scroll.set_deferred("scroll_vertical",scroll_position)
	_update_countdowns()

func _room_panel(page: Dictionary, parent: Node) -> void:
	var room := _card(parent,12 if _compact else 24)
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
	var name_label := _label(str(peer.player_id).substr(0,8),20 if _compact else 24,identity)
	name_label.add_theme_font_override("font",_heading_font)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var state := HBoxContainer.new()
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state.add_theme_constant_override("separation",8)
	identity.add_child(state)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(10,10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel",ThemeRules.rounded(Color("a6edb0") if peer.online and peer.status == "accepted" else Color("96aaa4"),5))
	state.add_child(dot)
	var status_label := _label(status,16 if _compact else 20,state)
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.add_theme_color_override("font_color",MUTED)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",6)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(actions)
	if peer.status == "incoming":
		var accept := _button("Accept",func(): _act("accept",peer),not _busy,actions)
		accept.custom_minimum_size.x = 112
		_icon_button(REMOVE_ICON,"Decline",func(): _act("remove",peer),not _busy,actions)
	elif peer.status == "outgoing": _icon_button(REMOVE_ICON,"Cancel request",func(): _act("remove",peer),not _busy,actions)
	else:
		var room_action := "Join" if peer.join_available else "Check room"
		var join := _button(room_action,func(): _act("join",peer),not _busy,actions)
		join.custom_minimum_size.x = 132 if _compact else 184
		join.add_theme_font_size_override("font_size",18 if _compact else 22)
		join.set_meta("room_action",room_action)
		_join_buttons.append(join)
		_icon_button(REMOVE_ICON,"Remove friend",func(): _remove = peer.duplicate(true); _render(),not _busy,actions)

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
	var before: Dictionary = client.view()
	_busy = true
	_update_countdowns()
	_countdown.text = "Refreshing…"
	var refreshed: bool = await client.refresh(manual)
	if not _current(): return
	_busy = false
	_message = "" if refreshed else client.last_error
	if _message.is_empty() and _foreground: _message = _change_notice(before,client.view())
	_render()

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
		"remove": await client.remove_friend(peer); _remove = {}
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

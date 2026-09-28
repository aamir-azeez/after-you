extends CanvasLayer
const ThemeRules = preload("res://presentation/control_theme.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const FriendsClient = preload("res://services/friends_client.gd")
signal closed
signal host_requested
signal open_requested
signal join_requested(descriptor: Dictionary)
var client: RefCounted
var shareable_room: Dictionary = {}
var room_title := ""
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
	layout.add_theme_constant_override("separation",12)
	_margin.add_child(layout)
	var refresh_row := HBoxContainer.new()
	refresh_row.add_theme_constant_override("separation",12)
	layout.add_child(refresh_row)
	_countdown = Label.new()
	_countdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh_row.add_child(_countdown)
	_refresh_button = _button("Refresh",func(): _refresh(true),true,refresh_row)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation",12)
	scroll.add_child(_content)
	_button("Back",close,true,layout)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_render()
	await _refresh()

func _layout() -> void:
	if not is_instance_valid(_margin): return
	var rect := get_viewport().get_visible_rect()
	var safe := rect
	if OS.has_feature("android"): safe = SafeArea.viewport_rect(Rect2(DisplayServer.get_display_safe_area()),get_viewport().get_screen_transform(),rect)
	var side := maxi(20,int((safe.size.x-820)*0.5))
	_margin.add_theme_constant_override("margin_left",int(safe.position.x)+side)
	_margin.add_theme_constant_override("margin_right",int(rect.end.x-safe.end.x)+side)
	_margin.add_theme_constant_override("margin_top",int(safe.position.y)+24)
	_margin.add_theme_constant_override("margin_bottom",int(rect.end.y-safe.end.y)+24)

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
	_refresh_button.text = "Refresh" if manual_wait == 0 else "Refresh (%ds)" % manual_wait
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

func _label(value: String, size: int = 20) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",size)
	_content.add_child(label)

func _button(value: String, action: Callable, enabled: bool = true, parent: Node = null) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(0,52)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.disabled = not enabled
	button.pressed.connect(action)
	(parent if parent != null else _content).add_child(button)
	return button

func _render() -> void:
	if not is_instance_valid(_content): return
	var focus := get_viewport().gui_get_focus_owner()
	var restore_input := focus is LineEdit and focus.name == "FriendCode"
	var caret: int = focus.caret_column if restore_input else 0
	var selection_from: int = focus.get_selection_from_column() if restore_input else 0
	var selection_to: int = focus.get_selection_to_column() if restore_input else 0
	_join_buttons.clear()
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_label("Friends",34)
	if not _message.is_empty(): _label(_message)
	if not _remove.is_empty():
		_label("Remove friend?",26)
		_button("Remove",func(): _act("remove",_remove),not _busy)
		_button("Cancel",func(): _remove = {}; _render(),not _busy)
		_update_countdowns()
		return
	var page: Dictionary = client.view()
	_presence_signature = _presence_key(page)
	_button("Host a room",_host,not _busy and not client.busy)
	if not shareable_room.is_empty() or openable_room:
		_label(room_title if not room_title.is_empty() else "Current room",22)
	if not shareable_room.is_empty():
		if FriendsClient.same_room(page.get("shared_room"),shareable_room):
			_label("Shared with friends")
		else:
			_label("All friends")
			_button("Share current room",func(): _act("share"),not _busy)
	if openable_room: _button("Return to room",_open,not _busy and not client.busy)
	if page.get("shared_room") != null: _button("Stop sharing room",func(): _act("unshare"),not _busy)
	# Put available rooms before requests and the add-code form.
	for joinable: bool in [true,false]:
		for peer: Dictionary in page.get("friends",[]):
			if peer.join_available != joinable: continue
			_friend_row(peer)
	if not page.is_empty():
		_label("Your friend code",22)
		var own := LineEdit.new()
		own.text = page.friend_code
		own.editable = false
		own.custom_minimum_size.y = 50
		_content.add_child(own)
		_button("Copy code",func(): DisplayServer.clipboard_set(str(page.friend_code)))
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation",10)
	_content.add_child(add_row)
	var field := LineEdit.new()
	field.name = "FriendCode"
	field.placeholder_text = "Friend code"
	field.max_length = 30
	field.text = _code
	field.editable = not _busy
	field.custom_minimum_size = Vector2(260,52)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_changed.connect(func(value: String): _code = value)
	add_row.add_child(field)
	if restore_input and not _busy:
		field.grab_focus()
		field.caret_column = caret
		if selection_to > selection_from: field.select(selection_from,selection_to)
	_button("Add friend",func(): _act("add"),not _busy,add_row)
	_update_countdowns()

func _friend_row(peer: Dictionary) -> void:
	var status := "Online" if peer.online else "Offline"
	if peer.status == "incoming": status = "Friend request"
	elif peer.status == "outgoing": status = "Request sent"
	_label("%s · %s" % [str(peer.player_id).substr(0,8),status],22)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	_content.add_child(row)
	if peer.status == "incoming":
		_button("Accept",func(): _act("accept",peer),not _busy,row)
		_button("Decline",func(): _act("remove",peer),not _busy,row)
	elif peer.status == "outgoing": _button("Cancel request",func(): _act("remove",peer),not _busy,row)
	else:
		var room_action := "Join" if peer.join_available else "Check room"
		var join := _button(room_action,func(): _act("join",peer),not _busy,row)
		join.set_meta("room_action",room_action)
		_join_buttons.append(join)
		_button("Remove friend",func(): _remove = peer.duplicate(true); _render(),not _busy,row)

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
	await client.refresh(manual)
	if not _current(): return
	_busy = false
	_message = client.last_error
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

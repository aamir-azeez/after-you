extends CanvasLayer
const ThemeRules = preload("res://presentation/control_theme.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
signal closed
signal join_requested(descriptor: Dictionary)
var client: RefCounted
var shareable_room: Dictionary = {}
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

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT]: _foreground = false
	elif what in [NOTIFICATION_APPLICATION_RESUMED,NOTIFICATION_APPLICATION_FOCUS_IN]: _foreground = true
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST: close()

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
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_label("Friends",34)
	if not _message.is_empty(): _label(_message)
	if not _remove.is_empty():
		_label("Remove friend?",26)
		_button("Remove",func(): _act("remove",_remove),not _busy)
		_button("Cancel",func(): _remove = {}; _render(),not _busy)
		return
	var page: Dictionary = client.view()
	_presence_signature = _presence_key(page)
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
	for peer: Dictionary in page.get("friends",[]):
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
			_button("Join",func(): _act("join",peer),not _busy and peer.join_available,row)
			_button("Remove friend",func(): _remove = peer.duplicate(true); _render(),not _busy,row)
	if not shareable_room.is_empty(): _button("Share current room",func(): _act("share"),not _busy)
	if page.get("shared_room") != null: _button("Stop sharing room",func(): _act("unshare"),not _busy)
	_button("Refresh",_refresh,not _busy and client.refresh_due())

func _refresh() -> void:
	if not _current() or not _foreground or _busy: return
	_busy = true
	await client.refresh()
	if not _current(): return
	_busy = false
	_message = client.last_error
	_render()

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

extends CanvasLayer
## Explicit community rules, reporting and blocking. Back stays available.
const Client = preload("res://services/safety_client.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const REASONS := [["Sexual content", "sexual_content"], ["Child safety", "child_safety"], ["Threats or harassment", "harassment"], ["Hateful content", "hate"], ["Someone's private information", "privacy"], ["Other inappropriate content", "other"]]
var client: RefCounted
var context: Dictionary = {}
var terms_only := false
var _closed: Callable
var _blocked: Callable
var _root: Control
var _margin: MarginContainer
var _content: VBoxContainer
var _owner_context: Dictionary = {}
var _alive := true
var _busy := false
var _message := ""
var _page := "home"
var _photo: Variant = null

func _init(service: RefCounted = null, room: Dictionary = {}, on_closed: Callable = Callable(), on_blocked: Callable = Callable(), rules_only: bool = false) -> void:
	client = service
	context = room.duplicate(true)
	_closed = on_closed
	_blocked = on_blocked
	terms_only = rules_only

func _ready() -> void:
	layer = 50
	_owner_context = client._context()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = Theme.new()
	_root.theme.default_font = preload("res://assets/fonts/nunito.ttf")
	_root.theme.default_font_size = 20
	_root.theme.set_color("font_color", "Label", Color("eceddb"))
	ThemeRules.install_buttons(_root.theme)
	add_child(_root)
	var background := ColorRect.new()
	background.color = Color("123936")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(background)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_margin.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_content)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_render()
	if not _owner_context.is_empty(): await _load()

func _layout() -> void:
	if not is_instance_valid(_margin): return
	var rect := get_viewport().get_visible_rect()
	var safe := rect
	if OS.has_feature("android"): safe = SafeArea.viewport_rect(Rect2(DisplayServer.get_display_safe_area()), get_viewport().get_screen_transform(), rect)
	var side := maxi(20, int((safe.size.x - 780) * 0.5))
	_margin.add_theme_constant_override("margin_left", int(safe.position.x) + side)
	_margin.add_theme_constant_override("margin_right", int(rect.end.x - safe.end.x) + side)
	_margin.add_theme_constant_override("margin_top", int(safe.position.y) + 24)
	_margin.add_theme_constant_override("margin_bottom", int(rect.end.y - safe.end.y) + 24)

func _current() -> bool:
	return _alive and is_inside_tree() and client._context() == _owner_context

func _process(_delta: float) -> void:
	if _alive and not _current(): close()

func _label(text: String, size: int = 20) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	_content.add_child(label)

func _button(text: String, action: Callable, enabled: bool = true) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 54
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.disabled = not enabled
	button.pressed.connect(action)
	_content.add_child(button)

func _render() -> void:
	if not is_instance_valid(_content): return
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_label("Community & privacy", 32)
	if not _message.is_empty(): _label(_message)
	if _busy:
		_label("Checking with the service… Your game and kept photos are unchanged.")
		_button("Back", close)
		return
	if _page == "report":
		_label("Report this photo" if _photo is Dictionary else "Report this player", 25)
		_label("Choose the reason for your report. This sends the room and photo reference to the developer for review; it does not upload another copy of the image. Avoid sharing private information in any later evidence.")
		for reason: Array in REASONS: _button(reason[0], func(): _report(reason[1]))
		_button("Cancel", func(): _page = "home"; _render())
		return
	if _page == "block":
		_label("Block this player?", 25)
		_label("This stops new shared-room interaction and partner photo delivery in both directions. Their photos will be hidden in shared replays. Photos already kept in your private library remain there. Existing saved files cannot be recalled from someone else's device. Your recorded contributions are kept.")
		_button("Block player", _block)
		_button("Cancel", func(): _page = "home"; _render())
		return
	if _page == "clear_report":
		_label("Stop checking the saved report?", 25)
		_label("This clears only its pending request on this phone. A report that already reached the developer is not withdrawn.")
		_button("Clear local report request", _clear_report)
		_button("Keep checking it", func(): _page = "home"; _render())
		return
	_label("Share only photos you have permission to share. Sexual content, child exploitation, threats, harassment, hateful or illegal content and sharing someone else's private information without consent are not allowed.")
	_button("Read community rules", func(): _open_link("/community-rules"))
	_button("Privacy policy", func(): _open_link("/privacy"))
	_button("Account deletion information", func(): _open_link("/account-deletion"))
	if _owner_context.is_empty():
		_label("Open your account before accepting rules or managing reports and blocks.")
	elif not client.config.is_empty():
		if client.terms_accepted: _label("Community rules accepted for this account.")
		else:
			_label("Before sharing a new photo, accept the community rules dated 16 September 2026. Accepting does not upload a photo.")
			_button("I accept the community rules", _accept)
	if not _owner_context.is_empty() and not terms_only:
		var pending: Dictionary = client.pending_report()
		if not pending.is_empty():
			_label("A report request is saved on this phone. Check its receipt or retry the same report before starting another.")
			_button("Check saved report", func(): _report_request(false))
			_button("Retry same report", func(): _report_request(true))
			_button("Clear local report request…", func(): _page = "clear_report"; _render())
		if Client.valid_room(context):
			_button("Report this player", func(): _photo = null; _page = "report"; _render(), pending.is_empty())
			var photos: Array = context.get("photos", [])
			for index in range(photos.size()):
				var photo: Dictionary = photos[index].duplicate(true)
				_button("Report partner photo " + str(index + 1), func(): _photo = photo; _page = "report"; _render(), pending.is_empty())
			_button("Block this player…", func(): _page = "block"; _render())
		var blocked: Array = client.blocked_players()
		if not blocked.is_empty():
			_label("Players you blocked", 25)
			_label("Removing your block does not remove a block set by the other player.")
			for index in range(blocked.size()):
				var player: String = blocked[index]
				_button("Unblock player " + str(index + 1) + " · " + player.substr(0, 6), func(): _unblock(player))
	if not _owner_context.is_empty(): _button("Check again", _load)
	_button("Back to your photo" if terms_only else "Back", close)

func _wait_api() -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while _current() and is_instance_valid(client._api) and client._api.busy:
		if Time.get_ticks_msec() >= deadline: _message = "Another request is still finishing. Try again in a moment."; return false
		await get_tree().create_timer(0.1).timeout
	return _current()

func _load() -> void:
	if _busy or not _current(): return
	_busy = true
	_render()
	if not await _wait_api():
		_busy = false
		if _current(): _render()
		return
	var ok: bool = await client.check_terms()
	if ok and not terms_only: ok = await client.refresh_blocks()
	if not _current(): return
	_busy = false
	_message = "" if ok else client.last_error
	_render()

func _accept() -> void:
	if _busy or not _current(): return
	_busy = true
	_render()
	var ok: bool = await client.accept_rules()
	if not _current(): return
	_busy = false
	_message = "Rules accepted. Return to your photo and choose Share when you are ready." if ok else client.last_error
	_render()

func _report(reason: String) -> void:
	if _busy or not _current(): return
	_busy = true
	_render()
	var ok: bool = await client.report(context, reason, _photo)
	if not _current(): return
	_busy = false
	_page = "home"
	_message = "Report received for review. You can also block this player. No response time is promised." if ok else client.last_error
	_render()

func _report_request(retry: bool) -> void:
	if _busy or not _current(): return
	_busy = true
	_render()
	var ok: bool = await client.retry_report() if retry else await client.check_report()
	if not _current(): return
	_busy = false
	_message = "Report received for review." if ok else client.last_error
	_render()

func _clear_report() -> void:
	_message = "Local request cleared. Any received report remains with the developer." if client.clear_pending_report() else client.last_error
	_page = "home"
	_render()

func _block() -> void:
	if _busy or not _current(): return
	_busy = true
	_render()
	var ok: bool = await client.block(context)
	if not _current(): return
	_busy = false
	if ok:
		_alive = false
		client.invalidate()
		if _blocked.is_valid(): _blocked.call()
		elif _closed.is_valid(): _closed.call()
		queue_free()
	else:
		_page = "home"
		_message = client.last_error
		_render()

func _unblock(player: String) -> void:
	if _busy or not _current(): return
	_busy = true
	_render()
	var ok: bool = await client.unblock(player)
	if not _current(): return
	_busy = false
	_message = "Your block was removed. The other player's block, if any, still applies." if ok else client.last_error
	_render()

func _open_link(path: String) -> void:
	if not client.open_public(path): _message = "This link could not open. Check your connection and try again."; _render()

func close() -> void:
	if not _alive: return
	_alive = false
	client.invalidate()
	if _closed.is_valid(): _closed.call()
	queue_free()

func _exit_tree() -> void:
	_alive = false
	if client != null: client.invalidate()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_WM_CLOSE_REQUEST] and _alive and is_instance_valid(client): close()

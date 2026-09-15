extends Control
## Explicit device transfer. No background upload or automatic camera access.
const Client = preload("res://services/photo_transfer_client.gd")
const Library = preload("res://services/turn_photo_library.gd")
const Controls = preload("res://presentation/control_theme.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const Capture = preload("res://services/optional_photo_capture.gd")
const Local = preload("res://services/turn_photo_local.gd")
const PhotoStore = preload("res://services/turn_photo_store.gd")
var client_override: RefCounted
var _api: Node
var _identity: Callable
var _closed: Callable
var _client: RefCounted
var _library: RefCounted
var _content: VBoxContainer
var _margin: MarginContainer
var _status: Label
var _actions: Array[Button] = []
var _owner := ""
var _epoch := -1
var _confirming := false
var _local_page := 0
var _migration_busy := false
var _local: Node
var _closing := false
var _confirm_clear := false
var _migration_message := ""
var _back: Button

func _init(api: Node = null, identity: Callable = Callable(), on_closed: Callable = Callable()) -> void:
	_api = api
	_identity = identity
	_closed = on_closed

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_library = Library.new()
	_client = Client.new(_request, _identity, _library) if client_override == null else client_override
	var bound: Dictionary = _identity.call() if _identity.is_valid() else {}
	_owner = str(bound.get("player_id", ""))
	_epoch = int(bound.get("epoch", -1))
	theme = Theme.new()
	theme.default_font = preload("res://assets/fonts/nunito.ttf")
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", Color("eceddb"))
	Controls.install_buttons(theme)
	var background := ColorRect.new()
	background.color = Color("123936")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_margin.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 14)
	scroll.add_child(_content)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_client.progress.connect(_progress)
	_render()
	if OS.has_feature("android") and client_override == null:
		_migration_busy = true
		_progress("Keeping any photos from earlier app versions on this phone…")
		var capture := Capture.new()
		add_child(capture)
		_local = Local.new(capture)
		add_child(_local)
		var migrated: Dictionary = await _local.migrate_owner(_owner, PhotoStore.new(), _library, _current)
		_migration_busy = false
		if not _current(): return
		_set_migration_result(migrated)
	await _refresh()

func _set_migration_result(result: Dictionary) -> void:
	_migration_message = ""
	if not result.get("ok", false) or int(result.get("failed", 0)) > 0 or int(result.get("missing", 0)) > 0:
		_migration_message = "Some earlier photos could not be read yet. Keep this phone's app data and retry Photo transfer before changing phones."

func _layout() -> void:
	if not is_instance_valid(_margin): return
	var rect := get_viewport().get_visible_rect()
	var safe := rect
	if OS.has_feature("android"):
		safe = SafeArea.viewport_rect(Rect2(DisplayServer.get_display_safe_area()), get_viewport().get_screen_transform(), rect)
	var side := maxi(24, int((safe.size.x - 820) * 0.5))
	_margin.add_theme_constant_override("margin_left", int(safe.position.x) + side)
	_margin.add_theme_constant_override("margin_right", int(rect.end.x - safe.end.x) + side)
	_margin.add_theme_constant_override("margin_top", int(safe.position.y) + 28)
	_margin.add_theme_constant_override("margin_bottom", int(rect.end.y - safe.end.y) + 24)

func _request(method: int, path: String, body: Dictionary) -> Dictionary:
	if not _current() or not is_instance_valid(_api):
		return {"ok": false, "code": "identity_changed"}
	return await _api.request_json(method, path, body)

func _current() -> bool:
	if _closing or not is_inside_tree() or not _identity.is_valid(): return false
	var value: Dictionary = _identity.call()
	return value.get("ready", false) and value.get("player_id") == _owner and value.get("epoch") == _epoch

func _process(_delta: float) -> void:
	if _client != null and not _current():
		_client.invalidate()
		_close()

func _paragraph(text: String, large: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if large:
		label.add_theme_font_override("font", preload("res://assets/fonts/fredoka.ttf"))
		label.add_theme_font_size_override("font_size", 32)
	return label

func _button(text: String, action: Callable, secondary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 54
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.pressed.connect(action)
	if secondary: Controls.secondary(button)
	button.disabled = _client.busy or _migration_busy
	_actions.append(button)
	return button

func _render() -> void:
	if not is_inside_tree(): return
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_actions.clear()
	_content.add_child(_paragraph("Photo transfer", true))
	var local: Dictionary = _client.local_entries()
	var entries: Array = local.get("entries", [])
	_content.add_child(_paragraph("%d photos saved on this phone" % entries.size()))
	if not _migration_message.is_empty():
		_content.add_child(_paragraph(_migration_message))
	_content.add_child(_paragraph("Move your photos to another phone using a temporary server copy. First prepare a transfer here, then recover your account on the other phone and choose Receive photos. Account recovery signs this phone out."))
	_status = _paragraph(_client.message)
	_status.add_theme_color_override("font_color", Color("f1c48a"))
	_content.add_child(_status)
	if _confirm_clear:
		_content.add_child(_paragraph("Clear this phone's unfinished transfer plan? Local photos are kept. Photos already on the server will stay until received or their 14-day expiry. This does not reset the once-per-day limit."))
		_content.add_child(_button("Clear unfinished plan", func(): _client.abandon_local_plan(); _confirm_clear = false; _render()))
		_content.add_child(_button("Keep the plan", func(): _confirm_clear = false; _render(), true))
	elif _confirming:
		_content.add_child(_paragraph("This uploads up to your newest 1,000 photos, including photos you kept private. Only your recovered account can receive them. The temporary copy lasts at most 14 days and is removed as each photo is safely received. Older photos stay on this phone. A new transfer can be prepared once every 24 hours."))
		_content.add_child(_button("Store photos for up to 14 days", _prepare))
		_content.add_child(_button("Not now", func(): _confirming = false; _render(), true))
	else:
		var prepare := _button("Prepare transfer", func(): _confirming = true; _render())
		prepare.disabled = _client.busy or _migration_busy or entries.is_empty() or not local.get("ok", false)
		_content.add_child(prepare)
		if _client.has_pending_upload():
			_content.add_child(_button("Continue preparing transfer", _resume))
		if _client.has_pending_work():
			_content.add_child(_button("Clear unfinished plan…", func(): _confirm_clear = true; _render(), true))
		_content.add_child(_button("Receive photos", _receive))
		_content.add_child(_button("Refresh transfer status", _refresh, true))
		_content.add_child(_paragraph("Received photos stay in app-private storage. Reinstalling the app or clearing its data removes local photos; prepare a transfer before changing phones. A transfer is temporary, not long-term storage."))
	var stop := Button.new()
	stop.text = "Pause & return" if _client.busy else "Back"
	stop.custom_minimum_size.y = 54
	stop.mouse_filter = Control.MOUSE_FILTER_PASS
	Controls.secondary(stop)
	stop.pressed.connect(_close)
	_content.add_child(stop)
	_back = stop
	if not entries.is_empty() and not _confirming:
		_content.add_child(_paragraph("On this phone", true))
		var start := _local_page * 12
		if start >= entries.size():
			_local_page = 0
			start = 0
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		_content.add_child(grid)
		for index in range(start, mini(start + 12, entries.size())):
			var exported: Dictionary = _library.export_entry(_owner, entries[index].entry_id)
			if not exported.get("ok", false): continue
			var payload: Dictionary = exported.get("entry", {})
			var image := Image.new()
			if image.load_jpg_from_buffer(Marshalls.base64_to_raw(str(payload.get("jpeg_base64", "")))) != OK: continue
			var picture := TextureRect.new()
			picture.texture = ImageTexture.create_from_image(image)
			picture.custom_minimum_size = Vector2(88, 88)
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			grid.add_child(picture)
		if entries.size() > 12:
			_content.add_child(_button("More photos", func(): _local_page = (_local_page + 1) % ceili(entries.size() / 12.0); _render(), true))

func _progress(text: String) -> void:
	if is_instance_valid(_status): _status.text = text
	if is_instance_valid(_back): _back.text = "Pause & return" if _client.busy else "Back"
	for action: Button in _actions:
		if is_instance_valid(action): action.disabled = _client.busy or _migration_busy

func _refresh() -> void:
	if not _current() or _client.busy or _migration_busy: return
	await _client.refresh()
	if _current(): _render()

func _prepare() -> void:
	if not _current() or _client.busy or _migration_busy: return
	_confirming = false
	await _client.prepare()
	if _current(): _render()

func _resume() -> void:
	if not _current() or _client.busy or _migration_busy: return
	await _client.resume_upload()
	if _current(): _render()

func _receive() -> void:
	if not _current() or _client.busy or _migration_busy: return
	await _client.receive()
	if _current(): _render()

func invalidate() -> void:
	if _client != null: _client.invalidate()
	if is_instance_valid(_local): _local.invalidate()

func _close() -> void:
	if _closing: return
	_closing = true
	invalidate()
	set_process(false)
	if _closed.is_valid():
		var action := _closed
		_closed = Callable()
		action.call_deferred()
	else:
		queue_free()

func _exit_tree() -> void:
	invalidate()

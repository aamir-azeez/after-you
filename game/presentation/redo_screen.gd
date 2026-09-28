extends CanvasLayer
const ThemeRules = preload("res://presentation/control_theme.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
signal closed
var client: RefCounted
var accepted := false
var allow_mutations := true
var _owner: Dictionary = {}
var _content: VBoxContainer
var _margin: MarginContainer
var _alive := true
var _busy := false
var _foreground := true

func _ready() -> void:
	layer = 51
	_owner = client._context()
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = Theme.new()
	var body := FontVariation.new()
	body.base_font = preload("res://assets/fonts/nunito.ttf")
	body.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):600.0}
	root.theme.default_font = body
	root.theme.default_font_size = 20
	root.theme.set_color("font_color","Label",Color("eceddb"))
	ThemeRules.install_buttons(root.theme)
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color("123936")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_margin)
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
	_button("Back",close,layout)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_render()
	await _refresh()

func _layout() -> void:
	var rect := get_viewport().get_visible_rect()
	var safe := rect
	if OS.has_feature("android"): safe = SafeArea.viewport_rect(Rect2(DisplayServer.get_display_safe_area()),get_viewport().get_screen_transform(),rect)
	var side := maxi(20,int((safe.size.x-680)*0.5))
	_margin.add_theme_constant_override("margin_left",int(safe.position.x)+side)
	_margin.add_theme_constant_override("margin_right",int(rect.end.x-safe.end.x)+side)
	_margin.add_theme_constant_override("margin_top",int(safe.position.y)+24)
	_margin.add_theme_constant_override("margin_bottom",int(rect.end.y-safe.end.y)+24)

func _current() -> bool: return _alive and is_inside_tree() and not _owner.is_empty() and client._context() == _owner
func _process(_delta: float) -> void:
	if not _current(): close()
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT]: _foreground = false
	elif what in [NOTIFICATION_APPLICATION_RESUMED,NOTIFICATION_APPLICATION_FOCUS_IN]: _foreground = true
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST: close()

func _label(text: String, size: int = 22) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",size)
	_content.add_child(label)
func _button(text: String, action: Callable, parent: Node = null) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 54
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.disabled = _busy and parent == null
	button.pressed.connect(action)
	(parent if parent != null else _content).add_child(button)

func _render() -> void:
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_label("Turn handoff",32)
	if not client.last_error.is_empty(): _label(client.last_error,20)
	if accepted:
		_label("Ready to record again")
		return
	if not client.pending().is_empty():
		_label("Redo accepted; finishing recovery" if client.has_method("settlement_pending") and client.settlement_pending() else "Request pending")
		_button("Retry request",func(): _act("retry"))
		return
	if not allow_mutations:
		_button("Refresh",_refresh)
		return
	var view: Dictionary = client.view()
	var request: Variant = view.get("request")
	if request is Dictionary:
		var labels := {"pending":"Redo requested","declined":"Request declined","cancelled":"Request cancelled","accepted":"Ready to record again"}
		_label(labels.get(request.status,"Request pending"))
	if client.can_accept():
		_button("Redo my turn",func(): _act("accept"))
		_button("Keep this turn",func(): _act("decline"))
	elif client.can_cancel(): _button("Cancel request",func(): _act("cancel"))
	elif client.can_request(): _button(client.request_label() if client.has_method("request_label") else "Ask for redo",func(): _act("request"))
	elif request == null and not _busy: _label("No redo request")
	_button("Refresh",_refresh)

func _refresh() -> void:
	if not _current() or not _foreground or _busy: return
	_busy = true
	_render()
	await client.refresh()
	if not _current(): return
	_busy = false
	_render()

func _act(action: String) -> void:
	if not _current() or not _foreground or _busy: return
	if not allow_mutations and action != "retry": return
	_busy = true
	_render()
	match action:
		"request": await client.request_redo()
		"accept": await client.accept()
		"decline": await client.decline()
		"cancel": await client.cancel()
		"retry": await client.retry(allow_mutations)
	if not _current(): return
	_busy = false
	accepted = client.accepted
	_render()

func close() -> void:
	if not _alive: return
	_alive = false
	closed.emit()
	queue_free()

func invalidate() -> void:
	_alive = false
	set_process(false)
	queue_free()

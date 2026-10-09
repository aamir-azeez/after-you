extends CanvasLayer
## Room hub presentation. Requests are emitted to the app; this screen never
## creates a room, polls a server, or marks activity seen during an open tap.
const SafeArea = preload("res://presentation/safe_area.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const InboxClient = preload("res://services/room_inbox_client.gd")
const CREAM := Color("eceddb")
const MUTED := Color("afc6be")
const PANEL := Color("173f39")
const SURFACE := Color("1b4941")
signal closed
signal room_open_requested(room: Dictionary)
signal host_requested(chapter_key: String, visibility: String)
signal chapter_picked(chapter_key: String)
signal join_code_requested(code: String)
signal friends_requested

var client: RefCounted
var chapters: Array[Dictionary] = []
var display_name: Callable
var thumbnail_for: Callable
var _root: Control
var _margin: MarginContainer
var _layout: VBoxContainer
var _body: GridContainer
var _rooms_column: VBoxContainer
var _right_column: VBoxContainer
var _rooms_list: VBoxContainer
var _tabs: HBoxContainer
var _notice: Label
var _chapter_picker: OptionButton
var _join_code: LineEdit
var _tab := "Your rooms"
var _visibility := "friends"
var _busy := false
var _compact := false
var _stacked := false
var _visible_rooms: Array[Dictionary] = []

func _ready() -> void:
	layer = 60
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = Theme.new()
	var body_font := FontVariation.new()
	body_font.base_font = preload("res://assets/fonts/nunito.ttf")
	body_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):600.0}
	var heading_font := FontVariation.new()
	heading_font.base_font = preload("res://assets/fonts/fredoka.ttf")
	heading_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):600.0}
	_root.theme.default_font = body_font
	_root.theme.default_font_size = 20
	_root.theme.set_color("font_color","Label",CREAM)
	ThemeRules.install_buttons(_root.theme)
	add_child(_root)
	var background := ColorRect.new()
	background.color = Color("123936")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(background)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_margin)
	_layout = VBoxContainer.new()
	_layout.add_theme_constant_override("separation",14)
	_margin.add_child(_layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",14)
	_layout.add_child(header)
	var back := Button.new()
	back.text = "← Back"
	back.custom_minimum_size = Vector2(92,52)
	ThemeRules.danger(back)
	back.pressed.connect(func(): closed.emit())
	header.add_child(back)
	var title := Label.new()
	title.text = "Play with a friend"
	title.add_theme_font_override("font",heading_font)
	title.add_theme_font_size_override("font_size",38)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation",10)
	_layout.add_child(_tabs)
	for tab_name: String in ["Your rooms","Friends","Completed"]:
		var tab_button := Button.new()
		tab_button.text = tab_name
		tab_button.custom_minimum_size = Vector2(130,50)
		ThemeRules.secondary(tab_button)
		tab_button.pressed.connect(func(): _select_tab(tab_name))
		_tabs.add_child(tab_button)
	_body = GridContainer.new()
	_body.columns = 2
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation",22)
	_layout.add_child(_body)
	_rooms_column = VBoxContainer.new()
	_rooms_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_column.size_flags_stretch_ratio = 1.25
	_rooms_column.add_theme_constant_override("separation",10)
	_body.add_child(_rooms_column)
	_notice = Label.new()
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.add_theme_color_override("font_color",MUTED)
	_rooms_column.add_child(_notice)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rooms_column.add_child(scroll)
	_rooms_list = VBoxContainer.new()
	_rooms_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_list.add_theme_constant_override("separation",10)
	scroll.add_child(_rooms_list)
	_right_column = VBoxContainer.new()
	_right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_column.size_flags_stretch_ratio = 0.9
	_right_column.add_theme_constant_override("separation",12)
	_body.add_child(_right_column)
	_build_host_panel(heading_font)
	get_viewport().size_changed.connect(_layout_safe_area)
	_layout_safe_area()
	_render()

func _build_host_panel(heading_font: FontVariation) -> void:
	var panel := _panel()
	_right_column.add_child(panel)
	var title := Label.new()
	title.text = "Start another journey"
	title.add_theme_font_override("font",heading_font)
	title.add_theme_font_size_override("font_size",28)
	panel.add_child(title)
	_chapter_picker = OptionButton.new()
	_chapter_picker.custom_minimum_size.y = 50
	_chapter_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for chapter: Dictionary in chapters: _chapter_picker.add_item(str(chapter.get("title",chapter.get("key","Chapter"))))
	_chapter_picker.item_selected.connect(_chapter_selected)
	panel.add_child(_chapter_picker)
	var visibility_row := HBoxContainer.new()
	visibility_row.add_theme_constant_override("separation",8)
	panel.add_child(visibility_row)
	for option: String in ["Friends","Invitation only"]:
		var button := Button.new()
		button.text = option
		button.custom_minimum_size = Vector2(0,50)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeRules.secondary(button)
		button.pressed.connect(func(): _set_visibility(option))
		visibility_row.add_child(button)
	var host := Button.new()
	host.text = "Host a room"
	host.custom_minimum_size.y = 54
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.pressed.connect(_request_host)
	panel.add_child(host)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation",8)
	_right_column.add_child(join_row)
	_join_code = LineEdit.new()
	_join_code.placeholder_text = "Invitation code"
	_join_code.custom_minimum_size.y = 50
	_join_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_join_code)
	var join := Button.new()
	join.text = "Join"
	join.custom_minimum_size = Vector2(96,50)
	join.pressed.connect(func():
		var code := _join_code.text.strip_edges().to_upper()
		if not code.is_empty(): join_code_requested.emit(code)
	)
	join_row.add_child(join)

func _layout_safe_area() -> void:
	if not is_instance_valid(_margin): return
	var rect := get_viewport().get_visible_rect()
	var safe := rect
	if OS.has_feature("android"):
		safe = SafeArea.viewport_rect(Rect2(DisplayServer.get_display_safe_area()),get_viewport().get_screen_transform(),rect)
	var compact := safe.size.x < 1050
	var stacked := safe.size.x < 820
	_compact = compact
	_stacked = stacked
	_body.columns = 1 if stacked else 2
	_body.add_theme_constant_override("separation",12 if compact else 22)
	var side := maxi(18,int((safe.size.x-1480)*0.5))
	_margin.add_theme_constant_override("margin_left",int(safe.position.x)+side)
	_margin.add_theme_constant_override("margin_right",int(rect.end.x-safe.end.x)+side)
	_margin.add_theme_constant_override("margin_top",int(safe.position.y)+12)
	_margin.add_theme_constant_override("margin_bottom",int(rect.end.y-safe.end.y)+12)

func set_client(value: RefCounted) -> void:
	client = value
	_render()

func set_chapters(value: Array[Dictionary]) -> void:
	chapters = value.duplicate(true)
	if is_instance_valid(_chapter_picker):
		_chapter_picker.clear()
		for chapter: Dictionary in chapters: _chapter_picker.add_item(str(chapter.get("title",chapter.get("key","Chapter"))))

func refresh() -> void:
	if client == null or _busy: return
	_busy = true
	await client.refresh()
	_busy = false
	_render()

## Caller invokes this after the selected room reports successful render.
func confirm_room_rendered(api_version: int, room_id: String) -> bool:
	if client == null: return false
	var confirmed: bool = client.confirm_room_rendered(api_version,room_id)
	if confirmed: _render()
	return confirmed

func _select_tab(value: String) -> void:
	_tab = value
	_render()
	if value == "Friends": friends_requested.emit()

func _render() -> void:
	if not is_instance_valid(_rooms_list): return
	for child: Node in _rooms_list.get_children(): child.queue_free()
	var state: Dictionary = client.view() if client != null else {"rooms":[],"stale":true,"error":"Rooms unavailable"}
	var rooms: Array = state.get("rooms",[])
	var filtered: Array[Dictionary] = []
	for value: Variant in rooms:
		if not value is Dictionary: continue
		var completed: bool = value.get("status") == "completed"
		if (_tab == "Completed" and completed) or (_tab == "Your rooms" and not completed): filtered.append(value)
	_visible_rooms = filtered
	_notice.text = ("Showing saved rooms while offline" if state.get("stale",true) and not rooms.is_empty() else str(state.get("error","")) if state.get("stale",true) else "")
	_notice.visible = not _notice.text.is_empty()
	if _tab == "Friends":
		var explainer := Label.new()
		explainer.text = "See your friends and their rooms."
		explainer.add_theme_color_override("font_color",MUTED)
		_rooms_list.add_child(explainer)
		var open := Button.new()
		open.text = "Open friends"
		open.custom_minimum_size.y = 52
		open.pressed.connect(func(): friends_requested.emit())
		_rooms_list.add_child(open)
	elif filtered.is_empty():
		var empty := Label.new()
		empty.text = "No completed rooms yet." if _tab == "Completed" else "Your rooms will appear here."
		empty.add_theme_color_override("font_color",MUTED)
		_rooms_list.add_child(empty)
	else:
		for room: Dictionary in filtered: _add_room_card(room)
	_right_column.visible = true
	_tabs.get_child(0).text = "Your rooms · %d" % filtered.size() if _tab == "Your rooms" else "Your rooms"

func _add_room_card(room: Dictionary) -> void:
	var card := _panel()
	card.add_theme_constant_override("separation",10)
	_rooms_list.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	card.add_child(row)
	var texture: Variant = thumbnail_for.call(str(room.chapter_key)) if thumbnail_for.is_valid() else _catalog_thumbnail(str(room.chapter_key))
	if texture is String: texture = load(texture)
	if texture is Texture2D:
		var image := TextureRect.new()
		image.texture = texture
		image.custom_minimum_size = Vector2(154,96)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		row.add_child(image)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation",2)
	row.add_child(details)
	var heading := Label.new()
	heading.text = str(room.get("chapter_title","A journey"))
	heading.add_theme_font_size_override("font_size",24)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(heading)
	var names: Array[String] = []
	for member: String in room.get("member_ids",[]):
		names.append(str(display_name.call(member)) if display_name.is_valid() else member)
	var participant_line := " · ".join(names)
	var part_label := Label.new()
	part_label.text = participant_line
	part_label.add_theme_color_override("font_color",MUTED)
	details.add_child(part_label)
	var status := str(room.get("status","unavailable"))
	var state_label := Label.new()
	state_label.text = _status_label(status)
	state_label.add_theme_color_override("font_color",Color("a6d9c4"))
	details.add_child(state_label)
	var action := Button.new()
	action.text = "Watch replay" if status == "completed" else "Continue" if status == "your_turn" else "Open"
	action.custom_minimum_size = Vector2(132,50)
	action.disabled = status == "unavailable"
	ThemeRules.secondary(action)
	action.pressed.connect(func(): room_open_requested.emit(room.duplicate(true)))
	row.add_child(action)
	if client != null and client.unread(room):
		var unread_badge := Label.new()
		unread_badge.text = "•"
		unread_badge.add_theme_color_override("font_color",Color("f4d77b"))
		unread_badge.add_theme_font_size_override("font_size",28)
		row.add_child(unread_badge)

func _catalog_thumbnail(chapter_key: String) -> Variant:
	# Loaded by resource path to keep this view usable while the catalog asset
	# package is integrated; catalog owns the chapter-to-thumbnail mapping.
	var script: Script = load("res://services/chapter_thumbnail_catalog.gd")
	if script == null: return null
	return script.path(chapter_key)

func _request_host() -> void:
	if chapters.is_empty() or not is_instance_valid(_chapter_picker): return
	var index := _chapter_picker.selected
	if index < 0 or index >= chapters.size(): return
	var chapter_key := str(chapters[index].get("key",""))
	if not chapter_key.is_empty(): host_requested.emit(chapter_key,_visibility)

func _chapter_selected(index: int) -> void:
	if index >= 0 and index < chapters.size(): chapter_picked.emit(str(chapters[index].get("key","")))

func _set_visibility(value: String) -> void:
	_visibility = "invitation_only" if value == "Invitation only" else "friends"

func _status_label(value: String) -> String:
	match value:
		"your_turn": return "Your turn"
		"waiting_for_their_turn": return "Waiting for their turn"
		"waiting_for_friend": return "Waiting for a friend"
		"completed": return "Completed"
		_: return "Unavailable"

func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(16)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel",style)
	return panel

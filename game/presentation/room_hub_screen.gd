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
var _body: BoxContainer
var _rooms_column: VBoxContainer
var _right_scroll: ScrollContainer
var _right_column: VBoxContainer
var _rooms_scroll: ScrollContainer
var _rooms_list: VBoxContainer
var _tabs: HBoxContainer
var _notice: Label
var _footer: Label
var _heading_font: FontVariation
var _chapter_picker: OptionButton
var _join_code: LineEdit
var _join: Button
var _hero: TextureRect
var _hero_title: Label
var _tab_buttons: Dictionary = {}
var _visibility_buttons: Dictionary = {}
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
	_heading_font = heading_font
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
	back.text = "Back"
	back.custom_minimum_size = Vector2(0,52)
	ThemeRules.danger(back,preload("res://assets/ui/back.svg"))
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
		tab_button.pressed.connect(func(): _select_tab(tab_name))
		_tabs.add_child(tab_button)
		_tab_buttons[tab_name] = tab_button
	_style_tabs()
	# Each column scrolls on its own; the body itself never scrolls.
	_body = BoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation",22)
	_layout.add_child(_body)
	_rooms_column = VBoxContainer.new()
	_rooms_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rooms_column.size_flags_stretch_ratio = 1.25
	_rooms_column.add_theme_constant_override("separation",10)
	_body.add_child(_rooms_column)
	_notice = Label.new()
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.add_theme_color_override("font_color",MUTED)
	_rooms_column.add_child(_notice)
	_rooms_scroll = ScrollContainer.new()
	_rooms_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rooms_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rooms_scroll.follow_focus = true
	_rooms_scroll.add_theme_constant_override("scrollbar_v_separation",6)
	ThemeRules.touch_scroll(_rooms_scroll)
	_rooms_column.add_child(_rooms_scroll)
	_rooms_list = VBoxContainer.new()
	_rooms_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_list.add_theme_constant_override("separation",10)
	_rooms_scroll.add_child(_rooms_list)
	_footer = Label.new()
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.add_theme_color_override("font_color",Color("f4d77b"))
	_footer.visible = false
	_rooms_column.add_child(_footer)
	_right_scroll = ScrollContainer.new()
	_right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_scroll.size_flags_stretch_ratio = 0.9
	_right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_right_scroll.follow_focus = true
	# Host controls and the chapter picker pass drags to this column too.
	ThemeRules.touch_scroll(_right_scroll)
	_body.add_child(_right_scroll)
	_right_column = VBoxContainer.new()
	_right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_column.add_theme_constant_override("separation",12)
	_right_scroll.add_child(_right_column)
	_build_host_panel(heading_font)
	get_viewport().size_changed.connect(_layout_safe_area)
	_layout_safe_area()
	_render()

func _build_host_panel(heading_font: FontVariation) -> void:
	var panel := _panel()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_right_column.add_child(panel)
	# PanelContainer overlaps its children, so stack the host controls in a box.
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Start another journey"
	title.add_theme_font_override("font",heading_font)
	title.add_theme_font_size_override("font_size",28)
	box.add_child(title)
	_hero = TextureRect.new()
	_hero.custom_minimum_size = Vector2(0,150)
	# Keep the chapter picture at a steady 2.4:1 so the whole island arrangement
	# stays visible instead of a thin, cropped strip of scenery.
	_hero.resized.connect(_fit_hero)
	_right_scroll.resized.connect(_fit_hero)
	_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_hero)
	_hero_title = Label.new()
	_hero_title.add_theme_font_override("font",heading_font)
	_hero_title.add_theme_font_size_override("font_size",24)
	_hero_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# The chapter picker right below already names the selection.
	_hero_title.visible = false
	box.add_child(_hero_title)
	_chapter_picker = OptionButton.new()
	_chapter_picker.custom_minimum_size.y = 50
	_chapter_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for chapter: Dictionary in chapters: _chapter_picker.add_item(str(chapter.get("title",chapter.get("key","Chapter"))))
	_chapter_picker.item_selected.connect(_chapter_selected)
	ThemeRules.secondary(_chapter_picker)
	box.add_child(_chapter_picker)
	var visibility_row := HBoxContainer.new()
	visibility_row.add_theme_constant_override("separation",8)
	box.add_child(visibility_row)
	for option: String in ["Friends","Invitation only"]:
		var button := Button.new()
		button.text = option
		button.custom_minimum_size = Vector2(0,50)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): _set_visibility(option))
		visibility_row.add_child(button)
		_visibility_buttons[option] = button
	_style_visibility()
	_update_hero()
	var host := Button.new()
	host.text = "Host a room"
	host.custom_minimum_size.y = 54
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.pressed.connect(_request_host)
	box.add_child(host)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation",8)
	_right_column.add_child(join_row)
	_join_code = LineEdit.new()
	_join_code.placeholder_text = "Invitation code"
	for field_state: String in ["normal","focus"]:
		var field_style := ThemeRules.padded(ThemeRules.rounded(Color("112c29"),12,Color("a6d9c4") if field_state == "focus" else Color("466e63")),16.0,10.0)
		_join_code.add_theme_stylebox_override(field_state,field_style)
	_join_code.custom_minimum_size.y = 50
	_join_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_join_code)
	_join = Button.new()
	_join.text = "Join"
	_join.custom_minimum_size = Vector2(96,50)
	_secondary(_join)
	_join.pressed.connect(func():
		var code := _join_code.text.strip_edges().to_upper()
		if not code.is_empty(): join_code_requested.emit(code)
	)
	join_row.add_child(_join)
	_join_code.text_changed.connect(func(_text: String): _update_join())
	_update_join()

func _update_join() -> void:
	if is_instance_valid(_join) and is_instance_valid(_join_code): _join.disabled = _join_code.text.strip_edges().is_empty()

func _secondary(button: Button) -> void:
	ThemeRules.secondary(button)
	button.add_theme_stylebox_override("disabled",ThemeRules.padded(ThemeRules.rounded(Color("203f39"),14,Color("54766a"))))
	button.add_theme_color_override("font_disabled_color",Color("9aaaa3"))

func _fit_hero() -> void:
	# Shortened only when the host column would not otherwise fit its height.
	if not is_instance_valid(_hero) or not is_instance_valid(_right_scroll): return
	var target := roundf(_hero.size.x / 2.4)
	if _right_scroll.size.y > 0.0:
		var others := _right_column.get_combined_minimum_size().y - _hero.custom_minimum_size.y
		target = minf(target,_right_scroll.size.y - others)
	_hero.custom_minimum_size.y = clampf(target,110.0,220.0)

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
	_body.vertical = stacked
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
		_update_hero()

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
	_style_tabs()
	_render()
	if value == "Friends": friends_requested.emit()

func _style_tabs() -> void:
	for tab_name: Variant in _tab_buttons:
		var button: Button = _tab_buttons[tab_name]
		_clear_button_style(button)
		if tab_name == _tab: ThemeRules.selected_tab(button)
		else: ThemeRules.plain_tab(button)

func _style_visibility() -> void:
	for option: Variant in _visibility_buttons:
		var button: Button = _visibility_buttons[option]
		var selected := _visibility == ("invitation_only" if option == "Invitation only" else "friends")
		_clear_button_style(button)
		if selected: ThemeRules.selected_tab(button)
		else: ThemeRules.secondary(button)

func _clear_button_style(button: Button) -> void:
	for state: String in ["normal","hover","pressed","hover_pressed","disabled"]:
		button.remove_theme_stylebox_override(state)
	for key: String in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color","font_disabled_color","icon_normal_color","icon_disabled_color"]:
		button.remove_theme_color_override(key)

func _update_hero() -> void:
	if not is_instance_valid(_hero) or chapters.is_empty() or not is_instance_valid(_chapter_picker): return
	var index := clampi(_chapter_picker.selected,0,chapters.size()-1)
	var chapter: Dictionary = chapters[index]
	_hero_title.text = str(chapter.get("title",chapter.get("key","Chapter")))
	var texture: Variant = thumbnail_for.call(str(chapter.get("key",""))) if thumbnail_for.is_valid() else _catalog_thumbnail(str(chapter.get("key","")))
	if texture is String: texture = load(texture) if not (texture as String).is_empty() else null
	_hero.texture = texture if texture is Texture2D else null

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
	_notice.text = ("Displaying saved rooms when offline" if state.get("stale",true) and not rooms.is_empty() else str(state.get("error","")) if state.get("stale",true) else "")
	_notice.visible = not _notice.text.is_empty()
	if _tab == "Friends":
		var explainer := Label.new()
		explainer.text = "Visit friends and their rooms."
		explainer.add_theme_color_override("font_color",MUTED)
		_rooms_list.add_child(explainer)
		var open := Button.new()
		open.text = "Open friends"
		open.custom_minimum_size.y = 52
		open.pressed.connect(func(): friends_requested.emit())
		_rooms_list.add_child(open)
	elif filtered.is_empty():
		var empty := Label.new()
		empty.text = "No rooms completed." if _tab == "Completed" else "Your rooms will be listed here."
		empty.add_theme_color_override("font_color",MUTED)
		_rooms_list.add_child(empty)
	else:
		for room: Dictionary in filtered: _add_room_card(room)
	_right_column.visible = true
	var active_count := 0
	for value: Variant in rooms:
		if value is Dictionary and value.get("status") != "completed": active_count += 1
	_tab_buttons["Your rooms"].text = "Your rooms · %d" % active_count
	_update_footer(rooms)

func _update_footer(rooms: Array) -> void:
	if not is_instance_valid(_footer): return
	var unread_count := 0
	for value: Variant in rooms:
		if value is Dictionary and client != null and client.unread(value): unread_count += 1
	if unread_count <= 0:
		_footer.visible = false
		return
	# Mirrors the concept footer, e.g. "2 rooms have new activity".
	_footer.text = "%d %s %s new activity" % [unread_count,"room" if unread_count == 1 else "rooms","has" if unread_count == 1 else "have"]
	_footer.visible = true

func _add_room_card(room: Dictionary) -> void:
	var card := _panel()
	card.mouse_filter = Control.MOUSE_FILTER_PASS
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
	details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	details.add_theme_constant_override("separation",4)
	row.add_child(details)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation",10)
	details.add_child(title_row)
	var heading := Label.new()
	heading.text = str(room.get("chapter_title","A journey"))
	if _heading_font != null: heading.add_theme_font_override("font",_heading_font)
	heading.add_theme_font_size_override("font_size",24)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(heading)
	# The unread dot stays inside the details column so every action lines up.
	if client != null and client.unread(room):
		var unread_dot := Panel.new()
		unread_dot.custom_minimum_size = Vector2(10,10)
		unread_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		unread_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		unread_dot.add_theme_stylebox_override("panel",ThemeRules.rounded(Color("f4d77b"),5))
		title_row.add_child(unread_dot)
	var meta: Array[String] = []
	var names: Array[String] = []
	for member: String in room.get("member_ids",[]):
		var shown := str(display_name.call(member)) if display_name.is_valid() else member
		# The display-name hook returns an empty string for the local player.
		if not shown.is_empty(): names.append(shown)
	if not names.is_empty(): meta.append(" · ".join(names))
	var part := _part_line(room)
	if not part.is_empty(): meta.append(part)
	var meta_label := Label.new()
	meta_label.text = " · ".join(meta)
	meta_label.add_theme_color_override("font_color",MUTED)
	meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta_label.visible = not meta.is_empty()
	details.add_child(meta_label)
	var status := str(room.get("status","unavailable"))
	details.add_child(_status_chip(status))
	var action := Button.new()
	action.text = "Watch replay" if status == "completed" else "Continue" if status == "your_turn" else "Open"
	action.custom_minimum_size = Vector2(132,50)
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	action.mouse_filter = Control.MOUSE_FILTER_PASS
	action.disabled = status in ["unavailable","offline"]
	# Your turn is the dominant call to action, so it keeps the cream primary
	# fill; every other room offers an outlined secondary Open/Watch.
	if status != "your_turn": _secondary(action)
	action.pressed.connect(func(): room_open_requested.emit(room.duplicate(true)))
	row.add_child(action)

func _status_chip(status: String) -> PanelContainer:
	var turn := status == "your_turn"
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.add_theme_stylebox_override("panel",ThemeRules.padded(ThemeRules.rounded(Color("2f5d52") if turn else Color("234c44"),9,Color("6f9a8c") if turn else Color.TRANSPARENT),10.0,3.0))
	var label := Label.new()
	label.text = _status_label(status)
	label.add_theme_font_size_override("font_size",18)
	label.add_theme_color_override("font_color",CREAM if turn else Color("a6d9c4"))
	chip.add_child(label)
	return chip

func _part_line(room: Dictionary) -> String:
	# Show stage progress when the room (or local history) carries it, matching
	# the "Part x / y" line in the concept. Avoid inventing numbers otherwise.
	var total := 0
	for chapter: Dictionary in chapters:
		if str(chapter.get("key","")) == str(room.get("chapter_key","")): total = int(chapter.get("stage_count",0))
	var part: int = int(room.get("part",0))
	if part <= 0 and room.has("stage_index"): part = int(room.get("stage_index",0)) + 1
	if total <= 0: total = int(room.get("stage_count",0))
	if part <= 0 or total <= 0: return ""
	return "Part %d / %d" % [part,total]

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
	_update_hero()
	if index >= 0 and index < chapters.size(): chapter_picked.emit(str(chapters[index].get("key","")))

func _set_visibility(value: String) -> void:
	_visibility = "invitation_only" if value == "Invitation only" else "friends"
	_style_visibility()

func _status_label(value: String) -> String:
	match value:
		"your_turn": return "Your turn"
		"waiting_for_their_turn": return "Waiting for their turn"
		"waiting_for_friend": return "Waiting for a friend"
		"completed": return "Completed"
		"offline": return "Offline"
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

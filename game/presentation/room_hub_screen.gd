extends CanvasLayer
## Room hub presentation. Requests are emitted to the app; this screen never
## creates a room, polls a server, or marks activity seen during an open tap.
const SafeArea = preload("res://presentation/safe_area.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const InboxClient = preload("res://services/room_inbox_client.gd")
const ShareCodes = preload("res://services/share_codes.gd")
const ChapterPicker = preload("res://presentation/chapter_picker.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const Purchases = preload("res://services/purchases.gd")
const TouchInput = preload("res://presentation/touch_input.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const REMOVE_ICON = preload("res://assets/ui/social/trash.svg")
## Rooms still in play; closing one ends it for both members.
const ACTIVE_STATUSES := ["waiting_for_friend","your_turn","waiting_for_their_turn"]
const CREAM := Color("eceddb")
const MUTED := Color("afc6be")
const PANEL := Color("173f39")
const SURFACE := Color("1b4941")
signal closed
## Taps pass the control they came from, so the app's busy-tap gate can label it.
signal room_open_requested(room: Dictionary, source: Control)
signal host_requested(chapter_key: String, visibility: String, source: Control)
signal chapter_picked(chapter_key: String)
signal visibility_picked(visibility: String)
signal join_code_requested(code: String, source: Control)
signal friends_requested(source: Control)
## A chapter locked until this build accepts a tester code was chosen or hosted.
signal tester_code_requested
## "lobby" retries a held create or join request, "redo" reopens the room with
## an unfinished redo request.
signal retry_requested(kind: String)
## After the player confirms: "close" ends a room still in play for both
## members, "leave" drops a room the other member closed, "leave_finished"
## leaves a finished room on the server (the friend keeps it), and "hide" takes
## a finished or unavailable room off this device's list.
signal room_remove_requested(room: Dictionary, action: String)
## The room cards were rebuilt (a refresh landed); a tap still waiting moves its
## label onto the new copy of its control (room_action).
signal cards_redrawn

var client: RefCounted
var chapters: Array[Dictionary] = []
var display_name: Callable
var thumbnail_for: Callable
## ChapterCompletion.chapters() for the friend marks on the chapter picker.
var completion_marks: Dictionary = {}
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
var _chapter_choice: Button
var _host_note: Label
var _host: Button
var _selected_key := ""
var _picker_page: VBoxContainer
var _picker: ChapterPicker
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
var _message := ""
var _held := ""
var _held_panel: PanelContainer
var _modal: Control
var _removing := false
## The server lets a member leave a finished room (capability room_leave_version).
var _leave_finished := false
## What the room cards were last drawn from; a refresh that changes nothing
## keeps the same cards, so a finger already on one still taps it.
var _rooms_drawn := 0
## Each drawn room card's Open, Continue or Watch replay button, by room id.
var _room_actions: Dictionary = {}
var _rooms_waiting := false

func _ready() -> void:
	layer = 60
	set_process(false)
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
		# Same yellow dot as the room cards, pinned to the tab's top-right corner.
		var tab_dot := Panel.new()
		tab_dot.name = "UnreadDot"
		tab_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab_dot.add_theme_stylebox_override("panel",ThemeRules.rounded(Color("f4d77b"),5))
		tab_dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		tab_dot.position = Vector2(-16,6)
		tab_dot.size = Vector2(10,10)
		tab_dot.visible = false
		tab_button.add_child(tab_dot)
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
	_build_held_panel()
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
	# The chapter button right below already names the selection.
	_hero_title.visible = false
	box.add_child(_hero_title)
	# Opens the same chapter picker as Play Solo, as a page over the hub.
	_chapter_choice = ChapterPicker.chooser("")
	_chapter_choice.pressed.connect(open_chapter_picker)
	box.add_child(_chapter_choice)
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
	# Why the chosen chapter cannot be hosted yet, when a tester code would open it.
	_host_note = Label.new()
	_host_note.name = "HostLockNote"
	_host_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_host_note.add_theme_color_override("font_color",MUTED)
	_host_note.visible = false
	box.add_child(_host_note)
	_host = Button.new()
	_host.name = "HostRoom"
	_host.text = "Host a room"
	_host.custom_minimum_size.y = 54
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.pressed.connect(_request_host)
	box.add_child(_host)
	_update_hero()
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation",8)
	_right_column.add_child(join_row)
	_join_code = LineEdit.new()
	_join_code.placeholder_text = "Invitation code"
	_join_code.max_length = ShareCodes.MAX_INPUT
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
		# The receiver parses room-<code>, legacy and link input; friend IDs are case-sensitive.
		var code := _join_code.text.strip_edges()
		if not code.is_empty(): join_code_requested.emit(code, _join)
	)
	join_row.add_child(_join)
	_join_code.text_changed.connect(func(_text: String): _update_join())
	_update_join()

func _build_held_panel() -> void:
	_held_panel = _panel()
	_held_panel.name = "HeldRequest"
	_held_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_right_column.add_child(_held_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",10)
	_held_panel.add_child(box)
	var text := Label.new()
	text.text = "Complete the saved request before entering another room."
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_color_override("font_color",MUTED)
	box.add_child(text)
	var retry := Button.new()
	retry.name = "RetryHeld"
	retry.custom_minimum_size.y = 52
	retry.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	retry.pressed.connect(func(): if not _held.is_empty(): retry_requested.emit(_held))
	box.add_child(retry)
	_update_held()

## Shows the retry for a held request; an empty kind hides it.
func set_held_request(kind: String) -> void:
	_held = kind if kind in ["lobby","redo"] else ""
	_update_held()

func _update_held() -> void:
	if not is_instance_valid(_held_panel): return
	_held_panel.visible = not _held.is_empty()
	var retry := _held_panel.find_child("RetryHeld",true,false) as Button
	retry.text = "Retry saved create / join request" if _held == "lobby" else "Retry request"
	retry.tooltip_text = retry.text

## A message above the room list, kept until the hub closes, a new one
## replaces it or the next tap starts (room_hub_flow.gd _tap).
func show_notice(text: String) -> void:
	_message = text
	_render()

## Android Back and Escape: the chapter picker handles its own Back, so this
## closes the hub only when nothing is open on top of it.
func go_back() -> void:
	if is_instance_valid(_modal):
		_modal.close()
		return
	if is_instance_valid(_picker_page) and _picker_page.visible: return
	closed.emit()

## True while the app closes or removes a room; the remove buttons wait.
func set_removing(value: bool) -> void:
	_removing = value
	_render()

## Whether finished rooms offer Leave room in place of Remove from list.
func set_leave_finished(value: bool) -> void:
	if value == _leave_finished: return
	_leave_finished = value
	_render()

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
	if SafeArea.applies():
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
	if is_instance_valid(_picker): _picker.refit()

func set_client(value: RefCounted) -> void:
	client = value
	_render()

func set_chapters(value: Array[Dictionary]) -> void:
	chapters = value.duplicate(true)
	# Keep the current choice while it is still offered.
	if _chapter_index(_selected_key) < 0: _selected_key = str(chapters[0].get("key","")) if not chapters.is_empty() else ""
	_update_hero()
	if is_instance_valid(_picker) and _picker_page.visible: _fill_picker()

## The player's last choice, kept by Main across hub rebuilds. Call before
## set_chapters; a chapter no longer offered falls back to the first one.
func restore_choice(key: String, visibility: String) -> void:
	_selected_key = key
	_visibility = "invitation_only" if visibility == "invitation_only" else "friends"

## The selected chapter's key; Host a room hosts this chapter.
func selected_key() -> String:
	return _selected_key

## Shows the shared chapter picker in place of the hub, at the current choice.
func open_chapter_picker() -> void:
	if chapters.is_empty() or not is_instance_valid(_margin): return
	if not is_instance_valid(_picker_page): _build_picker_page()
	_layout.visible = false
	_picker_page.visible = true
	_fill_picker()
	_picker.reveal(_selected_key)

## Returns to the hub without changing the choice.
func close_chapter_picker() -> void:
	if not is_instance_valid(_picker_page) or not _picker_page.visible: return
	var focus := get_viewport().gui_get_focus_owner()
	_picker_page.visible = false
	_layout.visible = true
	if focus != null and _picker_page.is_ancestor_of(focus): _chapter_choice.grab_focus()

func _build_picker_page() -> void:
	_picker_page = VBoxContainer.new()
	_picker_page.name = "ChapterPickerPage"
	_picker_page.add_theme_constant_override("separation",14)
	_picker_page.visible = false
	_margin.add_child(_picker_page)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",14)
	_picker_page.add_child(header)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0,52)
	ThemeRules.danger(back,preload("res://assets/ui/back.svg"))
	back.pressed.connect(close_chapter_picker)
	header.add_child(back)
	var title := Label.new()
	title.text = "Start another journey"
	title.add_theme_font_override("font",_heading_font)
	title.add_theme_font_size_override("font_size",38)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var picker := ChapterPicker.new()
	picker.variant = "friend"
	picker.action_name = "Host a room"
	picker.action_chevron = true
	picker.back_enabled = true
	picker.heading_font = _heading_font
	picker.available_width = _page_width
	picker.chosen.connect(_choose_chapter)
	picker.back_requested.connect(close_chapter_picker)
	_picker_page.add_child(picker)
	_picker = picker

func _page_width() -> float:
	# The window never grows with the grid, unlike the margin around it.
	return get_viewport().get_visible_rect().size.x-float(_margin.get_theme_constant("margin_left")+_margin.get_theme_constant("margin_right"))

func _fill_picker() -> void:
	# Built once per chapter list and picture size; reopening reuses the cards.
	_picker.set_entries(chapters,ChapterPicker.picture_for(_page_width()))
	_picker.refresh_marks(completion_marks)

func _choose_chapter(key: String) -> void:
	if _chapter_index(key) < 0: return
	if _needs_tester_code(key):
		close_chapter_picker()
		tester_code_requested.emit()
		return
	_selected_key = key
	_update_hero()
	chapter_picked.emit(key)
	close_chapter_picker()

## True when hosting `key` waits only for a tester code on this build.
func _needs_tester_code(key: String) -> bool:
	var index := _chapter_index(key)
	return index >= 0 and chapters[index].get("lock_reason","") == Purchases.HOSTING_NEEDS_TESTER_CODE

func _chapter_index(key: String) -> int:
	for index in range(chapters.size()):
		if str(chapters[index].get("key","")) == key: return index
	return -1

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
	if value == "Friends": friends_requested.emit(_tab_buttons.get(value))

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
	if not is_instance_valid(_hero) or chapters.is_empty() or not is_instance_valid(_chapter_choice): return
	var chapter: Dictionary = chapters[maxi(0,_chapter_index(_selected_key))]
	_hero_title.text = str(chapter.get("title",chapter.get("key","Chapter")))
	_chapter_choice.text = _hero_title.text
	var texture: Variant = thumbnail_for.call(str(chapter.get("key",""))) if thumbnail_for.is_valid() else _catalog_thumbnail(str(chapter.get("key","")))
	if texture is String: texture = load(texture) if not (texture as String).is_empty() else null
	_hero.texture = texture if texture is Texture2D else null
	if is_instance_valid(_host):
		var needs_code := _needs_tester_code(str(chapter.get("key","")))
		_host_note.text = str(chapter.get("note","")) if needs_code else ""
		_host_note.visible = needs_code and not _host_note.text.is_empty()
		_host.text = "Tester code" if needs_code else "Host a room"
		# The note changes the column height, so the picture is fitted again.
		_fit_hero.call_deferred()

func _render() -> void:
	if not is_instance_valid(_rooms_list): return
	var state: Dictionary = client.view() if client != null else {"rooms":[],"stale":true,"error":"Rooms unavailable"}
	var rooms: Array = state.get("rooms",[])
	var filtered: Array[Dictionary] = []
	for value: Variant in rooms:
		if not value is Dictionary: continue
		var completed: bool = value.get("status") == "completed"
		if (_tab == "Completed" and completed) or (_tab == "Your rooms" and not completed): filtered.append(value)
	_visible_rooms = filtered
	_draw_room_cards(filtered)
	# A tap's reason sits above the list's own state line, never in place of it.
	var list_state := ("Displaying saved rooms when offline" if not rooms.is_empty() else str(state.get("error",""))) if state.get("stale",true) else ""
	_notice.text = "
".join([_message, list_state].filter(func(line: String) -> bool: return not line.is_empty()))
	_notice.visible = not _notice.text.is_empty()
	_right_column.visible = true
	var active_count := 0
	for value: Variant in rooms:
		if value is Dictionary and value.get("status") != "completed": active_count += 1
	_tab_buttons["Your rooms"].text = "Your rooms · %d" % active_count
	_update_footer(rooms)

## Rebuilds the cards only when what they show has changed, and never while a
## finger is down on one: freeing that button would drop the tap. A rebuild
## held back that way runs on the first frame after the release.
func _draw_room_cards(filtered: Array[Dictionary]) -> void:
	var drawn := _room_cards_key(filtered)
	if drawn == _rooms_drawn and _rooms_list.get_child_count() > 0:
		_rooms_waiting = false
		return
	if TouchInput.press_held(_rooms_list):
		_rooms_waiting = true
		set_process(true)
		return
	_rooms_waiting = false
	_rooms_drawn = drawn
	_room_actions.clear()
	for child: Node in _rooms_list.get_children():
		_rooms_list.remove_child(child)
		child.queue_free()
	if _tab == "Friends":
		var explainer := Label.new()
		explainer.text = "Visit friends and their rooms."
		explainer.add_theme_color_override("font_color",MUTED)
		_rooms_list.add_child(explainer)
		var open := Button.new()
		open.text = "Open friends"
		open.custom_minimum_size.y = 52
		open.pressed.connect(func(): friends_requested.emit(open))
		_rooms_list.add_child(open)
	elif filtered.is_empty():
		var empty := Label.new()
		empty.text = "No rooms completed." if _tab == "Completed" else "Your rooms will be listed here."
		empty.add_theme_color_override("font_color",MUTED)
		_rooms_list.add_child(empty)
	else:
		for room: Dictionary in filtered: _add_room_card(room)
	cards_redrawn.emit()

## The drawn card's action button for a room, or null.
func room_action(room_id: String) -> Button:
	var found: Variant = _room_actions.get(room_id)
	return found if is_instance_valid(found) else null

func _room_cards_key(filtered: Array[Dictionary]) -> int:
	var parts: Array = [_tab, _removing, client == null]
	for room: Dictionary in filtered:
		var names: Array[String] = []
		for member: Variant in room.get("member_ids",[]):
			names.append(str(display_name.call(str(member))) if display_name.is_valid() else "")
		parts.append([room, client != null and client.unread(room), _removal(room), names])
	return hash(parts)

func _process(_delta: float) -> void:
	if not _rooms_waiting:
		set_process(false)
	elif not TouchInput.press_held(_rooms_list):
		_render()

func _update_footer(rooms: Array) -> void:
	if not is_instance_valid(_footer): return
	var unread_count := 0
	var active_unread := false
	var completed_unread := false
	# The footer counts every unread room; each tab's dot shows where they are.
	for value: Variant in rooms:
		if not value is Dictionary or client == null or not client.unread(value): continue
		unread_count += 1
		if value.get("status") == "completed": completed_unread = true
		else: active_unread = true
	_set_tab_dot("Your rooms",active_unread)
	_set_tab_dot("Completed",completed_unread)
	if unread_count <= 0:
		_footer.visible = false
		return
	# Mirrors the concept footer, e.g. "2 rooms have new activity".
	_footer.text = "%d %s %s new activity" % [unread_count,"room" if unread_count == 1 else "rooms","has" if unread_count == 1 else "have"]
	_footer.visible = true

func _set_tab_dot(tab_name: String, shown: bool) -> void:
	var button: Button = _tab_buttons.get(tab_name)
	if not is_instance_valid(button): return
	var dot := button.get_node_or_null("UnreadDot") as Control
	if dot != null: dot.visible = shown

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
		# The display-name hook returns an empty string for the local player.
		# Without the hook nobody is named, so a raw player id never shows.
		var shown := str(display_name.call(member)) if display_name.is_valid() else ""
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
	action.disabled = status in ["unavailable","offline","closed"]
	# Your turn is the dominant call to action, so it keeps the cream primary
	# fill; every other room offers an outlined secondary Open/Watch.
	if status != "your_turn": _secondary(action)
	action.pressed.connect(func(): room_open_requested.emit(room.duplicate(true), action))
	_room_actions[str(room.get("room_id",""))] = action
	row.add_child(action)
	var removal := _removal(room)
	if removal.is_empty(): return
	var remove := Button.new()
	remove.name = "RemoveRoom"
	remove.icon = REMOVE_ICON
	remove.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	remove.expand_icon = true
	remove.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	remove.add_theme_constant_override("icon_max_width",22)
	remove.custom_minimum_size = Vector2(50,50)
	remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	remove.mouse_filter = Control.MOUSE_FILTER_PASS
	remove.tooltip_text = _removal_label(removal)
	remove.accessibility_name = remove.tooltip_text
	remove.disabled = _removing
	_secondary(remove)
	# Text padding would shrink the icon to a speck inside a 50px target.
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		if not remove.has_theme_stylebox(state): continue
		var style := remove.get_theme_stylebox(state).duplicate() as StyleBox
		for edge: String in ["left","top","right","bottom"]: style.set("content_margin_"+edge,12)
		remove.add_theme_stylebox_override(state,style)
	remove.pressed.connect(func(): _ask_remove(room.duplicate(true),removal,remove))
	row.add_child(remove)

## "close" for a room still in play, "leave" for one the other member closed,
## "leave_finished" for a finished one while the server offers it, "hide" for
## any other finished or unavailable one, or "" when nothing applies. Every
## action but hide needs the latest server list to have confirmed the room.
func _removal(room: Dictionary) -> String:
	if client == null or not client.has_method("confirmed"): return ""
	var status := str(room.get("status",""))
	var server_room: bool = int(room.get("api_version",0)) in [1,2]
	if status == "completed" and _leave_finished and server_room and client.confirmed(room): return "leave_finished"
	if status in ["completed","unavailable"]: return "hide"
	if not server_room or not client.confirmed(room): return ""
	if status == "closed": return "leave"
	return "close" if status in ACTIVE_STATUSES else ""

func _removal_label(removal: String) -> String:
	match removal:
		"close": return "Close room"
		"leave_finished": return PlayerCopy.ROOM_LEAVE
		_: return "Remove from list"

func _ask_remove(room: Dictionary, removal: String, opener: Control) -> void:
	if _removing or is_instance_valid(_modal): return
	var label := _removal_label(removal)
	var heading := "Close this room?" if removal == "close" else PlayerCopy.ROOM_LEAVE_TITLE if removal == "leave_finished" else "Remove this room?"
	_modal = InGameModal.open(_root,"RoomRemoveModal",heading,str(room.get("chapter_title","")),opener)
	var status := str(room.get("status",""))
	if removal == "leave_finished": _modal.label(PlayerCopy.ROOM_LEAVE_BODY)
	elif removal != "close": _modal.label("Your friend keeps the room and its replay." if status == "completed" else "It only leaves your list.")
	elif status == "waiting_for_friend": _modal.label("Your invitation stops working, and any turn you saved here is deleted. You can't undo this.")
	else: _modal.label("The room closes for both of you, and its saved turns are deleted. You can't undo this.")
	var confirm: Button = _modal.add_actions(label if removal in ["close","leave_finished"] else "Remove",func():
		_modal.close(false)
		room_remove_requested.emit(room,removal))
	confirm.grab_focus()

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
	# A finished room's stage index is past its last stage.
	return "Part %d / %d" % [mini(part,total),total]

func _catalog_thumbnail(chapter_key: String) -> Variant:
	# Loaded by resource path to keep this view usable while the catalog asset
	# package is integrated; catalog owns the chapter-to-thumbnail mapping.
	var script: Script = load("res://services/chapter_thumbnail_catalog.gd")
	if script == null: return null
	return script.path(chapter_key)

func _request_host() -> void:
	if _needs_tester_code(_selected_key): tester_code_requested.emit()
	elif _chapter_index(_selected_key) >= 0: host_requested.emit(_selected_key,_visibility,_host)

func _set_visibility(value: String) -> void:
	_visibility = "invitation_only" if value == "Invitation only" else "friends"
	_style_visibility()
	visibility_picked.emit(_visibility)

func _status_label(value: String) -> String:
	match value:
		"your_turn": return "Your turn"
		"waiting_for_their_turn": return "Waiting for their turn"
		"waiting_for_friend": return "Waiting for a friend"
		"completed": return "Completed"
		"closed": return "Closed"
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

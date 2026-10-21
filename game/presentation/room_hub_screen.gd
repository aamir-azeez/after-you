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
const RoomCardMenu = preload("res://presentation/room_card_menu.gd")
const REMOVE_ICON = preload("res://assets/ui/social/trash.svg")
const MENU_ICON = preload("res://assets/ui/room/dots.svg")
const HIDE_ICON = preload("res://assets/ui/room/eye-off.svg")
const LEAVE_ICON = preload("res://assets/ui/room/door-exit.svg")
const ADD_FRIEND_ICON = preload("res://assets/ui/social/plus.svg")
const REQUESTED_ICON = preload("res://assets/ui/check.svg")
const PHONE_ICON = preload("res://assets/ui/room/phone.svg")
const FOLD_CLOSED_ICON = preload("res://assets/ui/social/chevron-right.svg")
const FOLD_OPEN_ICON = preload("res://assets/ui/social/chevron-down.svg")
const Typed = preload("res://services/typed_values.gd")
const EndReactions = preload("res://presentation/end_reactions.gd")
const HardMode = preload("res://services/hard_mode.gd")
const HardModeView = preload("res://presentation/hard_mode_view.gd")
const WARM := Color("f4d77b")
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
## The Hard chip changed (services/hard_mode.gd): host a hard room.
signal hard_picked(on: bool)
signal join_code_requested(code: String, source: Control)
signal friends_requested(source: Control)
## A chapter locked until this build accepts a tester code was chosen or hosted.
signal tester_code_requested
## "lobby" retries a held create or join request, "redo" reopens the room with
## an unfinished redo request.
signal retry_requested(kind: String)
## "close" ends a room still in play for both members and "leave" drops a room
## the other member closed, both after a confirm step. From a finished room's
## "..." menu, "hide" takes it off this device's list at once, and
## "leave_finished" leaves it on the server after its confirm step.
signal room_remove_requested(room: Dictionary, action: String)
## Show again on a room in the Hidden rooms section.
signal room_show_requested(room: Dictionary)
## "Add friend" picked on a finished room's menu: the room and its partner's id.
signal add_friend_requested(room: Dictionary, partner: String)
## The room cards were rebuilt (a refresh landed); a tap still waiting moves its
## label onto the new copy of its control (room_action).
signal cards_redrawn

var client: RefCounted
var chapters: Array[Dictionary] = []
var display_name: Callable
## (room: Dictionary) -> {"state": PartnerFriends state, "partner": id}: whether
## a finished room's menu offers to add its partner as a friend.
var partner_friend: Callable
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
## Hard rooms: shown once the server says it hosts them, for a chapter whose
## hard play is open.
var _hard_available := false
var _hard_states: Dictionary = {}
var _hard_on := false
var _hard_chip: Button
var _hard_note: Label
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
## The open "..." menu of a finished room card (room_card_menu.gd), if any.
var _menu: CanvasLayer
## Whether the Hidden rooms section is unfolded; folded each time the hub opens.
var _hidden_open := false
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
	# Under a camera cutout too, like every full-screen dim (SafeArea.bleed).
	SafeArea.bleed(background)
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
	# Fills the column, so an empty list's art gets the blank space.
	_rooms_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	SafeArea.watch(self,_layout_safe_area)
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
	var hard_row := HBoxContainer.new()
	hard_row.name = "HardRow"
	hard_row.add_theme_constant_override("separation",12)
	box.add_child(hard_row)
	_hard_chip = HardModeView.chip(_hard_on)
	_hard_chip.toggled.connect(func(on: bool):
		_hard_on = on
		_update_hard()
		hard_picked.emit(on))
	hard_row.add_child(_hard_chip)
	_hard_note = Label.new()
	_hard_note.name = "HardNote"
	_hard_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hard_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hard_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hard_note.add_theme_color_override("font_color",MUTED)
	hard_row.add_child(_hard_note)
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
	if is_instance_valid(_menu) and not _menu.is_closed():
		_menu.close()
		return
	if is_instance_valid(_modal):
		_modal.close()
		return
	if is_instance_valid(_picker_page) and _picker_page.visible: return
	closed.emit()

## True while the app closes or removes a room; the remove buttons wait.
func set_removing(value: bool) -> void:
	_removing = value
	_render()

## Whether a finished room's menu offers Leave room as well as Hide.
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
	var safe := SafeArea.rect(get_viewport())
	var compact := safe.size.x < 1050
	var stacked := safe.size.x < 820
	_compact = compact
	_stacked = stacked
	_body.vertical = stacked
	_body.add_theme_constant_override("separation",12 if compact else 22)
	var side := SafeArea.centred(safe.size.x,1480,18)
	# The hub keeps a phone's height on a tall screen; the chapter picker
	# shares this margin and keeps the full height for more rows.
	var picking := is_instance_valid(_picker_page) and _picker_page.visible
	var tall := 12 if picking else SafeArea.centred(safe.size.y,SafeArea.PAGE_HEIGHT,12)
	SafeArea.pad(_margin,rect,safe,side,tall,side,tall)
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
	_layout_safe_area()
	_fill_picker()
	_picker.reveal(_selected_key)

## Returns to the hub without changing the choice.
func close_chapter_picker() -> void:
	if not is_instance_valid(_picker_page) or not _picker_page.visible: return
	var focus := get_viewport().gui_get_focus_owner()
	_picker_page.visible = false
	_layout.visible = true
	_layout_safe_area()
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
	picker.hard_mode = HardMode.TOGETHER if _hard_available else ""
	picker.hard_states = _hard_states
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

## True while a rooms read is out.
func refreshing() -> bool:
	return _busy

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
		else: ThemeRules.outlined_tab(button)

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
		_update_hard()
		# The note changes the column height, so the picture is fitted again.
		_fit_hero.call_deferred()

## available: the server hosts hard rooms; states: HardMode.states(); on:
## the chip as last chosen.
func set_hard(available: bool, states: Dictionary, on: bool) -> void:
	_hard_available = available
	_hard_states = states.duplicate(true)
	_hard_on = on
	_update_hard()
	if is_instance_valid(_picker):
		_picker.hard_mode = HardMode.TOGETHER if available else ""
		_picker.refresh_hard(_hard_states)

## Whether Host a room hosts a hard room now.
func hard_selected() -> bool:
	return _hard_on and _hard_allowed(_selected_key)

func _hard_allowed(key: String) -> bool:
	return _hard_available and _hard_states.get(key) is Dictionary and str(_hard_states[key].get(HardMode.TOGETHER, HardMode.LOCKED)) != HardMode.LOCKED

func _update_hard() -> void:
	if not is_instance_valid(_hard_chip): return
	var row := _hard_chip.get_parent() as Control
	var offered := _hard_available and _hard_states.has(_selected_key)
	row.visible = offered
	if not offered: return
	var allowed := _hard_allowed(_selected_key)
	_hard_chip.disabled = not allowed
	HardModeView.set_chip(_hard_chip, _hard_on and allowed)
	_hard_note.text = PlayerCopy.HARD_LOCKED_NOTE if not allowed else PlayerCopy.HARD_HOST_NOTE_ON if _hard_on else PlayerCopy.HARD_HOST_NOTE_OFF
	_hard_note.visible = not _hard_note.text.is_empty()

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
	# Only a list that has really loaded is "empty"; before the first fetch it
	# is loading. Offline, or showing saved rooms, the notice above says so.
	var list_status := "ready" if client != null and not state.get("stale",true) else "offline" if not str(state.get("error","")).is_empty() or not rooms.is_empty() else "loading"
	_draw_room_cards(filtered,list_status)
	# A tap's reason sits above the list's own state line, never in place of it.
	var list_state := ("Displaying saved rooms when offline" if not rooms.is_empty() else str(state.get("error",""))) if state.get("stale",true) else ""
	_notice.text = "\n".join([_message, list_state].filter(func(line: String) -> bool: return not line.is_empty()))
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
func _draw_room_cards(filtered: Array[Dictionary], list_status: String) -> void:
	var drawn := _room_cards_key(filtered,list_status)
	if drawn == _rooms_drawn and _rooms_list.get_child_count() > 0:
		_rooms_waiting = false
		return
	if TouchInput.press_held(_rooms_list):
		_rooms_waiting = true
		set_process(true)
		return
	# An open "..." menu holds the cards like a finger does: freeing its button
	# would close it under the player, and the next tap would land on a card.
	# The menu's closed signal draws them once it is gone.
	if room_menu() != null:
		_rooms_waiting = false
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
	elif filtered.is_empty() and not (_tab == "Completed" and not _hidden_rooms().is_empty()):
		# Hidden finished rooms mean something is finished: their section, added
		# below, is the list then, without art saying there is nothing.
		var completed := _tab == "Completed"
		var ready := list_status == "ready"
		var title := (PlayerCopy.EMPTY_COMPLETED_TITLE if completed else PlayerCopy.EMPTY_ROOMS_TITLE) if ready else ""
		var text := (PlayerCopy.EMPTY_COMPLETED_TEXT if completed else PlayerCopy.EMPTY_ROOMS_TEXT) if ready else PlayerCopy.EMPTY_ROOMS_LOADING if list_status == "loading" else ""
		ThemeRules.empty_state(_rooms_list,"rooms_completed" if completed else "rooms",title,text)
	else:
		for room: Dictionary in filtered: _add_room_card(room)
	if _tab == "Completed": _add_hidden_section(_hidden_rooms())
	cards_redrawn.emit()

## The drawn card's action button for a room, or null.
func room_action(room_id: String) -> Button:
	var found: Variant = _room_actions.get(room_id)
	return found if is_instance_valid(found) else null

func _room_cards_key(filtered: Array[Dictionary], list_status: String) -> int:
	var parts: Array = [_tab, _removing, client == null, list_status]
	for room: Dictionary in filtered:
		var names: Array[String] = []
		for member: Variant in room.get("member_ids",[]):
			names.append(str(display_name.call(str(member))) if display_name.is_valid() else "")
		parts.append([room, client != null and client.unread(room), _removal(room), _menu_ids(room), names])
	if _tab == "Completed": parts.append([_hidden_open, _hidden_rooms().map(func(room: Dictionary) -> Array: return [room, _friend(room)])])
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
	details.add_child(_status_line(room, status))
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
	if status == "completed":
		row.add_child(_menu_button(room,action))
		return
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

## The trash button's action on a card that is not finished: "close" for a
## room still in play, "leave" for one the other member closed, "hide" for an
## unavailable one, or "" when nothing applies. Close and leave need the latest
## server list to have confirmed the room. Finished rooms use the "..." menu.
func _removal(room: Dictionary) -> String:
	if client == null or not client.has_method("confirmed"): return ""
	var status := str(room.get("status",""))
	if status == "completed": return ""
	if status == "unavailable": return "hide"
	if Typed.as_int(room.get("api_version")) not in [1,2] or not client.confirmed(room): return ""
	if status == "closed": return "leave"
	return "close" if status in ACTIVE_STATUSES else ""

func _removal_label(removal: String) -> String:
	return "Close room" if removal == "close" else "Remove from list"

## The rows of a finished room's "..." menu: Hide always, and Leave room while
## the server offers it for a room its latest list confirmed.
func _menu_rows(room: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [{"id": "hide", "title": PlayerCopy.ROOM_HIDE, "detail": PlayerCopy.ROOM_HIDE_DETAIL, "icon": HIDE_ICON}]
	if _leave_finished and int(room.get("api_version",0)) in [1,2] and client != null and client.has_method("confirmed") and client.confirmed(room):
		rows.append({"id": "leave_finished", "title": PlayerCopy.ROOM_LEAVE, "detail": PlayerCopy.ROOM_LEAVE_DETAIL, "icon": LEAVE_ICON, "tone": "danger"})
	var partner: Dictionary = partner_friend.call(room) if partner_friend.is_valid() else {}
	match str(partner.get("state", "")):
		"addable": rows.insert(0, {"id": "add_friend", "title": PlayerCopy.ROOM_ADD_FRIEND, "detail": PlayerCopy.ROOM_ADD_FRIEND_DETAIL % _friend(room), "icon": ADD_FRIEND_ICON})
		"requested": rows.insert(0, {"id": "friend_requested", "title": PlayerCopy.ROOM_FRIEND_REQUESTED, "detail": PlayerCopy.ROOM_FRIEND_REQUESTED_DETAIL % _friend(room), "icon": REQUESTED_ICON, "tone": "muted"})
	return rows

func _menu_ids(room: Dictionary) -> Array:
	if room.get("status") != "completed": return []
	return _menu_rows(room).map(func(row: Dictionary) -> String: return str(row.id))

## The square "..." button after Watch replay, with Watch replay's border and fill.
func _menu_button(room: Dictionary, beside: Button) -> Button:
	var button := Button.new()
	button.name = "RoomMenu"
	button.icon = MENU_ICON
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	button.add_theme_constant_override("icon_max_width",24)
	button.custom_minimum_size = Vector2(beside.custom_minimum_size.y,beside.custom_minimum_size.y)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.tooltip_text = PlayerCopy.ROOM_MENU
	button.accessibility_name = PlayerCopy.ROOM_MENU + ": " + str(room.get("chapter_title",""))
	button.disabled = _removing
	_secondary(button)
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		if not button.has_theme_stylebox(state): continue
		var style := button.get_theme_stylebox(state).duplicate() as StyleBox
		for edge: String in ["left","top","right","bottom"]: style.set("content_margin_"+edge,12)
		button.add_theme_stylebox_override(state,style)
	button.pressed.connect(func(): open_room_menu(room.duplicate(true),button,Input.is_action_pressed("ui_accept")))
	return button

## Opens the menu under a finished room's "..." button.
func open_room_menu(room: Dictionary, button: Control, keyboard: bool = false) -> void:
	if _removing or is_instance_valid(_modal) or (is_instance_valid(_menu) and not _menu.is_closed()): return
	_menu = RoomCardMenu.open(button,_menu_rows(room),keyboard)
	if _menu == null: return
	# Deferred, so a picked row's action runs before the cards it sits on are rebuilt.
	_menu.closed.connect(_render,CONNECT_DEFERRED)
	_menu.chosen.connect(func(id: String):
		if id == "hide": room_remove_requested.emit(room,"hide")
		elif id == "leave_finished": _ask_leave(room,button)
		elif id == "add_friend": add_friend_requested.emit(room, str((partner_friend.call(room) if partner_friend.is_valid() else {}).get("partner", ""))))

## The screen's root control, which in-game pop-ups cover.
func page_root() -> Control:
	return _root

## The open menu, for tests and captures; null when none is open.
func room_menu() -> CanvasLayer:
	return _menu if is_instance_valid(_menu) and not _menu.is_closed() else null

## The friend's nickname for a room's texts, or ROOM_FRIEND.
func _friend(room: Dictionary) -> String:
	for member: Variant in room.get("member_ids",[]):
		var shown := str(display_name.call(str(member))) if display_name.is_valid() else ""
		if not shown.is_empty(): return shown
	return PlayerCopy.ROOM_FRIEND

func _ask_leave(room: Dictionary, opener: Control) -> void:
	if _removing or is_instance_valid(_modal): return
	var friend := _friend(room)
	_modal = InGameModal.open(_root,"RoomLeaveModal",PlayerCopy.ROOM_LEAVE_TITLE,PlayerCopy.ROOM_LEAVE_SUBTITLE % [str(room.get("chapter_title","")),friend],opener)
	_modal.label(PlayerCopy.ROOM_LEAVE_BODY_LAST % friend if room.get("partner_left") == true else PlayerCopy.ROOM_LEAVE_BODY % friend)
	var phone := HBoxContainer.new()
	phone.name = "LeavePhoneLine"
	phone.add_theme_constant_override("separation",10)
	_modal.content.add_child(phone)
	var icon := TextureRect.new()
	icon.name = "PhoneIcon"
	icon.texture = PHONE_ICON
	icon.custom_minimum_size = Vector2(22,22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.modulate = MUTED
	phone.add_child(icon)
	var line: Label = _modal.label(PlayerCopy.ROOM_LEAVE_PHONE,17,phone)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_theme_color_override("font_color",MUTED)
	var confirm: Button = _modal.add_actions(PlayerCopy.ROOM_LEAVE,func():
		_modal.close(false)
		room_remove_requested.emit(room,"leave_finished"),"Cancel",true)
	# Leaving can't be undone, so the safe choice takes focus first.
	(_modal.find_child("ModalCancel",true,false) as Button).grab_focus()
	confirm.name = "ModalConfirm"

func _hidden_rooms() -> Array:
	return client.hidden_rooms() if client != null and client.has_method("hidden_rooms") else []

## The fold line "Hidden rooms · N" under the finished rooms, and, unfolded, a
## smaller dimmed card for each hidden room with Show again.
func _add_hidden_section(hidden: Array) -> void:
	if hidden.is_empty(): return
	var divider := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color("3e5e55")
	line.thickness = 1
	divider.add_theme_stylebox_override("separator",line)
	_rooms_list.add_child(divider)
	var fold := Button.new()
	fold.name = "HiddenRoomsFold"
	fold.text = PlayerCopy.ROOM_HIDDEN_FOLD % hidden.size()
	fold.icon = FOLD_OPEN_ICON if _hidden_open else FOLD_CLOSED_ICON
	fold.add_theme_constant_override("icon_max_width",20)
	fold.alignment = HORIZONTAL_ALIGNMENT_LEFT
	fold.custom_minimum_size.y = 48
	fold.mouse_filter = Control.MOUSE_FILTER_PASS
	fold.accessibility_name = fold.text
	for state: String in ["normal","hover","pressed","hover_pressed","focus"]:
		fold.add_theme_stylebox_override(state,ThemeRules.padded(ThemeRules.rounded(Color(1,1,1,0.05) if state in ["hover","pressed","hover_pressed"] else Color.TRANSPARENT,12,ThemeRules.CHOICE_BORDER if state == "focus" else Color.TRANSPARENT),10.0,6.0))
	for key: String in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color","icon_normal_color","icon_hover_color","icon_pressed_color","icon_hover_pressed_color","icon_focus_color"]:
		fold.add_theme_color_override(key,WARM)
	fold.pressed.connect(func():
		_hidden_open = not _hidden_open
		_render())
	_rooms_list.add_child(fold)
	if not _hidden_open: return
	for room: Dictionary in hidden: _add_hidden_card(room)

func _add_hidden_card(room: Dictionary) -> void:
	var card := _panel()
	card.name = "HiddenRoom"
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.modulate = Color(1,1,1,0.82)
	_rooms_list.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	card.add_child(row)
	var texture: Variant = thumbnail_for.call(str(room.chapter_key)) if thumbnail_for.is_valid() else _catalog_thumbnail(str(room.chapter_key))
	if texture is String: texture = load(texture)
	if texture is Texture2D:
		var image := TextureRect.new()
		image.texture = texture
		image.custom_minimum_size = Vector2(104,64)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		row.add_child(image)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	details.add_theme_constant_override("separation",2)
	row.add_child(details)
	var heading := Label.new()
	heading.text = str(room.get("chapter_title","A journey"))
	if _heading_font != null: heading.add_theme_font_override("font",_heading_font)
	heading.add_theme_font_size_override("font_size",20)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(heading)
	var friend := _friend(room)
	var meta := Label.new()
	meta.text = PlayerCopy.ROOM_HIDDEN_ALONE if friend == PlayerCopy.ROOM_FRIEND else PlayerCopy.ROOM_HIDDEN_LINE % friend
	meta.add_theme_font_size_override("font_size",17)
	meta.add_theme_color_override("font_color",MUTED)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(meta)
	var show := Button.new()
	show.name = "ShowAgain"
	show.text = PlayerCopy.ROOM_SHOW_AGAIN
	show.custom_minimum_size = Vector2(0,46)
	show.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	show.mouse_filter = Control.MOUSE_FILTER_PASS
	show.disabled = _removing
	_secondary(show)
	show.pressed.connect(func(): room_show_requested.emit(room.duplicate(true)))
	row.add_child(show)

func _ask_remove(room: Dictionary, removal: String, opener: Control) -> void:
	if _removing or is_instance_valid(_modal): return
	var label := _removal_label(removal)
	_modal = InGameModal.open(_root,"RoomRemoveModal","Close this room?" if removal == "close" else "Remove this room?",str(room.get("chapter_title","")),opener)
	var status := str(room.get("status",""))
	if removal != "close": _modal.label("It only leaves your list.")
	elif status == "waiting_for_friend": _modal.label("Your invitation stops working, and any turn you saved here is deleted. You can't undo this.")
	else: _modal.label("The room closes for both of you, and its saved turns are deleted. You can't undo this.")
	var confirm: Button = _modal.add_actions(label if removal == "close" else "Remove",func():
		_modal.close(false)
		room_remove_requested.emit(room,removal))
	confirm.grab_focus()

## The status chip, and beside it the friend's end-of-run face on their latest
## turn when the room list brought one (presentation/end_reactions.gd).
func _status_line(room: Dictionary, status: String) -> Control:
	var chip := _status_chip(status)
	var reaction: Variant = room.get("partner_reaction")
	if not reaction is Dictionary: return chip
	var line := HBoxContainer.new()
	line.name = "StatusLine"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation",10)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(chip)
	EndReactions.attach(line, {"friend": {"face": str(reaction.get("face","")), "color": str(reaction.get("color","mint")), "name": _friend(room)}, "compact": true})
	return line

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
	var part: int = Typed.as_int(room.get("part"))
	if part <= 0 and room.has("stage_index"): part = Typed.as_int(room.get("stage_index")) + 1
	if total <= 0: total = Typed.as_int(room.get("stage_count"))
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

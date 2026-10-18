extends Node
## Settings: one page with the player's spirit and the page title on top, a
## rail of categories on the left (each with a live summary) and the chosen
## category's rows on a cream panel on the right. Every row comes from the
## table in presentation/settings_rows.gd and is drawn by the shared builders
## in presentation/settings_kit.gd. Only a licence's full text is a screen of
## its own. It also saves the photo prompt preference that a chapter room's
## photo card changes.
##
## Main hosts it as a child. Settings live in saves; the flow keeps only the
## page it has open (the category on show and the rows drawn), and lets go of
## it when the page leaves the overlay. A change saves through
## saves.update_values, then Main's _apply_settings puts it into the world, HUD,
## sound and presence (a new setting with a runtime effect needs a line there);
## a failed save puts the row back and says so. The flow asks Main to go Home
## through home_requested, and reads Main only through this host contract (read
## at call time, so Main or a test can swap a service):
## - services: saves, _apply_settings, _play_store_enabled, identity_data, api,
##   secrets, get_tree
## - screen: mode, running, overlay, ui, _clear_overlay, _back_button, _card,
##   _label, _toast
## - flows (flow to flow, through the rows table): notification_flow
##   (reconcile, status_line, turn_notifications_on, set_turn_notifications,
##   turn_requests_on, set_turn_requests, turn_off), account_flow (panel_state,
##   identity_unread and the Account & recovery actions), store_flow
##   (restore_purchases, show_tester_access, show_store_from_settings),
##   _open_safety, _open_whats_new_card
## Main opens it through show_settings(category) (the Home cog, Safety's return,
## Photo transfer's return, Android Back from a licence or Tester code, and the
## settings_requested signals of StoreFlow and AccountFlow, which land on
## Account & recovery). show_graphics_settings() and show_licenses() open their
## categories. NotificationFlow calls refresh() when the service changes.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const LocalSave = preload("res://services/local_save.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const Rows = preload("res://presentation/settings_rows.gd")
const Kit = preload("res://presentation/settings_kit.gd")
const Spirit = preload("res://presentation/settings_spirit.gd")
const CREAM := Color("eceddb")
## Main's modes on these screens.
const MODE_SETTINGS := "settings"
const MODE_LICENSE_TEXT := "license_text"
## The categories, for callers that open one.
const EVERYDAY := Rows.EVERYDAY
const PLAY := Rows.PLAY
const GRAPHICS := Rows.GRAPHICS
const FRIENDS := Rows.FRIENDS
const ACCOUNT := Rows.ACCOUNT
const ABOUT := Rows.ABOUT
## The page at its 1280x720 base: side margins, the rail's width, the gap
## between rail and panel, and below this panel width a choice stacks under its text.
const MARGIN_X := 58
const RAIL_WIDTH := 262
const GAP := 24
const STACK_BELOW := 640.0

signal home_requested

var host: Node
## The open page, or empty. Freed with the overlay; see _forget().
var _page: Control
var _category := ""
var _categories: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
var _rail: Dictionary = {}
var _title: Label
var _reset: Button
var _list: VBoxContainer
var _scroll: ScrollContainer
var _spirit: Control
## The rows on show and their controls, for refresh().
var _live: Array[Dictionary] = []
## Bumped whenever the panel is drawn again; a late answer checks it.
var _view := 0
## The licence row a licence's text returns to.
var _license_row := ""

func _init(main: Node = null) -> void:
	host = main

## Opens Settings on a category (Everyday unless one is named). reveal: a row
## to scroll into view.
func show_settings(category: String = EVERYDAY, reveal: String = "") -> void:
	host.running = false
	host.mode = MODE_SETTINGS
	host._clear_overlay()
	_categories = Rows.categories(host)
	_rows = Rows.rows(host)
	if Rows.category(_categories, category).is_empty(): category = EVERYDAY
	_build_page()
	_select(category, reveal)

## Older entry points: Graphics and the licences are categories now.
func show_graphics_settings() -> void:
	show_settings(GRAPHICS)

func show_licenses() -> void:
	show_settings(ABOUT, _license_row)

func is_open() -> bool:
	return host.mode == MODE_SETTINGS and is_instance_valid(_page) and _page.is_inside_tree() and not _page.is_queued_for_deletion()

func category() -> String:
	return _category if is_open() else ""

func showing(id: String) -> bool:
	return is_open() and _category == id

## The inline box under an action row on show, or null.
func detail(row_id: String) -> VBoxContainer:
	if not is_open(): return null
	var block := _list.find_child(row_id + "Block", true, false)
	return block.get_node("DetailPad/Detail") as VBoxContainer if block != null else null

## A late answer may draw only into the panel it started on.
func view_token() -> int:
	return _view

func view_current(token: int) -> bool:
	return is_open() and token == _view

func _forget() -> void:
	_page = null
	_live.clear()
	_rail.clear()
	_rows.clear()
	_categories.clear()

func _build_page() -> void:
	var page := Control.new()
	page.name = "SettingsPage"
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.tree_exiting.connect(_forget)
	var backdrop := ColorRect.new()
	backdrop.name = "SettingsBackdrop"
	backdrop.color = Kit.PAGE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The page colour reaches every edge; the content stays in the safe area.
	SafeArea.bleed(backdrop)
	page.add_child(backdrop)
	var frame := MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var compact: bool = host.overlay.size.y < 640.0
	for side: Array in [["left", MARGIN_X], ["right", MARGIN_X], ["top", 16 if compact else 30], ["bottom", 14 if compact else 36]]:
		frame.add_theme_constant_override("margin_" + side[0], side[1])
	page.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16 if compact else 30)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(column)
	column.add_child(_header(compact))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", GAP)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(body)
	body.add_child(_rail_list())
	body.add_child(_panel())
	var footer := HBoxContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.alignment = BoxContainer.ALIGNMENT_END
	var mark := Kit.label(PlayerCopy.SETTINGS_WORDMARK, 20, Kit.MUTED, 600, true)
	mark.name = "Wordmark"
	footer.add_child(mark)
	column.add_child(footer)
	host.overlay.add_child(page)
	_page = page

func _header(compact: bool) -> Control:
	var header := HBoxContainer.new()
	header.name = "SettingsHeader"
	header.add_theme_constant_override("separation", 18)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spirit = Spirit.new(bool(host.saves.data.settings.get("reduced_motion", false)))
	if compact: _spirit.custom_minimum_size = Vector2(54, 75)
	header.add_child(_spirit)
	var titles := VBoxContainer.new()
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", 4)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Kit.label(PlayerCopy.MAIN_0FEE4C6E23F4, 30 if compact else 36, Kit.CREAM, 600, true)
	title.name = "SettingsTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(title)
	titles.add_child(Kit.label(PlayerCopy.SETTINGS_SAVED, 17, Kit.MUTED, 500))
	header.add_child(titles)
	var done: Button = host._back_button(PlayerCopy.SETTINGS_DONE, home_requested.emit)
	done.name = "SettingsDone"
	# Done lines up with the title, not with the spirit's middle.
	var corner := MarginContainer.new()
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.add_theme_constant_override("margin_top", 0 if compact else 18)
	corner.add_child(done)
	header.add_child(corner)
	Kit.style_done(done)
	done.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if not compact else Control.SIZE_SHRINK_CENTER
	return header

func _rail_list() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "SettingsRail"
	scroll.custom_minimum_size.x = RAIL_WIDTH
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ControlTheme.touch_scroll(scroll)
	Kit.style_scroll(scroll, false)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 9)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_rail.clear()
	for entry: Dictionary in _categories:
		var item := Kit.rail_item(entry, Rows.summary(entry, _rows, _value))
		item.pressed.connect(_open_category.bind(str(entry.id)))
		list.add_child(item)
		_rail[entry.id] = item
	return scroll

func _panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := Kit.rounded(Kit.PANEL, 20)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 20
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	panel.add_child(stack)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_title = Kit.label("", 28, Kit.INK, 600, true)
	_title.name = "PanelTitle"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_title)
	_reset = Kit.reset_button("")
	_reset.name = "ResetCategory"
	_reset.pressed.connect(_confirm_reset)
	head.add_child(_reset)
	var title_pad := MarginContainer.new()
	title_pad.add_theme_constant_override("margin_left", Kit.ROW_PAD)
	title_pad.add_theme_constant_override("margin_right", Kit.ROW_PAD)
	title_pad.add_child(head)
	stack.add_child(title_pad)
	_scroll = ScrollContainer.new()
	_scroll.name = "SettingsRows"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ControlTheme.touch_scroll(_scroll)
	Kit.style_scroll(_scroll, true)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	stack.add_child(_scroll)
	return panel

func _open_category(id: String) -> void:
	if id != _category: _select(id)

## Shows a category: the rail marks it and the panel draws its rows, once.
func _select(id: String, reveal: String = "") -> void:
	if not is_instance_valid(_page): return
	_category = id
	var entry := Rows.category(_categories, id)
	for key: String in _rail: Kit.select_rail_item(_rail[key], key == id)
	_title.text = str(entry.title)
	var reset: Dictionary = entry.get("reset", {})
	_reset.visible = not reset.is_empty()
	_reset.text = str(reset.get("label", ""))
	_reset.name = "Reset" + id.capitalize().replace(" ", "")
	_build_rows(Rows.in_category(_rows, id))
	if entry.has("on_open"): entry.on_open.call()
	refresh()
	if not reveal.is_empty(): _reveal.call_deferred(reveal)

func _build_rows(rows: Array[Dictionary]) -> void:
	_view += 1
	_live.clear()
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_scroll.scroll_vertical = 0
	var stacked := _panel_width() < STACK_BELOW
	var previous: Dictionary = {}
	for row: Dictionary in rows:
		if row.get("danger", false): _list.add_child(Kit.separation())
		elif not previous.is_empty(): _list.add_child(Kit.divider())
		var control := _row_control(row, stacked)
		_list.add_child(control)
		_live.append({"row": row, "control": control})
		previous = row

## The panel's width for its rows, from the page's own measures.
func _panel_width() -> float:
	return host.overlay.size.x - MARGIN_X * 2 - RAIL_WIDTH - GAP - 36.0 - Kit.ROW_PAD * 2

func _row_control(row: Dictionary, stacked: bool) -> Control:
	var id := str(row.id)
	var shown_row := row.duplicate()
	shown_row.label = Rows.text(row.get("label", ""))
	shown_row.note = Rows.text(row.get("note", ""))
	match str(row.kind):
		Rows.TOGGLE:
			var holder := Kit.toggle_row(shown_row, bool(_value(row)))
			var toggle := holder.get_node(id) as CheckButton
			toggle.toggled.connect(func(on: bool): _change(row, on))
			return holder
		Rows.CHOICE:
			var holder := Kit.choice_row(shown_row, str(_value(row)), stacked)
			for option: Button in Kit.options(holder.find_child(id, true, false)):
				option.pressed.connect(_change.bind(row, str(option.get_meta("value"))))
			return holder
		Rows.LINK:
			var holder := Kit.link_row(shown_row)
			(holder.get_node(id) as Button).pressed.connect(row.open)
			return holder
		Rows.ACTION:
			if row.get("danger", false):
				var danger := Kit.danger_row(shown_row)
				(danger.get_node(id) as Button).pressed.connect(row.run)
				return danger
			var block := Kit.action_row(shown_row)
			var holder: Control = block.get_node(id + "Row")
			var box := block.get_node("DetailPad/Detail") as VBoxContainer
			var button := holder.get_node(id) as Button
			if row.has("inline"): button.pressed.connect(func(): row.inline.call(box, holder))
			else: button.pressed.connect(row.run)
			return block
	return Kit.info_row(shown_row)

## A row's current value: its saved setting, or its own getter.
func _value(row: Dictionary) -> Variant:
	if row.has("get"): return row.get.call()
	if not row.has("key"): return null
	return host.saves.data.settings.get(row.key, LocalSave.defaults().settings.get(row.key))

## Saves a row's new value (the shared path for every row), or puts it back.
func _change(row: Dictionary, value: Variant) -> void:
	if not is_open() or value == _value(row) and not row.has("set"):
		refresh()
		return
	var kept: bool
	if row.has("set"):
		kept = bool(row.set.call(value))
	else:
		var next: Dictionary = host.saves.data.settings.duplicate(true)
		next[row.key] = value
		kept = host.saves.update_values({"settings": next})
		if kept: host._apply_settings()
	if not kept: host._toast(PlayerCopy.MAIN_34B82590B663)
	elif row.has("on_change"): row.on_change.call(value)
	refresh()

## Puts every row on show, the rail's summaries, the reset and the spirit in
## step with what is saved. Updates controls in place: nothing is rebuilt, so
## a finger on the page never loses its row.
func refresh() -> void:
	if not is_open(): return
	for item: Dictionary in _live:
		var row: Dictionary = item.row
		var control: Control = item.control
		var target := control.find_child(str(row.id), true, false)
		if target == null and str(row.id) == control.name: target = control
		var on := Rows.enabled(row)
		match str(row.kind):
			Rows.TOGGLE:
				var toggle := target as CheckButton
				toggle.set_pressed_no_signal(bool(_value(row)))
				toggle.disabled = not on
				(toggle.get_parent().find_child("Switch", true, false) as Kit.Switch).refresh()
			Rows.CHOICE:
				for option: Button in Kit.options(target):
					option.set_pressed_no_signal(str(option.get_meta("value")) == str(_value(row)))
					option.disabled = not on
			Rows.LINK, Rows.ACTION:
				if target is BaseButton: (target as BaseButton).disabled = not on
		if row.get("note") is Callable:
			var note := control.find_child("Note", true, false) as Label
			if note != null:
				note.text = Rows.text(row.note)
				note.visible = not note.text.is_empty()
	for id: String in _rail: Kit.set_rail_summary(_rail[id], Rows.summary(Rows.category(_categories, id), _rows, _value))
	var reset: Dictionary = Rows.category(_categories, _category).get("reset", {})
	_reset.disabled = reset.is_empty() or _at_defaults(reset.rows)
	if _spirit.has_method("set_reduced"): _spirit.set_reduced(bool(host.saves.data.settings.get("reduced_motion", false)))

func _at_defaults(ids: Array) -> bool:
	var defaults: Dictionary = LocalSave.defaults().settings
	for id: String in ids:
		var row := Rows.find(_rows, id)
		if not row.is_empty() and str(_value(row)) != str(defaults.get(row.key)): return false
	return true

func _confirm_reset() -> void:
	var reset: Dictionary = Rows.category(_categories, _category).get("reset", {})
	if reset.is_empty() or _at_defaults(reset.rows): return
	var modal := InGameModal.open(host.ui, "ResetConfirm", str(reset.confirm), "", _reset) as InGameModal
	modal.add_actions(PlayerCopy.SETTINGS_RESET, func():
		modal.close(false)
		_reset_rows(reset.rows), PlayerCopy.SETTINGS_CANCEL)

## Puts rows back to their defaults in one save.
func _reset_rows(ids: Array) -> void:
	if not is_open(): return
	var defaults: Dictionary = LocalSave.defaults().settings
	var next: Dictionary = host.saves.data.settings.duplicate(true)
	for id: String in ids:
		var row := Rows.find(_rows, id)
		if row.has("key"): next[row.key] = defaults[row.key]
	if host.saves.update_values({"settings": next}): host._apply_settings()
	else: host._toast(PlayerCopy.MAIN_34B82590B663)
	refresh()

func _reveal(row_id: String) -> void:
	if not is_open(): return
	var target := _list.find_child(row_id, true, false) as Control
	if target == null: return
	# Rows have no layout until the next frame.
	await get_tree().process_frame
	if is_open() and is_instance_valid(target): _scroll.ensure_control_visible(target)

## The photo card's Don't ask again (a chapter room's save_photo_prompt_preference).
func save_photo_prompt_preference(enabled: bool) -> bool:
	var next: Dictionary = host.saves.data.settings.duplicate(true)
	next.photo_prompts = enabled
	return host.saves.update_values({"settings": next})

## A licence's full text. Back returns to its row in About.
func show_license(entry: Dictionary, row_id: String = "") -> void:
	_license_row = row_id
	host.mode=MODE_LICENSE_TEXT
	var card: VBoxContainer = host._card(920)
	card.add_child(host._label(str(entry.title),30,CREAM,true))
	var text := RichTextLabel.new()
	text.name="LicenseText"
	text.bbcode_enabled=false
	text.selection_enabled=true
	text.scroll_active=true
	text.custom_minimum_size=Vector2(840,390)
	text.add_theme_font_size_override("normal_font_size",18)
	text.add_theme_color_override("default_color",CREAM)
	text.text=str(entry.text)
	card.add_child(text)
	card.add_child(host._back_button("Back to licenses",show_licenses,false))

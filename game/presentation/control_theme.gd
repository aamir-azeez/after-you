extends RefCounted
## Shared controls for the original islands and authored chapters.
const INK := Color("193d39")
const CREAM := Color("eceddb")
const DANGER_INK := Color("503a37")
const CHECK_ICON := preload("res://assets/ui/check.svg")
const CHOICE_PANEL := Color("173f39")
const CHOICE_BORDER := Color("668e7f")
const CHOICE_HIGHLIGHT := Color("315e53")
const CHOICE_DISABLED := Color("9aaaa3")
const TOUCH_SCROLL_META := "touch_scroll"
static var _blank_choice_icon: Texture2D

class ChoiceList extends CanvasLayer:
	## In-page dropdown for a themed OptionButton. It sits on its own canvas
	## layer just above the button's screen; a press on the shade around the
	## panel closes it. Rows take focus only once keys or a gamepad are used,
	## so a tap leaves focus where the engine menu would.
	var source: OptionButton
	var shade: Control
	var panel: PanelContainer
	var scroll: ScrollContainer
	var rows: Array[Button] = []
	var keyboard := false
	var place: Callable
	var _closed := false

	func pick(index: int) -> void:
		if _closed: return
		var button := source
		close(keyboard)
		# Matches the engine menu: re-choosing the current item emits nothing.
		if is_instance_valid(button) and index >= 0 and index < button.item_count and index != button.selected:
			button.select(index)
			button.item_selected.emit(index)

	func close(restore_focus: bool = false) -> void:
		if _closed: return
		_closed = true
		# The shade stays until the end of the frame: a finger press arrives as
		# an emulated mouse press and then a screen touch, and both must land
		# here, or the touch would press whatever lies beneath the list.
		if is_instance_valid(source):
			if source.has_meta("choice_list") and source.get_meta("choice_list") == self: source.remove_meta("choice_list")
			if restore_focus and source.is_inside_tree() and source.is_visible_in_tree(): source.grab_focus()
		queue_free()

	func row_for(index: int) -> Button:
		for row: Button in rows:
			if int(row.get_meta("choice_index",-1)) == index: return row
		return null

	func engage_keyboard() -> void:
		keyboard = true
		var target: Button = null
		for row: Button in rows:
			if row.disabled: continue
			row.focus_mode = Control.FOCUS_ALL
			if target == null: target = row
		var current := row_for(source.selected) if is_instance_valid(source) else null
		if current != null and not current.disabled: target = current
		if target != null: target.grab_focus()

	func _input(event: InputEvent) -> void:
		if _closed or not visible: return
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			close(keyboard)
		elif not keyboard:
			for action: String in ["ui_up","ui_down","ui_left","ui_right","ui_focus_next","ui_focus_prev","ui_accept"]:
				if event.is_action_pressed(action):
					# Keys after a tap-opened list start on the current choice.
					get_viewport().set_input_as_handled()
					engage_keyboard()
					return

	func _notification(what: int) -> void:
		if what == NOTIFICATION_WM_GO_BACK_REQUEST: close()

	func _on_shade_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			shade.accept_event()
			close(keyboard)

	func _on_viewport_resized() -> void:
		if not _closed and place.is_valid(): place.call()

	func _on_source_visibility() -> void:
		if not is_instance_valid(source) or not source.is_visible_in_tree(): close()

	func reveal(index: int) -> void:
		# Rows have no layout until the next frame; then start at the current choice.
		await get_tree().process_frame
		if _closed or not is_instance_valid(scroll): return
		var row := row_for(index)
		if row != null: scroll.scroll_vertical = int(row.position.y)

static func hint_bounds(ui_width: float, left_handed: bool) -> Rect2:
	# Reserve the full joystick touch area and both action buttons, not just
	# their artwork. These margins cover either existing control layout.
	var left := 258.0 if left_handed else 218.0
	var right := ui_width - (218.0 if left_handed else 258.0)
	var width := minf(680.0, maxf(120.0, right - left))
	return Rect2((left + right - width) / 2.0, -94, width, 78)

static func rounded(color: Color, radius: int=16, border: Color=Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color=color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1 if border.a>0 else 0)
	style.border_color=border
	return style

static func padded(style: StyleBox, horizontal: float = 18.0, vertical: float = 10.0) -> StyleBox:
	## Text and icons need breathing room from the rounded border on every state.
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style

static func install_buttons(theme: Theme) -> void:
	for state: String in ["normal","hover","pressed","hover_pressed"]:
		var color := CREAM if state=="normal" else Color("ffffff") if state=="hover" else Color("a6d9c4")
		theme.set_stylebox(state,"Button",padded(rounded(color)))
		theme.set_color("font_color" if state=="normal" else "font_"+state+"_color","Button",INK)
	theme.set_stylebox("disabled","Button",padded(rounded(Color("3e5e55"))))
	theme.set_color("font_disabled_color","Button",Color("9aaaa3"))
	# Focused cream buttons keep dark ink; the engine default is a light colour.
	theme.set_color("font_focus_color","Button",INK)
	theme.set_stylebox("focus","Button",padded(rounded(Color.TRANSPARENT,16,Color("a6d9c4"))))

static func secondary(button: Button) -> void:
	button.add_theme_stylebox_override("normal",padded(rounded(Color("254b45"),14,Color("54766a"))))
	button.add_theme_color_override("font_color",CREAM)
	button.add_theme_color_override("font_focus_color",CREAM)
	if button is OptionButton: choice_button(button)

static func selected_tab(button: Button) -> void:
	## The current tab or toggle option: a lighter teal pill. Cream stays
	## reserved for the screen's primary action.
	var fill := padded(rounded(Color("3a6b5f"),14))
	for state: String in ["normal","hover","pressed","hover_pressed","disabled"]:
		button.add_theme_stylebox_override(state,fill)
	for key: String in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color","font_disabled_color","icon_normal_color","icon_disabled_color"]:
		button.add_theme_color_override(key,CREAM)

static func plain_tab(button: Button) -> void:
	## Unselected tabs read as text until chosen.
	button.add_theme_stylebox_override("normal",padded(rounded(Color.TRANSPARENT,14)))
	button.add_theme_stylebox_override("hover",padded(rounded(Color(1,1,1,0.06),14)))
	button.add_theme_stylebox_override("pressed",padded(rounded(Color("3a6b5f"),14)))
	button.add_theme_stylebox_override("hover_pressed",padded(rounded(Color("3a6b5f"),14)))
	button.add_theme_color_override("font_color",Color("afc6be"))
	for key: String in ["font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
		button.add_theme_color_override(key,CREAM)

static func choice_button(button: OptionButton) -> void:
	for state: String in ["normal","hover","pressed","hover_pressed","disabled"]:
		var disabled := state == "disabled"
		var fill := Color("254b45") if state == "normal" else Color("315e53")
		if disabled: fill = Color("203f39")
		button.add_theme_stylebox_override(state,padded(rounded(fill,14,Color("54766a"))))
		button.add_theme_color_override("font_color" if state == "normal" else "font_"+state+"_color",Color("9aaaa3") if disabled else CREAM)
	button.add_theme_icon_override("arrow",preload("res://assets/ui/social/chevron-down.svg"))
	button.add_theme_constant_override("arrow_margin",16)
	button.add_theme_color_override("font_focus_color",CREAM)
	button.add_theme_stylebox_override("focus",padded(rounded(Color.TRANSPARENT,14,Color("a6d9c4"))))
	# A popup is its own window and does not reliably inherit the page's theme.
	var menu := button.get_popup()
	var choices := Theme.new()
	choices.default_font = button.get_theme_font("font")
	choices.default_font_size = maxi(20,button.get_theme_font_size("font_size"))
	choices.set_stylebox("panel","PopupMenu",padded(rounded(Color("173f39"),14,Color("668e7f")),12,8))
	choices.set_stylebox("hover","PopupMenu",padded(rounded(Color("315e53"),9),8,8))
	for color_name: String in ["font_color","font_hover_color","font_focus_color"]:
		choices.set_color(color_name,"PopupMenu",CREAM)
	choices.set_color("font_disabled_color","PopupMenu",Color("9aaaa3"))
	choices.set_constant("v_separation","PopupMenu",24)
	choices.set_constant("h_separation","PopupMenu",12)
	choices.set_constant("item_start_padding","PopupMenu",8)
	choices.set_constant("item_end_padding","PopupMenu",12)
	choices.set_icon("radio_checked","PopupMenu",CHECK_ICON)
	choices.set_icon("radio_unchecked","PopupMenu",_blank_icon())
	menu.theme = choices
	menu.prefer_native_menu = false
	if not button.has_meta("choice_popup_fitted"):
		button.set_meta("choice_popup_fitted",true)
		menu.about_to_popup.connect(func(): _fit_choice_popup(button))
		# The engine menu window cannot be dragged by touch and picks whichever
		# row a drag ends on. Taps and accept keys open the in-page ChoiceList
		# instead; show_popup() still opens the themed engine menu.
		button.button_mask = 0
		button.mouse_filter = Control.MOUSE_FILTER_PASS
		button.gui_input.connect(func(event: InputEvent): _choice_input(button,event))

static func _blank_icon() -> Texture2D:
	if _blank_choice_icon == null:
		var empty := Image.create(24,24,false,Image.FORMAT_RGBA8)
		empty.fill(Color.TRANSPARENT)
		_blank_choice_icon = ImageTexture.create_from_image(empty)
	return _blank_choice_icon

static func _choice_input(button: OptionButton, event: InputEvent) -> void:
	if not is_instance_valid(button): return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		# The engine opens its menu window on a raw touch press, ignoring
		# button_mask. The emulated mouse events that accompany every touch
		# drive the tap and the drag instead.
		button.accept_event()
		return
	if button.disabled:
		_end_choice_press(button)
		return
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed: _begin_choice_press(button)
		elif _end_choice_press(button) and Rect2(Vector2.ZERO,button.size).has_point(click.position):
			open_choices(button)
	elif event.is_action_pressed("ui_accept"):
		button.accept_event()
		open_choices(button,true)

static func _begin_choice_press(button: OptionButton) -> void:
	# A press is a tap until an enclosing list starts scrolling; that drag then
	# belongs to the list, exactly like the engine cancels a Button press.
	_end_choice_press(button)
	var cancel := func(): if is_instance_valid(button): _end_choice_press(button)
	var scrolls: Array = []
	var node := button.get_parent()
	while node != null:
		if node is ScrollContainer:
			(node as ScrollContainer).scroll_started.connect(cancel,CONNECT_ONE_SHOT)
			scrolls.append(node)
		node = node.get_parent()
	button.set_meta("choice_press",{"cancel":cancel,"scrolls":scrolls})

static func _end_choice_press(button: OptionButton) -> bool:
	if not button.has_meta("choice_press"): return false
	var press: Dictionary = button.get_meta("choice_press")
	button.remove_meta("choice_press")
	for scroll in press.scrolls:
		if is_instance_valid(scroll) and scroll.scroll_started.is_connected(press.cancel):
			scroll.scroll_started.disconnect(press.cancel)
	return true

static func choice_list(button: OptionButton) -> ChoiceList:
	## The open in-page list for this button, or null.
	var list: Variant = button.get_meta("choice_list") if is_instance_valid(button) and button.has_meta("choice_list") else null
	return list if is_instance_valid(list) and not list.is_queued_for_deletion() else null

static func open_choices(button: OptionButton, keyboard: bool = false) -> ChoiceList:
	if not is_instance_valid(button) or not button.is_inside_tree() or not button.is_visible_in_tree() or button.item_count == 0: return null
	var previous := choice_list(button)
	if previous != null: previous.close()
	var list := ChoiceList.new()
	list.name = "ChoiceList"
	list.source = button
	list.keyboard = keyboard
	var host := button.get_canvas_layer_node()
	list.layer = (host.layer if host != null else 0) + 1
	button.add_child(list,false,Node.INTERNAL_MODE_BACK)
	button.set_meta("choice_list",list)
	var font := button.get_theme_font("font")
	var font_size := maxi(20,button.get_theme_font_size("font_size"))
	list.shade = Control.new()
	list.shade.name = "ChoiceShade"
	list.shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	list.shade.mouse_filter = Control.MOUSE_FILTER_STOP
	list.shade.theme = _choice_list_theme(font,font_size)
	list.shade.gui_input.connect(list._on_shade_input)
	list.add_child(list.shade)
	list.panel = PanelContainer.new()
	list.panel.name = "ChoicePanel"
	list.panel.add_theme_stylebox_override("panel",padded(rounded(CHOICE_PANEL,14,CHOICE_BORDER),12,8))
	list.shade.add_child(list.panel)
	list.scroll = ScrollContainer.new()
	list.scroll.name = "ChoiceScroll"
	list.scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.scroll.follow_focus = true
	list.panel.add_child(list.scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",0)
	list.scroll.add_child(column)
	# Same row height as the engine menu: text height plus its 24 px separation.
	var row_height := maxf(48.0,ceilf(font.get_height(font_size)) + 24.0)
	for index: int in range(button.item_count):
		if button.is_item_separator(index):
			column.add_child(HSeparator.new())
			continue
		var row := Button.new()
		row.text = button.get_item_text(index)
		row.icon = CHECK_ICON if index == button.selected else _blank_icon()
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.custom_minimum_size.y = row_height
		row.disabled = button.is_item_disabled(index)
		row.focus_mode = Control.FOCUS_NONE
		row.accessibility_name = row.text
		row.set_meta("choice_index",index)
		row.pressed.connect(list.pick.bind(index))
		column.add_child(row)
		list.rows.append(row)
	_wrap_choice_focus(list)
	touch_scroll(list.scroll)
	list.place = _place_choice_list.bind(list,column.get_combined_minimum_size().y + list.panel.get_theme_stylebox("panel").get_minimum_size().y)
	list.place.call()
	button.get_viewport().size_changed.connect(list._on_viewport_resized)
	button.visibility_changed.connect(list._on_source_visibility)
	if keyboard: list.engage_keyboard()
	list.reveal(button.selected)
	return list

static func _wrap_choice_focus(list: ChoiceList) -> void:
	# Keyboard and gamepad focus cycles through the rows and never reaches the
	# page behind the list.
	var focusable: Array[Button] = []
	for row: Button in list.rows:
		if not row.disabled: focusable.append(row)
	for index: int in range(focusable.size()):
		var row := focusable[index]
		var above := row.get_path_to(focusable[(index - 1 + focusable.size()) % focusable.size()])
		var below := row.get_path_to(focusable[(index + 1) % focusable.size()])
		row.focus_neighbor_top = above
		row.focus_previous = above
		row.focus_neighbor_bottom = below
		row.focus_next = below
		row.focus_neighbor_left = NodePath(".")
		row.focus_neighbor_right = NodePath(".")

static func _place_choice_list(list: ChoiceList, content_height: float) -> void:
	# Same placement as the engine menu: under the button, at its width, and
	# scrolling inside whatever height is left above the window edge.
	var button := list.source
	if not is_instance_valid(button) or not button.is_inside_tree(): return
	var placement := button.get_global_transform_with_canvas()
	var rect := Rect2(placement.origin,button.size * placement.get_scale())
	var available := button.get_viewport().get_visible_rect().end.y - rect.end.y - 12.0
	list.panel.position = Vector2(rect.position.x,rect.end.y)
	list.panel.size = Vector2(rect.size.x,minf(content_height,maxf(48.0,available)))

static func _choice_list_theme(font: Font, font_size: int) -> Theme:
	var look := Theme.new()
	look.default_font = font
	look.default_font_size = font_size
	var plain := StyleBoxEmpty.new()
	plain.content_margin_left = 8
	plain.content_margin_right = 12
	var lit := rounded(CHOICE_HIGHLIGHT,9)
	lit.content_margin_left = 8
	lit.content_margin_right = 12
	for state: String in ["normal","disabled"]: look.set_stylebox(state,"Button",plain)
	for state: String in ["hover","pressed","hover_pressed","focus"]: look.set_stylebox(state,"Button",lit)
	for color_name: String in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
		look.set_color(color_name,"Button",CREAM)
	look.set_color("font_disabled_color","Button",CHOICE_DISABLED)
	for color_name: String in ["icon_normal_color","icon_hover_color","icon_pressed_color","icon_hover_pressed_color","icon_focus_color"]:
		look.set_color(color_name,"Button",Color.WHITE)
	look.set_color("icon_disabled_color","Button",CHOICE_DISABLED)
	look.set_constant("h_separation","Button",12)
	return look

static func touch_scroll(scroll: ScrollContainer) -> ScrollContainer:
	## Lets a drag that starts anywhere in the list scroll it, as the licenses
	## list always has: controls that do not take drags themselves pass the
	## press up to the scroller, and its scroll start cancels a pending tap.
	## Rows added later are adopted as they enter the tree.
	if not scroll.has_meta(TOUCH_SCROLL_META):
		scroll.set_meta(TOUCH_SCROLL_META,true)
		_adopt_touch_branch(scroll)
	return scroll

static func _adopt_touch_branch(node: Node) -> void:
	if not node.child_entered_tree.is_connected(_adopt_touch_node):
		node.child_entered_tree.connect(_adopt_touch_node)
	for child: Node in node.get_children():
		_adopt_touch_node(child)

static func _adopt_touch_node(node: Node) -> void:
	# Popups and layers are separate input roots with their own handling.
	if node is Window or node is CanvasLayer: return
	var control := node as Control
	if control != null and control.mouse_filter == Control.MOUSE_FILTER_STOP and not _keeps_own_drag(control):
		control.mouse_filter = Control.MOUSE_FILTER_PASS
	_adopt_touch_branch(node)

static func _keeps_own_drag(control: Control) -> bool:
	# Text entry, sliders and views that scroll themselves keep the gesture.
	var text := control as RichTextLabel
	if text != null: return text.selection_enabled or (text.scroll_active and not text.fit_content)
	return control is LineEdit or control is TextEdit or control is Slider or control is ScrollBar or control is SpinBox or control is ItemList or control is Tree

static func _fit_choice_popup(button: OptionButton) -> void:
	if not is_instance_valid(button) or not button.is_inside_tree(): return
	var menu := button.get_popup()
	menu.theme.default_font = button.get_theme_font("font")
	menu.theme.default_font_size = maxi(20,button.get_theme_font_size("font_size"))
	# Keep long lists scrollable inside the window, with clearance at both ends.
	var rect := Rect2(button.get_global_transform_with_canvas().origin,button.size)
	var available := button.get_viewport().get_visible_rect().end.y - rect.end.y - 12.0
	menu.min_size = Vector2i(int(button.size.x),0)
	menu.max_size = Vector2i(int(button.size.x),maxi(48,int(available)))
	_place_choice_popup.call_deferred(button)

static func _place_choice_popup(button: OptionButton) -> void:
	if not is_instance_valid(button) or not button.is_inside_tree(): return
	var menu := button.get_popup()
	if not menu.visible: return
	var rect := Rect2(button.get_global_transform_with_canvas().origin,button.size)
	menu.size = Vector2i(int(rect.size.x),mini(menu.size.y,menu.max_size.y))
	menu.position = Vector2i(int(rect.position.x),int(rect.end.y))

static func danger(button: Button, icon: Texture2D = null) -> void:
	## Reserved for Back and destructive actions. Coral stays soft while the
	## darker ink preserves readable text and icon contrast.
	if icon != null:
		button.icon = icon
		button.add_theme_constant_override("icon_max_width",22)
	# An icon-only control centres its icon in the 48 px target; a labelled one
	# keeps the icon inset from the left edge with the label centred.
	var icon_only := button.text.strip_edges().is_empty()
	if button.icon != null:
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if icon_only else HORIZONTAL_ALIGNMENT_LEFT
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("h_separation",0 if icon_only else 10)
	var inset := 12.0 if icon_only else 20.0
	for state: String in ["normal","hover","pressed","hover_pressed","disabled"]:
		var disabled := state == "disabled"
		var fill := Color("755b58") if disabled else Color("e9b3aa")
		if state == "hover": fill = Color("f2c2b8")
		if state in ["pressed","hover_pressed"]: fill = Color("d99a92")
		var foreground := Color("b8aaa5") if disabled else DANGER_INK
		button.add_theme_stylebox_override(state,padded(rounded(fill,14,Color("bd8982") if not disabled else Color("786a66")),inset,8.0))
		button.add_theme_color_override("font_color" if state == "normal" else "font_"+state+"_color",foreground)
		button.add_theme_color_override("icon_"+state+"_color",foreground)
	button.add_theme_stylebox_override("focus",padded(rounded(Color.TRANSPARENT,14,Color("f5d1c9")),inset,8.0))
	button.add_theme_color_override("font_focus_color",DANGER_INK)
	button.add_theme_color_override("icon_focus_color",DANGER_INK)
	if not icon_only and button.icon != null:
		# Keep the back-arrow and its label together as one centred group.
		center_icon_label(button, inset)

static func inset_button(button: Button, horizontal: float = 16, vertical: float = 8) -> void:
	for state: String in ["normal","hover","pressed","hover_pressed","disabled"]:
		var style := button.get_theme_stylebox(state).duplicate() as StyleBox
		style.content_margin_left = horizontal
		style.content_margin_right = horizontal
		style.content_margin_top = vertical
		style.content_margin_bottom = vertical
		button.add_theme_stylebox_override(state,style)

static func center_icon_label(button: Button, min_inset: float = 16.0) -> void:
	## A labelled icon button should read as one centred group: the icon, the
	## usual gap, then the label. Both sit left-aligned so they stay adjacent,
	## and equal left/right content margins recentre that group whenever the
	## button resizes. Only buttons laid out by a Container are recentred, so
	## fixed-size anchored HUD controls keep their own geometry. Icon-only and
	## text-only buttons keep the engine's own centring.
	if button.icon == null or button.text.strip_edges().is_empty():
		return
	button.set_meta("center_icon_label_inset", min_inset)
	if not button.has_meta("center_icon_label_wired"):
		button.set_meta("center_icon_label_wired", true)
		button.resized.connect(func(): _recenter_icon_label(button))
	_recenter_icon_label(button)

static func _recenter_icon_label(button: Button) -> void:
	# Each state keeps its own duplicated stylebox so shared theme styles are
	# never mutated; only the left/right margins move to centre the group.
	if not is_instance_valid(button) or button.icon == null or button.text.strip_edges().is_empty():
		return
	# Fixed-size anchored controls (gameplay HUD) set their own width; symmetric
	# centring margins would inflate their minimum size, so skip them.
	if not (button.get_parent() is Container):
		return
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var gap: float = float(button.get_theme_constant("h_separation"))
	var icon_width := float(button.icon.get_width())
	var max_width := button.get_theme_constant("icon_max_width")
	if max_width > 0: icon_width = minf(icon_width, float(max_width))
	var font := button.get_theme_font("font")
	var font_size := button.get_theme_font_size("font_size")
	var text_width := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var group := icon_width + gap + text_width
	var min_inset: float = float(button.get_meta("center_icon_label_inset", 16.0))
	var inset := maxf(min_inset, (button.size.x - group) / 2.0)
	for state: String in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
		if not button.has_theme_stylebox_override(state): continue
		var style := button.get_theme_stylebox(state).duplicate() as StyleBox
		style.content_margin_left = inset
		style.content_margin_right = inset
		button.add_theme_stylebox_override(state, style)

extends RefCounted
## Shared controls for the original islands and authored chapters.
const INK := Color("193d39")
const CREAM := Color("eceddb")
const DANGER_INK := Color("503a37")

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
	choices.set_icon("radio_checked","PopupMenu",preload("res://assets/ui/check.svg"))
	var empty := Image.create(24,24,false,Image.FORMAT_RGBA8)
	empty.fill(Color.TRANSPARENT)
	choices.set_icon("radio_unchecked","PopupMenu",ImageTexture.create_from_image(empty))
	menu.theme = choices
	menu.prefer_native_menu = false
	if not button.has_meta("choice_popup_fitted"):
		button.set_meta("choice_popup_fitted",true)
		menu.about_to_popup.connect(func(): _fit_choice_popup(button))

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

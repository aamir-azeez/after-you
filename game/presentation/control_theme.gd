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

static func install_buttons(theme: Theme) -> void:
	for state: String in ["normal","hover","pressed","hover_pressed"]:
		var color := CREAM if state=="normal" else Color("ffffff") if state=="hover" else Color("a6d9c4")
		theme.set_stylebox(state,"Button",rounded(color))
		theme.set_color("font_color" if state=="normal" else "font_"+state+"_color","Button",INK)
	theme.set_stylebox("disabled","Button",rounded(Color("3e5e55")))
	theme.set_color("font_disabled_color","Button",Color("9aaaa3"))
	theme.set_stylebox("focus","Button",rounded(Color.TRANSPARENT,16,Color("a6d9c4")))

static func secondary(button: Button) -> void:
	button.add_theme_stylebox_override("normal",rounded(Color("254b45"),14,Color("54766a")))
	button.add_theme_color_override("font_color",CREAM)

static func danger(button: Button, icon: Texture2D = null) -> void:
	## Reserved for Back and destructive actions. Coral stays soft while the
	## darker ink preserves readable text and icon contrast.
	if icon != null:
		button.icon = icon
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_constant_override("h_separation",10)
		button.add_theme_constant_override("icon_max_width",22)
	for state: String in ["normal","hover","pressed","hover_pressed","disabled"]:
		var disabled := state == "disabled"
		var fill := Color("755b58") if disabled else Color("e9b3aa")
		if state == "hover": fill = Color("f2c2b8")
		if state in ["pressed","hover_pressed"]: fill = Color("d99a92")
		var foreground := Color("b8aaa5") if disabled else DANGER_INK
		button.add_theme_stylebox_override(state,rounded(fill,14,Color("bd8982") if not disabled else Color("786a66")))
		button.add_theme_color_override("font_color" if state == "normal" else "font_"+state+"_color",foreground)
		button.add_theme_color_override("icon_"+state+"_color",foreground)
	button.add_theme_stylebox_override("focus",rounded(Color.TRANSPARENT,14,Color("f5d1c9")))
	button.add_theme_color_override("font_focus_color",DANGER_INK)
	button.add_theme_color_override("icon_focus_color",DANGER_INK)

static func inset_button(button: Button, horizontal: float = 16, vertical: float = 8) -> void:
	for state: String in ["normal","hover","pressed","hover_pressed","disabled"]:
		var style := button.get_theme_stylebox(state).duplicate() as StyleBox
		style.content_margin_left = horizontal
		style.content_margin_right = horizontal
		style.content_margin_top = vertical
		style.content_margin_bottom = vertical
		button.add_theme_stylebox_override(state,style)

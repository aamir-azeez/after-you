extends RefCounted
## Shared controls for the original islands and authored chapters.
const INK := Color("193d39")
const CREAM := Color("eceddb")

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

static func inset_button(button: Button, horizontal: float = 16, vertical: float = 8) -> void:
	for state: String in ["normal","hover","pressed","hover_pressed","disabled"]:
		var style := button.get_theme_stylebox(state).duplicate() as StyleBox
		style.content_margin_left = horizontal
		style.content_margin_right = horizontal
		style.content_margin_top = vertical
		style.content_margin_bottom = vertical
		button.add_theme_stylebox_override(state,style)

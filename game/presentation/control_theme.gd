extends RefCounted
## Shared button states for the original islands and authored chapters.
const INK := Color("193d39")
const CREAM := Color("eceddb")

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

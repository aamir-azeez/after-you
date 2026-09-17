extends RefCounted
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Shared player-facing actions. Controllers retain callbacks and availability.
const ControlTheme = preload("res://presentation/control_theme.gd")
const ICONS := {
	"play": preload("res://assets/ui/play.svg"),
	"retry": preload("res://assets/ui/retry.svg"),
	"pause": preload("res://assets/ui/pause.svg"),
	"finish": preload("res://assets/ui/finish.svg"),
	"save": preload("res://assets/ui/check.svg"),
	"back": preload("res://assets/ui/back.svg"),
	"next": preload("res://assets/ui/next.svg"),
	"record": preload("res://assets/ui/record.svg"),
}
const DEFINITIONS := {
	"record": {"label": "Record", "icon": "record", "primary": true, "hint": PlayerCopy.ACTION_BUTTONS_720AD17C8CC7},
	"resume": {"label": "Resume", "icon": "play", "primary": true, "hint": PlayerCopy.ACTION_BUTTONS_B35F6908BD12},
	"retry": {"label": "Retry", "icon": "retry", "primary": false, "hint": PlayerCopy.ACTION_BUTTONS_E434AB682F32},
	"preview": {"label": "Preview", "icon": "play", "primary": false, "hint": PlayerCopy.ACTION_BUTTONS_7AD5ED12D806},
	"save": {"label": "Save turn", "icon": "save", "primary": true, "hint": PlayerCopy.ACTION_BUTTONS_6FB275114778},
	"finish": {"label": "Finish", "icon": "finish", "primary": false, "hint": PlayerCopy.ACTION_BUTTONS_7B0D22BC0FEC},
	"pause": {"label": "Pause", "icon": "pause", "primary": false, "hint": "Pause the game."},
	"continue": {"label": "Continue", "icon": "next", "primary": true, "hint": PlayerCopy.ACTION_BUTTONS_C3D6912E5E40},
	"back": {"label": "Back", "icon": "back", "primary": false, "hint": PlayerCopy.ACTION_BUTTONS_09F37563336D},
	"leave_draft": {"label": "Back", "icon": "back", "primary": false, "hint": PlayerCopy.ACTION_BUTTONS_D37398B29BC6},
	"retry_save": {"label": "Retry save", "icon": "retry", "primary": true, "hint": PlayerCopy.ACTION_BUTTONS_DCBA5AB65E41},
	"leave_unsaved": {"label": "Leave without saving", "icon": "back", "primary": false, "hint": PlayerCopy.ACTION_BUTTONS_46C4ED81FF3A},
	"refresh": {"label": "Refresh", "icon": "retry", "primary": false, "hint": "Check for updates."},
	"check_saved": {"label": "Check status", "icon": "retry", "primary": true, "hint": PlayerCopy.ACTION_BUTTONS_2C04AA881C37},
	"replay": {"label": "Replay", "icon": "play", "primary": false, "hint": PlayerCopy.ACTION_BUTTONS_AFC0AFCCC64C},
	"replays": {"label": "Replays", "icon": "play", "primary": false, "hint": PlayerCopy.ACTION_BUTTONS_6ABB187E5B3A},
	"review": {"label": "Review", "icon": "next", "primary": true, "hint": PlayerCopy.ACTION_BUTTONS_2EA711DFB723},
	"cancel": {"label": "Cancel", "icon": "back", "primary": false, "hint": PlayerCopy.ACTION_BUTTONS_D425C3411671},
}

static func create(action_id: String, callback: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size.y = 50
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	apply(button, action_id)
	button.pressed.connect(callback)
	return button

static func apply(button: Button, action_id: String) -> void:
	assert(DEFINITIONS.has(action_id), "Unknown shared button action: " + action_id)
	var definition: Dictionary = DEFINITIONS[action_id]
	button.text = definition.label
	button.icon = ICONS[definition.icon]
	button.tooltip_text = definition.hint
	button.set_meta("action_id", action_id)
	button.add_theme_constant_override("h_separation", 10)
	button.add_theme_constant_override("icon_max_width", 22)
	var primary: bool = definition.primary
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var disabled := state == "disabled"
		var fill := Color("3e5e55") if disabled else Color("eceddb") if primary else Color("254b45")
		if state == "hover": fill = Color("ffffff") if primary else Color("325e54")
		if state in ["pressed", "hover_pressed"]: fill = Color("a6d9c4") if primary else Color("386a5e")
		var foreground := Color("9aaaa3") if disabled else ControlTheme.INK if primary else ControlTheme.CREAM
		var style := ControlTheme.rounded(fill, 16, Color.TRANSPARENT if primary else Color("54766a"))
		style.content_margin_left = 16
		style.content_margin_right = 16
		button.add_theme_stylebox_override(state, style)
		button.add_theme_color_override("font_color" if state == "normal" else "font_" + state + "_color", foreground)
		button.add_theme_color_override("icon_" + state + "_color", foreground)
	button.add_theme_color_override("font_focus_color", ControlTheme.INK if primary else ControlTheme.CREAM)
	button.add_theme_color_override("icon_focus_color", ControlTheme.INK if primary else ControlTheme.CREAM)
	button.add_theme_stylebox_override("focus", ControlTheme.rounded(Color.TRANSPARENT, 16, Color("a6d9c4")))

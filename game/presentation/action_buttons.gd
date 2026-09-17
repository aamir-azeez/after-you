extends RefCounted
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
	"record": {"label": "Record", "icon": "record", "primary": true, "hint": "Start recording this turn."},
	"resume": {"label": "Resume", "icon": "play", "primary": true, "hint": "Continue where you paused."},
	"retry": {"label": "Retry", "icon": "retry", "primary": false, "hint": "Start this turn again. Saved checkpoints stay unchanged."},
	"preview": {"label": "Preview", "icon": "play", "primary": false, "hint": "Watch this recording before saving."},
	"save": {"label": "Save turn", "icon": "save", "primary": true, "hint": "Keep this recording and continue."},
	"finish": {"label": "Finish", "icon": "finish", "primary": false, "hint": "Finish recording and review your turn."},
	"pause": {"label": "Pause", "icon": "pause", "primary": false, "hint": "Pause the game."},
	"continue": {"label": "Continue", "icon": "next", "primary": true, "hint": "Continue from your saved checkpoint."},
	"back": {"label": "Back", "icon": "back", "primary": false, "hint": "Return to the previous screen."},
	"leave_draft": {"label": "Back", "icon": "back", "primary": false, "hint": "Leave this screen and keep your saved draft."},
	"retry_save": {"label": "Retry save", "icon": "retry", "primary": true, "hint": "Try saving this same turn again."},
	"leave_unsaved": {"label": "Leave without saving", "icon": "back", "primary": false, "hint": "Leave without the part that could not be saved."},
	"refresh": {"label": "Refresh", "icon": "retry", "primary": false, "hint": "Check for updates."},
	"check_saved": {"label": "Check status", "icon": "retry", "primary": true, "hint": "Check whether your saved submission was accepted."},
	"replay": {"label": "Replay", "icon": "play", "primary": false, "hint": "Watch from the beginning."},
	"replays": {"label": "Replays", "icon": "play", "primary": false, "hint": "Watch your saved stages."},
	"review": {"label": "Review", "icon": "next", "primary": true, "hint": "Review this turn before saving."},
	"cancel": {"label": "Cancel", "icon": "back", "primary": false, "hint": "Keep your current progress."},
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

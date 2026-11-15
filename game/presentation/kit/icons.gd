extends RefCounted
## Icons that mean the same thing on every screen, so one change here reaches
## each place that shows them (tests/test_shared_paths.gd (l) holds the
## leaderboard one to this file).
##
## LEADERBOARD: the Phosphor "trophy" (assets/ui/social, MIT, with its
## LICENSE.txt), the owner's pick for every leaderboard button, row and title
## (2026-11-03). What's new names it "trophy" (presentation/whats_new_kit.gd).
const LEADERBOARD = preload("res://assets/ui/social/trophy.svg")
const ControlTheme = preload("res://presentation/control_theme.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")

## REPORT: the flag (assets/ui/room) on every Report button, the Room options
## Report or block row and the race picker's Race.
const REPORT = preload("res://assets/ui/room/flag.svg")
## Report's flag button is this square, and its flag this wide.
const REPORT_TARGET := 44.0
const REPORT_ICON_SIDE := 26.0

## Report as the flag alone on an outlined square tab (the leaderboard's rows,
## the pause cards' corner). Soft until touched, with no words, so the row's
## main action still leads; `description` names it for screen readers.
static func report_button(action: Callable, description: String) -> Button:
	var button := Button.new()
	button.icon = REPORT
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.tooltip_text = description
	button.accessibility_name = description
	button.add_theme_constant_override("icon_max_width", int(REPORT_ICON_SIDE))
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(REPORT_TARGET, REPORT_TARGET)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ControlTheme.outlined_tab(button)
	# The tab's padding is for words; the flag needs the square's room.
	var room := (REPORT_TARGET - REPORT_ICON_SIDE) / 2.0
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		ControlTheme.padded(button.get_theme_stylebox(state), room, room)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		button.add_theme_color_override("icon_" + state + "_color", UiTokens.SOFT if state == "normal" else UiTokens.CREAM)
	button.pressed.connect(action)
	return button

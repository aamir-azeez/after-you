extends RefCounted
## The Home square beside a menu screen's Back (presentation/menu_back.gd puts
## it there): the same coral square as Back, with the house, straight Home.
## It never takes Android Back, which stays on Back.
const ControlTheme = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const HOME_ICON = preload("res://assets/ui/whats_new/home.svg")
const NAME := "MenuHome"

## The square right after `back` in its row, shown or hidden; made once per
## page, so a screen that opens again keeps one.
static func attach(back: Button, shown: bool, home: Callable) -> Button:
	var row := back.get_parent()
	if row == null: return null
	var square := row.get_node_or_null(NAME) as Button
	if square == null:
		square = Button.new()
		square.name = NAME
		square.custom_minimum_size = back.custom_minimum_size
		square.size_flags_vertical = back.size_flags_vertical
		square.tooltip_text = PlayerCopy.MENU_HOME
		square.accessibility_name = PlayerCopy.MENU_HOME
		square.expand_icon = true
		square.focus_mode = back.focus_mode
		ControlTheme.danger(square, HOME_ICON)
		square.pressed.connect(func() -> void: home.call())
		row.add_child(square)
		row.move_child(square, back.get_index() + 1)
	square.visible = shown
	return square

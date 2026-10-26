extends PanelContainer
## The Display name section in the Friends header: the player's own pip (a
## still kit/pip_avatar.gd, drawn once by the shared renderer), "YOUR NAME" over the name others
## see, a quiet line while it waits to be sent or after the server said no,
## and Change, which opens the prompt to change it. display_name_flow.gd builds
## it and calls show_name() whenever the name changes.
const ThemeRules = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DisplayNames = preload("res://services/display_names.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const PENCIL_ICON = preload("res://assets/ui/social/pencil-simple.svg")
const MUTED := Color("afc6be")
const ERROR := Color("f2b8ae")

signal change_requested(source: Control)

var preview: Control
var name_label: Label
var status_label: Label
var change_button: Button

func _init(reduced_motion: bool = false) -> void:
	name = "DisplayNameChip"
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(ThemeRules.CHOICE_PANEL, 18, ThemeRules.CHOICE_BORDER), 8.0, 4.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	# Small enough that the chip is no taller than the title beside it.
	preview = PipAvatar.new(reduced_motion, PipAvatar.PEACH, Vector2(42, 56), true, true)
	preview.name = "DisplayNameChipPip"
	row.add_child(preview)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", -2)
	# Wide enough for the status line under a short name, so it never cuts.
	words.custom_minimum_size.x = 96
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(words)
	var small := Label.new()
	small.text = PlayerCopy.DISPLAY_NAME_SECTION.to_upper()
	small.add_theme_font_size_override("font_size", 13)
	small.add_theme_color_override("font_color", MUTED)
	words.add_child(small)
	name_label = Label.new()
	name_label.name = "DisplayNameChipName"
	name_label.add_theme_font_size_override("font_size", 21)
	words.add_child(name_label)
	status_label = Label.new()
	status_label.name = "DisplayNameChipStatus"
	status_label.add_theme_font_size_override("font_size", 15)
	# Clipped, so the line never widens the chip when it appears.
	status_label.clip_text = true
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.visible = false
	words.add_child(status_label)
	change_button = Button.new()
	change_button.name = "DisplayNameChange"
	change_button.text = PlayerCopy.DISPLAY_NAME_CHANGE
	change_button.icon = PENCIL_ICON
	change_button.add_theme_constant_override("icon_max_width", 18)
	change_button.custom_minimum_size = Vector2(0, 50)
	change_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ThemeRules.secondary(change_button)
	ThemeRules.inset_button(change_button, 14, 6)
	change_button.pressed.connect(func() -> void: change_requested.emit(change_button))
	row.add_child(change_button)

## The name others see now, and where the player's own choice stands
## (DisplayNames.own()): pending shows a quiet line, refused a warning one.
func show_name(shown: String, own: Dictionary) -> void:
	name_label.text = DisplayNames.short(shown)
	change_button.accessibility_name = PlayerCopy.DISPLAY_NAME_CHANGE_FOR % shown
	var state := str(own.get("state", ""))
	status_label.visible = state in [DisplayNames.PENDING, DisplayNames.REFUSED]
	status_label.text = PlayerCopy.DISPLAY_NAME_NOT_SAVED if state == DisplayNames.REFUSED else PlayerCopy.DISPLAY_NAME_PENDING
	status_label.add_theme_color_override("font_color", ERROR if state == DisplayNames.REFUSED else MUTED)

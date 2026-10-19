extends PanelContainer
## The small pill with the retry mark that shows a turn's try count: "Try 3"
## under the stage line in play (cream, bold, with a faint ink edge so it holds
## on bright scenery), and a turn's count in Replays (quiet: Replays keeps
## cream for its main action). One shape, radius, icon and padding for both.
## Presentation only; the counts come from services/turn_tries.gd.
const ControlTheme = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DisplayNames = preload("res://services/display_names.gd")
const ICON := preload("res://assets/ui/retry.svg")
const MUTED := Color("9dbeb4")
## A long name is cut so one pill never runs past its row.
const MAX_NAME := DisplayNames.MAX_LENGTH

var label: Label
var _icon: TextureRect

func _init(font_size: int = 18, quiet: bool = false) -> void:
	name = "TryPill"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var radius := int(float(font_size) * 0.95)
	var look := ControlTheme.rounded(ControlTheme.CHOICE_PANEL, radius, ControlTheme.CHOICE_BORDER) if quiet else ControlTheme.rounded(ControlTheme.CREAM, radius, Color(ControlTheme.INK, 0.25))
	add_theme_stylebox_override("panel", ControlTheme.padded(look, float(font_size) * 0.7, float(font_size) * 0.3))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(font_size * 0.4))
	add_child(row)
	_icon = TextureRect.new()
	_icon.texture = ICON
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2.ONE * float(font_size + (0 if quiet else 1))
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.modulate = MUTED if quiet else ControlTheme.INK
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ControlTheme.CREAM if quiet else ControlTheme.INK)
	if not quiet:
		var bold := FontVariation.new()
		bold.base_font = preload("res://assets/fonts/nunito.ttf")
		bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800.0}
		label.add_theme_font_override("font", bold)
	row.add_child(label)

## The pill in play: "Try 2" and on, hidden on the first try. With `text`
## (a hard run, which has no second try), that line instead, without the
## retry mark.
func show_try(tries: int, text: String = "") -> void:
	_icon.visible = text.is_empty()
	visible = tries > 1 or not text.is_empty()
	if visible: label.text = text if not text.is_empty() else PlayerCopy.TRY_PILL % tries

## A Replays pill for one turn: who played it and how many tries it took.
func show_turn(who: String, tries: int) -> void:
	visible = tries > 1
	label.text = PlayerCopy.TRY_COUNT % [DisplayNames.short(who, MAX_NAME), tries]

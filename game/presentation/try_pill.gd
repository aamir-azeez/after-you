extends PanelContainer
## The small pill with the retry mark that shows a turn's try count: "Try 3"
## under the stage line in play (cream, bold, with a faint ink edge so it holds
## on bright scenery), and a turn's count in Replays (quiet: Replays keeps
## cream for its main action). One shape, radius, icon and padding for both.
## A Replays turn played on its first try gets the mint First try chip, with a
## check mark in place of the retry mark (the retry count concept).
## Presentation only; the counts come from services/turn_tries.gd.
const ControlTheme = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DisplayNames = preload("res://services/display_names.gd")
const ICON := preload("res://assets/ui/retry.svg")
const MUTED := Color("9dbeb4")
## The First try chip's fill: the kit's mint.
const FIRST_FILL := Color("a9e0c6")
## A long name is cut so one pill never runs past its row.
const MAX_NAME := DisplayNames.MAX_LENGTH

var label: Label
var _icon: TextureRect
var _check: Control
var _font_size := 18

func _init(font_size: int = 18, quiet: bool = false) -> void:
	name = "TryPill"
	_font_size = font_size
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
	if not quiet: label.add_theme_font_override("font", _bold())
	row.add_child(label)

## The pills' bold Nunito. Made per pill: a static font would hold text
## server resources past shutdown (see presentation/kit/session_release.gd).
static func _bold() -> FontVariation:
	var bold := FontVariation.new()
	bold.base_font = preload("res://assets/fonts/nunito.ttf")
	bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800.0}
	return bold

## The pill in play: "Try 2" and on, hidden on the first try. With `text`
## (a hard run, which has no second try), that line instead, without the
## retry mark.
func show_try(tries: int, text: String = "") -> void:
	_icon.visible = text.is_empty()
	visible = tries > 1 or not text.is_empty()
	if visible: label.text = text if not text.is_empty() else PlayerCopy.TRY_PILL % tries

## A Replays pill for one turn: who played it and how many tries it took, or
## the First try chip when it took one. Hidden when no count was kept (a turn
## from an older build).
func show_turn(who: String, tries: int) -> void:
	visible = tries > 0
	var short := DisplayNames.short(who, MAX_NAME)
	if tries == 1: _first_try(short)
	else: label.text = PlayerCopy.TRY_COUNT % [short, tries]

## Whether this pill is the First try chip.
func first_try() -> bool:
	return is_instance_valid(_check) and _check.visible

func _first_try(who: String) -> void:
	var radius := int(float(_font_size) * 0.95)
	add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(FIRST_FILL, radius, Color(ControlTheme.INK, 0.15)), float(_font_size) * 0.7, float(_font_size) * 0.3))
	label.text = PlayerCopy.TRY_FIRST % who
	label.add_theme_color_override("font_color", ControlTheme.INK)
	label.add_theme_font_override("font", _bold())
	_icon.visible = false
	if not is_instance_valid(_check):
		_check = CheckMark.new(float(_font_size))
		_icon.get_parent().add_child(_check)
		_icon.get_parent().move_child(_check, 0)
	_check.visible = true


## The First try chip's check mark, drawn in ink to the retry mark's size.
class CheckMark extends Control:
	func _init(side: float) -> void:
		name = "FirstTryCheck"
		custom_minimum_size = Vector2.ONE * side
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var s := size.y
		draw_polyline(PackedVector2Array([Vector2(s * 0.14, s * 0.52), Vector2(s * 0.4, s * 0.78), Vector2(s * 0.88, s * 0.24)]), ControlTheme.INK, maxf(2.0, s * 0.15), true)

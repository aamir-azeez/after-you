extends HBoxContainer
## The Pollen balance chip, and the one chip the game uses (pollen board 1): one
## pill split in two. The left half holds the Pollen mark (kit/pollen_mark.gd)
## and the balance with thousands commas; a tap there is `amount_pressed` (the
## Pollen page). The right half is a plus, only where the Pollen store can sell
## and is not the screen showing the chip; a tap there is `plus_pressed` (the
## store). Without the plus the chip is the left half alone, a whole pill. A
## zero balance is the same plain chip. Home shows it left of Full Journey; the
## Wardrobe, the Pollen store and the Pollen page in their headers.
##
## Each half is its own Button, so a finger lands on exactly one of them and
## the first tap registers; the pill around them takes no input.
##
## show_gain() is the optional moment just after earning: the gain beside the
## amount ("24,125 +125") with a gold edge, gone after a moment (at once under
## Reduce motion). The chip never works out a gain itself: whoever shows it
## knows what the player last saw (presentation/pollen_play_flow.gd for Home).
## One tween per gain; nothing runs per frame.
const PollenMark = preload("res://presentation/kit/pollen_mark.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")
const PLUS := preload("res://assets/ui/social/plus.svg")

const FONT_SIZE := 22
const HEIGHT := 54.0
## The plus half: wide enough for a thumb, the plus centred in it.
const PLUS_WIDTH := 58.0
const RADIUS := 27
## The gain's gold, from the store card's gold family (board 1), never a grain colour.
const GOLD := Color("f1c48a")
## How long the gain stays before it fades, and the fade.
const GAIN_HOLD := 2.4
const GAIN_FADE := 0.6

signal amount_pressed
signal plus_pressed

## The left half (mark, amount, gain).
var amount_button: Button
var amount_label: Label
var gain_label: Label
## The right half and its plus, or null without one.
var plus_button: Button
var plus_icon: TextureRect
var _row: HBoxContainer

## A chip for `balance`; `plus`: show the plus half.
static func make(balance: int, plus: bool) -> Control:
	var chip: Control = load("res://presentation/kit/pollen_chip.gd").new()
	chip._build(balance, plus)
	return chip

func _build(balance: int, plus: bool) -> void:
	name = "PollenChip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 0)
	amount_button = _half("PollenChipBalance", PlayerCopy.POLLEN_CHIP_BALANCE % PollenMoney.grouped(balance))
	amount_button.pressed.connect(func() -> void: amount_pressed.emit())
	_row = HBoxContainer.new()
	_row.name = "PollenChipRow"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 10)
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_row.offset_left = 18
	_row.offset_right = -16 if plus else -20
	amount_button.add_child(_row)
	_row.add_child(PollenMark.beside(FONT_SIZE))
	amount_label = _text(PollenMoney.grouped(balance), UiTokens.CREAM)
	amount_label.name = "PollenChipAmount"
	_row.add_child(amount_label)
	gain_label = _text("", GOLD)
	gain_label.name = "PollenChipGain"
	gain_label.visible = false
	_row.add_child(gain_label)
	if plus:
		plus_button = _half("PollenChipPlusButton", PlayerCopy.WARDROBE_GET_POLLEN)
		plus_button.custom_minimum_size = Vector2(PLUS_WIDTH, HEIGHT)
		plus_button.pressed.connect(func() -> void: plus_pressed.emit())
		# The store needs the server: the plus greys while offline (presentation/offline_hold.gd).
		OfflineHold.hold(plus_button)
		plus_icon = TextureRect.new()
		plus_icon.name = "PollenChipPlus"
		plus_icon.texture = PLUS
		plus_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		plus_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		plus_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plus_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		plus_icon.custom_minimum_size = Vector2(28, 28)
		plus_icon.offset_left = -14
		plus_icon.offset_top = -14
		plus_icon.offset_right = 14
		plus_icon.offset_bottom = 14
		plus_button.add_child(plus_icon)
	_style(UiTokens.SECONDARY_BORDER)
	_fit()
	_row.minimum_size_changed.connect(_fit)

func _half(node_name: String, spoken: String) -> Button:
	var half := Button.new()
	half.name = node_name
	half.focus_mode = Control.FOCUS_ALL
	half.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	half.tooltip_text = spoken
	half.accessibility_name = spoken
	half.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(half)
	return half

## The left half is as wide as its row needs, and the chip HEIGHT tall.
func _fit() -> void:
	amount_button.custom_minimum_size = Vector2(_row.get_combined_minimum_size().x + _row.offset_left - _row.offset_right, HEIGHT)

## Shows `gain` beside the amount for a moment, then lets it go.
func show_gain(gain: int, reduced_motion: bool) -> void:
	if gain <= 0: return
	gain_label.text = "+" + PollenMoney.grouped(gain)
	gain_label.modulate.a = 1.0
	gain_label.visible = true
	_style(GOLD)
	if is_inside_tree(): _fade(reduced_motion)
	else: tree_entered.connect(_fade.bind(reduced_motion), CONNECT_ONE_SHOT)

func _fade(reduced_motion: bool) -> void:
	var tween := create_tween()
	tween.tween_interval(GAIN_HOLD)
	if not reduced_motion: tween.tween_property(gain_label, "modulate:a", 0.0, GAIN_FADE)
	tween.tween_callback(func() -> void:
		gain_label.visible = false
		_style(UiTokens.SECONDARY_BORDER))

## Both halves in `edge`: the left rounded on its left (all round without the
## plus), the plus rounded on its right, its left edge the line between them.
func _style(edge: Color) -> void:
	var split := plus_button != null
	_style_half(amount_button, edge, true, not split)
	if split: _style_half(plus_button, edge, false, true)

static func _style_half(half: Button, edge: Color, left: bool, right: bool) -> void:
	var fills := {"normal": UiTokens.NIGHT_GLASS, "hover": UiTokens.SECONDARY, "pressed": UiTokens.SELECTED, "hover_pressed": UiTokens.SELECTED, "disabled": UiTokens.NIGHT_GLASS}
	for state: String in fills:
		var style := _shape(ControlTheme.rounded(fills[state], RADIUS, edge), left, right)
		style.set_border_width_all(2)
		# The left half leaves the line between the halves to the plus.
		if not right: style.border_width_right = 0
		half.add_theme_stylebox_override(state, style)
	var ring := _shape(ControlTheme.rounded(Color.TRANSPARENT, RADIUS, UiTokens.MINT), left, right)
	ring.set_border_width_all(2)
	half.add_theme_stylebox_override("focus", ring)

## `style` with its corners rounded only on the `left` and `right` sides asked for.
static func _shape(style: StyleBoxFlat, left: bool, right: bool) -> StyleBoxFlat:
	if not left:
		style.corner_radius_top_left = 0
		style.corner_radius_bottom_left = 0
	if not right:
		style.corner_radius_top_right = 0
		style.corner_radius_bottom_right = 0
	return style

static func _text(value: String, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label

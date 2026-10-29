extends Button
## The Pollen balance chip, and the one chip the game uses (pollen board 1): the
## Pollen mark (kit/pollen_mark.gd), the balance with thousands commas, and a
## plus while the shop sells (iOS without a store and a server with the shop off
## show none). A zero balance is the same plain chip. Home shows it left of Full
## Journey; the Wardrobe, the Pollen store and Pollen from play in their headers.
##
## show_gain() is the optional moment just after earning: the gain beside the
## amount ("24,125 +125") with a gold edge, gone after a moment (at once under
## Reduce motion). The chip never works out a gain itself: whoever shows it
## knows what the player last saw (presentation/pollen_play_flow.gd for Home).
## One tween per gain; nothing runs per frame.
const PollenMark = preload("res://presentation/kit/pollen_mark.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const PLUS := preload("res://assets/ui/social/plus.svg")

const FONT_SIZE := 22
const HEIGHT := 54.0
## The gain's gold, from the store card's gold family (board 1), never a grain colour.
const GOLD := Color("f1c48a")
## How long the gain stays before it fades, and the fade.
const GAIN_HOLD := 2.4
const GAIN_FADE := 0.6

var amount_label: Label
var gain_label: Label
## The plus, or null while the shop does not sell.
var plus_icon: TextureRect
var _row: HBoxContainer

## A chip for `balance`; `shop`: show the plus.
static func make(balance: int, shop: bool) -> Button:
	var chip: Button = load("res://presentation/kit/pollen_chip.gd").new()
	chip._build(balance, shop)
	return chip

func _build(balance: int, shop: bool) -> void:
	name = "PollenChip"
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Pollen"
	accessibility_name = "Pollen: %s" % PollenMoney.grouped(balance)
	_style(UiTokens.SECONDARY_BORDER)
	_row = HBoxContainer.new()
	_row.name = "PollenChipRow"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 10)
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_row.offset_left = 18
	_row.offset_right = -14 if shop else -20
	add_child(_row)
	_row.add_child(PollenMark.beside(FONT_SIZE))
	amount_label = _text(PollenMoney.grouped(balance), UiTokens.CREAM)
	amount_label.name = "PollenChipAmount"
	_row.add_child(amount_label)
	gain_label = _text("", GOLD)
	gain_label.name = "PollenChipGain"
	gain_label.visible = false
	_row.add_child(gain_label)
	if shop:
		plus_icon = TextureRect.new()
		plus_icon.name = "PollenChipPlus"
		plus_icon.texture = PLUS
		plus_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		plus_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		plus_icon.custom_minimum_size = Vector2(28, 28)
		plus_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		plus_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row.add_child(plus_icon)
	_fit()
	_row.minimum_size_changed.connect(_fit)

## The chip is as wide as its row needs, and HEIGHT tall.
func _fit() -> void:
	custom_minimum_size = Vector2(_row.get_combined_minimum_size().x + _row.offset_left - _row.offset_right, HEIGHT)

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

func _style(edge: Color) -> void:
	var fills := {"normal": UiTokens.NIGHT_GLASS, "hover": UiTokens.SECONDARY, "pressed": UiTokens.SELECTED, "hover_pressed": UiTokens.SELECTED, "disabled": UiTokens.NIGHT_GLASS}
	for state: String in fills:
		var style := ControlTheme.rounded(fills[state], 27, edge)
		style.set_border_width_all(2)
		add_theme_stylebox_override(state, style)
	var ring := ControlTheme.rounded(Color.TRANSPARENT, 27, UiTokens.MINT)
	ring.set_border_width_all(2)
	add_theme_stylebox_override("focus", ring)

static func _text(value: String, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label

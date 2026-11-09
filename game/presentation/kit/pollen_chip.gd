extends HBoxContainer
## The money chip, and the one chip the game uses (pollen board 1, Fruits
## board 2): one pill split into halves. The left half holds the Pollen mark
## and the balance with thousands commas; a tap there is `amount_pressed` (the
## Pollen page). While Fruits show (services/pollen_surfaces.gd fruits_visible,
## asked through fruits_for()), the next half sits on the Orchard plum
## (kit/orchard_surface.gd) with the Fruit mark and the Fruit balance, 0 for a
## player with none yet; a tap there is `fruits_pressed` (the Fruits page). The
## last half is a plus, only where the store can sell and is not the screen
## showing the chip; a tap there is `plus_pressed` (the store). Without the plus
## the last amount half closes the pill. A zero balance is the same plain chip.
## Home shows it left of Full Journey; the Wardrobe, the store, the Pollen page
## and the Fruits page in their headers. Every mark comes from kit/currency_mark.gd.
##
## Each half is its own Button, so a finger lands on exactly one of them and
## the first tap registers; the pill around them takes no input.
##
## show_gain() is the optional moment just after earning: the gain beside the
## amount ("24,125 +125") with a gold edge, gone after a moment (at once under
## Reduce motion). The chip never works out a gain itself: whoever shows it
## knows what the player last saw (presentation/pollen_play_flow.gd for Home).
## One tween per gain; nothing runs per frame.
const CurrencyMark = preload("res://presentation/kit/currency_mark.gd")
const Orchard = preload("res://presentation/kit/orchard_surface.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const FruitWallet = preload("res://services/fruit_wallet.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")

const FONT_SIZE := 22
const HEIGHT := 54.0
## The plus half: wide enough for a thumb, the plus centred in it.
const PLUS_WIDTH := 58.0
## The plus's half length and stroke against its box, as the line icon draws them (assets/ui/social/plus.svg).
const PLUS_ARM := 0.34
const PLUS_STROKE := 0.0625
const RADIUS := 27
## The gain's gold, from the store card's gold family (board 1), never a grain colour.
const GOLD := Color("f1c48a")
## How long the gain stays before it fades, and the fade.
const GAIN_HOLD := 2.4
const GAIN_FADE := 0.6

signal amount_pressed
signal plus_pressed
## The Fruit half: the Fruits page.
signal fruits_pressed

## The left half (mark, amount, gain).
var amount_button: Button
var amount_label: Label
var gain_label: Label
## The Fruit half and its amount, or null while Fruits do not show.
var fruits_button: Button
var fruits_label: Label
## The right half and its plus, or null without one.
var plus_button: Button
var plus_icon: Control
var _row: HBoxContainer
var _fruit_row: HBoxContainer

## A chip for `balance`; `plus`: show the plus half; `fruits`: [] hides the
## Fruit half, [n] shows it with n Fruits (fruits_for() says which).
static func make(balance: int, plus: bool, fruits: Array = []) -> Control:
	var chip: Control = load("res://presentation/kit/pollen_chip.gd").new()
	chip._build(balance, plus, fruits)
	return chip

## What the Fruit half shows for the player of `scope`: [] while Fruits do not
## show (the build or the server), else [the kept Fruit balance], [0] until the
## server has said. `surfaces` and `fruits` default to the shared ones.
static func fruits_for(scope: Dictionary, surfaces: RefCounted = null, fruits: RefCounted = null) -> Array:
	var shown: RefCounted = surfaces if surfaces != null else PollenSurfaces.shared()
	var store: RefCounted = fruits if fruits != null else FruitWallet.shared()
	if scope.is_empty() or not shown.fruits_visible(store, scope): return []
	return [int(store.balance(str(scope.server), str(scope.owner)))]

func _build(balance: int, plus: bool, fruits: Array = []) -> void:
	name = "PollenChip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 0)
	amount_button = _half("PollenChipBalance", PlayerCopy.POLLEN_CHIP_BALANCE % PollenMoney.grouped(balance))
	amount_button.pressed.connect(func() -> void: amount_pressed.emit())
	_row = _half_row("PollenChipRow", plus or not fruits.is_empty())
	amount_button.add_child(_row)
	_row.add_child(CurrencyMark.beside(CurrencyMark.POLLEN, FONT_SIZE))
	amount_label = _text(PollenMoney.grouped(balance), UiTokens.CREAM)
	amount_label.name = "PollenChipAmount"
	_row.add_child(amount_label)
	gain_label = _text("", GOLD)
	gain_label.name = "PollenChipGain"
	gain_label.visible = false
	_row.add_child(gain_label)
	if not fruits.is_empty(): _fruit_half(int(fruits[0]), plus)
	if plus:
		plus_button = _half("PollenChipPlusButton", PlayerCopy.WARDROBE_GET_POLLEN)
		plus_button.custom_minimum_size = Vector2(PLUS_WIDTH, HEIGHT)
		plus_button.pressed.connect(func() -> void: plus_pressed.emit())
		# The store needs the server: the plus greys while offline (presentation/offline_hold.gd).
		OfflineHold.hold(plus_button)
		# Drawn as two strokes, so it stays a plus at any scale (a phone 360 tall halves it).
		plus_icon = Control.new()
		plus_icon.name = "PollenChipPlus"
		plus_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plus_icon.draw.connect(_draw_plus)
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

## The Fruit half: the Fruit mark and the Fruit balance on the Orchard plum.
func _fruit_half(fruits: int, plus: bool) -> void:
	fruits_button = _half("PollenChipFruits", PlayerCopy.FRUIT_CHIP_BALANCE % PollenMoney.grouped(fruits))
	fruits_button.pressed.connect(func() -> void: fruits_pressed.emit())
	_fruit_row = _half_row("PollenChipFruitRow", plus)
	fruits_button.add_child(_fruit_row)
	_fruit_row.add_child(CurrencyMark.beside(CurrencyMark.FRUITS, FONT_SIZE))
	fruits_label = _text(PollenMoney.grouped(fruits), UiTokens.CREAM)
	fruits_label.name = "PollenChipFruitAmount"
	_fruit_row.add_child(fruits_label)

## A half's mark and amount, centred, a little tighter on the side another half follows.
static func _half_row(node_name: String, followed: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = node_name
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 18
	row.offset_right = -16 if followed else -20
	return row

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

## The plus: the store's line icon's two strokes, in the chip's cream.
func _draw_plus() -> void:
	var box := plus_icon.size
	var middle := box * 0.5
	var arm := minf(box.x, box.y) * PLUS_ARM
	var width := maxf(minf(box.x, box.y) * PLUS_STROKE, 1.5)
	plus_icon.draw_line(middle - Vector2(arm, 0), middle + Vector2(arm, 0), UiTokens.CREAM, width, true)
	plus_icon.draw_line(middle - Vector2(0, arm), middle + Vector2(0, arm), UiTokens.CREAM, width, true)

## Each amount half is as wide as its row needs, and the chip HEIGHT tall.
func _fit() -> void:
	amount_button.custom_minimum_size = Vector2(_row.get_combined_minimum_size().x + _row.offset_left - _row.offset_right, HEIGHT)
	if fruits_button != null: fruits_button.custom_minimum_size = Vector2(_fruit_row.get_combined_minimum_size().x + _fruit_row.offset_left - _fruit_row.offset_right, HEIGHT)

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

## Every half in `edge`: the first rounded on its left, the last on its right
## (one half alone is all round), each later half's left edge the line between.
## The Fruit half keeps the chip's edge, filled with the Orchard plum.
func _style(edge: Color) -> void:
	var halves: Array[Button] = [amount_button]
	if fruits_button != null: halves.append(fruits_button)
	if plus_button != null: halves.append(plus_button)
	for index in range(halves.size()):
		_style_half(halves[index], edge, index == 0, index == halves.size() - 1, halves[index] == fruits_button)

static func _style_half(half: Button, edge: Color, left: bool, right: bool, plum: bool = false) -> void:
	var fills := {"normal": UiTokens.NIGHT_GLASS, "hover": UiTokens.SECONDARY, "pressed": UiTokens.SELECTED, "hover_pressed": UiTokens.SELECTED, "disabled": UiTokens.NIGHT_GLASS}
	if plum: fills = {"normal": Orchard.PLUM_DARK, "hover": Orchard.PLUM, "pressed": Orchard.PLUM_LIGHT, "hover_pressed": Orchard.PLUM_LIGHT, "disabled": Orchard.PLUM_DARK}
	for state: String in fills:
		var style := _shape(ControlTheme.rounded(fills[state], RADIUS, edge), left, right)
		style.set_border_width_all(2)
		# Each half but the last leaves the line between it and the next to that one.
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

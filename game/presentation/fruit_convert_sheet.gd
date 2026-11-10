extends RefCounted
## Turn Fruits into Pollen (Fruits board 8), on the shared in-game modal: a
## plum box with the Fruits to turn (the Fruit, the count, minus and plus in
## the server's steps), an arrow, a cream box with the Pollen they make, then
## "Your Fruits 101 to 81" and "Your Pollen 24,000 to 30,000", the one way
## line, Cancel and "Turn 20 Fruits into Pollen". It starts at one step and
## goes up to the most whole steps the balance covers. Every number is the
## server's rule (services/fruit_wallet.gd convert_rules) worked out before the
## player confirms; the server pays the real amount.
##
## Drawing and the count only: presentation/fruit_spend_flow.gd opens it and
## sends the spend. The main button needs the server, so it greys offline
## (presentation/offline_hold.gd). No timer.
const InGameModal = preload("res://presentation/in_game_modal.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const CurrencyMark = preload("res://presentation/kit/currency_mark.gd")
const Orchard = preload("res://presentation/kit/orchard_surface.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")
const ButtonTicks = preload("res://presentation/button_ticks.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const ARROW := preload("res://assets/ui/social/arrow-right.svg")

const FRUITS := CurrencyMark.FRUITS
const POLLEN := CurrencyMark.POLLEN
const CREAM_BOX := Color("f3efdf")
const INK := Color("1d3230")
const SOFT_INK := Color("4d625d")
const MUTED := ShopKit.MUTED
const CREAM := ShopKit.CREAM
const BIG := 46
const META := "fruit_convert_sheet"

var modal: Control
var count := 0
var step := 10
var rate := 0
var fruits := 0
var pollen := 0
var less: Button
var more: Button
var confirm: Button
var _count_label: Label
var _made_label: Label
var _fruits_after: Label
var _pollen_after: Label
var _send: Callable

## Opens the card over `parent`: `rules` {pollen_per_fruit, step}, the Fruit and
## Pollen balances, and `send(count)` for the main button. Returns the sheet;
## its modal holds it while open.
static func open(parent: Control, rules: Dictionary, fruit_balance: int, pollen_balance: int, send: Callable, opener: Control = null, say: Callable = Callable()) -> RefCounted:
	var sheet: RefCounted = load("res://presentation/fruit_convert_sheet.gd").new()
	sheet._build(parent, rules, fruit_balance, pollen_balance, send, opener, say)
	return sheet

## The most Fruits the balance turns in whole steps (0 below one step).
static func most(balance: int, step_size: int) -> int:
	return 0 if step_size <= 0 or balance < step_size else floori(balance / float(step_size)) * step_size

func _build(parent: Control, rules: Dictionary, fruit_balance: int, pollen_balance: int, send: Callable, opener: Control, say: Callable) -> void:
	step = maxi(int(rules.get("step", 10)), 1)
	rate = int(rules.get("pollen_per_fruit", 0))
	fruits = fruit_balance
	pollen = pollen_balance
	count = mini(step, most(fruits, step))
	_send = send
	modal = InGameModal.open(parent, "FruitConvert", PlayerCopy.FRUIT_CONVERT_TITLE, PlayerCopy.FRUIT_CONVERT_NOTE, opener)
	modal.set_meta(META, self)
	modal.widen(720.0)
	var row := HBoxContainer.new()
	row.name = "FruitConvertBoxes"
	row.add_theme_constant_override("separation", 16)
	modal.content.add_child(row)
	row.add_child(_fruit_box())
	var arrow := TextureRect.new()
	arrow.texture = ARROW
	arrow.modulate = CREAM
	arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	arrow.custom_minimum_size = Vector2(34, 34)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow)
	row.add_child(_pollen_box())
	_fruits_after = _after(PlayerCopy.FRUIT_CONVERT_YOUR_FRUITS, FRUITS, fruits, "FruitConvertYourFruits")
	_pollen_after = _after(PlayerCopy.FRUIT_CONVERT_YOUR_POLLEN, POLLEN, pollen, "FruitConvertYourPollen")
	var once := ShopKit.text(PlayerCopy.FRUIT_CONVERT_ONE_WAY, 16, MUTED)
	once.name = "FruitConvertOneWay"
	modal.content.add_child(once)
	confirm = modal.add_actions("", _confirm, PlayerCopy.DISPLAY_NAME_CANCEL)
	confirm.name = "FruitConvertConfirm"
	Orchard.peach_button(confirm, 16)
	confirm.add_theme_font_override("font", ShopKit.bold_font())
	# The spend sounds its own chord once the server confirms it.
	ButtonTicks.quiet(confirm)
	OfflineHold.hold(confirm, say)
	var cancel: Button = modal.find_child("ModalCancel", true, false)
	if cancel != null: ControlTheme.secondary(cancel)
	_show()

## The plum box: the Fruit and the count, "Fruits", then minus and plus.
func _fruit_box() -> Control:
	var box := Orchard.card(18.0, false, Vector2(20, 14))
	box.name = "FruitConvertFruits"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	box.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	column.add_child(top)
	top.add_child(CurrencyMark.make(FRUITS, 58.0))
	var figures := VBoxContainer.new()
	figures.add_theme_constant_override("separation", -4)
	figures.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(figures)
	_count_label = ShopKit.text("", BIG, Orchard.TEXT, ShopKit.heading_font())
	_count_label.name = "FruitConvertCount"
	figures.add_child(_count_label)
	figures.add_child(ShopKit.text(PlayerCopy.FRUIT_CONVERT_FRUITS, 16, Orchard.TEXT_SOFT))
	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", 10)
	column.add_child(steps)
	less = _step_button("FruitConvertLess", PlayerCopy.FRUIT_CONVERT_LESS, -1)
	more = _step_button("FruitConvertMore", PlayerCopy.FRUIT_CONVERT_MORE, 1)
	steps.add_child(less)
	steps.add_child(more)
	return box

## A square outlined step button with its drawn minus or plus.
func _step_button(node_name: String, spoken: String, direction: int) -> Button:
	var button := Button.new()
	button.name = node_name
	button.accessibility_name = spoken
	button.tooltip_text = spoken
	button.custom_minimum_size = Vector2(52, 52)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var fill := Orchard.PLUM_DARK
		if state == "hover": fill = Orchard.PLUM
		if state in ["pressed", "hover_pressed"]: fill = Orchard.PLUM_LIGHT
		var style := Orchard.flat(12, fill, Orchard.TEXT_SOFT if state != "disabled" else Color(Orchard.TEXT_SOFT, 0.3))
		if state == "focus": style = Orchard.flat(12, Color.TRANSPARENT, Orchard.TEXT)
		button.add_theme_stylebox_override(state, style)
	var sign := Sign.new()
	sign.plus = direction > 0
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sign.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sign.custom_minimum_size = Vector2(24, 24)
	sign.offset_left = -12
	sign.offset_top = -12
	sign.offset_right = 12
	sign.offset_bottom = 12
	button.add_child(sign)
	button.pressed.connect(func() -> void: change(direction))
	return button

## The cream box: the Pollen the count makes, "Pollen", and a few grains.
func _pollen_box() -> Control:
	var box := PanelContainer.new()
	box.name = "FruitConvertPollen"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(CREAM_BOX, 18), 22.0, 14.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var figures := VBoxContainer.new()
	figures.add_theme_constant_override("separation", -4)
	figures.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	figures.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(figures)
	_made_label = ShopKit.text("", BIG, INK, ShopKit.heading_font())
	_made_label.name = "FruitConvertMade"
	figures.add_child(_made_label)
	figures.add_child(ShopKit.text(PlayerCopy.FRUIT_CONVERT_POLLEN, 16, SOFT_INK))
	# A few grains, as the board scatters them.
	var grains := Control.new()
	grains.custom_minimum_size = Vector2(82, 82)
	grains.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(grains)
	for grain: Array in [[Vector2(16, 0), 40.0], [Vector2(0, 46), 26.0], [Vector2(50, 34), 30.0]]:
		var mark := CurrencyMark.make(POLLEN, grain[1])
		mark.position = grain[0]
		mark.size = Vector2(grain[1], grain[1])
		grains.add_child(mark)
	return box

## A balance line: its words, then "[mark] 101 to 81"; returns the label that changes.
func _after(words: String, currency: String, now: int, node_name: String) -> Label:
	var row := HBoxContainer.new()
	row.name = node_name
	row.add_theme_constant_override("separation", 8)
	modal.content.add_child(row)
	var said := ShopKit.text(words, 19, CREAM)
	said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(said)
	row.add_child(ShopKit.amount(now, 20, CREAM, "", "", currency))
	row.add_child(ShopKit.text(PlayerCopy.FRUIT_CONVERT_TO, 19, MUTED))
	var after := ShopKit.text("", 20, CREAM, ShopKit.bold_font())
	after.name = node_name + "After"
	row.add_child(after)
	return after

## One step down (-1) or up (1), held inside one step and the most the balance covers.
func change(direction: int) -> void:
	count = clampi(count + direction * step, mini(step, most(fruits, step)), most(fruits, step))
	_show()

func _show() -> void:
	var made := count * rate
	_count_label.text = PollenMoney.grouped(count)
	_made_label.text = PollenMoney.grouped(made)
	_fruits_after.text = PollenMoney.grouped(fruits - count)
	_pollen_after.text = PollenMoney.grouped(pollen + made)
	less.disabled = count <= step
	more.disabled = count + step > most(fruits, step)
	confirm.text = PlayerCopy.FRUIT_CONVERT_BUTTON % PollenMoney.grouped(count)
	OfflineHold.set_enabled(confirm, count >= step)

func _confirm() -> void:
	if count < step or not _send.is_valid(): return
	_send.call(count)

## A step button's minus or plus: short rounded bars in the words' colour, drawn
## at any size (a picture's thin stroke fades on a small screen).
class Sign extends Control:
	var plus := false
	func _draw() -> void:
		var width := maxf(2.0, size.y * 0.12)
		draw_line(Vector2(size.x * 0.18, size.y * 0.5), Vector2(size.x * 0.82, size.y * 0.5), Orchard.TEXT, width, true)
		if plus: draw_line(Vector2(size.x * 0.5, size.y * 0.18), Vector2(size.x * 0.5, size.y * 0.82), Orchard.TEXT, width, true)

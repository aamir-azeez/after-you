extends Control
## The Fruits page (Fruits board 6a), beside the Pollen page and in its header
## pattern: the coral back square, the title and its line, and the money chip
## (kit/pollen_chip.gd); then two cards, each drawn by its own view:
## - Fruits for playing together (presentation/fruit_goals_view.gd), cream;
## - Your Fruits (presentation/fruit_wallet_view.gd), on the Orchard plum
##   (kit/orchard_surface.gd): the balance, the newest Fruit lines and the buttons.
## presentation/fruits_page_flow.gd reads the data and calls render(); this
## script only draws it. Each card's list scrolls on its own; the plum card's
## buttons stay under its list. No timers. The frame (shade, header, chip slot,
## scrolling cards) is the kit's (kit/page_frame.gd), shared with the Pollen page.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Frame = preload("res://presentation/kit/page_frame.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const Orchard = preload("res://presentation/kit/orchard_surface.gd")
const GoalsView = preload("res://presentation/fruit_goals_view.gd")
const WalletView = preload("res://presentation/fruit_wallet_view.gd")

signal back_pressed
signal retry_pressed
## The goals link: every goal, or the first few again.
signal goals_toggled
## A Your Fruits button (fruit_wallet_view.gd GET, ORCHARD, SUNSHINE or CONVERT) and the button itself.
signal button_pressed(which: String, button: Button)

var back_button: Button
var title_font: Font
var _chip_slot: HBoxContainer
var _goals: VBoxContainer
var _wallet_head: VBoxContainer
var _wallet_lines: VBoxContainer
var _buttons: GridContainer

func _init(heading_font: Font = null) -> void:
	title_font = heading_font
	name = "FruitsPage"
	var frame := Frame.build(self, {"back_name": "FruitsPageBack", "back_words": PlayerCopy.FRUITS_PAGE_BACK, "title": PlayerCopy.FRUITS_PAGE_TITLE,
		"title_name": "FruitsPageTitle", "subtitle": PlayerCopy.FRUITS_PAGE_SUBTITLE}, title_font, func() -> void: back_pressed.emit())
	back_button = frame.back
	_chip_slot = frame.chip_slot
	var goals := Frame.cream_card(frame.body, "FruitGoalsCard")
	goals.size_flags_stretch_ratio = 1.27
	_goals = Frame.scrolling(goals)
	var wallet := Orchard.card(22.0, false, Vector2(22, 18))
	wallet.name = "FruitWalletCard"
	wallet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.body.add_child(wallet)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	wallet.add_child(stack)
	_wallet_head = VBoxContainer.new()
	_wallet_head.add_theme_constant_override("separation", 4)
	stack.add_child(_wallet_head)
	_wallet_lines = Frame.scrolling(stack, 8)
	# Two to a row, as the board sets them.
	_buttons = GridContainer.new()
	_buttons.name = "FruitWalletButtons"
	_buttons.columns = 2
	_buttons.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_buttons.add_theme_constant_override("h_separation", 12)
	_buttons.add_theme_constant_override("v_separation", 12)
	stack.add_child(_buttons)

## Puts a new chip in the header (or none), leaving the cards as they are.
func show_chip(chip: Control) -> void:
	Frame.show_chip(_chip_slot, chip)

## Draws `model` from the flow: {chip (or null), status ("" once the Fruits
## are in), retry, achievements, all, balance, entries, buttons}.
func render(model: Dictionary) -> void:
	Frame.show_chip(_chip_slot, model.get("chip"))
	Frame.clear([_goals, _wallet_head, _wallet_lines, _buttons])
	var status := str(model.get("status", ""))
	if not status.is_empty():
		_goals.add_child(ShopKit.text(PlayerCopy.FRUIT_GOALS_TITLE, 26, ShopKit.INK, title_font if title_font != null else ShopKit.heading_font()))
		Frame.status(_goals, status, GoalsView.SOFT_INK, "FruitsPage", PlayerCopy.FRUITS_PAGE_RETRY, (func() -> void: retry_pressed.emit()) if bool(model.get("retry", false)) else Callable())
		return
	GoalsView.fill(_goals, model, title_font, func() -> void: goals_toggled.emit())
	WalletView.fill(_wallet_head, _wallet_lines, _buttons, model, title_font, func(which: String, button: Button) -> void: button_pressed.emit(which, button))

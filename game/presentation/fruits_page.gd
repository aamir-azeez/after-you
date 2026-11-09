extends Control
## The Fruits page (Fruits board 6a), beside the Pollen page and in its header
## pattern: the coral back square, the title and its line, and the money chip
## (kit/pollen_chip.gd); then two cards, each drawn by its own view:
## - Fruits for playing together (presentation/fruit_goals_view.gd), cream;
## - Your Fruits (presentation/fruit_wallet_view.gd), on the Orchard plum
##   (kit/orchard_surface.gd): the balance, the newest Fruit lines and the buttons.
## presentation/fruits_page_flow.gd reads the data and calls render(); this
## script only draws it. Each card's list scrolls on its own; the plum card's
## buttons stay under its list. No timers.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const PageMargin = preload("res://presentation/kit/page_margin.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const Orchard = preload("res://presentation/kit/orchard_surface.gd")
const GoalsView = preload("res://presentation/fruit_goals_view.gd")
const WalletView = preload("res://presentation/fruit_wallet_view.gd")
const BACK_ICON = preload("res://assets/ui/social/arrow-left.svg")

const CARD := Color("f3efdf")
## Room kept for a list's scroll bar while it shows.
const GUTTER := 12

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
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.10, 0.10, 0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeArea.bleed(shade)
	add_child(shade)
	var margin := PageMargin.new(22, 22)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	margin.add_child(outer)
	outer.add_child(_header())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	var goals := PanelContainer.new()
	goals.name = "FruitGoalsCard"
	goals.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goals.size_flags_stretch_ratio = 1.27
	goals.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(CARD, 18), 22.0, 18.0))
	body.add_child(goals)
	_goals = _scrolling(goals)
	var wallet := Orchard.card(22.0, false, Vector2(22, 18))
	wallet.name = "FruitWalletCard"
	wallet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(wallet)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	wallet.add_child(stack)
	_wallet_head = VBoxContainer.new()
	_wallet_head.add_theme_constant_override("separation", 4)
	stack.add_child(_wallet_head)
	_wallet_lines = _scrolling(stack)
	_wallet_lines.add_theme_constant_override("separation", 8)
	# Two to a row, as the board sets them.
	_buttons = GridContainer.new()
	_buttons.name = "FruitWalletButtons"
	_buttons.columns = 2
	_buttons.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_buttons.add_theme_constant_override("h_separation", 12)
	_buttons.add_theme_constant_override("v_separation", 12)
	stack.add_child(_buttons)

func _header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	back_button = Button.new()
	back_button.name = "FruitsPageBack"
	back_button.custom_minimum_size = Vector2(56, 56)
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_button.tooltip_text = PlayerCopy.FRUITS_PAGE_BACK
	back_button.accessibility_name = PlayerCopy.FRUITS_PAGE_BACK
	back_button.expand_icon = true
	ControlTheme.danger(back_button, BACK_ICON)
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	header.add_child(back_button)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	var title := ShopKit.text(PlayerCopy.FRUITS_PAGE_TITLE, 34, UiTokens.CREAM, title_font if title_font != null else ShopKit.body_font())
	title.name = "FruitsPageTitle"
	titles.add_child(title)
	titles.add_child(ShopKit.text(PlayerCopy.FRUITS_PAGE_SUBTITLE, 17, UiTokens.MUTED))
	_chip_slot = HBoxContainer.new()
	_chip_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_chip_slot)
	return header

## A scrolling column inside `parent` that fills its height, with room for the scroll bar while it shows.
func _scrolling(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(inset)
	var bar := scroll.get_v_scroll_bar()
	bar.visibility_changed.connect(func() -> void: inset.add_theme_constant_override("margin_right", GUTTER if bar.visible else 0))
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	inset.add_child(column)
	return column

## Draws `model` from the flow: {chip (or null), status ("" once the Fruits
## are in), retry, achievements, all, balance, entries, buttons}.
func render(model: Dictionary) -> void:
	var chip: Variant = model.get("chip")
	for child: Node in _chip_slot.get_children():
		if child == chip: continue
		_chip_slot.remove_child(child)
		child.queue_free()
	if chip is Control and (chip as Control).get_parent() != _chip_slot: _chip_slot.add_child(chip)
	for column: Container in [_goals, _wallet_head, _wallet_lines, _buttons]:
		for child: Node in column.get_children():
			column.remove_child(child)
			child.queue_free()
	var status := str(model.get("status", ""))
	if not status.is_empty():
		_goals.add_child(ShopKit.text(PlayerCopy.FRUIT_GOALS_TITLE, 26, ShopKit.INK, title_font if title_font != null else ShopKit.heading_font()))
		var line := ShopKit.text(status, 17, Color("4e6660"))
		line.name = "FruitsPageStatus"
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_goals.add_child(line)
		if bool(model.get("retry", false)):
			var retry := Button.new()
			retry.name = "FruitsPageRetry"
			retry.text = PlayerCopy.FRUITS_PAGE_RETRY
			retry.custom_minimum_size = Vector2(0, 50)
			retry.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			retry.pressed.connect(func() -> void: retry_pressed.emit())
			_goals.add_child(retry)
		return
	GoalsView.fill(_goals, model, title_font, func() -> void: goals_toggled.emit())
	WalletView.fill(_wallet_head, _wallet_lines, _buttons, model, title_font, func(which: String, button: Button) -> void: button_pressed.emit(which, button))

extends Control
## The store as Fruits boards 9 (its Pollen tab) and 3 (its Fruits tab) draw
## it, in the Friends page frame:
## - the header: the coral back square, the "Store" title, the Pollen | Fruits
##   tabs (only while Fruits show), and "You have" with the money chip
##   (kit/pollen_chip.gd, no plus: this is where the plus leads);
## - the first pack card, only while that currency's one-time gift is on and
##   unused: its title with the percent, the pair of the pack it pictures
##   (kit/bundle_art.gd first_pack) and that pack's amount with the gift
##   ("21,000 + 4,200"). On the Fruits tab it wears the Orchard plum
##   (kit/orchard_surface.gd);
## - the pack cards as a ladder, each a step taller, bottoms aligned: the art,
##   the name, the amount with its mark, the bonus line ("1,000 bonus · 5%
##   more"), the first pack amount while the gift is on, and the price button
##   with the store's own local price. The pack with the most for the money
##   carries the ribbon and its per $1 figure; on the Fruits tab it is the plum
##   card, framed, with a peach button. A Pollen bundle the store did not price
##   shows no button. Prices are never crossed out; nothing counts down.
## - the buttons under the ladder: on Pollen "Earn Pollen free by playing" and
##   Previous purchases; on Fruits "Fruits for playing together" and "Turn
##   Fruits into Pollen" (each only while its screen can open) and Previous
##   purchases; then the store's footnote.
## Buttons that need the server hold while offline (presentation/offline_hold.gd).
##
## A view only: presentation/pollen_store_flow.gd builds the model and answers
## the signals. The model: balance (int; -1 while unknown), balance_known,
## fruits (the chip's Fruit half, kit/pollen_chip.gd fruits_for), status, retry,
## tabs (bool), tab ("pollen" or "fruits"), first ({} or {currency, title,
## pair, caption, amount, gift}), bundles: Array of {id, currency, name,
## amount, bonus, percent, first, price, best, ribbon, per} in store order,
## together and convert (bool: those buttons show).
const PlayerCopy = preload("res://presentation/player_copy.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const PageMargin = preload("res://presentation/kit/page_margin.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const BundleArt = preload("res://presentation/kit/bundle_art.gd")
const CurrencyMark = preload("res://presentation/kit/currency_mark.gd")
const Orchard = preload("res://presentation/kit/orchard_surface.gd")
const PollenChip = preload("res://presentation/kit/pollen_chip.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const BACK_ICON = preload("res://assets/ui/social/arrow-left.svg")
const USERS_ICON = preload("res://assets/ui/social/users.svg")
const SWAP_ICON = preload("res://assets/ui/social/arrows-left-right.svg")

const CREAM := ShopKit.CREAM
const MUTED := ShopKit.MUTED
const INK := Color("193d39")
const NAME := Color("3f5d55")
const SOFT := Color("4a655d")
const BONUS_INK := Color("2c5e50")
const CARD := Color("f5eedb")
const FIRST_CARD := Color("f8f1df")
const PRICE := Color("234e47")
## The Pollen gold: the best bundle's edge, its ribbon and the first bundle amounts.
const GOLD_EDGE := Color("e9b04f")
const GOLD_SOFT_EDGE := Color("edd08a")
const GOLD_RIBBON := Color("f6dc98")
const GOLD_INK := Color("5a3f08")
const GOLD_NUMBER := Color("8a5a10")
## The tab bar, as the board draws it.
const TABS_FILL := Color("0e3033")
const TABS_EDGE := Color("1d4a48")
## Sizes, from the boards' 2340x1080 capture at the phone's 1.5 layout scale.
const CARD_RADIUS := 25
const FIRST_WIDTH := 313.0
const GAP := 17
## Each card's height as a share of the ladder's: the first pack card, then the packs from the smallest.
const FIRST_STEP := 0.963
const STEPS: Array[float] = [0.683, 0.78, 0.878, 1.0]
## Each pack card's width against the smallest's.
const WIDTHS: Array[float] = [1.0, 1.054, 1.108, 1.333]
## Narrower than this (a 16:9 phone lays the page out 1280 wide), the first
## pack card and the big numbers step down a size so every card keeps its amount.
const COMPACT_BELOW := 1450.0
const COMPACT_FIRST_WIDTH := 250.0

signal back_pressed
signal bundle_pressed(id: String)
signal earn_pressed
## The Pollen balance on the header's chip.
signal pollen_pressed
## The Fruit half of the header's chip.
signal fruits_pressed
signal purchases_pressed
signal retry_pressed
signal tab_pressed(tab: String)
signal together_pressed
signal convert_pressed

var back_button: Button
var chip: Control
var purchases_button: Button
var _chip_box: HBoxContainer
var _chip_shown := []
var _tabs: HBoxContainer
var _tab_buttons := {}
var _status: Label
var _retry: Button
var _cards: HBoxContainer
var _footer: HBoxContainer
var _buttons := {}
var _shown_key := ""
var _footer_key := ""
var _model: Dictionary = {}
var _compact := false

func _init() -> void:
	name = "PollenStorePage"
	theme = ShopKit.page_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.12, 0.12, 0.97)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeArea.bleed(shade)
	add_child(shade)
	var margin := PageMargin.new(28, 20)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	margin.add_child(outer)
	outer.add_child(_header())
	_status = ShopKit.text("", 18, CREAM)
	_status.name = "PollenStoreStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_status)
	_retry = Button.new()
	_retry.name = "PollenStoreRetry"
	_retry.text = PlayerCopy.WARDROBE_TRY_AGAIN
	_retry.custom_minimum_size = Vector2(0, 48)
	_retry.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_retry.pressed.connect(func() -> void: retry_pressed.emit())
	outer.add_child(_retry)
	_cards = HBoxContainer.new()
	_cards.name = "PollenStoreBundles"
	_cards.add_theme_constant_override("separation", GAP)
	_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_cards)
	_footer = HBoxContainer.new()
	_footer.name = "PollenStoreFooter"
	_footer.add_theme_constant_override("separation", 18)
	outer.add_child(_footer)

func _header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	back_button = Button.new()
	back_button.name = "PollenStoreBack"
	back_button.custom_minimum_size = Vector2(56, 56)
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_button.tooltip_text = PlayerCopy.WARDROBE_BACK
	back_button.accessibility_name = PlayerCopy.WARDROBE_BACK
	back_button.expand_icon = true
	ThemeRules.danger(back_button, BACK_ICON)
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	header.add_child(back_button)
	var title := ShopKit.text(PlayerCopy.POLLEN_STORE_TITLE, 41, CREAM, ShopKit.heading_font())
	title.name = "PollenStoreTitle"
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	_tabs = HBoxContainer.new()
	_tabs.name = "PollenStoreTabs"
	_tabs.add_theme_constant_override("separation", 3)
	var tab_frame := PanelContainer.new()
	tab_frame.name = "PollenStoreTabFrame"
	tab_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var frame_style := ThemeRules.rounded(TABS_FILL, 18, TABS_EDGE)
	frame_style.set_border_width_all(2)
	tab_frame.add_theme_stylebox_override("panel", ThemeRules.padded(frame_style, 4, 4))
	tab_frame.add_child(_tabs)
	header.add_child(tab_frame)
	for tab: String in [CurrencyMark.POLLEN, CurrencyMark.FRUITS]:
		var words := ShopKit.text(PlayerCopy.STORE_TAB_FRUITS if tab == CurrencyMark.FRUITS else PlayerCopy.STORE_TAB_POLLEN, 20, CREAM)
		words.name = "TabWords"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(CurrencyMark.beside(tab, 21))
		row.add_child(words)
		var button := ShopKit.content_button(row, 46.0)
		button.name = "PollenStoreTab_" + tab
		button.accessibility_name = words.text
		button.custom_minimum_size.x = row.get_combined_minimum_size().x + 38.0
		button.pressed.connect(func() -> void: tab_pressed.emit(tab))
		_tabs.add_child(button)
		_tab_buttons[tab] = button
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spring)
	_chip_box = HBoxContainer.new()
	_chip_box.name = "PollenStoreBalance"
	_chip_box.add_theme_constant_override("separation", 14)
	_chip_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var have := ShopKit.text(PlayerCopy.POLLEN_STORE_YOU_HAVE, 17, MUTED)
	have.name = "PollenStoreYouHave"
	have.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip_box.add_child(have)
	header.add_child(_chip_box)
	return header

## The tabs: the picked one on its own currency's surface (Pollen cream with a
## gold edge, Fruits the Orchard plum), the other plain.
func _style_tabs(picked: String) -> void:
	for tab: String in _tab_buttons:
		var button: Button = _tab_buttons[tab]
		var words: Label = button.find_child("TabWords", true, false)
		var on := tab == picked
		var fill: StyleBox
		if not on: fill = ThemeRules.rounded(Color.TRANSPARENT, 14)
		elif tab == CurrencyMark.FRUITS: fill = Orchard.flat(14)
		else:
			fill = ThemeRules.rounded(CARD, 14, Color("f0d29a"))
			(fill as StyleBoxFlat).set_border_width_all(2)
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			button.add_theme_stylebox_override(state, fill if on or state == "normal" else ThemeRules.rounded(Color(1, 1, 1, 0.06), 14))
		button.add_theme_stylebox_override("focus", ThemeRules.rounded(Color.TRANSPARENT, 14, UiTokens.MINT))
		words.add_theme_color_override("font_color", INK if on and tab == CurrencyMark.POLLEN else CREAM)
		words.add_theme_font_override("font", ShopKit.bold_font() if on else ShopKit.body_font())
		button.set_meta("picked", on)

func _notification(what: int) -> void:
	if what != NOTIFICATION_RESIZED or size.x <= 0.0: return
	var compact := size.x < COMPACT_BELOW
	if compact == _compact: return
	_compact = compact
	_shown_key = ""
	_footer_key = ""
	if not _model.is_empty(): render(_model)

## Redraws the page from the flow's model.
func render(model: Dictionary) -> void:
	_model = model
	var balance := int(model.get("balance", -1))
	var known := bool(model.get("balance_known", balance >= 0))
	var fruits: Array = model.get("fruits", [])
	_chip_box.visible = known
	if [balance, known, fruits] != _chip_shown:
		_chip_shown = [balance, known, fruits]
		if is_instance_valid(chip):
			_chip_box.remove_child(chip)
			chip.queue_free()
		# The store is where the plus leads, so its own chip has none.
		chip = PollenChip.make(balance, false, fruits)
		chip.amount_pressed.connect(func() -> void: pollen_pressed.emit())
		chip.fruits_pressed.connect(func() -> void: fruits_pressed.emit())
		_chip_box.add_child(chip)
	var tab := str(model.get("tab", CurrencyMark.POLLEN))
	(_tabs.get_parent() as Control).visible = bool(model.get("tabs", false))
	_style_tabs(tab)
	var status := str(model.get("status", ""))
	_status.text = status
	_status.visible = not status.is_empty()
	_retry.visible = bool(model.get("retry", false))
	# The cards and the footer are each made again only when what they show
	# changed, so a redraw (prices landing) never replaces a button under a finger.
	var first: Dictionary = model.get("first", {})
	var bundles: Array = model.get("bundles", [])
	var beside_first := not first.is_empty() and not bundles.is_empty()
	var key := var_to_str([tab, first, bundles, _compact])
	if key != _shown_key:
		_shown_key = key
		_clear(_cards)
		_buttons.clear()
		if beside_first: _cards.add_child(_step(_first_card(first), FIRST_STEP, 0.0))
		for index in range(bundles.size()):
			var at := index + maxi(0, STEPS.size() - bundles.size())
			_cards.add_child(_step(_card(bundles[index]), STEPS[mini(at, STEPS.size() - 1)], WIDTHS[mini(at, WIDTHS.size() - 1)]))
	var footer_key := var_to_str([tab, model.get("together", false), model.get("convert", false), beside_first, _compact])
	if footer_key != _footer_key:
		_footer_key = footer_key
		_clear(_footer)
		_fill_footer(tab, model, beside_first)

static func _clear(holder: Node) -> void:
	for child: Node in holder.get_children():
		holder.remove_child(child)
		child.queue_free()

## The price button of a pack, or null (tests, the flow's tap gate).
func button(id: String) -> Button:
	return _buttons.get(id)

## A card set on the ladder: a column as tall as the ladder whose spring above
## the card takes the rest, so the card is `step` of the ladder's height (or
## its own height, when that is more) and sits on the shared bottom. `width`
## is its share of the row against the smallest pack (0: a fixed width).
func _step(card: Control, step: float, width: float) -> Control:
	var column := VBoxContainer.new()
	column.name = str(card.name) + "Step"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	if width > 0.0:
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_stretch_ratio = width
	else: column.custom_minimum_size.x = _first_width()
	var spring := Control.new()
	spring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spring.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spring.size_flags_stretch_ratio = maxf(1.0 - step, 0.001)
	column.add_child(spring)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = step
	column.add_child(card)
	return column

## The first pack card: Pollen cream with a soft gold edge, Fruits the Orchard plum.
func _first_card(first: Dictionary) -> Control:
	var fruit := str(first.currency) == CurrencyMark.FRUITS
	var panel: PanelContainer
	if fruit: panel = Orchard.card(CARD_RADIUS, false, Vector2(24, 24))
	else:
		panel = PanelContainer.new()
		var style := ThemeRules.rounded(FIRST_CARD, CARD_RADIUS, GOLD_SOFT_EDGE)
		style.set_border_width_all(2)
		panel.add_theme_stylebox_override("panel", ThemeRules.padded(style, 24, 24))
	panel.name = "PollenStoreGift"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var title := ShopKit.text(str(first.title), 28 if _compact else 33, Orchard.TEXT if fruit else INK, ShopKit.heading_font())
	title.name = "PollenStoreGiftTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	var art := BundleArt.boxed(str(first.pair), Vector2(0, 90))
	art.size_flags_horizontal = Control.SIZE_FILL
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(art)
	var caption := ShopKit.text(str(first.caption), 17, Orchard.TEXT_SOFT if fruit else SOFT)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(caption)
	var sum := HBoxContainer.new()
	sum.name = "PollenStoreGiftSum"
	sum.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sum.add_theme_constant_override("separation", 10)
	var sum_size := 26 if _compact else 31
	sum.add_child(CurrencyMark.beside(str(first.currency), sum_size))
	sum.add_child(ShopKit.text(PlayerCopy.STORE_FIRST_SUM % [PollenMoney.grouped(int(first.amount)), PollenMoney.grouped(int(first.gift))], sum_size, Orchard.TEXT if fruit else INK, ShopKit.bold_font()))
	column.add_child(sum)
	return panel

## A pack's card.
func _card(entry: Dictionary) -> Control:
	var fruit := str(entry.currency) == CurrencyMark.FRUITS
	var best := bool(entry.get("best", false))
	var plum := fruit and best
	var panel: PanelContainer
	if plum: panel = Orchard.card(CARD_RADIUS, true, Vector2(16, 16))
	else:
		panel = PanelContainer.new()
		var style := ThemeRules.rounded(CARD, CARD_RADIUS, GOLD_EDGE if best else Color.TRANSPARENT)
		if best: style.set_border_width_all(2)
		panel.add_theme_stylebox_override("panel", ThemeRules.padded(style, 16, 16))
	panel.name = "PollenStoreBundle_" + str(entry.id)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	if best and not str(entry.get("ribbon", "")).is_empty(): column.add_child(_ribbon(str(entry.ribbon), fruit))
	var art := BundleArt.new(str(entry.id), 0.0)
	art.custom_minimum_size = Vector2(0, 64)
	art.size_flags_horizontal = Control.SIZE_FILL
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(art)
	var ink := Orchard.TEXT if plum else INK
	var title := _centred(str(entry.name), 19, Orchard.RIPE if plum else NAME, ShopKit.bold_font())
	title.name = "PollenStoreBundleName"
	column.add_child(title)
	var total := ShopKit.amount(int(entry.amount), _amount_size(best), ink, "", "", str(entry.currency))
	total.name = "PollenStoreBundleAmount"
	total.alignment = BoxContainer.ALIGNMENT_CENTER
	total.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(total)
	var first := int(entry.get("first", 0))
	var first_words := PlayerCopy.FRUIT_STORE_CARD_FIRST if fruit else PlayerCopy.POLLEN_STORE_CARD_FIRST
	if int(entry.bonus) > 0:
		var bonus := _centred(PlayerCopy.STORE_CARD_BONUS % [PollenMoney.grouped(int(entry.bonus)), int(entry.percent)] + str(entry.get("per", "")), 15, Orchard.RIPE if plum else BONUS_INK, ShopKit.bold_font())
		bonus.name = "PollenStoreBonus"
		column.add_child(bonus)
		if first > 0: column.add_child(_first_line(first_words, first, fruit, plum))
	elif first > 0:
		column.add_child(_first_line(PlayerCopy.FRUIT_STORE_CARD_NO_BONUS_FIRST if fruit else PlayerCopy.POLLEN_STORE_CARD_NO_BONUS_FIRST, first, fruit, plum))
	else:
		var none := _centred(PlayerCopy.POLLEN_STORE_NO_BONUS + str(entry.get("per", "")), 15, Orchard.TEXT_SOFT if plum else SOFT, ShopKit.body_font())
		none.name = "PollenStoreBonus"
		column.add_child(none)
	var price := str(entry.get("price", ""))
	if price.is_empty(): return panel
	var buy := Button.new()
	buy.name = "PollenStoreBuy_" + str(entry.id)
	buy.text = price
	buy.custom_minimum_size = Vector2(0, 55)
	buy.add_theme_font_size_override("font_size", 25)
	buy.add_theme_font_override("font", ShopKit.bold_font())
	if plum: Orchard.peach_button(buy, 15)
	else:
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			var fill := PRICE
			if state == "hover": fill = PRICE.lightened(0.1)
			if state in ["pressed", "hover_pressed"]: fill = PRICE.darkened(0.15)
			if state == "disabled": fill = Color("6f8580")
			buy.add_theme_stylebox_override(state, ThemeRules.rounded(fill, 15))
			buy.add_theme_color_override("font_color" if state == "normal" else "font_%s_color" % state, CREAM)
	buy.pressed.connect(func() -> void: bundle_pressed.emit(str(entry.id)))
	# Buying needs the server: the price greys while offline.
	OfflineHold.hold(buy)
	column.add_child(buy)
	_buttons[str(entry.id)] = buy
	return panel

func _first_width() -> float:
	return COMPACT_FIRST_WIDTH if _compact else FIRST_WIDTH

## A pack's amount: the best pack's a size up, both a size down on a narrow page.
func _amount_size(best: bool) -> int:
	if _compact: return 42 if best else 34
	return 51 if best else 40

## The ribbon on the pack with the most for the money: Pollen gold, Fruits ripe peach.
static func _ribbon(words: String, fruit: bool) -> Control:
	var holder := HBoxContainer.new()
	holder.name = "PollenStoreRibbon"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(Orchard.RIPE if fruit else GOLD_RIBBON, 13), 11, 3))
	pill.add_child(ShopKit.text(words, 15, Orchard.PEACH_INK if fruit else GOLD_INK, ShopKit.bold_font()))
	holder.add_child(pill)
	return holder

## "First pack 110" or "No bonus · first bundle 6,000": the words, then the amount in bold.
static func _first_line(words: String, amount: int, fruit: bool, plum: bool) -> Control:
	var row := HBoxContainer.new()
	row.name = "PollenStoreFirst"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 5)
	var parts := (words % PollenMoney.grouped(amount)).rsplit(" ", true, 1)
	row.add_child(ShopKit.text(parts[0], 15, Orchard.TEXT_SOFT if plum else SOFT))
	var number_ink := Orchard.TEXT if plum else (Orchard.ON_CREAM if fruit else GOLD_NUMBER)
	row.add_child(ShopKit.text(parts[1], 15, number_ink, ShopKit.bold_font()))
	return row

static func _centred(words: String, font_size: int, color: Color, font: Font) -> Label:
	var label := ShopKit.text(words, font_size, color, font)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

## The buttons under the ladder (starting under the packs while the first pack
## card shows) and the footnote.
func _fill_footer(tab: String, model: Dictionary, beside_first: bool) -> void:
	if beside_first:
		var under := Control.new()
		under.mouse_filter = Control.MOUSE_FILTER_IGNORE
		under.custom_minimum_size.x = _first_width()
		_footer.add_child(under)
	if tab == CurrencyMark.FRUITS:
		if bool(model.get("together", false)): _footer.add_child(_foot_button("PollenStoreTogether", PlayerCopy.FRUIT_STORE_TOGETHER, USERS_ICON, func() -> void: together_pressed.emit()))
		if bool(model.get("convert", false)):
			var convert := _foot_button("PollenStoreConvert", PlayerCopy.FRUIT_STORE_CONVERT, SWAP_ICON, func() -> void: convert_pressed.emit())
			OfflineHold.hold(convert)
			_footer.add_child(convert)
	else: _footer.add_child(_foot_button("PollenStoreEarn", PlayerCopy.POLLEN_STORE_EARN, USERS_ICON, func() -> void: earn_pressed.emit()))
	purchases_button = _foot_button("PollenStorePurchases", PlayerCopy.POLLEN_PURCHASES_TITLE, null, func() -> void: purchases_pressed.emit())
	# The receipts come from the server: Previous purchases holds offline.
	OfflineHold.hold(purchases_button)
	_footer.add_child(purchases_button)
	var foot := ShopKit.text(PlayerCopy.for_platform(PlayerCopy.POLLEN_STORE_FOOT, PlayerCopy.POLLEN_STORE_FOOT_IOS), 15, MUTED)
	foot.name = "PollenStoreFoot"
	foot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.add_child(foot)

static func _foot_button(node_name: String, words: String, icon: Texture2D, pressed: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = words
	if icon != null:
		button.icon = icon
		button.expand_icon = false
		button.add_theme_constant_override("icon_max_width", 22)
		button.add_theme_constant_override("h_separation", 10)
	button.custom_minimum_size = Vector2(0, 48)
	button.add_theme_font_size_override("font_size", 19)
	ThemeRules.secondary(button)
	button.pressed.connect(pressed)
	return button

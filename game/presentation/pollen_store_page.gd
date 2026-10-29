extends Control
## The Pollen store as Pollen board 2 draws it, in the Friends page frame:
## - the header: the coral back square, "Pollen" over its note, and the
##   "You have [grain] 9,000" chip;
## - the first bundle line, only while that one-time gift is on and unused;
## - four bundle cards (Pinch, Pouch, Jar, Basket): the art (kit/bundle_art.gd),
##   the name, the total with its grain, the bonus in plain Pollen and percent
##   ("20,000 + 1,000 bonus · 5% more") or "No bonus", Pollen per $1, and the
##   price button with the store's own local price. A bundle the store did not
##   price shows no button. Prices are never crossed out; nothing counts down.
## - "Earn Pollen free by playing" and the footnote.
##
## A view only: presentation/pollen_store_flow.gd builds the model and answers
## the signals. The model: balance (int; -1 while unknown), status, retry,
## gift_percent (0 hides the first bundle line), and bundles: Array of
## {id, name, pollen, base, bonus, percent, per, price}, in store order.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const BundleArt = preload("res://presentation/kit/bundle_art.gd")
const PollenChip = preload("res://presentation/kit/pollen_chip.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const BACK_ICON = preload("res://assets/ui/social/arrow-left.svg")
const GIFT_ICON = preload("res://assets/ui/whats_new/gift.svg")
const USERS_ICON = preload("res://assets/ui/social/users.svg")

const CREAM := ShopKit.CREAM
const MUTED := ShopKit.MUTED
const INK := ShopKit.INK
const INK_SOFT := ShopKit.INK_SOFT
const CARD := Color("f5eedb")
const BONUS := Color("dcefe2")
const PRICE := Color("234e47")

signal back_pressed
signal bundle_pressed(id: String)
signal earn_pressed
signal retry_pressed

var back_button: Button
var chip: Control
var _gift: PanelContainer
var _gift_label: RichTextLabel
var _cards: HBoxContainer
var _status: Label
var _retry: Button
var _buttons := {}

func _init() -> void:
	name = "PollenStorePage"
	theme = ShopKit.page_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.12, 0.12, 0.97)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeArea.bleed(shade)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 28)
	for side: String in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	margin.add_child(outer)
	outer.add_child(_header())
	_gift = _gift_line()
	outer.add_child(_gift)
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
	_cards.add_theme_constant_override("separation", 18)
	_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_cards)
	outer.add_child(_footer())

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
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	titles.add_child(ShopKit.text(PlayerCopy.POLLEN_STORE_TITLE, 40, CREAM, ShopKit.heading_font()))
	titles.add_child(ShopKit.text(PlayerCopy.POLLEN_STORE_NOTE, 16, MUTED))
	header.add_child(titles)
	chip = PollenChip.new(24, PlayerCopy.POLLEN_STORE_YOU_HAVE)
	chip.name = "PollenStoreBalance"
	header.add_child(chip)
	return header

func _gift_line() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "PollenStoreGift"
	panel.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(Color("173f39"), 14, Color("4f7d6f")), 18, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var icon := TextureRect.new()
	icon.texture = GIFT_ICON
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(22, 22)
	icon.modulate = Color("f1c48a")
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	_gift_label = RichTextLabel.new()
	_gift_label.bbcode_enabled = true
	_gift_label.fit_content = true
	_gift_label.scroll_active = false
	_gift_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_gift_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gift_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gift_label.add_theme_font_size_override("normal_font_size", 17)
	_gift_label.add_theme_font_size_override("bold_font_size", 17)
	_gift_label.add_theme_font_override("normal_font", ShopKit.body_font())
	_gift_label.add_theme_font_override("bold_font", ShopKit.bold_font())
	_gift_label.add_theme_color_override("default_color", CREAM)
	row.add_child(_gift_label)
	return panel

func _footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var earn := Button.new()
	earn.name = "PollenStoreEarn"
	earn.text = PlayerCopy.POLLEN_STORE_EARN
	earn.icon = USERS_ICON
	earn.expand_icon = false
	earn.add_theme_constant_override("icon_max_width", 20)
	earn.add_theme_constant_override("h_separation", 10)
	earn.custom_minimum_size = Vector2(0, 50)
	earn.add_theme_font_size_override("font_size", 17)
	ThemeRules.secondary(earn)
	earn.pressed.connect(func() -> void: earn_pressed.emit())
	row.add_child(earn)
	var foot := ShopKit.text(PlayerCopy.POLLEN_STORE_FOOT, 14, MUTED)
	foot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(foot)
	return row

## Redraws the page from the flow's model.
func render(model: Dictionary) -> void:
	var balance := int(model.get("balance", -1))
	chip.set_balance(balance, bool(model.get("balance_known", balance >= 0)))
	var percent := int(model.get("gift_percent", 0))
	_gift.visible = percent > 0
	if percent > 0: _gift_label.text = "[b]%s[/b]%s" % [PlayerCopy.POLLEN_STORE_FIRST % percent, PlayerCopy.POLLEN_STORE_FIRST_MORE]
	var status := str(model.get("status", ""))
	_status.text = status
	_status.visible = not status.is_empty()
	_retry.visible = bool(model.get("retry", false))
	for child: Node in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	_buttons.clear()
	for entry: Dictionary in model.get("bundles", []): _cards.add_child(_card(entry))

## The price button of a bundle, or null (tests, the flow's tap gate).
func button(id: String) -> Button:
	return _buttons.get(id)

func _card(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.name = "PollenStoreBundle_" + str(entry.id)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(CARD, 22), 16, 16))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(column)
	column.add_child(BundleArt.new(str(entry.id), 104.0))
	var title := ShopKit.text(str(entry.name), 19, INK_SOFT, ShopKit.bold_font())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var total := ShopKit.amount(int(entry.pollen), 34, INK)
	total.alignment = BoxContainer.ALIGNMENT_CENTER
	total.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(total)
	var bonus_holder := CenterContainer.new()
	bonus_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bonus_holder)
	if int(entry.bonus) > 0:
		var pill := PanelContainer.new()
		pill.name = "PollenStoreBonus"
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(BONUS, 10), 10, 3))
		pill.add_child(ShopKit.text(PlayerCopy.POLLEN_STORE_BONUS % [PollenMoney.grouped(int(entry.base)), PollenMoney.grouped(int(entry.bonus)), int(entry.percent)], 14, Color("2e5d4f"), ShopKit.bold_font()))
		bonus_holder.add_child(pill)
	else:
		bonus_holder.add_child(ShopKit.text(PlayerCopy.POLLEN_STORE_NO_BONUS, 14, INK_SOFT))
	var per := ShopKit.text(str(entry.get("per", "")), 14, INK_SOFT)
	per.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(per)
	var price := str(entry.get("price", ""))
	if price.is_empty(): return panel
	var buy := Button.new()
	buy.name = "PollenStoreBuy_" + str(entry.id)
	buy.text = price
	buy.custom_minimum_size = Vector2(0, 54)
	buy.add_theme_font_size_override("font_size", 22)
	buy.add_theme_font_override("font", ShopKit.bold_font())
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var fill := PRICE
		if state == "hover": fill = PRICE.lightened(0.1)
		if state in ["pressed", "hover_pressed"]: fill = PRICE.darkened(0.15)
		if state == "disabled": fill = Color("6f8580")
		buy.add_theme_stylebox_override(state, ThemeRules.rounded(fill, 14))
		buy.add_theme_color_override("font_color" if state == "normal" else "font_%s_color" % state, CREAM)
	buy.pressed.connect(func() -> void: bundle_pressed.emit(str(entry.id)))
	column.add_child(buy)
	_buttons[str(entry.id)] = buy
	return panel

extends RefCounted
## The Pollen store's two cards (Pollen board 2), on the shared in-game modal:
## - confirm(): "Buy a Pouch?" with plain sums: the bundle with its bonus, the
##   first bundle gift while it is on and unused, You get, You'll have (the
##   balance before and after) and You pay (the store's own price). Its Buy
##   hands over to Google Play's own sheet; the game never asks for card details.
## - receipt(): after the server credited the purchase: "23,100 Pollen added",
##   the bundle and the gift, the balance before and after, what was paid and
##   the Google Play order number, then Open the Wardrobe and Done.
const InGameModal = preload("res://presentation/in_game_modal.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const BundleArt = preload("res://presentation/kit/bundle_art.gd")
const Bundles = preload("res://services/pollen_bundles.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const CREAM := ShopKit.CREAM
const MUTED := ShopKit.MUTED
const ARROW := "  →  "

## The confirm card for `bundle` at the store's `price`; `gift` is the first
## bundle gift (0 when none); `known` false leaves out You'll have. `buy` runs
## on its Buy button. Returns the modal.
static func confirm(parent: Control, bundle: String, price: String, gift: int, balance: int, known: bool, buy: Callable, opener: Control = null) -> Control:
	var title := str(PlayerCopy.POLLEN_STORE_BUNDLES.get(bundle, bundle))
	var modal: Control = InGameModal.open(parent, "PollenStoreConfirm", PlayerCopy.POLLEN_STORE_CONFIRM_TITLE % title, PlayerCopy.POLLEN_STORE_CONFIRM_NOTE, opener)
	modal.widen(620.0)
	var table := _body(modal, bundle)
	var pollen := Bundles.pollen(bundle)
	_line(table, _bundle_words(bundle), ShopKit.amount(pollen, 17, CREAM))
	if gift > 0: _line(table, PlayerCopy.POLLEN_STORE_GIFT % _gift_percent(bundle, gift), ShopKit.amount(gift, 17, CREAM))
	_line(table, PlayerCopy.POLLEN_STORE_YOU_GET, ShopKit.amount(pollen + gift, 19, CREAM), true)
	if known: _line(table, PlayerCopy.POLLEN_STORE_YOULL_HAVE, _before_after(balance, balance + pollen + gift))
	_line(table, PlayerCopy.POLLEN_STORE_YOU_PAY, ShopKit.text(price, 18, CREAM, ShopKit.bold_font()), true)
	var button: Button = modal.add_actions(PlayerCopy.POLLEN_STORE_BUY % price, buy, PlayerCopy.DISPLAY_NAME_CANCEL)
	var cancel: Button = modal.find_child("ModalCancel", true, false)
	if cancel != null: ThemeRules.secondary(cancel)
	button.name = "PollenStoreConfirmBuy"
	return modal

## The receipt for one credited purchase (services/bundle_claims.gd checked_receipt).
## `balance_after`: the balance the server's answer gave. `paid`: the price as the
## store showed it, or "" when it is not known here (then only the order shows).
## `open_wardrobe` runs on Open the Wardrobe (an empty Callable leaves it out).
static func receipt(parent: Control, credited: Dictionary, balance_after: int, paid: String, open_wardrobe: Callable, opener: Control = null) -> Control:
	var bundle := str(credited.bundle)
	var added := int(credited.pollen) + int(credited.first_gift)
	var modal: Control = InGameModal.open(parent, "PollenStoreReceipt", PlayerCopy.POLLEN_STORE_ADDED % PollenMoney.grouped(added), PlayerCopy.POLLEN_STORE_THANKS, opener)
	modal.widen(620.0)
	var art := BundleArt.new(bundle, 76.0)
	modal.header.add_child(art)
	modal.header.move_child(art, 0)
	var table := GridContainer.new()
	table.name = "PollenStoreReceiptLines"
	table.columns = 2
	table.add_theme_constant_override("h_separation", 18)
	table.add_theme_constant_override("v_separation", 10)
	modal.content.add_child(table)
	_line(table, _bundle_words(bundle), ShopKit.amount(int(credited.pollen), 17, CREAM))
	if int(credited.first_gift) > 0: _line(table, PlayerCopy.POLLEN_STORE_GIFT % _gift_percent(bundle, int(credited.first_gift)), ShopKit.amount(int(credited.first_gift), 17, CREAM))
	_line(table, PlayerCopy.POLLEN_STORE_BALANCE, _before_after(balance_after - added, balance_after))
	var order := str(credited.get("order", ""))
	var paid_line := paid
	if not order.is_empty(): paid_line = PlayerCopy.POLLEN_STORE_ORDER % [paid, order] if not paid.is_empty() else PlayerCopy.POLLEN_STORE_ORDER_ONLY % order
	if not paid_line.is_empty(): _line(table, PlayerCopy.POLLEN_STORE_PAID, ShopKit.text(paid_line, 16, CREAM))
	var done: Button = modal.add_actions(PlayerCopy.POLLEN_STORE_DONE, func() -> void: modal.close(), PlayerCopy.POLLEN_STORE_OPEN_WARDROBE)
	done.name = "PollenStoreDone"
	var wardrobe: Button = modal.find_child("ModalCancel", true, false)
	if wardrobe != null:
		wardrobe.name = "PollenStoreOpenWardrobe"
		ThemeRules.secondary(wardrobe)
		if open_wardrobe.is_valid():
			wardrobe.pressed.connect(open_wardrobe)
		else: wardrobe.visible = false
	modal.refresh_focus_order()
	return modal

## "Pouch, with its 1,000 bonus", or the bundle's name alone when it has none.
static func _bundle_words(bundle: String) -> String:
	var title := str(PlayerCopy.POLLEN_STORE_BUNDLES.get(bundle, bundle))
	return PlayerCopy.POLLEN_STORE_LINE_BONUS % [title, PollenMoney.grouped(Bundles.bonus(bundle))] if Bundles.bonus(bundle) > 0 else title

static func _gift_percent(bundle: String, gift: int) -> int:
	return roundi(100.0 * gift / Bundles.pollen(bundle)) if Bundles.pollen(bundle) > 0 else 0

static func _body(modal: Control, bundle: String) -> GridContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	modal.content.add_child(row)
	row.add_child(BundleArt.new(bundle, 84.0))
	var table := GridContainer.new()
	table.name = "PollenStoreConfirmLines"
	table.columns = 2
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("h_separation", 18)
	table.add_theme_constant_override("v_separation", 9)
	row.add_child(table)
	return table

static func _line(table: GridContainer, words: String, value: Control, strong: bool = false) -> void:
	var name_label := ShopKit.text(words, 18 if strong else 17, CREAM if strong else Color("d9e4dc"), ShopKit.bold_font() if strong else null)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_child(name_label)
	value.size_flags_horizontal = Control.SIZE_SHRINK_END
	table.add_child(value)

## "9,000 → [grain] 32,100"
static func _before_after(before: int, after: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "PollenBeforeAfter"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	row.add_child(ShopKit.text(PollenMoney.grouped(before) + ARROW, 16, MUTED))
	row.add_child(ShopKit.amount(after, 17, CREAM))
	return row

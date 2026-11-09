extends RefCounted
## The Wardrobe's two cards (Pollen board 5b), on the shared in-game modal:
## - confirm(): before any Pollen leaves the balance: "Buy Toadstool cap?", the
##   item on a still pip, then You have, the item, and You'll have left, each with the grain. Buy names the cost.
## - short(): when the balance is short: what it costs and what the player has,
##   the Needed box ("Needed: [grain] 5,500 more"), and "Keep playing with
##   friends to earn more." While bundles sell (a `buyer`) it also names the
##   smallest bundle that covers the gap (services/pollen_bundles.gd cover:
##   "Get the Basket to buy this.", or the largest, "The Basket gets you
##   closest.") beside its art, what it gives under that ("[grain] 115,000
##   Pollen", the store's own sum with any first bundle gift), with a button
##   that shows that bundle's store price and buys it right there
##   (presentation/short_card_buy.gd), and a line under it for how a purchase ended. It never estimates how long earning takes.
## Both cards take a currency (Fruits board 4b): a Fruit purchase shows the
## Fruit on every row and a plum Buy, and short_of() is the one short card for
## Pollen and Fruits (an Orchard item, Sunshine, converting).
const ButtonTicks = preload("res://presentation/button_ticks.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const BundleArt = preload("res://presentation/kit/bundle_art.gd")
const ShortCardBuy = preload("res://presentation/short_card_buy.gd")
const Bundles = preload("res://services/pollen_bundles.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")
const Outfit = preload("res://services/outfit.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const CurrencyMark = preload("res://presentation/kit/currency_mark.gd")
const OrchardSurface = preload("res://presentation/kit/orchard_surface.gd")
const USERS_ICON = preload("res://assets/ui/social/users.svg")
const FRUITS := "fruits"
const MUTED := ShopKit.MUTED
const CREAM := ShopKit.CREAM
const BOX := Color("143a35")
const BOX_EDGE := Color("2f5f56")
## What the suggested bundle gives, under its line.
const GETS_SIZE := 15
## Tiers whose short card never suggests a bundle. Empty since the owner asked
## (2026-11-02) for every short card to name one; POLLEN-RULES had kept Epic
## and Special out ("epic", "special" here puts that back).
const NO_BUNDLE_TIERS := []

## The confirm card for item `id` (or a set, worn as `outfit`); `buy` runs on
## its Buy button. `currency` "fruits" shows the Fruit on each row and a plum
## "Buy for [Fruit] 50" (board 4b); Pollen keeps board 5b. Returns the modal.
## `art`, when given, stands where the pip would (Sunshine's sun) and no pip is made; `note` is the line under the title.
static func confirm(parent: Control, id: String, item_name: String, cost: int, balance: int, buy: Callable, opener: Control = null, currency: String = "", outfit: Dictionary = {}, art: Control = null, note: String = PlayerCopy.WARDROBE_CONFIRM_NOTE) -> Control:
	var modal: Control = InGameModal.open(parent, "WardrobeConfirm", PlayerCopy.WARDROBE_CONFIRM_TITLE % item_name, note, opener)
	modal.widen(600.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	modal.content.add_child(row)
	if art != null:
		art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(art)
	else:
		var pip := PipAvatar.new(true, SpiritLook.PEACH, Vector2(96, 118), true)
		pip.name = "WardrobeConfirmPip"
		pip.outfit = outfit if not outfit.is_empty() else Outfit.of(id)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pip)
	var table := GridContainer.new()
	table.name = "WardrobeConfirmLines"
	table.columns = 2
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("h_separation", 18)
	table.add_theme_constant_override("v_separation", 10)
	row.add_child(table)
	_line(table, PlayerCopy.WARDROBE_YOU_HAVE, ShopKit.amount(balance, 18, CREAM, "", "", currency))
	_line(table, item_name, ShopKit.amount(cost, 18, CREAM, PlayerCopy.WARDROBE_MINUS % "", "", currency))
	_line(table, PlayerCopy.WARDROBE_LEFT, ShopKit.amount(balance - cost, 18, CREAM, "", "", currency))
	var button: Button = modal.add_actions(PlayerCopy.WARDROBE_BUY % PollenMoney.grouped(cost), buy, PlayerCopy.DISPLAY_NAME_CANCEL)
	if currency == FRUITS:
		# Buy for [Fruit] 50 on plum, the words and the mark inside the one button.
		button.text = ""
		ShopKit.set_button_content(button, buy_words(cost, 20, OrchardSurface.TEXT, currency))
		button.accessibility_name = PlayerCopy.WARDROBE_BUY % PollenMoney.grouped(cost)
		OrchardSurface.plum_button(button)
	# A purchase sounds its own chord once the server confirms it.
	ButtonTicks.quiet(button)
	var cancel: Button = modal.find_child("ModalCancel", true, false)
	if cancel != null: ThemeRules.secondary(cancel)
	button.name = "WardrobeConfirmBuy"
	return modal

## "Buy for [mark] 50": the words, then the amount in its currency.
static func buy_words(cost: int, font_size: int, color: Color, currency: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "WardrobeBuyContent"
	row.add_theme_constant_override("separation", 10)
	row.add_child(ShopKit.text(PlayerCopy.WARDROBE_BUY_FOR, font_size, color, ShopKit.bold_font()))
	row.add_child(ShopKit.amount(cost, font_size, color, "", "", currency))
	return row


## A row: `words`, then the amount.
static func _line(table: GridContainer, words: String, amount: Control) -> void:
	var name_label := ShopKit.text(words, 18, CREAM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_child(name_label)
	amount.size_flags_horizontal = Control.SIZE_SHRINK_END
	table.add_child(amount)

## The short-of-Pollen card for an item of `tier`. `buyer` is the Pollen
## store's purchase engine (presentation/bundle_purchase.gd) while bundles
## sell, else null, which leaves the suggestion out; `credited` runs once a
## bundle bought here arrived. `offer` is the wardrobe view's `bundles` part,
## for the first bundle gift. `in_shop` false (a name change, pollen board 6)
## words the suggestion for the name. Returns the modal.
static func short(parent: Control, item_name: String, tier: String, cost: int, balance: int, buyer: Node = null, credited: Callable = Callable(), opener: Control = null, in_shop: bool = true, offer: Dictionary = {}) -> Control:
	return short_of(parent, {"item_name": item_name, "tier": tier, "cost": cost, "balance": balance, "buyer": buyer, "credited": credited, "opener": opener, "in_shop": in_shop, "offer": offer})

## The one short card, for Pollen and Fruits. `spec`:
## - cost, balance (whole numbers; a balance below 0 counts the real gap),
##   currency ("pollen" when left out, or "fruits"), opener (focus returns there),
##   offer (the first pack gift: a wardrobe view's `bundles` part for Pollen,
##   services/fruit_wallet.gd offer() for Fruits);
## - Pollen (board 5b): item_name, tier, buyer, credited and in_shop, as short() says;
## - Fruits (board 4b): "You need [Fruit] 20 more." and, only with `get_fruits`
##   (a Callable that opens the store on its Fruit packs; pass it only while
##   services/pollen_surfaces.gd fruit_packs_visible), the smallest pack that
##   covers the gap ("Get the Handful to buy this.", Bundles.cover with
##   "fruits") and a plum Get Fruits that closes the card and calls it. Without
##   it neither the pack nor the button shows. No item is needed, so Sunshine
##   and converting use it as an Orchard item does.
## Returns the modal ("WardrobeShort").
static func short_of(parent: Control, spec: Dictionary) -> Control:
	if str(spec.get("currency", "")) == FRUITS: return _short_fruits(parent, spec)
	var item_name := str(spec.get("item_name", ""))
	var tier := str(spec.get("tier", ""))
	var cost := int(spec.get("cost", 0))
	var balance := int(spec.get("balance", 0))
	var buyer: Node = spec.get("buyer") as Node
	var credited: Callable = spec.get("credited", Callable())
	var opener: Control = spec.get("opener") as Control
	var in_shop := bool(spec.get("in_shop", true))
	var offer: Dictionary = spec.get("offer", {})
	var modal: Control = InGameModal.open(parent, "WardrobeShort", PlayerCopy.WARDROBE_SHORT_TITLE,
		PlayerCopy.WARDROBE_SHORT_NOTE % [item_name, PollenMoney.grouped(cost), PollenMoney.grouped(balance)], opener)
	modal.widen(600.0)
	var need_box := _box(modal.content, "WardrobeShortNeed")
	var need := HBoxContainer.new()
	need.add_theme_constant_override("separation", 10)
	need_box.add_child(need)
	need.add_child(ShopKit.text(PlayerCopy.WARDROBE_SHORT_NEEDED, 16, MUTED))
	need.add_child(ShopKit.amount(cost - balance, 20, CREAM, "", PlayerCopy.WARDROBE_SHORT_MORE))
	var earn_box := _box(modal.content, "WardrobeShortEarn")
	var earn_column := VBoxContainer.new()
	earn_column.add_theme_constant_override("separation", 4)
	earn_box.add_child(earn_column)
	var earn := HBoxContainer.new()
	earn.add_theme_constant_override("separation", 10)
	earn_column.add_child(earn)
	var icon := TextureRect.new()
	icon.texture = USERS_ICON
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(20, 20)
	icon.modulate = MUTED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	earn.add_child(icon)
	earn.add_child(ShopKit.text(PlayerCopy.WARDROBE_SHORT_EARN, 17, CREAM, ShopKit.bold_font()))
	var bundle := Bundles.cover(cost - balance, offer)
	if is_instance_valid(buyer) and not tier in NO_BUNDLE_TIERS and not bundle.is_empty(): _suggest(modal, bundle, offer, cost - balance, buyer, credited, in_shop)
	modal.refresh_focus_order()
	return modal

## The Fruit short card (board 4b): the gap with the Fruit, then the pack and Get Fruits while packs sell.
static func _short_fruits(parent: Control, spec: Dictionary) -> Control:
	var gap := int(spec.get("cost", 0)) - int(spec.get("balance", 0))
	var get_fruits: Callable = spec.get("get_fruits", Callable())
	var modal: Control = InGameModal.open(parent, "WardrobeShort", PlayerCopy.ORCHARD_SHORT_TITLE, "", spec.get("opener") as Control)
	modal.widen(600.0)
	var box := _box(modal.content, "WardrobeShortNeed")
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	box.add_child(column)
	var line := HFlowContainer.new()
	line.name = "WardrobeShortLine"
	line.add_theme_constant_override("h_separation", 8)
	line.add_theme_constant_override("v_separation", 4)
	column.add_child(line)
	line.add_child(ShopKit.text(PlayerCopy.ORCHARD_SHORT_NEED, 18, CREAM))
	line.add_child(ShopKit.amount(gap, 18, CREAM, "", PlayerCopy.ORCHARD_SHORT_MORE, FRUITS))
	var pack := Bundles.cover(gap, spec.get("offer", {}), FRUITS) if get_fruits.is_valid() else ""
	if not pack.is_empty():
		var reach := Bundles.adds(pack, spec.get("offer", {}))
		var words := ShopKit.text((PlayerCopy.WARDROBE_SHORT_BUNDLE_CLOSEST if reach < gap else PlayerCopy.WARDROBE_SHORT_BUNDLE) % Bundles.display_name(pack), 18, CREAM)
		words.name = "WardrobeShortBundleLine"
		line.add_child(words)
		var row := HBoxContainer.new()
		column.add_child(row)
		var content := HBoxContainer.new()
		content.add_theme_constant_override("separation", 10)
		content.add_child(CurrencyMark.beside(FRUITS, 20))
		content.add_child(ShopKit.text(PlayerCopy.ORCHARD_GET_FRUITS, 20, OrchardSurface.TEXT, ShopKit.bold_font()))
		var button := ShopKit.content_button(content, 50)
		button.name = "WardrobeGetFruits"
		button.custom_minimum_size.x = maxf(button.custom_minimum_size.x, 190.0)
		button.accessibility_name = PlayerCopy.ORCHARD_GET_FRUITS
		OrchardSurface.plum_button(button)
		button.pressed.connect(func() -> void:
			modal.close(false)
			get_fruits.call())
		row.add_child(button)
	modal.refresh_focus_order()
	return modal

## The suggested bundle's box: its art, "Get the Basket to buy this." ("to
## change your name." for a name change, `item` false; "The Basket gets you
## closest." when even it does not cover the `gap`), under it what the bundle
## gives (Bundles.adds with `offer`, as the store's confirm card sums it), its
## price button, and the line under the box for how a purchase ended.
static func _suggest(modal: Control, bundle: String, offer: Dictionary, gap: int, buyer: Node, credited: Callable, item: bool = true) -> void:
	var box := _box(modal.content, "WardrobeShortBundle")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var art := BundleArt.new(bundle, 52.0)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(art)
	var title := str(PlayerCopy.POLLEN_STORE_BUNDLES.get(bundle, bundle))
	var gets := Bundles.adds(bundle, offer)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(words)
	var line := ShopKit.text((PlayerCopy.WARDROBE_SHORT_BUNDLE_CLOSEST if gets < gap else PlayerCopy.WARDROBE_SHORT_BUNDLE if item else PlayerCopy.WARDROBE_SHORT_BUNDLE_NAME) % title, 17, CREAM, ShopKit.bold_font())
	line.name = "WardrobeShortBundleLine"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(line)
	words.add_child(_gets_line(gets, Bundles.gift(bundle, Bundles.gift_percent(offer)) > 0))
	var status := ShopKit.text("", 15, CREAM)
	status.name = "WardrobeShortStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.visible = false
	row.add_child(ShortCardBuy.make(modal, box, bundle, buyer, status, credited))
	modal.content.add_child(status)

## "[grain] 115,000 Pollen": what the suggested bundle gives. With the first
## bundle gift counted (`gift`) it says so while that fits on the one line,
## else the total alone; these words never widen the card.
static func _gets_line(gets: int, gift: bool) -> HBoxContainer:
	var row := ShopKit.amount(gets, GETS_SIZE, MUTED, "", PlayerCopy.WARDROBE_SHORT_BUNDLE_GETS)
	row.name = "WardrobeShortBundleGets"
	if not gift: return row
	var value: Label = row.find_child("PollenAmountValue", false, false)
	value.clip_text = true
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var long := PollenMoney.grouped(gets) + PlayerCopy.WARDROBE_SHORT_BUNDLE_GETS_GIFT
	var plain := value.text
	value.resized.connect(func() -> void:
		var fits := value.get_theme_font("font").get_string_size(long, HORIZONTAL_ALIGNMENT_LEFT, -1, GETS_SIZE).x <= value.size.x
		var wanted := long if fits else plain
		if value.text != wanted: value.text = wanted)
	return row

static func _box(parent: Control, node_name: String) -> PanelContainer:
	var box := PanelContainer.new()
	box.name = node_name
	box.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(BOX, 14, BOX_EDGE), 16, 12))
	parent.add_child(box)
	return box

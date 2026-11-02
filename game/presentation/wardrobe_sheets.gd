extends RefCounted
## The Wardrobe's two cards (Pollen board 5b), on the shared in-game modal:
## - confirm(): before any Pollen leaves the balance: "Buy Toadstool cap?", the
##   item on a still pip, then You have, the item, and You'll have left, each with the grain. Buy names the cost.
## - short(): when the balance is short: what it costs and what the player has,
##   the Needed box ("Needed: [grain] 5,500 more", "It stays in the shop."),
##   and "Keep playing with friends to earn more." While bundles sell
##   (`get_pollen` valid) it also names the smallest bundle that covers the gap
##   (services/pollen_bundles.gd cover: "Get the Basket to buy this.", or the
##   largest, "The Basket gets you closest.") beside its art, with a Get Pollen
##   button that opens the Pollen store with that bundle highlighted. It never
##   estimates how long earning takes.
const ButtonTicks = preload("res://presentation/button_ticks.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const BundleArt = preload("res://presentation/kit/bundle_art.gd")
const Bundles = preload("res://services/pollen_bundles.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")
const Outfit = preload("res://services/outfit.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const USERS_ICON = preload("res://assets/ui/social/users.svg")
const MUTED := ShopKit.MUTED
const CREAM := ShopKit.CREAM
const BOX := Color("143a35")
const BOX_EDGE := Color("2f5f56")
## Tiers whose short card never suggests a bundle. Empty since the owner asked
## (2026-11-02) for every short card to name one; POLLEN-RULES had kept Epic
## and Special out ("epic", "special" here puts that back).
const NO_BUNDLE_TIERS := []

## The confirm card for item `id`; `buy` runs on its Buy button. Returns the modal.
static func confirm(parent: Control, id: String, item_name: String, cost: int, balance: int, buy: Callable, opener: Control = null) -> Control:
	var modal: Control = InGameModal.open(parent, "WardrobeConfirm", PlayerCopy.WARDROBE_CONFIRM_TITLE % item_name, PlayerCopy.WARDROBE_CONFIRM_NOTE, opener)
	modal.widen(600.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	modal.content.add_child(row)
	var pip := PipAvatar.new(true, SpiritLook.PEACH, Vector2(96, 118), true)
	pip.name = "WardrobeConfirmPip"
	pip.outfit = Outfit.of(id)
	pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pip)
	var table := GridContainer.new()
	table.name = "WardrobeConfirmLines"
	table.columns = 2
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("h_separation", 18)
	table.add_theme_constant_override("v_separation", 10)
	row.add_child(table)
	_line(table, PlayerCopy.WARDROBE_YOU_HAVE, ShopKit.amount(balance, 18, CREAM))
	_line(table, item_name, ShopKit.amount(cost, 18, CREAM, PlayerCopy.WARDROBE_MINUS % ""))
	_line(table, PlayerCopy.WARDROBE_LEFT, ShopKit.amount(balance - cost, 18, CREAM))
	var button: Button = modal.add_actions(PlayerCopy.WARDROBE_BUY % PollenMoney.grouped(cost), buy, PlayerCopy.DISPLAY_NAME_CANCEL)
	# A purchase sounds its own chord once the server confirms it.
	ButtonTicks.quiet(button)
	var cancel: Button = modal.find_child("ModalCancel", true, false)
	if cancel != null: ThemeRules.secondary(cancel)
	button.name = "WardrobeConfirmBuy"
	return modal

## A row: `words`, then the amount.
static func _line(table: GridContainer, words: String, amount: Control) -> void:
	var name_label := ShopKit.text(words, 18, CREAM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_child(name_label)
	amount.size_flags_horizontal = Control.SIZE_SHRINK_END
	table.add_child(amount)

## The short-of-Pollen card for an item of `tier`. `get_pollen` (bundle: String)
## opens the Pollen store with the suggested bundle highlighted; an empty
## Callable (bundles not on sale) leaves the suggestion out. `offer` is the
## wardrobe view's `bundles` part, for the first bundle gift. `in_shop` false (a
## name change, pollen board 6) leaves out "It stays in the shop.". Returns the modal.
static func short(parent: Control, item_name: String, tier: String, cost: int, balance: int, get_pollen: Callable = Callable(), opener: Control = null, in_shop: bool = true, offer: Dictionary = {}) -> Control:
	var modal: Control = InGameModal.open(parent, "WardrobeShort", PlayerCopy.WARDROBE_SHORT_TITLE,
		PlayerCopy.WARDROBE_SHORT_NOTE % [item_name, PollenMoney.grouped(cost), PollenMoney.grouped(balance)], opener)
	modal.widen(600.0)
	var need_box := _box(modal.content, "WardrobeShortNeed")
	var need := HBoxContainer.new()
	need.add_theme_constant_override("separation", 10)
	need_box.add_child(need)
	need.add_child(ShopKit.text(PlayerCopy.WARDROBE_SHORT_NEEDED, 16, MUTED))
	need.add_child(ShopKit.amount(cost - balance, 20, CREAM, "", PlayerCopy.WARDROBE_SHORT_MORE))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	need.add_child(gap)
	if in_shop:
		var stays := ShopKit.text(PlayerCopy.WARDROBE_SHORT_STAYS, 13, MUTED)
		stays.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		need.add_child(stays)
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
	if get_pollen.is_valid() and not tier in NO_BUNDLE_TIERS and not bundle.is_empty(): _suggest(modal, bundle, Bundles.adds(bundle, offer) >= cost - balance, get_pollen, in_shop)
	modal.refresh_focus_order()
	return modal

## The suggested bundle's box: its art, "Get the Basket to buy this." ("to
## change your name." for a name change, `item` false; "The Basket gets you
## closest." when even it does not `covers` the gap), and Get Pollen.
static func _suggest(modal: Control, bundle: String, covers: bool, get_pollen: Callable, item: bool = true) -> void:
	var box := _box(modal.content, "WardrobeShortBundle")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var art := BundleArt.new(bundle, 52.0)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(art)
	var title := str(PlayerCopy.POLLEN_STORE_BUNDLES.get(bundle, bundle))
	var line := ShopKit.text((PlayerCopy.WARDROBE_SHORT_BUNDLE_CLOSEST if not covers else PlayerCopy.WARDROBE_SHORT_BUNDLE if item else PlayerCopy.WARDROBE_SHORT_BUNDLE_NAME) % title, 17, CREAM, ShopKit.bold_font())
	line.name = "WardrobeShortBundleLine"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)
	var button := Button.new()
	button.name = "WardrobeGetPollen"
	button.text = PlayerCopy.WARDROBE_GET_POLLEN
	button.custom_minimum_size = Vector2(0, 50)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(func() -> void:
		modal.close(false)
		get_pollen.call(bundle))
	row.add_child(button)

static func _box(parent: Control, node_name: String) -> PanelContainer:
	var box := PanelContainer.new()
	box.name = node_name
	box.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(BOX, 14, BOX_EDGE), 16, 12))
	parent.add_child(box)
	return box

extends RefCounted
## The Wardrobe's two cards (Pollen board 5b), on the shared in-game modal:
## - confirm(): before any Pollen leaves the balance: "Buy Toadstool cap?", the
##   item on a still pip, then You have, the item with its "about $X", and
##   You'll have left, each with the grain. Buy names the cost.
## - short(): when the balance is short: what it costs and what the player has,
##   the Needed box ("Needed: [grain] 5,500 more", "It stays in the shop."),
##   and "Keep playing with friends to earn more." A plain "Get Pollen" link
##   joins it only while bundles sell (`get_pollen` valid), and never for an
##   Epic or a Special: no bundle is ever suggested for those. It never names a
##   bundle and never estimates how long earning takes.
const InGameModal = preload("res://presentation/in_game_modal.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")
const Outfit = preload("res://services/outfit.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const USERS_ICON = preload("res://assets/ui/social/users.svg")
const MUTED := ShopKit.MUTED
const CREAM := ShopKit.CREAM
const BOX := Color("143a35")
const BOX_EDGE := Color("2f5f56")
## Tiers whose short card never links to the Pollen store.
const NO_BUNDLE_TIERS := ["epic", "special"]

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
	_line(table, PlayerCopy.WARDROBE_COST_LINE % [item_name, PollenMoney.about(cost)], ShopKit.amount(cost, 18, CREAM, PlayerCopy.WARDROBE_MINUS % ""))
	_line(table, PlayerCopy.WARDROBE_LEFT, ShopKit.amount(balance - cost, 18, CREAM))
	var button: Button = modal.add_actions(PlayerCopy.WARDROBE_BUY % PollenMoney.grouped(cost), buy, PlayerCopy.DISPLAY_NAME_CANCEL)
	var cancel: Button = modal.find_child("ModalCancel", true, false)
	if cancel != null: ThemeRules.secondary(cancel)
	button.name = "WardrobeConfirmBuy"
	return modal

static func _line(table: GridContainer, words: String, amount: Control) -> void:
	var name_label := ShopKit.text(words, 18, CREAM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_child(name_label)
	amount.size_flags_horizontal = Control.SIZE_SHRINK_END
	table.add_child(amount)

## The short-of-Pollen card for an item of `tier`. `get_pollen` opens the Pollen
## store; an empty Callable (bundles not on sale) leaves the link out. Returns the modal.
static func short(parent: Control, item_name: String, tier: String, cost: int, balance: int, get_pollen: Callable = Callable(), opener: Control = null) -> Control:
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
	if get_pollen.is_valid() and not tier in NO_BUNDLE_TIERS:
		var link := LinkButton.new()
		link.name = "WardrobeGetPollen"
		link.text = PlayerCopy.WARDROBE_GET_POLLEN
		link.underline = LinkButton.UNDERLINE_MODE_ALWAYS
		link.custom_minimum_size = Vector2(0, 44)
		link.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		link.add_theme_font_size_override("font_size", 16)
		link.add_theme_color_override("font_color", Color("cfe7dc"))
		link.add_theme_color_override("font_hover_color", CREAM)
		link.pressed.connect(func() -> void:
			modal.close(false)
			get_pollen.call())
		earn_column.add_child(link)
	modal.refresh_focus_order()
	return modal

static func _box(parent: Control, node_name: String) -> PanelContainer:
	var box := PanelContainer.new()
	box.name = node_name
	box.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(BOX, 14, BOX_EDGE), 16, 12))
	parent.add_child(box)
	return box

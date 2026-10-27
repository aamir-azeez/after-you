extends RefCounted
## The Wardrobe's two cards (board 5b), on the shared in-game modal:
## - confirm(): before any Pollen leaves the balance: what the player has, the
##   item with its "about $X", and what they'll have left. Buy names the cost.
## - short(): when the balance is short: the gap, and "Keep playing with
##   friends to earn more". It never suggests a bundle and never estimates how
##   long earning takes. A "Get Pollen" link joins it once bundles sell
##   (Phase 6), and even then never for an Epic or a Special.
const InGameModal = preload("res://presentation/in_game_modal.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const MUTED := Color("afc6be")

## The confirm card; `buy` runs on its Buy button. Returns the modal.
static func confirm(parent: Control, item_name: String, cost: int, balance: int, buy: Callable, opener: Control = null) -> Control:
	var modal: Control = InGameModal.open(parent, "WardrobeConfirm", PlayerCopy.WARDROBE_CONFIRM_TITLE % item_name, PlayerCopy.WARDROBE_CONFIRM_NOTE, opener)
	modal.widen(560.0)
	var table := GridContainer.new()
	table.name = "WardrobeConfirmLines"
	table.columns = 2
	table.add_theme_constant_override("h_separation", 24)
	table.add_theme_constant_override("v_separation", 8)
	modal.content.add_child(table)
	for line: Array in [[PlayerCopy.WARDROBE_YOU_HAVE, PollenMoney.grouped(balance)],
			[PlayerCopy.WARDROBE_COST_LINE % [item_name, PollenMoney.about(cost)], PlayerCopy.WARDROBE_MINUS % PollenMoney.grouped(cost)],
			[PlayerCopy.WARDROBE_LEFT, PollenMoney.grouped(balance - cost)]]:
		var name_label := modal.label(line[0], 19, table) as Label
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var amount := modal.label(line[1], 19, table) as Label
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var button: Button = modal.add_actions(PlayerCopy.WARDROBE_BUY % PollenMoney.grouped(cost), buy, PlayerCopy.DISPLAY_NAME_CANCEL)
	var cancel: Button = modal.find_child("ModalCancel", true, false)
	if cancel != null: ThemeRules.secondary(cancel)
	button.name = "WardrobeConfirmBuy"
	return modal

## The short-of-Pollen card. Returns the modal.
static func short(parent: Control, item_name: String, cost: int, balance: int, opener: Control = null) -> Control:
	var modal: Control = InGameModal.open(parent, "WardrobeShort", PlayerCopy.WARDROBE_SHORT_TITLE,
		PlayerCopy.WARDROBE_SHORT_NOTE % [item_name, PollenMoney.grouped(cost), PollenMoney.grouped(maxi(balance, 0))], opener)
	modal.widen(560.0)
	var need := modal.label(PlayerCopy.WARDROBE_SHORT_NEED % PollenMoney.grouped(cost - maxi(balance, 0)), 22) as Label
	need.name = "WardrobeShortNeed"
	var earn := modal.label(PlayerCopy.WARDROBE_SHORT_EARN, 19) as Label
	earn.add_theme_color_override("font_color", MUTED)
	# One way out: the shared footer's Cancel stays hidden, its primary closes.
	modal.add_actions(PlayerCopy.WARDROBE_CLOSE, func() -> void: modal.close())
	var cancel: Button = modal.find_child("ModalCancel", true, false)
	if cancel != null: cancel.visible = false
	return modal

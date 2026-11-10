extends RefCounted
## The out-of-energy card (board-10-energy-out), over a duel page through its
## own sheet, so Back closes it before the page: "Out of energy", the meter
## (presentation/duels/energy_meter.gd card: the empty sprouts and "Your next
## energy comes in 6 min."), a plain Wait that always shows, and beside it the
## peach "Refill for [Fruit] 20" only when the caller offers a refill (Fruits
## show and the meter is below its max: presentation/duels/duel_energy_flow.gd
## decides, so this card reads no Fruits). Wait only closes the card: waiting
## is free. Its Refill closes the card and calls `refill`; it needs the server,
## so it greys offline.
##
## Dropped from the board (owner, 2026-11-09: show, don't tell): "Or fill all
## 5 now with Fruits." The meter, the minutes line and the button carry it.
const EnergyMeter = preload("res://presentation/duels/energy_meter.gd")
const Sheets = preload("res://presentation/wardrobe_sheets.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const OrchardSurface = preload("res://presentation/kit/orchard_surface.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

const NAME := "EnergyOut"
const WIDTH := 660.0
const TITLE_SIZE := 36
const BUTTON_HEIGHT := 64.0
## The room the board leaves above the meter and under its line.
const ABOVE_METER := 28.0
const UNDER_LINE := 30.0
const FRUITS := "fruits"

## Opens the card over `page` (presentation/duels/duel_page_base.gd) for the
## player of `scope`, closing any card already up there. `refill_price` > 0
## offers the refill at that many Fruits; `refill(opener)` runs from its button.
## `say(text)` is where an offline tap says why. Returns the modal, or null while the page is closing.
static func open(page: CanvasLayer, store: RefCounted, scope: Dictionary, refill_price: int, refill: Callable, opener: Control = null, say: Callable = Callable()) -> Control:
	page.close_sheet()
	var modal: Control = page.sheet(NAME, PlayerCopy.ENERGY_OUT_TITLE, "", opener)
	if modal == null: return null
	modal.widen(WIDTH)
	modal.title_label.add_theme_font_size_override("font_size", TITLE_SIZE)
	modal.content.add_child(_gap(ABOVE_METER))
	modal.content.add_child(EnergyMeter.card(store, scope))
	modal.content.add_child(_gap(UNDER_LINE))
	var offered := refill_price > 0 and refill.is_valid()
	var button: Button = modal.add_actions(PlayerCopy.ENERGY_REFILL_FOR, func() -> void:
		if not offered: return
		modal.close(false)
		refill.call(opener), PlayerCopy.ENERGY_WAIT)
	var wait: Button = modal.find_child("ModalCancel", true, false)
	if wait != null:
		wait.name = "EnergyWait"
		ThemeRules.secondary(wait)
		wait.custom_minimum_size.y = BUTTON_HEIGHT
		wait.add_theme_font_override("font", ShopKit.bold_font())
		wait.add_theme_font_size_override("font_size", 22)
	if not offered:
		button.get_parent().remove_child(button)
		button.queue_free()
		modal.refresh_focus_order()
		return modal
	button.name = "EnergyRefill"
	button.text = ""
	button.custom_minimum_size.y = BUTTON_HEIGHT
	button.accessibility_name = "%s %s" % [PlayerCopy.ENERGY_REFILL_FOR, PollenMoney.grouped(refill_price)]
	ShopKit.set_button_content(button, Sheets.buy_words(refill_price, 22, OrchardSurface.PEACH_INK, FRUITS, PlayerCopy.ENERGY_REFILL_FOR))
	OrchardSurface.peach_button(button)
	OfflineHold.hold(button, say)
	return modal

static func _gap(tall: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = tall
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap

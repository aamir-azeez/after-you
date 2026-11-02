extends RefCounted
## The receipts list behind the Pollen store's Previous purchases (pollen board
## 2's store, presentation/pollen_store_flow.gd show_purchases): each bundle bought
## or refunded, newest first, with its art, its Pollen, its date and the receipt
## line the store's receipt shows ("$3.99 · Google Play order GPA.1234-...").
## Money is the server's US figure (services/pollen_history.gd), so it shows
## only for a player whose store sells in US dollars (`money`); anyone else sees
## receipt lines with the order alone. No total shows anywhere.
## open() makes the sheet (the shared in-game modal with the list on a light
## card that scrolls); render() draws the data into it. Pure drawing: it keeps
## nothing; presentation/pollen_store_flow.gd reads the history and calls render().
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const BundleArt = preload("res://presentation/kit/bundle_art.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const WhenLabel = preload("res://presentation/when_label.gd")
const StoreSheets = preload("res://presentation/pollen_store_sheets.gd")

const INK := Color("1d3230")
const SOFT_INK := Color("4e6660")
## The light card the list sits on, as on the Pollen page's cards, and the list's height.
const CARD := Color("f3efdf")
const LIST_HEIGHT := 330.0
const REFUND_INK := Color("8a4b42")
const ROW_SIZE := 17
const ART := 46.0
const GUTTER := 10.0

## The Previous purchases sheet over `parent`, its list empty until render().
static func open(parent: Control, opener: Control = null) -> Control:
	var modal: Control = InGameModal.open(parent, "PollenPurchases", PlayerCopy.POLLEN_PURCHASES_TITLE, PlayerCopy.for_platform(PlayerCopy.POLLEN_PURCHASES_NOTE, PlayerCopy.POLLEN_PURCHASES_NOTE_IOS), opener)
	modal.widen(680.0)
	var card := PanelContainer.new()
	card.name = "PollenPurchasesCard"
	card.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(CARD, 18), 20.0, 16.0))
	modal.content.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = LIST_HEIGHT
	card.add_child(scroll)
	var column := VBoxContainer.new()
	column.name = "PollenPurchasesList"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	return modal

## Draws `model` (as fill() takes it) into a sheet open() made, over what it showed.
static func render(modal: Control, model: Dictionary) -> void:
	var column: VBoxContainer = modal.find_child("PollenPurchasesList", true, false) if is_instance_valid(modal) else null
	if column == null: return
	for child: Node in column.get_children():
		column.remove_child(child)
		child.queue_free()
	fill(column, model)

## Fills `column` (already empty) from {lines (services/pollen_history.gd
## purchases), money (false: no money anywhere on the list), status (shown
## instead of the rows while the history is loading or could not be read) and
## retry (a Callable: a Try again button under the status)}.
static func fill(column: VBoxContainer, model: Dictionary) -> void:
	var status := str(model.get("status", ""))
	if not status.is_empty():
		var waiting := _wrapped(status, ROW_SIZE, SOFT_INK)
		waiting.name = "PollenPurchasesStatus"
		column.add_child(waiting)
		var retry: Variant = model.get("retry")
		if retry is Callable and (retry as Callable).is_valid():
			var again := Button.new()
			again.name = "PollenPurchasesRetry"
			again.text = PlayerCopy.POLLEN_PLAY_RETRY
			again.custom_minimum_size = Vector2(0, 50)
			again.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			again.pressed.connect(retry)
			column.add_child(again)
		return
	var lines: Array = model.get("lines", [])
	if lines.is_empty():
		var none := _wrapped(PlayerCopy.POLLEN_PURCHASES_NONE, ROW_SIZE, SOFT_INK)
		none.name = "PollenPurchasesNone"
		column.add_child(none)
		return
	var money := bool(model.get("money", false))
	for index in range(lines.size()):
		if index > 0: column.add_child(_rule())
		column.add_child(_row(lines[index], index, money))

## One bundle or refund: its art, then the name with its Pollen on the right,
## the date, and the receipt line across the row's full width (an order number
## is one long word).
static func _row(line: Dictionary, index: int, money: bool) -> Control:
	var refund := str(line.kind) == "bundlerefund"
	var row := HBoxContainer.new()
	row.name = "PollenPurchaseRow%d" % index
	row.add_theme_constant_override("separation", 12)
	var art: Control = BundleArt.faded(str(line.bundle), ART, 0.55) if refund else BundleArt.new(str(line.bundle), ART)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(art)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	row.add_child(words)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	words.add_child(top)
	var bundle_name := str(PlayerCopy.POLLEN_STORE_BUNDLES.get(str(line.bundle), str(line.bundle)))
	top.add_child(_wrapped(PlayerCopy.POLLEN_PURCHASE_REFUNDED % bundle_name if refund else bundle_name, ROW_SIZE, INK))
	var pollen := ShopKit.amount(absi(int(line.amount)), ROW_SIZE, REFUND_INK if refund else INK, PlayerCopy.WARDROBE_MINUS % "" if refund else "")
	pollen.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(pollen)
	# Room for the card's scroll bar, which this card is the one most likely to show.
	var gutter := Control.new()
	gutter.custom_minimum_size.x = GUTTER
	gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gutter)
	var when := WhenLabel.text(floori(int(line.at) / 1000.0))
	if not when.is_empty(): words.add_child(_wrapped(when, 14, SOFT_INK))
	var receipt := receipt_line(line, money)
	if not receipt.is_empty():
		var shown := _wrapped(receipt, 14, SOFT_INK)
		shown.name = "PollenPurchaseReceipt"
		words.add_child(shown)
	return row

## The store receipt's Paid line ("$3.99 · Google Play order GPA.1234"), from
## what the server kept (presentation/pollen_store_sheets.gd paid_line); the
## order alone without `money`.
static func receipt_line(line: Dictionary, money: bool = true) -> String:
	return StoreSheets.paid_line(PollenMoney.usd(int(line.usd_cents)) if money and int(line.get("usd_cents", -1)) >= 0 else "", str(line.get("order", "")), str(line.get("store", "")))

static func _wrapped(value: String, size: int, color: Color) -> Label:
	var label := ShopKit.text(value, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

static func _rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = Color(0, 0, 0, 0.08)
	rule.custom_minimum_size.y = 1
	return rule

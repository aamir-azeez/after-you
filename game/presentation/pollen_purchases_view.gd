extends RefCounted
## The Purchases card on Pollen from play when the page lists purchases (pollen
## boards 1 and 2: Settings › Account & recovery › Pollen and purchases): the
## money spent on bundles in total, then each bundle bought or refunded, newest
## first, with its art, its Pollen, its date and the receipt line the store's
## receipt shows ("$3.99 · Google Play order GPA.1234-..."). Money is the server's
## US figure (services/pollen_history.gd), so the total says it is in US dollars.
## Pure drawing: presentation/pollen_play_page.gd gives it the card's column and
## the data; it keeps nothing and takes no input.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const BundleArt = preload("res://presentation/kit/bundle_art.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const WhenLabel = preload("res://presentation/when_label.gd")
const StoreSheets = preload("res://presentation/pollen_store_sheets.gd")

const INK := Color("1d3230")
const SOFT_INK := Color("4e6660")
const BOX := Color("fbf8ec")
const BOX_EDGE := Color("e4dcc4")
const REFUND_INK := Color("8a4b42")
const ROW_SIZE := 17
const ART := 46.0
const GUTTER := 10.0

## Fills `column` (already empty) from {lines (services/pollen_history.gd
## purchases), spent_usd_cents (-1 when unknown: no total), loading}: the title
## always, the rest once the history is in.
static func fill(column: VBoxContainer, model: Dictionary, title_font: Font) -> void:
	var heading := ShopKit.text(PlayerCopy.POLLEN_PURCHASES_TITLE, 23, INK, title_font if title_font != null else ShopKit.heading_font())
	column.add_child(heading)
	column.add_child(_wrapped(PlayerCopy.POLLEN_PURCHASES_NOTE, 15, SOFT_INK))
	if bool(model.get("loading", false)): return
	var lines: Array = model.get("lines", [])
	if lines.is_empty():
		var none := _wrapped(PlayerCopy.POLLEN_PURCHASES_NONE, ROW_SIZE, SOFT_INK)
		none.name = "PollenPurchasesNone"
		column.add_child(none)
		return
	if int(model.get("spent_usd_cents", -1)) >= 0: column.add_child(_total(int(model.spent_usd_cents), title_font))
	for index in range(lines.size()):
		if index > 0: column.add_child(_rule())
		column.add_child(_row(lines[index], index))

## "$23.97 spent in total", and that it is in US dollars.
static func _total(cents: int, title_font: Font) -> Control:
	var box := PanelContainer.new()
	box.name = "PollenPurchasesTotal"
	box.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(BOX, 14, BOX_EDGE), 16.0, 12.0))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	box.add_child(column)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	column.add_child(line)
	var amount := ShopKit.text(PollenMoney.usd(cents), 34, INK, title_font if title_font != null else ShopKit.heading_font())
	amount.name = "PollenPurchasesSpent"
	line.add_child(amount)
	var words := ShopKit.text(PlayerCopy.POLLEN_PURCHASES_SPENT, ROW_SIZE, INK)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(words)
	column.add_child(_wrapped(PlayerCopy.POLLEN_PURCHASES_USD, 14, SOFT_INK))
	return box

## One bundle or refund: its art, then the name with its Pollen on the right,
## the date, and the receipt line across the row's full width (an order number
## is one long word).
static func _row(line: Dictionary, index: int) -> Control:
	var refund := str(line.kind) == "bundlerefund"
	var row := HBoxContainer.new()
	row.name = "PollenPurchaseRow%d" % index
	row.add_theme_constant_override("separation", 12)
	var art := BundleArt.new(str(line.bundle), ART)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if refund: art.modulate.a = 0.55
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
	var receipt := receipt_line(line)
	if not receipt.is_empty():
		var shown := _wrapped(receipt, 14, SOFT_INK)
		shown.name = "PollenPurchaseReceipt"
		words.add_child(shown)
	return row

## The store receipt's Paid line ("$3.99 · Google Play order GPA.1234"), from
## what the server kept (presentation/pollen_store_sheets.gd paid_line).
static func receipt_line(line: Dictionary) -> String:
	return StoreSheets.paid_line(PollenMoney.usd(int(line.usd_cents)) if int(line.get("usd_cents", -1)) >= 0 else "", str(line.get("order", "")))

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

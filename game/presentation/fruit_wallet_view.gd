extends RefCounted
## The Your Fruits card on the Fruits page (Fruits board 6a), on the Orchard
## plum: the big balance with the Fruit, the newest Fruit lines (a Full Journey
## month, an achievement with its place and date, a pack, Fruits turned into
## Pollen, and a refund of any of them), and the buttons: Get Fruits (only
## while Fruit packs sell), Open the Orchard, Sunshine and Turn into Pollen
## (each only while there is something for it).
## Pure drawing: presentation/fruits_page.gd gives it the card's parts and the
## data; it keeps nothing. Its buttons say which was pressed through `pressed`.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const CurrencyMark = preload("res://presentation/kit/currency_mark.gd")
const Orchard = preload("res://presentation/kit/orchard_surface.gd")
const SunMark = preload("res://presentation/kit/sun_mark.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const PollenHistory = preload("res://services/pollen_history.gd")
const Bundles = preload("res://services/pollen_bundles.gd")
const WhenLabel = preload("res://presentation/when_label.gd")

const ROW_SIZE := 18
const NOTE_SIZE := 14
const BIG := 64
## The buttons, in the board's order.
const GET := "get"
const ORCHARD := "orchard"
const SUNSHINE := "sunshine"
const CONVERT := "convert"

## Fills the card's `lines` column (inside its scroll) and `buttons` row from
## {balance, entries (services/pollen_history.gd fruit_entries), buttons
## ([GET, ORCHARD, SUNSHINE, CONVERT] as shown)}; `pressed(name, button)` runs on a button.
static func fill(head: VBoxContainer, lines: VBoxContainer, buttons: GridContainer, model: Dictionary, title_font: Font, pressed: Callable) -> void:
	var title := ShopKit.text(PlayerCopy.FRUIT_WALLET_TITLE, 26, Orchard.TEXT, title_font if title_font != null else ShopKit.heading_font())
	title.name = "FruitWalletTitle"
	head.add_child(title)
	var balance := HBoxContainer.new()
	balance.name = "FruitWalletBalance"
	balance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	balance.add_theme_constant_override("separation", 14)
	head.add_child(balance)
	balance.add_child(CurrencyMark.make(CurrencyMark.FRUITS, 72.0))
	var figure := ShopKit.text(PollenMoney.grouped(int(model.get("balance", 0))), BIG, Orchard.TEXT, ShopKit.heading_font())
	figure.name = "FruitWalletAmount"
	figure.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	balance.add_child(figure)
	var entries: Array = model.get("entries", [])
	for index in range(entries.size()):
		if index > 0: lines.add_child(_rule())
		lines.add_child(line(entries[index], index))
	for which: String in model.get("buttons", []):
		var button := _button(which)
		button.pressed.connect(func() -> void: pressed.call(which, button))
		buttons.add_child(button)

## One Fruit line: what it was, its place and date, and its Fruits ("+12", "−20").
static func line(entry: Dictionary, index: int = 0) -> Control:
	var row := HBoxContainer.new()
	row.name = "FruitLine%d" % index
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	row.add_child(words)
	var named := ShopKit.text(name_of(entry), ROW_SIZE, Orchard.TEXT)
	named.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(named)
	var detail := detail_of(entry)
	if not detail.is_empty(): words.add_child(ShopKit.text(detail, NOTE_SIZE, Orchard.TEXT_SOFT))
	var amount := int(entry.get("amount", 0))
	var said := PlayerCopy.FRUIT_GOAL_PAID % PollenMoney.grouped(amount) if amount > 0 else PlayerCopy.WARDROBE_MINUS % PollenMoney.grouped(-amount)
	var value := ShopKit.text(said, ROW_SIZE, Orchard.TEXT, ShopKit.bold_font())
	value.name = "FruitLineAmount"
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value)
	return row

## What a Fruit line was: "Full Journey, month 3", a goal's name, a pack's name,
## "Turned into Pollen", or any of them ", refunded".
static func name_of(entry: Dictionary) -> String:
	var kind := str(entry.get("kind", ""))
	var base := kind.trim_suffix("refund")
	var named := ""
	match base:
		"grant": named = PlayerCopy.FRUIT_LINE_GRANT % int(entry.step) if int(entry.get("step", 0)) > 0 else PlayerCopy.FRUIT_LINE_GRANT_PLAIN
		"welcome": named = PlayerCopy.FRUIT_LINE_WELCOME
		"bundle": named = Bundles.display_name(str(entry.get("bundle", "")))
		"ach": named = str(PlayerCopy.FRUIT_GOALS.get(str(entry.get("id", "")), ""))
		"convert": named = PlayerCopy.FRUIT_LINE_CONVERT
	if named.is_empty(): named = PlayerCopy.FRUITS_PAGE_TITLE
	return PlayerCopy.FRUIT_LINE_REFUNDED % named if kind.ends_with("refund") else named

## Its place and date ("The Relay Isles · Jan 12, 9:42 PM"), the date alone, or "".
static func detail_of(entry: Dictionary) -> String:
	var when := WhenLabel.text(floori(int(entry.get("at", 0)) / 1000.0))
	var place := PollenHistory.chapter_title(str(entry.get("level_id", "")))
	if place.is_empty(): return when
	return PlayerCopy.FRUIT_LINE_DETAIL % [place, when] if not when.is_empty() else place

## A button of the card: Get Fruits peach with the Fruit, the rest outlined.
static func _button(which: String) -> Button:
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	var words := ""
	match which:
		GET:
			words = PlayerCopy.ORCHARD_GET_FRUITS
			content.add_child(CurrencyMark.beside(CurrencyMark.FRUITS, 20))
		ORCHARD: words = PlayerCopy.FRUITS_PAGE_ORCHARD
		SUNSHINE:
			words = PlayerCopy.FRUITS_PAGE_SUNSHINE
			content.add_child(SunMark.beside(20, Orchard.TEXT))
		CONVERT:
			words = PlayerCopy.FRUITS_PAGE_CONVERT
			content.add_child(CurrencyMark.beside(CurrencyMark.POLLEN, 20))
	var ink := Orchard.PEACH_INK if which == GET else Orchard.TEXT
	content.add_child(ShopKit.text(words, 20, ink, ShopKit.bold_font()))
	var button := ShopKit.content_button(content, 54.0)
	# The board's room either side of the words.
	button.custom_minimum_size.x += 20.0
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.name = "FruitsPage_" + which
	button.accessibility_name = words
	if which == GET: Orchard.peach_button(button, 14)
	else: _outlined(button)
	# The store and turning Fruits into Pollen need the server.
	if which in [GET, CONVERT]: OfflineHold.hold(button)
	return button

static func _outlined(button: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var fill := Color.TRANSPARENT
		if state == "hover": fill = Color(Orchard.TEXT, 0.06)
		if state in ["pressed", "hover_pressed"]: fill = Color(Orchard.TEXT, 0.12)
		var edge := Orchard.TEXT if state == "focus" else Color(Orchard.TEXT_SOFT, 0.35 if state == "disabled" else 0.85)
		button.add_theme_stylebox_override(state, Orchard.flat(14, fill, edge))

static func _rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.1)
	rule.custom_minimum_size.y = 1
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule

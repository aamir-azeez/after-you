extends RefCounted
## The short of Pollen card's buy button (owner, 2026-11-02): it shows the
## suggested bundle's own store price ("$19.99") and buys that bundle right
## there, through the Pollen store's one purchase engine
## (presentation/bundle_purchase.gd), so the store's own sheet opens with no
## card of ours first: the price is on the button.
## - Until the store priced the bundles the button shows the bundle's name in
##   its loading look, and turns into the price when the prices come. A tap
##   meanwhile waits for them (BusyTapGate), so the first tap registers.
## - While a purchase is out the button takes no taps, so a double tap buys once.
## - Cancelled or failed: the card stays, with the line the store says it in.
##   A claim left waiting says the Pollen is on its way and the card can close.
## - Credited: the receipt counts as seen (the Pollen store would show it
##   otherwise) and `credited` runs; the card's owner decides what opens next.
##   Nothing is spent here: an item still takes its own Buy tap.
## - A price read that ends with the store no longer selling (an iPhone whose
##   capabilities read turned bundles off) takes the bundle box away, leaving
##   only the line about earning by playing.
## The button's words sit in its content (kit/shop_kit.gd set_button_content),
## so the tap gate's label never stands over them. It lives as long as its button.
const BusyTapGate = preload("res://presentation/busy_tap_gate.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")

## The display name card's error colour (presentation/display_name_prompt.gd).
const ERROR := Color("f2b8ae")
const FONT_SIZE := 18

var button: Button
var bundle := ""
var buyer: Node
var status: Label
## The card and the bundle box the button sits in.
var card: WeakRef
var box: WeakRef
var credited: Callable
var _gate: BusyTapGate
## The purchase this button started is out, or went through.
var _out := false

## A buy button for `bundle` on `modal` (the tap gate's area) in `bundle_box`,
## saying how a purchase ended on `status_line`. `engine` is the store's BundlePurchase.
static func make(modal: Control, bundle_box: Control, bundle_id: String, engine: Node, status_line: Label, on_credited: Callable) -> Button:
	var made := Button.new()
	made.name = "WardrobeShortBuy"
	made.custom_minimum_size = Vector2(120, 50)
	made.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var buy := new()
	buy.button = made
	buy.bundle = bundle_id
	buy.buyer = engine
	buy.status = status_line
	buy.card = weakref(modal)
	buy.box = weakref(bundle_box)
	buy.credited = on_credited
	buy._gate = BusyTapGate.new(modal)
	made.set_meta(&"short_card_buy", buy)
	engine.prices_changed.connect(buy._show_price)
	made.pressed.connect(buy.tap)
	buy._show_price()
	engine.ensure_prices()
	return made

## The button's words and look (the theme's cream button): the price in ink,
## or the bundle's name in soft ink while it loads; faded while a purchase is out.
func _show_price(_loaded: bool = false) -> void:
	if not is_instance_valid(button): return
	if not buyer.priced() and not buyer.loading() and not buyer.flow.available():
		var shut: Variant = box.get_ref()
		if shut is Control: (shut as Control).visible = false
		_say("")
		return
	var price: String = buyer.price(bundle)
	var title := str(PlayerCopy.POLLEN_STORE_BUNDLES.get(bundle, bundle))
	var ink := UiTokens.DISABLED_TEXT if button.disabled else ShopKit.INK_SOFT if price.is_empty() else ShopKit.INK
	ShopKit.set_button_content(button, ShopKit.text(title if price.is_empty() else price, FONT_SIZE, ink, ShopKit.bold_font()))
	button.text = ""
	button.accessibility_name = title if price.is_empty() else "%s, %s" % [title, price]

## A tap: waits for the prices (a read that failed goes again), then opens the store's sheet.
func tap() -> void:
	if _out or not _card_up(): return
	buyer.ensure_prices()
	_say("")
	_gate.tap(button, "", _ready_check(buyer), _run_once(weakref(self)), _alive(card), _expired(weakref(self)))

## Whether the card is still up (a card closed this frame is only queued to go).
func _card_up() -> bool:
	return _alive(card).call() and is_instance_valid(button)

## Lambdas made here hold no button, so a card closed meanwhile only ends the wait.
## The wait ends once a purchase may start, or once a price read ended without prices.
static func _ready_check(engine: Node) -> Callable:
	return func() -> bool: return engine.ready_to_buy() or (not engine.priced() and not engine.loading())

static func _alive(ref: WeakRef) -> Callable:
	return func() -> bool:
		var node: Variant = ref.get_ref()
		return node is Control and (node as Control).is_inside_tree() and not (node as Control).is_queued_for_deletion()

static func _run_once(ref: WeakRef) -> Callable:
	return func() -> void:
		var buy: Variant = ref.get_ref()
		if buy != null: buy._buy()

static func _expired(ref: WeakRef) -> Callable:
	return func() -> void:
		var buy: Variant = ref.get_ref()
		if buy != null: buy._say(PlayerCopy.POLLEN_STORE_OFFLINE, true)

func _buy() -> void:
	if _out or not _card_up(): return
	if buyer.price(bundle).is_empty():
		_say(PlayerCopy.POLLEN_STORE_OFFLINE, true)
		return
	var refused: String = buyer.buy(bundle, _ended)
	if not refused.is_empty():
		_say(PlayerCopy.POLLEN_STORE_OFFLINE, true)
		return
	_out = true
	button.disabled = true
	_show_price()

## How the purchase ended (presentation/bundle_purchase.gd).
func _ended(ended: Dictionary) -> void:
	match str(ended.outcome):
		"credited":
			buyer.take_unseen()
			if credited.is_valid(): credited.call()
		"on_its_way": _say(PlayerCopy.POLLEN_STORE_ON_ITS_WAY)
		_:
			_out = false
			if is_instance_valid(button): button.disabled = false
			_show_price()
			_say(PlayerCopy.MAIN_B621C76A2638 if ended.outcome == "cancelled" else str(ended.message), true)

func _say(text: String, error: bool = false) -> void:
	if not is_instance_valid(status): return
	status.text = text
	status.visible = not text.is_empty()
	status.add_theme_color_override("font_color", ERROR if error else ShopKit.CREAM)

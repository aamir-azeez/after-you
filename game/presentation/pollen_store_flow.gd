extends Node
## The Pollen store (Pollen board 2): the page, its confirm card, the store's
## own sheet (Google Play, or the App Store on iPhone), and the receipt. It
## sells only while the server has this store's bundles on (POLLEN_BUNDLES on
## Play, POLLEN_BUNDLES_APP_STORE on iPhone, never without the shop) and the
## build sells them (a Google Play or App Store build with its store key:
## services/pollen_surfaces.gd bundles_visible). The Test Store build and a free
## iPhone build never open it. On iPhone the prices load, and Buy opens Apple's
## sheet, only after this run's capabilities read (Main._read_store_support).
##
## The prices, the store's sheet and the claim after it are its child
## `purchase` (presentation/bundle_purchase.gd), which a short of Pollen card
## buys through too. After a purchase here the receipt shows from the server's
## answer; a claim that gets no answer stays waiting and goes again on the next
## flush, and its receipt shows the next time the store opens.
##
## Main hosts it as a child and reads Main only through this host contract
## (read at call time, so Main or a test can swap a service):
## - services: purchases (services/purchases.gd, or a test's stand-in with the
##   same signals and calls), api, _names_scope, and store_flow when Main has it
##   (configure_purchases, identity_ready, store_configured: the one RevenueCat
##   set-up for this player, shared with Full Journey)
## - screen: mode, running, overlay, ui, _clear_overlay, _toast, and
##   _mark_screen_back when Main has it
## - soundscape when Main has it (play_fixed_cue): a receipt's sound
## - show_pollen_from_play() -> bool (the Pollen page, presentation/pollen_play_flow.gd,
##   true once it opened), for "Earn Pollen free by playing" and the balance on
##   the page's chip; its Back comes back here
## - pollen_client (history) for Previous purchases, the receipts list
##   (presentation/pollen_purchases_view.gd), read once each time it opens
## It asks Main to leave through back_requested and to open the Wardrobe
## through wardrobe_requested. `return_to` names where Back goes ("wardrobe";
## "home" from Home's chip; "pollen" from the Pollen page's chip); Main reads it.
##
## Taps go through a BusyTapGate: a bundle tapped while the store is still
## loading waits for its prices instead of being dropped.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Page = preload("res://presentation/pollen_store_page.gd")
const Sheets = preload("res://presentation/pollen_store_sheets.gd")
const BusyTapGate = preload("res://presentation/busy_tap_gate.gd")
const Bundles = preload("res://services/pollen_bundles.gd")
const BundleClaims = preload("res://services/bundle_claims.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const StoreCurrency = preload("res://services/store_currency.gd")
const PurchasesView = preload("res://presentation/pollen_purchases_view.gd")
## The receipt sounds on the host's soundscape (play_on).
const Soundscape = preload("res://services/soundscape.gd")
const BundlePurchase = preload("res://presentation/bundle_purchase.gd")

const MODE_POLLEN_STORE := "pollen_store"

signal back_requested
signal wardrobe_requested

var host: Node
## What this build shows (services/pollen_surfaces.gd); tests set their own.
var surfaces: RefCounted
## Bundle claims (services/bundle_claims.gd); tests set their own.
var claims: RefCounted
## The wardrobe and wallet kept on this phone; tests set their own.
var wardrobe: RefCounted
var wallet: RefCounted
## () -> bool, awaited: RevenueCat is set up for the signed-in player. Tests set their own.
var store_ready: Callable
## The one purchase engine (presentation/bundle_purchase.gd), shared with the short of Pollen cards.
var purchase: BundlePurchase
var _page: Page
var _gate: BusyTapGate
var _sheet: WeakRef = null
var _status := ""
var _retry := false
## The Previous purchases sheet's history reads; only the newest one draws.
var _purchase_reads := 0
## Where Back returns: "wardrobe" (Main goes to the Wardrobe, or Home), "home" or "pollen".
var return_to := "wardrobe"

func _init(main: Node = null) -> void:
	host = main
	purchase = BundlePurchase.new(self)
	purchase.name = "BundlePurchase"
	add_child(purchase, false, Node.INTERNAL_MODE_BACK)
	purchase.prices_changed.connect(_on_prices)

func _surfaces() -> RefCounted:
	if surfaces == null: surfaces = PollenSurfaces.shared()
	return surfaces

func _claims() -> RefCounted:
	if claims == null: claims = BundleClaims.shared()
	return claims

func _wardrobe() -> RefCounted:
	if wardrobe == null: wardrobe = Wardrobe.shared()
	return wardrobe

func _wallet() -> RefCounted:
	if wallet == null: wallet = PollenWallet.shared()
	return wallet

func _scope() -> Dictionary:
	var value: Variant = host._names_scope() if host != null and host.has_method("_names_scope") else {}
	return value if value is Dictionary else {}

## Whether the store may open: the build sells bundles and the server has them on for this player.
func available() -> bool:
	return host != null and _surfaces().store_sells(_wardrobe(), _scope())

func is_open() -> bool:
	return is_instance_valid(_page) and _page.is_inside_tree() and not _page.is_queued_for_deletion()

## Opens the store, its Back going to `from`.
func show_store(from: String = "wardrobe") -> void:
	if not available(): return
	return_to = from
	host.running = false
	host.mode = MODE_POLLEN_STORE
	host._clear_overlay()
	_page = Page.new()
	_page.back_pressed.connect(func() -> void: back_requested.emit())
	_page.bundle_pressed.connect(tap_bundle)
	_page.earn_pressed.connect(show_earning)
	_page.pollen_pressed.connect(show_earning)
	_page.purchases_pressed.connect(show_purchases)
	_page.retry_pressed.connect(load_store)
	host.overlay.add_child(_page)
	if host.has_method("_mark_screen_back"): host._mark_screen_back(_page.back_button)
	_gate = BusyTapGate.new(_page)
	_status = PlayerCopy.POLLEN_STORE_LOADING
	_retry = false
	_redraw()
	# A purchase whose claim got no answer goes again first; a receipt it brings shows now.
	if _claims().pending(): await _claims().flush()
	_show_unseen()
	load_store()

## Opens the store again with the Back it had (when the Pollen page it opened goes Back).
func reopen() -> void:
	show_store(return_to)

## Reads the store's prices for the bundles (purchase.load_prices; a read
## already out, from a short card, is the one this waits for).
func load_store() -> void:
	if not is_open(): return
	_status = PlayerCopy.POLLEN_STORE_LOADING
	_retry = false
	_redraw()
	purchase.load_prices()

func _on_prices(loaded: bool) -> void:
	if not is_open(): return
	_status = "" if loaded else PlayerCopy.POLLEN_STORE_OFFLINE
	_retry = not loaded
	_redraw()

## A bundle's price button: waits for the prices, then opens the confirm card.
func tap_bundle(id: String) -> void:
	if not is_open() or _gate == null: return
	var button: Button = _page.button(id)
	if button == null: return
	_gate.tap(button, "", purchase.ready_to_buy, func() -> void: confirm(id), func() -> bool: return is_open(),
		func() -> void: _toast(PlayerCopy.POLLEN_STORE_OFFLINE))

## The confirm card for `id` (after a tap; tests call it directly).
func confirm(id: String) -> void:
	if not is_open() or not purchase.packages.has(id) or not purchase.buying.is_empty(): return
	_close_sheet()
	var gift := Bundles.gift(id, Bundles.gift_percent(_view().get("bundles", {})))
	_sheet = weakref(Sheets.confirm(host.ui, id, purchase.price(id), gift, _balance(), _balance_known(), func() -> void: buy(id), _page.button(id)))

## The confirm card's Buy: hands over to the store's sheet.
func buy(id: String) -> void:
	_close_sheet()
	if not is_open(): return
	var refused: String = purchase.buy(id, _purchase_ended)
	# Refused with no purchase out: this run's store answer, or prices a new read took away.
	if not refused.is_empty() and purchase.buying.is_empty(): _toast(PlayerCopy.POLLEN_STORE_OFFLINE)

## How a purchase from this page ended: the receipt, or why there is none.
func _purchase_ended(ended: Dictionary) -> void:
	match str(ended.outcome):
		"credited": _show_unseen(ended.bought)
		"on_its_way":
			# The purchase stands; the claim stays waiting and goes again on the next flush.
			_toast(PlayerCopy.POLLEN_STORE_ON_ITS_WAY)
			_redraw()
		_:
			_toast(PlayerCopy.MAIN_B621C76A2638 if ended.outcome == "cancelled" else str(ended.message))
			_redraw()

## Shows the receipts the player has not seen, newest last on top. `bought`,
## the package a purchase just paid for, gives the receipt its local price.
func _show_unseen(bought: Dictionary = {}) -> void:
	if not is_open(): return
	var receipts: Array = purchase.take_unseen()
	if receipts.is_empty():
		_redraw()
		return
	_close_sheet()
	var newest: Dictionary = receipts.back()
	var paid := str(bought.get("price", "")) if str(bought.get("bundle", "")) == str(newest.bundle) else ""
	_sheet = weakref(Sheets.receipt(host.ui, newest, int(newest.get("balance", _balance())), paid, func() -> void: wardrobe_requested.emit(), null))
	Soundscape.play_on(host, "ui_bought")
	_redraw()

## "Earn Pollen free by playing" and the balance on the page's chip: the Pollen
## page, whose Back returns here. When the Pollen page opened this store, that
## page is where Back leads, so it goes Back. A page that cannot open (Pollen
## not known on this phone yet) says so.
func show_earning() -> void:
	if not is_open() or not host.has_method("show_pollen_from_play"): return
	_close_sheet()
	if return_to == "pollen": back_requested.emit()
	elif not host.show_pollen_from_play(): _toast(PlayerCopy.POLLEN_PLAY_OFFLINE)

## Previous purchases: the receipts list on its sheet, from one history read.
## Money shows only while the store sells in US dollars (services/store_currency.gd),
## since the server keeps each store's US figure.
func show_purchases() -> void:
	if not is_open(): return
	_close_sheet()
	var sheet := PurchasesView.open(host.ui, _page.purchases_button)
	_sheet = weakref(sheet)
	_read_purchases(sheet)

## One history read for the open receipts list; its Try again reads again.
func _read_purchases(sheet: Control) -> void:
	PurchasesView.render(sheet, {"status": PlayerCopy.POLLEN_PLAY_LOADING})
	_purchase_reads += 1
	var read := _purchase_reads
	var client: Variant = host.get("pollen_client")
	var answer: Dictionary = {}
	if client != null: answer = await client.history()
	# A newer read, or the sheet closed meanwhile: this answer is not shown.
	if read != _purchase_reads or not is_instance_valid(sheet) or sheet.is_queued_for_deletion(): return
	if answer.is_empty(): PurchasesView.render(sheet, {"status": PlayerCopy.POLLEN_PURCHASES_OFFLINE, "retry": _read_purchases.bind(sheet)})
	else: PurchasesView.render(sheet, {"lines": answer.get("purchases", []), "money": StoreCurrency.usd()})

## The page's model (presentation/pollen_store_page.gd).
func model() -> Dictionary:
	var view := _view()
	var part: Dictionary = view.get("bundles", {})
	var bundles: Array = []
	for id: String in Bundles.ids():
		var package: Dictionary = purchase.packages.get(id, {})
		var micros := int(package.get("price_micros", 0))
		var currency := str(package.get("currency", ""))
		var per := ""
		if micros > 0: per = (PlayerCopy.POLLEN_STORE_PER_DOLLAR % PollenMoney.grouped(Bundles.per_unit(id, micros))) if currency in ["", "USD"] else (PlayerCopy.POLLEN_STORE_PER_UNIT % [PollenMoney.grouped(Bundles.per_unit(id, micros)), currency])
		bundles.append({"id": id, "name": str(PlayerCopy.POLLEN_STORE_BUNDLES.get(id, id)), "pollen": Bundles.pollen(id), "base": Bundles.base(id), "bonus": Bundles.bonus(id),
			"percent": Bundles.bonus_percent(id), "per": per, "price": str(package.get("price", ""))})
	return {"balance": _balance(), "balance_known": _balance_known(), "status": _status, "retry": _retry, "gift_percent": Bundles.gift_percent(part), "bundles": bundles}

func _redraw() -> void:
	if is_open(): _page.render(model())

func _view() -> Dictionary:
	var scope := _scope()
	return {} if scope.is_empty() else _wardrobe().view(str(scope.server), str(scope.owner))

func _balance() -> int:
	var scope := _scope()
	if scope.is_empty(): return -1
	var kept: Dictionary = _wallet().wallet(str(scope.server), str(scope.owner))
	return int(kept.get("balance", -1)) if not kept.is_empty() else -1

## Whether the server has said the balance (a refund may leave it below zero, even at -1).
func _balance_known() -> bool:
	var scope := _scope()
	return not scope.is_empty() and not _wallet().wallet(str(scope.server), str(scope.owner)).is_empty()

func _close_sheet() -> void:
	var open: Variant = _sheet.get_ref() if _sheet != null else null
	if open is Control and is_instance_valid(open) and open.has_method("close"): open.close(false)
	_sheet = null

func _toast(text: String) -> void:
	if host != null and host.has_method("_toast"): host._toast(text)

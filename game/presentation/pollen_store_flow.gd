extends Node
## The Pollen store (Pollen board 2): the page, its confirm card, Google Play's
## own sheet, and the receipt. It sells only while the server has bundles on
## (POLLEN_BUNDLES, never without the shop) and the build sells them (a Google
## Play build with its store key: services/pollen_surfaces.gd bundles_visible).
## iPhone and the Test Store build never open it.
##
## What a bundle adds is never decided here. Before Google Play's sheet opens,
## the flow marks a claim as waiting (services/bundle_claims.gd mark_pending), so
## a purchase is claimed even if the app closes during the sheet; a cancelled
## sheet drops the mark. After the sheet says the purchase went through, the
## flow asks the server to claim it and shows the receipt from the server's
## answer. A claim that gets no answer stays waiting and goes again on the next
## flush; its receipt shows the next time the store opens. The store's prices come
## only from the RevenueCat offering "pollen" (services/pollen_bundles.gd).
##
## Main hosts it as a child and reads Main only through this host contract
## (read at call time, so Main or a test can swap a service):
## - services: purchases (services/purchases.gd, or a test's stand-in with the
##   same signals and calls), api, _names_scope, and store_flow when Main has it
##   (configure_purchases, identity_ready, store_configured: the one RevenueCat
##   set-up for this player, shared with Full Journey)
## - screen: mode, running, overlay, ui, _clear_overlay, _toast, and
##   _mark_screen_back when Main has it
## - show_pollen_from_play() -> bool (Pollen from play, presentation/pollen_play_flow.gd,
##   true once it opened), for "Earn Pollen free by playing"; its Back comes back here
## It asks Main to leave through back_requested and to open the Wardrobe
## through wardrobe_requested. `return_to` names where Back goes ("wardrobe",
## or "friends" when the name prompt's short card opened it); Main reads it.
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

const MODE_POLLEN_STORE := "pollen_store"
## How long the store waits for RevenueCat to be set up for this player.
const SETUP_WAIT_MS := 15000
## Claims sent right after a purchase before leaving it to the flush, and the pause between them (growing).
const CLAIM_TRIES := 3
const CLAIM_PAUSE_S := 1.5

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
var _page: Page
var _gate: BusyTapGate
var _sheet: WeakRef = null
## Bundle id -> the offering's package for it, once the store priced it.
var _packages: Dictionary = {}
var _status := ""
var _retry := false
var _loaded := false
var _request := ""
var _buying := ""
## The package being bought, kept for its local price on the receipt.
var _bought: Dictionary = {}
## Whether this purchase set the waiting mark (a cancel then drops it).
var _marked := false
var _generation := 0
## Where Back returns: "wardrobe" (Main goes to the Wardrobe, or Home) or "friends".
var return_to := "wardrobe"

func _init(main: Node = null) -> void:
	host = main

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
	if host == null or not _surfaces().bundles_visible(): return false
	var scope := _scope()
	return not scope.is_empty() and _wardrobe().bundles(str(scope.server), str(scope.owner))

func is_open() -> bool:
	return is_instance_valid(_page) and _page.is_inside_tree() and not _page.is_queued_for_deletion()

func show_store(from: String = "wardrobe") -> void:
	if not available(): return
	return_to = from
	_connect_purchases()
	host.running = false
	host.mode = MODE_POLLEN_STORE
	host._clear_overlay()
	_generation += 1
	_page = Page.new()
	_page.back_pressed.connect(func() -> void: back_requested.emit())
	_page.bundle_pressed.connect(tap_bundle)
	_page.earn_pressed.connect(show_earning)
	_page.retry_pressed.connect(load_store)
	host.overlay.add_child(_page)
	if host.has_method("_mark_screen_back"): host._mark_screen_back(_page.back_button)
	_gate = BusyTapGate.new(_page)
	_packages = {}
	_loaded = false
	_status = PlayerCopy.POLLEN_STORE_LOADING
	_retry = false
	_redraw()
	# A purchase whose claim got no answer goes again first; a receipt it brings shows now.
	if _claims().pending(): await _claims().flush()
	_show_unseen()
	load_store()

## Reads the store's prices for the bundles.
func load_store() -> void:
	if not is_open(): return
	var generation := _generation
	_status = PlayerCopy.POLLEN_STORE_LOADING
	_retry = false
	_redraw()
	var ready: bool = await _store_ready()
	if not is_open() or generation != _generation: return
	if not ready:
		_fail_load()
		return
	_request = host.purchases.fetch_offerings()

func _fail_load() -> void:
	_status = PlayerCopy.POLLEN_STORE_OFFLINE
	_retry = true
	_loaded = false
	_redraw()

func _store_ready() -> bool:
	if store_ready.is_valid(): return await store_ready.call()
	var flow: Variant = host.get("store_flow")
	if flow == null: return false
	if host.has_method("_ensure_identity") and not await host._ensure_identity(): return false
	if not flow.store_configured: flow.configure_purchases(true)
	var deadline := Time.get_ticks_msec() + SETUP_WAIT_MS
	while not flow.identity_ready():
		if Time.get_ticks_msec() >= deadline or not is_open(): return false
		# A set-up that already failed (no request out, nothing configured) is not waited for.
		if not flow.store_configured and str(flow.store_configure_request).is_empty() and Time.get_ticks_msec() >= deadline - SETUP_WAIT_MS + 500: return false
		await get_tree().process_frame
	return true

func _connect_purchases() -> void:
	var purchases: Variant = host.get("purchases")
	if purchases == null: return
	if not purchases.completed.is_connected(_on_completed): purchases.completed.connect(_on_completed)
	if not purchases.failed.is_connected(_on_failed): purchases.failed.connect(_on_failed)

func _on_completed(id: String, operation: String, payload: Dictionary) -> void:
	if operation == "get_offerings" and id == _request:
		_request = ""
		if not is_open(): return
		_packages = Bundles.packages(payload)
		_loaded = not _packages.is_empty()
		_status = "" if _loaded else PlayerCopy.POLLEN_STORE_OFFLINE
		_retry = not _loaded
		_redraw()
	elif operation == "purchase_package" and id == _buying:
		_buying = ""
		_marked = false
		await _claim_after_purchase()

func _on_failed(id: String, operation: String, _code: String, message: String, cancelled: bool) -> void:
	if operation == "get_offerings" and id == _request:
		_request = ""
		if is_open(): _fail_load()
	elif operation == "purchase_package" and id == _buying:
		_buying = ""
		_bought = {}
		# Only a cancelled sheet surely took no payment; any other failure may settle later, so its mark stays.
		if cancelled and _marked: _claims().drop_mark()
		_marked = false
		_toast(PlayerCopy.MAIN_B621C76A2638 if cancelled else message)
		_redraw()

## A bundle's price button: waits for the prices, then opens the confirm card.
func tap_bundle(id: String) -> void:
	if not is_open() or _gate == null: return
	var button: Button = _page.button(id)
	if button == null: return
	_gate.tap(button, "", func() -> bool: return _loaded and _buying.is_empty() and not _claims().sending(), func() -> void: confirm(id), func() -> bool: return is_open(),
		func() -> void: _toast(PlayerCopy.POLLEN_STORE_OFFLINE))

## The confirm card for `id` (after a tap; tests call it directly).
func confirm(id: String) -> void:
	if not is_open() or not _packages.has(id) or not _buying.is_empty(): return
	_close_sheet()
	var package: Dictionary = _packages[id]
	var view := _view()
	var gift := Bundles.gift(id, int(view.get("bundles", {}).get("first_gift_percent", 0))) if bool(view.get("bundles", {}).get("first_gift", false)) else 0
	_sheet = weakref(Sheets.confirm(host.ui, id, str(package.price), gift, _balance(), _balance_known(), func() -> void: buy(id), _page.button(id)))

## The confirm card's Buy: hands over to Google Play's sheet.
func buy(id: String) -> void:
	_close_sheet()
	if not is_open() or not _packages.has(id) or not _buying.is_empty() or not available(): return
	_bought = _packages[id].duplicate()
	_bought.bundle = id
	# The mark goes on before the sheet, so a purchase is claimed even if the app closes during it.
	_marked = _claims().mark_pending()
	_buying = host.purchases.purchase(str(_bought.offering_id), str(_bought.id))

## After Google Play took the payment: the server claims it, then the receipt shows.
func _claim_after_purchase() -> void:
	var answer: Dictionary = {}
	# RevenueCat may list a purchase a moment after Google Play's sheet closes: a few quick tries, then the flush's.
	for attempt in range(CLAIM_TRIES):
		if attempt > 0: await get_tree().create_timer(CLAIM_PAUSE_S * attempt).timeout
		answer = await _claims().claim()
		if answer.get("ok", false) and not (answer.credited as Array).is_empty(): break
		if not is_inside_tree(): return
	if not answer.get("ok", false) or (answer.credited as Array).is_empty():
		# The purchase stands; the claim stays waiting and goes again on the next flush.
		_toast(PlayerCopy.POLLEN_STORE_ON_ITS_WAY)
		_bought = {}
		_redraw()
		return
	_show_unseen()
	_bought = {}

## Shows the receipts the player has not seen, newest last on top.
func _show_unseen() -> void:
	if not is_open(): return
	var receipts: Array = _claims().unseen()
	if receipts.is_empty():
		_redraw()
		return
	_claims().mark_seen()
	_close_sheet()
	var newest: Dictionary = receipts.back()
	var paid := str(_bought.get("price", "")) if str(_bought.get("bundle", "")) == str(newest.bundle) else ""
	_sheet = weakref(Sheets.receipt(host.ui, newest, int(newest.get("balance", _balance())), paid, func() -> void: wardrobe_requested.emit(), null))
	_redraw()

## "Earn Pollen free by playing": Pollen from play, whose Back returns here. A
## page that cannot open (Pollen not known on this phone yet) says so.
func show_earning() -> void:
	if not is_open() or not host.has_method("show_pollen_from_play"): return
	_close_sheet()
	if not host.show_pollen_from_play(): _toast(PlayerCopy.POLLEN_PLAY_OFFLINE)

## The page's model (presentation/pollen_store_page.gd).
func model() -> Dictionary:
	var view := _view()
	var part: Dictionary = view.get("bundles", {})
	var bundles: Array = []
	for id: String in Bundles.ids():
		var package: Dictionary = _packages.get(id, {})
		var micros := int(package.get("price_micros", 0))
		var currency := str(package.get("currency", ""))
		var per := ""
		if micros > 0: per = (PlayerCopy.POLLEN_STORE_PER_DOLLAR % PollenMoney.grouped(Bundles.per_unit(id, micros))) if currency in ["", "USD"] else (PlayerCopy.POLLEN_STORE_PER_UNIT % [PollenMoney.grouped(Bundles.per_unit(id, micros)), currency])
		bundles.append({"id": id, "name": str(PlayerCopy.POLLEN_STORE_BUNDLES.get(id, id)), "pollen": Bundles.pollen(id), "base": Bundles.base(id), "bonus": Bundles.bonus(id),
			"percent": Bundles.bonus_percent(id), "per": per, "price": str(package.get("price", ""))})
	return {"balance": _balance(), "balance_known": _balance_known(), "status": _status, "retry": _retry, "gift_percent": int(part.get("first_gift_percent", 0)) if bool(part.get("first_gift", false)) else 0, "bundles": bundles}

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

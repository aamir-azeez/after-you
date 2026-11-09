extends Node
## The one way a Pollen bundle or a Fruit pack is bought (Google Play, or the
## App Store on iPhone): the store's prices, the store's own sheet and the claim
## after it.
## The Pollen store (presentation/pollen_store_flow.gd) owns it as its child, and
## a short of Pollen card buys through the same one (presentation/short_card_buy.gd),
## so only one purchase is ever out.
##
## What a bundle adds is never decided here. Before the store's sheet opens, a
## claim is marked as waiting (services/bundle_claims.gd mark_pending), so a
## purchase is claimed even if the app closes during the sheet; a cancelled
## sheet drops the mark. After the sheet says the purchase went through, the
## server is asked to claim it a few times; a claim that gets no answer stays
## waiting and goes again on the next flush. The prices come only from the
## RevenueCat offerings "pollen" and "fruits" (services/pollen_bundles.gd
## packages; a Fruit pack is priced only while that offering has its product,
## and the ids never collide, so one `packages` holds both). On iPhone the
## prices load, and a purchase starts, only after this run's capabilities read
## (Main._read_store_support, services/store_support.gd).
##
## It reads its store flow at call time: host (purchases, _read_store_support,
## store_flow, _ensure_identity), store_ready, available() and _claims().
## Whoever starts a purchase hears how it ended, and no one else:
## {outcome: "credited" | "on_its_way" | "cancelled" | "failed", bought, message}.
const Bundles = preload("res://services/pollen_bundles.gd")
const BundleClaims = preload("res://services/bundle_claims.gd")
const StoreSupport = preload("res://services/store_support.gd")
const Connectivity = preload("res://services/connectivity.gd")

## How long a price read waits for RevenueCat to be set up for this player.
const SETUP_WAIT_MS := 15000
## Claims sent right after a purchase before leaving it to the flush, and the pause between them (growing).
const CLAIM_TRIES := 3
const CLAIM_PAUSE_S := 1.5

## A price read ended: `loaded` says whether the store priced the bundles.
signal prices_changed(loaded: bool)

var flow: Node
## Bundle id -> the offering's package for it, once the store priced it,
## for the player in `_priced_for` (a new player reads them again).
var packages: Dictionary = {}
var loaded := false
var _priced_for: Dictionary = {}
## The price read out ("" for none), and whether one is getting ready to go out.
var request := ""
var _loading := false
## The purchase out ("" for none).
var buying := ""
## The package being bought (its bundle and local price) and who hears how it ended.
var _bought: Dictionary = {}
var _done: Callable
## Whether this purchase set the waiting mark (a cancel then drops it).
var _marked := false
## The receipts known when this purchase began (receipts_known): a new one for
## its bundle means its claim was credited, even by a flush the app sent on its
## return from the store's sheet. Its claim takes this and _bought as its own
## when the sheet closes, so a purchase made while it still tries never changes them.
var _known_at_buy: Array = []
## Receipts already shown or taken (take_unseen), newest last: a claim whose
## receipt another purchase took first still counts as credited.
var _shown: Array = []

func _init(store_flow: Node = null) -> void:
	flow = store_flow

func _host() -> Node:
	return flow.host if flow != null else null

func _claims() -> RefCounted:
	return flow._claims()

## Whether the store priced the bundles for the signed-in player.
func priced() -> bool:
	return loaded and _priced_for == flow._scope()

## Whether a purchase may start now: priced, no new read out, none out, and no claim being sent.
func ready_to_buy() -> bool:
	return priced() and not loading() and buying.is_empty() and not _claims().sending()

## The store's own local price for `bundle` ("$19.99"), or "" until it is priced.
func price(bundle: String) -> String:
	return str((packages.get(bundle, {}) as Dictionary).get("price", "")) if priced() else ""

## Whether this player's prices are known or being read; when neither, a read starts.
func ensure_prices() -> void:
	if not priced() and not loading(): load_prices()

## Reads the store's prices, one read at a time: a call while one is out
## waits for that one. Every read ends with prices_changed.
func load_prices() -> void:
	if _loading or not request.is_empty(): return
	_loading = true
	_connect()
	var ready: bool = await _store_ready()
	var host := _host()
	# An iPhone asks the server once this run before it prices anything; its answer may close the store.
	if ready and host != null and host.has_method("_read_store_support"):
		await host._read_store_support()
		ready = flow.available() and StoreSupport.shared().read_now()
	_loading = false
	if not ready or host == null or host.get("purchases") == null:
		_priced({})
		return
	request = host.purchases.fetch_offerings()

## Whether a price read is out.
func loading() -> bool:
	return _loading or not request.is_empty()

func _store_ready() -> bool:
	if flow.store_ready.is_valid(): return await flow.store_ready.call()
	var host := _host()
	var store_flow: Variant = host.get("store_flow") if host != null else null
	if store_flow == null: return false
	if host.has_method("_ensure_identity") and not await host._ensure_identity(): return false
	if not store_flow.store_configured: store_flow.configure_purchases(true)
	var deadline := Time.get_ticks_msec() + SETUP_WAIT_MS
	while not store_flow.identity_ready():
		if Time.get_ticks_msec() >= deadline: return false
		# A set-up that already failed (no request out, nothing configured) is not waited for.
		if not store_flow.store_configured and str(store_flow.store_configure_request).is_empty() and Time.get_ticks_msec() >= deadline - SETUP_WAIT_MS + 500: return false
		await get_tree().process_frame
	return true

func _connect() -> void:
	var host := _host()
	var purchases: Variant = host.get("purchases") if host != null else null
	if purchases == null: return
	if not purchases.completed.is_connected(_on_completed): purchases.completed.connect(_on_completed)
	if not purchases.failed.is_connected(_on_failed): purchases.failed.connect(_on_failed)

func _priced(payload: Dictionary) -> void:
	packages = Bundles.packages(payload)
	# Loaded means the Pollen bundles were priced, as before; the Fruit packs come with the same read.
	loaded = not packages.is_empty()
	packages.merge(Bundles.packages(payload, "", Bundles.FRUITS))
	_priced_for = flow._scope()
	prices_changed.emit(loaded)

## Opens the store's sheet for `bundle`; `done` (outcome: Dictionary) hears how
## it ended. Returns "" once the sheet is asked for, "offline" when this run's
## store answer does not let money move or the phone is offline, or "busy"
## (not priced, or one is out).
## A tap waits for ready_to_buy() first, so a claim being sent is not cut short.
func buy(bundle: String, done: Callable) -> String:
	if not buying.is_empty() or not priced() or not packages.has(bundle) or not flow.available(): return "busy"
	# Money moves only on this run's answer (services/store_support.gd): on iPhone, available() above
	# then reads the bundles that same capabilities read set.
	if not StoreSupport.shared().read_now(): return "offline"
	# Nor while the phone reads as offline (services/connectivity.gd): the claim needs the server.
	if not Connectivity.shared().online(): return "offline"
	_connect()
	_bought = (packages[bundle] as Dictionary).duplicate()
	_bought.bundle = bundle
	_done = done
	# The mark goes on before the sheet, so a purchase is claimed even if the app closes during it.
	_marked = _claims().mark_pending()
	_known_at_buy = receipts_known()
	buying = _host().purchases.purchase(str(_bought.offering_id), str(_bought.id))
	return ""

func _on_completed(id: String, operation: String, payload: Dictionary) -> void:
	if operation == "get_offerings" and id == request:
		request = ""
		_priced(payload)
	elif operation == "purchase_package" and id == buying:
		var bought := _bought
		var known := _known_at_buy
		var done := _done
		_clear_purchase()
		var outcome := await _claim_after_purchase(bought, known)
		if done.is_valid(): done.call({"outcome": outcome, "bought": bought, "message": ""})

func _on_failed(id: String, operation: String, _code: String, message: String, cancelled: bool) -> void:
	if operation == "get_offerings" and id == request:
		request = ""
		_priced({})
	elif operation == "purchase_package" and id == buying:
		var bought := _bought
		var done := _done
		# Only a cancelled sheet surely took no payment; any other failure may settle later, so its mark stays.
		if cancelled and _marked: _claims().drop_mark()
		_clear_purchase()
		if done.is_valid(): done.call({"outcome": "cancelled" if cancelled else "failed", "bought": bought, "message": message})

func _clear_purchase() -> void:
	buying = ""
	_bought = {}
	_done = Callable()
	_known_at_buy = []
	_marked = false

## After the store took the payment: "credited" once the server claimed it, or
## "on_its_way" when the claim is left waiting for the next flush.
## `bought` and `known` are this purchase's own (_bought and _known_at_buy at its buy).
func _claim_after_purchase(bought: Dictionary, known: Array) -> String:
	var bundle := str(bought.get("bundle", ""))
	# RevenueCat may list a purchase a moment after the store's sheet closes: a few quick tries, then the flush's.
	for attempt in range(CLAIM_TRIES):
		if attempt > 0: await get_tree().create_timer(CLAIM_PAUSE_S * attempt).timeout
		# Always asked once: a flush that credited an older purchase first clears the mark this one needs.
		await _claims().claim()
		# Credited by this claim, or by a flush (the app's return from the store's sheet) before it.
		if credited_since(known, bundle): return "credited"
		if not is_inside_tree(): return "on_its_way"
	return "credited" if credited_since(known, bundle) else "on_its_way"

## The receipts already shown or taken and those still unseen, Pollen and Fruits.
func receipts_known() -> Array:
	return _shown + _claims().unseen() + _claims().unseen_fruits()

## Whether a receipt for `bundle` came that `known` (receipts_known at a buy)
## did not have. Another bundle's receipt is another purchase's.
func credited_since(known: Array, bundle: String) -> bool:
	return receipts_known().any(func(receipt: Dictionary) -> bool: return str(receipt.bundle) == bundle and not receipt in known)

## The receipts the player has not seen, oldest first, now marked seen.
func take_unseen() -> Array:
	var receipts: Array = _claims().unseen()
	if receipts.is_empty(): return receipts
	_claims().mark_seen()
	_shown = (_shown + receipts).slice(-BundleClaims.MAX_UNSEEN * 4)
	return receipts

## The Fruit pack receipts the player has not seen, oldest first, now marked seen.
func take_unseen_fruits() -> Array:
	var receipts: Array = _claims().unseen_fruits()
	if receipts.is_empty(): return receipts
	_claims().mark_fruits_seen()
	_shown = (_shown + receipts).slice(-BundleClaims.MAX_UNSEEN * 4)
	return receipts

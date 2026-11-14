extends Node
## The store (Fruits boards 9 and 3, after Pollen board 2) with its Pollen tab
## and, while Fruits show (services/pollen_surfaces.gd fruits_visible), its
## Fruits tab: the page, its confirm card, the store's
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
## - open_fruits_page(from) and open_fruit_convert() when Main has them (the
##   Fruits page and its convert card): the chip's Fruit half, "Fruits for
##   playing together" and "Turn Fruits into Pollen", each shown only while
##   Main can open it
## - menu_opened(screen, from, back) when Main has it: the one back history the
##   menu screens share (presentation/menu_back.gd), told the store opened over `from`
## It asks Main to leave through back_requested (Main's back history says where
## Back goes) and to open the Wardrobe through wardrobe_requested.
##
## The Fruits tab lists a Fruit pack only while the server sells them in this
## phone's store (fruit_packs_visible) and RevenueCat's "fruits" offering priced
## it. Fruit packs buy through the same purchase engine and claim, with the same
## loading, error and receipt feedback as the Pollen bundles.
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
const OfflineHold = preload("res://presentation/offline_hold.gd")
const StoreCurrency = preload("res://services/store_currency.gd")
const PurchasesView = preload("res://presentation/pollen_purchases_view.gd")
## The receipt sounds on the host's soundscape (play_on).
const Soundscape = preload("res://services/soundscape.gd")
const BundlePurchase = preload("res://presentation/bundle_purchase.gd")
const BundleArt = preload("res://presentation/kit/bundle_art.gd")
const PollenChip = preload("res://presentation/kit/pollen_chip.gd")
const FruitWallet = preload("res://services/fruit_wallet.gd")

const MODE_POLLEN_STORE := "pollen_store"
## Its name in Main's back history (presentation/menu_back.gd).
const MENU_SCREEN := "store"

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
## The Fruits kept on this phone (services/fruit_wallet.gd); tests set their own.
var fruits: RefCounted
## The tab showing: "pollen" or "fruits".
var tab := Bundles.POLLEN
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

func _fruits() -> RefCounted:
	if fruits == null: fruits = FruitWallet.shared()
	return fruits

## Whether the Fruits tab shows: Fruits show for the signed-in player.
func fruits_shown() -> bool:
	return _surfaces().fruits_visible(_fruits(), _scope())

## Whether Fruit packs sell here now (the Fruits tab's cards).
func fruit_packs_sell() -> bool:
	return _surfaces().fruit_packs_visible(_fruits(), _scope())

func _scope() -> Dictionary:
	var value: Variant = host._names_scope() if host != null and host.has_method("_names_scope") else {}
	return value if value is Dictionary else {}

## Whether the store may open: the build sells bundles and the server has them on for this player.
func available() -> bool:
	return host != null and _surfaces().store_sells(_wardrobe(), _scope())

func is_open() -> bool:
	return is_instance_valid(_page) and _page.is_inside_tree() and not _page.is_queued_for_deletion()

## Opens the store on `tab_name` ("pollen", or "fruits" while Fruits show) over the screen `from` (Main's back history).
## Offline it says why and asks the server once instead: prices and buying need it.
func show_store(from: String = "wardrobe", tab_name: String = Bundles.POLLEN) -> void:
	if not available(): return
	if OfflineHold.refuse(): return
	tab = Bundles.FRUITS if tab_name == Bundles.FRUITS and fruits_shown() else Bundles.POLLEN
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
	_page.tab_pressed.connect(set_tab)
	_page.fruits_pressed.connect(show_fruits)
	_page.together_pressed.connect(show_fruits)
	_page.convert_pressed.connect(show_convert)
	# The chip and the Fruits tab follow the kept Fruits (a claim, a conversion, a read).
	if not _fruits().changed.is_connected(_on_fruits_changed): _fruits().changed.connect(_on_fruits_changed)
	host.overlay.add_child(_page)
	if host.has_method("_mark_screen_back"): host._mark_screen_back(_page.back_button)
	if host.has_method("menu_opened"): host.menu_opened(MENU_SCREEN, from, _page.back_button)
	_gate = BusyTapGate.new(_page)
	_status = PlayerCopy.POLLEN_STORE_LOADING
	_retry = false
	_redraw()
	# A purchase whose claim got no answer goes again first; a receipt it brings shows now.
	if _claims().pending(): await _claims().flush()
	_show_unseen()
	load_store()

## Opens the store again on the tab it had (Back from a page it opened).
func reopen() -> void:
	show_store("", tab)

## A tab: the Pollen bundles, or the Fruit packs while Fruits show.
func set_tab(tab_name: String) -> void:
	if not is_open(): return
	var wanted := Bundles.FRUITS if tab_name == Bundles.FRUITS and fruits_shown() else Bundles.POLLEN
	if wanted == tab: return
	tab = wanted
	_close_sheet()
	_redraw()

## The chip's Fruit half and "Fruits for playing together": the Fruits page,
## whose Back comes here (or, when the Fruits page opened this store, the
## history goes back to it).
func show_fruits() -> void:
	if not is_open(): return
	_close_sheet()
	if host.has_method("open_fruits_page"): host.open_fruits_page(MENU_SCREEN)

## "Turn Fruits into Pollen": the convert card over the store.
func show_convert() -> void:
	if not is_open() or not host.has_method("open_fruit_convert"): return
	_close_sheet()
	host.open_fruit_convert()

func _on_fruits_changed(_server: String, _owner: String) -> void:
	_redraw()

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
	# A Fruit pack sells only while the server sells Fruit packs here.
	if Bundles.currency_of(id) == Bundles.FRUITS and not fruit_packs_sell(): return
	_close_sheet()
	var fruit := Bundles.currency_of(id) == Bundles.FRUITS
	var gift := Bundles.gift(id, Bundles.gift_percent(_offer(Bundles.currency_of(id))))
	var balance := _fruit_balance() if fruit else _balance()
	var known := _fruits_known() if fruit else _balance_known()
	_sheet = weakref(Sheets.confirm(host.ui, id, purchase.price(id), gift, balance, known, func() -> void: buy(id), _page.button(id)))

## The confirm card's Buy: hands over to the store's sheet.
func buy(id: String) -> void:
	_close_sheet()
	if not is_open() or (Bundles.currency_of(id) == Bundles.FRUITS and not fruit_packs_sell()): return
	var refused: String = purchase.buy(id, _purchase_ended)
	# Refused with no purchase out: this run's store answer, or prices a new read took away.
	if not refused.is_empty() and purchase.buying.is_empty(): _toast(PlayerCopy.POLLEN_STORE_OFFLINE)

## How a purchase from this page ended: the receipt, or why there is none.
func _purchase_ended(ended: Dictionary) -> void:
	match str(ended.outcome):
		"credited": _show_unseen(ended.bought)
		"on_its_way":
			# The purchase stands; the claim stays waiting and goes again on the next flush.
			_toast(PlayerCopy.FRUIT_STORE_ON_ITS_WAY if Bundles.currency_of(str(ended.bought.get("bundle", ""))) == Bundles.FRUITS else PlayerCopy.POLLEN_STORE_ON_ITS_WAY)
			_redraw()
		_:
			_toast(PlayerCopy.MAIN_B621C76A2638 if ended.outcome == "cancelled" else str(ended.message))
			_redraw()

## Shows the receipts the player has not seen of one currency, newest last on
## top: the currency `bought` is in (the package a purchase just paid for,
## which gives the receipt its local price), else Pollen, else Fruits. Only
## that currency's receipts count as seen; the other's show on the next visit.
## Fruit receipts show only while Fruits do.
func _show_unseen(bought: Dictionary = {}) -> void:
	if not is_open(): return
	var fruit_first: bool = Bundles.currency_of(str(bought.get("bundle", ""))) == Bundles.FRUITS if not bought.is_empty() else (_claims().unseen() as Array).is_empty()
	var receipts: Array = purchase.take_unseen_fruits() if fruit_first and fruits_shown() else purchase.take_unseen()
	if receipts.is_empty():
		_redraw()
		return
	_close_sheet()
	var newest: Dictionary = receipts.back()
	var paid := str(bought.get("price", "")) if str(bought.get("bundle", "")) == str(newest.bundle) else ""
	var fruit := Bundles.currency_of(str(newest.bundle)) == Bundles.FRUITS
	var after := int(newest.get("balance", _fruit_balance() if fruit else _balance()))
	_sheet = weakref(Sheets.receipt(host.ui, newest, after, paid, func() -> void: wardrobe_requested.emit(), null))
	Soundscape.play_on(host, "ui_bought")
	_redraw()

## "Earn Pollen free by playing" and the balance on the page's chip: the Pollen
## page, whose Back returns here (or, when the Pollen page opened this store,
## the history goes back to it). A page that cannot open (Pollen not known on
## this phone yet) says so.
func show_earning() -> void:
	if not is_open() or not host.has_method("show_pollen_from_play"): return
	_close_sheet()
	if not host.show_pollen_from_play(): _toast(PlayerCopy.POLLEN_PLAY_OFFLINE)

## Previous purchases: the receipts list on its sheet, from one history read.
## Money shows only while the store sells in US dollars (services/store_currency.gd),
## since the server keeps each store's US figure.
func show_purchases() -> void:
	if not is_open(): return
	_close_sheet()
	var sheet := PurchasesView.open(host.ui, _page.purchases_button, fruits_shown())
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
	else: PurchasesView.render(sheet, {"lines": PurchasesView.lines(answer, fruits_shown()), "money": StoreCurrency.usd()})

## The page's model (presentation/pollen_store_page.gd): the tab showing, its
## first pack card while that currency's gift is on and unused, and its packs
## (every Pollen bundle, priced or not; a Fruit pack only once priced, and only
## while Fruit packs sell). The pack with the most for the money carries the
## ribbon and its per $1 figure.
func model() -> Dictionary:
	if tab == Bundles.FRUITS and not fruits_shown(): tab = Bundles.POLLEN
	var fruit := tab == Bundles.FRUITS
	var percent := Bundles.gift_percent(_offer(tab))
	var bundles: Array = []
	if not fruit or fruit_packs_sell():
		for id: String in Bundles.ids(tab):
			var package: Dictionary = purchase.packages.get(id, {})
			if fruit and package.is_empty(): continue
			bundles.append({"id": id, "currency": tab, "name": Bundles.display_name(id), "amount": Bundles.amount(id), "bonus": Bundles.bonus(id), "percent": Bundles.bonus_percent(id),
				"first": Bundles.adds(id, _offer(tab)) if percent > 0 else 0, "price": str(package.get("price", "")), "best": false, "ribbon": "", "per": ""})
	_mark_best(bundles)
	var first := {}
	var pictured := BundleArt.first_pack(tab).trim_suffix("_pair")
	if percent > 0 and not bundles.is_empty() and pictured in Bundles.ids(tab):
		var title := (PlayerCopy.FRUIT_STORE_FIRST_DOUBLE if percent == 100 else PlayerCopy.FRUIT_STORE_FIRST % percent) if fruit else PlayerCopy.POLLEN_STORE_FIRST % percent
		first = {"currency": tab, "title": title, "pair": BundleArt.first_pack(tab), "caption": (PlayerCopy.FRUIT_STORE_FIRST_AS if fruit else PlayerCopy.POLLEN_STORE_FIRST_AS) % Bundles.display_name(pictured),
			"amount": Bundles.amount(pictured), "gift": Bundles.gift(pictured, percent)}
	var together := fruit and host != null and host.has_method("open_fruits_page") and host.has_method("show_fruits_page")
	var convert := fruit and host != null and host.has_method("open_fruit_convert") and host.has_method("show_fruit_convert")
	return {"balance": _balance(), "balance_known": _balance_known(), "fruits": PollenChip.fruits_for(_scope(), _surfaces(), _fruits()), "status": _status, "retry": _retry,
		"tabs": fruits_shown(), "tab": tab, "first": first, "bundles": bundles, "together": together, "convert": convert, "gift_percent": percent}

## Gives the priced pack with the most for one unit of the store's currency
## (the biggest on a tie) the ribbon and its per unit figure.
func _mark_best(bundles: Array) -> void:
	var best := -1
	var most := 0
	for index in range(bundles.size()):
		var package: Dictionary = purchase.packages.get(str(bundles[index].id), {})
		var per := Bundles.per_unit(str(bundles[index].id), int(package.get("price_micros", 0)))
		if per > 0 and per >= most:
			most = per
			best = index
	if best < 0: return
	var entry: Dictionary = bundles[best]
	var unit := str((purchase.packages.get(str(entry.id), {}) as Dictionary).get("currency", ""))
	var dollars := unit in ["", "USD"]
	var fruit := str(entry.currency) == Bundles.FRUITS
	entry.best = true
	if dollars: entry.ribbon = PlayerCopy.FRUIT_STORE_MOST if fruit else PlayerCopy.POLLEN_STORE_MOST
	else: entry.ribbon = (PlayerCopy.FRUIT_STORE_MOST_UNIT if fruit else PlayerCopy.POLLEN_STORE_MOST_UNIT) % unit
	entry.per = (PlayerCopy.STORE_CARD_PER_DOLLAR % PollenMoney.grouped(most)) if dollars else (PlayerCopy.STORE_CARD_PER_UNIT % [PollenMoney.grouped(most), unit])

## The first pack gift's offer for `currency` (services/pollen_bundles.gd gift_percent):
## the wardrobe view's bundles part for Pollen, the kept Fruits' offer for Fruits.
func _offer(currency: String) -> Dictionary:
	if currency != Bundles.FRUITS: return _view().get("bundles", {})
	var scope := _scope()
	return {} if scope.is_empty() else _fruits().offer(str(scope.server), str(scope.owner))

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

## The kept Fruit balance (0 until the server has said; below 0 after a refund).
func _fruit_balance() -> int:
	var scope := _scope()
	return 0 if scope.is_empty() else int(_fruits().balance(str(scope.server), str(scope.owner)))

## Whether the server has said the Fruit balance.
func _fruits_known() -> bool:
	var scope := _scope()
	return not scope.is_empty() and not _fruits().part(str(scope.server), str(scope.owner)).is_empty()

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

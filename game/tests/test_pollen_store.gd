extends SceneTree
## The Pollen store (Pollen board 2: presentation/pollen_store_flow.gd,
## pollen_store_page.gd, pollen_store_sheets.gd) and the bundle claims behind
## it (services/bundle_claims.gd, services/pollen_bundles.gd), with a stand-in
## host, a stand-in store (RevenueCat's purchases bridge) and a fake server:
## - it opens only while the server sells bundles and the build sells them
##   (never on a free iPhone build or the Test Store build);
## - on iPhone: the App Store's own products and prices from the same "pollen"
##   offering, Apple's wording, an App Store receipt line, prices only after this
##   run's server answer, and no sheet without it;
## - the four bundles show the art, totals, bonus lines, Pollen per $1 and the
##   store's own prices from the "pollen" offering only; the first bundle line
##   shows only while that gift is on and unused, on one line with its percent;
## - at 1600x738 and on small phones (1600x720, 1280x720) the header, the first bundle
##   line, the cards and the footer sit in order inside the page, with no gap
##   left where the header's note was;
## - the confirm card adds up in plain sums, and its Buy hands over to the store;
## - a purchase is claimed from the server, and the receipt shows what was
##   added, the balance before and after, the price and the order number;
## - a cancelled or failed purchase claims nothing; a claim that gets no answer
##   stays waiting, goes again on the next flush, and its receipt shows on the
##   next visit; a refund the server took back shows in the balance, below zero;
## - a tap while a claim is still out waits for it (first taps);
## - the claims service checks every answer and keeps its waiting mark on disk;
## - the bundle a short card suggests (services/pollen_bundles.gd cover); the
##   chip without a plus, whose balance opens the Pollen
##   page (or goes Back to it when the page opened the store); Previous
##   purchases opens the receipts list from one history read, money only in US
##   dollars; the footnote no longer points to Settings;
## - the Fruits tab (Fruits board 3) shows only while Fruits show, its packs
##   only while they sell and the "fruits" offering prices them: the first pack
##   card that pays double with the Bowl pair, the ladder with the Barrel framed
##   on plum under "Most Fruits per $1", the chip's Fruit half, "Fruits for
##   playing together" and "Turn Fruits into Pollen" only while Main can open
##   them; a Fruit pack buys through the same engine and claim, with its own
##   confirm card and receipt; Previous purchases lists Fruit packs and refunds;
##   the price buttons, convert and Previous purchases hold while offline;
## - a Wardrobe short card buys its bundle in place through the same purchase
##   engine (presentation/short_card_buy.gd): the bundle's name while the prices
##   load, then its store price; one purchase for any number of taps; once the
##   Pollen arrives the item's confirm card opens on the new balance and nothing
##   is spent without its Buy; a bundle that only got closer opens the short
##   card again; cancelled, failed and on its way stay on the card with their
##   line; on iPhone the same, after this run's server answer, at Apple's price.
const Flow = preload("res://presentation/pollen_store_flow.gd")
const BundlePurchase = preload("res://presentation/bundle_purchase.gd")
const BundleClaims = preload("res://services/bundle_claims.gd")
const AtomicFile = preload("res://services/atomic_file.gd")
const Bundles = preload("res://services/pollen_bundles.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const StoreSupport = preload("res://services/store_support.gd")
const StoreCurrency = preload("res://services/store_currency.gd")
const PollenHistory = preload("res://services/pollen_history.gd")
const WardrobeFlow = preload("res://presentation/wardrobe_flow.gd")
const WardrobeClient = preload("res://services/wardrobe_client.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const FruitWallet = preload("res://services/fruit_wallet.gd")
const Connectivity = preload("res://services/connectivity.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")

# Synthetic ids only.
const ME := "bbbbbbbbbbbbbbbbbbbbbb"
const SERVER := "https://pollen-store.example.test"

var checks := 0
var failures := 0
var _paths: Array[String] = []

class Host extends Node:
	var api: Node = null
	var mode := ""
	var running := true
	var overlay: Control
	var ui: Control
	var purchases: Node
	var toasts: Array = []
	var scope := {}
	var earning_opened := 0
	var earning_opens := true
	var pollen_client: RefCounted = null
	var pollen_store_flow: Node = null
	## The screens the store said it opened over (Main's back history, menu_opened).
	var opened: Array = []
	func menu_opened(_screen: String, from: String, _back: Button) -> void: opened.append(from)
	func show_pollen_from_play() -> bool:
		earning_opened += 1
		return earning_opens
	func _names_scope() -> Dictionary: return scope
	func _clear_overlay() -> void:
		for child: Node in overlay.get_children(): child.queue_free()
	func _toast(text: String) -> void: toasts.append(text)

## An iPhone's Main: its one capabilities read this run (Main._read_store_support)
## notes the server's answer, and the bundles that read carries.
## A Main that hosts the Fruits page and its convert card (Main.open_fruits_page, open_fruit_convert).
class FruitHost extends Host:
	var fruit_pages: Array = []
	var converts := 0
	func show_fruits_page(from: String) -> void: fruit_pages.append(from)
	func open_fruits_page(from: String) -> bool:
		show_fruits_page(from)
		return true
	func show_fruit_convert() -> void: converts += 1
	func open_fruit_convert() -> bool:
		show_fruit_convert()
		return true

class IosHost extends Host:
	var support: RefCounted
	var store: RefCounted
	var reads := 0
	## "on", "off" (the server sells no App Store bundles) or "fail" (no answer).
	var answer := "on"
	func _read_store_support() -> bool:
		reads += 1
		if answer == "fail": return false
		store.set_enabled(scope.server, scope.owner, true, true, answer == "on")
		support.note(scope.server, scope.owner, answer == "on")
		return answer == "on"

## The RevenueCat bridge's signals and calls (services/purchases.gd).
class FakePurchases extends Node:
	signal completed(request_id: String, operation: String, payload: Dictionary)
	signal failed(request_id: String, operation: String, code: String, message: String, cancelled: bool)
	var offerings: Dictionary = {}
	var offerings_fail := false
	## The read stays out until a test answers it.
	var offerings_silent := false
	## "ok", "cancel" or "fail".
	var outcome := "ok"
	var bought: Array = []
	var serial := 0
	func fetch_offerings() -> String:
		serial += 1
		var id := "read-%d" % serial
		if offerings_silent: pass
		elif offerings_fail: failed.emit.call_deferred(id, "get_offerings", "revenuecat_NETWORK_ERROR", "No store", false)
		else: completed.emit.call_deferred(id, "get_offerings", offerings)
		return id
	func purchase(offering_id: String, package_id: String) -> String:
		serial += 1
		var id := "buy-%d" % serial
		bought.append([offering_id, package_id])
		match outcome:
			"ok": completed.emit.call_deferred(id, "purchase_package", {"schema_version": 1})
			"cancel": failed.emit.call_deferred(id, "purchase_package", "revenuecat_PURCHASE_CANCELLED", "Purchase cancelled.", true)
			"silent": pass
			_: failed.emit.call_deferred(id, "purchase_package", "revenuecat_STORE_PROBLEM", "The store had a problem.", false)
		return id

## The store's offerings with the "fruits" one: the four Fruit packs at the Play prices, or `without` left out.
static func _fruit_offerings(without: String = "") -> Dictionary:
	var offerings := _offerings()
	var packages: Array = []
	for row: Array in [["handful", "$2.49", 2490000], ["bowl", "$4.99", 4990000], ["crate", "$9.99", 9990000], ["barrel", "$19.99", 19990000]]:
		if row[0] == without: continue
		packages.append({"id": row[0], "product_id": Bundles.product(row[0], Bundles.PLAY_STORE), "type": "CUSTOM", "price": row[1], "price_micros": float(row[2]), "currency": "USD"})
	offerings.offerings.append({"id": "fruits", "packages": packages})
	return offerings

## The `fruits` part of a wallet read: `balance` Fruits, the first pack gift while `gift`.
static func _fruit_part(balance: int, gift: bool = true) -> Dictionary:
	return {"fruits": {"schema_version": 1.0, "balance": float(balance), "earned": float(maxi(balance, 0)), "first_pack_gift": gift, "first_pack_percent": 100.0, "achievements": []}}

## The Pollen history read behind Previous purchases (services/pollen_client.gd history).
class FakeHistory extends RefCounted:
	var tree: SceneTree
	var answer: Dictionary = {}
	var reads := 0
	func history() -> Dictionary:
		reads += 1
		await tree.process_frame
		return answer.duplicate(true)

class Fake extends RefCounted:
	var tree: SceneTree
	var sent: Array = []
	var replies: Array = []
	var delay := 1
	func call_it(method: int, path: String, body: Dictionary) -> Dictionary:
		sent.append({"method": method, "path": path, "body": body.duplicate(true)})
		for i in range(delay): await tree.process_frame
		var reply: Variant = replies.pop_front() if not replies.is_empty() else {"ok": false, "status": 0, "code": "connection_interrupted"}
		return reply

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _path(stem: String) -> String:
	var path := "user://test-pollen-store-%s-%s.json" % [stem, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

func _frames(count: int = 6) -> void:
	for i in range(count): await process_frame

## The store's offerings: Full Journey's and the Pollen one.
static func _offerings() -> Dictionary:
	var packages: Array = []
	for row: Array in [["pinch", "$0.99", 990000], ["pouch", "$3.99", 3990000], ["jar", "$7.99", 7990000], ["basket", "$19.99", 19990000]]:
		packages.append({"id": "%s_package" % row[0], "product_id": Bundles.product(row[0], Bundles.PLAY_STORE) + ":buy", "type": "CUSTOM", "price": row[1], "price_micros": float(row[2]), "currency": "USD"})
	return {"schema_version": 1, "mode": "google_play", "current_id": "default", "offerings": [
		{"id": "default", "packages": [{"id": "$rc_monthly", "product_id": "after_you_full_journey_monthly", "type": "MONTHLY", "price": "$0.99", "price_micros": 990000.0, "currency": "USD"}]},
		{"id": "pollen", "packages": packages}]}

static func _view(gift: bool, percent: int = 0, balance: int = 9000) -> Dictionary:
	return {"schema_version": 1.0, "balance": float(balance), "earned": float(maxi(balance, 0)), "bank": 12.0, "name_price": 0.0,
		"wardrobe": {"items": [], "packs": [], "look": {}, "look_revision": 1.0, "offered": ["daisy"], "offered_packs": [], "sets": {}, "unlocked": []},
		"bundles": {"first_gift": gift, "first_gift_percent": float(percent), "spent_usd_cents": 0.0}}

static func _credited(bundle: String, gift: int, balance: int, order: String = "GPA.1234-5678-9012-34567", store: String = "") -> Dictionary:
	var credited := {"bundle": bundle, "pollen": float(Bundles.pollen(bundle)), "first_gift": float(gift), "order": order, "purchased_at": 1.8e12, "usd_cents": float(Bundles.usd_cents(bundle))}
	if not store.is_empty(): credited.store = store
	return {"ok": true, "status": 200, "data": {"schema_version": 1.0, "balance": float(balance), "pending": false, "refunded": [], "credited": [credited]}}

## The same "pollen" offering as an iPhone's SDK lists it: the App Store's products and prices.
static func _ios_offerings() -> Dictionary:
	var packages: Array = []
	for row: Array in [["pinch", "$1.49", 1490000], ["pouch", "$4.99", 4990000], ["jar", "$8.99", 8990000], ["basket", "$21.99", 21990000]]:
		packages.append({"id": row[0], "product_id": Bundles.product(row[0], Bundles.APP_STORE), "type": "CUSTOM", "price": row[1], "price_micros": float(row[2]), "currency": "USD"})
	return {"schema_version": 1, "mode": "app_store", "current_id": "default", "offerings": [
		{"id": "default", "packages": [{"id": "$rc_monthly", "product_id": "after_you_full_journey_monthly_ios", "type": "MONTHLY", "price": "$1.49", "price_micros": 1490000.0, "currency": "USD"}]},
		{"id": "pollen", "packages": packages}]}

func _setup(server_bundles: bool = true, build_bundles: bool = true, sells: bool = true, iphone: bool = false, fruit_host: bool = false) -> Dictionary:
	var host: Host = IosHost.new() if iphone else (FruitHost.new() if fruit_host else Host.new())
	host.overlay = Control.new()
	host.ui = Control.new()
	for layer: Control in [host.overlay, host.ui]: layer.size = Vector2(1600, 738)
	root.add_child(host)
	host.add_child(host.overlay)
	host.add_child(host.ui)
	host.scope = {"server": SERVER, "owner": ME}
	var purchases := FakePurchases.new()
	purchases.offerings = _offerings()
	host.add_child(purchases)
	host.purchases = purchases
	var store: RefCounted = Wardrobe.new(_path("wardrobe"))
	var wallet: RefCounted = PollenWallet.new(_path("wallet"))
	store.set_enabled(SERVER, ME, true, true, server_bundles)
	wallet.set_enabled(SERVER, ME, true)
	store.note_view(SERVER, ME, _view(false))
	wallet.note_wallet(SERVER, ME, _view(false))
	var fake := Fake.new()
	fake.tree = self
	# Fruits stay off unless a test turns them on.
	var fruits: RefCounted = FruitWallet.new(_path("fruits"))
	var claims: RefCounted = BundleClaims.new(_path("claims"), store, wallet, fruits)
	claims.connect_to(null, host._names_scope, fake.call_it)
	var flow: Node = Flow.new(host)
	host.add_child(flow)
	flow.surfaces = PollenSurfaces.new(sells, build_bundles)
	flow.claims = claims
	flow.wardrobe = store
	flow.wallet = wallet
	flow.fruits = fruits
	flow.store_ready = func() -> bool: return true
	return {"host": host, "purchases": purchases, "store": store, "wallet": wallet, "fake": fake, "claims": claims, "flow": flow, "fruits": fruits}

## A store with Fruits on (`packs`: Fruit packs sell too) for a player with `balance` Fruits, on a Main that hosts the Fruits page.
func _fruit_setup(packs: bool = true, balance: int = 101, gift: bool = true) -> Dictionary:
	var t := _setup(true, true, true, false, true)
	t.purchases.offerings = _fruit_offerings()
	t.fruits.set_enabled(SERVER, ME, true, packs)
	t.fruits.note_view(SERVER, ME, _fruit_part(balance, gift))
	return t

func _run() -> void:
	await _gates()
	await _cards()
	await _buying()
	await _gift()
	for size: Vector2 in [Vector2(1600, 738), Vector2(1600, 720), Vector2(1280, 720)]: await _layout(size)
	await _cancelled_and_failed()
	await _claim_waits()
	await _resume_flush_first()
	await _second_purchase_while_trying()
	await _other_bundle_credited_first()
	await _refund()
	await _offline_store()
	await _first_tap_waits()
	await _claims_service()
	await _iphone()
	_cover()
	await _suggested_and_routes()
	await _previous_purchases()
	await _fruits_tab()
	await _fruit_packs_off()
	await _fruit_purchase()
	await _fruit_purchases_list()
	await _fruit_offline()
	await _short_card_buys()
	await _short_card_outcomes()
	await _short_card_iphone()
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU POLLEN STORE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _gates() -> void:
	for row: Array in [[false, true, true, "the server has bundles off"], [true, false, true, "the Test Store build"], [true, false, false, "iPhone, selling nothing"]]:
		var t := _setup(row[0], row[1], row[2])
		_check(not t.flow.available(), "No store: " + row[3])
		t.flow.show_store()
		await _frames(2)
		_check(t.host.overlay.get_child_count() == 0 and t.purchases.serial == 0 and t.fake.sent.is_empty(), "Opening it then shows and asks nothing: " + row[3])
		t.host.queue_free()
	var shop_off := _setup()
	shop_off.store.set_enabled(SERVER, ME, true, false, true)
	_check(not shop_off.flow.available() and not shop_off.store.bundles(SERVER, ME), "Bundles never sell without the shop")
	shop_off.host.queue_free()
	await _frames(2)

func _cards() -> void:
	var t := _setup()
	t.flow.show_store("home")
	_check(t.host.opened.back() == "home", "Opened from Home's chip, the back history hears it opened over Home")
	t.flow.show_store()
	_check(t.host.opened.back() == "wardrobe", "and over the Wardrobe by default")
	_check(t.host.mode == Flow.MODE_POLLEN_STORE and t.flow.is_open() and PlayerCopy.POLLEN_STORE_LOADING in _texts(t.host.overlay), "The store opens and says it is loading")
	await _frames()
	var page: Node = t.host.overlay
	var words := _texts(page)
	for id: String in Bundles.ORDER:
		_check(page.find_child("PollenStoreBundle_" + id, true, false) != null and page.find_child("PollenStoreBuy_" + id, true, false) != null, "The %s card and its price button show" % id)
	_check("$0.99" in words and "$3.99" in words and "$7.99" in words and "$19.99" in words, "Each price is the store's own: " + str(words))
	_check(not "after_you_full_journey_monthly" in str(t.flow.purchase.packages) and t.flow.purchase.packages.size() == 4, "Only the Pollen offering's packages are read")
	_check(PlayerCopy.POLLEN_STORE_NO_BONUS in words and PlayerCopy.STORE_CARD_BONUS % ["1,000", 5] in words and PlayerCopy.STORE_CARD_BONUS % ["4,000", 10] in words, "Bonus lines in plain Pollen and percent: " + str(words))
	# Board 9: only the bundle with the most Pollen for the money says its per $1, under its ribbon.
	_check(PlayerCopy.STORE_CARD_BONUS % ["15,000", 15] + PlayerCopy.STORE_CARD_PER_DOLLAR % "5,753" in words and PlayerCopy.POLLEN_STORE_MOST in words, "The Wheelbarrow carries the ribbon and its 5,753 per $1")
	_check(not words.any(func(word: String) -> bool: return word.contains("5,051") or word.contains("5,263") or word.contains("5,507")), "No other card says its per $1")
	var ribbon: Node = page.find_child("PollenStoreRibbon", true, false)
	_check(ribbon != null and page.find_child("PollenStoreBundle_basket", true, false).is_ancestor_of(ribbon), "The ribbon sits on the Wheelbarrow card")
	var heights: Array = Bundles.ORDER.map(func(id: String) -> float: return (page.find_child("PollenStoreBundle_" + id, true, false) as Control).size.y)
	var bottoms: Array = Bundles.ORDER.map(func(id: String) -> float: return (page.find_child("PollenStoreBundle_" + id, true, false) as Control).get_global_rect().end.y)
	_check(heights[0] < heights[1] and heights[1] < heights[2] and heights[2] < heights[3] and bottoms.all(func(bottom: float) -> bool: return absf(bottom - bottoms[0]) <= 0.5), "The cards climb as a ladder, bottoms aligned: %s %s" % [heights, bottoms])
	_check(page.find_child("PollenStoreTabFrame", true, false) != null and not (page.find_child("PollenStoreTabFrame", true, false) as Control).visible, "No tabs while Fruits are off")
	_check(["5,000", "21,000", "44,000", "115,000"].all(func(amount: String) -> bool: return amount in words), "Each total with its grain")
	_check(page.find_children("BundleArt", "", true, false).size() == 4, "Each card has its art")
	_check(page.find_child("PollenStoreGift", true, false) == null, "No first bundle card while that gift is off")
	_check("9,000" in _texts(page.find_child("PollenStoreBalance", true, false)) and PlayerCopy.POLLEN_STORE_YOU_HAVE in words, "The chip says You have 9,000")
	_check(PlayerCopy.POLLEN_STORE_EARN in words and PlayerCopy.POLLEN_PURCHASES_TITLE in words and PlayerCopy.POLLEN_STORE_FOOT in words and not words.any(func(word: String) -> bool: return word.contains("Settings")),
		"Earn Pollen free by playing, Previous purchases, and the footnote, which no longer points to Settings")
	var toasts: int = t.host.toasts.size()
	(page.find_child("PollenStoreEarn", true, false) as Button).pressed.emit()
	_check(t.host.earning_opened == 1 and t.host.toasts.size() == toasts, "Earn Pollen free by playing opens Pollen from play on the first tap")
	t.host.earning_opens = false
	(page.find_child("PollenStoreEarn", true, false) as Button).pressed.emit()
	_check(t.host.earning_opened == 2 and t.host.toasts.size() == toasts + 1 and t.host.toasts.back() == PlayerCopy.POLLEN_PLAY_OFFLINE, "A Pollen from play that cannot open says so")
	var back := {"asked": false}
	t.flow.back_requested.connect(func() -> void: back.asked = true)
	(page.find_child("PollenStoreBack", true, false) as Button).pressed.emit()
	_check(back.asked, "Back asks the host to leave")
	t.host.queue_free()
	await _frames(2)

func _buying() -> void:
	var t := _setup()
	t.flow.show_store()
	await _frames()
	t.flow.confirm("pouch")
	var sheet: Node = t.host.ui.find_child("PollenStoreConfirm", true, false)
	var words := _texts(sheet)
	_check(sheet != null and PlayerCopy.POLLEN_STORE_CONFIRM_TITLE % "Pouch" in words and PlayerCopy.POLLEN_STORE_LINE_BONUS % ["Pouch", "1,000"] in words, "Buy a Pouch? with the Pouch and its bonus")
	_check("21,000" in words and PlayerCopy.POLLEN_STORE_YOU_GET in words and "9,000  →  " in words and "30,000" in words and "$3.99" in words and not words.any(func(word: String) -> bool: return word.begins_with(PlayerCopy.POLLEN_STORE_GIFT.get_slice("(", 0))), "Plain sums: you get 21,000, 9,000 to 30,000, you pay $3.99, no gift: " + str(words))
	_check(t.purchases.bought.is_empty() and t.fake.sent.is_empty(), "Nothing is bought until its Buy")
	t.fake.replies = [_credited("pouch", 0, 30000)]
	(sheet.find_child("PollenStoreConfirmBuy", true, false) as Button).pressed.emit()
	await _frames(10)
	_check(t.purchases.bought == [["pollen", "pouch_package"]], "Its Buy hands the Pouch's package to the store")
	_check(t.fake.sent.size() == 1 and t.fake.sent[0].path == BundleClaims.CLAIM_PATH and t.fake.sent[0].body == {"schema_version": 1}, "Then the server is asked to claim it, and the phone says nothing about what was bought")
	var receipt: Node = t.host.ui.find_child("PollenStoreReceipt", true, false)
	var lines := _texts(receipt)
	_check(receipt != null and PlayerCopy.POLLEN_STORE_ADDED % "21,000" in lines and PlayerCopy.POLLEN_STORE_THANKS in lines, "The receipt: 21,000 Pollen added: " + str(lines))
	_check("9,000  →  " in lines and "30,000" in lines and PlayerCopy.POLLEN_STORE_ORDER % ["$3.99", "GPA.1234-5678-9012-34567"] in lines, "The balance before and after, the price and the order number")
	_check(t.wallet.wallet(SERVER, ME).balance == 30000 and not t.claims.pending() and t.claims.unseen().is_empty(), "The balance follows the server; nothing waits and the receipt counts as seen")
	var opened := {"count": 0}
	t.flow.wardrobe_requested.connect(func() -> void: opened.count += 1)
	(receipt.find_child("PollenStoreOpenWardrobe", true, false) as Button).pressed.emit()
	await _frames(2)
	_check(opened.count == 1 and t.host.ui.find_child("PollenStoreReceipt", true, false) == null, "Open the Wardrobe closes the receipt and asks for the Wardrobe")
	t.host.queue_free()
	await _frames(2)

## The first bundle gift, while it is on and unused, at the owner's 20%.
func _gift() -> void:
	var t := _setup()
	t.store.note_view(SERVER, ME, _view(true, 20))
	t.flow.show_store()
	await _frames()
	var gift: Control = t.host.overlay.find_child("PollenStoreGift", true, false)
	var gift_words := _texts(gift)
	_check(gift != null and gift_words == [PlayerCopy.POLLEN_STORE_FIRST % 20, PlayerCopy.POLLEN_STORE_FIRST_AS % "Pouch", PlayerCopy.STORE_FIRST_SUM % ["21,000", "4,200"]] and gift.find_child("BundleArt", true, false).bundle == "pouch_pair",
		"The first bundle card while the gift is on: its percent, the Pouch pair and 21,000 + 4,200, nothing more: " + str(gift_words))
	var page_words := " | ".join(_texts(t.host.overlay))
	for line: String in [PlayerCopy.POLLEN_STORE_CARD_NO_BONUS_FIRST % "6,000", PlayerCopy.POLLEN_STORE_CARD_FIRST % "25,200", PlayerCopy.POLLEN_STORE_CARD_FIRST % "52,800", PlayerCopy.POLLEN_STORE_CARD_FIRST % "138,000"]:
		var cut := line.rfind(" ")
		_check(page_words.contains(line.left(cut) + " | " + line.substr(cut + 1)), "Each card says what it adds as a first bundle, its amount in bold: %s in %s" % [line, page_words])
	t.flow.confirm("pouch")
	var words := _texts(t.host.ui.find_child("PollenStoreConfirm", true, false))
	_check(PlayerCopy.POLLEN_STORE_GIFT % 20 in words and "4,200" in words and "25,200" in words and "34,200" in words, "The confirm card adds the gift: 4,200, you get 25,200, you'll have 34,200: " + str(words))
	t.fake.replies = [_credited("pouch", 4200, 34200)]
	t.flow.buy("pouch")
	await _frames(10)
	var lines := _texts(t.host.ui.find_child("PollenStoreReceipt", true, false))
	_check(PlayerCopy.POLLEN_STORE_ADDED % "25,200" in lines and PlayerCopy.POLLEN_STORE_GIFT % 20 in lines and "34,200" in lines, "The receipt: 25,200 Pollen added with the gift row: " + str(lines))
	t.store.note_view(SERVER, ME, _view(false, 20))
	t.flow._redraw()
	await _frames(2)
	_check(t.host.overlay.find_child("PollenStoreGift", true, false) == null and not _texts(t.host.overlay).any(func(word: String) -> bool: return word.begins_with("First bundle")), "Once used, the card and the first bundle amounts go")
	t.host.queue_free()
	await _frames(2)

## A cancelled sheet claims nothing and drops its mark; a failed one claims nothing now but keeps its
## mark (a payment may settle later); a sheet the app never heard back from (closed) keeps it too.
## The page at `size` with the first bundle line on: the header holds only the
## back square, the title and the chip, every part sits below the one before it,
## and the footer ends inside the page.
func _layout(size: Vector2) -> void:
	var t := _setup()
	for layer: Control in [t.host.overlay, t.host.ui]: layer.size = size
	t.store.note_view(SERVER, ME, _view(true, 20))
	t.flow.show_store()
	await _frames()
	var page: Control = t.host.overlay.find_child("PollenStorePage", true, false)
	var title: Control = page.find_child("PollenStoreTitle", true, false)
	var back: Control = page.find_child("PollenStoreBack", true, false)
	var header := title.get_parent() as Control
	_check(header == back.get_parent() and is_equal_approx(header.size.y, maxf(back.size.y, title.get_combined_minimum_size().y)), "The header is as tall as its back square or title, with no note under the title at %s: %s" % [size, header.size])
	_check(_texts(header).slice(0, 2) == [PlayerCopy.POLLEN_STORE_TITLE, PlayerCopy.POLLEN_STORE_YOU_HAVE], "The title is followed by You have, with no note between at %s: %s" % [size, _texts(header)])
	var gift: Control = page.find_child("PollenStoreGift", true, false)
	_check(gift != null and page.get_global_rect().encloses(gift.get_global_rect()) and gift.size.x >= gift.get_combined_minimum_size().x - 0.5 and gift.size.y >= gift.get_combined_minimum_size().y - 0.5, "The first bundle card fits the page at %s" % size)
	var cards: Array[Control] = [gift]
	for id: String in Bundles.ORDER: cards.append(page.find_child("PollenStoreBundle_" + id, true, false))
	var apart := true
	for index in range(1, cards.size()): apart = apart and cards[index].get_global_rect().position.x >= cards[index - 1].get_global_rect().end.x - 0.5
	_check(apart, "The first bundle card and the four cards sit side by side without overlap at %s" % size)
	for card: Control in cards:
		for label: Label in card.find_children("*", "Label", true, false):
			if label.is_visible_in_tree(): _check(card.get_global_rect().grow(0.5).encloses(label.get_global_rect()), "%s keeps '%s' inside it at %s" % [card.name, label.text, size])
	var parts: Array[Control] = [header, page.find_child("PollenStoreBundles", true, false), (page.find_child("PollenStoreEarn", true, false) as Control).get_parent()]
	var ordered := true
	for index in range(1, parts.size()): ordered = ordered and parts[index].get_global_rect().position.y >= parts[index - 1].get_global_rect().end.y - 0.5
	_check(ordered and parts.back().get_global_rect().end.y <= page.get_global_rect().end.y + 0.5, "Header, first bundle line, cards and footer sit in order inside the page at %s" % size)
	for id: String in Bundles.ORDER:
		var card: Control = page.find_child("PollenStoreBundle_" + id, true, false)
		_check(page.get_global_rect().encloses(card.get_global_rect()), "The %s card fits the page at %s" % [id, size])
	t.host.queue_free()
	await _frames(2)

func _cancelled_and_failed() -> void:
	for outcome: String in ["cancel", "fail", "silent"]:
		var t := _setup()
		t.purchases.outcome = outcome
		t.flow.show_store()
		await _frames()
		t.flow.buy("jar")
		await _frames(6)
		_check(t.purchases.bought.size() == 1 and t.fake.sent.is_empty(), "A %s purchase claims nothing at once" % outcome)
		_check(t.claims.pending() == (outcome != "cancel"), "%s: the waiting mark %s" % [outcome, "goes" if outcome == "cancel" else "stays, so the next flush claims it"])
		_check(t.host.ui.find_child("PollenStoreReceipt", true, false) == null and t.host.toasts.size() == (0 if outcome == "silent" else 1), "%s: no receipt, at most one line for the player" % outcome)
		_check(t.wallet.wallet(SERVER, ME).balance == 9000, "%s: the balance is unchanged" % outcome)
		if outcome != "cancel":
			t.fake.replies = [_credited("jar", 0, 53000)]
			await t.claims.flush()
			_check(t.wallet.wallet(SERVER, ME).balance == 53000 and not t.claims.pending() and t.claims.unseen().size() == 1, "%s: the next flush claims it and keeps its receipt" % outcome)
		t.host.queue_free()
		await _frames(2)

## A claim with no answer stays waiting; the next flush credits it and its receipt shows on the next visit.
func _claim_waits() -> void:
	var t := _setup()
	t.flow.show_store()
	await _frames()
	t.flow.buy("pinch")
	await _frames(4)
	await create_timer(BundlePurchase.CLAIM_PAUSE_S * 3.0 + 0.5).timeout
	await _frames(4)
	_check(t.fake.sent.size() == BundlePurchase.CLAIM_TRIES and t.claims.pending() and PlayerCopy.POLLEN_STORE_ON_ITS_WAY in t.host.toasts, "No answer: a few tries, then it waits and the player is told it is on its way")
	var reload: RefCounted = BundleClaims.new(t.claims.path, t.store, t.wallet)
	reload.connect_to(null, t.host._names_scope, t.fake.call_it)
	_check(reload.pending(), "The waiting claim survives a restart")
	# A write cut off between its steps: a damaged file beside the whole new copy.
	var whole := FileAccess.get_file_as_string(t.claims.path)
	for pair: Array in [[t.claims.path + ".tmp", whole], [t.claims.path, whole.substr(0, whole.length() / 2)]]:
		var file := FileAccess.open(pair[0], FileAccess.WRITE)
		file.store_string(pair[1])
		file.close()
	var cut: RefCounted = BundleClaims.new(t.claims.path, t.store, t.wallet)
	cut.connect_to(null, t.host._names_scope, t.fake.call_it)
	_check(cut.pending() and AtomicFile.remove_unreadable(t.claims.path), "A damaged claims file reads its whole copy, so the waiting claim is not lost")
	DirAccess.remove_absolute(t.claims.path + ".tmp")
	t.fake.replies = [_credited("pinch", 0, 14000)]
	await t.claims.flush()
	_check(not t.claims.pending() and t.claims.unseen().size() == 1 and t.wallet.wallet(SERVER, ME).balance == 14000, "The next flush credits it and keeps its receipt for the player")
	t.flow.show_store()
	await _frames(4)
	_check(PlayerCopy.POLLEN_STORE_ADDED % "5,000" in _texts(t.host.ui.find_child("PollenStoreReceipt", true, false)) and t.claims.unseen().is_empty(), "Its receipt shows on the next visit, once")
	t.host.queue_free()
	await _frames(2)

## The app's return from the store's sheet sends the waiting claim (Main's
## flush) before the purchase's answer comes. The purchase's claim takes that
## answer instead of failing as busy, and the receipt shows either way.
func _resume_flush_first() -> void:
	for flushed_first: bool in [false, true]:
		var t := _setup()
		t.purchases.outcome = "silent"
		t.flow.show_store()
		await _frames()
		t.flow.buy("pouch")
		await _frames(2)
		var buying: String = t.flow.purchase.buying
		t.fake.delay = 1 if flushed_first else 20
		t.fake.replies = [_credited("pouch", 0, 30000), {"ok": true, "status": 200, "data": {"schema_version": 1.0, "balance": 30000.0, "pending": false, "refunded": [], "credited": []}}]
		if flushed_first: await t.claims.flush()
		else:
			t.claims.flush()
			await _frames(2)
		t.purchases.completed.emit(buying, "purchase_package", {"schema_version": 1})
		await create_timer(BundlePurchase.CLAIM_PAUSE_S * 3.0 + 0.5).timeout
		await _frames(4)
		var lines := _texts(t.host.ui.find_child("PollenStoreReceipt", true, false))
		var case := "flushed first" if flushed_first else "flush still sending"
		_check(PlayerCopy.POLLEN_STORE_ADDED % "21,000" in lines and not PlayerCopy.POLLEN_STORE_ON_ITS_WAY in t.host.toasts, "%s: the receipt shows, not 'on its way': %s %s" % [case, lines, t.host.toasts])
		_check(t.fake.sent.size() == (2 if flushed_first else 1), "%s: the purchase's claim asks no more than it needs: %d" % [case, t.fake.sent.size()])
		t.host.queue_free()
		await _frames(2)

## A second bundle bought while the first purchase's claim still pauses between
## tries: each purchase keeps its own snapshot and price. The first, credited by
## a flush during the pause, shows its receipt (never "on its way"); the second
## shows its own receipt with its own price, or, when the first one's receipt
## already showed it, says nothing wrong.
func _second_purchase_while_trying() -> void:
	var nothing_new := func(balance: int) -> Dictionary: return {"ok": true, "status": 200, "data": {"schema_version": 1.0, "balance": float(balance), "pending": false, "refunded": [], "credited": []}}
	for both_at_once: bool in [false, true]:
		var case := "the first claim credits both" if both_at_once else "each claim credits its own"
		var t := _setup()
		t.purchases.outcome = "silent"
		t.flow.show_store()
		await _frames()
		t.flow.buy("pouch")
		await _frames(2)
		var first: String = t.flow.purchase.buying
		t.fake.replies = [nothing_new.call(9000)]
		t.purchases.completed.emit(first, "purchase_package", {"schema_version": 1})
		await _frames(4)
		_check(t.fake.sent.size() == 1 and t.claims.unseen().is_empty(), "%s: the first claim found nothing yet and pauses" % case)
		# The app's return from the store's sheet credits the first purchase during the pause.
		t.fake.replies = [_credited("pouch", 0, 30000)]
		await t.claims.flush()
		t.flow.buy("jar")
		await _frames(2)
		var second: String = t.flow.purchase.buying
		_check(second != first and not second.is_empty(), "%s: the second bundle's sheet opens while the first still tries" % case)
		var jar := _credited("jar", 0, 74000, "GPA.1234-5678-9012-34568")
		t.fake.replies = [jar if both_at_once else nothing_new.call(30000)]
		await create_timer(BundlePurchase.CLAIM_PAUSE_S + 0.5).timeout
		await _frames(4)
		var lines := _texts(t.host.ui.find_child("PollenStoreReceipt", true, false))
		if both_at_once: _check(PlayerCopy.POLLEN_STORE_ADDED % "44,000" in lines, "%s: the first purchase's claim shows the newest receipt: %s" % [case, lines])
		else: _check(PlayerCopy.POLLEN_STORE_ADDED % "21,000" in lines and PlayerCopy.POLLEN_STORE_ORDER % ["$3.99", "GPA.1234-5678-9012-34567"] in lines, "%s: the first purchase shows its receipt and its own price: %s" % [case, lines])
		_check(not PlayerCopy.POLLEN_STORE_ON_ITS_WAY in t.host.toasts, "%s: the first purchase never says 'on its way' once credited: %s" % [case, t.host.toasts])
		t.fake.replies = [nothing_new.call(74000) if both_at_once else jar]
		t.purchases.completed.emit(second, "purchase_package", {"schema_version": 1})
		await create_timer(BundlePurchase.CLAIM_PAUSE_S * 3.0 + 0.5).timeout
		await _frames(4)
		# The first receipt was still freeing as this one opened, so this one is found by its sheet, not its name.
		lines = _texts(t.flow._sheet.get_ref() if t.flow._sheet != null else null)
		if not both_at_once: _check(PlayerCopy.POLLEN_STORE_ADDED % "44,000" in lines and PlayerCopy.POLLEN_STORE_ORDER % ["$7.99", "GPA.1234-5678-9012-34568"] in lines, "%s: the second purchase shows its own receipt and price: %s" % [case, lines])
		_check(not PlayerCopy.POLLEN_STORE_ON_ITS_WAY in t.host.toasts, "%s: neither purchase says 'on its way' once credited: %s" % [case, t.host.toasts])
		_check(t.wallet.wallet(SERVER, ME).balance == 74000 and t.claims.unseen().is_empty(), "%s: both are credited and seen" % case)
		t.host.queue_free()
		await _frames(2)

## The second bundle's claim is credited while the first purchase is still not
## listed: that receipt is the second purchase's, so the first keeps trying and
## then says it is on its way.
func _other_bundle_credited_first() -> void:
	var t := _setup()
	t.purchases.outcome = "silent"
	t.flow.show_store()
	await _frames()
	t.flow.buy("pouch")
	await _frames(2)
	var first: String = t.flow.purchase.buying
	t.fake.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "balance": 9000.0, "pending": false, "refunded": [], "credited": []}}]
	t.purchases.completed.emit(first, "purchase_package", {"schema_version": 1})
	await _frames(4)
	t.flow.buy("jar")
	await _frames(2)
	t.fake.replies = [_credited("jar", 0, 53000, "GPA.1234-5678-9012-34568")]
	t.purchases.completed.emit(t.flow.purchase.buying, "purchase_package", {"schema_version": 1})
	await _frames(4)
	var lines := _texts(t.flow._sheet.get_ref() if t.flow._sheet != null else null)
	_check(PlayerCopy.POLLEN_STORE_ADDED % "44,000" in lines and PlayerCopy.POLLEN_STORE_ORDER % ["$7.99", "GPA.1234-5678-9012-34568"] in lines, "The second purchase shows its own receipt and price: %s" % [lines])
	await create_timer(BundlePurchase.CLAIM_PAUSE_S * 3.0 + 0.5).timeout
	await _frames(4)
	_check(PlayerCopy.POLLEN_STORE_ON_ITS_WAY in t.host.toasts and t.claims.pending(), "The first purchase, never listed, keeps waiting and says it is on its way: %s" % [t.host.toasts])
	t.host.queue_free()
	await _frames(2)

func _refund() -> void:
	var t := _setup()
	t.fake.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "balance": -2100.0, "pending": false, "credited": [], "refunded": [{"bundle": "pouch", "amount": -23100.0, "order": "GPA.1"}]}}]
	var answer: Dictionary = await t.claims.claim()
	_check(answer.ok and answer.refunded.size() == 1 and t.wallet.wallet(SERVER, ME).balance == -2100, "A refund the server took back shows in the balance, below zero")
	t.flow.show_store()
	await _frames()
	_check("-2,100" in _texts(t.host.overlay.find_child("PollenStoreBalance", true, false)), "The chip shows the balance as it is")
	t.host.queue_free()
	await _frames(2)

func _offline_store() -> void:
	var t := _setup()
	t.purchases.offerings_fail = true
	t.flow.show_store()
	await _frames()
	var page: Node = t.host.overlay
	_check(PlayerCopy.POLLEN_STORE_OFFLINE in _texts(page) and (page.find_child("PollenStoreRetry", true, false) as Control).visible and page.find_child("PollenStoreBuy_pinch", true, false) == null, "Offline: the store says so, offers Try again and shows no price")
	t.flow.confirm("pinch")
	_check(t.host.ui.find_child("PollenStoreConfirm", true, false) == null, "Offline: nothing can be bought")
	t.purchases.offerings_fail = false
	(page.find_child("PollenStoreRetry", true, false) as Button).pressed.emit()
	await _frames()
	_check(page.find_child("PollenStoreBuy_pinch", true, false) != null and not PlayerCopy.POLLEN_STORE_OFFLINE in _texts(page), "Try again reads the prices")
	var not_ready := _setup()
	not_ready.flow.store_ready = func() -> bool: return false
	not_ready.flow.show_store()
	await _frames()
	_check(PlayerCopy.POLLEN_STORE_OFFLINE in _texts(not_ready.host.overlay) and not_ready.purchases.serial == 0, "A store that could not be set up asks for no prices")
	t.host.queue_free()
	not_ready.host.queue_free()
	await _frames(2)

## A price tapped while a claim is still out waits for it, then opens the card: the first tap registers.
func _first_tap_waits() -> void:
	var t := _setup()
	t.flow.show_store()
	await _frames()
	t.fake.delay = 14
	t.fake.replies = [_credited("pinch", 0, 14000)]
	t.claims.claim()
	await process_frame
	_check(t.claims.sending(), "A claim is out")
	t.flow.tap_bundle("jar")
	await _frames(3)
	_check(t.host.ui.find_child("PollenStoreConfirm", true, false) == null, "The tap waits while the claim is out")
	await _frames(20)
	_check(t.host.ui.find_child("PollenStoreConfirm", true, false) != null, "Then the confirm card opens, without a second tap")
	t.host.queue_free()
	await _frames(2)

func _claims_service() -> void:
	for bad: Dictionary in [{"bundle": "nope", "pollen": 1, "first_gift": 0, "order": "", "purchased_at": 1, "usd_cents": 1}, {"bundle": "pinch", "pollen": -1, "first_gift": 0, "order": "", "purchased_at": 1, "usd_cents": 1},
			{"bundle": "pinch", "pollen": 5000, "first_gift": 0, "order": "<b>", "purchased_at": 1, "usd_cents": 99}]:
		var kept := BundleClaims.checked_answer({"schema_version": 1, "balance": 5, "credited": [bad], "refunded": []})
		_check(kept.get("balance") == 5 and (kept.get("credited", [1]) as Array).is_empty(), "A receipt that fails its check is left out and the balance still counts: " + str(bad))
	_check(BundleClaims.checked_answer({"schema_version": 1, "balance": 5, "credited": [{"bundle": "pinch", "pollen": 5000, "first_gift": 0, "order": "GPA." + "1".repeat(120), "purchased_at": 1, "usd_cents": 99}], "refunded": []}).credited.size() == 1, "A long order number the server allows is kept")
	_check(BundleClaims.checked_answer({"schema_version": 2, "balance": 5, "credited": [], "refunded": []}).is_empty() and BundleClaims.checked_answer({"schema_version": 1, "balance": 1.5, "credited": [], "refunded": []}).is_empty(), "A wrong version or a broken balance fails it")
	_check(not BundleClaims.checked_answer({"schema_version": 1, "balance": -5, "credited": [], "refunded": []}).is_empty(), "A balance below zero is a real answer")
	var t := _setup()
	t.fake.replies = [{"ok": false, "status": 503, "code": "pollen_bundles_disabled"}]
	await t.claims.claim()
	_check(t.claims.pending(), "A server pause keeps the claim waiting")
	t.fake.replies = [{"ok": false, "status": 401, "code": "invalid_auth"}]
	await t.claims.flush()
	_check(t.claims.pending(), "A changed device keeps it waiting")
	t.fake.replies = [{"ok": false, "status": 400, "code": "invalid_pollen_bundle_claim"}]
	await t.claims.flush()
	_check(not t.claims.pending(), "A refusal of the claim itself stops it")
	await t.claims.claim()
	for i in range(BundleClaims.MAX_EMPTY + 1):
		t.fake.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "balance": 9000.0, "pending": false, "credited": [], "refunded": []}}]
		await t.claims.flush()
	_check(not t.claims.pending() and t.fake.sent.size() <= 4 + BundleClaims.MAX_EMPTY, "A purchase that never lands stops being asked about after a while")
	t.host.scope = {}
	_check(t.claims.scope().is_empty() and not t.claims.pending(), "Signed out: no claim")
	t.host.queue_free()
	await _frames(2)

## Every visible word under `node`.
## iPhone: the App Store's bundles at its prices, Apple's wording and receipt line,
## and money only on this run's answer from the server.
func _iphone() -> void:
	PlatformSupport.override_platform = PlatformSupport.IOS
	var support: RefCounted = StoreSupport.new(_path("store-support"))
	StoreSupport.use_shared(support)
	var t := _setup(true, true, true, true)
	support.scope_source = t.host._names_scope
	t.host.support = support
	t.host.store = t.store
	t.purchases.offerings = _ios_offerings()
	_check(Bundles.store() == Bundles.APP_STORE and Bundles.usd_cents("pinch") == 149 and Bundles.product("jar") == "after_you_pollen_jar_ios", "An iPhone buys from the App Store's products and prices")
	t.flow.show_store()
	await _frames()
	var words := _texts(t.host.overlay)
	_check(t.host.reads == 1, "The store asks the server once this run before it prices anything")
	_check("$1.49" in words and "$4.99" in words and "$8.99" in words and "$21.99" in words and t.flow.purchase.packages.size() == 4, "Each price is the App Store's own: " + str(words))
	_check(PlayerCopy.STORE_CARD_BONUS % ["15,000", 15] + PlayerCopy.STORE_CARD_PER_DOLLAR % "5,230" in words, "Pollen per $1 at the App Store's prices on the Wheelbarrow: %s" % [words])
	_check(PlayerCopy.POLLEN_STORE_FOOT_IOS in words and not PlayerCopy.POLLEN_STORE_FOOT in words, "The footnote names the App Store")
	t.flow.confirm("pouch")
	var sheet: Node = t.host.ui.find_child("PollenStoreConfirm", true, false)
	_check(sheet != null and PlayerCopy.POLLEN_STORE_CONFIRM_NOTE_IOS in _texts(sheet) and "$4.99" in _texts(sheet), "The confirm card says Apple charges it, at the App Store's price")
	t.fake.replies = [_credited("pouch", 0, 30000, "2000000000000310", Bundles.APP_STORE)]
	(sheet.find_child("PollenStoreConfirmBuy", true, false) as Button).pressed.emit()
	await _frames(10)
	_check(t.purchases.bought == [["pollen", "pouch"]], "Its Buy hands the App Store's Pouch package to the store")
	var receipt: Node = t.host.ui.find_child("PollenStoreReceipt", true, false)
	_check(receipt != null and PlayerCopy.POLLEN_STORE_APP_STORE_ORDER % ["$4.99", "2000000000000310"] in _texts(receipt), "The receipt names the App Store transaction: " + str(_texts(receipt) if receipt != null else []))
	_check(t.claims.unseen().is_empty() and not t.claims.pending(), "Nothing waits after the claim")
	t.host.queue_free()
	await _frames(2)
	# A server that sells no App Store bundles: the store prices nothing and opens no sheet.
	support = StoreSupport.new(_path("store-support-off"))
	StoreSupport.use_shared(support)
	var off := _setup(true, true, true, true)
	support.scope_source = off.host._names_scope
	off.host.support = support
	off.host.store = off.store
	off.host.answer = "off"
	off.purchases.offerings = _ios_offerings()
	off.flow.show_store()
	await _frames()
	_check(off.host.reads == 1 and off.purchases.serial == 0 and off.flow.purchase.packages.is_empty() and not off.flow.available(), "No App Store bundles on the server: nothing priced, nothing to buy")
	off.host.queue_free()
	await _frames(2)
	# No answer this run (the read failed): the store prices nothing, and Buy opens no sheet even with a package in hand.
	support = StoreSupport.new(_path("store-support-fail"))
	StoreSupport.use_shared(support)
	var failed := _setup(true, true, true, true)
	support.scope_source = failed.host._names_scope
	failed.host.support = support
	failed.host.store = failed.store
	failed.host.answer = "fail"
	failed.purchases.offerings = _ios_offerings()
	failed.flow.show_store()
	await _frames()
	_check(failed.host.reads == 1 and failed.purchases.serial == 0 and failed.flow.purchase.packages.is_empty() and PlayerCopy.POLLEN_STORE_OFFLINE in _texts(failed.host.overlay), "Without this run's answer the store prices nothing and says it isn't reachable")
	failed.flow.purchase.packages = Bundles.packages(_ios_offerings())
	failed.flow.buy("pinch")
	await _frames(4)
	_check(failed.purchases.bought.is_empty() and failed.host.toasts.has(PlayerCopy.POLLEN_STORE_OFFLINE) and not failed.claims.pending(), "and Buy opens no sheet and sets no claim mark")
	failed.host.queue_free()
	await _frames(2)
	StoreSupport.use_shared(null)
	PlatformSupport.override_platform = ""

## The bundle a short card suggests: the smallest that covers the gap, the first
## bundle gift counted only while it is on, else the largest.
func _cover() -> void:
	var gift := {"first_gift": true, "first_gift_percent": 20}
	_check(Bundles.cover(80000 - 1200) == "basket", "An 80,000 item with 1,200 Pollen points to the Basket")
	_check(Bundles.cover(1) == "pinch" and Bundles.cover(5000) == "pinch" and Bundles.cover(5001) == "pouch" and Bundles.cover(44000) == "jar", "The smallest bundle whose Pollen covers the gap, bonus included")
	_check(Bundles.cover(50000) == "basket" and Bundles.cover(50000, gift) == "jar" and Bundles.adds("jar", gift) == 52800, "The first bundle gift counts while it is on: %s" % Bundles.adds("jar", gift))
	_check(Bundles.cover(50000, {"first_gift": false, "first_gift_percent": 20}) == "basket", "A used gift counts for nothing")
	_check(Bundles.cover(500000) == "basket", "A gap no bundle covers points to the largest")

## The store's chip has no plus and its balance and Earn open the Pollen page
## (Main's back history goes back to it when the Pollen page opened the store).
func _suggested_and_routes() -> void:
	var t := _setup()
	t.flow.show_store("wardrobe")
	await _frames()
	var page: Node = t.host.overlay
	var chip: Control = page.find_child("PollenChip", true, false)
	_check(chip != null and chip.plus_button == null, "The store's own chip has no plus")
	chip.amount_pressed.emit()
	_check(t.host.earning_opened == 1, "Its balance opens the Pollen page")
	t.flow.show_store("pollen")
	await _frames()
	var back := {"count": 0}
	t.flow.back_requested.connect(func() -> void: back.count += 1)
	(page.find_child("PollenChip", true, false) as Control).amount_pressed.emit()
	(page.find_child("PollenStoreEarn", true, false) as Button).pressed.emit()
	_check(back.count == 0 and t.host.earning_opened == 3, "Opened from the Pollen page, its balance and Earn open it through the same route, never Back")
	t.flow.show_store("home")
	var kept_tab: String = t.flow.tab
	t.flow.reopen()
	_check(t.host.opened.back() == "" and t.flow.tab == kept_tab, "Opening again keeps its tab and tells the back history it came back")
	t.host.queue_free()
	await _frames(2)

## Previous purchases: the receipts list, read once per opening, money only while
## the store sells in US dollars, offline said plainly, and a newer read wins.
func _previous_purchases() -> void:
	var t := _setup()
	var history := FakeHistory.new()
	history.tree = self
	history.answer = PollenHistory.checked({"schema_version": 1.0, "entries": [], "first_clears": [], "spent_usd_cents": 1999.0, "purchases": [
		{"kind": "bundle", "amount": 115000.0, "at": 1.80e12, "bundle": "basket", "order": "GPA.2222-3333-4444-55555", "usd_cents": 1999.0}]})
	t.host.pollen_client = history
	StoreCurrency.use_path(_path("currency"))
	StoreCurrency.note(_offerings())
	t.flow.show_store()
	await _frames()
	var button := t.host.overlay.find_child("PollenStorePurchases", true, false) as Button
	_check(button != null and button.is_visible_in_tree(), "Previous purchases shows on the store")
	button.pressed.emit()
	var sheet: Node = t.host.ui.find_child("PollenPurchases", true, false)
	_check(sheet != null and PlayerCopy.POLLEN_PLAY_LOADING in _texts(sheet) and history.reads == 1, "It opens the receipts list at once, loading, from one read")
	await _frames()
	var words := _texts(sheet)
	_check(PlayerCopy.POLLEN_PURCHASES_TITLE in words and "Wheelbarrow" in words and PlayerCopy.POLLEN_STORE_ORDER % ["$19.99", "GPA.2222-3333-4444-55555"] in words and sheet.find_children("PollenPurchaseRow*", "", true, false).size() == 1,
		"Each bundle with its receipt line: " + str(words))
	_check(not words.any(func(word: String) -> bool: return word.contains("total")), "No total")
	sheet.close()
	await _frames(2)
	StoreCurrency.note({"schema_version": 1, "offerings": [{"id": "pollen", "packages": [{"id": "p", "product_id": Bundles.product("pinch", Bundles.PLAY_STORE), "price": "£0.99", "price_micros": 990000.0, "currency": "GBP"}]}]})
	button.pressed.emit()
	await _frames()
	sheet = t.host.ui.find_child("PollenPurchases", true, false)
	words = _texts(sheet)
	_check(history.reads == 2 and not words.any(func(word: String) -> bool: return word.contains("$")) and PlayerCopy.POLLEN_STORE_ORDER_ONLY % "GPA.2222-3333-4444-55555" in words, "In pounds: the order and no money: " + str(words))
	history.answer = {}
	button.pressed.emit()
	await _frames()
	# A second tap closes the open list and opens a fresh one.
	var open: Array = t.host.ui.get_children().filter(func(node: Node) -> bool: return node.find_child("PollenPurchasesList", true, false) != null and not node.is_queued_for_deletion())
	_check(open.size() == 1, "One receipts list at a time: %d" % open.size())
	if open.is_empty(): return
	sheet = open.back()
	_check(PlayerCopy.POLLEN_PURCHASES_OFFLINE in _texts(sheet) and sheet.find_child("PollenPurchasesNone", true, false) == null, "Offline: it says so and guesses nothing")
	history.answer = PollenHistory.checked({"schema_version": 1.0, "entries": [], "purchases": []})
	(sheet.find_child("PollenPurchasesRetry", true, false) as Button).pressed.emit()
	await _frames()
	_check(history.reads == 4 and sheet.find_child("PollenPurchasesNone", true, false) != null, "Its Try again reads again in the same list")
	StoreCurrency.use_path(StoreCurrency.PATH)
	t.host.queue_free()
	await _frames(2)

static func _texts(node: Node) -> Array:
	var out: Array = []
	if node == null: return out
	if node is CanvasItem and not (node as CanvasItem).visible: return out
	if (node is Label or node is Button) and not str(node.text).is_empty(): out.append(node.text)
	for child: Node in node.get_children(): out.append_array(_texts(child))
	return out

## A Wardrobe on the store test's host, its page open on Daisy (1,000) with
## `balance`; the short card's buyer is this store's purchase engine.
func _wardrobe_on(t: Dictionary, balance: int) -> Node:
	Catalog.set_offered(["daisy"])
	t.host.pollen_store_flow = t.flow
	var view := _view(false, 0, balance)
	t.store.note_view(SERVER, ME, view)
	t.wallet.note_wallet(SERVER, ME, view)
	var flow: Node = WardrobeFlow.new(t.host)
	t.host.add_child(flow)
	flow.client = WardrobeClient.new(null, t.host._names_scope, t.fake.call_it, t.store, t.wallet)
	flow.surfaces = PollenSurfaces.new(true, true)
	t.fake.replies = [{"ok": true, "status": 200, "data": view}]
	flow.show_wardrobe()
	await _frames()
	t.fake.sent.clear()
	flow.select("daisy")
	await flow.act("daisy")
	return flow

## The button's words (its content label).
static func _buy_words(button: Node) -> Array:
	return _texts(button) if button != null else []

func _short_card_buys() -> void:
	var t := _setup()
	t.purchases.offerings_silent = true
	var flow := await _wardrobe_on(t, 500)
	var card: Node = t.host.ui.find_child("WardrobeShort", true, false)
	var words := _texts(card)
	_check(card != null and not words.has("It stays in the shop.") and PlayerCopy.WARDROBE_SHORT_EARN in words and PlayerCopy.WARDROBE_SHORT_BUNDLE % "Pinch" in words, "The short card says no more that it stays in the shop, and names the Pinch: " + str(words))
	var button: Button = card.find_child("WardrobeShortBuy", true, false) if card != null else null
	_check(button != null and card.find_child("WardrobeGetPollen", true, false) == null, "Get Pollen gives way to the bundle's own buy button")
	_check(_buy_words(button) == ["Pinch"] and t.flow.purchase.loading() and t.purchases.serial == 1, "While the store prices it, the button names the Pinch and one price read is out: " + str(_buy_words(button)))
	t.fake.replies = [_credited("pinch", 0, 5500)]
	button.pressed.emit()
	button.pressed.emit()
	await _frames(4)
	_check(t.purchases.bought.is_empty(), "A tap while the prices load waits for them")
	t.purchases.completed.emit(t.flow.purchase.request, "get_offerings", _offerings())
	await _frames(2)
	button.pressed.emit()
	await _frames(12)
	_check(t.purchases.bought == [["pollen", "pinch_package"]], "The prices came: one purchase of the Pinch for every tap: " + str(t.purchases.bought))
	var short_left: Array = t.host.ui.find_children("WardrobeShort", "", true, false).filter(func(node: Node) -> bool: return not node.is_queued_for_deletion())
	var confirm: Node = t.host.ui.find_child("WardrobeConfirm", true, false)
	var lines := _texts(confirm)
	_check(short_left.is_empty() and confirm != null and "5,500" in lines and "4,500" in lines, "Once the Pollen arrived the short card gave way to Daisy's confirm card on 5,500: " + str(lines))
	_check(t.fake.sent.size() == 1 and t.fake.sent[0].path == BundleClaims.CLAIM_PATH and t.claims.unseen().is_empty() and not t.claims.pending(), "Only the claim was sent, nothing was spent, and the receipt counts as seen")
	_check(t.host.ui.find_child("PollenStoreReceipt", true, false) == null, "No receipt card over the confirm card")
	t.host.queue_free()
	await _frames(2)
	# A price already read: the button shows it at once. A bundle that only got closer opens the short card again.
	var c := _setup()
	c.flow.purchase.load_prices()
	await _frames(2)
	await _wardrobe_on(c, 500)
	var again: Node = c.host.ui.find_child("WardrobeShort", true, false)
	var priced: Button = again.find_child("WardrobeShortBuy", true, false) if again != null else null
	_check(_buy_words(priced) == ["$0.99"] and c.purchases.serial == 1, "Prices already read: the button shows the Pinch's store price, with no second read: " + str(_buy_words(priced)))
	c.fake.replies = [_credited("pinch", 0, 900)]
	priced.pressed.emit()
	await _frames(12)
	# The new card takes a fresh name while the old one is still leaving.
	var shorts: Array = c.host.ui.get_children().filter(func(node: Node) -> bool: return node.find_child("WardrobeShortNeed", true, false) != null and not node.is_queued_for_deletion())
	_check(shorts.size() == 1 and "100" + PlayerCopy.WARDROBE_SHORT_MORE in _texts(shorts[0]) and c.host.ui.find_child("WardrobeConfirm", true, false) == null, "Still short on 900: the short card opens again with the new gap: " + str(c.host.ui.get_children().map(func(node: Node) -> Array: return _texts(node))))
	c.host.queue_free()
	await _frames(2)

func _short_card_outcomes() -> void:
	for row: Array in [["cancel", PlayerCopy.MAIN_B621C76A2638], ["fail", "The store had a problem."]]:
		var t := _setup()
		t.purchases.outcome = row[0]
		await _wardrobe_on(t, 500)
		var card: Node = t.host.ui.find_child("WardrobeShort", true, false)
		var button: Button = card.find_child("WardrobeShortBuy", true, false)
		button.pressed.emit()
		await _frames(8)
		var status: Label = card.find_child("WardrobeShortStatus", true, false)
		_check(is_instance_valid(card) and not card.is_queued_for_deletion() and status.visible and status.text == row[1] and not button.disabled, "%s: the card stays with its line, and the button can be tapped again: %s" % [row[0], status.text])
		_check(t.fake.sent.is_empty() and (row[0] != "cancel" or not t.claims.pending()), "%s: nothing is claimed; a cancel drops the mark" % row[0])
		t.host.queue_free()
		await _frames(2)
	# A card closed while its tap waits for the prices buys nothing.
	var gone := _setup()
	gone.purchases.offerings_silent = true
	await _wardrobe_on(gone, 500)
	var leaving: Node = gone.host.ui.find_child("WardrobeShort", true, false)
	(leaving.find_child("WardrobeShortBuy", true, false) as Button).pressed.emit()
	await _frames(2)
	leaving.close()
	gone.purchases.completed.emit(gone.flow.purchase.request, "get_offerings", _offerings())
	await _frames(8)
	_check(gone.purchases.bought.is_empty() and not gone.claims.pending(), "A card closed while its tap waits opens no store sheet")
	gone.host.queue_free()
	await _frames(2)
	# The claim gets no answer: the purchase stands, on its way, and the card can close.
	var w := _setup()
	await _wardrobe_on(w, 500)
	var waiting: Node = w.host.ui.find_child("WardrobeShort", true, false)
	var buy: Button = waiting.find_child("WardrobeShortBuy", true, false)
	buy.pressed.emit()
	await _frames(4)
	_check(buy.disabled and _texts(buy) == ["$0.99"], "While the purchase is out the button takes no taps")
	await create_timer(BundlePurchase.CLAIM_PAUSE_S * 3.0 + 0.5).timeout
	var line: Label = waiting.find_child("WardrobeShortStatus", true, false)
	_check(line.visible and line.text == PlayerCopy.POLLEN_STORE_ON_ITS_WAY and buy.disabled and w.claims.pending() and w.purchases.bought.size() == 1, "No answer: it says the Pollen is on its way, the claim waits, and no second purchase can start")
	var close: Button = waiting.find_child("ModalClose", true, false)
	close.pressed.emit()
	await _frames(2)
	_check(not is_instance_valid(waiting) or waiting.is_queued_for_deletion(), "and the card closes")
	w.host.queue_free()
	await _frames(2)

func _short_card_iphone() -> void:
	PlatformSupport.override_platform = PlatformSupport.IOS
	var support: RefCounted = StoreSupport.new(_path("store-support-short"))
	StoreSupport.use_shared(support)
	var t := _setup(true, true, true, true)
	support.scope_source = t.host._names_scope
	t.host.support = support
	t.host.store = t.store
	t.purchases.offerings = _ios_offerings()
	await _wardrobe_on(t, 500)
	await _frames(4)
	var card: Node = t.host.ui.find_child("WardrobeShort", true, false)
	var button: Button = card.find_child("WardrobeShortBuy", true, false)
	_check(t.host.reads == 1 and _buy_words(button) == ["$1.49"], "iPhone: the card asks the server once this run, then shows the App Store's price: " + str(_buy_words(button)))
	t.fake.replies = [_credited("pinch", 0, 5500, "2000000000000311", Bundles.APP_STORE)]
	button.pressed.emit()
	await _frames(12)
	_check(t.purchases.bought == [["pollen", "pinch"]] and t.host.ui.find_child("WardrobeConfirm", true, false) != null, "iPhone: the App Store's Pinch, then Daisy's confirm card")
	t.host.queue_free()
	await _frames(2)
	# This run's server answer turns App Store bundles off: the card keeps only the earning line.
	var off := _setup(true, true, true, true)
	support.scope_source = off.host._names_scope
	off.host.support = support
	off.host.store = off.store
	off.host.answer = "off"
	off.purchases.offerings = _ios_offerings()
	await _wardrobe_on(off, 500)
	await _frames(4)
	var shut: Node = off.host.ui.find_child("WardrobeShort", true, false)
	var bundle_box: Control = shut.find_child("WardrobeShortBundle", true, false) if shut != null else null
	_check(shut != null and bundle_box != null and not bundle_box.visible and PlayerCopy.WARDROBE_SHORT_EARN in _texts(shut) and off.purchases.bought.is_empty(), "iPhone, bundles off this run: the bundle box goes, the earning line stays: " + str(_texts(shut)))
	off.host.queue_free()
	await _frames(2)
	StoreSupport.use_shared(null)
	PlatformSupport.override_platform = ""

## The Fruits tab as board 3 draws it, from the services' numbers.
func _fruits_tab() -> void:
	var off := _setup()
	off.purchases.offerings = _fruit_offerings()
	off.flow.show_store("home", "fruits")
	await _frames()
	_check(off.flow.tab == "pollen" and not (off.host.overlay.find_child("PollenStoreTabFrame", true, false) as Control).visible and off.host.overlay.find_child("PollenStoreBundle_barrel", true, false) == null, "Fruits off: no tabs, the store opens on Pollen and lists no Fruit pack")
	off.flow.set_tab("fruits")
	var chip: Control = off.flow._page.chip
	_check(off.flow.tab == "pollen" and chip != null and chip.fruits_button == null, "Fruits off: the Fruits tab cannot be picked and the chip has no Fruit half")
	off.host.queue_free()
	var t := _fruit_setup()
	t.flow.show_store("home")
	await _frames()
	var page: Node = t.host.overlay
	_check((page.find_child("PollenStoreTabFrame", true, false) as Control).visible and t.flow.tab == "pollen", "Fruits on: both tabs show, the store opens on Pollen")
	chip = t.flow._page.chip
	_check(chip.fruits_button != null and chip.fruits_label.text == "101" and chip.plus_button == null, "The header's chip shows 101 Fruits on its plum half, with no plus")
	(page.find_child("PollenStoreTab_fruits", true, false) as Button).pressed.emit()
	await _frames()
	_check(t.flow.tab == "fruits", "A tap on Fruits shows the Fruits tab")
	var words := _texts(page)
	for id: String in Bundles.FRUIT_ORDER:
		_check(page.find_child("PollenStoreBundle_" + id, true, false) != null and page.find_child("PollenStoreBuy_" + id, true, false) != null, "The %s card and its price show" % id)
	_check(["Handful", "Bowl", "Crate", "Barrel", "$2.49", "$4.99", "$9.99", "$19.99"].all(func(word: String) -> bool: return word in words) and page.find_child("PollenStoreBundle_pinch", true, false) == null, "The Fruit packs by name at the store's prices, and no Pollen bundle: " + str(words))
	_check(PlayerCopy.FRUIT_STORE_MOST in words and page.find_child("PollenStoreBundle_barrel", true, false).is_ancestor_of(page.find_child("PollenStoreRibbon", true, false)), "The Barrel carries Most Fruits per $1")
	_check(PlayerCopy.STORE_CARD_BONUS % ["60", 30] + PlayerCopy.STORE_CARD_PER_DOLLAR % "13" in words and PlayerCopy.STORE_CARD_BONUS % ["5", 10] in words and PlayerCopy.STORE_CARD_BONUS % ["20", 20] in words, "Bonus lines from the pack table, 13 per $1 on the Barrel: " + str(words))
	var joined := " | ".join(words)
	for line: Array in [["No bonus · first pack", "50"], ["First pack", "110"], ["First pack", "240"], ["First pack", "520"]]:
		_check(joined.contains(line[0] + " | " + line[1]), "First pack amounts pay double: %s %s" % line)
	var gift: Control = page.find_child("PollenStoreGift", true, false)
	_check(gift != null and _texts(gift) == [PlayerCopy.FRUIT_STORE_FIRST_DOUBLE, PlayerCopy.FRUIT_STORE_FIRST_AS % "Bowl", PlayerCopy.STORE_FIRST_SUM % ["55", "55"]] and gift.find_child("BundleArt", true, false).bundle == "bowl_pair" and gift.find_child("FruitMark", true, false) != null,
		"The first pack card pays double with the Bowl pair and 55 + 55 with the Fruit mark: " + str(_texts(gift)))
	_check(page.find_child("PollenStoreBundle_barrel", true, false).find_child("FruitMark", true, false) != null and page.find_child("PollenStoreBundle_barrel", true, false).find_child("PollenMark", true, false) == null, "Fruit amounts wear the Fruit mark")
	_check(page.find_child("PollenStoreEarn", true, false) == null and PlayerCopy.FRUIT_STORE_TOGETHER in words and PlayerCopy.FRUIT_STORE_CONVERT in words and PlayerCopy.POLLEN_PURCHASES_TITLE in words and PlayerCopy.POLLEN_STORE_FOOT in words, "The Fruits tab's buttons and footnote")
	(page.find_child("PollenStoreTogether", true, false) as Button).pressed.emit()
	(page.find_child("PollenStoreConvert", true, false) as Button).pressed.emit()
	(t.flow._page.chip as Control).fruits_pressed.emit()
	_check(t.host.fruit_pages == ["store", "store"] and t.host.converts == 1, "Fruits for playing together and the chip's Fruit half open the Fruits page; Turn Fruits into Pollen the convert card")
	for size: Vector2 in [Vector2(1600, 738), Vector2(1600, 720), Vector2(1280, 720)]:
		for layer: Control in [t.host.overlay, t.host.ui]: layer.size = size
		await _frames(3)
		var cards: Array[Control] = [page.find_child("PollenStoreGift", true, false)]
		for id: String in Bundles.FRUIT_ORDER: cards.append(page.find_child("PollenStoreBundle_" + id, true, false))
		var fits := true
		for index in range(cards.size()):
			fits = fits and page.find_child("PollenStorePage", true, false).get_global_rect().grow(0.5).encloses(cards[index].get_global_rect())
			if index > 0: fits = fits and cards[index].get_global_rect().position.x >= cards[index - 1].get_global_rect().end.x - 0.5
			for label: Label in cards[index].find_children("*", "Label", true, false): fits = fits and cards[index].get_global_rect().grow(0.5).encloses(label.get_global_rect())
		_check(fits, "The Fruits tab's cards fit side by side, their words inside, at %s" % size)
	# A pack the "fruits" offering does not have never shows; the ribbon goes to the best one left.
	t.purchases.offerings = _fruit_offerings("barrel")
	t.flow.load_store()
	await _frames()
	_check(page.find_child("PollenStoreBundle_barrel", true, false) == null and page.find_child("PollenStoreBundle_crate", true, false).is_ancestor_of(page.find_child("PollenStoreRibbon", true, false)), "Without the Barrel's product it is not shown and the Crate takes the ribbon")
	# Back on the Pollen tab, from a Main that cannot open the Fruits page.
	t.flow.set_tab("pollen")
	await _frames()
	_check(page.find_child("PollenStoreBundle_pinch", true, false) != null and page.find_child("PollenStoreBundle_handful", true, false) == null and page.find_child("PollenStoreEarn", true, false) != null, "The Pollen tab lists the bundles again")
	t.host.queue_free()
	var plain := _setup()
	plain.purchases.offerings = _fruit_offerings()
	plain.fruits.set_enabled(SERVER, ME, true, true)
	plain.flow.show_store("home", "fruits")
	await _frames()
	_check(plain.flow.tab == "fruits" and plain.host.overlay.find_child("PollenStoreTogether", true, false) == null and plain.host.overlay.find_child("PollenStoreConvert", true, false) == null, "Opened on its Fruits tab; with no Fruits page to open, neither of its buttons shows")
	_check((plain.flow._page.chip as Control).fruits_label.text == "0", "Before the first Fruits read the chip shows 0 Fruits")
	plain.host.queue_free()
	await _frames(2)

## Fruits on but no Fruit packs on sale here: the tab shows its buttons and no card.
func _fruit_packs_off() -> void:
	var t := _fruit_setup(false)
	t.flow.show_store("home", "fruits")
	await _frames()
	var page: Node = t.host.overlay
	_check(t.flow.tab == "fruits" and page.find_child("PollenStoreGift", true, false) == null and Bundles.FRUIT_ORDER.all(func(id: String) -> bool: return page.find_child("PollenStoreBundle_" + id, true, false) == null), "Packs off: no first pack card and no pack")
	_check(page.find_child("PollenStoreTogether", true, false) != null and page.find_child("PollenStoreConvert", true, false) != null, "Packs off: the Fruits tab still offers its two buttons")
	t.flow.confirm("bowl")
	_check(t.host.ui.find_child("PollenStoreConfirm", true, false) == null, "Packs off: a Fruit pack cannot be bought even when the offering lists it")
	t.host.queue_free()
	await _frames(2)

## A Fruit pack bought through the same engine and claim, with its own confirm card and receipt.
func _fruit_purchase() -> void:
	var t := _fruit_setup()
	t.flow.show_store("home", "fruits")
	await _frames()
	t.flow.confirm("bowl")
	var sheet: Node = t.host.ui.find_child("PollenStoreConfirm", true, false)
	var words := _texts(sheet)
	_check(sheet != null and PlayerCopy.POLLEN_STORE_CONFIRM_TITLE % "Bowl" in words and PlayerCopy.FRUIT_STORE_CONFIRM_NOTE in words and PlayerCopy.FRUIT_STORE_GIFT % 100 in words and "110" in words and "101  →  " in words and "211" in words and "$4.99" in words,
		"Buy a Bowl? 55 with its double, you get 110, 101 to 211, you pay $4.99: " + str(words))
	_check(sheet.find_child("FruitMark", true, false) != null and sheet.find_child("PollenMark", true, false) == null, "The confirm card's amounts wear the Fruit mark")
	var credited := {"bundle": "bowl", "fruits": 55.0, "first_gift": 55.0, "order": "GPA.9999-8888-7777-66666", "purchased_at": 1.8e12, "usd_cents": 499.0}
	t.fake.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "balance": 9000.0, "pending": false, "refunded": [], "credited": [], "fruit_credited": [credited], "fruit_refunded": [], "fruit_balance": 211.0}}]
	(sheet.find_child("PollenStoreConfirmBuy", true, false) as Button).pressed.emit()
	await _frames(10)
	_check(t.purchases.bought == [["fruits", "bowl"]], "Its Buy hands the Bowl's package from the fruits offering to the store")
	var receipt: Node = t.host.ui.find_child("PollenStoreReceipt", true, false)
	var lines := _texts(receipt)
	_check(receipt != null and PlayerCopy.FRUIT_STORE_ADDED % "110" in lines and PlayerCopy.FRUIT_STORE_GIFT % 100 in lines and "101  →  " in lines and "211" in lines and PlayerCopy.POLLEN_STORE_ORDER % ["$4.99", "GPA.9999-8888-7777-66666"] in lines,
		"The receipt: 110 Fruits added, the double, 101 to 211, the price and order: " + str(lines))
	_check(t.fruits.balance(SERVER, ME) == 211 and t.claims.unseen_fruits().is_empty() and not PlayerCopy.FRUIT_STORE_ON_ITS_WAY in t.host.toasts, "The Fruit balance follows the server and the receipt counts as seen")
	await _frames(2)
	_check((t.flow._page.chip as Control).fruits_label.text == "211", "The header's chip follows the new Fruit balance")
	t.host.queue_free()
	await _frames(2)
	# A claim that gets no answer says the Fruits are on their way.
	var late := _fruit_setup()
	late.flow.show_store("home", "fruits")
	await _frames()
	late.flow.buy("handful")
	await create_timer(BundlePurchase.CLAIM_PAUSE_S * 3.0 + 0.5).timeout
	await _frames(4)
	_check(PlayerCopy.FRUIT_STORE_ON_ITS_WAY in late.host.toasts and late.claims.pending(), "With no answer the Fruits are on their way and the claim waits: " + str(late.host.toasts))
	late.host.queue_free()
	await _frames(2)
	# A Pollen bundle and a Fruit pack credited by one claim: one receipt at a time, the other waits for the next visit.
	var both := _fruit_setup()
	var pollen_credit: Dictionary = _credited("pinch", 0, 14000).data.credited[0]
	var fruit_credit := {"bundle": "handful", "fruits": 25.0, "first_gift": 25.0, "order": "GPA.9999-8888-7777-11111", "purchased_at": 1.8e12, "usd_cents": 249.0}
	both.fake.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "balance": 14000.0, "pending": false, "refunded": [], "credited": [pollen_credit], "fruit_credited": [fruit_credit], "fruit_refunded": [], "fruit_balance": 151.0}}]
	both.claims.mark_pending()
	await both.claims.claim()
	both.flow.show_store("home")
	await _frames()
	var first_receipt := _texts(both.host.ui.find_child("PollenStoreReceipt", true, false))
	_check(PlayerCopy.POLLEN_STORE_ADDED % "5,000" in first_receipt and both.claims.unseen_fruits().size() == 1, "The Pollen receipt shows first and the Fruit one still waits: " + str(first_receipt))
	both.flow._close_sheet()
	both.flow.show_store("home")
	await _frames()
	var second_receipt := _texts(both.flow._sheet.get_ref() if both.flow._sheet != null else null)
	_check(PlayerCopy.FRUIT_STORE_ADDED % "50" in second_receipt and both.claims.unseen_fruits().is_empty(), "The next visit shows the Fruit receipt: " + str(second_receipt))
	both.host.queue_free()
	await _frames(2)

## Previous purchases with Fruits on: Fruit packs and their refunds join the list, newest first.
func _fruit_purchases_list() -> void:
	var t := _fruit_setup()
	var history := FakeHistory.new()
	history.tree = self
	history.answer = PollenHistory.checked({"schema_version": 1.0, "entries": [], "first_clears": [], "spent_usd_cents": 1999.0,
		"purchases": [{"kind": "bundle", "amount": 115000.0, "at": 1.80e12, "bundle": "basket", "order": "GPA.2222-3333-4444-55555", "usd_cents": 1999.0}],
		"fruit_entries": [{"kind": "bundlerefund", "amount": -110.0, "at": 1.82e12, "bundle": "bowl", "order": "GPA.9999-8888-7777-66666"},
			{"kind": "ach", "amount": 10.0, "at": 1.815e12, "id": "together_first"},
			{"kind": "bundle", "amount": 110.0, "at": 1.81e12, "bundle": "bowl", "order": "GPA.9999-8888-7777-66666", "usd_cents": 499.0}]})
	t.host.pollen_client = history
	StoreCurrency.use_path(_path("currency"))
	StoreCurrency.note(_offerings())
	t.flow.show_store()
	await _frames()
	(t.host.overlay.find_child("PollenStorePurchases", true, false) as Button).pressed.emit()
	await _frames()
	var sheet: Node = t.host.ui.find_child("PollenPurchases", true, false)
	var rows: Array = sheet.find_children("PollenPurchaseRow*", "", true, false)
	var words := _texts(sheet)
	_check(rows.size() == 3 and PlayerCopy.FRUIT_PURCHASES_NOTE in words and PlayerCopy.POLLEN_PURCHASE_REFUNDED % "Bowl" in words and "Bowl" in words and "Wheelbarrow" in words, "Fruit packs and their refund join the list, achievements do not: " + str(words))
	_check(rows.size() == 3 and _texts(rows[0])[0] == PlayerCopy.POLLEN_PURCHASE_REFUNDED % "Bowl" and _texts(rows[1])[0] == "Bowl" and _texts(rows[2])[0] == "Wheelbarrow", "Newest first across both currencies")
	_check(rows.size() == 3 and rows[1].find_child("FruitMark", true, false) != null and rows[2].find_child("PollenMark", true, false) != null and PlayerCopy.POLLEN_STORE_ORDER % ["$4.99", "GPA.9999-8888-7777-66666"] in words, "Each row wears its own mark and receipt line")
	t.host.queue_free()
	var off := _setup()
	off.host.pollen_client = history
	off.flow.show_store()
	await _frames()
	(off.host.overlay.find_child("PollenStorePurchases", true, false) as Button).pressed.emit()
	await _frames()
	sheet = off.host.ui.find_child("PollenPurchases", true, false)
	_check(sheet.find_children("PollenPurchaseRow*", "", true, false).size() == 1 and PlayerCopy.POLLEN_PURCHASES_NOTE in _texts(sheet), "With Fruits off the list stays Pollen only")
	off.host.queue_free()
	await _frames(2)

## Offline, every store button that needs the server greys and comes back with the connection.
func _fruit_offline() -> void:
	var state: RefCounted = Connectivity.new()
	Connectivity.use_shared(state)
	var t := _fruit_setup()
	t.flow.show_store("home", "fruits")
	await _frames()
	var page: Node = t.host.overlay
	var held := func() -> Array:
		var out: Array = []
		for name: String in ["PollenStoreBuy_handful", "PollenStoreBuy_barrel", "PollenStoreConvert", "PollenStorePurchases"]:
			var button := page.find_child(name, true, false) as BaseButton
			out.append(button != null and OfflineHold.held(button))
		return out
	_check(held.call() == [false, false, false, false], "Online nothing is held")
	state.force(false)
	await _frames(2)
	_check(held.call() == [true, true, true, true], "Offline the prices, Turn Fruits into Pollen and Previous purchases hold: %s" % [held.call()])
	_check(not OfflineHold.held(page.find_child("PollenStoreTogether", true, false) as BaseButton) and not OfflineHold.held(page.find_child("PollenStoreTab_pollen", true, false) as BaseButton), "The Fruits page and the tabs stay open offline")
	state.force(true)
	await _frames(2)
	_check(held.call() == [false, false, false, false], "Back online they come back at once")
	t.host.queue_free()
	Connectivity.use_shared(null)
	await _frames(2)

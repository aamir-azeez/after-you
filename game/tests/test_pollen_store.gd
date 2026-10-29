extends SceneTree
## The Pollen store (Pollen board 2: presentation/pollen_store_flow.gd,
## pollen_store_page.gd, pollen_store_sheets.gd) and the bundle claims behind
## it (services/bundle_claims.gd, services/pollen_bundles.gd), with a stand-in
## host, a stand-in store (RevenueCat's purchases bridge) and a fake server:
## - it opens only while the server sells bundles and the build sells them
##   (never on iPhone or the Test Store build);
## - the four bundles show the art, totals, bonus lines, Pollen per $1 and the
##   store's own prices from the "pollen" offering only; the first bundle line
##   shows only while that gift is on and unused;
## - the confirm card adds up in plain sums, and its Buy hands over to the store;
## - a purchase is claimed from the server, and the receipt shows what was
##   added, the balance before and after, the price and the order number;
## - a cancelled or failed purchase claims nothing; a claim that gets no answer
##   stays waiting, goes again on the next flush, and its receipt shows on the
##   next visit; a refund the server took back shows in the balance, below zero;
## - a tap while a claim is still out waits for it (first taps);
## - the claims service checks every answer and keeps its waiting mark on disk.
const Flow = preload("res://presentation/pollen_store_flow.gd")
const BundleClaims = preload("res://services/bundle_claims.gd")
const Bundles = preload("res://services/pollen_bundles.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

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
	func show_pollen_from_play() -> bool:
		earning_opened += 1
		return earning_opens
	func _names_scope() -> Dictionary: return scope
	func _clear_overlay() -> void:
		for child: Node in overlay.get_children(): child.queue_free()
	func _toast(text: String) -> void: toasts.append(text)

## The RevenueCat bridge's signals and calls (services/purchases.gd).
class FakePurchases extends Node:
	signal completed(request_id: String, operation: String, payload: Dictionary)
	signal failed(request_id: String, operation: String, code: String, message: String, cancelled: bool)
	var offerings: Dictionary = {}
	var offerings_fail := false
	## "ok", "cancel" or "fail".
	var outcome := "ok"
	var bought: Array = []
	var serial := 0
	func fetch_offerings() -> String:
		serial += 1
		var id := "read-%d" % serial
		if offerings_fail: failed.emit.call_deferred(id, "get_offerings", "revenuecat_NETWORK_ERROR", "No store", false)
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
		packages.append({"id": "%s_package" % row[0], "product_id": Bundles.play_product(row[0]) + ":buy", "type": "CUSTOM", "price": row[1], "price_micros": float(row[2]), "currency": "USD"})
	return {"schema_version": 1, "mode": "google_play", "current_id": "default", "offerings": [
		{"id": "default", "packages": [{"id": "$rc_monthly", "product_id": "after_you_full_journey_monthly", "type": "MONTHLY", "price": "$0.99", "price_micros": 990000.0, "currency": "USD"}]},
		{"id": "pollen", "packages": packages}]}

static func _view(gift: bool, percent: int = 0, balance: int = 9000) -> Dictionary:
	return {"schema_version": 1.0, "balance": float(balance), "earned": float(maxi(balance, 0)), "bank": 12.0, "name_price": 0.0,
		"wardrobe": {"items": [], "packs": [], "look": {}, "look_revision": 1.0, "offered": ["daisy"], "offered_packs": [], "sets": {}, "unlocked": []},
		"bundles": {"first_gift": gift, "first_gift_percent": float(percent), "spent_usd_cents": 0.0}}

static func _credited(bundle: String, gift: int, balance: int, order: String = "GPA.1234-5678-9012-34567") -> Dictionary:
	return {"ok": true, "status": 200, "data": {"schema_version": 1.0, "balance": float(balance), "pending": false, "refunded": [],
		"credited": [{"bundle": bundle, "pollen": float(Bundles.pollen(bundle)), "first_gift": float(gift), "order": order, "purchased_at": 1.8e12, "usd_cents": float(Bundles.usd_cents(bundle))}]}}

func _setup(server_bundles: bool = true, build_bundles: bool = true, sells: bool = true) -> Dictionary:
	var host := Host.new()
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
	var claims: RefCounted = BundleClaims.new(_path("claims"), store, wallet)
	claims.connect_to(null, host._names_scope, fake.call_it)
	var flow: Node = Flow.new(host)
	host.add_child(flow)
	flow.surfaces = PollenSurfaces.new(sells, build_bundles)
	flow.claims = claims
	flow.wardrobe = store
	flow.wallet = wallet
	flow.store_ready = func() -> bool: return true
	return {"host": host, "purchases": purchases, "store": store, "wallet": wallet, "fake": fake, "claims": claims, "flow": flow}

func _run() -> void:
	await _gates()
	await _cards()
	await _buying()
	await _gift()
	await _cancelled_and_failed()
	await _claim_waits()
	await _refund()
	await _offline_store()
	await _first_tap_waits()
	await _claims_service()
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
	t.flow.show_store()
	_check(t.host.mode == Flow.MODE_POLLEN_STORE and t.flow.is_open() and PlayerCopy.POLLEN_STORE_LOADING in _texts(t.host.overlay), "The store opens and says it is loading")
	await _frames()
	var page: Node = t.host.overlay
	var words := _texts(page)
	for id: String in Bundles.ORDER:
		_check(page.find_child("PollenStoreBundle_" + id, true, false) != null and page.find_child("PollenStoreBuy_" + id, true, false) != null, "The %s card and its price button show" % id)
	_check("$0.99" in words and "$3.99" in words and "$7.99" in words and "$19.99" in words, "Each price is the store's own: " + str(words))
	_check(not "after_you_full_journey_monthly" in str(t.flow._packages) and t.flow._packages.size() == 4, "Only the Pollen offering's packages are read")
	_check(PlayerCopy.POLLEN_STORE_NO_BONUS in words and PlayerCopy.POLLEN_STORE_BONUS % ["20,000", "1,000", 5] in words and PlayerCopy.POLLEN_STORE_BONUS % ["40,000", "4,000", 10] in words and PlayerCopy.POLLEN_STORE_BONUS % ["100,000", "15,000", 15] in words, "Bonus lines in plain Pollen and percent")
	for row: Array in [["5,051"], ["5,263"], ["5,507"], ["5,753"]]:
		_check(PlayerCopy.POLLEN_STORE_PER_DOLLAR % row[0] in words, "Pollen per $1: %s in %s" % [row[0], words])
	_check(["5,000", "21,000", "44,000", "115,000"].all(func(amount: String) -> bool: return amount in words), "Each total with its grain")
	_check(page.find_children("BundleArt", "", true, false).size() == 4, "Each card has its art")
	_check(not (page.find_child("PollenStoreGift", true, false) as Control).visible, "No first bundle line while that gift is off")
	_check("9,000" in _texts(page.find_child("PollenStoreBalance", true, false)) and PlayerCopy.POLLEN_STORE_YOU_HAVE in words, "The chip says You have 9,000")
	_check(PlayerCopy.POLLEN_STORE_EARN in words and PlayerCopy.POLLEN_STORE_FOOT in words, "Earn Pollen free by playing and the footnote")
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
	_check("21,000" in words and PlayerCopy.POLLEN_STORE_YOU_GET in words and "9,000  →  " in words and "30,000" in words and "$3.99" in words and not PlayerCopy.POLLEN_STORE_GIFT % 10 in words, "Plain sums: you get 21,000, 9,000 to 30,000, you pay $3.99, no gift: " + str(words))
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

## The first bundle gift, while it is on and unused.
func _gift() -> void:
	var t := _setup()
	t.store.note_view(SERVER, ME, _view(true, 10))
	t.flow.show_store()
	await _frames()
	var gift: Control = t.host.overlay.find_child("PollenStoreGift", true, false)
	_check(gift.visible and (gift.find_child("*", true, false) != null) and str((t.host.overlay.find_children("*", "RichTextLabel", true, false)[0] as RichTextLabel).text).contains("10%"), "The first bundle line shows while the gift is on")
	t.flow.confirm("pouch")
	var words := _texts(t.host.ui.find_child("PollenStoreConfirm", true, false))
	_check(PlayerCopy.POLLEN_STORE_GIFT % 10 in words and "2,100" in words and "23,100" in words and "32,100" in words, "The confirm card adds the gift: 2,100, you get 23,100, you'll have 32,100: " + str(words))
	t.fake.replies = [_credited("pouch", 2100, 32100)]
	t.flow.buy("pouch")
	await _frames(10)
	var lines := _texts(t.host.ui.find_child("PollenStoreReceipt", true, false))
	_check(PlayerCopy.POLLEN_STORE_ADDED % "23,100" in lines and PlayerCopy.POLLEN_STORE_GIFT % 10 in lines and "32,100" in lines, "The receipt: 23,100 Pollen added with the gift row: " + str(lines))
	t.store.note_view(SERVER, ME, _view(false, 10))
	t.flow._redraw()
	_check(not gift.visible, "Once used, the line goes")
	t.host.queue_free()
	await _frames(2)

## A cancelled sheet claims nothing and drops its mark; a failed one claims nothing now but keeps its
## mark (a payment may settle later); a sheet the app never heard back from (closed) keeps it too.
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
	await create_timer(Flow.CLAIM_PAUSE_S * 3.0 + 0.5).timeout
	await _frames(4)
	_check(t.fake.sent.size() == Flow.CLAIM_TRIES and t.claims.pending() and PlayerCopy.POLLEN_STORE_ON_ITS_WAY in t.host.toasts, "No answer: a few tries, then it waits and the player is told it is on its way")
	var reload: RefCounted = BundleClaims.new(t.claims.path, t.store, t.wallet)
	reload.connect_to(null, t.host._names_scope, t.fake.call_it)
	_check(reload.pending(), "The waiting claim survives a restart")
	t.fake.replies = [_credited("pinch", 0, 14000)]
	await t.claims.flush()
	_check(not t.claims.pending() and t.claims.unseen().size() == 1 and t.wallet.wallet(SERVER, ME).balance == 14000, "The next flush credits it and keeps its receipt for the player")
	t.flow.show_store()
	await _frames(4)
	_check(PlayerCopy.POLLEN_STORE_ADDED % "5,000" in _texts(t.host.ui.find_child("PollenStoreReceipt", true, false)) and t.claims.unseen().is_empty(), "Its receipt shows on the next visit, once")
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
static func _texts(node: Node) -> Array:
	var out: Array = []
	if node == null: return out
	if node is CanvasItem and not (node as CanvasItem).visible: return out
	if (node is Label or node is Button) and not str(node.text).is_empty(): out.append(node.text)
	for child: Node in node.get_children(): out.append_array(_texts(child))
	return out

extends SceneTree
## The Wardrobe on screen (presentation/wardrobe_flow.gd, wardrobe_page.gd,
## wardrobe_sheets.gd), as Pollen board 5b draws it, with a stand-in host and a
## fake transport:
## - it opens only while the server has the wardrobe on, on every build;
## - the page lists what the server sells, with the shelf of the week in its own
##   panel, the slot chips, tier frames, prices with the grain;
## - no Pollen price names a money figure (cards, the Buy button and the
##   confirm card; the owner removed the about $X hints, 2026-11-02);
## - the main button says Buy for [grain] N, Wear or Take off; a tap
##   while the wardrobe is still being read waits for the read (first taps);
## - Buy opens the confirm card (the pip, balance, cost, what is left) and
##   only its Buy sends, at the cost the card showed;
## - a short balance opens the short card (Needed box, It stays in the shop,
##   Keep playing with friends) and sends nothing; only while bundles sell it
##   names the smallest bundle that covers the gap (the first bundle gift
##   counted) and its Get Pollen asks for the store on that bundle, for every
##   tier; a Special that is not unlocked cannot be bought;
## - the balance chip's + shows only while bundles sell; its balance asks for the Pollen page;
## - the pip switch draws your pip in mint "as your friend sees you";
## - an earned item has the Earned frame and a Not for sale chip;
## - All items lists every earned item the server offers, owned or not, on its
##   slot chip: one not owned has the lock, no price and no Buy, picking it puts
##   it on the big pip and says how it is earned, and it is never on the shelf,
##   never bought, never behind Get more or the short card; one owned says Yours;
## - Wear and Take off send the whole look; Back asks the host to leave and
##   remembers where the Wardrobe was opened from;
## - a build without the shop (iOS selling nothing) and a server with the shop
##   off show the same frame on Owned: no price, no Buy, no shelf, no +, and All
##   items only while an earned item not owned is offered, with no sale wording;
## - an empty list shows the one hanger drawing (presentation/empty_state.gd)
##   with its case's line: nothing owned, nothing in the shop, or the shop off;
##   never while loading or offline, made once and still on idle frames;
## - every slot of Owned ends with a Get more card (the hanger drawing, no pip)
##   while the shop has anything not owned; it opens All items on its slot, or
##   on a slot with something to buy; never on All items, with nothing owned,
##   or without the shop.
const Flow = preload("res://presentation/wardrobe_flow.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const WardrobeClient = preload("res://services/wardrobe_client.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const TierFrame = preload("res://presentation/kit/tier_frame.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")
const Page = preload("res://presentation/wardrobe_page.gd")
const Sheets = preload("res://presentation/wardrobe_sheets.gd")
const Bundles = preload("res://services/pollen_bundles.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")

# Synthetic ids only.
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const SERVER := "https://wardrobe-flow.example.test"
const SOLD := ["daisy", "seashell", "straw_hat", "tide", "lantern", "lighthouse_lamp"]

var checks := 0
var failures := 0
var _paths: Array[String] = []

## Stands in for the Pollen store's purchase engine (presentation/bundle_purchase.gd):
## nothing priced yet, so a short card's button names its bundle and waits.
class StubBuyer extends Node:
	signal prices_changed(loaded: bool)
	var flow: Node
	var loads := 0
	func priced() -> bool: return false
	func loading() -> bool: return loads > 0
	func load_prices() -> void: loads += 1
	func ensure_prices() -> void: if not loading(): load_prices()
	func price(_bundle: String) -> String: return ""
	func ready_to_buy() -> bool: return false
	func buy(_bundle: String, _done: Callable) -> String: return "busy"
	func take_unseen() -> Array: return []

## Stands in for Main's Pollen store flow: whether it sells, and its engine.
class StoreStub extends Node:
	var on := true
	var purchase: Node
	var opened: Array = []
	func available() -> bool: return on
	func show_store(from: String = "wardrobe") -> void: opened.append(from)

class Host extends Node:
	var api: Node = null
	var pollen_store_flow: Node = null
	var mode := ""
	var running := true
	var overlay: Control
	var ui: Control
	var toasts: Array = []
	var scope := {}
	func _names_scope() -> Dictionary: return scope
	func _clear_overlay() -> void:
		for child: Node in overlay.get_children(): child.queue_free()
	func _toast(text: String) -> void: toasts.append(text)

class Fake extends RefCounted:
	var tree: SceneTree
	var sent: Array = []
	var replies: Array = []
	## Frames each answer takes.
	var delay := 1
	func call_it(method: int, path: String, body: Dictionary) -> Dictionary:
		sent.append({"method": method, "path": path, "body": body.duplicate(true)})
		for i in range(delay): await tree.process_frame
		var reply: Variant = replies.pop_front() if not replies.is_empty() else {"ok": false, "status": 0, "code": "connection_interrupted"}
		return reply.call(body) if reply is Callable else reply

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _path(stem: String) -> String:
	var path := "user://test-wardrobe-flow-%s-%s.json" % [stem, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

static func _answer(items: Array, look: Dictionary, balance: int, unlocked: Array = [], bundles: Variant = null) -> Dictionary:
	var data := {"schema_version": 1.0, "balance": float(balance), "earned": float(maxi(balance, 0)), "bank": 12.0, "name_price": 0.0,
		"wardrobe": {"items": items, "packs": [], "look": look, "look_revision": 1.0, "offered": SOLD + ["gold_leaf", "every_hard", "top_ten_ribbon"],
			"offered_packs": [], "sets": {}, "unlocked": unlocked}}
	if bundles != null: data.bundles = bundles
	return {"ok": true, "status": 200, "data": data}

func _frames(count: int = 6) -> void:
	for i in range(count): await process_frame

## `bundles`: the server has bundles on and the build sells them.
func _setup(on: bool = true, bundles: bool = false) -> Dictionary:
	var host := Host.new()
	host.overlay = Control.new()
	host.ui = Control.new()
	host.overlay.size = Vector2(1600, 738)
	host.ui.size = Vector2(1600, 738)
	root.add_child(host)
	host.add_child(host.overlay)
	host.add_child(host.ui)
	host.scope = {"server": SERVER, "owner": ME}
	var store: RefCounted = Wardrobe.new(_path("store"))
	var wallet: RefCounted = PollenWallet.new(_path("wallet"))
	var fake := Fake.new()
	fake.tree = self
	var flow: Node = Flow.new(host)
	host.add_child(flow)
	flow.client = WardrobeClient.new(null, host._names_scope, fake.call_it, store, wallet)
	flow.week = 3
	flow.surfaces = PollenSurfaces.new(true, bundles)
	if bundles:
		var stub := StoreStub.new()
		stub.purchase = StubBuyer.new()
		stub.purchase.flow = stub
		stub.add_child(stub.purchase)
		host.add_child(stub)
		host.pollen_store_flow = stub
	# The shared wardrobe releases what the server offers (services/wardrobe.gd); the flow here uses its own store.
	preload("res://services/cosmetic_catalog.gd").set_offered(SOLD + ["gold_leaf", "every_hard", "top_ten_ribbon"])
	if on:
		store.set_enabled(SERVER, ME, true, true, bundles)
		wallet.set_enabled(SERVER, ME, true)
	return {"host": host, "store": store, "wallet": wallet, "fake": fake, "flow": flow}

func _run() -> void:
	await _gates()
	await _buying()
	await _first_tap_waits()
	await _short_card()
	await _gets_fit()
	await _page_parts()
	await _offline()
	await _negative_balance()
	await _wearing()
	await _owned_only()
	await _server_shop_off()
	await _empty_lists()
	await _get_more()
	await _earned_in_shop()
	await _earned_without_shop()
	await _start_tab()
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	preload("res://services/cosmetic_catalog.gd").set_offered([])
	print("AFTER YOU WARDROBE FLOW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _gates() -> void:
	var off := _setup(false)
	_check(not off.flow.available(), "No Wardrobe while the server has the wardrobe off")
	off.flow.show_wardrobe()
	_check(off.host.overlay.get_child_count() == 0 and off.fake.sent.is_empty(), "Opening it then shows and sends nothing")
	var hidden := _setup()
	hidden.flow.surfaces = PollenSurfaces.new(false)
	_check(hidden.flow.available(), "A build that sells nothing still has the Wardrobe")
	_check(not PollenSurfaces.new(false, true).bundles_visible() and not PollenSurfaces.new(true).bundles_visible() and PollenSurfaces.new(true, true).bundles_visible(), "Only a build that sells and sells bundles shows bundles")
	off.host.queue_free()
	hidden.host.queue_free()
	await _frames(2)

func _buying() -> void:
	var t := _setup()
	t.fake.replies = [_answer([], {}, 24000)]
	t.flow.show_wardrobe()
	_check(t.host.mode == Flow.MODE_WARDROBE and t.flow.is_open() and t.flow.return_to == "settings", "The page opens, from Settings by default")
	await _frames()
	var model: Dictionary = t.flow.model()
	_check(model.balance == 24000 and model.items.size() == 9 and model.items.filter(func(entry: Dictionary) -> bool: return entry.sold).size() == 6 and t.fake.sent.size() == 1 and t.fake.sent[0].path == "/v1/pollen", "It reads the wardrobe and lists the six items the server sells, and the three earned ones")
	_check(model.featured.size() == 4 and model.featured[3] == "lighthouse_lamp", "Week 3's shelf: the Commons, the Uncommon and the Special in the top slot")
	_check(model.selected == "lighthouse_lamp", "With nothing picked, the shelf's top slot is on the big pip")
	_check(t.host.overlay.find_child("WardrobeCard_daisy", true, false) != null and t.host.overlay.find_child("WardrobeShelfCard_lighthouse_lamp", true, false) != null, "The items and the shelf are drawn")
	_check("24,000" in _texts(t.host.overlay.find_child("WardrobeBalance", true, false)), "The chip shows the balance grouped")
	_check(not _plus_shown(t.host.overlay), "No + on the chip while bundles do not sell")
	t.flow.set_kind("body")
	t.flow.select("tide")
	_check(t.flow.model().preview == {"body": "tide"}, "The picked item shows on the big pip")
	var action: Button = t.host.overlay.find_child("WardrobeAction", true, false)
	var words := _texts(action)
	_check(words == [PlayerCopy.WARDROBE_BUY_FOR, "20,000"] and action.find_child("PollenMark", true, false) != null, "Its button says Buy for [grain] 20,000 and nothing more: " + str(words))
	await t.flow.act("tide")
	var sheet: Node = t.host.ui.find_child("WardrobeConfirm", true, false)
	_check(sheet != null and t.fake.sent.size() == 1, "Buy opens the confirm card and sends nothing yet")
	var texts := _texts(sheet)
	_check("24,000" in texts and "Tide" in texts and "4,000" in texts and _no_money(sheet), "The card shows the balance, the item, the cost and what is left, with no money figure: " + str(texts))
	_check(sheet.find_child("WardrobeConfirmPip", true, false) != null and sheet.find_children("PollenMark", "", true, false).size() == 3, "It shows the item on a pip and the grain on each row")
	t.fake.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "op": "spend", "kind": "item", "id": "tide", "pieces": ["tide"], "cost": 20000.0, "balance": 4000.0}}]
	await t.flow.confirm_buy("tide", 20000)
	_check(t.fake.sent.size() == 2 and t.fake.sent[1].path == "/v1/pollen/spend" and t.fake.sent[1].body.expected_cost == 20000 and t.fake.sent[1].body.id == "tide", "Its Buy sends the purchase at the cost the card showed")
	_check("tide" in t.store.view(SERVER, ME).items and t.flow.model().balance == 4000 and PlayerCopy.WARDROBE_BOUGHT % "Tide" in t.host.toasts, "Then it is owned, the balance follows, and the player is told")
	_check(_texts(t.host.overlay.find_child("WardrobeAction", true, false)) == [PlayerCopy.WARDROBE_WEAR], "The bought item now offers Wear")
	var lamp: Dictionary = t.flow._entry("lighthouse_lamp")
	_check(lamp.locked and str(lamp.unlock_name) != "sleeping-lighthouse", "A Special waits for its chapter, named by title")
	t.flow.select("lighthouse_lamp")
	_check((t.host.overlay.find_child("WardrobeAction", true, false) as Button).disabled and PlayerCopy.WARDROBE_LOCKED % lamp.unlock_name in _texts(t.host.overlay), "A locked Special's button is off and says where it opens")
	await t.flow.act("lighthouse_lamp")
	_check(t.fake.sent.size() == 2, "A locked Special cannot be bought")
	var back := {"asked": false}
	t.flow.back_requested.connect(func() -> void: back.asked = true)
	(t.host.overlay.find_child("WardrobeBack", true, false) as Button).pressed.emit()
	_check(back.asked, "Back asks the host to leave")
	t.flow.show_wardrobe("home")
	_check(t.flow.return_to == "home", "Opened from Home, Back goes to Home")
	t.host.queue_free()
	await _frames(2)

## A Buy tapped while the first read is still out waits for it, then opens the card: the first tap registers.
func _first_tap_waits() -> void:
	var t := _setup()
	t.store.note_view(SERVER, ME, _answer([], {}, 24000).data)
	t.wallet.note_wallet(SERVER, ME, _answer([], {}, 24000).data)
	t.fake.delay = 12
	t.fake.replies = [_answer([], {}, 24000)]
	t.flow.show_wardrobe()
	await process_frame
	t.flow.select("daisy")
	_check(t.flow._client().busy(), "The read is still out")
	t.flow.tap_action("daisy")
	await _frames(3)
	_check(t.host.ui.find_child("WardrobeConfirm", true, false) == null, "The tap waits while the read is out")
	await _frames(20)
	_check(t.host.ui.find_child("WardrobeConfirm", true, false) != null, "Then the confirm card opens, without a second tap")
	t.host.queue_free()
	await _frames(2)

func _short_card() -> void:
	for bundles: bool in [false, true]:
		var t := _setup(true, bundles)
		t.fake.replies = [_answer([], {}, 14500)]
		t.flow.show_wardrobe()
		await _frames()
		_check(_plus_shown(t.host.overlay) == bundles, "The chip's + shows only while bundles sell (%s)" % bundles)
		var opened: Array = []
		var pollen := {"count": 0}
		t.flow.store_requested.connect(func() -> void: opened.append("store"))
		t.flow.pollen_requested.connect(func() -> void: pollen.count += 1)
		var chip: Control = t.host.overlay.find_child("PollenChip", true, false)
		chip.amount_pressed.emit()
		_check(pollen.count == 1 and opened.is_empty(), "The chip's balance asks for the Pollen page")
		if bundles:
			chip.plus_pressed.emit()
			_check(opened == ["store"], "The chip's + asks for the store")
			opened.clear()
		t.flow.select("tide")
		await t.flow.act("tide")
		var sheet: Node = t.host.ui.find_child("WardrobeShort", true, false)
		var words := _texts(sheet)
		_check(sheet != null and t.fake.sent.size() == 1, "A short balance opens the short card and sends nothing")
		_check(PlayerCopy.WARDROBE_SHORT_NOTE % ["Tide", "20,000", "14,500"] in words and PlayerCopy.WARDROBE_SHORT_NEEDED in words and "5,500" + PlayerCopy.WARDROBE_SHORT_MORE in words, "It says what it costs, what you have and Needed: 5,500 more: " + str(words))
		_check(not "It stays in the shop." in words and PlayerCopy.WARDROBE_SHORT_EARN in words, "It says to keep playing with friends, and no more that it stays in the shop")
		_check(not words.any(func(text: String) -> bool: return text.contains("$") or text.contains("week") or text.contains("day")), "It never shows money or a time to earn it")
		_check((PlayerCopy.WARDROBE_SHORT_BUNDLE % "Pouch" in words) == bundles and words.any(func(text: String) -> bool: return text.contains("Pinch") or text.contains("Basket") or text.contains("Wheelbarrow")) == false,
			"While bundles sell it names the smallest bundle that covers 5,500, the Pouch (%s): %s" % [bundles, words])
		var buy: BaseButton = sheet.find_child("WardrobeShortBuy", true, false)
		_check((buy != null) == bundles and (sheet.find_child("WardrobeShortBundle", true, false) != null) == bundles and sheet.find_child("WardrobeGetPollen", true, false) == null, "The bundle and its buy button show only while bundles sell (%s)" % bundles)
		if buy != null:
			_check(_texts(buy) == ["Pouch"] and t.host.pollen_store_flow.purchase.loads == 1, "Before the store priced it the button names the Pouch, and the card asks for the prices: " + str(_texts(buy)))
			buy.pressed.emit()
			await _frames(2)
			_check(opened.is_empty() and t.host.ui.find_child("WardrobeShort", true, false) != null, "Its tap stays on the card and opens no store page")
		sheet.close()
		await _frames(2)
		t.flow.select("lantern")
		await t.flow.act("lantern")
		var epic: Node = t.host.ui.find_child("WardrobeShort", true, false)
		_check(epic != null and (PlayerCopy.WARDROBE_SHORT_BUNDLE % "Basket" in _texts(epic)) == bundles, "Short 35,500 for an Epic: the jar bundle, shown as the Basket, while bundles sell (%s)" % bundles)
		if bundles:
			var gets: Node = epic.find_child("WardrobeShortBundleGets", true, false)
			_check(gets != null and gets.find_child("PollenMark", true, false) != null and _texts(gets) == ["44,000" + PlayerCopy.WARDROBE_SHORT_BUNDLE_GETS], "Under it the grain and what the Jar gives, its bonus in: " + str(_texts(gets)))
		_check(t.flow.model().get("bundles") == bundles, "The model says whether bundles sell")
		t.host.queue_free()
		await _frames(2)
	# A Special 99,500 short points to the Basket (unlocked here so it is buyable).
	var s := _setup(true, true)
	s.fake.replies = [_answer([], {}, 500, ["lighthouse_lamp"])]
	s.flow.show_wardrobe()
	await _frames()
	s.flow.select("lighthouse_lamp")
	await s.flow.act("lighthouse_lamp")
	var special: Node = s.host.ui.find_child("WardrobeShort", true, false)
	_check(special != null and PlayerCopy.WARDROBE_SHORT_BUNDLE % "Wheelbarrow" in _texts(special) and special.find_child("WardrobeShortBuy", true, false) != null, "Short 99,500 for a Special: the basket bundle, shown as the Wheelbarrow")
	s.host.queue_free()
	await _frames(2)
	# With the first bundle gift on, a 50,000 gap is the jar's 44,000 and its 8,800 gift (shown as the Basket); past the basket (the Wheelbarrow) it gets you closest.
	for row: Array in [[0, "jar", PlayerCopy.WARDROBE_SHORT_BUNDLE], [-100000, "basket", PlayerCopy.WARDROBE_SHORT_BUNDLE_CLOSEST]]:
		var g := _setup(true, true)
		g.fake.replies = [_answer([], {}, row[0], [], {"first_gift": true, "first_gift_percent": 20.0, "spent_usd_cents": 0.0})]
		g.flow.show_wardrobe()
		await _frames()
		g.flow.select("lantern")
		await g.flow.act("lantern")
		var gifted: Node = g.host.ui.find_child("WardrobeShort", true, false)
		_check(gifted != null and row[2] % Bundles.display_name(row[1]) in _texts(gifted), "Balance %d with the gift on: %s" % [row[0], _texts(gifted)])
		# The store's confirm card sums the same: the bundle with its bonus and the 20% gift.
		var total := Bundles.adds(str(row[1]), {"first_gift": true, "first_gift_percent": 20})
		var value: Label = gifted.find_child("WardrobeShortBundleGets", true, false).find_child("PollenAmountValue", true, false)
		var long := PollenMoney.grouped(total) + PlayerCopy.WARDROBE_SHORT_BUNDLE_GETS_GIFT
		var fits := value.get_theme_font("font").get_string_size(long, HORIZONTAL_ALIGNMENT_LEFT, -1, value.get_theme_font_size("font_size")).x <= value.size.x
		_check(value.text == (long if fits else PollenMoney.grouped(total) + PlayerCopy.WARDROBE_SHORT_BUNDLE_GETS) and PollenMoney.grouped(total) == ("52,800" if row[1] == "jar" else "138,000"), "With the gift on it gives %s, naming the gift only while that fits: %s" % [PollenMoney.grouped(total), value.text])
		g.host.queue_free()
		await _frames(2)

## The frame's parts: tier frames and glow, the slot chips, the pip switch and the earned chip.
func _page_parts() -> void:
	var t := _setup()
	t.fake.replies = [_answer(["gold_leaf"], {}, 24000)]
	t.flow.show_wardrobe()
	await _frames()
	var page: Node = t.host.overlay
	_check(page.find_child("WardrobeShelf", true, false).visible and page.find_child("WardrobeStays", true, false).visible, "The shelf sits in its own panel and the page says every item stays in the shop")
	var chips: Array = page.find_child("WardrobeKinds", true, false).get_children().map(func(node: Node) -> String: return node.name)
	_check(chips == ["WardrobeKind_hat", "WardrobeKind_body", "WardrobeKind_leaf"], "Slot chips: Hat, Body and Leaf: " + str(chips))
	t.flow.set_kind("hat")
	var grid: Node = page.find_child("WardrobeItems", true, false)
	_check(grid.get_children().all(func(card: Node) -> bool: return str(t.flow._entry(str(card.name).trim_prefix("WardrobeCard_")).slot) == "hat"), "The Hat chip lists hats only")
	var lantern: Button = page.find_child("WardrobeCard_lantern", true, false)
	var style := lantern.get_theme_stylebox("normal") as StyleBoxFlat
	_check(style.border_color == TierFrame.frame("epic") and style.shadow_size > 0, "An Epic card has its frame and its glow")
	var daisy := (page.find_child("WardrobeCard_daisy", true, false) as Button).get_theme_stylebox("normal") as StyleBoxFlat
	_check(daisy.border_color == TierFrame.frame("common") and daisy.shadow_size == 0, "A Common card has its frame and no glow")
	_check(_texts(lantern).has(TierFrame.word("epic")) and lantern.find_child("TierMark", true, false) != null and lantern.find_child("PollenMark", true, false) != null and _no_money(lantern), "A card has the tier mark and word and the grain, with no money figure: " + str(_texts(lantern)))
	var shelf_card: Node = page.find_child("WardrobeShelfCard_lighthouse_lamp", true, false)
	_check(shelf_card != null and shelf_card.find_child("PollenAmountValue", true, false) != null and _no_money(shelf_card), "A shelf card has its price with no money figure: " + str(_texts(shelf_card)))
	t.flow.set_kind("leaf")
	var leaf: Button = page.find_child("WardrobeCard_gold_leaf", true, false)
	_check(leaf != null and (leaf.get_theme_stylebox("normal") as StyleBoxFlat).border_color == TierFrame.frame("earned") and leaf.find_child("WardrobeNotForSale", true, false) != null, "An earned item has the Earned frame and the Not for sale chip")
	var pip: Control = page.find_child("WardrobePip", true, false)
	t.flow.set_view("friend")
	await process_frame
	var friend: Control = page.find_child("WardrobePip", true, false)
	_check(friend != pip and friend._color == SpiritLook.MINT and t.flow.model().view == "friend", "As your friend sees you: the pip is mint")
	t.flow.set_view("you")
	_check((page.find_child("WardrobePip", true, false) as Control)._color == SpiritLook.PEACH, "Your pip: peach again")
	_check(PlayerCopy.WARDROBE_DRAG in _texts(page), "Drag to turn your pip.")
	_check(PlayerCopy.WARDROBE_NOTE == "Customize your little pip!" and PlayerCopy.WARDROBE_NOTE in _texts(page), "The header says Customize your little pip!")
	t.host.queue_free()
	await _frames(2)

## Nothing kept and no answer: the page says the wardrobe isn't reachable and offers Try again, which reads again.
func _offline() -> void:
	var t := _setup()
	t.flow.show_wardrobe()
	_check(PlayerCopy.WARDROBE_LOADING in _texts(t.host.overlay), "While the first read is out the page says it is opening")
	await _frames()
	var page: Node = t.host.overlay
	_check(PlayerCopy.WARDROBE_OFFLINE in _texts(page) and (page.find_child("WardrobeRetry", true, false) as Control).visible, "Offline: the page says so and offers Try again")
	_check(page.find_child("PollenChip", true, false) == null and not (page.find_child("WardrobeAction", true, false) as Control).visible, "Offline: no balance it does not know and no button")
	t.fake.replies = [_answer([], {}, 24000)]
	(page.find_child("WardrobeRetry", true, false) as Button).pressed.emit()
	await _frames()
	_check(t.fake.sent.size() == 2 and not PlayerCopy.WARDROBE_OFFLINE in _texts(page) and "24,000" in _texts(page.find_child("WardrobeBalance", true, false)), "Try again reads again and the page fills in")
	t.host.queue_free()
	await _frames(2)

## A refund the server took back leaves the balance below zero: it shows as it is, and Buy says why it can't.
func _negative_balance() -> void:
	var t := _setup()
	t.fake.replies = [_answer([], {}, -2100)]
	t.flow.show_wardrobe()
	await _frames()
	_check("-2,100" in _texts(t.host.overlay.find_child("WardrobeBalance", true, false)), "A balance below zero shows as it is")
	t.flow.set_kind("hat")
	t.flow.select("daisy")
	await t.flow.act("daisy")
	var sheet: Node = t.host.ui.find_child("WardrobeShort", true, false)
	_check(sheet != null and "3,100" + PlayerCopy.WARDROBE_SHORT_MORE in _texts(sheet) and t.fake.sent.size() == 1, "The short card counts the real gap (3,100 more) and nothing is sent")
	t.host.queue_free()
	await _frames(2)

func _wearing() -> void:
	var t := _setup()
	t.store.note_view(SERVER, ME, _answer(["daisy", "tide"], {}, 3000).data)
	t.wallet.note_wallet(SERVER, ME, _answer([], {}, 3000).data)
	t.fake.replies = [_answer(["daisy", "tide"], {}, 3000)]
	t.flow.show_wardrobe()
	await _frames()
	t.flow.select("daisy")
	_check(_texts(t.host.overlay.find_child("WardrobeAction", true, false)) == [PlayerCopy.WARDROBE_WEAR], "An owned item offers Wear")
	t.fake.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "op": "equip", "look": {"hat": "daisy"}, "revision": 9.0e12}}]
	await t.flow.act("daisy")
	_check(t.fake.sent[-1].path == "/v1/pollen/equip" and t.fake.sent[-1].body.look == {"hat": "daisy"}, "Wear sends the whole look")
	_check(t.flow.model().items.filter(func(entry: Dictionary) -> bool: return entry.worn).map(func(entry: Dictionary) -> String: return entry.id) == ["daisy"], "Then it shows as worn")
	_check(_texts(t.host.overlay.find_child("WardrobeAction", true, false)) == [PlayerCopy.WARDROBE_TAKE_OFF], "A worn item offers Take off")
	t.fake.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "op": "equip", "look": {}, "revision": 9.0e12 + 1}}]
	await t.flow.act("daisy")
	_check(t.fake.sent[-1].body.look == {} and t.store.view(SERVER, ME).look.is_empty(), "Take off sends the look without it")
	t.flow.set_tab("owned")
	_check(t.host.overlay.find_child("WardrobeCard_lantern", true, false) == null and t.host.overlay.find_child("WardrobeCard_daisy", true, false) != null, "Owned lists only what the player has")
	t.host.queue_free()
	await _frames(2)

## The same wardrobe on both builds: the one that sells shows the shop, the one that sells nothing only what is owned.
func _owned_only() -> void:
	for sells: bool in [true, false]:
		var t := _setup()
		t.flow.surfaces = PollenSurfaces.new(sells, sells)
		t.store.set_enabled(SERVER, ME, true, true, true)
		t.store.note_view(SERVER, ME, _answer(["daisy"], {}, 3000).data)
		t.wallet.note_wallet(SERVER, ME, _answer([], {}, 3000).data)
		t.fake.replies = [_answer(["daisy"], {}, 3000)]
		t.flow.show_wardrobe()
		await _frames()
		var model: Dictionary = t.flow.model()
		var page: Node = t.host.overlay
		var shelf: Control = page.find_child("WardrobeShelf", true, false)
		var all_tab: Control = page.find_child("WardrobeTab_all", true, false)
		_check(t.flow.available() and "3,000" in _texts(page.find_child("WardrobeBalance", true, false)), "%s: the Wardrobe opens with the balance" % _build(sells))
		if sells:
			_check(model.shop and model.tab == "all" and model.items.size() == 9 and all_tab.visible and shelf.visible and _plus_shown(page), "Selling: the tabs, the shelf, every item and the chip's +")
			_check(t.flow._error_line("not_owned") == PlayerCopy.WARDROBE_ERRORS.not_owned, "Selling: refusals keep their words")
		else:
			_check(not model.shop and not model.bundles and model.tab == "owned" and model.featured.is_empty() and model.items.map(func(entry: Dictionary) -> String: return entry.id) == ["daisy", "gold_leaf", "every_hard", "top_ten_ribbon"], "Selling nothing: the owned item and the earned ones, no shelf, no bundles")
			_check(all_tab.visible and (page.find_child("WardrobeTab_owned", true, false) as Control).visible and not shelf.visible and page.find_child("WardrobeCard_tide", true, false) == null and not _plus_shown(page), "Selling nothing: Owned first with All items for the earned ones, no shelf, no item on sale, no +")
			_check(not _texts(page).any(func(text: String) -> bool: return text.contains("$") or text.contains("Buy") or text.contains("sale") or text.contains("about") or text == PlayerCopy.WARDROBE_STAYS), "Selling nothing: no price anywhere: " + str(_texts(page)))
			t.flow.set_tab("all")
			_check(t.flow.model().tab == "all" and page.find_child("WardrobeCard_tide", true, false) == null and not _texts(page).any(func(text: String) -> bool: return text.contains("Buy") or text.contains("sale")), "Selling nothing: All items holds no item on sale and no sale wording")
			t.flow.set_tab("owned")
			var sent: int = t.fake.sent.size()
			await t.flow.act("tide")
			t.flow.confirm_buy("tide", 20000)
			await _frames()
			_check(t.fake.sent.size() == sent and t.host.ui.get_child_count() == 0, "Selling nothing: an item on sale is never bought and no card opens")
			_check(["not_owned", "pollen_short", "pollen_price_changed"].all(func(code: String) -> bool: return t.flow._error_line(code) == PlayerCopy.WARDROBE_ERROR) and t.flow._error_line("busy") == PlayerCopy.WARDROBE_ERRORS.busy, "Selling nothing: a refusal never says buy or price")
			t.flow.select("daisy")
			_check(_texts(page.find_child("WardrobeAction", true, false)) == [PlayerCopy.WARDROBE_WEAR], "Selling nothing: an owned item offers Wear")
			t.fake.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "op": "equip", "look": {"hat": "daisy"}, "revision": 9.0e12}}]
			await t.flow.act("daisy")
			_check(t.fake.sent[-1].path == "/v1/pollen/equip" and t.fake.sent[-1].body.look == {"hat": "daisy"}, "Selling nothing: Wear sends the look")
			t.store.note_view(SERVER, ME, _answer([], {}, 3000).data)
			t.flow._redraw()
			_check(PlayerCopy.WARDROBE_NOTHING_EARNED in _texts(page) and not PlayerCopy.WARDROBE_NOTHING_OWNED in _texts(page), "Selling nothing: an empty Wardrobe never mentions buying")
		t.host.queue_free()
		await _frames(2)

## The server's wallet read with the wardrobe on and the shop off: owned items only, no prices, no name price.
static func _owned_answer(items: Array, balance: int) -> Dictionary:
	return {"ok": true, "status": 200, "data": {"schema_version": 1.0, "balance": float(balance), "earned": float(balance), "bank": 12.0,
		"wardrobe": {"items": items, "packs": [], "look": {}, "look_revision": 1.0, "offered": ["daisy", "seashell", "straw_hat", "tide", "lantern", "lighthouse_lamp", "gold_leaf", "top_ten_ribbon"]}}}

## The wardrobe on and the shop off on the server, on the build that sells (Android) and the one that sells nothing (iPhone).
func _server_shop_off() -> void:
	for sells: bool in [true, false]:
		var t := _setup(false)
		t.store.set_enabled(SERVER, ME, true, false, true)
		t.wallet.set_enabled(SERVER, ME, true)
		t.flow.surfaces = PollenSurfaces.new(sells, sells)
		var label := "%s, shop off" % _build(sells)
		t.store.note_view(SERVER, ME, _owned_answer(["gold_leaf", "top_ten_ribbon"], 3000).data)
		t.wallet.note_wallet(SERVER, ME, _owned_answer([], 3000).data)
		t.fake.replies = [_owned_answer(["gold_leaf", "top_ten_ribbon"], 3000)]
		_check(t.flow.available() and not t.store.bundles(SERVER, ME), label + ": the Wardrobe opens, and bundles never sell without the shop")
		t.flow.show_wardrobe()
		await _frames()
		var model: Dictionary = t.flow.model()
		var page: Node = t.host.overlay
		_check("3,000" in _texts(page.find_child("WardrobeBalance", true, false)) and not _plus_shown(page), label + ": the balance shows, with no +")
		var ids: Array = model.items.map(func(entry: Dictionary) -> String: return entry.id)
		ids.sort()
		_check(not model.shop and model.tab == "owned" and model.featured.is_empty() and ids == ["gold_leaf", "top_ten_ribbon"], label + ": only the earned items: " + str(ids))
		_check(model.items.all(func(entry: Dictionary) -> bool: return entry.owned and not entry.sold and not entry.locked and int(entry.price) == 0), label + ": nothing on sale, locked or priced")
		_check(not (page.find_child("WardrobeTab_all", true, false) as Control).visible and not (page.find_child("WardrobeShelf", true, false) as Control).visible, label + ": Owned alone and no shelf")
		var words := _texts(page)
		_check(not words.any(func(text: String) -> bool: return text.contains("$") or text.contains("Buy") or text.contains("sale") or text.contains("about")), label + ": no price and no buy wording: " + str(words))
		_check(page.find_child("WardrobeNotForSale", true, false) == null, label + ": no Not for sale chip when nothing is sold")
		t.flow.set_tab("all")
		_check(t.flow.model().tab == "owned", label + ": All items cannot be chosen")
		var sent: int = t.fake.sent.size()
		await t.flow.act("tide")
		t.flow.confirm_buy("tide", 1000)
		await _frames()
		_check(t.fake.sent.size() == sent and t.host.ui.get_child_count() == 0, label + ": nothing is bought and no card opens")
		_check(t.flow._error_line("not_owned") == PlayerCopy.WARDROBE_ERROR, label + ": a refusal never says buy")
		t.flow.select("gold_leaf")
		_check(_texts(page.find_child("WardrobeAction", true, false)) == [PlayerCopy.WARDROBE_WEAR], label + ": an earned item offers Wear")
		t.fake.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "op": "equip", "look": {"leaf": "gold_leaf"}, "revision": 9.0e12}}]
		await t.flow.act("gold_leaf")
		_check(t.fake.sent[-1].path == "/v1/pollen/equip" and t.fake.sent[-1].body.look == {"leaf": "gold_leaf"}, label + ": Wear sends the look")
		t.store.note_view(SERVER, ME, _owned_answer([], 3000).data)
		t.flow._redraw()
		_check(PlayerCopy.WARDROBE_NOTHING_EARNED in _texts(page) and not PlayerCopy.WARDROBE_NOTHING_OWNED in _texts(page), label + ": the empty Wardrobe says " + PlayerCopy.WARDROBE_NOTHING_EARNED)
		t.host.queue_free()
		await _frames(2)

func _empty_lists() -> void:
	var t := _setup()
	t.flow.show_wardrobe()
	var page: Node = t.host.overlay
	_check(_empty(page) == null, "Empty lists: no drawing while the first read is out")
	await _frames()
	_check(_empty(page) == null and PlayerCopy.WARDROBE_OFFLINE in _texts(page), "Empty lists: offline says so, with no drawing")
	t.fake.replies = [_answer([], {}, 24000)]
	await t.flow.refresh()
	_check(_empty(page) == null and (page.find_child("WardrobeItems", true, false) as Control).visible, "Empty lists: none while things are on sale")
	t.flow.set_tab("owned")
	var empty: Control = _empty(page)
	_check(empty != null and empty.art == "wardrobe" and _texts(page).count(PlayerCopy.WARDROBE_NOTHING_OWNED) == 1 and not (page.find_child("WardrobeItems", true, false) as Control).visible, "Nothing owned: the drawing with its line, once")
	await _frames(3)
	var drawn: int = empty.draw_count if empty != null else -1
	t.flow._redraw()
	await _frames(20)
	_check(drawn >= 1 and _empty(page) == empty and empty.draw_count == drawn, "Nothing owned: a redraw with nothing new keeps the drawing, and idle frames draw nothing")
	t.flow.set_tab("all")
	_check(_empty(page) == null and (page.find_child("WardrobeItems", true, false) as Control).visible, "Back to All items: the drawing goes and the items show again")
	t.flow.set_tab("owned")
	var bare: Dictionary = _answer([], {}, 24000).data
	bare.wardrobe.offered = []
	t.store.note_view(SERVER, ME, bare)
	t.flow.set_tab("all")
	empty = _empty(page)
	_check(empty != null and empty.art == "wardrobe" and PlayerCopy.WARDROBE_NOTHING_IN_SHOP in _texts(page) and not (page.find_child("WardrobeShelf", true, false) as Control).visible, "Nothing in the shop: the drawing with its line")
	t.flow.set_tab("owned")
	_check(_texts(page).has(PlayerCopy.WARDROBE_NOTHING_OWNED) and not _texts(page).has(PlayerCopy.WARDROBE_NOTHING_IN_SHOP), "Both tabs empty: switching tabs changes the line")
	t.store.set_enabled(SERVER, ME, true, false, true)
	t.flow._redraw()
	empty = _empty(page)
	_check(empty != null and empty.art == "wardrobe" and PlayerCopy.WARDROBE_NOTHING_EARNED in _texts(page) and not PlayerCopy.WARDROBE_NOTHING_OWNED in _texts(page), "The shop off: the drawing says what you earn shows here")
	t.host.queue_free()
	await _frames(2)

func _get_more() -> void:
	var t := _setup()
	t.store.note_view(SERVER, ME, _answer(["daisy", "gold_leaf"], {}, 24000).data)
	t.wallet.note_wallet(SERVER, ME, _answer([], {}, 24000).data)
	t.fake.replies = [_answer(["daisy", "gold_leaf"], {}, 24000)]
	t.flow.show_wardrobe()
	await _frames()
	var page: Node = t.host.overlay
	_check(page.find_child("WardrobeGetMore", true, false) == null, "Get more: not on All items")
	t.flow.set_tab("owned")
	var kinds: Array = t.flow.model().kinds
	_check(kinds == ["hat", "leaf"], "Get more: Owned has the Hat and Leaf chips: " + str(kinds))
	for kind: String in kinds:
		t.flow.set_kind(kind)
		var grid: Node = page.find_child("WardrobeItems", true, false)
		var tile: Button = page.find_child("WardrobeGetMore", true, false)
		_check(tile != null and tile.get_parent() == grid and grid.get_child(-1) == tile and grid.get_child_count() == 2 and tile.custom_minimum_size == Page.CARD_SIZE, "Get more: the last card on Owned %s, an item card's size" % kind)
		_check(tile != null and _texts(tile) == [PlayerCopy.WARDROBE_GET_MORE] and tile.accessibility_name == PlayerCopy.WARDROBE_GET_MORE and tile.find_child("PipAvatar*", true, false) == null and tile.find_children("*", "SubViewport", true, false).is_empty(), "Get more: its words and the hanger drawing, with no pip render on %s" % kind)
	t.flow.select("gold_leaf")
	var picked: Button = page.find_child("WardrobeGetMore", true, false)
	_check(picked != null and (picked.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.a == 0.0 and (picked.get_theme_stylebox("normal") as StyleBoxFlat).border_width_left == 0, "Get more: picking an item leaves the card's dashed look alone")
	picked.pressed.emit()
	var model: Dictionary = t.flow.model()
	_check(model.tab == "all" and model.kind == "hat" and page.find_child("WardrobeGetMore", true, false) == null, "Get more on Leaf (nothing more to buy there): All items on Hat: %s %s" % [model.tab, model.kind])
	t.flow.set_tab("owned")
	t.flow.set_kind("hat")
	page.find_child("WardrobeGetMore", true, false).pressed.emit()
	model = t.flow.model()
	_check(model.tab == "all" and model.kind == "hat" and page.find_child("WardrobeCard_seashell", true, false) != null, "Get more on Hat: All items on Hat")
	t.flow.set_tab("owned")
	_check(t.flow.model().more and page.find_child("WardrobeGetMore", true, false) != null, "Get more: back on Owned")
	t.store.set_enabled(SERVER, ME, true, false, true)
	t.flow._redraw()
	_check(not t.flow.model().more and page.find_child("WardrobeGetMore", true, false) == null, "Get more: gone when the shop turns off while Owned shows")
	t.store.set_enabled(SERVER, ME, true, true, false)
	t.store.note_view(SERVER, ME, _answer(SOLD + ["gold_leaf"], {}, 24000).data)
	t.flow.set_tab("owned")
	_check(page.find_child("WardrobeGetMore", true, false) == null, "Get more: none once everything on sale is owned")
	t.store.note_view(SERVER, ME, _answer([], {}, 24000).data)
	t.flow._redraw()
	_check(page.find_child("WardrobeGetMore", true, false) == null and _empty(page) != null, "Get more: none on an empty Owned, which keeps its drawing")
	t.host.queue_free()
	await _frames(2)
	for sells: bool in [true, false]:
		var off := _setup(false)
		off.store.set_enabled(SERVER, ME, true, false, true)
		off.wallet.set_enabled(SERVER, ME, true)
		off.flow.surfaces = PollenSurfaces.new(sells, sells)
		off.store.note_view(SERVER, ME, _owned_answer(["gold_leaf", "top_ten_ribbon"], 3000).data)
		off.fake.replies = [_owned_answer(["gold_leaf", "top_ten_ribbon"], 3000)]
		off.flow.show_wardrobe()
		await _frames()
		_check(off.flow.model().tab == "owned" and off.host.overlay.find_child("WardrobeCard_gold_leaf", true, false) != null and off.host.overlay.find_child("WardrobeGetMore", true, false) == null, "%s, shop off: no Get more" % _build(sells))
		off.flow.show_more("hat")
		_check(off.flow.model().tab == "owned", "%s, shop off: Get more never opens All items" % _build(sells))
		off.host.queue_free()
		await _frames(2)

## The page's empty list drawing, or null.
static func _empty(page: Node) -> Control:
	var found: Array = page.find_children("EmptyState", "", true, false).filter(func(node: Node) -> bool: return not node.is_queued_for_deletion())
	return found[0] if found.size() == 1 else null

## Whether the balance chip's + shows.
static func _plus_shown(page: Node) -> bool:
	var plus: Node = page.find_child("PollenChipPlus", true, false)
	return plus != null and (plus as Control).is_visible_in_tree()

static func _build(sells: bool) -> String:
	return "Selling" if sells else "Selling nothing"

## Whether nothing visible under `node` names money ("$" or "about").
static func _no_money(node: Node) -> bool:
	return not _texts(node).any(func(text: String) -> bool: return text.contains("$") or text.contains("about"))

## The gift's longer words show only while they fit: the total alone on a narrow line, the words on a wide one.
func _gets_fit() -> void:
	for row: Array in [[150.0, "138,000" + PlayerCopy.WARDROBE_SHORT_BUNDLE_GETS], [900.0, "138,000" + PlayerCopy.WARDROBE_SHORT_BUNDLE_GETS_GIFT]]:
		var holder := Control.new()
		root.add_child(holder)
		var line: HBoxContainer = Sheets._gets_line(138000, true)
		holder.add_child(line)
		line.size = Vector2(row[0], 24)
		await _frames(3)
		var value: Label = line.find_child("PollenAmountValue", true, false)
		_check(value.text == row[1] and line.size.x <= row[0] + 0.5, "At %d px the line says %s" % [row[0], value.text])
		holder.queue_free()
	await _frames(2)

## Every visible word under `node`.
static func _texts(node: Node) -> Array:
	var out: Array = []
	if node == null: return out
	if node is CanvasItem and not (node as CanvasItem).visible: return out
	if (node is Label or node is Button) and not str(node.text).is_empty(): out.append(node.text)
	for child: Node in node.get_children(): out.append_array(_texts(child))
	return out

## Earned items in All items on the build that sells: every one the server
## offers, on its slot chip, locked with no price; picking one tries it on and
## says how it is earned; nothing buys it, features it or counts it as more to buy.
func _earned_in_shop() -> void:
	var earned := ["gold_leaf", "every_hard", "top_ten_ribbon"]
	var t := _setup()
	t.store.note_view(SERVER, ME, _answer(["daisy"], {}, 100).data)
	t.wallet.note_wallet(SERVER, ME, _answer([], {}, 100).data)
	t.fake.replies = [_answer(["daisy"], {}, 100)]
	t.flow.show_wardrobe()
	await _frames()
	var page: Node = t.host.overlay
	var model: Dictionary = t.flow.model()
	var rows: Array = model.items.filter(func(entry: Dictionary) -> bool: return entry.id in earned)
	_check(model.tab == "all" and rows.size() == 3 and rows.all(func(entry: Dictionary) -> bool: return not entry.owned and not entry.sold and int(entry.price) == 0 and not entry.locked and entry.tier == "earned"), "Earned in the shop: all three listed, not owned, not sold, no price")
	_check(rows.all(func(entry: Dictionary) -> bool: return entry.earn == Catalog.earn(entry.id) and not str(entry.earn).is_empty()), "Earned in the shop: each row carries how it is earned")
	for kind: Array in [["leaf", ["gold_leaf", "every_hard"]], ["hat", ["top_ten_ribbon"]]]:
		t.flow.set_kind(kind[0])
		for id: String in kind[1]:
			var card: Button = page.find_child("WardrobeCard_" + id, true, false)
			_check(card != null and card.find_child("WardrobeNotForSale", true, false) != null and card.find_child("PollenMark", true, false) == null and card.find_child("WardrobeTag", true, false) == null and _texts(card).has(TierFrame.word("earned")), "Earned in the shop: %s on the %s chip with the Earned word and lock, no price, no Yours: %s" % [id, kind[0], _texts(card)])
	_check(t.flow.model().kinds == ["hat", "body", "leaf"], "Earned in the shop: the Leaf chip shows for the earned leaves")
	var weeks_clean := true
	for week: int in range(0, 60):
		t.flow.week = week
		if (t.flow.model().featured as Array).any(func(id: String) -> bool: return id in earned): weeks_clean = false
	t.flow.week = 3
	_check(weeks_clean, "Earned in the shop: never on the Featured shelf, any week")
	for id: String in earned:
		t.flow.select(id)
		var action: Control = page.find_child("WardrobeAction", true, false)
		var note: Label = page.find_child("WardrobeItemNote", true, false)
		_check(not action.visible and note.visible and note.text == Catalog.earn(id) and (page.find_child("WardrobeItemName", true, false) as Label).text == Catalog.display_name(id), "Earned in the shop: picking %s shows its name and how it is earned, with no button: %s" % [id, note.text])
		_check(t.flow.model().preview.get(Catalog.slot(id), "") == id, "Earned in the shop: picking %s tries it on the big pip" % id)
	_check(PlayerCopy.COSMETIC_GOLD_LEAF_EARN == "Hold first place on any chapter board, together." and PlayerCopy.COSMETIC_EVERY_HARD_EARN == "Clear every chapter on Hard, together." and PlayerCopy.COSMETIC_TOP_TEN_RIBBON_EARN == "Finish in a chapter board's top 10, together.", "Earned in the shop: the three lines")
	t.flow.select("top_ten_ribbon")
	t.flow.set_tab("owned")
	var owned_model: Dictionary = t.flow.model()
	_check(owned_model.selected == "daisy" and not owned_model.preview.has("leaf") and owned_model.preview.get("hat", "") == "daisy" and not (page.find_child("WardrobeItemNote", true, false) as Control).visible, "Earned in the shop: on Owned an earned item picked on All items gives way to what is owned: %s" % [owned_model.selected])
	t.flow.set_tab("all")
	_check(t.flow.model().selected == "top_ten_ribbon", "Earned in the shop: back on All items it is picked again")
	var sent: int = t.fake.sent.size()
	await t.flow.act("every_hard")
	await _frames()
	_check(t.fake.sent.size() == sent and t.host.ui.get_child_count() == 0, "Earned in the shop: nothing is sent and no card opens, not even the short card on a low balance")
	t.flow.set_tab("owned")
	_check(not t.flow.model().items.any(func(entry: Dictionary) -> bool: return entry.id in earned and entry.owned) and page.find_child("WardrobeCard_gold_leaf", true, false) == null, "Earned in the shop: Owned lists none of them")
	t.store.note_view(SERVER, ME, _answer(SOLD + ["gold_leaf"], {}, 100).data)
	t.flow._redraw()
	_check(not t.flow.model().more and page.find_child("WardrobeGetMore", true, false) == null and Flow._buyable_slots(t.flow.model().items).is_empty(), "Earned in the shop: with everything on sale owned, the earned ones left never bring Get more")
	t.flow.set_tab("all")
	t.flow.set_kind("leaf")
	var mine: Button = page.find_child("WardrobeCard_gold_leaf", true, false)
	_check(mine != null and PlayerCopy.WARDROBE_OWNED_TAG in _texts(mine) and mine.find_child("WardrobeNotForSale", true, false) != null, "Earned in the shop: an owned one still says Yours: %s" % [_texts(mine)])
	t.flow.select("gold_leaf")
	_check(_texts(page.find_child("WardrobeAction", true, false)) == [PlayerCopy.WARDROBE_WEAR] and not (page.find_child("WardrobeItemNote", true, false) as Control).visible, "Earned in the shop: an owned one offers Wear")
	t.host.queue_free()
	await _frames(2)

## Without the shop (the build that sells nothing, and the server's shop off):
## an earned item not owned shows on All items, which opens beside Owned, with
## its lock and word and no sale wording; with every earned item owned, Owned is alone.
func _earned_without_shop() -> void:
	for sells: bool in [true, false]:
		var t := _setup(false)
		t.store.set_enabled(SERVER, ME, true, false, true)
		t.wallet.set_enabled(SERVER, ME, true)
		t.flow.surfaces = PollenSurfaces.new(sells, sells)
		var label := "%s, shop off" % _build(sells)
		var answer := _answer(["gold_leaf"], {"leaf": "gold_leaf"}, 3000)
		t.store.note_view(SERVER, ME, answer.data)
		t.wallet.note_wallet(SERVER, ME, answer.data)
		t.fake.replies = [answer]
		t.flow.show_wardrobe()
		await _frames()
		var page: Node = t.host.overlay
		var model: Dictionary = t.flow.model()
		_check(not model.shop and model.all_items and model.tab == "owned" and (page.find_child("WardrobeTab_all", true, false) as Control).visible and not (page.find_child("WardrobeStays", true, false) as Control).visible, label + ": opens on Owned, with All items beside it")
		t.flow.set_tab("all")
		model = t.flow.model()
		var ids: Array = model.items.map(func(entry: Dictionary) -> String: return entry.id)
		_check(model.tab == "all" and model.kinds == ["hat", "leaf"] and ids == ["gold_leaf", "every_hard", "top_ten_ribbon"] and page.find_child("WardrobeCard_every_hard", true, false) != null, label + ": All items lists the earned items and nothing on sale: " + str(ids))
		t.flow.set_kind("hat")
		var ribbon: Node = page.find_child("WardrobeCard_top_ten_ribbon", true, false)
		_check(ribbon != null and ribbon.find_child("WardrobeNotForSale", true, false) == null and _texts(ribbon).has(TierFrame.word("earned")) and ribbon.find_child("TierMark", true, false) != null, label + ": an earned card keeps its word and lock mark, with no Not for sale chip")
		t.flow.select("top_ten_ribbon")
		var note: Label = page.find_child("WardrobeItemNote", true, false)
		_check(note.visible and note.text == Catalog.earn("top_ten_ribbon") and not (page.find_child("WardrobeAction", true, false) as Control).visible, label + ": picking one says how it is earned, with no button")
		_check(not _texts(page).any(func(text: String) -> bool: return text.contains("$") or text.contains("Buy") or text.contains("sale") or text.contains("about")), label + ": no sale wording: " + str(_texts(page)))
		var sent: int = t.fake.sent.size()
		await t.flow.act("top_ten_ribbon")
		_check(t.fake.sent.size() == sent and t.host.ui.get_child_count() == 0, label + ": nothing is sent")
		var all_owned := _answer(["gold_leaf", "every_hard", "top_ten_ribbon"], {}, 3000)
		t.store.note_view(SERVER, ME, all_owned.data)
		t.flow._redraw()
		_check(not t.flow.model().all_items and t.flow.model().tab == "owned" and not (page.find_child("WardrobeTab_all", true, false) as Control).visible, label + ": every earned item owned: Owned alone")
		t.host.queue_free()
		await _frames(2)
		var bare := _setup(false)
		bare.store.set_enabled(SERVER, ME, true, false, true)
		bare.wallet.set_enabled(SERVER, ME, true)
		bare.flow.surfaces = PollenSurfaces.new(sells, sells)
		bare.store.note_view(SERVER, ME, _answer([], {}, 3000).data)
		bare.fake.replies = [_answer([], {}, 3000)]
		bare.flow.show_wardrobe()
		await _frames()
		var empty_model: Dictionary = bare.flow.model()
		_check(empty_model.tab == "all" and empty_model.all_items and (bare.host.overlay.find_child("WardrobeTab_owned", true, false) as Control).visible, label + ": nothing owned opens on All items, with Owned one tap away")
		bare.flow.set_tab("owned")
		empty_model = bare.flow.model()
		_check(empty_model.tab == "owned" and str(empty_model.selected).is_empty() and (empty_model.preview as Dictionary).is_empty() and PlayerCopy.WARDROBE_NOTHING_EARNED in _texts(bare.host.overlay), label + ": the empty Owned, one tap away, has nothing picked or tried on")
		bare.host.queue_free()
		await _frames(2)

## The tab the Wardrobe opens on (owner, 2026-11-03): All items while the player
## owns nothing yet, on a build that sells (Android) and one that sells nothing
## (iPhone without a store), from Settings and from Home, even when the first
## read comes after the page opened; Owned stays one tap away and a picked tab
## holds until the page opens again. A player who owns something opens on
## Owned without the shop, and on All items once the shop's switch arrives.
func _start_tab() -> void:
	for sells: bool in [true, false]:
		for from: String in ["settings", "home"]:
			var label := "%s, from %s" % [_build(sells), from]
			var t := _setup(false)
			t.store.set_enabled(SERVER, ME, true, sells, true)
			t.wallet.set_enabled(SERVER, ME, true)
			t.flow.surfaces = PollenSurfaces.new(sells, sells)
			t.fake.replies = [_answer([], {}, 3000), _answer([], {}, 3000)]
			t.flow.show_wardrobe(from)
			await _frames()
			var page: Node = t.host.overlay
			var model: Dictionary = t.flow.model()
			_check(t.fake.sent.size() == 1 and model.tab == "all" and model.all_items and (page.find_child("WardrobeTab_owned", true, false) as Control).visible, label + ": the first read after opening, nothing owned: All items, Owned beside it")
			t.flow.set_tab("owned")
			t.flow._redraw()
			_check(t.flow.model().tab == "owned", label + ": Owned, once picked, holds through a redraw")
			t.flow.show_wardrobe(from)
			await _frames()
			_check(t.flow.model().tab == "all", label + ": opening again starts on All items again")
			t.host.queue_free()
			await _frames(2)
	var keeper := _setup(false)
	keeper.store.set_enabled(SERVER, ME, true, false, false)
	keeper.wallet.set_enabled(SERVER, ME, true)
	keeper.flow.surfaces = PollenSurfaces.new(true, false)
	var answer := _answer(["daisy"], {"hat": "daisy"}, 3000)
	keeper.store.note_view(SERVER, ME, answer.data)
	keeper.wallet.note_wallet(SERVER, ME, answer.data)
	keeper.fake.replies = [answer]
	keeper.flow.show_wardrobe()
	await _frames()
	_check(not keeper.flow.model().shop and keeper.flow.model().tab == "owned", "Something owned, shop off: opens on Owned")
	keeper.store.set_enabled(SERVER, ME, true, true, false)
	keeper.flow._redraw()
	_check(keeper.flow.model().shop and keeper.flow.model().tab == "all", "The shop's switch after opening: All items")
	keeper.host.queue_free()
	await _frames(2)
	# A tap on an item holds the tab: a late read that turns up an owned item never moves the player off it.
	var tapped := _setup(false)
	tapped.store.set_enabled(SERVER, ME, true, false, true)
	tapped.wallet.set_enabled(SERVER, ME, true)
	tapped.flow.surfaces = PollenSurfaces.new(false)
	var empty := _answer([], {}, 3000)
	tapped.store.note_view(SERVER, ME, empty.data)
	tapped.wallet.note_wallet(SERVER, ME, empty.data)
	tapped.fake.replies = [empty]
	tapped.flow.show_wardrobe()
	await _frames()
	tapped.flow.select("every_hard")
	_check(tapped.flow.model().tab == "all" and tapped.flow.model().selected == "every_hard", "Nothing owned: All items, the tapped item picked")
	var late := _answer(["gold_leaf"], {}, 3000)
	tapped.store.note_view(SERVER, ME, late.data)
	tapped.flow._redraw()
	_check(tapped.flow.model().tab == "all" and tapped.flow.model().selected == "every_hard", "A late read with an owned item keeps All items and the tapped item")
	tapped.host.queue_free()
	await _frames(2)

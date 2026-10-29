extends SceneTree
## The Wardrobe on screen (presentation/wardrobe_flow.gd, wardrobe_page.gd,
## wardrobe_sheets.gd), as Pollen board 5b draws it, with a stand-in host and a
## fake transport:
## - it opens only while the server has the wardrobe on, on every build;
## - the page lists what the server sells, with the shelf of the week in its own
##   panel, the slot chips, tier frames, prices with the grain and about $X;
## - the main button says Buy for [grain] N about $X, Wear or Take off; a tap
##   while the wardrobe is still being read waits for the read (first taps);
## - Buy opens the confirm card (the pip, balance, cost with its about line,
##   what is left) and only its Buy sends, at the cost the card showed;
## - a short balance opens the short card (Needed box, It stays in the shop,
##   Keep playing with friends) and sends nothing; its Get Pollen link shows
##   only while bundles sell and never for an Epic or a Special; a Special that
##   is not unlocked cannot be bought;
## - the balance chip's + shows only while bundles sell;
## - the pip switch draws your pip in mint "as your friend sees you";
## - an earned item has the Earned frame and a Not for sale chip;
## - Wear and Take off send the whole look; Back asks the host to leave and
##   remembers where the Wardrobe was opened from;
## - a build without the shop (iOS selling nothing) and a server with the shop
##   off show the same frame with only Owned: no price, no Buy, no shelf, no +.
const Flow = preload("res://presentation/wardrobe_flow.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const WardrobeClient = preload("res://services/wardrobe_client.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const TierFrame = preload("res://presentation/kit/tier_frame.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")

# Synthetic ids only.
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const SERVER := "https://wardrobe-flow.example.test"
const SOLD := ["daisy", "seashell", "straw_hat", "tide", "lantern", "lighthouse_lamp"]

var checks := 0
var failures := 0
var _paths: Array[String] = []

class Host extends Node:
	var api: Node = null
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
	await _page_parts()
	await _offline()
	await _negative_balance()
	await _wearing()
	await _owned_only()
	await _server_shop_off()
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
	_check(model.balance == 24000 and model.items.size() == 6 and t.fake.sent.size() == 1 and t.fake.sent[0].path == "/v1/pollen", "It reads the wardrobe and lists the six items the server sells")
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
	_check(PlayerCopy.WARDROBE_BUY_FOR in words and "20,000" in words and PlayerCopy.WARDROBE_ABOUT % "$3.96" in words and action.find_child("PollenMark", true, false) != null, "Its button says Buy for [grain] 20,000 about $3.96: " + str(words))
	await t.flow.act("tide")
	var sheet: Node = t.host.ui.find_child("WardrobeConfirm", true, false)
	_check(sheet != null and t.fake.sent.size() == 1, "Buy opens the confirm card and sends nothing yet")
	var texts := _texts(sheet)
	_check("24,000" in texts and (PlayerCopy.WARDROBE_COST_LINE % ["Tide", PollenMoney.about(20000)]) in texts and "4,000" in texts and PollenMoney.about(20000) == "$3.96", "The card shows the balance, the cost with about $3.96 and what is left")
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
		var opened := {"count": 0}
		t.flow.store_requested.connect(func() -> void: opened.count += 1)
		t.flow.select("tide")
		await t.flow.act("tide")
		var sheet: Node = t.host.ui.find_child("WardrobeShort", true, false)
		var words := _texts(sheet)
		_check(sheet != null and t.fake.sent.size() == 1, "A short balance opens the short card and sends nothing")
		_check(PlayerCopy.WARDROBE_SHORT_NOTE % ["Tide", "20,000", "14,500"] in words and PlayerCopy.WARDROBE_SHORT_NEEDED in words and "5,500" + PlayerCopy.WARDROBE_SHORT_MORE in words, "It says what it costs, what you have and Needed: 5,500 more: " + str(words))
		_check(PlayerCopy.WARDROBE_SHORT_STAYS in words and PlayerCopy.WARDROBE_SHORT_EARN in words, "It says it stays in the shop and to keep playing with friends")
		_check(not words.any(func(text: String) -> bool: return text.contains("$") or text.contains("Pinch") or text.contains("Basket") or text.contains("week") or text.contains("day")), "It never names a bundle or a time to earn it")
		var link: BaseButton = sheet.find_child("WardrobeGetPollen", true, false)
		_check((link != null) == bundles, "Get Pollen shows only while bundles sell (%s)" % bundles)
		if link != null:
			link.pressed.emit()
			await _frames(2)
			_check(opened.count == 1 and t.host.ui.find_child("WardrobeShort", true, false) == null, "Get Pollen closes the card and asks for the Pollen store")
		for id: String in ["lantern"]:
			t.flow.select(id)
			await t.flow.act(id)
			var epic: Node = t.host.ui.find_child("WardrobeShort", true, false)
			_check(epic != null and epic.find_child("WardrobeGetPollen", true, false) == null, "Short of Pollen for an Epic: never a Get Pollen link")
		_check(t.flow.model().get("bundles") == bundles, "The model says whether bundles sell")
		t.host.queue_free()
		await _frames(2)
	# A Special's short card never links either (unlocked here so it is buyable).
	var s := _setup(true, true)
	s.fake.replies = [_answer([], {}, 500, ["lighthouse_lamp"])]
	s.flow.show_wardrobe()
	await _frames()
	s.flow.select("lighthouse_lamp")
	await s.flow.act("lighthouse_lamp")
	var special: Node = s.host.ui.find_child("WardrobeShort", true, false)
	_check(special != null and special.find_child("WardrobeGetPollen", true, false) == null, "Short of Pollen for a Special: never a Get Pollen link")
	s.host.queue_free()
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
	_check(_texts(lantern).has(TierFrame.word("epic")) and lantern.find_child("TierMark", true, false) != null and lantern.find_child("PollenMark", true, false) != null and PlayerCopy.WARDROBE_ABOUT % "$9.90" in _texts(lantern), "A card has the tier mark and word, the grain and about $X")
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
			_check(model.shop and model.tab == "all" and model.items.size() == 6 and all_tab.visible and shelf.visible and _plus_shown(page), "Selling: the tabs, the shelf, every item and the chip's +")
			_check(t.flow._error_line("not_owned") == PlayerCopy.WARDROBE_ERRORS.not_owned, "Selling: refusals keep their words")
		else:
			_check(not model.shop and not model.bundles and model.tab == "owned" and model.featured.is_empty() and model.items.map(func(entry: Dictionary) -> String: return entry.id) == ["daisy"], "Selling nothing: only the owned item, no shelf, no bundles")
			_check(not all_tab.visible and (page.find_child("WardrobeTab_owned", true, false) as Control).visible and not shelf.visible and page.find_child("WardrobeCard_tide", true, false) == null and not _plus_shown(page), "Selling nothing: Owned alone, no shelf, no item on sale, no +")
			_check(not _texts(page).any(func(text: String) -> bool: return text.contains("$") or text.contains("Buy") or text.contains("sale") or text.contains("about") or text == PlayerCopy.WARDROBE_STAYS), "Selling nothing: no price anywhere: " + str(_texts(page)))
			t.flow.set_tab("all")
			_check(t.flow.model().tab == "owned", "Selling nothing: All items cannot be chosen")
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

## Whether the balance chip's + shows.
static func _plus_shown(page: Node) -> bool:
	var plus: Node = page.find_child("PollenChipPlus", true, false)
	return plus != null and (plus as Control).is_visible_in_tree()

static func _build(sells: bool) -> String:
	return "Selling" if sells else "Selling nothing"

## Every visible word under `node`.
static func _texts(node: Node) -> Array:
	var out: Array = []
	if node == null: return out
	if node is CanvasItem and not (node as CanvasItem).visible: return out
	if (node is Label or node is Button) and not str(node.text).is_empty(): out.append(node.text)
	for child: Node in node.get_children(): out.append_array(_texts(child))
	return out

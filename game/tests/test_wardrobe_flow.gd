extends SceneTree
## The Wardrobe on screen (presentation/wardrobe_flow.gd, wardrobe_page.gd,
## wardrobe_sheets.gd) with a stand-in host and a fake transport:
## - it opens only while the server has the shop on, on every build;
## - the page lists what the server sells, with the shelf of the week;
## - Buy opens the confirm card (balance, cost with its about line, what is
##   left) and only its Buy sends, at the cost the card showed;
## - a short balance opens the short card and sends nothing; a Special that is
##   not unlocked cannot be bought;
## - Wear and Take off send the whole look;
## - Back asks the host to leave;
## - a build without the shop (services/pollen_surfaces.gd, iOS selling
##   nothing) lists only what the player owns, with the balance, and Wear and
##   Take off; no All items tab, no shelf, no price, and nothing is bought.
const Flow = preload("res://presentation/wardrobe_flow.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const WardrobeClient = preload("res://services/wardrobe_client.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")

# Synthetic ids only.
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const SERVER := "https://wardrobe-flow.example.test"

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
	func call_it(method: int, path: String, body: Dictionary) -> Dictionary:
		sent.append({"method": method, "path": path, "body": body.duplicate(true)})
		await tree.process_frame
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

static func _answer(items: Array, look: Dictionary, balance: int, unlocked: Array = []) -> Dictionary:
	return {"ok": true, "status": 200, "data": {"schema_version": 1.0, "balance": float(balance), "earned": float(balance), "bank": 12.0, "name_price": 0.0,
		"wardrobe": {"items": items, "packs": [], "look": look, "look_revision": 1.0, "offered": ["daisy", "seashell", "straw_hat", "tide", "lantern", "lighthouse_lamp"],
			"offered_packs": [], "sets": {}, "unlocked": unlocked}}}

func _frames(count: int = 6) -> void:
	for i in range(count): await process_frame

func _setup(on: bool = true) -> Dictionary:
	var host := Host.new()
	host.overlay = Control.new()
	host.ui = Control.new()
	host.overlay.size = Vector2(1280, 720)
	host.ui.size = Vector2(1280, 720)
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
	flow.surfaces = PollenSurfaces.new(true)
	# The shared wardrobe releases what the server offers (services/wardrobe.gd); the flow here uses its own store.
	preload("res://services/cosmetic_catalog.gd").set_offered(["daisy", "seashell", "straw_hat", "tide", "lantern", "lighthouse_lamp"])
	if on:
		store.set_enabled(SERVER, ME, true)
		wallet.set_enabled(SERVER, ME, true)
	return {"host": host, "store": store, "wallet": wallet, "fake": fake, "flow": flow}

func _run() -> void:
	await _gates()
	await _buying()
	await _wearing()
	await _owned_only()
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	preload("res://services/cosmetic_catalog.gd").set_offered([])
	print("AFTER YOU WARDROBE FLOW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _gates() -> void:
	var off := _setup(false)
	_check(not off.flow.available(), "No Wardrobe while the server has the shop off")
	off.flow.show_wardrobe()
	_check(off.host.overlay.get_child_count() == 0 and off.fake.sent.is_empty(), "Opening it then shows and sends nothing")
	var hidden := _setup()
	hidden.flow.surfaces = PollenSurfaces.new(false)
	_check(hidden.flow.available(), "A build that sells nothing still has the Wardrobe")
	off.host.queue_free()
	hidden.host.queue_free()
	await _frames(2)

func _buying() -> void:
	var t := _setup()
	t.fake.replies = [_answer([], {}, 24000)]
	t.flow.show_wardrobe()
	_check(t.host.mode == Flow.MODE_WARDROBE and t.flow.is_open(), "The page opens")
	await _frames()
	var model: Dictionary = t.flow.model()
	_check(model.balance == 24000 and model.items.size() == 6 and t.fake.sent.size() == 1 and t.fake.sent[0].path == "/v1/pollen", "It reads the wardrobe and lists the six items the server sells")
	_check(model.featured == ["daisy", "seashell", "straw_hat", "lighthouse_lamp"] or (model.featured.size() == 4 and model.featured[3] == "lighthouse_lamp"), "Week 3's shelf: the Commons, the Uncommon and the Special in the top slot")
	_check(t.host.overlay.find_child("WardrobeCard_tide", true, false) != null and t.host.overlay.find_child("WardrobeFeatured", true, false) != null, "Every item and the shelf are drawn")
	var balance: Label = t.host.overlay.find_child("WardrobeBalance", true, false)
	_check(balance != null and balance.text == PlayerCopy.WARDROBE_BALANCE % "24,000", "The balance shows grouped")
	t.flow.select("tide")
	_check(t.flow.model().preview == {"body": "tide"}, "The picked item shows on the big pip")
	var action: Button = t.host.overlay.find_child("WardrobeAction", true, false)
	_check(action.text == PlayerCopy.WARDROBE_BUY % "20,000", "Its button says the price")
	await t.flow.act("tide")
	var sheet: Node = t.host.ui.find_child("WardrobeConfirm", true, false)
	_check(sheet != null and t.fake.sent.size() == 1, "Buy opens the confirm card and sends nothing yet")
	var texts := _texts(sheet)
	_check("24,000" in texts and (PlayerCopy.WARDROBE_COST_LINE % ["Tide", PollenMoney.about(20000)]) in texts and "4,000" in texts and PollenMoney.about(20000) == "$3.96", "The card shows the balance, the cost with about $3.96 and what is left")
	t.fake.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "op": "spend", "kind": "item", "id": "tide", "pieces": ["tide"], "cost": 20000.0, "balance": 4000.0}}]
	await t.flow.confirm_buy("tide", 20000)
	_check(t.fake.sent.size() == 2 and t.fake.sent[1].path == "/v1/pollen/spend" and t.fake.sent[1].body.expected_cost == 20000 and t.fake.sent[1].body.id == "tide", "Its Buy sends the purchase at the cost the card showed")
	_check("tide" in t.store.view(SERVER, ME).items and t.flow.model().balance == 4000 and PlayerCopy.WARDROBE_BOUGHT % "Tide" in t.host.toasts, "Then it is owned, the balance follows, and the player is told")
	t.flow.select("lantern")
	await t.flow.act("lantern")
	_check(t.host.ui.find_child("WardrobeShort", true, false) != null and t.fake.sent.size() == 2, "A short balance opens the short card and sends nothing")
	_check(PlayerCopy.WARDROBE_SHORT_NEED % "46,000" in _texts(t.host.ui.find_child("WardrobeShort", true, false)), "It says how much more is needed")
	var lamp: Dictionary = t.flow._entry("lighthouse_lamp")
	_check(lamp.locked and str(lamp.unlock_name) != "sleeping-lighthouse", "A Special waits for its chapter, named by title")
	await t.flow.act("lighthouse_lamp")
	_check(t.fake.sent.size() == 2, "A locked Special cannot be bought")
	var back := {"asked": false}
	t.flow.back_requested.connect(func() -> void: back.asked = true)
	(t.host.overlay.find_child("WardrobeBack", true, false) as Button).pressed.emit()
	_check(back.asked, "Back asks the host to leave")
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
	_check((t.host.overlay.find_child("WardrobeAction", true, false) as Button).text == PlayerCopy.WARDROBE_WEAR, "An owned item offers Wear")
	t.fake.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "op": "equip", "look": {"hat": "daisy"}, "revision": 9.0e12}}]
	await t.flow.act("daisy")
	_check(t.fake.sent[-1].path == "/v1/pollen/equip" and t.fake.sent[-1].body.look == {"hat": "daisy"}, "Wear sends the whole look")
	_check(t.flow.model().items.filter(func(entry: Dictionary) -> bool: return entry.worn).map(func(entry: Dictionary) -> String: return entry.id) == ["daisy"], "Then it shows as worn")
	t.fake.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "op": "equip", "look": {}, "revision": 9.0e12 + 1}}]
	await t.flow.act("daisy")
	_check(t.fake.sent[-1].body.look == {} and t.store.view(SERVER, ME).look.is_empty(), "Take off sends the look without it")
	t.flow.set_tab("owned")
	_check(t.host.overlay.find_child("WardrobeCard_lantern", true, false) == null and t.host.overlay.find_child("WardrobeCard_tide", true, false) != null, "Owned lists only what the player has")
	t.host.queue_free()
	await _frames(2)

## The same wardrobe on both builds: the one that sells shows the shop, the one that sells nothing only what is owned.
func _owned_only() -> void:
	for sells: bool in [true, false]:
		var t := _setup()
		t.flow.surfaces = PollenSurfaces.new(sells)
		t.store.note_view(SERVER, ME, _answer(["daisy"], {}, 3000).data)
		t.wallet.note_wallet(SERVER, ME, _answer([], {}, 3000).data)
		t.fake.replies = [_answer(["daisy"], {}, 3000)]
		t.flow.show_wardrobe()
		await _frames()
		var model: Dictionary = t.flow.model()
		var page: Node = t.host.overlay
		var tabs: Control = page.find_child("WardrobeTabs", true, false)
		var shelf: Control = page.find_child("WardrobeFeatured", true, false)
		var balance: Label = page.find_child("WardrobeBalance", true, false)
		_check(t.flow.available() and balance != null and balance.text == PlayerCopy.WARDROBE_BALANCE % "3,000", "%s: the Wardrobe opens with the balance" % _build(sells))
		if sells:
			_check(model.shop and model.tab == "all" and model.items.size() == 6 and tabs.visible and shelf.visible, "Selling: the tabs, the shelf and every item")
			_check(page.find_child("WardrobeCard_tide", true, false) != null and PlayerCopy.WARDROBE_PRICE % "20,000" in _texts(page), "Selling: an item on sale shows its price")
			_check(t.flow._error_line("not_owned") == PlayerCopy.WARDROBE_ERRORS.not_owned, "Selling: refusals keep their words")
		else:
			_check(not model.shop and model.tab == "owned" and model.featured.is_empty() and model.items.map(func(entry: Dictionary) -> String: return entry.id) == ["daisy"], "Selling nothing: only the owned item, no shelf")
			_check(not tabs.visible and not shelf.visible and page.find_child("WardrobeCard_tide", true, false) == null, "Selling nothing: no tabs, no shelf, no item on sale")
			_check(not _texts(page).any(func(text: String) -> bool: return text.contains("$") or (text.contains("Pollen") and text != balance.text)), "Selling nothing: no price anywhere: " + str(_texts(page)))
			t.flow.set_tab("all")
			_check(t.flow.model().tab == "owned", "Selling nothing: All items cannot be chosen")
			var sent: int = t.fake.sent.size()
			await t.flow.act("tide")
			t.flow.confirm_buy("tide", 20000)
			await _frames()
			_check(t.fake.sent.size() == sent and t.host.ui.get_child_count() == 0, "Selling nothing: an item on sale is never bought and no card opens")
			_check(["not_owned", "pollen_short", "pollen_price_changed"].all(func(code: String) -> bool: return t.flow._error_line(code) == PlayerCopy.WARDROBE_ERROR) and t.flow._error_line("busy") == PlayerCopy.WARDROBE_ERRORS.busy, "Selling nothing: a refusal never says buy or price")
			t.flow.select("daisy")
			_check((page.find_child("WardrobeAction", true, false) as Button).text == PlayerCopy.WARDROBE_WEAR, "Selling nothing: an owned item offers Wear")
			t.fake.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "op": "equip", "look": {"hat": "daisy"}, "revision": 9.0e12}}]
			await t.flow.act("daisy")
			_check(t.fake.sent[-1].path == "/v1/pollen/equip" and t.fake.sent[-1].body.look == {"hat": "daisy"}, "Selling nothing: Wear sends the look")
			t.store.note_view(SERVER, ME, _answer([], {}, 3000).data)
			t.flow._redraw()
			_check(PlayerCopy.WARDROBE_NOTHING_EARNED in _texts(page) and not PlayerCopy.WARDROBE_NOTHING_OWNED in _texts(page), "Selling nothing: an empty Wardrobe never mentions buying")
		t.host.queue_free()
		await _frames(2)

static func _build(sells: bool) -> String:
	return "Selling" if sells else "Selling nothing"

static func _texts(node: Node) -> Array:
	var out: Array = []
	if node == null: return out
	if node is Label or node is Button: out.append(node.text)
	for child: Node in node.get_children(): out.append_array(_texts(child))
	return out

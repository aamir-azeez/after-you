extends SceneTree
## The Wardrobe offline (services/wardrobe.gd pending, services/wardrobe_client.gd
## sync, presentation/wardrobe_flow.gd), through a fake transport and the
## shared online/offline answer (services/connectivity.gd):
## - a look put on offline is worn on this phone at once (OwnLook, the page),
##   saved with AtomicFile and sent with the equip call once online, with the
##   revision and key fixed when it was put on, so every send is the same equip;
## - the sync rule: the newer intent wins by revision. A server look whose
##   revision reached the pending one (another phone, later) stands and the
##   pending one goes; a pending look newer than the server's is sent and wins;
## - no answer keeps it for the next sync; a refusal drops it and reads again;
##   a look put on while a send is out goes next, only the newest;
## - a deleted identity forgets it and a send in flight changes nothing;
## - buying never queues: offline it is refused and nothing is sent;
## - the page offline: it opens over a saved wardrobe only, wears and takes
##   off, says it is offline, keeps All items browsable with Buy greyed and a
##   line saying why, and reads again and enables Buy once back online;
## - with the server's shop off, owned items stay wearable offline;
## - earned items the saved catalogue offers show offline on All items, locked,
##   saying how they are earned, and nothing is sent;
## - the Orchard offline: its Fruit prices stay browsable from the saved
##   catalogue, a Fruit Buy greys with the same line, its action opens no card
##   and sends nothing, and a Fruit card left open closes when the phone goes offline.
const Wardrobe = preload("res://services/wardrobe.gd")
const WardrobeClient = preload("res://services/wardrobe_client.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const OwnLook = preload("res://services/own_look.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const Connectivity = preload("res://services/connectivity.gd")
const Flow = preload("res://presentation/wardrobe_flow.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const FruitWallet = preload("res://services/fruit_wallet.gd")

# Synthetic ids only.
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const SERVER := "https://wardrobe-offline.example.test"
const SOLD := ["daisy", "seashell", "straw_hat", "tide", "lantern", "lighthouse_lamp"]

var checks := 0
var failures := 0
var _paths: Array[String] = []

class Fake extends RefCounted:
	var tree: SceneTree
	var sent: Array = []
	var replies: Array = []
	var delay := 1
	func call_it(method: int, path: String, body: Dictionary) -> Dictionary:
		sent.append({"method": method, "path": path, "body": body.duplicate(true)})
		for i in range(delay): await tree.process_frame
		var reply: Variant = replies.pop_front() if not replies.is_empty() else {"ok": false, "status": 0, "code": "connection_interrupted"}
		return reply.call(body) if reply is Callable else reply

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

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _path(stem: String) -> String:
	var path := "user://test-wardrobe-offline-%s-%s.json" % [stem, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

func _frames(count: int = 6) -> void:
	for i in range(count): await process_frame

static func wallet(items: Array, look: Dictionary, revision: int, balance: int = 24000, shop: bool = true) -> Dictionary:
	var part := {"items": items, "packs": [], "look": look, "look_revision": float(revision), "offered": SOLD}
	var data := {"schema_version": 1.0, "balance": float(balance), "earned": float(balance), "bank": 12.0, "wardrobe": part}
	if shop:
		data.name_price = 0.0
		part.merge({"offered_packs": [], "sets": {}, "unlocked": []})
	return data

static func receipt(look: Dictionary, revision: int) -> Dictionary:
	return {"ok": true, "status": 200, "data": {"schema_version": 1.0, "op": "equip", "look": look, "revision": float(revision)}}

func _client(store: RefCounted, fake: Fake, state: RefCounted) -> RefCounted:
	var client: RefCounted = WardrobeClient.new(null, func() -> Dictionary: return {"server": SERVER, "owner": ME}, fake.call_it, store, PollenWallet.new(_path("wallet")))
	client.connectivity = state
	return client

func _store(items: Array = ["daisy", "tide", "lantern"], look: Dictionary = {}, revision: int = 5) -> RefCounted:
	var store: RefCounted = Wardrobe.new(_path("store"))
	store.set_enabled(SERVER, ME, true, true)
	store.note_view(SERVER, ME, wallet(items, look, revision))
	return store

func _fake() -> Fake:
	var fake := Fake.new()
	fake.tree = self
	return fake

func _run() -> void:
	Catalog.set_offered(SOLD)
	_store_rules()
	_saved_and_damaged()
	await _offline_then_online()
	await _no_answer_keeps_it()
	await _conflicts()
	await _double_equip()
	await _refused()
	await _deleted_identity()
	await _no_buying_offline()
	await _page()
	await _page_shop_off()
	await _page_earned()
	await _page_orchard()
	await _retry_soon()
	Catalog.set_offered([])
	Connectivity.use_shared(null)
	Wardrobe.use_shared(null)
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU WARDROBE OFFLINE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _store_rules() -> void:
	var store := _store()
	var heard := [0]
	Wardrobe.use_shared(store)
	store.scope_source = func() -> Dictionary: return {"server": SERVER, "owner": ME}
	store.changed.connect(func() -> void: heard[0] += 1)
	_check(store.put_on(SERVER, ME, {"hat": "straw_hat"}, 1000).is_empty(), "An item not owned cannot be put on")
	var none: RefCounted = Wardrobe.new(_path("none"))
	none.set_enabled(SERVER, ME, true)
	_check(none.put_on(SERVER, ME, {"hat": "daisy"}, 1000).is_empty(), "Nothing is put on before the server has said a wardrobe")
	var put: Dictionary = store.put_on(SERVER, ME, {"hat": "daisy"}, 1000)
	_check(put.look == {"hat": "daisy"} and put.revision == 1000 and str(put.key).length() == 32, "A look put on keeps its revision (the clock then) and its own key")
	_check(store.effective_look(SERVER, ME) == {"hat": "daisy"} and store.view(SERVER, ME).look.is_empty(), "It is worn here at once while the confirmed look stays the server's")
	_check(OwnLook.outfit().get("hat") == "daisy" and heard[0] > 0, "Solo play and replays (OwnLook) wear it at once, and the change is announced")
	var again: Dictionary = store.put_on(SERVER, ME, {"hat": "daisy", "body": "tide"}, 900)
	_check(again.revision == 1001 and again.key != put.key, "A later look moves the revision on even when the clock went back, with a new key")
	_check(store.put_on(SERVER, ME, {}, 1).revision == 1002 and store.effective_look(SERVER, ME).is_empty(), "Taking everything off is a look too")
	# The server reaching the pending revision settles it: equal (it landed) or past (another phone, later).
	store.put_on(SERVER, ME, {"body": "tide"}, 5000)
	store.note_view(SERVER, ME, wallet(["daisy", "tide", "lantern"], {"hat": "lantern"}, 4000))
	_check(store.effective_look(SERVER, ME) == {"body": "tide"}, "A server look older than the pending one leaves it pending")
	store.note_view(SERVER, ME, wallet(["daisy", "tide", "lantern"], {"hat": "lantern"}, 6000))
	_check(store.pending(SERVER, ME).is_empty() and store.effective_look(SERVER, ME) == {"hat": "lantern"}, "A server look put on later on another phone stands; the pending one goes")
	store.put_on(SERVER, ME, {"body": "tide"}, 7000)
	store.note_view(SERVER, ME, wallet(["daisy", "lantern"], {}, 6000))
	_check(store.pending(SERVER, ME).is_empty(), "A pending look with an item no longer owned goes")
	var key: String = store.put_on(SERVER, ME, {"hat": "daisy"}, 8000).key
	store.drop_pending(SERVER, ME, "0".repeat(32))
	_check(not store.pending(SERVER, ME).is_empty(), "Dropping another key's look keeps this one")
	store.drop_pending(SERVER, ME, key)
	_check(store.pending(SERVER, ME).is_empty() and store.effective_look(SERVER, ME).is_empty(), "A refused look goes and the confirmed one shows")
	store.put_on(SERVER, ME, {"hat": "daisy"}, 9000)
	_check(store.clear_owner(ME) and store.pending(SERVER, ME).is_empty() and store.effective_look(SERVER, ME).is_empty() and OwnLook.outfit().is_empty(), "Deleting the identity forgets the pending look too")
	Wardrobe.use_shared(null)

func _saved_and_damaged() -> void:
	var path := _path("saved")
	var store: RefCounted = Wardrobe.new(path)
	store.set_enabled(SERVER, ME, true, true)
	store.note_view(SERVER, ME, wallet(["daisy"], {}, 5))
	var put: Dictionary = store.put_on(SERVER, ME, {"hat": "daisy"}, 4242)
	var reread: RefCounted = Wardrobe.new(path)
	_check(reread.pending(SERVER, ME) == put and reread.effective_look(SERVER, ME) == {"hat": "daisy"}, "The pending look is saved and read back after a restart")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var scope_key := Wardrobe.scope_key(SERVER, ME)
	_check(saved.scopes[scope_key].has("pending"), "The pending look is in the saved file")
	for change: Array in [["key", "not-a-key"], ["revision", -3], ["revision", 1.5], ["look", {"shoe": "daisy"}], ["look", "daisy"]]:
		var broken: Dictionary = saved.duplicate(true)
		broken.scopes[scope_key].pending[change[0]] = change[1]
		var damaged := _path("damaged")
		var file := FileAccess.open(damaged, FileAccess.WRITE)
		file.store_string(JSON.stringify(broken))
		file.close()
		var read: RefCounted = Wardrobe.new(damaged)
		_check(read.pending(SERVER, ME).is_empty() and not read.view(SERVER, ME).is_empty(), "A damaged pending look is dropped and the saved wardrobe kept")

func _offline_then_online() -> void:
	var state: RefCounted = Connectivity.new()
	state.force(false)
	var store := _store()
	var fake := _fake()
	var client := _client(store, fake, state)
	var answer: Dictionary = await client.wear({"hat": "daisy"})
	_check(answer.ok and answer.get("pending", false) and fake.sent.is_empty(), "Offline, Wear works here at once and sends nothing")
	var put: Dictionary = store.pending(SERVER, ME)
	_check((await client.sync()).get("pending", false) and fake.sent.is_empty(), "A sync offline waits")
	state.note_reached()
	fake.replies = [func(body: Dictionary) -> Dictionary: return receipt(body.look, int(body.revision))]
	answer = await client.sync()
	_check(fake.sent.size() == 1 and fake.sent[0].path == WardrobeClient.EQUIP_PATH and fake.sent[0].body.idempotency_key == put.key and fake.sent[0].body.revision == put.revision and fake.sent[0].body.look == {"hat": "daisy"}, "Online it goes with the equip call, the key and revision fixed when it was put on")
	_check(answer.ok and not answer.get("pending", false) and store.pending(SERVER, ME).is_empty() and store.view(SERVER, ME).look == {"hat": "daisy"}, "The receipt confirms it")
	await client.sync()
	_check(fake.sent.size() == 1, "With nothing pending a sync sends nothing")

func _no_answer_keeps_it() -> void:
	var state: RefCounted = Connectivity.new()
	var store := _store()
	var fake := _fake()
	var client := _client(store, fake, state)
	fake.replies = [{"ok": false, "status": 0, "code": "connection_interrupted"}]
	var answer: Dictionary = await client.wear({"body": "tide"})
	_check(answer.ok and answer.get("pending", false) and not store.pending(SERVER, ME).is_empty(), "A send with no answer keeps the look for later")
	_check(fake.sent.size() <= WardrobeClient.MAX_SENDS, "It tries at most its sends")
	var first: Dictionary = fake.sent[0].body
	fake.sent.clear()
	# Going offline mid-send stops the retries.
	fake.replies = [func(_body: Dictionary) -> Dictionary:
		state.force(false)
		return {"ok": false, "status": 0, "code": "connection_interrupted"}]
	await client.sync()
	_check(fake.sent.size() == 1 and not store.pending(SERVER, ME).is_empty(), "Once the phone reads as offline no more tries go, and the look is kept")
	state.note_reached()
	fake.replies = [func(body: Dictionary) -> Dictionary: return receipt(body.look, int(body.revision))]
	await client.sync()
	_check(fake.sent[-1].body == first and store.pending(SERVER, ME).is_empty() and store.view(SERVER, ME).look == {"body": "tide"}, "The next sync sends the very same equip (same key, revision and look), and it lands")

func _conflicts() -> void:
	# Another phone put a look on after this one's offline change: the server answers its newer look.
	var state: RefCounted = Connectivity.new()
	state.force(false)
	var store := _store()
	var fake := _fake()
	var client := _client(store, fake, state)
	await client.wear({"hat": "daisy"})
	var put: Dictionary = store.pending(SERVER, ME)
	state.note_reached()
	fake.replies = [receipt({"hat": "lantern"}, int(put.revision) + 60000)]
	await client.sync()
	_check(store.pending(SERVER, ME).is_empty() and store.effective_look(SERVER, ME) == {"hat": "lantern"}, "Server revision past the pending one: the other phone's later look stands")
	# This phone's offline change is newer than the server's: it is sent and wins.
	state.force(false)
	await client.wear({"body": "tide"})
	put = store.pending(SERVER, ME)
	store.note_view(SERVER, ME, wallet(["daisy", "tide", "lantern"], {"hat": "daisy"}, int(put.revision) - 10))
	_check(store.effective_look(SERVER, ME) == {"body": "tide"}, "A wallet read with an older server look keeps the newer pending one")
	state.note_reached()
	fake.replies = [func(body: Dictionary) -> Dictionary: return receipt(body.look, int(body.revision))]
	await client.sync()
	_check(store.view(SERVER, ME).look == {"body": "tide"} and store.pending(SERVER, ME).is_empty(), "Newest intent wins: the pending look is sent and confirmed")
	# A wallet read that already shows the pending revision (it landed, the reply was lost) settles it with no send.
	state.force(false)
	await client.wear({})
	put = store.pending(SERVER, ME)
	store.note_view(SERVER, ME, wallet(["daisy", "tide", "lantern"], {}, int(put.revision)))
	_check(store.pending(SERVER, ME).is_empty(), "A read showing the pending revision settles it")
	state.note_reached()
	var before := fake.sent.size()
	await client.sync()
	_check(fake.sent.size() == before, "Then nothing more is sent")

func _double_equip() -> void:
	var state: RefCounted = Connectivity.new()
	var store := _store()
	var fake := _fake()
	fake.delay = 4
	var client := _client(store, fake, state)
	fake.replies = [func(body: Dictionary) -> Dictionary: return receipt(body.look, int(body.revision)), func(body: Dictionary) -> Dictionary: return receipt(body.look, int(body.revision))]
	client.wear({"hat": "daisy"})
	await process_frame
	await client.wear({"hat": "daisy", "body": "tide"})
	await client.wear({"body": "tide"})
	_check(store.effective_look(SERVER, ME) == {"body": "tide"}, "Every tap shows at once, the last one last")
	for i in range(16): await process_frame
	_check(fake.sent.size() == 2 and fake.sent[1].body.look == {"body": "tide"}, "While one send is out, only the newest look goes next: %s" % [fake.sent.map(func(s: Dictionary) -> Dictionary: return s.body.look)])
	_check(store.pending(SERVER, ME).is_empty() and store.view(SERVER, ME).look == {"body": "tide"} and not client.busy(), "And it ends on the newest look")
	_check(int(fake.sent[1].body.revision) > int(fake.sent[0].body.revision), "Revisions only move forward")

func _refused() -> void:
	var state: RefCounted = Connectivity.new()
	state.force(false)
	var store := _store()
	var fake := _fake()
	var client := _client(store, fake, state)
	await client.wear({"hat": "daisy"})
	state.note_reached()
	fake.replies = [{"ok": false, "status": 409, "code": "not_owned"}, {"ok": true, "status": 200, "data": wallet(["tide"], {}, 9)}]
	await client.sync()
	_check(store.pending(SERVER, ME).is_empty() and fake.sent.size() == 2 and fake.sent[1].path == WardrobeClient.WALLET_PATH, "A refusal drops the look and reads the wardrobe again")
	_check(store.effective_look(SERVER, ME).is_empty() and store.view(SERVER, ME).items == ["tide"], "The page then shows what the server says")
	# Refusals that will pass keep the look: a rate limit, a token problem, an update needed.
	for passing: Dictionary in [{"status": 429, "code": "rate_limited"}, {"status": 401, "code": "invalid_auth"}, {"status": 426, "code": "client_update_required"}]:
		var kept := _store(["daisy", "tide"])
		var again := _fake()
		var keeper := _client(kept, again, state)
		again.replies = [{"ok": false, "status": passing.status, "code": passing.code}]
		var answer: Dictionary = await keeper.wear({"hat": "daisy"})
		_check(answer.ok and answer.get("pending", false) and kept.effective_look(SERVER, ME) == {"hat": "daisy"} and again.sent.size() == 1, "A %d %s keeps the look for the next sync" % [passing.status, passing.code])

func _deleted_identity() -> void:
	var state: RefCounted = Connectivity.new()
	var store := _store()
	var fake := _fake()
	fake.delay = 3
	var client := _client(store, fake, state)
	fake.replies = [func(body: Dictionary) -> Dictionary: return receipt(body.look, int(body.revision))]
	client.wear({"hat": "daisy"})
	await process_frame
	store.clear_owner(ME)
	for i in range(8): await process_frame
	_check(store.view(SERVER, ME).is_empty() and store.pending(SERVER, ME).is_empty() and store.effective_look(SERVER, ME).is_empty(), "A reply after the identity was deleted brings nothing back")
	_check((await client.wear({"hat": "daisy"})).code == "pollen_wardrobe_disabled", "Nothing is put on for a deleted identity")

func _no_buying_offline() -> void:
	var state: RefCounted = Connectivity.new()
	state.force(false)
	var store := _store()
	var fake := _fake()
	var client := _client(store, fake, state)
	var answer: Dictionary = await client.buy("item", "straw_hat", 1000)
	_check(not answer.ok and answer.code == "offline" and fake.sent.is_empty(), "Buying offline is refused and nothing is sent or queued")

func _setup_page(state: RefCounted, saved: bool, shop: bool = true) -> Dictionary:
	var host := Host.new()
	host.overlay = Control.new()
	host.ui = Control.new()
	host.overlay.size = Vector2(1560, 720)
	host.ui.size = Vector2(1560, 720)
	root.add_child(host)
	host.add_child(host.overlay)
	host.add_child(host.ui)
	host.scope = {"server": SERVER, "owner": ME}
	var store: RefCounted = Wardrobe.new(_path("page"))
	var purse: RefCounted = PollenWallet.new(_path("purse"))
	store.set_enabled(SERVER, ME, true, shop)
	purse.set_enabled(SERVER, ME, true)
	if saved:
		var data := wallet(["daisy", "tide"], {"body": "tide"}, 5, 24000, shop)
		store.note_view(SERVER, ME, data)
		purse.note_wallet(SERVER, ME, data)
	var fake := _fake()
	var flow: Node = Flow.new(host)
	host.add_child(flow)
	flow.client = WardrobeClient.new(null, host._names_scope, fake.call_it, store, purse)
	flow.client.connectivity = state
	flow.surfaces = PollenSurfaces.new(true, true)
	flow.week = 3
	return {"host": host, "store": store, "fake": fake, "flow": flow}

func _page() -> void:
	var state: RefCounted = Connectivity.new()
	Connectivity.use_shared(state)
	state.force(false)
	var empty := _setup_page(state, false)
	_check(not empty.flow.available(), "Offline with nothing saved the Wardrobe does not show")
	state.note_reached()
	_check(empty.flow.available(), "Online it shows (it reads the wardrobe)")
	empty.host.queue_free()
	state.force(false)
	var t := _setup_page(state, true)
	_check(t.flow.available(), "Offline over a saved wardrobe the Wardrobe shows")
	t.flow.show_wardrobe("home")
	await _frames()
	var page: Node = t.host.overlay
	_check(t.fake.sent.is_empty(), "Opening it offline sends nothing")
	_check(PlayerCopy.WARDROBE_OFFLINE_NOTE in _texts(page) and not (page.find_child("WardrobeRetry", true, false) as Control).visible, "It says it is offline, with no Try again over a saved wardrobe")
	_check(page.find_child("PollenChipPlusButton", true, false) == null, "No Pollen store plus offline")
	t.flow.set_tab("owned")
	t.flow.select("daisy")
	await t.flow.act("daisy")
	_check(t.fake.sent.is_empty() and t.flow.model().items.filter(func(entry: Dictionary) -> bool: return entry.worn).map(func(entry: Dictionary) -> String: return entry.id).has("daisy"), "Owned: Wear works offline and shows as worn")
	_check(_texts(page.find_child("WardrobeAction", true, false)) == [PlayerCopy.WARDROBE_TAKE_OFF], "The worn item offers Take off")
	t.flow.select("tide")
	await t.flow.act("tide")
	_check(not t.flow.model().items.any(func(entry: Dictionary) -> bool: return entry.id == "tide" and entry.worn), "Take off works offline too")
	t.flow.set_tab("all")
	_check(t.flow.model().tab == "all" and t.flow.model().buy_offline, "All items stays browsable from the saved catalogue")
	t.flow.select("straw_hat")
	var action: Button = page.find_child("WardrobeAction", true, false)
	_check(action.visible and action.disabled and PlayerCopy.WARDROBE_CONNECT_TO_BUY in _texts(page), "Buy greys and says it needs a connection")
	await t.flow.act("straw_hat")
	_check(t.fake.sent.is_empty() and t.host.ui.get_child_count() == 0 and t.host.toasts.has(PlayerCopy.OFFLINE_NEEDS_CONNECTION), "Buy offline opens no card, sends nothing and says why")
	await t.flow.confirm_buy("straw_hat", 1000)
	_check(t.fake.sent.is_empty(), "A confirm that lands offline sends nothing")
	# Back online: the look goes, the page reads again, Buy comes back.
	t.fake.replies = [func(body: Dictionary) -> Dictionary: return receipt(body.look, int(body.revision)), {"ok": true, "status": 200, "data": wallet(["daisy", "tide"], {"hat": "daisy"}, 9000000000000)}]
	state.note_reached()
	t.flow.connectivity_changed(true)
	await _frames(10)
	_check(t.fake.sent.size() >= 2 and t.fake.sent[0].path == WardrobeClient.EQUIP_PATH and t.fake.sent[0].body.look == {"hat": "daisy"}, "Back online the look put on offline goes first")
	_check(t.store.pending(SERVER, ME).is_empty() and not t.flow.model().buy_offline and not action.disabled and not PlayerCopy.WARDROBE_OFFLINE_NOTE in _texts(page), "Then Buy comes back and the offline line goes")
	t.host.queue_free()
	await _frames(2)

func _page_shop_off() -> void:
	var state: RefCounted = Connectivity.new()
	Connectivity.use_shared(state)
	state.force(false)
	var t := _setup_page(state, true, false)
	t.flow.show_wardrobe()
	await _frames()
	_check(t.flow.model().tab == "owned" and not t.flow.model().buy_offline, "Shop off: only Owned, nothing to buy")
	t.flow.select("daisy")
	await t.flow.act("daisy")
	_check(t.store.effective_look(SERVER, ME).get("hat") == "daisy" and t.fake.sent.is_empty(), "Shop off: owned items are still wearable offline")
	t.host.queue_free()
	await _frames(2)

func _page_earned() -> void:
	var state: RefCounted = Connectivity.new()
	Connectivity.use_shared(state)
	state.force(false)
	var t := _setup_page(state, false)
	var data := wallet(["daisy"], {}, 5)
	data.wardrobe.offered = SOLD + ["gold_leaf", "every_hard", "top_ten_ribbon"]
	t.store.note_view(SERVER, ME, data)
	t.flow.client.wallet.note_wallet(SERVER, ME, data)
	t.flow.show_wardrobe()
	await _frames()
	t.flow.set_kind("leaf")
	var page: Node = t.host.overlay
	_check(t.flow.model().tab == "all" and page.find_child("WardrobeCard_every_hard", true, false) != null and page.find_child("WardrobeCard_gold_leaf", true, false) != null, "Offline: the earned items show from the saved catalogue")
	t.flow.select("every_hard")
	var note: Label = page.find_child("WardrobeItemNote", true, false)
	_check(note.visible and note.text == Catalog.earn("every_hard") and not (page.find_child("WardrobeAction", true, false) as Control).visible, "Offline: an earned item says how it is earned, with no button")
	await t.flow.act("every_hard")
	_check(t.fake.sent.is_empty() and t.host.ui.get_child_count() == 0 and t.host.toasts.is_empty(), "Offline: tapping an earned item sends nothing and says nothing")
	t.host.queue_free()
	await _frames(2)

## A send that got no answer while still online goes again soon (a few times), not only on the next resume.
func _retry_soon() -> void:
	var state: RefCounted = Connectivity.new()
	Connectivity.use_shared(state)
	var t := _setup_page(state, true)
	t.flow.sync_retry_ms = [30, 30]
	var down := {"ok": false, "status": 503, "code": "unavailable"}
	t.fake.replies = [down, down, down]
	var worn: bool = await t.flow.wear_item("daisy")
	_check(worn and not t.store.pending(SERVER, ME).is_empty() and t.fake.sent.size() == 3, "Server errors keep the look put on (three tries)")
	t.fake.replies = [func(body: Dictionary) -> Dictionary: return receipt(body.look, int(body.revision))]
	await create_timer(0.2).timeout
	await _frames(4)
	_check(t.store.pending(SERVER, ME).is_empty() and t.store.view(SERVER, ME).look.get("hat") == "daisy", "It goes again by itself soon after and lands")
	var sent: int = t.fake.sent.size()
	await create_timer(0.2).timeout
	_check(t.fake.sent.size() == sent, "Then nothing more is sent")
	t.host.queue_free()
	await _frames(2)

static func _texts(node: Node) -> Array:
	var out: Array = []
	if node == null: return out
	if node is CanvasItem and not (node as CanvasItem).visible: return out
	if (node is Label or node is Button) and not str(node.text).is_empty(): out.append(node.text)
	for child: Node in node.get_children(): out.append_array(_texts(child))
	return out

## The Orchard offline over a saved wardrobe with Fruits on.
func _page_orchard() -> void:
	var orchard := ["fruit_cap", "blossom_crown", "orchard_skin", "apple_leaf", "sprig_coral", "sprig_plum", "sprig_sun", "sprig_sky"]
	Catalog.set_offered(SOLD + orchard)
	var state: RefCounted = Connectivity.new()
	Connectivity.use_shared(state)
	state.note_reached()
	var t := _setup_page(state, false)
	var fruits: RefCounted = FruitWallet.new(_path("fruits"))
	fruits.set_enabled(SERVER, ME, true)
	t.flow.client = WardrobeClient.new(null, t.host._names_scope, t.fake.call_it, t.store, PollenWallet.new(_path("orchard-purse")), null, fruits)
	t.flow.client.connectivity = state
	var data := wallet(["daisy"], {}, 5)
	data.wardrobe.offered = SOLD + orchard
	data.wardrobe.fruit_prices = {"fruit_cap": 50, "blossom_crown": 50, "orchard_skin": 100, "apple_leaf": 25, "sprig_coral": 10, "sprig_plum": 10, "sprig_sun": 10, "sprig_sky": 10}
	data.wardrobe.fruit_sets = {"orchard": ["fruit_cap", "orchard_skin", "apple_leaf"]}
	data.fruits = {"schema_version": 1.0, "balance": 101.0, "earned": 101.0, "first_pack_gift": false, "first_pack_percent": 100.0, "achievements": []}
	t.fake.replies = [{"ok": true, "status": 200, "data": data}]
	t.flow.show_wardrobe()
	await _frames()
	t.flow.set_tab("orchard")
	await t.flow.act("fruit_cap")
	_check(t.host.ui.find_child("WardrobeConfirm", true, false) != null, "Online a Fruit Buy opens its confirm card")
	state.force(false)
	t.flow.connectivity_changed(false)
	await _frames(2)
	_check(t.host.ui.find_child("WardrobeConfirm", true, false) == null, "Going offline closes the Fruit card left open")
	var page: Node = t.host.overlay
	_check(t.flow.model().tab == "orchard" and page.find_child("OrchardCard_fruit_cap", true, false) != null and t.flow.model().buy_offline, "Offline the Orchard stays browsable from the saved catalogue")
	var action: Button = page.find_child("WardrobeAction", true, false)
	_check(action.visible and action.disabled and PlayerCopy.WARDROBE_CONNECT_TO_BUY in _texts(page), "A Fruit Buy greys and says it needs a connection")
	var sends: int = t.fake.sent.size()
	await t.flow.act("fruit_cap")
	_check(t.fake.sent.size() == sends and t.host.ui.get_child_count() == 0 and t.host.toasts.has(PlayerCopy.OFFLINE_NEEDS_CONNECTION), "Its action offline opens no card, sends nothing and says why")
	await t.flow.confirm_buy("orchard", 145, "set")
	_check(t.fake.sent.size() == sends, "A set confirm that lands offline sends nothing")
	t.host.queue_free()
	Catalog.set_offered(SOLD)
	await _frames(2)

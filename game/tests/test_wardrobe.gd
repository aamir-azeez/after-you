extends SceneTree
## The wardrobe on this phone (services/wardrobe.gd), the player's own look
## (services/own_look.gd) and the wardrobe routes' client
## (services/wardrobe_client.gd), through a fake transport:
## - only the contract's shapes are kept; a damaged file reads as empty, and
##   the next wallet read fills it again;
## - an older look never replaces a newer one;
## - the server's offered items release them in the catalogue, so the own pip
##   wears what the server sells, and nothing while the shop is off;
## - a purchase or look that got no answer goes again with the same key and
##   body; a new action gets a new key; an equip revision only moves forward;
## - one action at a time, and an answer saying the phone was out of date reads
##   the wardrobe again;
## - with the wardrobe on and the shop off (POLLEN_WARDROBE alone) the phone
##   keeps owned and earned items and wears them, with no price, no name
##   change price and nothing bought; a file from before the split reads the
##   shop off until the server says again.
const Wardrobe = preload("res://services/wardrobe.gd")
const WardrobeClient = preload("res://services/wardrobe_client.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const OwnLook = preload("res://services/own_look.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const AtomicFile = preload("res://services/atomic_file.gd")

# Synthetic ids only.
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const OTHER := "bbbbbbbbbbbbbbbbbbbbbb"
const SERVER := "https://wardrobe.example.test"

var checks := 0
var failures := 0
var _paths: Array[String] = []

## The API the online session reads capabilities through (synthetic token).
class CapsApi extends Node:
	var base_url := SERVER
	var player_id := ME
	var device_token := "synthetic-device-token"
	var capabilities: Dictionary = {}
	func request_json(_method: int, path: String, _body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		await Engine.get_main_loop().process_frame
		if path == "/v2/capabilities": return {"ok": true, "status": 200, "data": capabilities.duplicate(true)}
		return {"ok": false, "status": 0, "code": "connection_interrupted"}

## The session's room store, in memory.
class MemoryStore extends RefCounted:
	var values: Dictionary = {}
	func load_scope(scope: String) -> Dictionary:
		return {"ok": true, "found": values.has(scope), "value": values.get(scope, {}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		values[scope] = value.duplicate(true)
		return {"ok": true}

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
	var path := "user://test-%s-%s.json" % [stem, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

## A wallet answer with the shop on, as the server sends it (numbers as floats).
static func answer(items: Array = [], look: Dictionary = {}, revision: int = 0, balance: int = 24000, name_price: int = 0) -> Dictionary:
	return {"schema_version": 1.0, "balance": float(balance), "earned": float(balance), "bank": 12.0, "name_price": float(name_price),
		"wardrobe": {"items": items, "packs": [], "look": look, "look_revision": float(revision), "offered": ["daisy", "seashell", "straw_hat", "tide", "lantern", "lighthouse_lamp"],
			"offered_packs": [], "sets": {}, "unlocked": []}}

func _run() -> void:
	_checked_views()
	_file_and_damage()
	_clear_owner()
	_looks_in_order()
	_own_look()
	await _client_retries()
	await _client_one_at_a_time()
	await _client_stale()
	await _name_price()
	await _wardrobe_without_shop()
	_capabilities()
	await _offered_tag_wiring()
	_orchard_prices()
	Catalog.set_offered([])
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU WARDROBE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

## The Orchard's money safety (services/wardrobe.gd sale and set_cost): an
## Orchard item sells only at its Fruit price, never at its tier's price read as
## Pollen; a Pollen item never at a Fruit price; and a set costs what spend.ts
## charges (175 struck to 145 with nothing owned, 125 to 105 with the cap owned,
## one missing piece at its own price).
func _orchard_prices() -> void:
	var fruit_view := {"prices": {"daisy": 1000}, "fruit_prices": {"fruit_cap": 50, "orchard_skin": 100, "apple_leaf": 25, "sprig_sun": 10}, "fruit_sets": {"orchard": ["fruit_cap", "orchard_skin", "apple_leaf"]}, "sets": {}}
	_check(Wardrobe.sale(fruit_view, "fruit_cap") == {"currency": "fruits", "price": 50} and Wardrobe.sale(fruit_view, "sprig_sun") == {"currency": "fruits", "price": 10}, "An Orchard item sells at its Fruit price, in Fruits")
	_check(Wardrobe.sale(fruit_view, "daisy") == {"currency": "pollen", "price": 1000} and Wardrobe.sale(fruit_view, "tide") == {"currency": "pollen", "price": Catalog.price("tide")}, "A Pollen item sells at its Pollen price, its tier's while the server sends none")
	_check(Wardrobe.sale(fruit_view, "blossom_crown").is_empty(), "An Orchard item the server does not price in Fruits is not sold")
	_check(Wardrobe.sale({"prices": {}, "fruit_prices": {}}, "fruit_cap").is_empty() and Catalog.price("fruit_cap") == 50, "With Fruits off an Orchard item is never sold at its tier's 50 read as Pollen")
	_check(Wardrobe.sale({"prices": {"fruit_cap": 50}, "fruit_prices": {"fruit_cap": 50}}, "fruit_cap").is_empty() and Wardrobe.sale({"prices": {"daisy": 1000}, "fruit_prices": {"daisy": 10}}, "daisy").is_empty(), "A price in the other currency than the tier's means not sold")
	_check(Wardrobe.set_cost(fruit_view, "orchard", []) == {"currency": "fruits", "pieces": ["fruit_cap", "orchard_skin", "apple_leaf"], "full": 175, "cost": 145}, "The Orchard set with nothing owned: 175, 15% off rounded down to 5 is 145")
	_check(Wardrobe.set_cost(fruit_view, "orchard", ["fruit_cap"]) == {"currency": "fruits", "pieces": ["orchard_skin", "apple_leaf"], "full": 125, "cost": 105}, "With the Fruit cap owned: 125 for the two left, 105 together")
	_check(Wardrobe.set_cost(fruit_view, "orchard", ["fruit_cap", "orchard_skin"]) == {"currency": "fruits", "pieces": ["apple_leaf"], "full": 25, "cost": 25}, "One missing piece costs its own price")
	_check((Wardrobe.set_cost(fruit_view, "orchard", ["fruit_cap", "orchard_skin", "apple_leaf"]).pieces as Array).is_empty(), "Every piece owned: nothing left to buy")
	var off := fruit_view.duplicate(true)
	(off.fruit_prices as Dictionary).erase("orchard_skin")
	_check(Wardrobe.set_cost(off, "orchard", []).is_empty() and Wardrobe.set_cost(fruit_view, "unknown", []).is_empty(), "A set with a piece not sold, or an unknown set, has no price")
	var pollen_set := {"prices": {"daisy": 1000, "straw_hat": 1000}, "sets": {"meadow": ["daisy", "straw_hat"]}}
	_check(Wardrobe.set_cost(pollen_set, "meadow", []) == {"currency": "pollen", "pieces": ["daisy", "straw_hat"], "full": 2000, "cost": 1700}, "A Pollen set rounds down to 100 as the server does")

## A wallet answer with the wardrobe on and the shop off: no prices, sets, unlocks or name price.
static func owned_answer(items: Array = [], look: Dictionary = {}, revision: int = 0, balance: int = 3000) -> Dictionary:
	return {"schema_version": 1.0, "balance": float(balance), "earned": float(balance), "bank": 12.0,
		"wardrobe": {"items": items, "packs": [], "look": look, "look_revision": float(revision), "offered": ["daisy", "gold_leaf", "top_ten_ribbon"]}}

func _checked_views() -> void:
	var kept := Wardrobe.checked_view(answer(["daisy"], {"hat": "daisy"}, 7, 5000, 1000))
	_check(kept.items == ["daisy"] and kept.look == {"hat": "daisy"} and kept.look_revision == 7 and kept.name_price == 1000, "A wallet answer's wardrobe is kept with whole numbers")
	_check(kept.offered.size() == 6 and kept.sets.is_empty(), "What the server sells is kept as it said")
	var plain := answer()
	plain.erase("wardrobe")
	_check(Wardrobe.checked_view(plain).is_empty(), "A wallet answer with the shop off keeps no wardrobe")
	for broken: Dictionary in [answer([], {"shoe": "daisy"}), answer([], {"hat": 3}), answer(["Daisy!"]), answer([], {}, -1), answer([], {}, 0, 0, -5)]:
		_check(Wardrobe.checked_view(broken).is_empty() or Wardrobe.checked_view(broken).items.is_empty(), "A wardrobe that breaks the contract is refused: %s" % JSON.stringify(broken.wardrobe))
	var bad_look := answer()
	bad_look.wardrobe.look = {"hat": "daisy", "shoe": "x"}
	_check(Wardrobe.checked_view(bad_look).is_empty(), "A look with a slot the game does not know is refused whole")
	var halfway := answer()
	halfway.wardrobe.look_revision = 1.5
	_check(Wardrobe.checked_view(halfway).is_empty(), "A revision that is not whole is refused")

func _file_and_damage() -> void:
	var path := _path("wardrobe")
	var store: RefCounted = Wardrobe.new(path)
	store.set_enabled(SERVER, ME, true)
	_check(store.note_view(SERVER, ME, answer(["daisy"], {"hat": "daisy"}, 3)), "A wallet answer is kept")
	var again: RefCounted = Wardrobe.new(path)
	_check(again.enabled(SERVER, ME) and again.view(SERVER, ME).look == {"hat": "daisy"} and again.view(SERVER, ME).items == ["daisy"], "The wardrobe survives a restart")
	_check(again.view(SERVER, OTHER).is_empty() and again.view("https://other.example.test", ME).is_empty(), "Each server and player keeps its own wardrobe")
	AtomicFile.remove(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{\"schema_version\": 1, \"scopes\": {\"" + SERVER + "|" + ME + "\": {\"enabled\": true, \"view\": {\"items\": \"oops\"")
	file.close()
	var damaged: RefCounted = Wardrobe.new(path)
	_check(damaged.view(SERVER, ME).is_empty(), "A damaged file reads as empty")
	damaged.set_enabled(SERVER, ME, true)
	_check(damaged.note_view(SERVER, ME, answer(["tide"])) and damaged.view(SERVER, ME).items == ["tide"], "The next wallet read fills it again")
	var corrupt: RefCounted = Wardrobe.new(path)
	_check(corrupt.view(SERVER, ME).items == ["tide"], "And that answer is what the file then holds")

## Account deletion forgets one player on every server; the other players' wardrobes stay.
func _clear_owner() -> void:
	var path := _path("wardrobe-clear")
	var store: RefCounted = Wardrobe.new(path)
	for server: String in [SERVER, "https://other.example.test"]:
		for owner: String in [ME, OTHER]:
			store.set_enabled(server, owner, true)
			store.note_view(server, owner, answer(["daisy"], {"hat": "daisy"}, 3))
	store.scope_source = func() -> Dictionary: return {"server": SERVER, "owner": ME}
	_check(store.active_look() == {"hat": "daisy"} and not Catalog._offered.is_empty(), "The signed-in player wears their look before account deletion")
	store.clear_owner(ME)
	_check(store.active_look().is_empty() and Catalog._offered.is_empty(), "Forgetting the signed-in player drops their look and what the catalogue released for them")
	var again: RefCounted = Wardrobe.new(path)
	_check(again.view(SERVER, ME).is_empty() and again.view("https://other.example.test", ME).is_empty(), "Forgetting a player (account deletion) drops their wardrobe on every server")
	_check(again.view(SERVER, OTHER).look == {"hat": "daisy"} and again.view("https://other.example.test", OTHER).look == {"hat": "daisy"}, "and keeps every other player's")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{damaged")
	file.close()
	var aside := path + ".unreadable-" + FileAccess.get_sha256(path)
	Wardrobe.new(path).clear_owner(ME)
	_check(FileAccess.file_exists(path) and not FileAccess.file_exists(aside) and AtomicFile.read_json(path) is Dictionary, "Forgetting a player replaces a damaged file and removes the copy kept aside")

func _looks_in_order() -> void:
	var store: RefCounted = Wardrobe.new(_path("looks"))
	store.set_enabled(SERVER, ME, true)
	store.note_view(SERVER, ME, answer(["daisy", "seashell"], {}, 10))
	_check(store.note_look(SERVER, ME, {"schema_version": 1.0, "op": "equip", "look": {"hat": "seashell"}, "revision": 20.0}), "A newer look is kept")
	_check(not store.note_look(SERVER, ME, {"schema_version": 1.0, "op": "equip", "look": {"hat": "daisy"}, "revision": 15.0}) and store.view(SERVER, ME).look == {"hat": "seashell"}, "An older look that arrives late never replaces a newer one")
	_check(store.note_spend(SERVER, ME, {"schema_version": 1.0, "op": "spend", "kind": "item", "pieces": ["tide"], "balance": 4000.0}) and "tide" in store.view(SERVER, ME).items, "A confirmed purchase is owned")
	_check(store.name_price(SERVER, ME) == 0 and Wardrobe.new(_path("unset")).name_price(SERVER, ME) == -1, "The name change price is known only once the server said it")

func _own_look() -> void:
	var store: RefCounted = Wardrobe.new(_path("own"))
	Wardrobe.use_shared(store)
	var who := {"owner": ME}
	store.scope_source = func() -> Dictionary: return {"server": SERVER, "owner": who.owner}
	store.set_enabled(SERVER, ME, true)
	store.note_view(SERVER, ME, answer(["daisy", "tide"], {"hat": "daisy", "body": "tide"}, 4))
	_check(Catalog.released("daisy") and Catalog.released("tide") and not Catalog.released("gold_leaf"), "The server's offered items are released in the catalogue")
	_check(OwnLook.outfit() == {"hat": "daisy", "body": "tide"}, "The own pip wears the signed-in player's look")
	who.owner = OTHER
	_check(OwnLook.outfit().is_empty() and not Catalog.released("daisy"), "Another player on this phone wears their own look, and the first player's offer goes with them")
	who.owner = ME
	store.set_enabled(SERVER, ME, false)
	_check(OwnLook.outfit().is_empty() and not Catalog.released("daisy"), "With the shop off the own pip wears the default look")
	Wardrobe.use_shared(null)

func _setup() -> Dictionary:
	var store: RefCounted = Wardrobe.new(_path("client"))
	var wallet: RefCounted = PollenWallet.new(_path("client-wallet"))
	var fake := Fake.new()
	fake.tree = self
	var scope := func() -> Dictionary: return {"server": SERVER, "owner": ME}
	var client: RefCounted = WardrobeClient.new(null, scope, fake.call_it, store, wallet)
	store.set_enabled(SERVER, ME, true)
	wallet.set_enabled(SERVER, ME, true)
	return {"store": store, "wallet": wallet, "fake": fake, "client": client}

func _client_retries() -> void:
	var t := _setup()
	t.fake.replies = [{"ok": true, "status": 200, "data": answer(["daisy"], {}, 0, 24000)}]
	var read: Dictionary = await t.client.refresh()
	_check(read.ok and t.wallet.wallet(SERVER, ME).balance == 24000 and t.store.view(SERVER, ME).items == ["daisy"], "A refresh keeps the wallet and the wardrobe from one read")
	t.fake.sent.clear()
	var receipt := {"schema_version": 1.0, "op": "spend", "kind": "item", "id": "tide", "pieces": ["tide"], "cost": 20000.0, "balance": 4000.0}
	t.fake.replies = [{"ok": false, "status": 0, "code": "connection_interrupted"}, {"ok": false, "status": 503, "code": "server_paused"}, {"ok": true, "status": 200, "data": receipt}]
	var bought: Dictionary = await t.client.buy("item", "tide", 20000)
	_check(bought.ok and t.fake.sent.size() == 3, "A purchase with no answer goes again, up to its last send")
	_check(t.fake.sent.all(func(entry: Dictionary) -> bool: return entry.body == t.fake.sent[0].body), "Every send of one purchase carries the same key and body")
	_check(t.fake.sent[0].body.expected_cost == 20000 and t.fake.sent[0].body.kind == "item" and str(t.fake.sent[0].body.idempotency_key).length() == 32, "It names the cost shown and a fresh key")
	_check("tide" in t.store.view(SERVER, ME).items and t.wallet.wallet(SERVER, ME).balance == 4000, "The receipt's item is owned and its balance kept")
	t.fake.sent.clear()
	t.fake.replies = [{"ok": false, "status": 402, "code": "pollen_short"}]
	var short: Dictionary = await t.client.buy("item", "lantern", 50000)
	_check(not short.ok and short.code == "pollen_short" and t.fake.sent.size() == 1, "A refusal is the answer, never sent again")
	t.fake.sent.clear()
	t.fake.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "op": "equip", "look": {"body": "tide"}, "revision": 9.0}}]
	var before := int(Time.get_unix_time_from_system() * 1000.0)
	var worn: Dictionary = await t.client.wear({"body": "tide"})
	_check(worn.ok and int(t.fake.sent[0].body.revision) >= before and t.fake.sent[0].body.look == {"body": "tide"}, "A look carries a revision from this phone's clock")
	var second_key: String = t.fake.sent[0].body.idempotency_key
	t.store.note_look(SERVER, ME, {"schema_version": 1.0, "look": {"body": "tide"}, "revision": 9.0e12})
	t.fake.sent.clear()
	t.fake.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "op": "equip", "look": {}, "revision": 9.0e12 + 1}}]
	await t.client.wear({})
	_check(int(t.fake.sent[0].body.revision) == 9000000000001 and t.fake.sent[0].body.idempotency_key != second_key, "A revision never goes below the last one confirmed, and each look has its own key")

func _client_one_at_a_time() -> void:
	var t := _setup()
	t.fake.replies = [{"ok": true, "status": 200, "data": answer()}]
	t.client.refresh()
	var second: Dictionary = await t.client.buy("item", "daisy", 1000)
	_check(not second.ok and second.code == "busy" and t.fake.sent.size() == 1, "An action asked for while another is out answers busy and sends nothing")
	for i in range(5): await process_frame
	_check(not t.client.busy() and not t.store.view(SERVER, ME).is_empty(), "The first one still finishes")

func _client_stale() -> void:
	var t := _setup()
	t.store.note_view(SERVER, ME, answer([], {}))
	t.fake.replies = [{"ok": false, "status": 409, "code": "already_owned"}, {"ok": true, "status": 200, "data": answer(["daisy"])}]
	var answer_now: Dictionary = await t.client.buy("item", "daisy", 1000)
	_check(not answer_now.ok and answer_now.code == "already_owned", "An item bought already says so")
	_check(t.fake.sent.size() == 2 and t.fake.sent[1].path == WardrobeClient.WALLET_PATH and t.store.view(SERVER, ME).items == ["daisy"], "Then the wardrobe is read again, so the phone shows it owned")
	var off: RefCounted = WardrobeClient.new(null, func() -> Dictionary: return {"server": SERVER, "owner": ME}, t.fake.call_it, Wardrobe.new(_path("off")), t.wallet)
	t.fake.sent.clear()
	_check((await off.buy("item", "daisy", 1000)).code == "pollen_shop_disabled" and t.fake.sent.is_empty(), "Nothing is sent while the server has the shop off")

## A name change carries the price the prompt showed for that very choice, or 0, never a price read later.
func _name_price() -> void:
	var DisplayNames: GDScript = load("res://services/display_names.gd")
	var DisplayNameClient: GDScript = load("res://services/display_name_client.gd")
	var store: RefCounted = Wardrobe.new(_path("names-wardrobe"))
	Wardrobe.use_shared(store)
	store.set_enabled(SERVER, ME, true)
	store.note_view(SERVER, ME, answer([], {}, 0, 5000, 1000))
	var names: RefCounted = DisplayNames.new(_path("names"))
	names.set_enabled(SERVER, ME, true)
	var fake := Fake.new()
	fake.tree = self
	fake.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "display_name": "Robin", "revision": 1.0}}, {"ok": false, "status": 409, "code": "name_change_price"}]
	var client: RefCounted = DisplayNameClient.new(null, func() -> Dictionary: return {"server": SERVER, "owner": ME}, fake.call_it, names)
	var chosen: Dictionary = names.choose(SERVER, ME, "typed", "Robin")
	client.note_shown_price(int(chosen.revision), 1000)
	client.flush()
	for i in range(4): await process_frame
	_check(fake.sent.size() == 1 and fake.sent[0].body.get("pollen_price") == 1000, "A name carries the price shown for it")
	names.choose(SERVER, ME, "typed", "Robin Sky")
	client.flush()
	for i in range(4): await process_frame
	_check(fake.sent.size() == 2 and fake.sent[1].body.get("pollen_price") == 0, "A choice no price was shown for sends 0, so the server refuses instead of charging")
	names.choose(SERVER, ME, "anonymous", "")
	client.flush()
	for i in range(4): await process_frame
	_check(fake.sent.size() == 3 and not fake.sent[2].body.has("pollen_price"), "Going anonymous carries no price")
	Wardrobe.use_shared(null)

## The wardrobe on with the shop off (POLLEN_WARDROBE without POLLEN_SHOP).
func _wardrobe_without_shop() -> void:
	var kept := Wardrobe.checked_view(owned_answer(["gold_leaf"], {"leaf": "gold_leaf"}, 4))
	_check(kept.items == ["gold_leaf"] and kept.look == {"leaf": "gold_leaf"} and kept.prices.is_empty() and kept.sets.is_empty() and kept.unlocked.is_empty() and kept.offered_packs.is_empty() and kept.name_price == -1, "A wardrobe answer without the shop is kept, with no price and no name price")
	var bad := owned_answer()
	bad.wardrobe.unlocked = "oops"
	_check(Wardrobe.checked_view(bad).is_empty(), "A shop part that is sent must still be the contract's")
	var path := _path("no-shop")
	var store: RefCounted = Wardrobe.new(path)
	store.set_enabled(SERVER, ME, true, false)
	_check(store.enabled(SERVER, ME) and not store.shop(SERVER, ME), "The wardrobe can be on with the shop off")
	_check(store.note_view(SERVER, ME, owned_answer(["gold_leaf"])) and store.view(SERVER, ME).items == ["gold_leaf"], "Its wallet read is kept")
	_check(store.name_price(SERVER, ME) == -1, "No name change price without the shop")
	var again: RefCounted = Wardrobe.new(path)
	_check(again.enabled(SERVER, ME) and not again.shop(SERVER, ME) and again.view(SERVER, ME).items == ["gold_leaf"], "Both answers survive a restart")
	store.set_enabled(SERVER, ME, true, true)
	_check(store.shop(SERVER, ME), "The shop turns on beside it")
	store.set_enabled(SERVER, ME, false, true)
	_check(not store.enabled(SERVER, ME) and not store.shop(SERVER, ME), "No shop without the wardrobe")
	var old_path := _path("before-split")
	AtomicFile.write_text(old_path, JSON.stringify({"schema_version": 1, "scopes": {Wardrobe.scope_key(SERVER, ME): {"enabled": true, "view": {}}}}))
	var old: RefCounted = Wardrobe.new(old_path)
	_check(old.enabled(SERVER, ME) and not old.shop(SERVER, ME), "A file from before the split keeps the wardrobe and reads the shop off until the server says")
	var fake := Fake.new()
	fake.tree = self
	var client: RefCounted = WardrobeClient.new(null, func() -> Dictionary: return {"server": SERVER, "owner": ME}, fake.call_it, store, PollenWallet.new(_path("no-shop-wallet")))
	store.set_enabled(SERVER, ME, true, false)
	_check((await client.buy("item", "daisy", 1000)).code == "pollen_shop_disabled" and fake.sent.is_empty(), "Nothing is bought while the shop is off")
	fake.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "op": "equip", "look": {"leaf": "gold_leaf"}, "revision": 9.0e12}}]
	_check((await client.wear({"leaf": "gold_leaf"})).ok and fake.sent.size() == 1 and fake.sent[0].path == WardrobeClient.EQUIP_PATH, "An earned item is worn")
	# A name change carries no price while the shop is off.
	var DisplayNames: GDScript = load("res://services/display_names.gd")
	var DisplayNameClient: GDScript = load("res://services/display_name_client.gd")
	Wardrobe.use_shared(store)
	var names: RefCounted = DisplayNames.new(_path("no-shop-names"))
	names.set_enabled(SERVER, ME, true)
	var sender := Fake.new()
	sender.tree = self
	sender.replies = [{"ok": true, "status": 200, "data": {"schema_version": 1.0, "display_name": "Robin", "revision": 1.0}}]
	var name_client: RefCounted = DisplayNameClient.new(null, func() -> Dictionary: return {"server": SERVER, "owner": ME}, sender.call_it, names)
	names.choose(SERVER, ME, "typed", "Robin")
	name_client.flush()
	for i in range(4): await process_frame
	_check(sender.sent.size() == 1 and not sender.sent[0].body.has("pollen_price"), "A name sent while the shop is off carries no price")
	Wardrobe.use_shared(null)

## A real capabilities read hands the server's offered tag to the shared
## wardrobe under the same scope the Pollen client reads (and none while the
## wardrobe is off), so a view kept under no tag is read again.
func _offered_tag_wiring() -> void:
	var store: RefCounted = Wardrobe.new(_path("tag-wiring"))
	Wardrobe.use_shared(store)
	store.set_enabled(SERVER, ME, true, false)
	store.note_view(SERVER, ME, owned_answer())
	var api := CapsApi.new()
	root.add_child(api)
	var session: RefCounted = load("res://services/relay_online_session.gd").new(api, func() -> Dictionary: return {"ready": true, "player_id": ME, "epoch": 1}, MemoryStore.new())
	var base := {"api_version": 2, "recording_version": 2, "simulation_version": 2, "mutations_enabled": true, "validation": "structural_client_replay_required", "chapters": []}
	api.capabilities = base.merged({"pollen_version": 1, "pollen_wardrobe_version": 1, "pollen_offered_tag": "0badf00d"})
	_check(await session.load_capabilities(), "Capabilities load")
	_check(store.needs_read(SERVER, ME), "The capabilities read hands the offered tag to the wardrobe the Pollen client reads")
	api.capabilities = base.merged({"pollen_version": 1, "pollen_offered_tag": "0badf00d"})
	_check(await session.load_capabilities(), "Capabilities load without the wardrobe")
	_check(not store.needs_read(SERVER, ME), "With the wardrobe off nothing is read")
	Wardrobe.use_shared(null)
	api.queue_free()
	await process_frame

## What the session reads from the server's capabilities: the wardrobe and the shop apart, and a
## server from before the split, which sends only the shop's version, meaning both.
func _capabilities() -> void:
	var session: RefCounted = load("res://services/relay_online_session.gd").new(null, func() -> Dictionary: return {}, RefCounted.new())
	var cases := [
		[{"pollen_version": 1.0}, false, false, "Earning only: no wardrobe, no shop"],
		[{"pollen_version": 1.0, "pollen_wardrobe_version": 1.0}, true, false, "The wardrobe alone"],
		[{"pollen_version": 1.0, "pollen_wardrobe_version": 1.0, "pollen_shop_version": 1.0}, true, true, "The wardrobe and the shop"],
		[{"pollen_version": 1.0, "pollen_shop_version": 1.0}, true, true, "A server from before the split: the shop means both"],
		[{"pollen_wardrobe_version": 1.0, "pollen_shop_version": 1.0}, false, false, "Nothing without earning"],
	]
	for item: Array in cases:
		session.capabilities = item[0]
		_check(session.wardrobe_supported() == item[1] and session.shop_supported() == item[2], item[3])


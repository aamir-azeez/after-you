extends SceneTree
## Fruits on this phone, the services under every Fruit surface, through fake
## transports and synthetic ids only:
## - the packs table (content/pollen_bundles.json schema 3, services/pollen_bundles.gd):
##   each currency's packs, their amounts, gifts and products per store, the
##   "fruits" offering, and the Jar and Basket shown as Basket and Wheelbarrow;
## - the wallet read's Fruits part (services/fruit_wallet.gd): only the contract's
##   shapes, a broken sub part dropped by itself, a restart keeps it, each
##   achievement unlock toasts once and a new install toasts none;
## - the capabilities and the one visibility gate (services/pollen_surfaces.gd);
## - turn and clear receipts' Sunshine and Fruits parts (services/pollen_wallet.gd);
## - spends: Orchard items, convert and Sunshine bodies, keys and retries, refusals,
##   and both balances kept from the receipt (services/wardrobe_client.gd);
## - Fruit pack claims (services/bundle_claims.gd) and the history's Fruit lines
##   (services/pollen_history.gd); the Orchard's prices in the wardrobe view.
const Bundles = preload("res://services/pollen_bundles.gd")
const FruitWallet = preload("res://services/fruit_wallet.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenGrant = preload("res://services/pollen_grant.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const WardrobeClient = preload("res://services/wardrobe_client.gd")
const WalletReply = preload("res://services/wallet_reply.gd")
const BundleClaims = preload("res://services/bundle_claims.gd")
const PollenHistory = preload("res://services/pollen_history.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const AtomicFile = preload("res://services/atomic_file.gd")
const PollenClient = preload("res://services/pollen_client.gd")

# Synthetic ids only.
const SERVER := "https://fruits.example.test"
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const OTHER := "bbbbbbbbbbbbbbbbbbbbbb"
const ROOM := "cccccccccccccccccccccc"

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

class Online extends RefCounted:
	var on := true
	func online() -> bool: return on

class Fake extends RefCounted:
	var tree: SceneTree
	var sent: Array = []
	var replies: Array = []
	func call_it(method: int, path: String, body: Dictionary) -> Dictionary:
		sent.append({"method": method, "path": path, "body": body.duplicate(true)})
		await tree.process_frame
		return replies.pop_front() if not replies.is_empty() else {"ok": false, "status": 0, "code": "connection_interrupted"}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_table()
	_offerings()
	_names()
	_parts()
	_file()
	_unlocks()
	_receipt_unlocks()
	_capabilities()
	await _capabilities_wiring()
	await _read_wiring()
	_surfaces()
	_reply()
	_turn_receipts()
	_clear_receipts()
	await _spends()
	await _spend_refusals()
	await _claims()
	_history()
	_wardrobe_prices()
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup", ".unreadable"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU FRUIT WALLET: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _path(stem: String) -> String:
	var path := "user://test-fruits-%s-%s.json" % [stem, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

## The wallet read's Fruits part as the server sends it (numbers as floats).
static func part(balance: float = 40.0, paid: Array = [], extra: Dictionary = {}) -> Dictionary:
	var rows: Array = []
	for id: String in ["together_first", "together_five", "duel_win_first", "keepsake_first"]:
		var row := {"id": id, "fruits": 10.0 if id != "together_five" else 15.0, "goal": 1.0 if id != "together_five" else 5.0, "progress": 0.0, "live": id != "keepsake_first"}
		if id in paid: row.paid_at = 1.8e12
		rows.append(row)
	var value := {"schema_version": 1.0, "balance": balance, "earned": 60.0, "sunshine": {"left": 0.0, "turns": 24.0, "price": 10.0},
		"convert": {"pollen_per_fruit": 400.0, "step": 10.0}, "first_pack_gift": true, "first_pack_percent": 100.0, "achievements": rows,
		"grant": {"next": 15.0, "top": 30.0, "welcome": 25.0, "welcome_paid": true, "latest": {"amount": 15.0, "welcome": 25.0, "at": 1.8e12}}}
	value.merge(extra, true)
	return value

## A whole wallet answer with the shop on and a Fruits part.
static func answer(fruits: Variant = part(), balance: float = 9000.0) -> Dictionary:
	var value := {"schema_version": 1.0, "balance": balance, "earned": balance, "bank": 12.0, "name_price": 0.0,
		"wardrobe": {"items": [], "packs": [], "look": {}, "look_revision": 1.0, "offered": ["daisy"], "offered_packs": [], "sets": {}, "unlocked": [],
			"prices": {"daisy": 1000.0}, "fruit_prices": {"fruit_cap": 50.0, "apple_leaf": 25.0, "orchard_skin": 100.0, "sprig_sun": 10.0}, "fruit_sets": {"orchard": ["fruit_cap", "orchard_skin", "apple_leaf"]}}}
	if fruits != null: value.fruits = fruits
	return value

func _fruit_store() -> RefCounted:
	var store: RefCounted = FruitWallet.new(_path("store"))
	store.set_enabled(SERVER, ME, true, true)
	return store

# --- The packs table ---------------------------------------------------------

func _table() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(Bundles.PATH))
	_check(raw is Dictionary and int(raw.schema_version) == 3 and raw.first_bonus_percent == {"pollen": 20.0, "fruits": 100.0}, "The table is schema 3 with a first gift per currency")
	_check(raw.bundles.keys() == ["pinch", "pouch", "jar", "basket", "handful", "bowl", "crate", "barrel"], "Its keys are in store order: %s" % [raw.bundles.keys()])
	_check(Bundles.ids() == Bundles.ORDER and Bundles.ids("pollen") == ["pinch", "pouch", "jar", "basket"] and Bundles.ids("fruits") == ["handful", "bowl", "crate", "barrel"], "Each currency lists its own packs; no currency means Pollen")
	_check(Bundles.pollen("pouch") == 21000 and Bundles.amount("pouch") == 21000 and Bundles.pollen("bowl") == 0 and Bundles.amount("bowl") == 55, "pollen() stays Pollen only; amount() reads either")
	for row: Array in [["handful", 25, 0, 249, 299], ["bowl", 55, 5, 499, 599], ["crate", 120, 20, 999, 1099], ["barrel", 260, 60, 1999, 2199]]:
		var id: String = row[0]
		_check(Bundles.currency_of(id) == "fruits" and Bundles.amount(id) == row[1] and Bundles.bonus(id) == row[2] and Bundles.usd_cents(id, Bundles.PLAY_STORE) == row[3] and Bundles.usd_cents(id, Bundles.APP_STORE) == row[4], "The %s: %d Fruits, %d bonus, its US prices" % [id, row[1], row[2]])
		_check(Bundles.product(id, Bundles.PLAY_STORE) == "after_you_fruits_" + id and Bundles.product(id, Bundles.APP_STORE) == "after_you_fruits_%s_ios" % id, "The %s's product on each store" % id)
		_check(raw.bundles[id].play_store.revenuecat_product == "" and raw.bundles[id].app_store.revenuecat_product == "", "The %s's RevenueCat product is not set up yet" % id)
	for id: String in ["pinch", "pouch", "jar", "basket"]:
		_check(raw.bundles[id].currency == "pollen" and Bundles.product(id, Bundles.PLAY_STORE) == "after_you_pollen_" + id and not str(raw.bundles[id].play_store.revenuecat_product).is_empty(), "The %s keeps its product and RevenueCat id" % id)
	_check(Bundles.bonus_percent("bowl") == 10 and Bundles.bonus_percent("crate") == 20 and Bundles.bonus_percent("barrel") == 30 and Bundles.bonus_percent("pouch") == 5, "Bonus percents of the base")
	_check(Bundles.first_bonus_percent() == 20 and Bundles.first_bonus_percent("fruits") == 100, "First pack gifts: Pollen 20%%, Fruits 100%%")
	var offer := {"first_gift": true, "first_gift_percent": 100}
	_check(Bundles.adds("handful", offer) == 50 and Bundles.adds("handful") == 25 and Bundles.gift("barrel", 100) == 260, "A first Fruit pack pays double: the Handful gives 50")
	_check(Bundles.cover(40, {}, "fruits") == "bowl" and Bundles.cover(40, offer, "fruits") == "handful" and Bundles.cover(1000, {}, "fruits") == "barrel" and Bundles.cover(5001) == "pouch", "The pack to suggest is per currency")
	var priced := {"handful": {}, "crate": {}}
	_check(Bundles.cover(40, {}, "fruits", priced) == "crate" and Bundles.cover(1000, {}, "fruits", priced) == "crate" and Bundles.cover(40, {}, "fruits", {}) == "" and Bundles.cover(40, {}, "fruits", null) == "bowl",
		"Only a pack the store priced is named: the Crate when the Bowl has no price, none with no prices, any while prices are unknown")
	_check(Bundles.per_unit("barrel", 19990000) == 13, "Fruits per $1 for the Barrel: 13")
	var broken := Bundles.checked_table({"first_bonus_percent": {"pollen": "x"}, "bundles": {"a": {"currency": "gold", "amount": 5, "bonus": 0}, "b": {"currency": "fruits", "amount": 5.5, "bonus": 0},
		"c": {"currency": "fruits", "amount": 5, "bonus": 0, "play_store": {"product": "p", "usd_cents": 1}}, "d": {"currency": "fruits", "amount": 10, "bonus": 2, "play_store": {"product": "p", "usd_cents": 1}, "app_store": {"product": "q", "usd_cents": 2}}}})
	_check(broken.bundles.keys() == ["d"] and broken.first_bonus_percent == {"pollen": 0, "fruits": 0}, "A pack off the schema is left out, a broken gift reads as none: %s" % [broken])
	_check(Bundles.checked_table(null).bundles.is_empty() and Bundles.checked_table("x").bundles.is_empty(), "A table that does not parse keeps no pack")

func _offerings() -> void:
	var payload := {"offerings": [
		{"id": "pollen", "packages": [{"id": "pinch", "product_id": "after_you_pollen_pinch", "price": "$0.99", "price_micros": 990000, "currency": "USD"},
			{"id": "bowl", "product_id": "after_you_fruits_bowl", "price": "$4.99", "price_micros": 4990000, "currency": "USD"}]},
		{"id": "fruits", "packages": [{"id": "handful", "product_id": "after_you_fruits_handful", "price": "$2.49", "price_micros": 2490000, "currency": "USD"},
			{"id": "barrel", "product_id": "after_you_fruits_barrel:buy", "price": "$19.99", "price_micros": 19990000, "currency": "USD"},
			{"id": "crate", "product_id": "after_you_fruits_crate_ios", "price": "$10.99", "price_micros": 10990000, "currency": "USD"},
			{"id": "pouch", "product_id": "after_you_pollen_pouch", "price": "$3.99", "price_micros": 3990000, "currency": "USD"},
			{"id": "bowl", "product_id": "after_you_fruits_bowl", "price": ""}]},
		{"id": "full_journey", "packages": [{"id": "monthly", "product_id": "after_you_full_journey_monthly", "price": "$0.99"}]}]}
	var fruits := Bundles.packages(payload, Bundles.PLAY_STORE, "fruits")
	_check(fruits.keys() == ["handful", "barrel"] and fruits.handful.offering_id == "fruits" and fruits.barrel.id == "barrel" and fruits.barrel.price == "$19.99", "The Fruits offering sells only Play's Fruit packs with a price: %s" % [fruits])
	var pollen := Bundles.packages(payload, Bundles.PLAY_STORE)
	_check(pollen.keys() == ["pinch"] and pollen.pinch.offering_id == "pollen", "The Pollen offering still sells only Pollen bundles: %s" % [pollen])
	var ios := Bundles.packages(payload, Bundles.APP_STORE, "fruits")
	_check(ios.keys() == ["crate"], "On the App Store only its own Fruit products: %s" % [ios])
	_check(Bundles.packages({"offerings": [{"id": "fruits", "packages": "x"}]}, "", "fruits").is_empty() and Bundles.packages({"offerings": "x"}, "", "fruits").is_empty(), "A broken offerings payload sells nothing")
	_check(Bundles.bundle_for_product("after_you_fruits_crate", Bundles.PLAY_STORE) == "" and Bundles.bundle_for_product("after_you_fruits_crate", Bundles.PLAY_STORE, "fruits") == "crate" and Bundles.bundle_for_product("after_you_fruits_crate", Bundles.PLAY_STORE, "") == "crate", "A product maps to its pack within its currency")
	_check(Bundles.offering() == "pollen" and Bundles.offering("fruits") == "fruits", "Each currency's RevenueCat offering")

func _names() -> void:
	var names := {"pinch": "Pinch", "pouch": "Pouch", "jar": "Basket", "basket": "Wheelbarrow", "handful": "Handful", "bowl": "Bowl", "crate": "Crate", "barrel": "Barrel"}
	for id: String in names:
		_check(Bundles.display_name(id) == names[id], "The %s shows as %s: %s" % [id, names[id], Bundles.display_name(id)])
	_check(Bundles.product("jar", Bundles.PLAY_STORE) == "after_you_pollen_jar" and Bundles.product("basket", Bundles.APP_STORE) == "after_you_pollen_basket_ios", "Renamed bundles keep their ids and products")

# --- The Fruits part ---------------------------------------------------------

func _parts() -> void:
	var kept := FruitWallet.checked_part(part(40.0, ["together_first"]))
	_check(kept.balance == 40 and kept.earned == 60 and kept.sunshine == {"left": 0, "turns": 24, "price": 10} and kept.convert == {"pollen_per_fruit": 400, "step": 10} and kept.first_pack_gift and kept.first_pack_percent == 100, "The Fruits part is kept with whole numbers: %s" % [kept])
	_check(kept.achievements.size() == 4 and kept.achievements[0].paid and kept.achievements[0].paid_at == 1800000000000 and not kept.achievements[1].paid and not kept.achievements[3].live, "Achievements keep their order, paid and live")
	_check(kept.grant == {"next": 15, "top": 30, "welcome": 25, "welcome_paid": true, "latest": {"amount": 15, "welcome": 25, "at": 1800000000000}}, "The Full Journey Fruits are kept")
	_check(FruitWallet.checked_part(part(-30.0)).balance == -30, "A balance below 0 after a refund is kept")
	for broken: Variant in [null, "x", part(40.5), part(40.0, [], {"earned": -1.0}), part(40.0, [], {"schema_version": 2.0}), part(40.0, [], {"balance": "40"})]:
		_check(FruitWallet.checked_part(broken).is_empty(), "A part without a whole balance and earned is refused: %s" % [broken])
	var laddered := FruitWallet.checked_part(part(40.0, [], {"ladder": {"first": 15.0, "step": 1.0, "every": 2.0, "top": 30.0, "welcome": 25.0}}))
	_check(laddered.ladder == {"first": 15, "step": 1, "every": 2, "top": 30, "welcome": 25}, "The Fruit ladder everyone is shown is kept: %s" % [laddered])
	for broken_ladder: Variant in [{"first": 15.0, "step": 1.0, "every": 0.0, "top": 30.0, "welcome": 25.0}, {"first": 15.0, "step": 1.0, "every": 2.0, "top": 10.0, "welcome": 25.0}, {"first": 15.0, "step": 1.0, "every": 2.0, "top": 30.0}, "15"]:
		_check(not FruitWallet.checked_part(part(40.0, [], {"ladder": broken_ladder})).has("ladder") and FruitWallet.checked_part(part(40.0, [], {"ladder": broken_ladder})).balance == 40, "A ladder off the contract is left out by itself: %s" % [broken_ladder])
	var ladder_store: RefCounted = FruitWallet.new(_path("ladder"))
	ladder_store.set_enabled(SERVER, ME, true)
	_check(ladder_store.ladder(SERVER, ME).is_empty(), "No ladder before a read")
	ladder_store.note_view(SERVER, ME, {"fruits": part(40.0, [], {"ladder": {"first": 15.0, "step": 1.0, "every": 2.0, "top": 30.0, "welcome": 25.0}})})
	_check(ladder_store.ladder(SERVER, ME).top == 30 and FruitWallet.new(ladder_store.path).ladder(SERVER, ME).first == 15, "A read's ladder is kept, a restart included")
	var sub := FruitWallet.checked_part(part(40.0, [], {"sunshine": {"left": 30.0, "turns": 24.0, "price": 10.0}, "convert": {"pollen_per_fruit": 0.0, "step": 10.0}, "first_pack_gift": "yes", "grant": {"next": 15.0}}))
	_check(sub.balance == 40 and not sub.has("sunshine") and not sub.has("convert") and not sub.has("grant") and not sub.first_pack_gift and sub.achievements.size() == 4, "A broken sub part is left out by itself: %s" % [sub])
	var rows := part()
	rows.achievements = [{"id": "Bad Id", "fruits": 10.0, "goal": 1.0, "progress": 0.0, "live": true}, {"id": "ok_one", "fruits": 10.0, "goal": 1.0, "progress": 0.0, "live": "yes"},
		{"id": "ok_two", "fruits": 10.0, "goal": 3.0, "progress": 9.0, "live": true, "level_id": "relay-isles", "room_id": ROOM}, {"id": "ok_two", "fruits": 10.0, "goal": 1.0, "progress": 0.0, "live": true},
		{"id": "ok_three", "fruits": 10.0, "goal": 1.0, "progress": 0.0, "live": true, "paid_at": -1.0}, "x"]
	var rows_kept := FruitWallet.checked_part(rows)
	_check(rows_kept.achievements.size() == 1 and rows_kept.achievements[0].id == "ok_two" and rows_kept.achievements[0].progress == 3 and rows_kept.achievements[0].room_id == ROOM, "Each broken or repeated row is left out by itself: %s" % [rows_kept.achievements])
	var too_many := part()
	too_many.achievements = range(40).map(func(i: int) -> Dictionary: return {"id": "a%d" % i, "fruits": 1.0, "goal": 1.0, "progress": 0.0, "live": true})
	_check(FruitWallet.checked_part(too_many).achievements.is_empty() and FruitWallet.checked_part(too_many).balance == 40, "An overlong list keeps no rows, the balance still counts")

func _file() -> void:
	var path := _path("file")
	var store: RefCounted = FruitWallet.new(path)
	_check(not store.enabled(SERVER, ME) and not store.needs_read(SERVER, ME) and store.part(SERVER, ME).is_empty(), "Nothing before the server says")
	store.set_enabled(SERVER, ME, false, true)
	_check(not store.packs(SERVER, ME), "Packs never sell without Fruits")
	store.set_enabled(SERVER, ME, true, true)
	_check(store.enabled(SERVER, ME) and store.packs(SERVER, ME) and store.needs_read(SERVER, ME), "Fruits on and none kept: the wallet is read")
	_check(store.note_view(SERVER, ME, answer(part(40.0, ["together_first"]))) and not store.needs_read(SERVER, ME), "A wallet answer's part is kept")
	var again: RefCounted = FruitWallet.new(path)
	_check(again.enabled(SERVER, ME) and again.packs(SERVER, ME) and again.part(SERVER, ME) == store.part(SERVER, ME) and again.balance(SERVER, ME) == 40, "The Fruits survive a restart")
	_check(again.part(SERVER, OTHER).is_empty() and again.part("https://other.example.test", ME).is_empty(), "Each server and player keeps its own")
	_check(again.offer(SERVER, ME) == {"first_gift": true, "first_gift_percent": 100} and Bundles.adds("bowl", again.offer(SERVER, ME)) == 110, "The first pack gift reads as an offer for the packs")
	_check(again.convert_valid(SERVER, ME, 20) and not again.convert_valid(SERVER, ME, 15) and not again.convert_valid(SERVER, ME, 0) and again.convert_pollen(SERVER, ME, 20) == 8000, "Convert: whole steps only, 400 Pollen a Fruit")
	_check(again.sunshine_buyable(SERVER, ME) and again.grant_paid(SERVER, ME, 1800000000000) == {"amount": 15, "welcome": 25} and again.grant_paid(SERVER, ME, 5).is_empty(), "Sunshine buyable at 0 left; the grant's Fruits by its instalment")
	store.set_enabled(SERVER, OTHER, true)
	_check(not store.note_view(SERVER, OTHER, answer(null)) and not store.needs_read(SERVER, OTHER), "A read with no Fruits part this build can keep asks no more this launch")
	_check(FruitWallet.new(path).needs_read(SERVER, OTHER), "and asks again after a restart")
	AtomicFile.remove(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{\"schema_version\": 1, \"scopes\": {\"" + SERVER + "|" + ME + "\": {\"enabled\": true, \"part\": {\"balance\": \"oops\"")
	file.close()
	var damaged: RefCounted = FruitWallet.new(path)
	_check(damaged.part(SERVER, ME).is_empty() and damaged.unlocks(SERVER, ME).is_empty(), "A damaged file reads as empty")
	var odd := _path("odd")
	AtomicFile.write_text(odd, JSON.stringify({"schema_version": 1, "scopes": {SERVER + "|" + ME: {"enabled": true, "packs": true, "part": {"balance": 5}, "paid": ["ok", 5, "Bad"], "unlocks": [{"id": "ok", "fruits": 10}, {"id": "ok", "fruits": 10}, {"id": 3}], "baseline": true}, "nobar": {}}}))
	var read: RefCounted = FruitWallet.new(odd)
	_check(read.enabled(SERVER, ME) and read.part(SERVER, ME).is_empty() and read.unlocks(SERVER, ME) == [{"id": "ok", "fruits": 10}], "A file's broken values are dropped one by one: %s" % [read.unlocks(SERVER, ME)])
	_check(read.clear_owner(ME) and FruitWallet.new(odd).part(SERVER, ME).is_empty() and not FruitWallet.new(odd).enabled(SERVER, ME), "Account deletion forgets the player")

# --- Unlocks -------------------------------------------------------------------

func _unlocks() -> void:
	var path := _path("unlocks")
	var store: RefCounted = FruitWallet.new(path)
	store.set_enabled(SERVER, ME, true)
	var heard := {"count": 0}
	store.unlocked.connect(func(_s: String, _o: String) -> void: heard.count += 1)
	store.note_view(SERVER, ME, answer(part(40.0, ["together_first", "duel_win_first"])))
	_check(store.unlocks(SERVER, ME).is_empty() and heard.count == 0, "The first read learns what was paid before: no toasts on a new install")
	store.note_view(SERVER, ME, answer(part(50.0, ["together_first", "duel_win_first", "together_five"])))
	_check(store.unlocks(SERVER, ME) == [{"id": "together_five", "fruits": 15}] and heard.count == 1, "A newly paid achievement toasts: %s" % [store.unlocks(SERVER, ME)])
	store.note_view(SERVER, ME, answer(part(50.0, ["together_first", "duel_win_first", "together_five"])))
	_check(store.unlocks(SERVER, ME).size() == 1 and heard.count == 1, "The same read again adds nothing")
	_check(FruitWallet.new(path).unlocks(SERVER, ME) == [{"id": "together_five", "fruits": 15}], "A toast not shown yet survives a restart")
	store.mark_unlock_shown(SERVER, ME, "together_five")
	_check(store.unlocks(SERVER, ME).is_empty() and FruitWallet.new(path).unlocks(SERVER, ME).is_empty(), "Once shown it never shows again, after a restart too")
	store.note_view(SERVER, ME, answer(part(50.0, ["together_first"])))
	_check(store.unlocks(SERVER, ME).is_empty(), "A late read without them never toasts them again")
	_check(store.part(SERVER, ME).achievements.filter(func(row: Dictionary) -> bool: return row.paid).size() == 3, "and never takes back a paid achievement")
	store.note_view(SERVER, ME, answer(part(50.0, ["together_first", "duel_win_first", "together_five"])))
	_check(store.unlocks(SERVER, ME).is_empty(), "nor toasts them when they come back")

func _receipt_unlocks() -> void:
	var store := _fruit_store()
	var receipt := PollenWallet.checked_receipt(_receipt({"fruits": {"balance": 10.0, "paid": [{"id": "together_first", "amount": 10.0}]}}))
	_check(store.note_receipt(SERVER, ME, receipt) and store.unlocks(SERVER, ME) == [{"id": "together_first", "fruits": 10}], "A receipt's paid achievement toasts, before any read")
	store.note_view(SERVER, ME, answer(part(40.0, ["together_first", "duel_win_first"])))
	_check(store.unlocks(SERVER, ME) == [{"id": "together_first", "fruits": 10}] and store.balance(SERVER, ME) == 40, "The first read after it adds no toast of its own and keeps the one waiting")
	store.note_receipt(SERVER, ME, receipt)
	_check(store.unlocks(SERVER, ME).size() == 1, "The same receipt again (a retried reply) toasts nothing more")
	var later := PollenWallet.checked_receipt(_receipt({"fruits": {"balance": 55.0, "paid": [{"id": "together_five", "amount": 15.0}]}, "sunshine_left": 7.0}))
	store.note_receipt(SERVER, ME, later)
	_check(store.unlocks(SERVER, ME).size() == 2 and store.balance(SERVER, ME) == 55 and store.sunshine(SERVER, ME).left == 7, "A receipt keeps its Fruit balance and Sunshine turns left")
	store.note_view(SERVER, ME, answer(part(55.0, ["together_first", "duel_win_first", "together_five"])))
	_check(store.unlocks(SERVER, ME).size() == 2, "A read naming an achievement a receipt already toasted adds none")
	var off: RefCounted = FruitWallet.new(_path("off"))
	_check(not off.note_receipt(SERVER, ME, receipt) and off.unlocks(SERVER, ME).is_empty(), "Nothing is kept while Fruits are off")

# --- Capabilities and surfaces ---------------------------------------------------

func _capabilities() -> void:
	var session: RefCounted = load("res://services/relay_online_session.gd").new(null, func() -> Dictionary: return {}, RefCounted.new())
	var shop := {"pollen_version": 1.0, "pollen_shop_version": 1.0}
	var cases := [
		[shop, false, false, "The shop alone: no Fruits"],
		[shop.merged({"pollen_fruits_version": 1.0}), true, false, "Fruits on, no packs"],
		[shop.merged({"pollen_fruits_version": 1.0, "pollen_fruit_packs_version": 1.0}), true, true, "Fruits and Play's packs"],
		[shop.merged({"pollen_fruits_version": 1.0, "pollen_app_store_fruit_packs_version": 1.0}), true, false, "The App Store's packs never sell on this store"],
		[shop.merged({"pollen_fruit_packs_version": 1.0}), false, false, "Packs never without Fruits"],
		[{"pollen_version": 1.0, "pollen_fruits_version": 1.0, "pollen_fruit_packs_version": 1.0}, false, false, "Nothing without the shop"],
		[shop.merged({"pollen_fruits_version": 2.0}), false, false, "Another version is off"],
	]
	for item: Array in cases:
		session.capabilities = item[0]
		_check(session.fruits_supported() == item[1] and session.fruit_packs_supported() == item[2], item[3])

## The capabilities read hands Fruits and packs to the shared Fruit store, before its flush.
func _capabilities_wiring() -> void:
	var stores := {"fruits": FruitWallet.new(_path("caps-fruits")), "wallet": PollenWallet.new(_path("caps-wallet")), "wardrobe": Wardrobe.new(_path("caps-wardrobe")), "grant": PollenGrant.new(_path("caps-grant"))}
	FruitWallet.use_shared(stores.fruits)
	PollenWallet.use_shared(stores.wallet)
	Wardrobe.use_shared(stores.wardrobe)
	PollenGrant.use_shared(stores.grant)
	var api := CapsApi.new()
	root.add_child(api)
	var session: RefCounted = load("res://services/relay_online_session.gd").new(api, func() -> Dictionary: return {"ready": true, "player_id": ME, "epoch": 1}, MemoryStore.new())
	var base := {"api_version": 2, "recording_version": 2, "simulation_version": 2, "mutations_enabled": true, "validation": "structural_client_replay_required", "chapters": [],
		"pollen_version": 1, "pollen_wardrobe_version": 1, "pollen_shop_version": 1}
	api.capabilities = base.merged({"pollen_fruits_version": 1, "pollen_fruit_packs_version": 1})
	_check(await session.load_capabilities(), "Capabilities load")
	_check(stores.fruits.enabled(SERVER, ME) and stores.fruits.packs(SERVER, ME) and stores.fruits.needs_read(SERVER, ME), "The capabilities read turns Fruits and packs on, so the next flush reads the wallet")
	api.capabilities = base.duplicate()
	_check(await session.load_capabilities(), "Capabilities load without Fruits")
	_check(not stores.fruits.enabled(SERVER, ME) and not stores.fruits.packs(SERVER, ME) and not stores.fruits.needs_read(SERVER, ME), "With Fruits off every Fruit part is off")
	for store: Variant in [FruitWallet, PollenWallet, Wardrobe, PollenGrant]: store.use_shared(null)
	api.queue_free()
	await process_frame

## A phone that read the wallet before FRUITS went on reads it once more for the Fruits part.
func _read_wiring() -> void:
	var wallet: RefCounted = PollenWallet.new(_path("read-wallet"))
	wallet.set_enabled(SERVER, ME, true)
	wallet.note_wallet(SERVER, ME, answer(null))
	var fruits := _fruit_store()
	var fake := Fake.new()
	fake.tree = self
	var client: RefCounted = PollenClient.new(null, func() -> Dictionary: return {"server": SERVER, "owner": ME}, fake.call_it, wallet)
	client.wardrobe = null
	client.grant = null
	client.fruits = fruits
	fake.replies = [{"ok": true, "status": 200, "data": answer(part(40.0))}]
	client.flush()
	await client.settled
	_check(fake.sent.size() == 1 and fake.sent[0].method == HTTPClient.METHOD_GET and fake.sent[0].path == "/v1/pollen" and fruits.balance(SERVER, ME) == 40, "One flush reads the wallet once and keeps the Fruits part: %s" % [fake.sent])
	client.flush()
	await process_frame
	await process_frame
	_check(fake.sent.size() == 1, "The next flush reads nothing more")
	var bare := _fruit_store()
	client.fruits = bare
	fake.sent.clear()
	fake.replies = [{"ok": true, "status": 200, "data": answer(null)}]
	client.flush()
	await client.settled
	client.flush()
	await process_frame
	await process_frame
	_check(fake.sent.size() == 1 and bare.part(SERVER, ME).is_empty(), "A reply with no Fruits part is not read again on the next flush")

func _surfaces() -> void:
	var on := _fruit_store()
	var fruits_only: RefCounted = FruitWallet.new(_path("fruits-only"))
	fruits_only.set_enabled(SERVER, ME, true, false)
	var off: RefCounted = FruitWallet.new(_path("surfaces-off"))
	var scope := {"server": SERVER, "owner": ME}
	var sells: RefCounted = PollenSurfaces.new(true, true)
	var no_bundles: RefCounted = PollenSurfaces.new(true, false)
	var nothing: RefCounted = PollenSurfaces.new(false, true)
	_check(sells.fruits_visible(on, scope) and sells.fruit_packs_visible(on, scope), "A selling build with Fruits and packs on shows both")
	_check(sells.fruits_visible(fruits_only, scope) and not sells.fruit_packs_visible(fruits_only, scope), "Packs hide while the server sells none")
	_check(no_bundles.fruits_visible(on, scope) and not no_bundles.fruit_packs_visible(on, scope), "A build without bundles shows Fruits but no packs")
	_check(not nothing.fruits_visible(on, scope) and not nothing.fruit_packs_visible(on, scope), "A build that sells nothing shows no Fruit surface")
	_check(not sells.fruits_visible(off, scope) and not sells.fruit_packs_visible(off, scope) and not sells.fruits_visible(on, {}) and not sells.fruits_visible(null, scope), "Fruits off, no player or no store: every Fruit surface hides")

func _reply() -> void:
	var wallet: RefCounted = PollenWallet.new(_path("reply-wallet"))
	var fruits := _fruit_store()
	var kept: Dictionary = WalletReply.note(SERVER, ME, answer(part(40.0, [], {"balance": "broken"})), wallet, null, null, fruits, null)
	_check(kept.wallet and not kept.fruits and fruits.part(SERVER, ME).is_empty(), "A broken Fruits part never stops the Pollen wallet")
	kept = WalletReply.note(SERVER, ME, answer(part(40.0)), wallet, null, null, fruits, null)
	_check(kept.wallet and kept.fruits and fruits.balance(SERVER, ME) == 40, "One read feeds the Fruits beside the wallet")
	kept = WalletReply.note(SERVER, ME, answer(part(40.0)), wallet, null, null, null, null)
	_check(kept.wallet and not kept.fruits, "An older caller without the Fruit store still works")

# --- Receipts ------------------------------------------------------------------

## A turn receipt as the server sends it (JSON numbers arrive as floats).
static func _receipt(extra: Dictionary = {}, turn_extra: Dictionary = {}) -> Dictionary:
	var turn := {"kind": "bank", "base": 89.0, "bonuses": ["first_try"], "bonus_percent": 25.0, "amount": 89.0, "bloom": 1.0, "bloom_extra": 0.0,
		"boost_percent": 10.0, "boost": 9.0, "total": 196.0, "boost_from": ["partner"]}
	turn.merge(turn_extra, true)
	var value := {"schema_version": 1.0, "earned": 196.0, "balance": 9196.0, "turn": turn, "clears": []}
	value.merge(extra, true)
	return value

static func _hash(n: int) -> String:
	return ("%x" % n).lpad(64, "0")

func _turn_receipts() -> void:
	var kept := PollenWallet.checked_receipt(_receipt({"sunshine_left": 23.0, "fruits": {"balance": 50.0, "paid": [{"id": "duel_win_first", "amount": 10.0}]}}, {"sunshine": 98.0}))
	_check(kept.turn.sunshine == 98 and kept.sunshine_left == 23 and kept.fruits == {"balance": 50, "paid": [{"id": "duel_win_first", "amount": 10}]}, "A receipt keeps Sunshine's Pollen, the turns left and the Fruits paid: %s" % [kept])
	var broken := PollenWallet.checked_receipt(_receipt({"sunshine_left": -1.0, "fruits": {"balance": "x", "paid": []}}, {"sunshine": 1.5}))
	_check(not broken.is_empty() and broken.earned == 196 and not broken.turn.has("sunshine") and not broken.has("sunshine_left") and not broken.has("fruits"), "Broken Fruit parts are left out and the Pollen line still shows")
	var lines := PollenWallet.checked_receipt(_receipt({"fruits": {"balance": 5.0, "paid": [{"id": "Bad", "amount": 1.0}, {"id": "top_ten", "amount": 15.0}, {"id": "top_ten", "amount": 15.0}]}}))
	_check(lines.fruits.paid == [{"id": "top_ten", "amount": 15}], "A broken or repeated paid line is left out by itself")
	_check(not PollenWallet.checked_receipt(_receipt({}, {"kind": "after_bank", "sunshine": 9.0})).turn.has("sunshine"), "Sunshine pays only on a bank turn")
	var fruits := _fruit_store()
	fruits.note_view(SERVER, ME, answer(part(40.0, [], {"sunshine": {"left": 24.0, "turns": 24.0, "price": 10.0}})))
	var wallet: RefCounted = PollenWallet.new(_path("turn-wallet"))
	wallet.fruits = fruits
	wallet.set_enabled(SERVER, ME, true)
	_check(wallet.note_receipt(SERVER, ME, ROOM, _hash(1), _receipt({"sunshine_left": 23.0, "fruits": {"balance": 50.0, "paid": [{"id": "duel_win_first", "amount": 10.0}]}}, {"sunshine": 98.0})), "The turn's receipt is kept")
	_check(fruits.balance(SERVER, ME) == 50 and fruits.sunshine(SERVER, ME).left == 23 and fruits.unlocks(SERVER, ME) == [{"id": "duel_win_first", "fruits": 10}], "The turn's Fruits, its toast and Sunshine's turns reach the Fruit store")
	var again: RefCounted = PollenWallet.new(wallet.path)
	_check(again.result_for(SERVER, ME, ROOM, _hash(1)).turn.sunshine == 98 and again.result_for(SERVER, ME, ROOM, _hash(1)).fruits.paid.size() == 1, "The kept result keeps its Sunshine and Fruit lines after a restart")
	wallet.settle_claim(SERVER, ME, ROOM, _hash(2), {"status": "credited", "receipt": _receipt({"sunshine_left": 22.0})})
	_check(fruits.sunshine(SERVER, ME).left == 22, "A claim's receipt feeds the Fruit store the same way")

func _clear_receipts() -> void:
	var fruits := _fruit_store()
	var wallet: RefCounted = PollenWallet.new(_path("clear-wallet"))
	wallet.fruits = fruits
	wallet.set_enabled(SERVER, ME, true)
	wallet.queue_clear(SERVER, ME, "room:" + ROOM)
	var receipt := {"schema_version": 1.0, "earned": 500.0, "balance": 9500.0, "clears": [{"kind": "clear", "total": 500.0, "boost_percent": 0.0, "level_id": "relay-isles"}],
		"fruits": {"balance": 10.0, "paid": [{"id": "together_first", "amount": 10.0}]}}
	wallet.settle_clear(SERVER, ME, "room:" + ROOM, {"status": "credited", "receipt": receipt})
	_check(fruits.unlocks(SERVER, ME) == [{"id": "together_first", "fruits": 10}], "A first clear's achievement reaches the Fruit store")
	_check(wallet.result_for(SERVER, ME, ROOM, PollenWallet.ROOM_CLEAR).get("fruits", {}).get("paid", []).size() == 1, "and the room's end card keeps its Fruit line")

# --- Spends --------------------------------------------------------------------

func _client(fake: Fake, online: Online = null) -> Dictionary:
	var wardrobe: RefCounted = Wardrobe.new(_path("wardrobe"))
	wardrobe.set_enabled(SERVER, ME, true, true)
	var wallet: RefCounted = PollenWallet.new(_path("spend-wallet"))
	wallet.set_enabled(SERVER, ME, true)
	var fruits := _fruit_store()
	var grant: RefCounted = PollenGrant.new(_path("grant"))
	WalletReply.note(SERVER, ME, answer(part(40.0)), wallet, wardrobe, grant, fruits, null)
	var client: RefCounted = WardrobeClient.new(null, func() -> Dictionary: return {"server": SERVER, "owner": ME}, fake.call_it, wardrobe, wallet, grant, fruits)
	client.connectivity = online if online != null else Online.new()
	return {"client": client, "wardrobe": wardrobe, "wallet": wallet, "fruits": fruits}

static func _ok(data: Dictionary) -> Dictionary:
	return {"ok": true, "status": 200, "data": data.merged({"schema_version": 1.0})}

static func _key(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[a-f0-9]{32}$").search(value) != null

func _spends() -> void:
	var fake := Fake.new()
	fake.tree = self
	var t := _client(fake)
	var lost := {"ok": false, "status": 0, "code": "connection_interrupted"}
	fake.replies = [lost, _ok({"kind": "convert", "currency": "fruits", "balance": 13000.0, "fruit_balance": 30.0, "pollen": 4000.0})]
	var answer_convert: Dictionary = await t.client.convert(10)
	_check(answer_convert.ok and fake.sent.size() == 2 and fake.sent[0].body == fake.sent[1].body, "A convert with no answer goes again with the same key and body")
	var body: Dictionary = fake.sent[0].body
	_check(fake.sent[0].path == WardrobeClient.SPEND_PATH and body.kind == "convert" and body.id == "10" and body.expected_cost == 10 and int(body.schema_version) == 1 and _key(body.idempotency_key), "Convert sends kind convert, the count as digits and its cost in Fruits: %s" % [body])
	_check(t.fruits.balance(SERVER, ME) == 30 and t.wallet.wallet(SERVER, ME).balance == 13000, "The receipt's Fruit and Pollen balances are both kept")
	fake.sent.clear()
	fake.replies = [_ok({"kind": "sunshine", "currency": "fruits", "balance": 13000.0, "fruit_balance": 20.0, "sunshine_left": 24.0})]
	var answer_sun: Dictionary = await t.client.buy_sunshine()
	var sun: Dictionary = fake.sent[0].body
	_check(answer_sun.ok and sun.kind == "sunshine" and sun.id == "sunshine" and sun.expected_cost == 10 and _key(sun.idempotency_key) and sun.idempotency_key != body.idempotency_key, "Sunshine sends its own key and the server's price: %s" % [sun])
	_check(t.fruits.balance(SERVER, ME) == 20 and t.fruits.sunshine(SERVER, ME).left == 24 and not t.fruits.sunshine_buyable(SERVER, ME), "Sunshine's turns are kept and it is not buyable again while they last")
	fake.sent.clear()
	fake.replies = [_ok({"kind": "item", "id": "fruit_cap", "pieces": ["fruit_cap"], "currency": "fruits", "balance": 13000.0, "fruit_balance": -30.0})]
	var answer_item: Dictionary = await t.client.buy("item", "fruit_cap", 50)
	_check(answer_item.ok and fake.sent[0].body.kind == "item" and fake.sent[0].body.expected_cost == 50 and "fruit_cap" in t.wardrobe.view(SERVER, ME).items, "An Orchard item goes through the same spend, its cost in Fruits")
	_check(t.fruits.balance(SERVER, ME) == -30 and t.fruits.blocked(SERVER, ME), "A Fruit balance below 0 reads as blocked")
	fake.sent.clear()
	var bad: Dictionary = await t.client.convert(15)
	_check(not bad.ok and bad.code == "invalid_pollen_spend" and fake.sent.is_empty(), "A count off the server's steps is refused here, nothing sent")
	var offline := Online.new()
	offline.on = false
	t.client.connectivity = offline
	var refused: Dictionary = await t.client.buy_sunshine()
	_check(not refused.ok and refused.code == "offline" and fake.sent.is_empty(), "Offline a spend is refused, never queued")
	t.client.connectivity = Online.new()
	t.fruits.set_enabled(SERVER, ME, false)
	var disabled: Dictionary = await t.client.convert(10)
	_check(not disabled.ok and disabled.code == "fruits_disabled" and fake.sent.is_empty(), "With Fruits off a convert is refused")

func _spend_refusals() -> void:
	for code: String in ["fruits_short", "fruits_blocked", "sunshine_active", "pollen_price_changed"]:
		var fake := Fake.new()
		fake.tree = self
		var t := _client(fake)
		var status := 402 if code == "fruits_short" else (403 if code == "fruits_blocked" else 409)
		fake.replies = [{"ok": false, "status": status, "code": code}, {"ok": true, "status": 200, "data": answer(part(5.0))}]
		var refused: Dictionary = await t.client.convert(10)
		_check(not refused.ok and refused.code == code and fake.sent.size() == 2 and fake.sent[1].method == HTTPClient.METHOD_GET and fake.sent[1].path == WardrobeClient.WALLET_PATH, "%s is final (no retry) and reads the wallet again" % code)
		_check(t.fruits.balance(SERVER, ME) == 5, "%s: the wallet read brings the Fruits up to date" % code)
	var fake := Fake.new()
	fake.tree = self
	var t := _client(fake)
	fake.replies = [{"ok": false, "status": 503, "code": "fruits_disabled"}, {"ok": false, "status": 503, "code": "fruits_disabled"}, {"ok": false, "status": 503, "code": "fruits_disabled"}]
	var down: Dictionary = await t.client.buy_sunshine()
	_check(not down.ok and down.code == "fruits_disabled" and fake.sent.size() == 3 and fake.sent.all(func(sent: Dictionary) -> bool: return sent.body == fake.sent[0].body), "A 503 goes again with the same key up to the limit")

# --- Claims ----------------------------------------------------------------------

func _claims() -> void:
	var wardrobe: RefCounted = Wardrobe.new(_path("claims-wardrobe"))
	wardrobe.set_enabled(SERVER, ME, true, true, false)
	var wallet: RefCounted = PollenWallet.new(_path("claims-wallet"))
	wallet.set_enabled(SERVER, ME, true)
	var fruits := _fruit_store()
	WalletReply.note(SERVER, ME, answer(part(40.0)), wallet, wardrobe, null, fruits, null)
	var path := _path("claims")
	var claims: RefCounted = BundleClaims.new(path, wardrobe, wallet, fruits)
	var fake := Fake.new()
	fake.tree = self
	claims.connect_to(null, func() -> Dictionary: return {"server": SERVER, "owner": ME}, fake.call_it)
	_check(not claims.scope().is_empty(), "Fruit packs on alone open the claim route (Pollen bundles off)")
	var credited := {"bundle": "bowl", "fruits": 110.0, "first_gift": 55.0, "order": "GPA.1111-2222-3333-44444", "purchased_at": 1.8e12, "usd_cents": 499.0}
	fake.replies = [_ok({"balance": 9000.0, "credited": [], "refunded": [], "fruit_credited": [credited, {"bundle": "pinch", "fruits": 5.0}], "fruit_refunded": [], "fruit_balance": 150.0})]
	var answer_claim: Dictionary = await claims.claim()
	_check(answer_claim.ok and answer_claim.fruit_credited.size() == 1 and answer_claim.fruit_credited[0].bundle == "bowl" and answer_claim.fruit_credited[0].fruits == 110 and answer_claim.fruit_balance == 150, "A Fruit pack is credited on the same claim; a Pollen bundle among Fruit lines is left out: %s" % [answer_claim])
	_check(not claims.pending() and fruits.balance(SERVER, ME) == 150, "A credited Fruit pack ends the waiting claim and its balance is kept")
	_check(claims.unseen().is_empty() and claims.unseen_fruits().size() == 1 and claims.unseen_fruits()[0].balance == 150, "Its receipt waits in the Fruits' own unseen list")
	var again: RefCounted = BundleClaims.new(path, wardrobe, wallet, fruits)
	again.connect_to(null, func() -> Dictionary: return {"server": SERVER, "owner": ME}, fake.call_it)
	_check(again.unseen_fruits() == claims.unseen_fruits(), "The unseen Fruit receipt survives a restart")
	again.mark_fruits_seen()
	_check(again.unseen_fruits().is_empty(), "Seen, it goes")
	var refund := BundleClaims.checked_answer({"schema_version": 1.0, "balance": 1000.0, "credited": [], "refunded": [], "fruit_credited": "x",
		"fruit_refunded": [{"bundle": "crate", "amount": -120.0, "order": "GPA.1", "pollen_taken": 4000.0, "store": "app_store"}, {"bundle": "crate", "amount": -120.0, "order": "GPA.1"}], "fruit_balance": -20.0})
	_check(refund.fruit_credited.is_empty() and refund.fruit_refunded == [{"bundle": "crate", "amount": -120, "order": "GPA.1", "pollen_taken": 4000, "store": "app_store"}] and refund.fruit_balance == -20, "Refunds keep the Pollen taken back; a broken list or line is left out: %s" % [refund])
	var old := BundleClaims.checked_answer({"schema_version": 1.0, "balance": 1000.0, "credited": [], "refunded": []})
	_check(not old.is_empty() and old.fruit_credited.is_empty() and not old.has("fruit_balance"), "An answer from before Fruits is still valid")
	var gone: RefCounted = FruitWallet.new(_path("claims-off"))
	var closed: RefCounted = BundleClaims.new(_path("claims-closed"), wardrobe, wallet, gone)
	closed.connect_to(null, func() -> Dictionary: return {"server": SERVER, "owner": ME}, fake.call_it)
	_check(closed.scope().is_empty(), "Neither bundles nor Fruit packs on: no claim")

# --- History -------------------------------------------------------------------

func _history() -> void:
	var value := {"schema_version": 1.0, "entries": [
		{"kind": "turn", "amount": 196.0, "at": 3.0, "level_id": "relay-isles", "stage_id": "garden", "role": "a", "sunshine": 98.0},
		{"kind": "convert", "amount": 4000.0, "at": 2.0}, {"kind": "reclaim", "amount": -400.0, "at": 1.0}, {"kind": "convert", "amount": -5.0, "at": 1.0}],
		"fruit_entries": [{"kind": "ach", "amount": 10.0, "at": 5.0, "id": "together_first", "level_id": "relay-isles"}, {"kind": "grant", "amount": 15.0, "at": 4.0, "step": 3.0},
			{"kind": "bundle", "amount": 110.0, "at": 3.0, "bundle": "bowl", "order": "GPA.1", "store": "app_store", "usd_cents": 599.0}, {"kind": "convert", "amount": -10.0, "at": 2.0},
			{"kind": "bundle", "amount": 5.0, "at": 1.0, "bundle": "pinch"}, {"kind": "ach", "amount": -10.0, "at": 1.0}, {"kind": "gift", "amount": 1.0, "at": 1.0}, {"kind": "grant", "amount": 1.0, "at": 1.0, "store": "play"}]}
	var kept := PollenHistory.checked(value)
	_check(kept.turns.size() == 1 and kept.turns[0].sunshine == 98, "A turn keeps Sunshine's Pollen")
	_check(kept.exchanges == [{"kind": "convert", "amount": 4000, "at": 2}, {"kind": "reclaim", "amount": -400, "at": 1}], "Convert and reclaim lines are kept with their sign: %s" % [kept.exchanges])
	_check(kept.fruit_entries.size() == 4 and kept.fruit_entries[0].id == "together_first" and kept.fruit_entries[1].step == 3 and kept.fruit_entries[2].store == "app_store" and kept.fruit_entries[3].amount == -10, "Fruit lines keep what each kind names; broken ones are left out: %s" % [kept.fruit_entries])
	var broken := PollenHistory.checked({"schema_version": 1.0, "entries": [], "fruit_entries": "x"})
	_check(not broken.is_empty() and broken.fruit_entries.is_empty() and broken.exchanges.is_empty(), "A broken Fruit list reads as none and the rest still shows")

# --- The Orchard's prices --------------------------------------------------------

func _wardrobe_prices() -> void:
	var view := Wardrobe.checked_view(answer())
	_check(view.fruit_prices == {"fruit_cap": 50, "apple_leaf": 25, "orchard_skin": 100, "sprig_sun": 10} and view.fruit_sets == {"orchard": ["fruit_cap", "orchard_skin", "apple_leaf"]} and view.prices == {"daisy": 1000}, "The view keeps the Orchard's prices and sets apart from Pollen's")
	_check(Wardrobe.spend_currency(view, "fruit_cap") == "fruits" and Wardrobe.spend_currency(view, "orchard") == "fruits" and Wardrobe.spend_currency(view, "daisy") == "pollen", "Each spend names its currency")
	_check(Wardrobe.spend_price(view, "fruit_cap") == 50 and Wardrobe.spend_price(view, "daisy") == 1000 and Wardrobe.set_pieces(view, "orchard").size() == 3, "and its price in that currency")
	var broken := answer()
	broken.wardrobe.fruit_prices = {"fruit_cap": -5.0, "Bad": 5.0, "sprig_sun": 10.0}
	broken.wardrobe.fruit_sets = "x"
	var kept := Wardrobe.checked_view(broken)
	_check(not kept.is_empty() and kept.fruit_prices == {"sprig_sun": 10} and kept.fruit_sets.is_empty(), "Broken Orchard prices or sets are left out; the wardrobe still reads")
	var store: RefCounted = Wardrobe.new(_path("orchard"))
	store.set_enabled(SERVER, ME, true, true)
	store.note_view(SERVER, ME, answer())
	_check(Wardrobe.new(store.path).view(SERVER, ME).fruit_prices.size() == 4, "The Orchard's prices survive a restart")
	_check(Catalog.currency("daisy") == "pollen" and Catalog.currency("no_such_item") == "pollen", "Pollen items and unknown ids read as Pollen")
	# The Orchard items and their tiers come with the art kit (content/cosmetics/index.gd TIER_CURRENCY).
	for id: String in ["fruit_cap", "blossom_crown", "orchard_skin", "apple_leaf", "sprig_coral", "sprig_plum", "sprig_sun", "sprig_sky"]:
		if Catalog.has(id): _check(Catalog.currency(id) == "fruits", "%s is sold for Fruits by its tier" % id)

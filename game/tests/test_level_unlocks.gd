extends SceneTree
## Opening a chapter with Fruits, on the phone, through fake transports,
## synthetic ids and a synthetic price (no registered chapter has one yet):
## - the descriptor field "unlock" ({} by default on every chapter);
## - the gate (services/chapter_unlocks.gd): a priced chapter is locked for a
##   free player until paid, open with Full Journey, its card's note the price
##   while the server sells levels and the Full Journey line while it does not;
## - the kept Fruits (services/fruit_wallet.gd): the read's `levels` part, the
##   opened levels that only grow, a restart keeps them;
## - the spend (services/wardrobe_client.gd unlock_level): its body, one key for
##   every send of one tap, a stale refusal reading the wallet again;
## - the confirm card and the short card (presentation/fruit_spend_flow.gd).
const Unlocks = preload("res://services/chapter_unlocks.gd")
const Index = preload("res://content/chapters/index.gd")
const Registry = preload("res://services/chapter_registry.gd")
const FruitWallet = preload("res://services/fruit_wallet.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const WardrobeClient = preload("res://services/wardrobe_client.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const Connectivity = preload("res://services/connectivity.gd")
const SpendFlow = preload("res://presentation/fruit_spend_flow.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const PollenHistory = preload("res://services/pollen_history.gd")
const FruitLines = preload("res://presentation/fruit_wallet_view.gd")

# Synthetic ids only.
const SERVER := "https://levels.example.test"
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const PRICE := 3

var checks := 0
var failures := 0
var _paths: Array[String] = []
## A free chain chapter given the synthetic price, and its level id.
var key := ""
var level := ""

class Online extends RefCounted:
	var on := true
	signal changed(online: bool)
	func online() -> bool: return on
	func check_now() -> void: pass

## The routes: answers each request with the next reply, or no answer.
class Server extends RefCounted:
	var replies: Array = []
	var sent: Array = []
	func call_it(method: int, path: String, body: Dictionary) -> Dictionary:
		await Engine.get_main_loop().process_frame
		sent.append({"method": method, "path": path, "body": body.duplicate(true)})
		return replies.pop_front() if not replies.is_empty() else {"ok": false, "status": 0, "code": "connection_interrupted"}

class Host extends Node:
	var said: Array = []
	var api: Node = null
	func _toast(text: String) -> void: said.append(text)

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _path(stem: String) -> String:
	var path := "user://test-levels-%s-%s.json" % [stem, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

func _run() -> void:
	var online := Online.new()
	Connectivity.use_shared(online)
	PollenSurfaces.set_shared_for_tests(true, true)
	for candidate: String in Unlocks.chain():
		if not Registry.descriptor(candidate).get("premium", false) and Unlocks.opens_after(candidate) != "":
			key = candidate
			break
	level = key.get_slice("@", 0)
	Unlocks.prices_override = {level: PRICE}
	_descriptors()
	_gate()
	_kept()
	await _spend()
	await _card(online)
	Unlocks.prices_override = {}
	Connectivity.use_shared(null)
	PollenSurfaces.set_shared_for_tests(null)
	for path: String in _paths:
		for candidate: String in [path, path + ".tmp", path + ".backup"]:
			if FileAccess.file_exists(candidate): DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
	print("LEVEL UNLOCKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

## The wallet read's Fruits part with `levels`.
static func part(balance: float, levels: Variant) -> Dictionary:
	var value := {"schema_version": 1.0, "balance": balance, "earned": 60.0, "first_pack_gift": false, "first_pack_percent": 100.0, "achievements": []}
	if levels != null: value.levels = levels
	return value

static func levels_part(open: Array = []) -> Dictionary:
	return {"prices": {"test-level-x": 7.0}, "open": open}

func _fruits(stem: String, balance: float, levels: Variant) -> RefCounted:
	var store: RefCounted = FruitWallet.new(_path(stem))
	store.set_enabled(SERVER, ME, true, true)
	store.note_view(SERVER, ME, {"fruits": part(balance, levels)})
	return store

func _client(server: Server, fruits: RefCounted) -> RefCounted:
	var wardrobe: RefCounted = Wardrobe.new(_path("wardrobe"))
	wardrobe.set_enabled(SERVER, ME, true, true)
	var wallet: RefCounted = PollenWallet.new(_path("wallet"))
	wallet.set_enabled(SERVER, ME, true)
	wallet.note_wallet(SERVER, ME, {"schema_version": 1.0, "balance": 900.0, "earned": 900.0, "bank": 12.0})
	var client: RefCounted = WardrobeClient.new(null, func() -> Dictionary: return {"server": SERVER, "owner": ME}, server.call_it, wardrobe, wallet, null, fruits)
	client.connectivity = Online.new()
	return client

static func _ok(data: Dictionary) -> Dictionary:
	return {"ok": true, "status": 200, "data": data.merged({"schema_version": 1.0})}

# --- Descriptors and the gate ----------------------------------------------------

func _descriptors() -> void:
	_check(not key.is_empty(), "A free chain chapter after First Steps carries the synthetic price")
	for registered: String in Index.keys():
		var unlock: Variant = Index.data(registered).get("unlock")
		_check(unlock is Dictionary, "%s has the unlock field, {} unless priced" % registered)
	_check(Index.OPTIONAL.unlock == {}, "A chapter is free unless its descriptor names a price")

func _gate() -> void:
	var on := {"on": true, "open": []}
	var state := Unlocks.unsettled(false, on)
	_check(Unlocks.price(key) == PRICE and Unlocks.price(Unlocks.chain()[0]) == 0, "The price is the chapter's; an unpriced one is 0")
	_check(Unlocks.fruit_locked(key, state) and not Unlocks.open(key, state) and Unlocks.reached(key, state), "A free player has reached it but its price locks it")
	_check(Unlocks.fruit_offered(key, state), "While the server sells levels, a tap offers the price")
	_check(Unlocks.reason(key, state, true) == PlayerCopy.LEVEL_UNLOCK_NOTE % PollenMoney.grouped(PRICE), "Its card says the price: %s" % Unlocks.reason(key, state, true))
	var item := {"key": key, "locked": false}
	_check(Unlocks.lock_entry(item, state) and item.locked and item.note == PlayerCopy.LEVEL_UNLOCK_NOTE % PollenMoney.grouped(PRICE), "The card is locked with the price as its note")
	var off := Unlocks.unsettled(false, {"on": false, "open": []})
	_check(Unlocks.fruit_locked(key, off) and not Unlocks.fruit_offered(key, off) and Unlocks.reason(key, off) == PlayerCopy.CHAPTER_LOCKED_FULL_JOURNEY, "Levels off: a Full Journey chapter, nothing offered")
	var none := Unlocks.unsettled(false)
	_check(Unlocks.fruit_locked(key, none) and not Unlocks.fruit_offered(key, none), "Before any read it stays locked and offers nothing")
	var paid := Unlocks.unsettled(false, {"on": true, "open": [level]})
	var open_item := {"key": key, "locked": false}
	_check(Unlocks.open(key, paid) and not Unlocks.fruit_locked(key, paid) and not Unlocks.lock_entry(open_item, paid) and not open_item.locked, "Paid: open, its card unlocked")
	var paid_off := Unlocks.unsettled(false, {"on": false, "open": [level]})
	_check(Unlocks.open(key, paid_off), "Paid stays open with levels switched off")
	var journey := Unlocks.unsettled(true, on)
	_check(Unlocks.open(key, journey) and not Unlocks.fruit_offered(key, journey), "Full Journey plays it free")
	var progress := Unlocks.progress([], {}, {}, false, [], on)
	_check(not Unlocks.reached(key, progress) and Unlocks.reason(key, progress, true) == PlayerCopy.CHAPTER_LOCKED_NOTE % Unlocks.title(Unlocks.opens_after(key)), "Not reached yet: the chain's own lock comes first")
	_check(Unlocks.join_header(Unlocks.progress([], {}, {}, false, [], on)) == Unlocks.join_header(Unlocks.progress([], {}, {}, false)), "A join's header is the chain's alone: the host covers the price")

# --- The kept Fruits -----------------------------------------------------------

func _kept() -> void:
	var path := _path("kept")
	var store: RefCounted = FruitWallet.new(path)
	store.set_enabled(SERVER, ME, true, true)
	store.note_view(SERVER, ME, {"fruits": part(40.0, null)})
	_check(not store.level_unlocks_on(SERVER, ME) and store.opened_levels(SERVER, ME).is_empty(), "A part without levels: none sold, none open")
	store.note_view(SERVER, ME, {"fruits": part(40.0, levels_part(["test-level-x"]))})
	_check(store.level_unlocks_on(SERVER, ME) and store.opened_levels(SERVER, ME) == ["test-level-x"], "The read's open list is kept")
	_check(store.note_spend(SERVER, ME, {"kind": "level", "id": level, "fruit_balance": 37.0}) and level in store.opened_levels(SERVER, ME) and store.balance(SERVER, ME) == 37, "A level receipt opens it and keeps the balance")
	store.note_view(SERVER, ME, {"fruits": part(37.0, levels_part([]))})
	_check(store.opened_levels(SERVER, ME).size() == 2, "A late read never closes a level paid for")
	store.note_view(SERVER, ME, {"fruits": part(37.0, null)})
	_check(not store.level_unlocks_on(SERVER, ME) and store.opened_levels(SERVER, ME).size() == 2, "Levels switched off: nothing sold, still open")
	var again: RefCounted = FruitWallet.new(path)
	_check(again.opened_levels(SERVER, ME) == store.opened_levels(SERVER, ME), "A restart keeps the opened levels")
	for bad: Variant in [{"prices": {"Bad_Id": 3.0}, "open": []}, {"prices": {"x": 0.0}, "open": []}, {"prices": {}, "open": ["../x"]}, {"prices": [], "open": []}]:
		_check(FruitWallet.checked_levels(bad).is_empty(), "A levels part off the contract is dropped: %s" % [bad])
	var kept := FruitWallet.checked_part(part(5.0, {"prices": {"x": 0.0}, "open": []}))
	_check(kept.balance == 5 and not kept.has("levels"), "and the rest of the part is kept")
	var line: Dictionary = PollenHistory._fruit_line({"kind": "level", "amount": -3.0, "at": 1.0, "level_id": level})
	_check(line.get("kind") == "level" and line.get("level_id") == level and FruitLines.name_of(line) == PlayerCopy.FRUIT_LINE_LEVEL, "The Fruits history lists an unlock as Chapter opened, its chapter beside it")
	_check(PollenHistory._fruit_line({"kind": "level", "amount": 3.0, "at": 1.0}).is_empty(), "An unlock line that adds Fruits is off the contract")

# --- The spend -----------------------------------------------------------------

func _spend() -> void:
	var server := Server.new()
	var fruits := _fruits("spend", 40.0, levels_part())
	var client := _client(server, fruits)
	server.replies = [{"ok": false, "status": 0, "code": "connection_interrupted"}, _ok({"kind": "level", "id": level, "pieces": [], "cost": float(PRICE), "currency": "fruits", "balance": 900.0, "fruit_balance": 37.0})]
	var answer: Dictionary = await client.unlock_level(level, PRICE)
	var body: Dictionary = server.sent[0].body if not server.sent.is_empty() else {}
	_check(answer.ok and server.sent.size() == 2 and server.sent[0].body == server.sent[1].body, "A tap with no answer goes again with the same key and body")
	_check(body.get("kind") == "level" and body.get("id") == level and body.get("expected_cost") == PRICE and server.sent[0].path == WardrobeClient.SPEND_PATH, "It sends kind level, the level id and the card's price: %s" % [body])
	_check(level in fruits.opened_levels(SERVER, ME) and fruits.balance(SERVER, ME) == 37, "The receipt opens the level and keeps the Fruits")
	server.sent.clear()
	server.replies = [{"ok": false, "status": 409, "code": "already_owned"}, {"ok": true, "status": 200, "data": {"schema_version": 1.0, "balance": 900.0, "earned": 900.0, "bank": 12.0,
		"wardrobe": {"items": [], "packs": [], "look": {}, "look_revision": 1.0, "offered": [], "offered_packs": [], "sets": {}, "unlocked": [], "prices": {}},
		"fruits": part(37.0, levels_part(["test-level-y"]))}}]
	var again: Dictionary = await client.unlock_level("test-level-y", PRICE)
	_check(not again.ok and again.code == "already_owned" and server.sent.size() == 2 and server.sent[1].path == WardrobeClient.WALLET_PATH and server.sent[0].body.idempotency_key != body.idempotency_key, "A second tap is a new key; already_owned reads the wallet again")
	_check("test-level-y" in fruits.opened_levels(SERVER, ME), "and that read keeps the level open")
	server.sent.clear()
	var off_store := _fruits("spend-off", 40.0, null)
	var off: Dictionary = await _client(server, off_store).unlock_level(level, PRICE)
	_check(not off.ok and off.code == "level_unlocks_disabled" and server.sent.is_empty(), "Levels off: refused here, nothing sent")
	var bad: Dictionary = await client.unlock_level(level, 0)
	_check(not bad.ok and bad.code == "invalid_pollen_spend" and server.sent.is_empty(), "No price: refused here")

# --- The confirm card ------------------------------------------------------------

func _card(online: Online) -> void:
	var host := Host.new()
	root.add_child(host)
	var spend: Node = SpendFlow.new(host)
	host.add_child(spend)
	var parent := Control.new()
	parent.size = Vector2(1561, 720)
	host.add_child(parent)
	var spent: Array = []
	spend.spent.connect(func(kind: String) -> void: spent.append(kind))
	var server := Server.new()
	var fruits := _fruits("card", 40.0, levels_part())
	spend.client = _client(server, fruits)
	spend.unlock_level(key, parent)
	var card: Control = spend.sheet()
	_check(card != null and card.name == "WardrobeConfirm", "With the Fruits: the shared Fruit confirm card")
	_check(card != null and card.find_child("LevelUnlockArt", true, false) != null and card.find_child("WardrobeConfirmPip", true, false) == null, "The chapter's picture stands where the pip would")
	_check(card != null and card.title_label.text == PlayerCopy.LEVEL_UNLOCK_TITLE % Unlocks.title(key), "Open [chapter]?")
	var confirm: Button = card.find_child("LevelUnlockConfirm", true, false) if card != null else null
	_check(confirm != null and confirm.find_child("WardrobeBuyContent", true, false) != null, "A plum Open for [Fruit] 3")
	server.replies = [_ok({"kind": "level", "id": level, "pieces": [], "cost": float(PRICE), "currency": "fruits", "balance": 900.0, "fruit_balance": 37.0})]
	if confirm != null: confirm.pressed.emit()
	for frame in range(8): await process_frame
	_check(server.sent.size() == 1 and server.sent[0].body.kind == "level" and spent == ["level"], "Open sends the spend once and says a level opened")
	_check(not host.said.is_empty() and host.said.back() == PlayerCopy.LEVEL_UNLOCK_DONE % Unlocks.title(key), "and says the chapter is open")
	spend.client = _client(server, _fruits("card-short", 2.0, levels_part()))
	spend.unlock_level(key, parent)
	_check(spend.sheet() != null and spend.sheet().name == "WardrobeShort", "Short of the price: the shared short card")
	spend._close_sheet()
	spend.client = _client(server, _fruits("card-off", 40.0, null))
	spend.unlock_level(key, parent)
	_check(spend.sheet() == null and host.said.back() == PlayerCopy.FRUIT_SPEND_ERRORS.level_unlocks_disabled, "Levels off: no card, the reason shows")
	spend.client = _client(server, _fruits("card-offline", 40.0, levels_part()))
	online.on = false
	spend.unlock_level(key, parent)
	_check(spend.sheet() == null and host.said.back() == PlayerCopy.OFFLINE_NEEDS_CONNECTION, "Offline: nothing opens and the reason shows")
	online.on = true
	host.queue_free()
	for frame in range(2): await process_frame

extends SceneTree
## Item blooms on this phone (services/pollen_wallet.gd, presentation/pollen_result_line.gd,
## presentation/pollen_odds.gd):
## - a receipt's item_bloom is kept only in the contract's shapes: an item, or
##   the tier's Pollen when the player had every item it could bring;
## - the results line says "A lucky bloom: a new Daisy!" beside the player's own
##   still pip wearing the new item, never a live view; the Pollen case gets the
##   flower; no dashes;
## - the dropped item is owned in the wardrobe at once;
## - Help publishes the odds, the item odds only while the server says item
##   blooms drop, on every build; a build that sells nothing leaves out the
##   sentence that names Full Journey.
const PollenWallet = preload("res://services/pollen_wallet.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const ResultLine = preload("res://presentation/pollen_result_line.gd")
const PollenOdds = preload("res://presentation/pollen_odds.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")

# Synthetic ids only.
const SERVER := "https://pollen.example.test"
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"

var checks := 0
var failures := 0
var _paths: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_receipts()
	_lines()
	await _built_line()
	_owned_at_once()
	_odds()
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	PollenWallet.use_shared(null)
	Wardrobe.use_shared(null)
	PollenSurfaces.set_shared_for_tests(null)
	print("AFTER YOU POLLEN ITEM BLOOM: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _path(label: String) -> String:
	var path := "user://test-pollen-item-bloom-%s-%s.json" % [label, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

static func _hash(n: int) -> String:
	return ("%x" % n).lpad(64, "0")

## A bank turn's receipt that dropped `bloom` (numbers as floats, as the server sends them).
static func _receipt(bloom: Dictionary, earned: int = 89) -> Dictionary:
	return {"schema_version": 1.0, "earned": float(earned), "balance": float(earned), "clears": [], "item_bloom": bloom,
		"turn": {"kind": "bank", "base": 89.0, "bonuses": [], "bonus_percent": 0.0, "amount": 89.0, "bloom": 1.0, "bloom_extra": 0.0, "boost_percent": 0.0, "boost": 0.0, "total": 89.0}}

func _receipts() -> void:
	var item := PollenWallet.checked_receipt(_receipt({"tier": "common", "roll": 5000.0, "item_id": "daisy"}))
	_check(item.get("item_bloom") == {"tier": "common", "item_id": "daisy"}, "A dropped item is kept as its tier and id")
	var pollen := PollenWallet.checked_receipt(_receipt({"tier": "rare", "roll": 900.0, "pollen": 20000.0}, 20089))
	_check(pollen.get("item_bloom") == {"tier": "rare", "pollen": 20000}, "A fully owned tier's Pollen is kept")
	for broken: Dictionary in [{"tier": "earned", "item_id": "gold_leaf"}, {"tier": "common", "item_id": "Bad Id"}, {"tier": "common", "item_id": "daisy", "pollen": 1000.0},
			{"tier": "common", "pollen": 0.0}, {"tier": "common"}, {"tier": "mythic", "item_id": "daisy"}]:
		_check(PollenWallet.checked_receipt(_receipt(broken)).is_empty(), "A receipt with a broken item bloom is not kept: " + str(broken))
	var plain := _receipt({})
	plain.erase("item_bloom")
	_check(not PollenWallet.checked_receipt(plain).has("item_bloom"), "A turn with no drop keeps no item bloom")

func _lines() -> void:
	var item := PollenWallet.checked_receipt(_receipt({"tier": "common", "roll": 5000.0, "item_id": "daisy"}))
	_check(ResultLine.lines(item, "Maya") == PackedStringArray(["+89 Pollen", "@daisy|A lucky bloom: a new Daisy!"]), "A drop names the new item, where the pip goes")
	var pollen := PollenWallet.checked_receipt(_receipt({"tier": "common", "roll": 5000.0, "pollen": 1000.0}, 1089))
	_check(ResultLine.lines(pollen, "Maya") == PackedStringArray(["+1089 Pollen", "*A lucky bloom: +1,000 Pollen"]), "A fully owned tier pays its price, with the flower")
	var unknown := PollenWallet.checked_receipt(_receipt({"tier": "rare", "roll": 900.0, "item_id": "future_item"}))
	_check(ResultLine.lines(unknown, "")[1] == "@future_item|A lucky bloom: a new item for your pip!", "An item this build does not know yet still reads plainly")
	for line: String in [PlayerCopy.POLLEN_ITEM_BLOOM, PlayerCopy.POLLEN_ITEM_BLOOM_POLLEN, PlayerCopy.POLLEN_ITEM_BLOOM_UNKNOWN, PlayerCopy.POLLEN_ODDS, PlayerCopy.POLLEN_ODDS_ITEMS, PlayerCopy.POLLEN_ODDS_PAID, PlayerCopy.POLLEN_ODDS_TITLE]:
		_check(not line.contains("-") and not line.contains("—") and not line.contains("–"), "No dashes: " + line)

func _built_line() -> void:
	var store := PollenWallet.new(_path("line"))
	var wardrobe := Wardrobe.new(_path("line-wardrobe"))
	Wardrobe.use_shared(wardrobe)
	store.set_enabled(SERVER, ME, true)
	store.note_receipt(SERVER, ME, ROOM, _hash(1), _receipt({"tier": "common", "roll": 5000.0, "item_id": "daisy"}))
	PollenSurfaces.set_shared_for_tests(true)
	var line: Control = ResultLine.build({"server": SERVER, "owner": ME}, ROOM, _hash(1), "Maya", Color.WHITE, store)
	_check(line != null, "The line shows for a drop")
	if line == null: return
	root.add_child(line)
	await process_frame
	var pip := line.find_child("PollenItemBloomPip", true, false)
	_check(pip != null and bool(pip.get("still")), "The new item shows on a still pip, never a live view")
	_check(pip != null and pip.get("outfit") == {"hat": "daisy"}, "The pip wears the item that dropped")
	_check(line.find_child("PollenBloomFlower", true, false) == null, "An item drop has its pip, not a flower")
	var texts: Array = line.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)
	_check("A lucky bloom: a new Daisy!" in texts, "The words beside it: " + str(texts))
	line.queue_free()
	await process_frame

func _owned_at_once() -> void:
	var wardrobe := Wardrobe.new(_path("owned"))
	Wardrobe.use_shared(wardrobe)
	var store := PollenWallet.new(_path("owned-wallet"))
	store.item_dropped.connect(wardrobe.note_drop)
	store.set_enabled(SERVER, ME, true)
	wardrobe.set_enabled(SERVER, ME, true)
	wardrobe.note_view(SERVER, ME, {"schema_version": 1.0, "balance": 0.0, "earned": 0.0, "bank": 12.0, "name_price": 0.0,
		"wardrobe": {"items": ["seashell"], "packs": [], "look": {}, "look_revision": 0.0, "offered": ["daisy", "seashell"], "offered_packs": [], "sets": {}, "unlocked": []}})
	store.note_receipt(SERVER, ME, ROOM, _hash(2), _receipt({"tier": "common", "roll": 5000.0, "item_id": "daisy"}))
	_check(wardrobe.view(SERVER, ME).items == ["daisy", "seashell"], "The dropped item is owned in the wardrobe at once")
	store.note_receipt(SERVER, ME, ROOM, _hash(2), _receipt({"tier": "common", "roll": 5000.0, "item_id": "daisy"}))
	_check(wardrobe.view(SERVER, ME).items == ["daisy", "seashell"], "The same receipt again owns it once")

func _odds() -> void:
	var store := PollenWallet.new(_path("odds"))
	var scope := {"server": SERVER, "owner": ME}
	PollenSurfaces.set_shared_for_tests(true)
	_check(not PollenOdds.shown(scope, store), "No odds while Pollen is off")
	store.set_enabled(SERVER, ME, true)
	_check(PollenOdds.shown(scope, store) and not PollenOdds.shown({}, store), "Shown with Pollen on, only for a signed in player")
	_check(PollenOdds.note(scope, store) == PlayerCopy.POLLEN_ODDS + " " + PlayerCopy.POLLEN_ODDS_PAID, "Lucky bloom odds only while items do not drop")
	PollenSurfaces.set_shared_for_tests(false)
	_check(PollenOdds.shown(scope, store), "A build that sells nothing publishes the odds too")
	_check(PollenOdds.note(scope, store) == PlayerCopy.POLLEN_ODDS, "There without the sentence that names Full Journey")
	PollenSurfaces.set_shared_for_tests(true)
	store.set_item_blooms(SERVER, ME, true)
	var note := PollenOdds.note(scope, store)
	_check(note.contains("8 pay double and 2 pay triple") and note.contains("Special 2, Epic 160, Rare 1,600, Uncommon 2,500 and Common 5,000"), "Item odds are published while they drop: " + note)
	var again := PollenWallet.new(store.path)
	_check(again.item_blooms(SERVER, ME), "The item bloom flag survives a restart")
	again.set_enabled(SERVER, ME, false)
	_check(not again.item_blooms(SERVER, ME), "and means nothing while Pollen is off")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

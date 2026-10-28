extends SceneTree
## Pollen on this phone (services/pollen_wallet.gd and its neighbours):
## - the server's answers are checked before anything is kept, and only whole
##   numbers and known words pass;
## - a confirmed receipt is kept for the results line, its claim goes, and the
##   balance follows it; a turn without one waits to be claimed, once, at most
##   32 of them and none older than 28 days;
## - everything is kept per server and player, survives a restart, and a file
##   that cannot be read reads as empty (the client then asks the server again);
## - rooms_api asks for Pollen on the capability and on turns, and takes the
##   credit out of a turn reply, so the room kept is unchanged;
## - the results line: its words, the boost line naming whose Full Journey it
##   was, the flower for a bloom, and nothing while Pollen is off or on a build
##   that hides paid content.
const PollenWallet = preload("res://services/pollen_wallet.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const ResultLine = preload("res://presentation/pollen_result_line.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

# Synthetic ids only.
const SERVER := "https://pollen.example.test"
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const OTHER := "bbbbbbbbbbbbbbbbbbbbbb"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const DAY_MS := 86400000

var checks := 0
var failures := 0
var _paths: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_receipts()
	_claims()
	_results()
	_clears()
	_scopes_and_file()
	_damaged_file()
	_rooms_api()
	_result_line()
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	PollenWallet.use_shared(null)
	PollenSurfaces.set_shared_for_tests(null)
	print("AFTER YOU POLLEN WALLET: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _path(label: String) -> String:
	var path := "user://test-pollen-wallet-%s-%s.json" % [label, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

func _store() -> RefCounted:
	return PollenWallet.new(_path("store"))

static func _hash(n: int) -> String:
	return ("%x" % n).lpad(64, "0")

## A receipt as the server sends it (JSON numbers arrive as floats).
static func _receipt(earned: float = 98.0, balance: float = 98.0, extra: Dictionary = {}) -> Dictionary:
	var turn := {"kind": "bank", "base": 89.0, "bonuses": ["first_try"], "bonus_percent": 25.0, "amount": 89.0, "bloom": 1.0, "bloom_extra": 0.0,
		"boost_percent": 10.0, "boost": 9.0, "total": earned, "boost_from": ["partner"]}
	turn.merge(extra, true)
	return {"schema_version": 1.0, "earned": earned, "balance": balance, "turn": turn, "clears": []}

func _receipts() -> void:
	var good := PollenWallet.checked_receipt(_receipt())
	_check(not good.is_empty() and good.earned is int and good.turn.amount is int and good.turn.bloom == 1, "A receipt is kept with whole numbers")
	_check(PollenWallet.checked_receipt(_receipt(10.0, 10.0, {"reason": "late"})).turn.reason == "late", "A late turn's reason is kept")
	for broken: Dictionary in [{"bloom": 4.0}, {"bloom": 1.5}, {"bonuses": ["luck"]}, {"kind": "jackpot"}, {"total": -1.0}, {"boost_percent": 101.0}, {"reason": "streak"}, {"boost_from": ["stranger"]}]:
		_check(PollenWallet.checked_receipt(_receipt(98.0, 98.0, broken)).is_empty(), "A turn line with %s is refused" % JSON.stringify(broken))
	var wrong := _receipt()
	wrong.schema_version = 2.0
	_check(PollenWallet.checked_receipt(wrong).is_empty(), "So is another schema")
	wrong = _receipt()
	wrong.erase("clears")
	_check(PollenWallet.checked_receipt(wrong).is_empty(), "and a receipt without its clears list")
	wrong = _receipt()
	wrong.clears = [{"kind": "clear", "level_id": "first-steps", "amount": 1200.0, "boost_percent": 0.0, "boost": 0.0, "total": 1200.0}]
	_check(PollenWallet.checked_receipt(wrong).clears == [{"kind": "clear", "total": 1200, "boost_percent": 0}], "A first clear line is kept")
	wrong.clears[0].kind = "prize"
	_check(PollenWallet.checked_receipt(wrong).is_empty(), "an unknown clear is not")
	var no_turn := _receipt()
	no_turn.erase("turn")
	_check(not PollenWallet.checked_receipt(no_turn).is_empty(), "A clear's receipt has no turn line")
	_check(PollenWallet.checked_wallet({"schema_version": 1.0, "balance": 10.0, "earned": 12.0, "bank": 3.0}) == {"balance": 10, "earned": 12, "bank": 3}, "A wallet answer is kept")
	_check(PollenWallet.checked_wallet({"schema_version": 1.0, "balance": 1.5, "earned": 0.0, "bank": 0.0}).is_empty() and PollenWallet.checked_wallet({"balance": 1.0}).is_empty(), "A broken one is not")
	_check(PollenWallet.checked_wallet({"schema_version": 1.0, "balance": -4750.0, "earned": 4500.0, "bank": 0.0}) == {"balance": -4750, "earned": 4500, "bank": 0}, "A balance a refund took below zero is kept")

func _claims() -> void:
	var store := _store()
	var now := 1_800_000_000_000
	_check(store.queue_claim(SERVER, ME, ROOM, _hash(1), now), "An unconfirmed turn waits to be claimed")
	_check(store.queue_claim(SERVER, ME, ROOM, _hash(1), now) and store.claims(SERVER, ME, 32, now).size() == 1, "once")
	_check(not store.queue_claim(SERVER, ME, "short", _hash(2), now) and not store.queue_claim(SERVER, ME, ROOM, "nothex", now), "Only a room id and a recording hash are kept")
	for n in range(2, 40): store.queue_claim(SERVER, ME, ROOM, _hash(n), now + n)
	var waiting: Array = store.claims(SERVER, ME, 100, now + 100)
	_check(waiting.size() == PollenWallet.MAX_CLAIMS and waiting[0].recording_hash == _hash(8), "At most 32 wait; the oldest go first")
	_check(store.claims(SERVER, ME, 4, now + 100).size() == 4 and waiting[0].keys() == ["room_id", "recording_hash"], "A send takes four, as the route does")
	_check(store.claims(SERVER, ME, 100, now + 29 * DAY_MS).is_empty(), "A claim older than 28 days goes: the server would refuse it")
	store.queue_claim(SERVER, ME, ROOM, _hash(50), now)
	store.queue_claim(SERVER, ME, ROOM, _hash(51), now)
	store.queue_claim(SERVER, ME, ROOM, _hash(52), now)
	store.settle_claim(SERVER, ME, ROOM, _hash(50), {"status": "refused", "code": "pollen_turn_not_found"})
	store.settle_claim(SERVER, ME, ROOM, _hash(51), {"status": "retry"})
	store.settle_claim(SERVER, ME, ROOM, _hash(52), {"status": "credited", "receipt": _receipt()})
	var left: Array = store.claims(SERVER, ME, 100, now).map(func(entry: Dictionary) -> String: return entry.recording_hash)
	_check(not _hash(50) in left and _hash(51) in left and not _hash(52) in left, "A refused claim goes for good, retry keeps it, credited keeps its receipt")
	_check(not store.result_for(SERVER, ME, ROOM, _hash(52)).is_empty(), "The credited one shows its line")
	store.settle_claim(SERVER, ME, ROOM, _hash(51), {"status": "credited", "receipt": {"schema_version": 1.0}})
	_check(not _hash(51) in store.claims(SERVER, ME, 100, now).map(func(entry: Dictionary) -> String: return entry.recording_hash), "A credited claim whose receipt is broken still goes: the server paid it")
	_check(not store.queue_claim(SERVER, ME, ROOM, _hash(52), now), "A turn with a confirmed result is never claimed again")

func _results() -> void:
	var store := _store()
	_check(store.note_wallet(SERVER, ME, {"schema_version": 1.0, "balance": 500.0, "earned": 900.0, "bank": 5.0}), "The wallet answer is kept")
	store.queue_claim(SERVER, ME, ROOM, _hash(7))
	_check(store.note_receipt(SERVER, ME, ROOM, _hash(7), _receipt(98.0, 598.0)), "A turn's receipt is kept")
	_check(store.claims(SERVER, ME).is_empty(), "and its claim goes")
	_check(store.wallet(SERVER, ME) == {"balance": 598, "earned": 900, "bank": 5}, "The balance follows the receipt; earned and bank wait for the next wallet answer")
	_check(not store.note_receipt(SERVER, ME, ROOM, _hash(8), {"schema_version": 1.0, "pending": true}), "A pending answer is not a receipt")
	for n in range(10, 20): store.note_receipt(SERVER, ME, ROOM, _hash(n), _receipt())
	_check(store.result_for(SERVER, ME, ROOM, _hash(7)).is_empty() and not store.result_for(SERVER, ME, ROOM, _hash(19)).is_empty(), "Only the newest results are kept")
	_check(store.result_for(SERVER, ME, "QQQQQQQQQQQQQQQQQQQQQQ", _hash(19)).is_empty(), "A result belongs to its room")

func _clears() -> void:
	var path := _path("clears")
	var store: RefCounted = PollenWallet.new(path)
	_check(store.queue_clear(SERVER, ME, "room:" + ROOM) and store.queue_clear(SERVER, ME, "level:first-steps"), "A room seen finished and a chapter finished solo wait to be claimed")
	_check(not store.queue_clear(SERVER, ME, "room:" + ROOM), "once")
	_check(not store.queue_clear(SERVER, ME, "room:short") and not store.queue_clear(SERVER, ME, "level:Bad Level") and not store.queue_clear(SERVER, ME, "prize:x"), "Only a room id or a chapter id")
	_check(store.clear_claims(SERVER, ME) == [{"key": "room:" + ROOM, "claim": {"room_id": ROOM}}, {"key": "level:first-steps", "claim": {"level_id": "first-steps"}}], "Each goes as the route takes it")
	store.settle_clear(SERVER, ME, "room:" + ROOM, {"status": "retry"})
	_check(store.clear_claims(SERVER, ME)[0].key == "level:first-steps", "A clear the server cannot settle yet goes behind the others")
	store.settle_clear(SERVER, ME, "level:first-steps", {"status": "credited", "receipt": _receipt(1200.0, 1200.0)})
	store.settle_clear(SERVER, ME, "room:" + ROOM, {"status": "refused", "code": "pollen_clear_not_found"})
	_check(store.clear_claims(SERVER, ME).is_empty() and store.cleared(SERVER, ME, "level:first-steps") and store.cleared(SERVER, ME, "room:" + ROOM), "Credited and refused are settled")
	_check(not store.queue_clear(SERVER, ME, "level:first-steps"), "and never sent again")
	store.mark_cleared(SERVER, ME, "room:QQQQQQQQQQQQQQQQQQQQQQ")
	_check(not store.queue_clear(SERVER, ME, "room:QQQQQQQQQQQQQQQQQQQQQQ"), "A room this player's own turn finished needs no clear claim")
	store.queue_clear(SERVER, ME, "level:high-and-low")
	var again: RefCounted = PollenWallet.new(path)
	_check(again.clear_claims(SERVER, ME).size() == 1 and again.cleared(SERVER, ME, "level:first-steps") and not again.queue_clear(SERVER, ME, "level:first-steps"), "Waiting and settled clears survive a restart")

func _scopes_and_file() -> void:
	var path := _path("reload")
	var store: RefCounted = PollenWallet.new(path)
	_check(not store.enabled(SERVER, ME), "Pollen is off until the server says")
	store.set_enabled(SERVER, ME, true)
	store.note_wallet(SERVER, ME, {"schema_version": 1.0, "balance": 40.0, "earned": 40.0, "bank": 11.0})
	store.note_receipt(SERVER, ME, ROOM, _hash(3), _receipt(40.0, 40.0))
	store.queue_claim(SERVER, ME, ROOM, _hash(4))
	_check(not store.enabled(SERVER, OTHER) and store.wallet(SERVER, OTHER).is_empty() and store.wallet("https://other.example.test", ME).is_empty(), "Each server and player has its own")
	var again: RefCounted = PollenWallet.new(path)
	_check(again.enabled(SERVER, ME) and again.wallet(SERVER, ME).balance == 40, "The file survives a restart")
	_check(again.result_for(SERVER, ME, ROOM, _hash(3)) == store.result_for(SERVER, ME, ROOM, _hash(3)) and again.claims(SERVER, ME).size() == 1, "with its results and claims")
	var text := FileAccess.get_file_as_string(path)
	var parsed: Dictionary = JSON.parse_string(text)
	var key := PollenWallet.scope_key(SERVER, ME)
	parsed.scopes[key].results[0].receipt.turn.bloom = 9
	parsed.scopes[key].claims.append({"room_id": "bad", "recording_hash": _hash(5), "at": 1})
	parsed.scopes[key].wallet.balance = 2.5
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(parsed))
	file.close()
	var checked: RefCounted = PollenWallet.new(path)
	_check(checked.result_for(SERVER, ME, ROOM, _hash(3)).is_empty() and checked.claims(SERVER, ME).size() == 1 and checked.wallet(SERVER, ME).is_empty(), "Bad entries in the file are dropped one by one")
	store.set_enabled(SERVER, ME, false)
	_check(not PollenWallet.new(path).enabled(SERVER, ME), "Off is kept too")

func _damaged_file() -> void:
	var path := _path("damaged")
	var store: RefCounted = PollenWallet.new(path)
	store.set_enabled(SERVER, ME, true)
	store.note_wallet(SERVER, ME, {"schema_version": 1.0, "balance": 7.0, "earned": 7.0, "bank": 12.0})
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{\"schema_version\": 1, \"scopes\": {")
	file.close()
	var damaged: RefCounted = PollenWallet.new(path)
	_check(damaged.wallet(SERVER, ME).is_empty() and not damaged.enabled(SERVER, ME), "A damaged file reads as empty, so the wallet is asked for again")
	_check(damaged.note_wallet(SERVER, ME, {"schema_version": 1.0, "balance": 7.0, "earned": 7.0, "bank": 12.0}) and PollenWallet.new(path).wallet(SERVER, ME).balance == 7, "and the next answer writes a whole file")

func _rooms_api() -> void:
	_check(PollenWallet.HEADER in RoomsApi.capability_headers(HTTPClient.METHOD_GET, "/v2/capabilities"), "The capability asks for Pollen")
	_check(PollenWallet.HEADER in RoomsApi.capability_headers(HTTPClient.METHOD_POST, "/v2/rooms/" + ROOM + "/turns"), "So does a turn")
	for case: Array in [[HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM], [HTTPClient.METHOD_POST, "/v2/rooms/" + ROOM + "/fork"], [HTTPClient.METHOD_GET, "/v1/room-inbox"], [HTTPClient.METHOD_POST, "/v2/rooms"]]:
		_check(not PollenWallet.HEADER in RoomsApi.capability_headers(case[0], case[1]), "%s does not" % case[1])
	var api := RoomsApi.new()
	var body := JSON.stringify({"receipt": {"turn_id": "t0-0-a"}, "room": {"room_id": ROOM}, "pollen": {"schema_version": 1, "pending": true}}).to_utf8_buffer()
	var result: Dictionary = api._result([HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), body], HTTPClient.METHOD_POST, "/v2/rooms/" + ROOM + "/turns")
	_check(result.get("pollen") == {"schema_version": 1.0, "pending": true} and not result.data.has("pollen") and result.data.keys() == ["receipt", "room"], "The credit leaves the turn reply, so the receipt kept is unchanged")
	api.free()

func _result_line() -> void:
	var receipt := PollenWallet.checked_receipt(_receipt(98.0, 98.0))
	_check(ResultLine.lines(receipt, "Maya") == PackedStringArray(["+98 Pollen", "First try: +25%", "Maya has Full Journey: +10%"]), "Earned, the skill bonus and whose Full Journey boosted it")
	var both := PollenWallet.checked_receipt(_receipt(286.0, 286.0, {"bonuses": ["first_try", "gold_pace"], "bonus_percent": 40.0, "bloom": 2.0, "bloom_extra": 125.0, "boost_percent": 20.0, "boost_from": ["you", "partner"]}))
	_check(ResultLine.lines(both, "Maya") == PackedStringArray(["+286 Pollen", "First try and gold pace: +40%", "*A lucky bloom: ×2", "You and Maya have Full Journey: +20%"]), "A bloom gets its flower; two members' boost names both")
	_check(ResultLine.lines(both, "Maya", false) == PackedStringArray(["+286 Pollen", "First try and gold pace: +40%", "*A lucky bloom: ×2"]), "A build that names no Full Journey leaves out the boost line, not the amount")
	var mine := PollenWallet.checked_receipt(_receipt(98.0, 98.0, {"boost_from": ["you"], "bonuses": []}))
	_check(ResultLine.lines(mine, "Maya") == PackedStringArray(["+98 Pollen", "You have Full Journey: +10%"]), "Your own Full Journey says so")
	_check(ResultLine.lines(PollenWallet.checked_receipt(_receipt(98.0, 98.0, {"bonuses": []})), "a friend")[1] == "Your friend has Full Journey: +10%", "A friend with no name reads plainly")
	var repeat := PollenWallet.checked_receipt(_receipt(10.0, 10.0, {"kind": "after_bank", "bonuses": [], "bonus_percent": 0.0, "amount": 10.0, "boost_percent": 0.0, "boost": 0.0, "boost_from": [], "reason": "repeat"}))
	_check(ResultLine.lines(repeat, "") == PackedStringArray(["+10 Pollen", PlayerCopy.POLLEN_REPEAT]), "A repeat says why it pays a little")
	repeat.turn.reason = "late"
	_check(ResultLine.lines(repeat, "") == PackedStringArray(["+10 Pollen", PlayerCopy.POLLEN_LATE]), "So does a turn from an earlier week")
	var hard := PollenWallet.checked_receipt(_receipt(311.0, 311.0, {"bonuses": ["hard"], "bonus_percent": 50.0, "boost_percent": 0.0, "boost": 0.0, "boost_from": []}))
	_check(ResultLine.lines(hard, "") == PackedStringArray(["+311 Pollen", "Hard: +50%"]), "Hard has its own words")
	for line: String in [PlayerCopy.POLLEN_REPEAT, PlayerCopy.POLLEN_BANK_EMPTY, PlayerCopy.POLLEN_LATE, PlayerCopy.POLLEN_BLOOM, PlayerCopy.POLLEN_BOOST_BOTH, PlayerCopy.POLLEN_FIRST_CLEAR]:
		_check(not line.contains("-") and not line.contains("—") and not line.contains("–"), "No dashes: " + line)
	_check(ResultLine.lines({}, "Maya").is_empty(), "No receipt, no line")
	# The line itself: only while the server has Pollen on, on every build (a build that sells nothing earns too).
	var store := _store()
	store.note_receipt(SERVER, ME, ROOM, _hash(90), _receipt(196.0, 196.0, {"bloom": 2.0, "bloom_extra": 89.0}))
	var scope := {"server": SERVER, "owner": ME}
	PollenSurfaces.set_shared_for_tests(true)
	_check(ResultLine.build(scope, ROOM, _hash(90), "Maya", Color.WHITE, store) == null, "Nothing while Pollen is off")
	store.set_enabled(SERVER, ME, true)
	var line: Control = ResultLine.build(scope, ROOM, _hash(90), "Maya", Color.WHITE, store)
	_check(line != null and line.find_child("PollenBloomFlower", true, false) != null, "On, the line shows, with a flower for the bloom")
	if line != null: line.free()
	_check(ResultLine.build(scope, ROOM, _hash(91), "Maya", Color.WHITE, store) == null and ResultLine.build({}, ROOM, _hash(90), "Maya", Color.WHITE, store) == null, "Nothing for another turn or without a player")
	PollenSurfaces.set_shared_for_tests(false)
	line = ResultLine.build(scope, ROOM, _hash(90), "Maya", Color.WHITE, store)
	_check(line != null and line.find_child("PollenBloomFlower", true, false) != null, "A build that sells nothing shows the line too")
	var words: Array = [] if line == null else line.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)
	_check("+196 Pollen" in words and not words.any(func(text: String) -> bool: return text.contains("Full Journey")), "with what the turn earned and no Full Journey: " + str(words))
	if line != null: line.free()
	PollenSurfaces.set_shared_for_tests(null)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

extends SceneTree
## Looks kept per turn and per room member (services/turn_looks.gd), what each
## slot of a room's world wears (presentation/slot_looks.gd), and the looks a
## reply carries leaving the room it came with (services/rooms_api.gd):
## - only valid hashes, player ids and looks are kept; the newest stay past the
##   bound; a damaged file reads as empty;
## - live: the viewer wears their own look, the partner theirs, and a recording
##   that plays in the turn its own turn's look;
## - replay: each slot in its recording's own look, whatever anyone wears now;
## - a hard run record never carries a look (its fields are counted exactly).
const TurnLooks = preload("res://services/turn_looks.gd")
const SlotLooks = preload("res://presentation/slot_looks.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const HardMode = preload("res://services/hard_mode.gd")
const AtomicFile = preload("res://services/atomic_file.gd")

# Synthetic ids only.
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const FRIEND := "bbbbbbbbbbbbbbbbbbbbbb"
const SERVER := "https://looks.example.test"

var checks := 0
var failures := 0
var _paths: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _store() -> RefCounted:
	var path := "user://test-turn-looks-%s.json" % Crypto.new().generate_random_bytes(6).hex_encode()
	_paths.append(path)
	return TurnLooks.new(path)

static func _hash(n: int) -> String:
	return ("%x" % n).lpad(64, "0")

func _run() -> void:
	_store_rules()
	_slots()
	_reply_looks()
	_hard_runs()
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU TURN LOOKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _store_rules() -> void:
	var store := _store()
	_check(store.note_turns({_hash(1): {"hat": "daisy"}, _hash(2): {}, "nope": {"hat": "daisy"}, _hash(3): {"shoe": "x"}}) == 2, "Valid turns are kept, the rest dropped")
	_check(store.look(_hash(1)) == {"hat": "daisy"} and store.has(_hash(2)) and store.look(_hash(2)).is_empty() and not store.has(_hash(3)), "A default look is kept as known; a broken one is not kept")
	_check(store.note_turns({_hash(1): {"hat": "daisy"}}) == 0, "The same look again changes nothing")
	_check(store.note_member(FRIEND, {"body": "tide"}) and not store.note_member("short", {"body": "tide"}) and store.member(FRIEND) == {"body": "tide"}, "A member's look is kept by player id")
	var again: RefCounted = TurnLooks.new(store.path)
	_check(again.look(_hash(1)) == {"hat": "daisy"} and again.member(FRIEND) == {"body": "tide"}, "Looks survive a restart")
	var many := {}
	for n in range(TurnLooks.MAX_TURNS + 10): many[_hash(1000 + n)] = {"hat": "seashell"}
	_check(store.note_turns(many) == 0, "A reply with more turns than the bound is refused whole")
	for n in range(TurnLooks.MAX_TURNS + 10): store.note_turn(_hash(5000 + n), {"hat": "seashell"})
	_check(not store.has(_hash(1)) and store.has(_hash(5000 + TurnLooks.MAX_TURNS + 9)), "Past the bound the oldest go first")
	AtomicFile.remove(store.path)
	var file := FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string("{\"schema_version\": 1, \"turns\": {")
	file.close()
	var damaged: RefCounted = TurnLooks.new(store.path)
	_check(damaged.look(_hash(5000 + TurnLooks.MAX_TURNS + 9)).is_empty() and damaged.note_turn(_hash(7), {"hat": "daisy"}), "A damaged file reads as empty, and fills again")

func _slots() -> void:
	var store := _store()
	var wardrobe: RefCounted = Wardrobe.new("user://test-turn-looks-wardrobe-%s.json" % Crypto.new().generate_random_bytes(6).hex_encode())
	_paths.append(wardrobe.path)
	Wardrobe.use_shared(wardrobe)
	wardrobe.scope_source = func() -> Dictionary: return {"server": SERVER, "owner": ME}
	wardrobe.set_enabled(SERVER, ME, true)
	wardrobe.note_view(SERVER, ME, {"name_price": 0.0, "wardrobe": {"items": ["straw_hat"], "packs": [], "look": {"hat": "straw_hat"}, "look_revision": 1.0,
		"offered": ["daisy", "seashell", "straw_hat", "tide"], "offered_packs": [], "sets": {}, "unlocked": []}})
	store.note_member(FRIEND, {"body": "tide"})
	store.note_turn(_hash(10), {"hat": "daisy"})
	store.note_turn(_hash(11), {"hat": "seashell"})
	var room := {"player_slot": "p1", "host_id": FRIEND, "guest_id": ME}
	_check(SlotLooks.live(room, [], store) == {"p1": {"hat": "straw_hat"}, "p0": {"body": "tide"}}, "Live: the viewer wears their own look, the partner theirs")
	var ghost := {"player_slot": "p0", "recording_hash": _hash(10)}
	_check(SlotLooks.live(room, [ghost], store) == {"p1": {"hat": "straw_hat"}, "p0": {"hat": "daisy"}}, "The partner's first turn, played back, wears its own turn's look")
	var mine := {"player_slot": "p1", "recording_hash": _hash(11)}
	_check(SlotLooks.replay([ghost, mine], store) == {"p0": {"hat": "daisy"}, "p1": {"hat": "seashell"}}, "A replay dresses each slot in its recording's look, not today's")
	_check(SlotLooks.replay([{"player_slot": "p0", "recording_hash": _hash(99)}], store) == {"p0": {}}, "A turn this phone never heard a look for plays in the default")
	_check(SlotLooks.live({}, [], store).is_empty(), "Solo play, with no room, keeps the default look")
	Wardrobe.use_shared(null)
	preload("res://services/cosmetic_catalog.gd").set_offered([])

func _reply_looks() -> void:
	var shared := _store()
	TurnLooks.use_shared(shared)
	var api: Node = RoomsApi.new()
	var body := JSON.stringify({"room_id": "x", "partner_look": {"hat": "daisy"}, "turn_looks": {_hash(20): {"hat": "daisy"}}})
	var result: Dictionary = api._result([HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), body.to_utf8_buffer()], HTTPClient.METHOD_GET, "/v2/rooms/RRRRRRRRRRRRRRRRRRRRRR")
	_check(not result.data.has("partner_look") and not result.data.has("turn_looks") and result.data.room_id == "x", "Looks leave the room reply, so the room kept is exactly what it was")
	_check(result.partner_look == {"hat": "daisy"} and shared.look(_hash(20)) == {"hat": "daisy"}, "The partner's look goes to the coordinator and turns' looks are kept")
	var refused: Dictionary = api._result([HTTPRequest.RESULT_SUCCESS, 404, PackedStringArray(), JSON.stringify({"turn_looks": {_hash(21): {"hat": "daisy"}}}).to_utf8_buffer()], HTTPClient.METHOD_GET, "/v2/rooms/RRRRRRRRRRRRRRRRRRRRRR")
	_check(not refused.ok and not shared.has(_hash(21)), "A refused reply keeps no looks")
	for row: Array in [[HTTPClient.METHOD_GET, "/v2/rooms/RRRRRRRRRRRRRRRRRRRRRR", true], [HTTPClient.METHOD_POST, "/v2/rooms/RRRRRRRRRRRRRRRRRRRRRR/turns", true],
			[HTTPClient.METHOD_GET, "/v2/rooms/RRRRRRRRRRRRRRRRRRRRRR/replay-transfer", true], [HTTPClient.METHOD_GET, "/v1/room-inbox", false], [HTTPClient.METHOD_GET, "/v1/friends", false]]:
		_check(RoomsApi.capability_headers(row[0], row[1]).has(RoomsApi.LOOKS_HEADER) == row[2], "Looks are asked for on %s: %s" % [row[1], row[2]])
	api.free()
	TurnLooks.use_shared(null)

func _hard_runs() -> void:
	var run := HardMode.run_record("first-steps@2", "hard", "finished", "", "you", 0, "a", [], {}, "", "RRRRRRRRRRRRRRRRRRRRRR")
	run.id = "x"
	var valid := HardMode.valid_run(run)
	var dressed := run.duplicate(true)
	dressed["look"] = {"hat": "daisy"}
	_check(not HardMode.valid_run(dressed) or not valid, "A hard run with a look field is not a valid run, so looks live in services/turn_looks.gd")
	_check(not run.has("look"), "A hard run record carries no look")

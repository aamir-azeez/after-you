extends SceneTree
## Joining a friend's room needs its chapter open for the joiner
## (services/chapter_unlocks.gd). The phone cannot know a room's chapter before
## it joins, so every join carries the chapters open to the player and the room
## refuses one past them (backend chapter_not_open). The refusal is final: it
## never holds other rooms, and it tells the player which chapter to ask for.
const Session = preload("res://services/relay_online_session.gd")
const Unlocks = preload("res://services/chapter_unlocks.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Fixture = preload("res://tests/unlock_fixture.gd")
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const CODE := "A1A1A1A1A1A1A1A1A1A1"

var checks := 0
var failures := 0

class MemoryStore:
	extends RefCounted
	var values: Dictionary = {}
	func load_scope(scope: String) -> Dictionary:
		return {"ok":true,"found":values.has(scope),"value":values.get(scope,{}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		values[scope] = JSON.parse_string(JSON.stringify(value))
		return {"ok":true}

## A server whose relay room is for `room_level`: it refuses a join whose open
## chapters leave that out, as the backend's room join does.
class FakeApi:
	extends Node
	var player_id := GUEST
	var device_token := "synthetic-device-token"
	var base_url := "https://synthetic.invalid"
	var room_level := "relay-isles"
	var joins: Array[PackedStringArray] = []
	func configured() -> bool: return true
	func request_json(method: int, path: String, body: Dictionary = {}, still: Callable = Callable()) -> Dictionary:
		return await request_json_with_headers(method, path, body, PackedStringArray(), still)
	func request_json_with_headers(_method: int, path: String, _body: Dictionary, extra: PackedStringArray, _still: Callable = Callable()) -> Dictionary:
		await get_tree().process_frame
		if path == "/v2/capabilities":
			return {"ok":true,"status":200,"data":{"api_version":2,"recording_version":2,"simulation_version":2,"mutations_enabled":true,"validation":"structural_client_replay_required","chapters":[{"level_id":"relay-isles","level_version":2,"definition_hash":Canonical.digest(Catalog.relay_isles()),"premium":false}]}}
		if path == "/v2/rooms": return {"ok":true,"status":200,"data":{"rooms":[]}}
		if path == "/v2/rooms/join":
			joins.append(extra)
			var line := ""
			for header: String in extra:
				if header.begins_with(Unlocks.JOIN_HEADER + ": "): line = header.get_slice(": ", 1)
			if not extra.is_empty() and not room_level in line.split(","):
				return {"ok":false,"status":403,"code":"chapter_not_open","error":"Forbidden"}
			return {"ok":false,"status":409,"code":"room_full","error":"That room is full."}
		return {"ok":false,"status":404,"code":"not_found"}

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _run() -> void:
	var chain := Unlocks.chain()
	var newcomer := Unlocks.progress([], {}, {}, false)
	var veteran := Unlocks.progress(Fixture.cleared_through(chain[-1], "friend"), {}, {}, true)
	# A new player invited to a room for the second chapter.
	var api := FakeApi.new()
	root.add_child(api)
	var identity := func() -> Dictionary: return {"ready":true,"player_id":GUEST,"epoch":1}
	var session := Session.new(api, identity, MemoryStore.new())
	session.join_unlocks = func() -> Dictionary: return newcomer
	_check(await session.load_lobby(), "The guest's lobby loads")
	_check((await session.join_room("room-" + CODE)).is_empty(), "A new player is refused a room for a chapter they have not reached")
	_check(api.joins.size() == 1 and Array(api.joins[0]) == [Unlocks.join_header(newcomer)], "The join names the chapters open to the player: %s" % [api.joins])
	_check(session.last_error == PlayerCopy.CHAPTER_JOIN_NOT_REACHED % Unlocks.title(Registry.FIRST_STEPS), "The refusal says to ask the friend for First Steps: " + session.last_error)
	_check(session.pending_lobby().is_empty(), "The refusal is final and never holds other rooms")
	_check("-" not in PlayerCopy.CHAPTER_JOIN_NOT_REACHED and "—" not in PlayerCopy.CHAPTER_JOIN_NOT_REACHED, "The refusal has no dashes")
	# Played First Steps together: the second chapter's room now takes them.
	var after_first := Unlocks.progress(Fixture.cleared(chain[0], "friend"), {}, {}, false)
	session.join_unlocks = func() -> Dictionary: return after_first
	await session.join_room("room-" + CODE)
	_check(session.last_error != PlayerCopy.CHAPTER_JOIN_NOT_REACHED % Unlocks.title(chain[1]) and api.joins.size() == 2, "After First Steps with a friend the next chapter's room is not refused for the chapter")
	# A veteran is never refused for a chapter.
	api.room_level = chain[-1].get_slice("@", 0)
	session.join_unlocks = func() -> Dictionary: return veteran
	await session.join_room("room-" + CODE)
	_check(session.last_error == "That room is full.", "A veteran's join reaches the room's own answer: " + session.last_error)
	# While the keepsake ledger is unsettled the join carries nothing.
	session.join_unlocks = func() -> Dictionary: return Unlocks.unsettled()
	await session.join_room("room-" + CODE)
	_check(api.joins[-1].is_empty() and session.last_error == "That room is full.", "An unsettled ledger sends no header, as an older build")
	# Without Main's progress (an older wiring) the join carries nothing and is never refused here.
	session.join_unlocks = Callable()
	await session.join_room("room-" + CODE)
	_check(api.joins[-1].is_empty() and session.last_error == "That room is full.", "No progress, no header")
	api.queue_free()
	await process_frame
	print("CHAPTER UNLOCK JOIN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

extends "res://tests/test_archived_story_rooms.gd"
## The one checked read before a room this phone has not proven ordinary is
## selected: what it refuses, and that a stale or failed check never saves a
## proof or a selection.

func _run() -> void:
	await _unknown_failures()
	await _save_failures()
	await _await_changes()
	await _strict_indices()
	print("Room probe: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

## ORDINARY is open and proven; NEXT_ROOM has never been checked.
func _ordinary() -> Dictionary:
	var h := ArchiveHarness.new()
	root.add_child(h)
	h.rooms[ORDINARY] = _room("high-and-low",ORDINARY,false)
	h.rooms[NEXT_ROOM] = _room("rolling-home",NEXT_ROOM,false)
	var online := Online.new(h,h.identity,h.store)
	online.capabilities = {"mutations_enabled":true}
	_check(await online.open_room(ORDINARY) and online.standalone_room_proven(ORDINARY),"The ordinary room is open and proven")
	return {"h":h,"online":online}

func _unknown_failures() -> void:
	for failure: String in ["offline","other409","wrong_room","wrong_proof"]:
		var c := await _ordinary()
		var before: Dictionary = c.h.store.saved.duplicate(true)
		var prior: RefCounted = c.online.coordinator
		var room: Dictionary = c.h.rooms[NEXT_ROOM].duplicate(true)
		match failure:
			"offline": c.h.replies["/v2/rooms/"+NEXT_ROOM] = {"ok":false,"status":0,"code":"connection_interrupted"}
			"other409": c.h.replies["/v2/rooms/"+NEXT_ROOM] = {"ok":false,"status":409,"code":"campaign_required"}
			"wrong_room":
				room.room_id = GUEST
				c.h.replies["/v2/rooms/"+NEXT_ROOM] = {"ok":true,"status":200,"data":room}
			"wrong_proof":
				room.checkpoint.checkpoint_hash = "a".repeat(64)
				c.h.replies["/v2/rooms/"+NEXT_ROOM] = {"ok":true,"status":200,"data":room}
		_check(not await c.online.open_room(NEXT_ROOM),"An unchecked "+failure+" room is not opened")
		_check(c.online.coordinator == prior and c.online.last_room() == ORDINARY and Canonical.same(before,c.h.store.saved),failure+" keeps every saved scope and the previous room")
		_check(c.online.archived_room_kind(NEXT_ROOM).is_empty(),failure+" records nothing about the room")
		c.h.free()

func _save_failures() -> void:
	for target: String in ["cache","index"]:
		var c := await _ordinary()
		var prior: RefCounted = c.online.coordinator
		var old_index: Dictionary = c.h.store.saved["relay-lobby-v2:"+HOST].duplicate(true)
		var old_source: Dictionary = c.h.store.saved[_room_scope(ORDINARY)].duplicate(true)
		c.h.store.fail_scope = _room_scope(NEXT_ROOM) if target == "cache" else "relay-lobby-v2:"+HOST
		_check(not await c.online.open_room(NEXT_ROOM),"A failed "+target+" save stops the move")
		_check(c.online.coordinator == prior and c.online.last_room() == ORDINARY and Canonical.same(old_index,c.h.store.saved["relay-lobby-v2:"+HOST]) and Canonical.same(old_source,c.h.store.saved[_room_scope(ORDINARY)]),"The previous room, its journal and the index stay as they were")
		if target == "index":
			_check(c.h.store.saved.has(_room_scope(NEXT_ROOM)) and c.online.last_room() == ORDINARY,"An index failure leaves only the checked target's unselected cache")
		c.h.store.fail_scope = ""
		_check(await c.online.open_room(NEXT_ROOM) and c.online.last_room() == NEXT_ROOM,"Trying again finishes the same move")
		c.h.free()

func _await_changes() -> void:
	for change: String in ["epoch","selection","draft","device","backend"]:
		var c := await _ordinary()
		var old_index: Dictionary = c.h.store.saved["relay-lobby-v2:"+HOST].duplicate(true)
		var prior: RefCounted = c.online.coordinator
		c.h.on_request = func():
			match change:
				"epoch": c.h.identity_value.epoch += 1
				"selection": c.online._room_selection_generation += 1
				"draft": prior.save_draft(_json("res://tests/fixtures/cooperative/upper-path-a.json"))
				"device": c.h.device_token = "synthetic-rotated-device"
				"backend": c.h.base_url = "https://changed.synthetic.invalid"
		_check(not await c.online.open_room(NEXT_ROOM),"A "+change+" change during the check stops the move")
		_check(Canonical.same(old_index,c.h.store.saved["relay-lobby-v2:"+HOST]) and not c.h.store.saved.has(_room_scope(NEXT_ROOM)),"A stale check saves no proof, cache or selection after a "+change+" change")
		c.h.on_request = Callable()
		c.h.free()
	var c := await _ordinary()
	var index: Dictionary = c.h.store.saved["relay-lobby-v2:"+HOST].duplicate(true)
	c.h.store.on_save = func(scope: String):
		if scope == _room_scope(NEXT_ROOM): c.h.identity_value.epoch += 1
	_check(not await c.online.open_room(NEXT_ROOM) and Canonical.same(index,c.h.store.saved["relay-lobby-v2:"+HOST]),"An identity change during the cache save publishes nothing")
	c.h.store.on_save = Callable()
	c.h.free()
	c = await _ordinary()
	c.h.store.on_save = func(scope: String):
		if scope == "relay-lobby-v2:"+HOST:
			c.h.player_id = GUEST
			c.h.identity_value.player_id = GUEST
			c.h.identity_value.epoch += 1
	_check(not await c.online.open_room(NEXT_ROOM),"An identity change during the index save stops the move")
	_check(c.online._owner == GUEST and c.online._index.owner_player_id == GUEST and c.online.last_room().is_empty(),"The old owner's index never reaches the new owner's memory")
	c.h.store.on_save = Callable()
	c.h.free()

func _strict_indices() -> void:
	for bad: String in ["future","unknown","outside","duplicate","missing"]:
		var c := await _ordinary()
		var value: Dictionary = c.h.store.saved["relay-lobby-v2:"+HOST].duplicate(true)
		value.schema_version = 2
		value["standalone_ids"] = [ORDINARY]
		match bad:
			"future": value.schema_version = 3
			"unknown": value.extra = true
			"outside": value.standalone_ids = [NEXT_ROOM]
			"duplicate": value.standalone_ids = [ORDINARY,ORDINARY]
			"missing": value.erase("standalone_ids")
		c.h.store.saved["relay-lobby-v2:"+HOST] = JSON.parse_string(JSON.stringify(value))
		var online := Online.new(c.h,c.h.identity,c.h.store)
		var before: Dictionary = c.h.store.saved.duplicate(true)
		var count: int = c.h.calls.size()
		_check(not await online.open_room(ORDINARY) and c.h.calls.size() == count and Canonical.same(before,c.h.store.saved),"An unfamiliar "+bad+" index is held without a read or a rewrite")
		c.h.free()

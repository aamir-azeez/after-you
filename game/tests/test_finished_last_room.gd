extends "res://tests/test_archived_story_navigation.gd"
## Play with a friend after the last room ended on the server: its replay was
## saved by both phones (410 replay_transferred) or it was closed or left (404).
## 0.6.0 blocked every visit with "The chapter service could not be checked".

func _run() -> void:
	fixture = _json("res://tests/fixtures/campaign/control-v2.json")
	for case: String in ["transferred","transferred_no_copy","left","closed","offline","outage","live"]:
		await _case(case)
	print("Finished last room: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _case(case: String) -> void:
	var h := ArchiveHarness.new()
	h.store = RestoreStore.new()
	root.add_child(h)
	h.rooms[ORDINARY] = _room("high-and-low",ORDINARY,false)
	var online := Online.new(h,h.identity,h.store)
	# Opened before a Story owner existed: last_room without a standalone proof.
	_check(await online.open_room(ORDINARY),case+": the room was opened earlier")
	_check(not h.store.saved["relay-lobby-v2:"+HOST].has("standalone_ids"),case+": its last-room pointer carries no standalone proof")
	var room_scope := _room_scope(ORDINARY)
	var journal: Variant = h.store.saved.get(room_scope)
	if case == "transferred_no_copy": h.store.saved.erase(room_scope)
	match case:
		"transferred","transferred_no_copy": h.replies["/v2/rooms/"+ORDINARY] = {"ok":false,"status":410,"code":"replay_transferred"}
		"left": h.replies["/v2/rooms/"+ORDINARY] = {"ok":false,"status":404,"code":"room_not_found"}
		"closed": h.replies["/v2/rooms/"+ORDINARY] = {"ok":false,"status":410,"code":"room_closed"}
		"offline": h.replies["/v2/rooms/"+ORDINARY] = {"ok":false,"status":0,"code":"connection_interrupted"}
		"outage": h.replies["/v2/rooms/"+ORDINARY] = {"ok":false,"status":503,"code":"unavailable"}
	var cold := _archived({"h":h})
	var prepared: bool = await cold.online.prepare_archived_navigation()
	var index: Dictionary = h.store.saved["relay-lobby-v2:"+HOST]
	match case:
		"transferred":
			_check(prepared and cold.online.last_error.is_empty(),"A room whose replay both players saved lets navigation go on: "+cold.online.last_error)
			_check(index.last_room == ORDINARY and cold.online.coordinator != null,"Its saved copy stays the last room, ready for a replay or a redo")
		"transferred_no_copy":
			_check(prepared and cold.online.last_error.is_empty(),"A finished room with no copy on this phone does not block either: "+cold.online.last_error)
		"left","closed":
			_check(prepared and cold.online.last_error.is_empty(),case+": a room that is over no longer blocks Play with a friend: "+cold.online.last_error)
			_check(index.last_room == "" and cold.online.coordinator == null,case+": the stale last-room pointer is cleared")
			if journal != null: _check(Canonical.same(h.store.saved.get(room_scope),journal),case+": the room's own journal is kept untouched")
		"offline","outage":
			_check(not prepared and cold.online.last_error == preload("res://presentation/player_copy.gd").MAIN_571E92F64ED1,case+": a real failure still says the service could not be checked")
			_check(index.last_room == ORDINARY,case+": nothing is cleared when the server could not answer")
		"live":
			_check(prepared and index.last_room == ORDINARY,"A live room is unchanged")
	if prepared:
		cold.online.capabilities = {"mutations_enabled":true}
		_check(cold.online._can_lobby_mutate(),case+": hosting and joining are open again: "+cold.online.last_error)
	h.free()

extends "res://tests/test_campaign_owned_restore.gd"

const ORDINARY := "OOOOOOOOOOOOOOOOOOOOOO"
const NEXT_ROOM := "NNNNNNNNNNNNNNNNNNNNNN"

class GuardHarness:
	extends RestoreHarness
	var unmarked_holds: Dictionary = {}
	var offline := false
	var marked := 0
	func request_campaign_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		marked += 1
		var response: Dictionary = await super.request_campaign_json(method,path,body)
		marked -= 1
		return response
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		if offline or (marked == 0 and unmarked_holds.has(path)):
			calls.append({"method":method,"path":path,"body":body.duplicate(true)})
			return {"ok":false,"status":0 if offline else 409,"code":"connection_interrupted" if offline else "campaign_required"}
		return await super.request_json(method,path,body)

func _run() -> void:
	fixture = _json("res://tests/fixtures/campaign/control-v2.json")
	await _classification_and_offline()
	await _unknown_failures()
	await _known_children()
	await _ambiguous_children()
	await _save_failures()
	await _await_changes()
	await _pending_source()
	await _unvisited_and_cache()
	await _strict_indices()
	print("Campaign ordinary navigation: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _ordinary() -> Dictionary:
	var h := GuardHarness.new()
	h.store = RestoreStore.new()
	root.add_child(h)
	h.rooms[ORDINARY] = _room("high-and-low",ORDINARY,false)
	h.rooms[NEXT_ROOM] = _room("rolling-home",NEXT_ROOM,false)
	var online := Online.new(h,h.identity,h.store)
	_check(await online.open_room(ORDINARY),"A legacy ordinary cache and v1 index exist")
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	_check(owner.restore_owner(),"An empty campaign owner registers the guarded navigation boundary")
	return {"h":h,"online":online,"owner":owner}

func _classification_and_offline() -> void:
	var c := await _ordinary()
	var count: int = c.h.calls.size()
	_check(await c.online.open_room(ORDINARY),"A v1 ordinary cache is classified with an explicit native-verified read")
	_check(c.h.calls.size() == count+1 and c.h.campaign_calls.is_empty(),"Classification performs exactly one unmarked room GET")
	var index: Dictionary = c.h.store.saved["relay-lobby-v2:"+HOST]
	_check(index.schema_version == 2 and Canonical.same(index.standalone_ids,[ORDINARY]),"Only the verified room receives durable standalone classification")
	var cold := _cold(c)
	c.h.offline = true
	_check(not await cold.online.open_room(ORDINARY) and cold.online.last_room() == ORDINARY,"A later offline refresh may fail without losing the proven ordinary selection")
	_check(cold.online.coordinator != null and cold.online.coordinator.my_turn() and not cold.online.coordinator.campaign_recovery_only(),"JSON-round-tripped v2 classification preserves cold offline rehearsal")
	_check(cold.online.coordinator.save_draft(_json("res://tests/fixtures/cooperative/upper-path-a.json")),"Offline ordinary rehearsal still saves through native verification")
	c.h.free()

func _unknown_failures() -> void:
	for failure: String in ["offline","campaign","wrong_room","wrong_proof"]:
		var c := await _ordinary()
		var before: Dictionary = c.h.store.saved.duplicate(true)
		var prior: RefCounted = c.online.coordinator
		match failure:
			"offline": c.h.offline = true
			"campaign": c.h.unmarked_holds["/v2/rooms/"+NEXT_ROOM] = true
			"wrong_room": c.h.rooms[NEXT_ROOM].room_id = OTHER
			"wrong_proof": c.h.rooms[NEXT_ROOM].checkpoint.checkpoint_hash = "a".repeat(64)
		_check(not await c.online.open_room(NEXT_ROOM),"Unknown "+failure+" target cannot become ordinary")
		_check(c.online.coordinator == prior and c.online.last_room() == ORDINARY and Canonical.same(before,c.h.store.saved),"Refused classification preserves every durable scope and the prior Coordinator")
		c.h.free()

func _known_children() -> void:
	var c := await _make()
	_check(c.owner.classify_room(c.anchor).campaign,"A validated anchor is known before any ordinary admission")
	c.h.rooms[ORDINARY] = _room("high-and-low",ORDINARY,false)
	var bound_calls: int = c.h.calls.size()
	_check(not await c.online.open_room(ORDINARY) and c.h.calls.size() == bound_calls,"Direct ordinary entry cannot bypass explicit release of a story owner")
	_check(not c.online._can_lobby_mutate() and c.h.calls.size() == bound_calls,"Create, Join and saved ordinary lobby retries also require deliberate story departure")
	c.h.view = fixture.accepted_result.campaign.duplicate(true)
	_check(await c.owner.refresh(),"A later control journal publishes the second child")
	_check(c.owner.classify_room(c.target).campaign,"Journal writes invalidate the detached scan and reveal new children")
	_check(await c.owner.select_current() and c.owner.adopt_selected() and c.owner.release_for_ordinary(),"Completed adoption permits deliberate ordinary departure")
	var cold := _cold(c)
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var count: int = c.h.calls.size()
	for room: String in [c.anchor,c.target]:
		_check(not await cold.online.open_room(room),"Cold released campaign children cannot use the ordinary entry point")
	_check(c.h.calls.size() == count and Canonical.same(before,c.h.store.saved),"Known-child refusal precedes HTTP and all target-index writes")
	# An old standalone classification cannot override newly known ownership.
	var index: Dictionary = c.h.store.saved["relay-lobby-v2:"+HOST].duplicate(true)
	index.schema_version = 2
	if c.target not in index.room_ids: index.room_ids.append(c.target)
	index["standalone_ids"] = [c.target]
	c.h.store.saved["relay-lobby-v2:"+HOST] = index
	var again := _cold(c)
	_check(not await again.online.open_room(c.target) and c.h.calls.size() == count,"Known campaign history overrides a contradictory standalone classification")
	c.h.rooms[ORDINARY] = _room("high-and-low",ORDINARY,false)
	_check(await again.online.open_room(ORDINARY),"A released story's last-room pointer does not trap departure to a verified ordinary level")
	_check(again.online.last_room() == ORDINARY and not again.online.coordinator.campaign_scoped(),"Departure creates a fresh ordinary Coordinator and transport")
	c.h.free()

func _ambiguous_children() -> void:
	for reverse: bool in [false,true]:
		var c := await _make()
		c.h.view = fixture.accepted_result.campaign.duplicate(true)
		_check(await c.owner.refresh(),"A valid journal publishes the collision target")
		var lobby: Dictionary = c.h.store.saved["relay-campaign-lobby-v1:"+HOST].duplicate(true)
		var other: Dictionary = lobby.campaigns[0].duplicate(true)
		other.campaign_room_id = c.target
		lobby.campaigns.append(other)
		if reverse: lobby.campaigns.reverse()
		c.h.store.saved["relay-campaign-lobby-v1:"+HOST] = lobby
		var cold := _cold(c)
		var classified: Dictionary = cold.owner.classify_room(c.target)
		_check(classified.get("ok") == true and classified.campaign and classified.detail.get("kind") == "ambiguous","A child colliding with another anchor stays ambiguous in either reference order")
		var before: Dictionary = c.h.store.saved.duplicate(true)
		var count: int = c.h.calls.size()
		_check(not await cold.online.open_room(c.target) and c.h.calls.size() == count and Canonical.same(before,c.h.store.saved),"Ambiguous classification cannot write or dispatch an ordinary request")
		c.h.free()

func _save_failures() -> void:
	for target: String in ["cache","index"]:
		var c := await _ordinary()
		var prior: RefCounted = c.online.coordinator
		var old_index: Dictionary = c.h.store.saved["relay-lobby-v2:"+HOST].duplicate(true)
		var old_source: Dictionary = c.h.store.saved[_room_scope(ORDINARY)].duplicate(true)
		c.h.store.fail_scope = _room_scope(NEXT_ROOM) if target == "cache" else "relay-lobby-v2:"+HOST
		_check(not await c.online.open_room(NEXT_ROOM),"Failed "+target+" persistence blocks navigation")
		_check(c.online.coordinator == prior and c.online.last_room() == ORDINARY and Canonical.same(old_index,c.h.store.saved["relay-lobby-v2:"+HOST]) and Canonical.same(old_source,c.h.store.saved[_room_scope(ORDINARY)]),"Cache/index failure preserves prior pointer, native source and ownership")
		if target == "index":
			_check(c.h.store.saved.has(_room_scope(NEXT_ROOM)),"An index failure may leave only the already verified, unselected target cache")
		c.h.store.fail_scope = ""
		_check(await c.online.open_room(NEXT_ROOM),"Explicit retry can finish the same verified ordinary navigation")
		c.h.free()

func _await_changes() -> void:
	for change: String in ["epoch","selection","draft","owner","retire","device","backend"]:
		var c := await _ordinary()
		var old_index: Dictionary = c.h.store.saved["relay-lobby-v2:"+HOST].duplicate(true)
		var prior: RefCounted = c.online.coordinator
		var retained := {}
		c.h.on_request = func():
			match change:
				"epoch": c.h.identity_value.epoch += 1
				"selection": c.online._room_selection_generation += 1
				"draft": prior.save_draft(_json("res://tests/fixtures/cooperative/upper-path-a.json"))
				"owner": retained.owner = Owner.new(c.online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
				"retire": c.owner.invalidate_identity()
				"device": c.h.device_token = "synthetic-rotated-device"
				"backend": c.h.base_url = "https://changed.synthetic.invalid"
		_check(not await c.online.open_room(NEXT_ROOM),"Changed "+change+" context cannot adopt a delayed ordinary read")
		_check(Canonical.same(old_index,c.h.store.saved["relay-lobby-v2:"+HOST]) and not c.h.store.saved.has(_room_scope(NEXT_ROOM)),"A stale probe never saves target proof or selection")
		c.h.on_request = Callable()
		retained.clear()
		c.h.free()
	var c := await _ordinary()
	var index: Dictionary = c.h.store.saved["relay-lobby-v2:"+HOST].duplicate(true)
	c.h.store.on_save = func(scope: String):
		if scope == _room_scope(NEXT_ROOM): c.h.identity_value.epoch += 1
	_check(not await c.online.open_room(NEXT_ROOM) and Canonical.same(index,c.h.store.saved["relay-lobby-v2:"+HOST]),"Identity change during native cache save cannot publish classification")
	c.h.store.on_save = Callable()
	c.h.free()
	c = await _ordinary()
	c.h.store.on_save = func(scope: String):
		if scope == "relay-lobby-v2:"+HOST:
			c.h.player_id = OTHER
			c.h.identity_value.player_id = OTHER
			c.h.identity_value.epoch += 1
	_check(not await c.online.open_room(NEXT_ROOM),"Identity change during index save prevents adoption")
	_check(c.online._owner == OTHER and c.online._index.owner_player_id == OTHER and c.online.last_room().is_empty(),"The old owner's index cannot be installed into a newly restored owner's memory")
	c.h.store.on_save = Callable()
	c.h.free()

	# A weak owner must remain alive in the caller, never through an Online cycle.
	c = await _ordinary()
	var owner_ref: WeakRef = weakref(c.owner)
	c.erase("owner")
	await process_frame
	_check(owner_ref.get_ref() == null,"Online registration does not keep a retired owner alive")
	var calls: int = c.h.calls.size()
	_check(not await c.online.open_room(NEXT_ROOM) and c.h.calls.size() == calls,"A retired guard owner fails closed before an ordinary probe")
	c.h.free()

func _pending_source() -> void:
	var c := await _ordinary()
	_check(await c.online.open_room(ORDINARY),"Ordinary source has durable standalone proof")
	_check(not await c.online.coordinator.commit(_json("res://tests/fixtures/cooperative/upper-path-a.json")),"The source holds a genuine lost-response native turn")
	var saved: Dictionary = c.online.coordinator.pending()
	var cold := _cold(c)
	var count: int = c.h.calls.size()
	_check(not await cold.online.open_room(NEXT_ROOM) and c.h.calls.size() == count,"Cold pending source prevents target classification or navigation")
	_check(not cold.online.can_leave_for_legacy(),"The same pending lock applies to legacy departure")
	_check(await cold.online.open_room(ORDINARY) and Canonical.same(saved,cold.online.coordinator.pending()),"Exact original ordinary room reopens with its saved request intact")
	c.h.free()

func _unvisited_and_cache() -> void:
	var c := await _ordinary()
	_check(c.owner.bind_campaign(OTHER,Protocol.key(fixture.definition)),"A listed story may be retained before its journal exists")
	# Empty publication has no outstanding source mutation or selected child.
	_check(c.owner.release_for_ordinary(),"Unvisited settled binding may be released deliberately")
	var reads := {"count":0}
	c.h.store.on_load = func(scope: String):
		if scope.begins_with("relay-campaign-v1:"): reads.count += 1
	_check(c.owner.classify_room(OTHER).campaign,"Even an unvisited anchor is classified locally")
	var first: int = reads.count
	_check(not c.owner.classify_room(ORDINARY).campaign and reads.count == first,"Repeated classification reuses a validated bounded scan")
	_check(await c.online.open_room(ORDINARY),"Missing unvisited journals do not block a normal native-verified room")
	c.h.store.on_load = Callable()
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
		var owner := Owner.new(online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
		_check(owner.restore_owner(),"Campaign lobby remains independently readable")
		var before: Dictionary = c.h.store.saved.duplicate(true)
		var count: int = c.h.calls.size()
		_check(not await online.open_room(ORDINARY) and c.h.calls.size() == count and Canonical.same(before,c.h.store.saved),"Unfamiliar "+bad+" index is held without rewriting bytes or probing")
		c.h.free()

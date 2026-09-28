extends "res://tests/test_campaign_owned_restore.gd"
const ORDINARY := "OOOOOOOOOOOOOOOOOOOOOO"

class SelectionOwner extends RefCounted:
	var identity: Callable
	var anchor := ""
	var states: Dictionary = {}
	var retired := false
	var revision := 0
	func terminal_anchor_released(value: String) -> bool:
		var now: Dictionary = identity.call()
		return not retired and now.get("ready") == true and now.get("player_id") == "HHHHHHHHHHHHHHHHHHHHHH" and now.get("epoch") == 1 and value == anchor
	func terminal_room_status(value: String, room: String) -> String:
		if not terminal_anchor_released(value): return "held"
		return "unrelated" if room.is_empty() else str(states.get(room,"held"))
	func auxiliary_retirement() -> int: return revision
	func classification_context() -> Dictionary: return {"revision":revision}
	func refresh_terminal_classification() -> bool: return true

func _run() -> void:
	fixture = _json("res://tests/fixtures/campaign/control-v2.json")
	await _saved_pending()
	await _held_coordinator(false)
	await _held_coordinator(true)
	await _failure_retry()
	await _independent_pointers(false)
	await _independent_pointers(true)
	await _classification_holds()
	for race: String in ["identity","selection","owner","binding","classification"]: await _save_race(race)
	await _standalone_proof()
	await _cold_lifetime()
	print("Terminal room selection: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _selection(c: Dictionary) -> SelectionOwner:
	var owner := SelectionOwner.new()
	owner.identity = c.h.identity
	owner.anchor = c.anchor
	owner.states[c.anchor] = "released"
	owner.states[ORDINARY] = "unrelated"
	c.online.register_campaign_owner(owner)
	return owner

func _saved_pending() -> void:
	var c := await _make()
	_check(not await c.online.coordinator.commit(_json("res://tests/fixtures/cooperative/upper-path-a.json")),"A real native pending turn exists before terminal retirement")
	var owner := _selection(c)
	var old: RefCounted = c.online.coordinator
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var calls: int = c.h.calls.size()
	var generation: int = c.online._generation
	var selection: int = c.online.campaign_selection_generation()
	_check(c.online.retire_campaign_selection(c.anchor),"Exact terminal selection retires despite a saved pending turn")
	_check(c.online.last_room().is_empty() and c.online.coordinator == null and c.online._bound_room.is_empty(),"Only the terminal room's active pointers clear")
	_check(c.online._generation == generation and c.online.campaign_selection_generation() == selection+1,"Retirement advances selection without retiring global identity")
	_check(c.h.calls.size() == calls and old.snapshot().is_empty() and old.observe_room_binding().is_empty(),"The old coordinator retires synchronously without HTTP")
	for scope: String in before:
		if scope == "relay-lobby-v2:"+HOST: continue
		_check(Canonical.same(c.h.store.saved[scope],before[scope]),"Retirement preserves every unrelated and raw room/control journal: "+scope)
	var expected: Dictionary = before["relay-lobby-v2:"+HOST].duplicate(true)
	expected.last_room = ""
	_check(Canonical.same(expected,c.h.store.saved["relay-lobby-v2:"+HOST]),"Index schema, membership, ordinary proofs and pending admission remain unchanged")
	var writes: int = c.h.store.writes.size()
	_check(c.online.retire_campaign_selection(c.anchor) and c.h.store.writes.size() == writes and owner.terminal_anchor_released(c.anchor),"A no-match repeat is a local no-write success")
	c.h.free()

func _held_coordinator(busy: bool) -> void:
	var c := await _make()
	var owner := _selection(c)
	if busy: c.online.coordinator._busy = 1
	else: c.online.coordinator.read_only = true
	_check(not c.online.coordinator.observe_room_binding().is_empty() and c.online.coordinator.observe_campaign_state().is_empty(),"Identity observation stays available while gameplay state is held")
	_check(c.online.retire_campaign_selection(c.anchor) and c.online.coordinator == null and owner.terminal_anchor_released(c.anchor),"A held coordinator cannot trap a proven terminal selection")
	c.h.free()

func _failure_retry() -> void:
	var c := await _make()
	var owner := _selection(c)
	var old: RefCounted = c.online.coordinator
	var before: Dictionary = c.h.store.saved.duplicate(true)
	c.h.store.fail_scope = "relay-lobby-v2:"+HOST
	_check(not c.online.retire_campaign_selection(c.anchor),"Failed pointer persistence does not report local recovery complete")
	_check(c.online.coordinator == old and c.online.last_room() == c.anchor and Canonical.same(before,c.h.store.saved) and not c.online._retiring_selection,"Failed save retains all pointer and journal state and releases the temporary writer guard")
	c.h.store.fail_scope = ""
	_check(c.online.retire_campaign_selection(c.anchor) and owner.terminal_anchor_released(c.anchor),"The same permanent terminal proof permits a local retry")
	c.h.free()

func _independent_pointers(last_terminal: bool) -> void:
	var c := await _make()
	var owner := _selection(c)
	var previous: RefCounted = c.online.coordinator
	if last_terminal:
		var ordinary := Online.Coordinator.new(c.online.transport,c.h.store.load_scope,c.h.store.save_scope,c.h.identity)
		_check(ordinary.bind_room(ORDINARY),"Independent ordinary coordinator binds without replacing the old durable terminal pointer")
		c.online.coordinator = ordinary
		c.online._bound_room = ORDINARY
	else:
		c.online._index.last_room = ORDINARY
		c.h.store.saved["relay-lobby-v2:"+HOST] = c.online._index.duplicate(true)
	var current: RefCounted = c.online.coordinator
	_check(c.online.retire_campaign_selection(c.anchor),"Last-room and live coordinator retire independently")
	_check((c.online.last_room().is_empty() if last_terminal else c.online.last_room() == ORDINARY) and (c.online.coordinator == current if last_terminal else c.online.coordinator == null),"The unrelated pointer survives terminal cleanup")
	_check(owner.terminal_anchor_released(c.anchor) and (not current.observe_room_binding().is_empty() if last_terminal else previous.observe_room_binding().is_empty()),"Only the matching coordinator is invalidated")
	c.h.free()

func _classification_holds() -> void:
	var c := await _make()
	var owner := _selection(c)
	var before: Dictionary = c.h.store.saved.duplicate(true)
	owner.states[c.anchor] = "held"
	_check(not c.online.retire_campaign_selection(c.anchor) and Canonical.same(before,c.h.store.saved),"Unknown or ambiguous classification never clears a pointer")
	owner.states[c.anchor] = "released"
	c.online._opening = true
	_check(not c.online.retire_campaign_selection(c.anchor),"An outstanding ordinary selection cannot race local retirement")
	c.online._opening = false
	c.online._busy = true
	_check(not c.online.retire_campaign_selection(c.anchor),"An outstanding index-affecting transport settles before retirement")
	c.online._busy = false
	c.online._bound_room = ORDINARY
	_check(not c.online.retire_campaign_selection(c.anchor) and Canonical.same(before,c.h.store.saved),"A mismatched actual coordinator identity holds both pointers")
	c.h.free()

func _save_race(race: String) -> void:
	var c := await _make()
	var owner := _selection(c)
	var store := RestoreStore.new()
	store.saved = c.h.store.saved.duplicate(true)
	c.online._store = store
	var old: RefCounted = c.online.coordinator
	var changed_owner := SelectionOwner.new()
	changed_owner.identity = c.h.identity
	store.on_save = func(_scope: String):
		match race:
			"identity": c.h.identity_value.epoch = 2
			"selection": c.online._room_selection_generation += 1
			"owner": c.online.register_campaign_owner(changed_owner)
			"binding": old._room = ORDINARY
			"classification": owner.revision += 1
	_check(not c.online.retire_campaign_selection(c.anchor),"A synchronous Store callback cannot apply stale terminal retirement: "+race)
	_check(c.online.coordinator == old and not c.online._retiring_selection,"Stale local completion cannot drop a newer or changed coordinator: "+race)
	store.on_save = Callable()
	c.h.free()

func _standalone_proof() -> void:
	var c := await _make()
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var calls: int = c.h.calls.size()
	_check(not c.online.standalone_room_proven(ORDINARY),"Ordinary room membership alone is not a native admission proof")
	c.online._index.schema_version = 2
	c.online._index.room_ids.append(ORDINARY)
	c.online._index["standalone_ids"] = [ORDINARY]
	_check(c.online.standalone_room_proven(ORDINARY),"Exact previously admitted standalone proof is available without Owner recursion")
	c.h.identity_value.epoch = 2
	_check(not c.online.standalone_room_proven(ORDINARY) and c.h.calls.size() == calls and Canonical.same(before,c.h.store.saved),"Stale identity cannot use proof; the observation never loads, writes or sends")
	c.h.free()

func _cold_lifetime() -> void:
	var c := await _make()
	var online := Online.new(c.h,c.h.identity,c.h.store)
	var owner := SelectionOwner.new()
	owner.identity = c.h.identity
	owner.anchor = c.anchor
	online.register_campaign_owner(owner)
	var calls: int = c.h.calls.size()
	var writes: int = c.h.store.writes.size()
	var lifetime: Dictionary = online.terminal_lifetime(owner)
	_check(not lifetime.is_empty() and online.terminal_lifetime_current(lifetime,owner),"Cold terminal lifetime primes the local index without requiring any Owner restore method")
	_check(c.h.calls.size() == calls and c.h.store.writes.size() == writes and online.coordinator == null,"Cold lifetime capture performs no HTTP, save, child binding or Owner callback")
	var replacement := RestoreHarness.new()
	root.add_child(replacement)
	replacement.player_id = c.h.player_id
	replacement.device_token = c.h.device_token
	replacement.base_url = c.h.base_url
	online._api = replacement
	_check(not online.terminal_lifetime_current(lifetime,owner),"Replacing an API object with identical credentials retires its old captured lifetime")
	var fresh: Dictionary = online.terminal_lifetime(owner)
	_check(online.terminal_lifetime_current(fresh,owner) and fresh.api_instance != lifetime.api_instance,"An explicit fresh lifetime captures the replacement API instance")
	replacement.free()
	c.h.free()

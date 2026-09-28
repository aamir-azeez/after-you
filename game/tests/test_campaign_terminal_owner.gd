extends "res://tests/test_campaign_online_session.gd"
const Terminal = preload("res://services/campaign_terminal_session.gd")
const Lobby = preload("res://services/campaign_lobby_protocol.gd")
const LobbyTests = preload("res://tests/test_campaign_lobby_owner.gd")
const ORDINARY := "OOOOOOOOOOOOOOOOOOOOOO"

class CountingStore:
	extends Boundaries.MemoryStore
	var journal_reads := 0
	var on_load: Callable
	func load_scope(scope: String) -> Dictionary:
		if scope.begins_with("relay-campaign-v1:"): journal_reads += 1
		var result := super.load_scope(scope)
		if on_load.is_valid(): on_load.call(scope)
		return result

class TerminalHarness:
	extends LobbyTests.Harness
	var hint := ""
	var terminal_reply := true
	var terminal_status := 200
	var admission_mode := ""
	var admission_edit: Callable
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		var admission: bool = path.ends_with("/cancel") and not admission_mode.is_empty()
		if not admission and not path.ends_with("/reconcile-deletion") and not (path == "/v2/campaigns" and method == HTTPClient.METHOD_GET and not hint.is_empty()):
			return await super.request_json(method,path,body)
		busy = true
		calls.append({"method":method,"path":path,"body":body.duplicate(true)})
		if on_request.is_valid(): on_request.call()
		if hold: await release
		else: await get_tree().process_frame
		busy = false
		if admission:
			var original := path.trim_suffix("/cancel")
			var result := {"schema_version":1,"operation":"campaign_terminal_admission","admission":"create","status":"terminal","player_id":player_id,"idempotency_key":body.idempotency_key,"request_hash":Lobby.request_hash(player_id,original,body),"campaign_room_id":view.campaign_room_id}
			if admission_mode == "cancelled":
				result.operation = "campaign_admission_cancel"
				result.status = "cancelled"
				result.erase("campaign_room_id")
				result["campaign"] = null
			if admission_edit.is_valid(): admission_edit.call(result)
			return {"ok":true,"status":terminal_status,"data":result}
		if path == "/v2/campaigns":
			return {"ok":false,"status":409,"code":Terminal.HINT_CODE,"data":{"error":{"code":Terminal.HINT_CODE,"campaign_room_id":hint,"retryable":false}}}
		if not terminal_reply: return {"ok":false,"status":0,"code":"connection_interrupted"}
		return {"ok":true,"status":terminal_status,"data":{"schema_version":1,"operation":"campaign_terminal_cleanup","status":"released","player_id":player_id,"campaign_room_id":path.get_slice("/",3)}}

func _run() -> void:
	fixture = _json("res://tests/fixtures/campaign/control-v2.json")
	await _discovery_and_retirement()
	await _cold_terminal_first()
	await _lost_and_repeat()
	await _local_save_retries()
	await _classification()
	await _unrelated_auxiliary()
	await _unknown_anchor_auxiliary()
	await _admission_retirement()
	await _capabilities_and_unknown()
	await _identity_boundaries()
	await _api_replacement()
	await _retirement_during_await()
	await _max_history_reads()
	await _classification_save_drift()
	await _scan_owner_replacement()
	await _admission_save_failure()
	await _server_create_correlation()
	await _server_correlation_holds()
	await _malformed_index_independence()
	print("Campaign terminal Owner: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _make_terminal(selected: bool = true) -> Dictionary:
	var h := TerminalHarness.new()
	h.store = CountingStore.new()
	root.add_child(h)
	h.view = fixture.active_view.duplicate(true)
	h.capabilities = Boundaries.campaign_capabilities(fixture.definition)
	var anchor: String = h.view.campaign_room_id
	var target: String = fixture.accepted_result.campaign.chapters[1].room_id
	h.rooms[anchor] = _room("high-and-low",anchor,false)
	h.rooms[target] = _room("rolling-home",target,false)
	h.store.saved["photos:sentinel"] = {"raw":"retained private photo draft"}
	var online := Online.new(h,h.identity,h.store)
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	_check(owner.restore_owner() and h.calls.is_empty(),"Cold Owner prepares its local ordinary index and terminal ledger without network")
	online.capabilities = h.capabilities.duplicate(true)
	if selected:
		_check(owner.bind_campaign(anchor,Protocol.key(fixture.definition)),"Bound pointer is saved for a real campaign")
		_check(await owner.refresh() and await owner.select_current() and owner.adopt_selected(),"A verified campaign child is selected through its real scoped transport")
		_check(not online.standalone_room_proven(anchor),"Campaign setup does not fabricate ordinary classification")
	return {"h":h,"online":online,"owner":owner,"anchor":anchor,"target":target}

func _terminal_scope() -> String: return "relay-campaign-terminal-v1:"+HOST
func _index_scope() -> String: return "relay-lobby-v2:"+HOST

func _receipt(anchor: String) -> Dictionary:
	return {"schema_version":1,"operation":"campaign_terminal_cleanup","status":"released","player_id":HOST,"campaign_room_id":anchor}

func _seed_receipt(c: Dictionary, anchor: String) -> void:
	c.h.store.saved[_terminal_scope()] = {"schema_version":1,"owner_player_id":HOST,"pending":{},"released":[_receipt(anchor)]}

func _cold_owner(c: Dictionary) -> Dictionary:
	var online := Online.new(c.h,c.h.identity,c.h.store)
	var owner := Owner.new(online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
	_check(owner.restore_owner(),"Cold terminal-aware Owner remains available for local recovery")
	return {"online":online,"owner":owner}

func _hint(c: Dictionary, anchor: String = "") -> void:
	c.h.hint = c.anchor if anchor.is_empty() else anchor
	var before: Dictionary = c.h.store.saved.duplicate(true)
	_check(not await c.owner.load_campaign_lobby() and c.owner.last_code == Terminal.HINT_CODE,"Only an explicit authenticated list read discovers the typed terminal target")
	_check(Canonical.same(before,c.h.store.saved),"A terminal hint does not mutate any local pointer or journal")
	_check(c.owner.terminal_recovery().phase == "available","Typed discovery exposes an explicit recovery action")

func _assert_raw(c: Dictionary, before: Dictionary) -> void:
	for scope: String in before:
		if scope in [_lobby(),_index_scope(),_terminal_scope()]: continue
		_check(Canonical.same(c.h.store.saved.get(scope),before[scope]),"Terminal retirement preserves raw scope "+scope)

func _dispose_terminal(c: Dictionary) -> void:
	c.h.on_request = Callable()
	c.h.admission_edit = Callable()
	c.h.store.on_save = Callable()
	c.h.store.on_load = Callable()
	c.h.free()

func _discovery_and_retirement() -> void:
	var c := await _make_terminal()
	var record := _json("res://tests/fixtures/cooperative/upper-path-a.json")
	_check(not await c.online.coordinator.commit(record) and not c.online.coordinator.pending().is_empty(),"The selected chapter has a real lost-response turn")
	var old: RefCounted = c.online.coordinator
	var factory: RefCounted = c.online.auxiliary_context_factory()
	var target: RefCounted = factory.for_room(c.anchor,"replay")
	_check(target.current(),"The retained media target is initially current")
	await _hint(c)
	_check(not c.owner.terminal_anchor_released(c.anchor) and target.current(),"Hint alone does not claim permanent terminal authority")
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var calls: int = c.h.calls.size()
	c.h.leave_allowed = false
	_check(await c.owner.reconcile_terminal(),"Explicit terminal recovery can retire a lost turn without its ordinary leave guard")
	_check(c.h.calls.size() == calls+1 and c.h.calls[-1].path == Terminal.path_for(c.anchor),"Recovery sends exactly one marked monotone cleanup POST")
	_check(c.owner.terminal_anchor_released(c.anchor) and c.owner.terminal_recovery().is_empty(),"Durable terminal proof remains after all local retirement finishes")
	_check(c.owner.bound_campaign().is_empty() and c.online.last_room().is_empty() and c.online.coordinator == null,"Matching Owner and ordinary selection pointers clear")
	_check(old.snapshot().is_empty() and not target.current() and factory.current(),"Matching coordinator and auxiliary target retire without killing their entire factory")
	_assert_raw(c,before)
	_check(c.h.store.saved[_lobby()].campaigns.size() == 1,"Retained references survive for historical classification")
	_dispose_terminal(c)

func _cold_terminal_first() -> void:
	var c := await _make_terminal()
	c.h.rooms[c.anchor] = _room("high-and-low",c.anchor,true)
	_check(await c.online.coordinator.refresh(),"Real completed source is available for Continue")
	_check(not await c.owner.continue_current() and not c.owner.pending().is_empty(),"Lost Continue creates a durable control pending intent")
	_seed_receipt(c,c.anchor)
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var calls: int = c.h.calls.size()
	c.h.device_token = ""
	var cold := _cold_owner(c)
	_check(cold.owner._campaign == null and cold.owner._bridge == null and cold.online.coordinator == null,"Permanent receipt is restored before any old bound control/child bridge")
	_check(cold.owner.terminal_recovery().phase == "retiring" and not cold.owner.read_only,"Supported pending local retirement is recoverable rather than globally read-only")
	_check(c.h.calls.size() == calls and Canonical.same(before,c.h.store.saved),"Cold terminal restore remains offline and read-only")
	_check(await cold.owner.reconcile_terminal() and c.h.calls.size() == calls,"Receipt-backed cold retirement needs no capabilities or repeated POST")
	_check(not cold.owner.bind_campaign(c.anchor,Protocol.key(fixture.definition)),"Saved active journal cannot rebind a permanently terminal story")
	_assert_raw(c,before)
	_dispose_terminal(c)

func _lost_and_repeat() -> void:
	var c := await _make_terminal(false)
	await _hint(c)
	c.h.terminal_reply = false
	_check(not await c.owner.reconcile_terminal() and c.owner.terminal_recovery().phase == "pending","Lost POST keeps one exact durable cleanup request")
	var first: Dictionary = c.h.calls[-1].duplicate(true)
	var cold := _cold_owner(c)
	cold.online.capabilities = c.h.capabilities.duplicate(true)
	c.h.terminal_reply = true
	_check(await cold.owner.reconcile_terminal() and Canonical.same(first,c.h.calls[-1]),"Cold retry uses the identical original path and body")
	c.owner = cold.owner
	c.online = cold.online
	await _hint(c)
	c.h.terminal_reply = false
	_check(not await c.owner.reconcile_terminal() and c.owner.terminal_anchor_released(c.anchor),"A later explicit same-anchor hint stages a fresh cleanup without hiding old terminal proof")
	_check(c.owner.terminal_recovery().phase == "pending","Late prelink cleanup is not suppressed by an older released receipt")
	c.h.terminal_reply = true
	_check(await c.owner.reconcile_terminal(),"Repeated cleanup settles the newly pending request")
	_check(c.h.store.saved[_terminal_scope()].released.size() == 1,"Repeated requests retain one immutable terminal receipt")
	_dispose_terminal(c)

func _local_save_retries() -> void:
	for scope: String in [_index_scope(),_lobby()]:
		var c := await _make_terminal()
		await _hint(c)
		c.h.store.fail_scope = scope
		_check(not await c.owner.reconcile_terminal() and c.owner.terminal_anchor_released(c.anchor),"Failed local pointer save follows a durable released receipt")
		_check(c.owner.restore_owner() and not c.owner.read_only and c.owner.terminal_recovery().phase == "retiring","Local save failure exposes retryable retirement through a usable Owner")
		var before: Dictionary = c.h.store.saved.duplicate(true)
		var calls: int = c.h.calls.size()
		c.h.store.fail_scope = ""
		var cold := _cold_owner(c)
		_check(await cold.owner.reconcile_terminal() and c.h.calls.size() == calls,"Restart between local save boundaries retries only local retirement")
		_check(cold.online.last_room().is_empty() and cold.owner.bound_campaign().is_empty(),"Both durable pointer stages eventually settle")
		_assert_raw(c,before)
		_dispose_terminal(c)

func _classification() -> void:
	var c := await _make_terminal()
	c.h.view = fixture.accepted_result.campaign.duplicate(true)
	_check(await c.owner.refresh(),"Retained publication contains the next exact child mapping")
	_seed_receipt(c,c.anchor)
	var cold := _cold_owner(c)
	_check(cold.owner.terminal_room_status(c.anchor,c.anchor) == "released" and cold.owner.terminal_room_status(c.anchor,c.target) == "released","Root and unique retained child classify as the released campaign")
	_check(cold.owner.terminal_room_status(c.anchor,OTHER) == "held" and cold.owner.terminal_room_status(c.anchor,"") == "unrelated","Unknown is held and empty selection is unrelated")
	cold.online._index = {"schema_version":2,"owner_player_id":HOST,"room_ids":[ORDINARY],"standalone_ids":[ORDINARY],"last_room":"","pending":{}}
	_check(cold.owner.terminal_room_status(c.anchor,ORDINARY) == "unrelated","Only validated durable standalone proof classifies an ordinary room")
	cold.online._index.room_ids.append(c.target)
	cold.online._index.standalone_ids.append(c.target)
	_check(cold.owner.terminal_room_status(c.anchor,c.target) == "held","Campaign/standalone collision is held rather than erased")
	cold.online._index.standalone_ids = [ORDINARY]
	var journal: Dictionary = c.h.store.saved[_journal(c.anchor)].duplicate(true)
	c.h.store.saved[_journal(c.anchor)]["schema_version"] = 999
	cold.owner.refresh_terminal_classification()
	_check(cold.owner.terminal_room_status(c.anchor,c.target) == "held","Future retained journal cannot authorize child retirement")
	c.h.store.saved[_journal(c.anchor)] = journal
	var other_view: Dictionary = fixture.active_view.duplicate(true)
	other_view.invite_code = "CD".repeat(10)
	other_view.campaign_room_id = ("v2:"+other_view.invite_code).sha256_text().substr(0,22)
	other_view.chapters[0].room_id = other_view.campaign_room_id
	var reference := {"campaign_room_id":other_view.campaign_room_id,"campaign_key":Protocol.key(fixture.definition)}
	cold.owner._lobby.campaigns.append(reference)
	var other := journal.duplicate(true)
	other.campaign_room_id = reference.campaign_room_id
	other.view = other_view
	other.selected_room = ""
	c.h.store.saved[_journal(reference.campaign_room_id)] = other
	cold.owner.refresh_terminal_classification()
	_check(cold.owner.terminal_room_status(c.anchor,reference.campaign_room_id) == "unrelated","Another exact retained campaign root stays unrelated")
	other.view = fixture.accepted_result.campaign.duplicate(true)
	other.view.campaign_room_id = reference.campaign_room_id
	other.view.invite_code = "CD".repeat(10)
	other.view.chapters[0].room_id = reference.campaign_room_id
	cold.owner.refresh_terminal_classification()
	_check(cold.owner.terminal_room_status(c.anchor,c.target) == "held","Two independently valid retained campaign mappings cannot claim the same child")
	_dispose_terminal(c)

func _unrelated_auxiliary() -> void:
	var c := await _make_terminal()
	var reference := {"campaign_room_id":OTHER,"campaign_key":Protocol.key(fixture.definition)}
	c.owner._lobby.campaigns.append(reference)
	c.h.store.saved[_lobby()] = c.owner._lobby.duplicate(true)
	var factory: RefCounted = c.online.auxiliary_context_factory()
	var active: RefCounted = factory.for_room(c.anchor,"replay")
	var control: RefCounted = c.owner._campaign
	var generation: int = c.owner._generation
	await _hint(c,OTHER)
	_check(await c.owner.reconcile_terminal(),"Cleanup of another known terminal root settles independently")
	_check(active.current() and c.owner._campaign == control and c.owner._generation == generation,"Another anchor's cleanup preserves the unrelated bound bridge and auxiliary target")
	_check(c.owner.bound_campaign().campaign_room_id == c.anchor and c.online.last_room() == c.anchor,"Unrelated selected story and ordinary pointer remain intact")
	_dispose_terminal(c)

func _unknown_anchor_auxiliary() -> void:
	var c := await _make_terminal(false)
	var factory: RefCounted = c.online.auxiliary_context_factory()
	var target: RefCounted = factory.for_room(c.anchor,"replay")
	var other: RefCounted = factory.for_room(ORDINARY,"replay")
	_check(target.binding.kind == "ordinary" and target.current() and other.current(),"An unknown server root may have an earlier ordinary-classified auxiliary target")
	await _hint(c)
	_check(await c.owner.reconcile_terminal(),"Explicit unknown-link cleanup saves the permanent exact-root receipt")
	_check(not target.current() and other.current() and factory.current(),"Exact terminal root retires its old ordinary-classified target while unrelated ordinary targets remain live")
	_check(not factory.for_room(c.anchor,"photo").current(),"Fresh auxiliary lookup cannot downgrade a known terminal root to ordinary")
	var calls: int = c.h.calls.size()
	var response: Dictionary = await target.request({"owner_player_id":HOST,"identity_epoch":1,"method":HTTPClient.METHOD_GET,"path":"/v2/rooms/"+c.anchor,"body":{}})
	_check(response.get("ignored") == true and c.h.calls.size() == calls,"Retained terminal target cannot dispatch even though old ordinary room data remains")
	_dispose_terminal(c)

func _admission_retirement() -> void:
	for mode: String in ["accepted_create","join","unknown_create","other_join"]:
		var c := await _make_terminal(false)
		var joining := mode.ends_with("join")
		var body: Dictionary = Lobby.join_body(fixture.definition,"CD".repeat(10) if mode == "other_join" else "AB".repeat(10),"K".repeat(36)) if joining else Lobby.create_body(fixture.definition,"K".repeat(36))
		var path := "/v2/campaigns/join" if joining else "/v2/campaigns"
		var accepted := {"campaign_room_id":c.anchor,"campaign_key":Protocol.key(fixture.definition)} if mode == "accepted_create" else {}
		var pending := {"path":path,"body":body,"request_hash":Lobby.request_hash(HOST,path,body),"accepted_campaign":accepted,"cancel_requested":false}
		var lobby := {"schema_version":3,"owner_player_id":HOST,"campaigns":[accepted] if not accepted.is_empty() else [],"bound_campaign":{},"pending":pending}
		c.h.store.saved[_lobby()] = lobby.duplicate(true)
		_seed_receipt(c,c.anchor)
		var cold := _cold_owner(c)
		if mode in ["accepted_create","join"]:
			_check(cold.owner.terminal_recovery().phase == "retiring" and await cold.owner.reconcile_terminal(),"Exact "+mode+" correlates to permanent terminal proof")
			_check(cold.owner.pending_lobby().is_empty(),"Receipt-backed matching admission lock retires")
			var mapping: Dictionary = cold.owner._terminal_admission.mapping_for(cold.owner._admission_request(pending))
			_check(Canonical.same(mapping.request,cold.owner._admission_request(pending)) and mapping.witness.kind == ("accepted_reference" if mode == "accepted_create" else "join_invitation"),"The exact original admission and truthful local witness survive pending clear")
		else:
			_check(cold.owner.terminal_recovery().is_empty() and Canonical.same(cold.owner.pending_lobby(),pending),"Unknown Create or another Join remains intact without guessed correlation")
			_check(not cold.owner.can_leave(),"Unrelated or unknown admission still owns its navigation lock")
		_dispose_terminal(c)

func _capabilities_and_unknown() -> void:
	for mode: String in ["paused","global","unknown","malformed"]:
		var c := await _make_terminal(false)
		await _hint(c)
		if mode == "paused":
			c.online.capabilities.campaign_creation_enabled = false
			c.online.capabilities.campaign_mutations_enabled = false
		elif mode == "global": c.online.capabilities.mutations_enabled = false
		elif mode == "unknown": c.online.capabilities.erase("campaign_control_version")
		else: c.online.capabilities.campaign_definitions = [{}]
		var calls: int = c.h.calls.size()
		_check(await c.owner.reconcile_terminal() == (mode == "paused"),"Cleanup obeys control2/global capability independently of fresh admission and Continue: "+mode)
		_check(c.h.calls.size() == calls+(1 if mode == "paused" else 0),"Unavailable cleanup never fabricates a dispatch")
		_dispose_terminal(c)
	var c := await _make_terminal(false)
	c.h.hint = "malformed"
	_check(not await c.owner.load_campaign_lobby() and c.owner.terminal_recovery().is_empty(),"Malformed list hint is not terminal evidence")
	c.h.store.saved[_terminal_scope()] = {"schema_version":999}
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var cold := Owner.new(c.online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
	_check(not cold.restore_owner() and cold.read_only and Canonical.same(before,c.h.store.saved),"Future terminal ledger holds without overwriting or binding gameplay")
	_dispose_terminal(c)

func _identity_boundaries() -> void:
	for phase: String in ["request","receipt","lobby"]:
		var c := await _make_terminal()
		await _hint(c)
		if phase == "request": c.h.on_request = func(): c.h.identity_value.epoch += 1
		else:
			c.h.store.on_save = func(scope: String):
				if scope == (_terminal_scope() if phase == "receipt" else _lobby()):
					if phase == "receipt" and c.h.store.saved[scope].released.is_empty(): return
					c.h.identity_value.epoch += 1
		_check(not await c.owner.reconcile_terminal(),"Identity flip at "+phase+" boundary does not settle old in-memory authority")
		_check(not c.owner.terminal_anchor_released(c.anchor),"Stale owner cannot expose an old epoch's terminal proof")
		if phase == "request": _check(c.h.store.saved[_terminal_scope()].released.is_empty(),"Awaited stale receipt is not saved")
		_dispose_terminal(c)

func _api_replacement() -> void:
	var c := await _make_terminal()
	var replacement := TerminalHarness.new()
	root.add_child(replacement)
	replacement.store = c.h.store
	replacement.rooms = c.h.rooms.duplicate(true)
	replacement.view = c.h.view.duplicate(true)
	replacement.capabilities = c.h.capabilities.duplicate(true)
	var factory: RefCounted = c.online.auxiliary_context_factory()
	var target: RefCounted = factory.for_room(c.anchor,"replay")
	c.h.on_request = func(): c.online._api = replacement
	var response: Dictionary = await target.request({"owner_player_id":HOST,"identity_epoch":1,"method":HTTPClient.METHOD_GET,"path":"/v2/rooms/"+c.anchor,"body":{}})
	_check(response.get("ignored") == true and not target.current(),"Replacing the exact API object retires awaited target despite identical credentials and URL")
	_check(c.owner.restore_owner(),"A later explicit restore can bind a fresh exact API lifetime")
	var fresh: RefCounted = c.online.auxiliary_context_factory()
	_check(fresh.current() and fresh.for_room(c.anchor,"replay").current(),"Fresh factory observes the replacement API without resurrecting the old target")
	c.h.on_request = Callable()
	c.online._api = c.h
	await _hint(c)
	c.h.on_request = func(): c.online._api = replacement
	_check(not await c.owner.reconcile_terminal(),"Terminal POST also discards a reply from the replaced API instance")
	_check(c.h.store.saved[_terminal_scope()].released.is_empty(),"Discarded terminal reply does not create durable terminal authority")
	_dispose_terminal(c)
	replacement.free()

func _retirement_during_await() -> void:
	var c := await _make_terminal(false)
	await _hint(c)
	c.h.on_request = func():
		c.owner.invalidate_identity()
		c.owner.restore_owner()
	var completion := {"done":false,"okay":true}
	var run := func():
		completion.okay = await c.owner.reconcile_terminal()
		completion.done = true
	run.call()
	for tick in range(5): await process_frame
	_check(completion.done and not completion.okay,"Owner invalidation/replacement during the actual await drains the old Terminal service without retaining a test reference")
	_check(not c.owner.terminal_anchor_released(c.anchor) and c.h.store.saved[_terminal_scope()].released.is_empty(),"Superseded reply cannot install old terminal authority")
	_dispose_terminal(c)

func _max_history_reads() -> void:
	var c := await _make_terminal(false)
	var refs: Array = []
	var receipts: Array = []
	for index in range(128):
		var anchor := "T%021d" % index
		refs.append({"campaign_room_id":anchor,"campaign_key":Protocol.key(fixture.definition)})
		receipts.append(_receipt(anchor))
	c.h.store.saved[_lobby()] = {"schema_version":1,"owner_player_id":HOST,"campaigns":refs,"bound_campaign":refs[0],"pending":{}}
	c.h.store.saved[_terminal_scope()] = {"schema_version":1,"owner_player_id":HOST,"pending":{},"released":receipts}
	c.h.store.journal_reads = 0
	var started := Time.get_ticks_msec()
	var cold := _cold_owner(c)
	var elapsed := Time.get_ticks_msec()-started
	_check(c.h.store.journal_reads == 128,"Cold128-receipt/128-reference restoration reads each detached journal once")
	for reference: Dictionary in refs:
		_check(cold.owner.terminal_room_status(refs[0].campaign_room_id,reference.campaign_room_id) == ("released" if reference == refs[0] else "unrelated"),"Cached maximum-history status preserves exact anchor classification")
	_check(c.h.store.journal_reads == 128,"Pure status checks do not rescan retained journals")
	print("Terminal cold128 classification: %d ms, %d journal reads" % [elapsed,c.h.store.journal_reads])
	var before: int = c.h.store.journal_reads
	_check(await cold.owner.reconcile_terminal(),"Maximum-history local retirement remains explicit and bounded")
	_check(c.h.store.journal_reads-before <= 384,"Retirement uses bounded fresh passes, not a scan per receipt or pointer")
	_dispose_terminal(c)

func _classification_save_drift() -> void:
	var c := await _make_terminal()
	await _hint(c)
	c.h.store.on_save = func(scope: String):
		if scope == _index_scope(): c.h.store.saved[_journal(c.anchor)].seen = ["0:arrival"]
	_check(not await c.owner.reconcile_terminal(),"A synchronous control-journal change after pointer save invalidates the retirement lease")
	_check(c.online.coordinator != null and c.owner.terminal_recovery().phase == "retiring","Changed authority preserves the displayed coordinator for explicit local retry")
	c.h.store.on_save = Callable()
	_check(await c.owner.reconcile_terminal() and c.online.coordinator == null,"Fresh explicit retry validates the changed retained bytes before dropping the coordinator")
	_dispose_terminal(c)

func _scan_owner_replacement() -> void:
	var c := await _make_terminal()
	_seed_receipt(c,c.anchor)
	var before: Dictionary = c.h.store.saved.duplicate(true)
	c.h.store.on_load = func(scope: String):
		if scope == _journal(c.anchor):
			c.h.store.on_load = Callable()
			c.h.player_id = GUEST
			c.h.identity_value = {"ready":true,"player_id":GUEST,"epoch":2}
			c.owner.invalidate_identity()
			_check(c.owner.restore_owner(),"A new Owner restores during an older detached classification read")
	_check(not c.owner.restore_owner(true),"The superseded scan stops before discovery or bound restoration")
	_check(c.owner._owner == GUEST and c.owner._epoch == 2 and c.owner.restore_owner() and c.owner.bound_campaign().is_empty(),"Older scan completion preserves the newer restored Owner")
	_check(not c.owner.read_only and c.owner.terminal_recovery().is_empty() and Canonical.same(before,c.h.store.saved),"Identity drift neither invents retiring state nor writes older evidence into the new scope")
	_dispose_terminal(c)

func _admission_save_failure() -> void:
	var c := await _make_terminal(false)
	var body: Dictionary = Lobby.join_body(fixture.definition,"AB".repeat(10),"J".repeat(36))
	var pending := {"path":"/v2/campaigns/join","body":body,"request_hash":Lobby.request_hash(HOST,"/v2/campaigns/join",body),"accepted_campaign":{},"cancel_requested":false}
	c.h.store.saved[_lobby()] = {"schema_version":3,"owner_player_id":HOST,"campaigns":[],"bound_campaign":{},"pending":pending}
	_seed_receipt(c,c.anchor)
	var cold := _cold_owner(c)
	c.h.store.fail_scope = Owner.TerminalAdmission.scope_for(HOST)
	var before: Dictionary = c.h.store.saved.duplicate(true)
	_check(not await cold.owner.reconcile_terminal() and Canonical.same(cold.owner.pending_lobby(),pending),"Failed raw admission witness save keeps the original pending request")
	_check(Canonical.same(before,c.h.store.saved),"Witness failure precedes all pointer retirement writes")
	c.h.store.fail_scope = ""
	var restarted := _cold_owner(c)
	_check(await restarted.owner.reconcile_terminal() and restarted.owner.pending_lobby().is_empty(),"Cold local retry persists the witness before clearing the lock")
	_check(not restarted.owner._terminal_admission.mapping_for(restarted.owner._admission_request(pending)).is_empty(),"Exact original Join evidence remains readable after settlement")
	_dispose_terminal(c)

func _lost_create() -> Dictionary:
	var c := await _make_terminal(false)
	_check(await c.owner.load_campaign_lobby(),"The real lobby loads before the original Create")
	c.h.fail_post = true
	_check((await c.owner.create_campaign(Protocol.key(fixture.definition))).is_empty(),"Original Create reply is lost after one exact request is saved")
	c.h.fail_post = false
	c.h.admission_mode = "terminal"
	return c

func _server_create_correlation() -> void:
	var c := await _lost_create()
	var original: Dictionary = c.owner.pending_lobby()
	var count: int = c.h.calls.size()
	_check(not await c.owner.cancel_lobby_request() and c.owner.last_code == Terminal.HINT_CODE,"Explicit Cancel consumes a genuine request-bound terminal Create result without claiming successful cancellation")
	_check(c.h.calls.size() == count+1 and c.h.calls[-1].path == "/v2/campaigns/cancel" and Canonical.same(c.h.calls[-1].body,original.body),"Only the existing original Cancel is dispatched")
	_check(c.owner.pending_lobby().cancel_requested and c.owner.pending_lobby().accepted_campaign.is_empty() and c.owner.bound_campaign().is_empty(),"Terminal admission evidence neither clears nor fabricates acceptance/adoption")
	var request: Dictionary = c.owner._admission_request(original)
	var mapping: Dictionary = c.owner._terminal_admission.mapping_for(request)
	_check(mapping.witness.kind == "server_create" and mapping.witness.terminal.request_hash == original.request_hash,"The actual server result and exact original request are durable first")
	_check(c.owner.terminal_recovery().phase == "available" and c.owner.terminal_recovery().campaign_room_id == c.anchor and not c.owner.terminal_anchor_released(c.anchor),"Request correlation enables cleanup but does not fabricate its released receipt")
	var cold := _cold_owner(c)
	count = c.h.calls.size()
	_check(cold.owner.terminal_recovery().phase == "available" and not await cold.owner.cancel_lobby_request() and c.h.calls.size() == count,"Cold saved mapping exposes recovery without repeating Cancel")
	cold.online.capabilities = c.h.capabilities.duplicate(true)
	_check(await cold.owner.reconcile_terminal() and cold.owner.pending_lobby().is_empty(),"Separate explicit cleanup receipt permits retirement of the correlated lost Create")
	_check(c.h.calls.size() == count+1 and c.h.calls[-1].path == Terminal.path_for(c.anchor),"Recovery performs only the monotone cleanup POST")
	_check(Canonical.same(cold.owner._terminal_admission.mapping_for(request),mapping),"Server witness wins over a proposed local witness and survives pending clear unchanged")
	_dispose_terminal(c)

func _server_correlation_holds() -> void:
	for mode: String in ["owner","key","hash","anchor","operation","status","http","save","ordinary_cancel"]:
		var c := await _lost_create()
		var original: Dictionary = c.owner.pending_lobby()
		if mode == "save": c.h.store.fail_scope = Owner.TerminalAdmission.scope_for(HOST)
		elif mode == "http": c.h.terminal_status = 202
		elif mode == "ordinary_cancel": c.h.admission_mode = "cancelled"
		else:
			c.h.admission_edit = func(value: Dictionary):
				match mode:
					"owner": value.player_id = OTHER
					"key": value.idempotency_key = "other-key-value-1"
					"hash": value.request_hash = "f".repeat(64)
					"anchor": value.campaign_room_id = "bad"
					"operation": value.operation = "campaign_terminal_cleanup"
					"status": value.status = "released"
		var okay: bool = await c.owner.cancel_lobby_request()
		_check(okay == (mode == "ordinary_cancel"),"Terminal admission "+mode+" preserves strict result and ordinary Cancel semantics")
		_check(c.owner.terminal_recovery().is_empty() and c.owner._terminal_admission.mappings().is_empty(),"Rejected or ordinary cancellation does not manufacture terminal correlation")
		if mode != "ordinary_cancel":
			_check(Canonical.same(c.owner.pending_lobby().body,original.body) and c.owner.pending_lobby().cancel_requested,"Invalid result or mapping save failure retains exact Cancel intent")
			if mode == "save":
				c.h.store.fail_scope = ""
				_check(not await c.owner.cancel_lobby_request() and c.owner.terminal_recovery().phase == "available","Mapping storage recovery repeats the same Cancel and durably installs real evidence")
		else: _check(c.owner.pending_lobby().is_empty(),"Ordinary exact cancelled result still clears only its admission lock")
		_dispose_terminal(c)

func _malformed_index_independence() -> void:
	for evidence: bool in [false,true]:
		for mode: String in ["future","malformed","unreadable"]:
			var c := await _make_terminal(false)
			var correct := {"schema_version":1,"owner_player_id":HOST,"room_ids":[],"last_room":"","pending":{}}
			var bad := correct.duplicate(true)
			if mode == "future": bad.schema_version = 999
			elif mode == "malformed": bad["extra"] = true
			else: c.h.store.fail_read = _index_scope()
			c.h.store.saved[_index_scope()] = bad
			if evidence: _seed_receipt(c,c.anchor)
			var before: Dictionary = c.h.store.saved.duplicate(true)
			var calls: int = c.h.calls.size()
			var cold := _cold_owner(c)
			_check(not cold.online.terminal_index_ready() and not cold.owner.read_only,"Invalid "+mode+" ordinary index does not invalidate independently readable local Campaign lobby")
			_check(cold.owner.terminal_anchor_released(c.anchor) == evidence,"Permanent terminal evidence remains readable independently of index readiness")
			if evidence: _check(cold.owner.terminal_recovery().phase == "retiring","Unreadable last_room never masquerades as fully settled retirement")
			else: cold.owner._terminal_hint = c.anchor # Already authenticated discovery may predate the local failure.
			cold.online.capabilities = c.h.capabilities.duplicate(true)
			_check(not await cold.owner.reconcile_terminal() and c.h.calls.size() == calls and Canonical.same(before,c.h.store.saved),"Cleanup staging, receipt/mapping/pointer writes and network all hold on an invalid index")
			c.h.store.fail_read = ""
			c.h.store.saved[_index_scope()] = correct
			_check(await cold.owner.reconcile_terminal() and cold.online.terminal_index_ready(),"Explicit recovery can re-read the now-supported index without rebinding identity or discarding evidence")
			_check(c.h.calls.size() == calls+(0 if evidence else 1),"Existing receipt retries locally; newly staged cleanup sends only its explicit POST")
			_dispose_terminal(c)

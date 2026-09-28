extends SceneTree
const Owner = preload("res://services/campaign_online_session.gd")
const Online = preload("res://services/relay_online_session.gd")
const Protocol = preload("res://services/campaign_protocol.gd")
const Lobby = preload("res://services/campaign_lobby_protocol.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const LobbyTests = preload("res://tests/test_campaign_lobby_owner.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
var fixture: Dictionary
var checks := 0
var failures := 0

class CancelHarness:
	extends LobbyTests.Harness
	var fail_cancel := false
	var cancel_status := "cancelled"
	var cancel_http := 200
	var edit_ack: Callable
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		if not path.ends_with("/cancel"): return await super.request_json(method,path,body)
		busy = true
		calls.append({"method":method,"path":path,"body":body.duplicate(true)})
		if on_request.is_valid(): on_request.call()
		await get_tree().process_frame
		busy = false
		if fail_cancel: return {"ok":false,"status":0,"code":"connection_interrupted"}
		var original := path.trim_suffix("/cancel")
		var ack := {"schema_version":1,"operation":"campaign_admission_cancel","admission":"join" if original.ends_with("/join") else "create",
			"status":cancel_status,"player_id":player_id,"idempotency_key":body.idempotency_key,"request_hash":Lobby.request_hash(player_id,original,body),
			"campaign":view.duplicate(true) if cancel_status == "accepted" else null}
		if edit_ack.is_valid(): edit_ack.call(ack)
		return {"ok":true,"status":cancel_http,"data":ack}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/campaign/control-v2.json"))
	await _cancel_both_roles()
	await _lost_cancel_restart()
	await _accepted_cancel()
	await _accepted_later_control()
	await _durability_boundaries()
	await _reply_holds()
	await _pause_and_identity()
	await _legacy_intents()
	await _preserve_old_bound()
	print("Campaign lobby cancellation: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _setup(guest: bool = false) -> Dictionary:
	var h := CancelHarness.new()
	root.add_child(h)
	var player := GUEST if guest else HOST
	h.player_id = player
	h.identity_value.player_id = player
	h.view = fixture.active_view.duplicate(true)
	if guest:
		h.view.player_slot = "p1"
		h.view.invite_code = null
		h.view.invite_expires_at = null
		h.post_status = 200
	h.capabilities = {"api_version":2,"simulation_version":2,"recording_version":2,"mutations_enabled":true,"validation":"structural_client_replay_required","chapters":[],
		"campaign_control_version":2,"campaign_creation_enabled":true,"campaign_mutations_enabled":true,"campaign_definitions":[fixture.definition.duplicate(true)]}
	var online := Online.new(h,h.identity,h.store)
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	_check(await owner.load_campaign_lobby(),"Campaign capability and list load before admission")
	h.fail_post = true
	var result: String = await owner.join_campaign(Protocol.key(fixture.definition),"AB".repeat(10)) if guest else await owner.create_campaign(Protocol.key(fixture.definition))
	_check(result.is_empty() and not owner.pending_lobby().is_empty(),"Lost admission reply leaves one exact saved request")
	h.fail_post = false
	return {"h":h,"online":online,"owner":owner,"player":player,"scope":"relay-campaign-lobby-v1:"+player}

func _dispose(c: Dictionary) -> void:
	c.h.on_request = Callable()
	c.h.edit_ack = Callable()
	c.h.store.on_save = Callable()
	c.h.free()

func _cancel_both_roles() -> void:
	for guest: bool in [false,true]:
		var c := await _setup(guest)
		var before: Dictionary = c.owner.pending_lobby()
		_check(Protocol.matches(before.body.idempotency_key,"^[A-Za-z0-9_-]{36}$") and before.body.schema_version == (2 if guest else 1),"Each admission has one saved generated key under its exact wire schema")
		c.h.leave_allowed = false
		c.h.on_request = func():
			var saved: Dictionary = c.h.store.saved[c.scope]
			_check(saved.schema_version == 3 and saved.pending.cancel_requested and Canonical.same(saved.pending.body,before.body),"Cancel direction and original body are durable before network dispatch")
		_check(await c.owner.cancel_lobby_request(),"Explicit fenced cancellation succeeds while displayed input is busy")
		_check(c.owner.pending_lobby().is_empty() and c.owner.bound_campaign().is_empty() and c.online.last_room().is_empty(),"Only pending admission is cleared; no owner or room is adopted")
		_check(c.h.calls[-1].path == Lobby.cancel_path(before.path) and Canonical.same(c.h.calls[-1].body,before.body),"Cancel carries the exact original admission body")
		_dispose(c)

func _lost_cancel_restart() -> void:
	for guest: bool in [false,true]:
		var c := await _setup(guest)
		c.h.fail_cancel = true
		_check(not await c.owner.cancel_lobby_request() and c.owner.pending_lobby().cancel_requested,"Lost Cancel reply retains the cancellation direction")
		var before: Dictionary = c.owner.pending_lobby()
		var count: int = c.h.calls.size()
		var online := Online.new(c.h,c.h.identity,c.h.store)
		var cold := Owner.new(online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
		_check(cold.restore_owner() and Canonical.same(cold.pending_lobby(),before),"Cold restore retains the exact Cancel request")
		_check((await cold.retry_lobby_request()).is_empty() and c.h.calls.size() == count,"Unknown capabilities do not dispatch Cancel or admission")
		c.h.capabilities.campaign_creation_enabled = false
		c.h.capabilities.campaign_mutations_enabled = false
		_check(await cold.load_campaign_lobby(),"Read-only recovery remains available with fresh admission and continuation paused")
		c.h.fail_cancel = false
		c.h.leave_allowed = false
		count = c.h.calls.size()
		await cold.retry_lobby_request()
		_check(cold.pending_lobby().is_empty() and c.h.calls.size() == count+1 and c.h.calls[-1].path == Lobby.cancel_path(before.path),"Retry after restart fences the saved attempt without submitting admission again")
		_dispose(c)

func _accepted_cancel() -> void:
	for guest: bool in [false,true]:
		var c := await _setup(guest)
		c.h.cancel_status = "accepted"
		c.h.on_request = func(): c.h.leave_allowed = false
		_check(not await c.owner.cancel_lobby_request() and c.owner.last_code == "campaign_already_accepted","Acceptance racing Cancel is reported as accepted, never discarded")
		var pending: Dictionary = c.owner.pending_lobby()
		_check(pending.cancel_requested and not pending.accepted_campaign.is_empty() and c.owner.bound_campaign().is_empty(),"Accepted reference is durable while old displayed input keeps its owner")
		var count: int = c.h.calls.size()
		_check(not await c.owner.cancel_lobby_request() and c.h.calls.size() == count,"Durable acceptance cannot be cancelled again")
		_check((await c.owner.retry_lobby_request()).is_empty() and c.h.calls.size() == count,"Busy source prevents acceptance settlement from changing ownership")
		c.h.on_request = Callable()
		c.h.leave_allowed = true
		c.h.store.fail_scope = c.scope
		_check((await c.owner.retry_lobby_request()).is_empty() and c.h.calls.size() == count,"Failed bound-pointer save keeps acceptance without another POST")
		c.h.store.fail_scope = ""
		var online := Online.new(c.h,c.h.identity,c.h.store)
		var cold := Owner.new(online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
		_check(await cold.retry_lobby_request() == fixture.active_view.campaign_room_id,"Cold accepted settlement needs no capability fetch or repeated Cancel")
		_check(c.h.calls.size() == count+1 and c.h.calls[-1].method == HTTPClient.METHOD_GET and cold.pending_lobby().is_empty(),"Accepted Cancel settles with exactly one control GET")
		_dispose(c)

func _accepted_later_control() -> void:
	for state: String in ["continuing","deleting"]:
		var c := await _setup()
		if state == "continuing": c.h.view = fixture.pending_result.campaign.duplicate(true)
		else: c.h.view.state = "deleting"
		c.h.cancel_status = "accepted"
		_check(not await c.owner.cancel_lobby_request() and not c.owner.pending_lobby().accepted_campaign.is_empty(),"Accepted "+state+" admission is retained even when current control is not playable")
		_check(c.owner.bound_campaign().is_empty() and c.online.coordinator == null,"A later control response does not adopt a chapter during Cancel")
		var count: int = c.h.calls.size()
		_check(await c.owner.retry_lobby_request() == fixture.active_view.campaign_room_id and c.owner.pending_lobby().is_empty(),"Accepted "+state+" settles into its normal control recovery")
		_check(c.h.calls.size() == count+1 and c.h.calls[-1].method == HTTPClient.METHOD_GET and c.owner.view().state == state and c.owner.selected_room().is_empty() and c.online.coordinator == null,"Later control settlement is one GET with no implicit gameplay")
		_dispose(c)

func _durability_boundaries() -> void:
	for phase: String in ["direction","cancelled","accepted"]:
		var c := await _setup()
		if phase == "direction": c.h.store.fail_scope = c.scope
		else:
			c.h.cancel_status = phase
			c.h.store.on_save = func(scope: String):
				if scope == c.scope: c.h.store.fail_scope = c.scope
		var count: int = c.h.calls.size()
		_check(not await c.owner.cancel_lobby_request(),"Failed "+phase+" journal save does not report successful cancellation")
		_check(not c.owner.pending_lobby().is_empty() and c.h.calls.size() == count+(0 if phase == "direction" else 1),"Failed durable boundary retains request and dispatches only after saved direction")
		c.h.store.on_save = Callable()
		c.h.store.fail_scope = ""
		if phase != "direction":
			var saved: Dictionary = c.owner.pending_lobby()
			_check(saved.cancel_requested and saved.accepted_campaign.is_empty(),"Unacknowledged store failure retains sticky Cancel for exact retry")
			await c.owner.retry_lobby_request()
			_check(c.h.calls[-1].path.ends_with("/cancel"),"Store recovery repeats the fence request rather than admission")
		_dispose(c)

func _reply_holds() -> void:
	for mode: String in ["owner","key","hash","schema","operation","admission","status","extra","cancelled_campaign","accepted_projection","accepted_anchor","http"]:
		var c := await _setup(mode == "accepted_anchor")
		c.h.edit_ack = func(ack: Dictionary):
			match mode:
				"owner": ack.player_id = "Z".repeat(22)
				"key": ack.idempotency_key = "changed-attempt-key"
				"hash": ack.request_hash = "f".repeat(64)
				"schema": ack.schema_version = 2
				"operation": ack.operation = "delete_campaign"
				"admission": ack.admission = "join"
				"status": ack.status = "denied"
				"extra": ack["unknown"] = true
				"cancelled_campaign": ack.campaign = c.h.view.duplicate(true)
				"accepted_projection":
					ack.status = "accepted"
					ack.campaign = c.h.view.duplicate(true)
					ack.campaign.host_id = "Z".repeat(22)
				"accepted_anchor":
					ack.status = "accepted"
					ack.campaign = c.h.view.duplicate(true)
					ack.campaign.campaign_room_id = "Z".repeat(22)
		if mode == "http": c.h.cancel_http = 403
		_check(not await c.owner.cancel_lobby_request() and not c.owner.pending_lobby().is_empty() and c.owner.pending_lobby().cancel_requested,"Malformed "+mode+" reply cannot erase or reverse Cancel")
		var before: Dictionary = c.owner.pending_lobby()
		await c.owner.retry_lobby_request()
		_check(Canonical.same(c.owner.pending_lobby(),before) and c.h.calls[-1].path.ends_with("/cancel"),"Unknown "+mode+" retries only the same cancellation")
		_dispose(c)

func _pause_and_identity() -> void:
	var c := await _setup()
	c.h.capabilities.mutations_enabled = false
	_check(await c.owner.load_campaign_lobby(),"Paused global mutations still allow list reads")
	var count: int = c.h.calls.size()
	_check(not await c.owner.cancel_lobby_request() and c.owner.pending_lobby().cancel_requested and c.h.calls.size() == count,"Global pause saves cancellation intent without sending a write")
	c.h.capabilities.mutations_enabled = true
	_check(await c.owner.load_campaign_lobby(),"Capabilities can explicitly resume writes")
	c.h.on_request = func(): c.h.identity_value.epoch += 1
	_check(not await c.owner.cancel_lobby_request(),"A stale identity response cannot finalize cancellation")
	_check(c.h.store.saved[c.scope].pending.cancel_requested and not c.h.store.saved[c.scope].pending.is_empty(),"Identity replacement preserves the prior owner's exact intent")
	_dispose(c)

func _legacy_intents() -> void:
	for guest: bool in [false,true]:
		var c := await _setup(guest)
		var old: Dictionary = c.h.store.saved[c.scope].duplicate(true)
		old.schema_version = 2
		old.pending.erase("cancel_requested")
		if guest:
			old.pending.body.schema_version = 1
			old.pending.body.erase("idempotency_key")
			old.pending.request_hash = Lobby.request_hash(c.player,old.pending.path,old.pending.body)
		c.h.store.save_scope(c.scope,old)
		var count: int = c.h.calls.size()
		var writes: int = c.h.store.writes.size()
		var restored: bool = c.owner.restore_owner(true)
		if guest:
			_check(not restored and c.owner.read_only,"Legacy Join1 is held without inventing an attempt key")
			_check(not await c.owner.cancel_lobby_request() and (await c.owner.retry_lobby_request()).is_empty(),"Unsupported legacy Join cannot be retried or cancelled")
			_check(c.h.calls.size() == count and c.h.store.writes.size() == writes and Canonical.same(old,c.h.store.saved[c.scope]),"Legacy evidence remains byte-equivalent and undispatched")
		else:
			_check(restored and await c.owner.cancel_lobby_request(),"A legacy saved Create1 can explicitly migrate to cancellation schema3")
		_dispose(c)

func _preserve_old_bound() -> void:
	var c := await _setup()
	var pending: Dictionary = c.owner.pending_lobby()
	var saved: Dictionary = c.h.store.saved[c.scope].duplicate(true)
	var reference := {"campaign_room_id":fixture.active_view.campaign_room_id,"campaign_key":Protocol.key(fixture.definition)}
	saved.campaigns = [reference]
	saved.bound_campaign = reference
	c.h.store.save_scope(c.scope,saved)
	_check(c.owner.restore_owner(true) and await c.owner.refresh(),"A prior bound campaign can coexist with the unresolved later request")
	var session: RefCounted = c.owner._campaign
	var source_snapshot: Dictionary = c.h.store.saved.duplicate(true)
	c.h.leave_allowed = false
	_check(await c.owner.cancel_lobby_request(),"Cancellation does not need to leave the displayed old owner")
	_check(Canonical.same(c.owner.bound_campaign(),reference) and c.owner._campaign == session and c.owner.pending_lobby().is_empty(),"Fenced cancellation preserves the old bound session exactly")
	for scope: String in source_snapshot:
		if scope != c.scope: _check(Canonical.same(c.h.store.saved[scope],source_snapshot[scope]),"Every unrelated source/selection journal remains unchanged")
	_check(Canonical.same(c.h.calls[-1].body,pending.body),"The fence still belongs to the later request")
	_dispose(c)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

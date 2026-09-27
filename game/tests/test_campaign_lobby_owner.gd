extends SceneTree
const Owner = preload("res://services/campaign_online_session.gd")
const Online = preload("res://services/relay_online_session.gd")
const Protocol = preload("res://services/campaign_protocol.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Boundaries = preload("res://tests/test_campaign_room_bridge.gd")
const LobbyProtocol = preload("res://services/campaign_lobby_protocol.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
var fixture: Dictionary
var checks := 0
var failures := 0

class Harness:
	extends Boundaries.Harness
	var capabilities: Dictionary = {}
	var campaigns: Array = []
	var post_status := 201
	var fail_post := false
	var fail_control := false
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		if path not in ["/v2/capabilities","/v2/campaigns","/v2/campaigns/join"] and not (fail_control and path.begins_with("/v2/campaigns/")):
			return await super.request_json(method,path,body)
		busy = true
		calls.append({"method":method,"path":path,"body":body.duplicate(true)})
		if on_request.is_valid(): on_request.call()
		await get_tree().process_frame
		busy = false
		if path == "/v2/capabilities": return {"ok":true,"status":200,"data":capabilities.duplicate(true)}
		if path == "/v2/campaigns" and method == HTTPClient.METHOD_GET: return {"ok":true,"status":200,"data":{"campaigns":campaigns.duplicate(true)}}
		if fail_control and method == HTTPClient.METHOD_GET: return {"ok":false,"status":503,"code":"campaign_state_unavailable"}
		if fail_post: return {"ok":false,"status":0,"code":"connection_interrupted"}
		return {"ok":true,"status":post_status,"data":{"campaign":view.duplicate(true)}}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/campaign/control-v2.json"))
	await _create_and_guest_join()
	await _lost_reply()
	await _accepted_local_retry()
	await _storage_boundaries()
	await _reply_guards()
	await _capability_holds()
	await _list_preservation()
	await _identity_race()
	await _source_race()
	await _journal_roundtrip()
	await _continuation_pending_lobby()
	print("Campaign lobby owner: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _setup(guest: bool = false) -> Dictionary:
	var h := Harness.new()
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
	_check(await owner.load_campaign_lobby(),"Story availability and list load without ordinary room enumeration")
	_check(h.calls.size() == 2 and h.calls[0].path == "/v2/capabilities" and h.calls[1].path == "/v2/campaigns","The story lobby sends only its own two read requests")
	return {"h":h,"online":online,"owner":owner,"player":player,"scope":"relay-campaign-lobby-v1:"+player}

func _create_and_guest_join() -> void:
	for guest: bool in [false,true]:
		var c := await _setup(guest)
		c.h.on_request = func():
			if c.h.calls[-1].method == HTTPClient.METHOD_POST:
				var durable: Dictionary = c.h.store.saved[c.scope]
				_check(durable.schema_version == 3 and Canonical.same(durable.pending.body,c.h.calls[-1].body),"Exact lobby intent is durable before create/join dispatch")
		var anchor: String = await c.owner.join_campaign(Protocol.key(fixture.definition),"ab-ab-ab-ab-ab-ab-ab-ab-ab-ab") if guest else await c.owner.create_campaign(Protocol.key(fixture.definition))
		_check(anchor == fixture.active_view.campaign_room_id and c.owner.pending_lobby().is_empty(),"Valid acceptance settles one durable campaign owner")
		_check(c.owner.bound_campaign().campaign_room_id == anchor and c.owner.view().campaign_room_id == anchor,"Bound pointer and control journal are durable together before gameplay selection")
		_check(c.owner.selected_room().is_empty() and c.online.last_room().is_empty() and c.online.coordinator == null,"Create/join never selects, adopts, records or appends an ordinary room")
		_check(not c.owner.can_leave(),"Native current-child adoption remains a separate required boundary")
		_check(_posts(c.h.calls).size() == 1 and c.h.calls[-1].method == HTTPClient.METHOD_GET,"Acceptance completes with one control GET")
		c.h.free()

func _lost_reply() -> void:
	var c := await _setup()
	c.h.fail_post = true
	_check((await c.owner.create_campaign(Protocol.key(fixture.definition))).is_empty(),"Lost creation response remains pending")
	var pending: Dictionary = c.owner.pending_lobby()
	_check(not pending.is_empty() and pending.accepted_campaign.is_empty() and not c.owner.can_leave(),"Unknown acceptance preserves the original key and blocks ownership replacement")
	_check(not c.owner.release_for_ordinary() and not c.owner.bind_campaign("Z".repeat(22),Protocol.key(fixture.definition)),"Ordinary departure and another story cannot clear uncertainty")
	var online := Online.new(c.h,c.h.identity,c.h.store)
	var cold := Owner.new(online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
	_check(cold.restore_owner() and Canonical.same(cold.pending_lobby(),pending),"Restart restores the same create intent")
	c.h.capabilities.campaign_creation_enabled = false
	c.h.capabilities.campaign_mutations_enabled = false
	_check(await cold.load_campaign_lobby() and not cold.supports_campaign_creation(Protocol.key(fixture.definition)),"Paused new admission stays separate from the saved request")
	c.h.fail_post = false
	c.h.post_status = 200
	_check(await cold.retry_lobby_request() == fixture.active_view.campaign_room_id,"Accepted saved retry recovers while fresh creation and Continue are paused")
	var posts := _posts(c.h.calls)
	_check(posts.size() == 2 and Canonical.same(posts[0],posts[1]),"Retry repeats exactly the original endpoint, body and key")
	c.h.free()

func _accepted_local_retry() -> void:
	for state: String in ["active","continuing","deleting"]:
		var c := await _setup()
		if state == "continuing": c.h.view = fixture.pending_result.campaign.duplicate(true)
		elif state == "deleting": c.h.view.state = "deleting"
		c.h.fail_control = true
		_check((await c.owner.create_campaign(Protocol.key(fixture.definition))).is_empty(),"Interrupted control read retains local acceptance")
		var pending: Dictionary = c.owner.pending_lobby()
		_check(not pending.accepted_campaign.is_empty() and c.owner.bound_campaign() == pending.accepted_campaign,"Accepted reference is durable before the first control read")
		var online := Online.new(c.h,c.h.identity,c.h.store)
		var cold := Owner.new(online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
		_check(cold.restore_owner(),"Restart restores the accepted owner before ordinary selection")
		c.h.fail_control = false
		var count: int = c.h.calls.size()
		_check(await cold.retry_lobby_request() == fixture.active_view.campaign_room_id and cold.pending_lobby().is_empty(),"Durable "+state+" control owns recovery after lobby settlement")
		_check(_posts(c.h.calls.slice(count)).is_empty() and c.h.calls.size() == count+1,"Accepted local settlement needs only its control GET, with no capability or creation POST")
		_check(cold.view().get("state") == state and cold.selected_room().is_empty() and online.coordinator == null,"Later transition/deletion does not deadlock Create or cause automatic gameplay")
		c.h.free()

func _storage_boundaries() -> void:
	for boundary: String in ["intent","accepted","bound","journal","settled"]:
		var c := await _setup()
		var initial: Dictionary = c.h.store.saved.duplicate(true)
		var journal: String = "relay-campaign-v1:"+HOST+":"+fixture.active_view.campaign_room_id
		if boundary == "intent": c.h.store.fail_scope = c.scope
		elif boundary in ["accepted","journal"]:
			c.h.on_request = func():
				if c.h.calls[-1].method == HTTPClient.METHOD_POST: c.h.store.fail_scope = c.scope if boundary == "accepted" else journal
		elif boundary == "bound":
			c.h.store.on_save = func(scope: String):
				if scope == c.scope and not c.h.store.saved[scope].pending.accepted_campaign.is_empty(): c.h.store.fail_scope = c.scope
		else:
			c.h.store.on_save = func(scope: String):
				if scope == journal: c.h.store.fail_scope = c.scope
		_check((await c.owner.create_campaign(Protocol.key(fixture.definition))).is_empty(),"Failed "+boundary+" write cannot report completed lobby acceptance")
		var count: int = _posts(c.h.calls).size()
		_check(c.online.coordinator == null and c.online.last_room().is_empty(),"Local write failure never changes gameplay ownership")
		if boundary == "intent": _check(count == 0 and Canonical.same(initial,c.h.store.saved),"Failed intent write sends no request and preserves old bytes")
		else:
			_check(count == 1 and not c.owner.pending_lobby().is_empty(),"Every later failure retains the exact request")
			c.h.store.fail_scope = ""
			c.h.store.on_save = Callable()
			c.h.on_request = Callable()
			_check(await c.owner.retry_lobby_request() == fixture.active_view.campaign_room_id,"Storage recovery can settle without manual data edits")
			_check(_posts(c.h.calls).size() == (2 if boundary == "accepted" else 1),"Only unsaved acceptance repeats the original POST")
		c.h.free()

func _reply_guards() -> void:
	for mode: String in ["status","pin","anchor"]:
		var c := await _setup()
		if mode == "status": c.h.post_status = 202
		elif mode == "pin": c.h.view.campaign_key.definition_hash = "f".repeat(64)
		else:
			c.h.view.invite_code = "CD".repeat(10)
			c.h.view.campaign_room_id = ("v2:"+c.h.view.invite_code).sha256_text().substr(0,22)
			c.h.view.chapters[0].room_id = c.h.view.campaign_room_id
		var result: String = await c.owner.join_campaign(Protocol.key(fixture.definition),"AB".repeat(10)) if mode == "anchor" else await c.owner.create_campaign(Protocol.key(fixture.definition))
		_check(result.is_empty() and c.owner.bound_campaign().is_empty() and c.owner.pending_lobby().accepted_campaign.is_empty(),"Invalid "+mode+" cannot replace the bound owner")
		c.h.free()

func _capability_holds() -> void:
	for mode: String in ["missing","version","definition","global","creation"]:
		var c := await _setup()
		match mode:
			"missing": c.h.capabilities.erase("campaign_control_version")
			"version": c.h.capabilities.campaign_control_version = 3
			"definition": c.h.capabilities.campaign_definitions[0].story.content_hash = "f".repeat(64)
			"global": c.h.capabilities.mutations_enabled = false
			"creation": c.h.capabilities.campaign_creation_enabled = false
		await c.owner.load_campaign_lobby()
		var count: int = c.h.calls.size()
		_check((await c.owner.create_campaign(Protocol.key(fixture.definition))).is_empty() and c.h.calls.size() == count and c.owner.pending_lobby().is_empty(),"Unavailable "+mode+" capability does not create an intent or POST")
		c.h.free()

func _list_preservation() -> void:
	var c := await _setup()
	c.h.campaigns = [fixture.active_view.duplicate(true)]
	_check(await c.owner.load_campaign_lobby() and c.owner.campaign_references().size() == 1 and c.owner.bound_campaign().is_empty(),"Discovery remembers a reference without selecting its owner")
	c.h.campaigns = []
	_check(await c.owner.load_campaign_lobby() and c.owner.campaign_references().size() == 1,"Missing list entries do not erase local history")
	var before: Dictionary = c.h.store.saved.duplicate(true)
	c.h.campaigns = [fixture.active_view.duplicate(true),fixture.active_view.duplicate(true)]
	_check(not await c.owner.load_campaign_lobby() and Canonical.same(before,c.h.store.saved),"Malformed whole list preserves every local journal byte")
	c.h.free()

func _identity_race() -> void:
	var c := await _setup()
	c.h.on_request = func():
		if c.h.calls[-1].method == HTTPClient.METHOD_POST: c.h.identity_value.epoch += 1
	_check((await c.owner.create_campaign(Protocol.key(fixture.definition))).is_empty(),"A late create response cannot bind a replacement identity epoch")
	var saved: Dictionary = c.h.store.saved[c.scope]
	_check(saved.bound_campaign.is_empty() and saved.pending.accepted_campaign.is_empty() and not saved.pending.is_empty(),"Only the pre-dispatch request survives identity replacement")
	c.h.free()

func _source_race() -> void:
	for phase: String in ["post","control"]:
		var c := await _setup()
		c.h.on_request = func():
			var request: Dictionary = c.h.calls[-1]
			if (phase == "post" and request.method == HTTPClient.METHOD_POST) or (phase == "control" and request.path.ends_with(fixture.active_view.campaign_room_id)):
				c.h.leave_allowed = false
		_check((await c.owner.create_campaign(Protocol.key(fixture.definition))).is_empty(),"Source readiness changing during "+phase+" cannot silently finish the owner change")
		var pending: Dictionary = c.owner.pending_lobby()
		_check(not pending.accepted_campaign.is_empty(),"An accepted reply remains durable even when displayed input must wait")
		if phase == "post": _check(c.owner.bound_campaign().is_empty(),"Post-await source work preserves the prior bound owner")
		var count: int = c.h.calls.size()
		_check((await c.owner.retry_lobby_request()).is_empty() and c.h.calls.size() == count,"Ongoing source input/photo work prevents even a settlement GET")
		c.h.on_request = Callable()
		c.h.leave_allowed = true
		_check(await c.owner.retry_lobby_request() == fixture.active_view.campaign_room_id and _posts(c.h.calls).size() == 1,"An explicit later settlement uses the saved acceptance without another POST")
		c.h.free()

func _posts(calls: Array) -> Array:
	return calls.filter(func(value: Dictionary) -> bool: return value.method == HTTPClient.METHOD_POST)

func _journal_roundtrip() -> void:
	var c := await _setup()
	c.h.fail_control = true
	await c.owner.create_campaign(Protocol.key(fixture.definition))
	var journal: Dictionary = c.h.store.saved[c.scope].duplicate(true)
	_check(c.owner._valid_lobby(journal),"JSON round-tripped schema3 and its accepted intent remain valid")
	journal.campaigns[0].campaign_key.campaign_version = int(journal.campaigns[0].campaign_key.campaign_version)
	_check(c.owner._valid_lobby(journal),"Canonical numeric equality recognizes the same existing accepted anchor across JSON/native numbers")
	journal.schema_version = 4
	_check(not c.owner._valid_lobby(journal),"A future lobby schema remains held without inference")
	c.h.free()

func _continuation_pending_lobby() -> void:
	for path: String in ["/v2/campaigns","/v2/campaigns/join"]:
		var c := await _setup()
		var anchor: String = fixture.active_view.campaign_room_id
		_check(c.owner.bind_campaign(anchor,Protocol.key(fixture.definition)),"Previous bound owner is durable before a later lobby request")
		c.h.view = fixture.pending_result.campaign.duplicate(true)
		_check(await c.owner.refresh(),"Read-only refresh can discover the previous campaign's continuing state")
		var pending_body := LobbyProtocol.create_body(fixture.definition,"a".repeat(36)) if path == "/v2/campaigns" else LobbyProtocol.join_body(fixture.definition,"AB".repeat(10),"saved-join-key-0001")
		var saved: Dictionary = c.h.store.saved[c.scope].duplicate(true)
		saved.schema_version = 2
		saved.pending = {"path":path,"body":pending_body,"request_hash":LobbyProtocol.request_hash(HOST,path,pending_body),"accepted_campaign":{}}
		c.h.store.save_scope(c.scope,saved)
		_check(c.owner.restore_owner(true) and not c.owner.pending_lobby().is_empty(),"Restart retains the unresolved lobby intent and old bound control together")
		var calls: int = c.h.calls.size()
		var writes: int = c.h.store.writes.size()
		var before: Dictionary = c.h.store.saved.duplicate(true)
		_check(not await c.owner.resume_continuation() and c.owner.last_code == "campaign_lobby_pending","Continuing-source recovery respects the saved Create/Join hold")
		_check(c.h.calls.size() == calls and c.h.store.writes.size() == writes and Canonical.same(before,c.h.store.saved),"Blocked recovery performs no source probe, POST or journal write")
		c.h.free()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

extends SceneTree
## Native rules-8 replay, friends entry, and durable redo against one fake server.
const Session = preload("res://services/relay_online_session.gd")
const Friends = preload("res://services/friends_client.gd")
const Redo = preload("res://services/redo_client.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Recent = preload("res://tests/test_recent_rooms.gd")
const HOST := Recent.HOST
const GUEST := Recent.GUEST
const CODE := "A1A1A1A1A1A1A1A1A1A1"
const FRIEND_REQUEST := "FFFFFFFFFFFFFFFFFFFFFF"

class MemoryStore:
	extends RefCounted
	var values: Dictionary = {}
	func load_scope(scope: String) -> Dictionary:
		return {"ok":true,"found":values.has(scope),"value":values.get(scope,{}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		values[scope] = JSON.parse_string(JSON.stringify(value))
		return {"ok":true}

class Api:
	extends Node
	var player_id := ""
	var device_token := "synthetic-comfort-social"
	var base_url := "https://synthetic.invalid"
	var busy := false
	var responder: Callable
	var drop_fork_reply := false
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		busy = true
		var request: Dictionary = JSON.parse_string(JSON.stringify({"owner":player_id,"method":method,"path":path,"body":body}))
		var response: Dictionary = responder.call(request)
		busy = false
		if drop_fork_reply and method == HTTPClient.METHOD_POST and path.ends_with("/fork") and response.get("ok",false):
			drop_fork_reply = false
			return {"ok":false,"status":0,"code":"connection_interrupted"}
		# Real HTTPRequest and on-disk journals deserialize integer JSON as floats.
		return JSON.parse_string(JSON.stringify(response))

var checks := 0
var failures := 0
var fixture: Dictionary = {}
var level := Registry.definition(Registry.RELAY)
var room_id := ("v2:" + CODE).sha256_text().substr(0,22)
var state := {"exists":false,"joined":false,"revision":0,"branch":0,"stage_index":0,"has_a":false,"simulation_version":2}
var enabled := true
var calls: Array = []
var receipts: Dictionary = {}
var redo_request: Variant = null
var accepted_pairs: Array = []
var stores: Dictionary = {}
var apis: Array[Node] = []
var redo_persisted_before_post := true

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var bundle: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/comfort8/recordings.json"))
	if _check(bundle is Dictionary and bundle.get("relay") is Dictionary,"Load the actual comfort8 Relay fixture"):
		fixture = bundle.relay
		await _exercise()
	for api: Node in apis: api.queue_free()
	await process_frame
	print("AFTER YOU COMFORT SOCIAL INTEGRATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _exercise() -> void:
	if not _check(fixture.pairs.size() == 2 and fixture.checkpoints.size() == 3 and fixture.pairs[1].a.simulation_version == 8 and fixture.pairs[1].a.stage_id == "garden","Use the real rules8 Garden A and its completed Relay checkpoint"): return
	var host_identity := Recent.Identity.new()
	host_identity.player = HOST
	var guest_identity := Recent.Identity.new()
	guest_identity.player = GUEST
	var host_api := _api(HOST)
	var guest_api := _api(GUEST)
	var host_store := MemoryStore.new()
	var guest_store := MemoryStore.new()
	stores = {HOST:host_store,GUEST:guest_store}
	var host := Session.new(host_api,host_identity.current,host_store)
	var guest := Session.new(guest_api,guest_identity.current,guest_store)
	if not _check(await host.load_lobby() and await host.create_room(Registry.RELAY) == room_id,"Actual Session creates and natively opens a fresh negotiated room: " + host.last_error): return
	var creations := _calls("/v2/rooms",HTTPClient.METHOD_POST,HOST)
	if not _check(creations.size() == 1 and creations[0].body.get("simulation_version") == 8 and host.coordinator.snapshot().simulation_version == 8,"Fresh room creation explicitly sends pin8 against a server whose retained default is2"): return
	var live: RefCounted = host.coordinator.create_live_simulation()
	_check(live != null and live.simulation_version == 8,"Fresh native recording uses the accepted explicit8 room pin")
	if not _check(await guest.load_lobby() and guest.room_ids().is_empty(),"An unjoined friend has no room membership before normal admission"): return
	var friends := Friends.new(guest_api,guest_identity.current)
	if not _check(await friends.refresh(),"Accepted friend page loads through the real FriendsClient"): return
	var friend: Dictionary = friends.view().friends[0]
	_check(not friend.online and friend.join_available,"An offline accepted friend can share an asynchronous room")
	var invitation: Dictionary = await friends.join_friend(friend)
	if not _check(invitation.get("api_version") == 2 and invitation.get("room_id") == room_id and not state.joined,"Friend descriptor is verified without admitting a room member"): return
	if not _check(await guest.join_room(invitation.invite_code) == room_id,"Friend entry uses the existing durable Session join: " + guest.last_error): return
	var joins := _calls("/v2/rooms/join",HTTPClient.METHOD_POST,GUEST)
	_check(joins.size() == 1 and joins[0].body.invite_code == CODE and Canonical.same(joins[0].body.supported_simulation_versions,[2,4,5,6,7,8]),"Ordinary join advertises rules8 exactly once")
	guest = Session.new(guest_api,guest_identity.current,guest_store)
	_check(guest.room_ids().is_empty(),"Cold recency hints alone never claim authenticated room access")
	if not _check(await guest.load_lobby(),"Guest reconnect refreshes its authenticated room membership"): return
	var summaries: Array = guest.room_summaries()
	_check(summaries.size() == 1 and summaries[0].room_id == room_id and not summaries[0].hosted and summaries[0].last_opened,"Recent rooms retain the friend's joined room as a guest entry")
	var before := calls.size()
	if not _check(await guest.open_room(room_id),"Guest reopens its saved room without another invitation: " + guest.last_error): return
	_check(calls.size() == before + 1 and calls.back().method == HTTPClient.METHOD_GET and calls.back().path == _room_path() and calls.back().owner == GUEST and _calls("/v2/rooms/join",HTTPClient.METHOD_POST,GUEST).size() == 1,"Recent reopen is one authenticated exact-room GET, with no second join")

	if not _check(await host.open_room(room_id) and await host.coordinator.commit(fixture.pairs[0].a),"Host commits the actual rules8 Relay A recording: " + host.coordinator.last_error): return
	if not _check(await guest.open_room(room_id) and await guest.coordinator.commit(fixture.pairs[0].b),"Guest commits Relay B and the native derived checkpoint: " + guest.coordinator.last_error): return
	if not _check(await guest.coordinator.commit(fixture.pairs[1].a),"Guest becomes Garden's first player and commits the actual rules8 A: " + guest.coordinator.last_error): return
	if not _check(await host.open_room(room_id),"Host verifies Garden A and the nonempty completed prefix"): return
	var original: Dictionary = guest.coordinator.snapshot()
	var prefix: Array = guest.chapter_pairs()
	_check(original.simulation_version == 8 and original.stage_index == 1 and original.first_player_id == GUEST and original.active_player_id == HOST and original.completed_pair_ids == ["p0-0"],"Garden roles reverse: G is first and H can request a redo")
	_check(Canonical.same(original.checkpoint,fixture.checkpoints[1]) and Canonical.same(prefix,[fixture.pairs[0]]) and Canonical.same(accepted_pairs,[fixture.pairs[0]]),"The completed Relay pair and real middle checkpoint are retained before consent")
	var requester: RefCounted = host.redo_client()
	if not _check(requester.bind_room("relay",host.coordinator.snapshot()) and await requester.refresh() and requester.can_request() and not requester.can_accept(),"Second player H can request but cannot approve their own Garden redo"): return
	if not _check(await requester.request_redo(),"Actual RedoClient persists and submits H's advisory request"): return
	var source: Dictionary = Redo.source_for("relay",original)
	_check(source.stage_index == 1 and source.first_player_id == GUEST and source.second_player_id == HOST and source.a_hash == fixture.pairs[1].a.recording_hash,"Redo source binds the accepted rules8 Garden recording and reversed owners")
	var consent: RefCounted = guest.redo_client()
	if not _check(consent.bind_room("relay",original) and await consent.refresh() and consent.can_accept() and not consent.can_request(),"First player G alone receives the current consent action"): return
	guest_api.drop_fork_reply = true
	if not _check(not await consent.accept() and consent.pending().get("action") == "accept","Server accepts consent but a lost reply leaves the exact request durable"): return
	var held: Dictionary = consent.pending()
	var redo_scope := "relay-redo-relay-v1:" + GUEST + ":" + room_id
	_check(redo_persisted_before_post and guest_store.values.has(redo_scope) and Canonical.same(guest_store.values[redo_scope].pending,held),"Both advisory request and consent are durable before their respective POSTs")
	_check(state.branch == 1 and _calls(_room_path()+"/fork",HTTPClient.METHOD_POST,GUEST).size() == 1,"Lost response corresponds to exactly one accepted branch change")
	_check(guest.coordinator.snapshot().branch == original.branch and guest.coordinator.snapshot().recording_a != null,"Lost control response does not inject an unverified gameplay snapshot")
	before = calls.size()
	_check(not guest.can_leave_for_legacy() and calls.size() == before,"Warm Session holds navigation locally until consent is reconciled")

	enabled = false
	guest = Session.new(guest_api,guest_identity.current,guest_store)
	if not _check(await guest.load_lobby() and not guest.mutations_enabled(),"Cold Session reloads while new chapter mutations are paused"): return
	before = calls.size()
	_check(guest.pending_redo_room() == room_id and not guest.can_leave_for_legacy() and calls.size() == before,"Cold Session restores the same durable consent hold without a network mutation")
	if not _check(await guest.open_room(room_id),"Same-room authenticated recovery independently validates the accepted fork"): return
	consent = guest.redo_client()
	if not _check(consent.bind_room("relay",guest.coordinator.snapshot()) and Canonical.same(consent.pending(),held),"Binding the new A-ready source keeps the exact old-source pending request"): return
	before = calls.size()
	if not _check(await consent.retry(false) and consent.accepted and consent.pending().is_empty(),"Paused cold recovery accepts the stored operation receipt without re-posting consent"): return
	_check(calls.size() == before + 1 and calls.back().owner == GUEST and calls.back().method == HTTPClient.METHOD_GET and calls.back().path == _room_path()+"/operations/"+str(held.body.idempotency_key),"Recovery reads only the original caller's exact operation key")
	_check(_calls(_room_path()+"/fork",HTTPClient.METHOD_POST,GUEST).size() == 1 and guest_store.values[redo_scope].pending.is_empty() and guest.can_leave_for_legacy(),"Confirmed receipt clears the durable hold without creating a second branch")
	if not _check(await guest.open_room(room_id),"Normal coordinator refresh remains the gameplay authority after receipt reconciliation"): return
	var recovered: Dictionary = guest.coordinator.snapshot()
	_check(recovered.simulation_version == 8 and recovered.stage_index == 1 and recovered.branch == 1 and recovered.active_role == "a" and recovered.active_player_id == GUEST and recovered.recording_a == null,"Redo returns Garden to G's A turn on the same explicit8 pin")
	_check(Canonical.same(recovered.completed_pair_ids,original.completed_pair_ids) and Canonical.same(recovered.checkpoint,original.checkpoint) and Canonical.same(guest.chapter_pairs(),prefix) and Canonical.same(accepted_pairs,[fixture.pairs[0]]),"Redo and cold recovery preserve the nonempty completed pair, its proof, and the exact checkpoint")
	live = guest.coordinator.create_live_simulation()
	_check(live != null and live.simulation_version == 8 and live.role == "a" and live.stage.id == "garden","Native re-recording after recovered consent retains rules8 and Garden's first-player role")

func _api(owner: String) -> Api:
	var api := Api.new()
	api.player_id = owner
	api.responder = _server
	root.add_child(api)
	apis.append(api)
	return api

func _snapshot(owner: String) -> Dictionary:
	var index: int = state.stage_index
	var first: String = HOST if index == 0 else GUEST
	var second: String = GUEST if index == 0 else HOST
	var room := {"api_version":2,"schema_version":2,"simulation_version":state.simulation_version,"room_id":room_id,"revision":state.revision,"branch":state.branch,"stage_index":index,
		"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),"host_id":HOST,"guest_id":GUEST if state.joined else null,
		"checkpoint":fixture.checkpoints[index].duplicate(true),"a_turn_id":"t%d-%d-a" % [state.branch,index] if state.has_a else null,"completed_pair_ids":["p0-0","p0-1"].slice(0,index),
		"invite_expires_at":"2026-10-01T00:00:00Z","created_at":"2026-09-27T00:00:00Z","updated_at":"2026-09-27T00:00:00Z",
		"active_role":"b" if state.has_a else "a","first_player_id":first,"active_player_id":second if state.has_a else first,"player_slot":"p0" if owner == HOST else "p1",
		"stage_id":level.stages[index].id,"recording_a":fixture.pairs[index].a.duplicate(true) if state.has_a else null,"validation":"structural_client_replay_required"}
	if owner == HOST: room["invite_code"] = CODE
	return room

func _server(request: Dictionary) -> Dictionary:
	calls.append(request.duplicate(true))
	var path: String = request.path
	var body: Dictionary = request.body
	var owner: String = request.owner
	var post: bool = request.method == HTTPClient.METHOD_POST
	if path == "/v2/capabilities":
		return _ok({"api_version":2,"recording_version":2,"simulation_version":2,"mutations_enabled":enabled,"validation":"structural_client_replay_required","chapters":[{"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),"simulation_version":2,"recording_version":2,"supported_simulation_versions":[2,8],"premium":false}]})
	if path == "/v2/rooms" and not post:
		return _ok({"rooms":[_snapshot(owner)] if state.exists and (owner == HOST or state.joined) else []})
	if path == "/v1/friends":
		return _ok({"schema_version":1,"friend_code":owner,"refresh_after_seconds":60,"shared_room":null,"friends":[{"player_id":HOST,"request_id":FRIEND_REQUEST,"status":"accepted","online":false,"expires_after_seconds":0,"join_available":true}]})
	if path == "/v1/friends/"+HOST+"/join" and post and owner == GUEST and body.get("request_id") == FRIEND_REQUEST:
		return _ok({"schema_version":1,"api_version":2,"room_id":room_id,"invite_code":CODE})
	if post and not enabled: return _error("v2_mutations_disabled",503)
	if path == "/v2/rooms" and post and owner == HOST:
		state.exists = true
		state.simulation_version = body.get("simulation_version",2)
		return _ok(_snapshot(owner))
	# JSON numbers need canonical comparison; Array membership distinguishes floats from ints.
	if path == "/v2/rooms/join" and post and owner == GUEST and body.get("invite_code") == CODE and Canonical.same(body.get("supported_simulation_versions",[]),[2,4,5,6,7,8]):
		if not state.joined:
			state.joined = true
			state.revision += 1
		return _ok(_snapshot(owner))
	if not state.exists or (owner != HOST and not state.joined): return _error("room_not_found",404)
	if path == _room_path() and not post: return _ok(_snapshot(owner))
	if path.begins_with(_room_path()+"/operations/") and not post:
		var saved: Dictionary = receipts.get(path.get_file(),{})
		return _ok({"room":_snapshot(owner),"receipt":saved.receipt}) if saved.get("owner") == owner else _error("operation_not_found",404)
	if path == _room_path()+"/redo":
		var source := Redo.source_for("relay",_snapshot(owner))
		if post:
			_verify_redo_durable(owner,body)
			if source.is_empty() or owner != source.second_player_id or body.get("action") != "request" or not Canonical.same(body.get("source"),source): return _error("redo_source_changed",409)
			redo_request = {"request_id":Canonical.digest(source),"source":source,"status":"pending"}
		return _ok({"schema_version":1,"source":null if source.is_empty() else source,"request":null if source.is_empty() else redo_request})
	if path == _room_path()+"/turns" and post:
		var room := _snapshot(owner)
		var recording: Dictionary = body.get("recording",{})
		var index: int = state.stage_index
		if owner != room.active_player_id or body.get("base_revision") != state.revision or body.get("branch") != state.branch or not Canonical.same(recording,fixture.pairs[index][room.active_role]): return _error("invalid_recording",400)
		if room.active_role == "b" and not Canonical.same(body.get("checkpoint"),fixture.checkpoints[index+1]): return _error("invalid_checkpoint",400)
		state.revision += 1
		state.has_a = room.active_role == "a"
		if room.active_role == "b":
			accepted_pairs.append(fixture.pairs[index].duplicate(true))
			state.stage_index += 1
		var receipt := _receipt(body,"turns",index,recording.stage_id)
		receipt.turn_id = "t%d-%d-%s" % [state.branch,index,recording.role]
		receipt.recording_hash = recording.recording_hash
		receipt.pair_id = "p%d-%d" % [state.branch,index] if recording.role == "b" else null
		receipts[body.idempotency_key] = {"owner":owner,"receipt":receipt}
		return _ok({"room":_snapshot(owner),"receipt":receipt})
	if path == _room_path()+"/fork" and post:
		_verify_redo_durable(owner,body)
		var source := Redo.source_for("relay",_snapshot(owner))
		if source.is_empty() or not redo_request is Dictionary or owner != source.first_player_id or body.get("redo_request_id") != redo_request.request_id or body.get("base_revision") != state.revision or body.get("branch") != state.branch or body.get("stage_index") != state.stage_index: return _error("redo_source_changed",409)
		state.revision += 1
		state.branch += 1
		state.has_a = false
		redo_request.status = "accepted"
		var receipt := _receipt(body,"fork",state.stage_index,level.stages[state.stage_index].id)
		receipts[body.idempotency_key] = {"owner":owner,"receipt":receipt}
		return _ok({"room":_snapshot(owner),"receipt":receipt})
	return _error("unexpected_test_request",404)

func _receipt(body: Dictionary, operation: String, stage_index: int, stage_id: String) -> Dictionary:
	var hashed := body.duplicate(true)
	hashed.operation = operation
	return {"schema_version":2,"room_id":room_id,"idempotency_key":body.idempotency_key,"request_hash":Canonical.digest(hashed),"operation":operation,"accepted_revision":state.revision,"branch":state.branch,
		"stage_index":stage_index,"stage_id":stage_id,"checkpoint_hash":fixture.checkpoints[state.stage_index].checkpoint_hash,"turn_id":null,"recording_hash":null,"pair_id":null}

func _verify_redo_durable(owner: String, body: Dictionary) -> void:
	var store: RefCounted = stores[owner]
	var journal: Dictionary = store.values.get("relay-redo-relay-v1:"+owner+":"+room_id,{})
	redo_persisted_before_post = redo_persisted_before_post and Canonical.same(journal.get("pending",{}).get("body"),body)

func _calls(path: String, method: int, owner: String) -> Array:
	return calls.filter(func(item: Dictionary) -> bool: return item.path == path and item.method == method and item.owner == owner)
func _room_path() -> String: return "/v2/rooms/" + room_id
func _ok(value: Dictionary) -> Dictionary: return {"ok":true,"status":200,"data":value}
func _error(code: String, status: int) -> Dictionary: return {"ok":false,"status":status,"code":code}
func _check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	return value

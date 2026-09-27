extends SceneTree
const Owner = preload("res://services/campaign_online_session.gd")
const Online = preload("res://services/relay_online_session.gd")
const Protocol = preload("res://services/campaign_protocol.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Boundaries = preload("res://tests/test_campaign_room_bridge.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
var fixture: Dictionary
var checks := 0
var failures := 0

class Harness:
	extends Boundaries.Harness
	var operation_reply: Dictionary = {}
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		if "/operations/" not in path: return await super.request_json(method,path,body)
		busy = true
		calls.append({"method":method,"path":path,"body":body.duplicate(true)})
		if on_request.is_valid(): on_request.call()
		await get_tree().process_frame
		busy = false
		if not operation_reply.is_empty(): return operation_reply.duplicate(true)
		return {"ok":false,"status":404,"code":"operation_not_found"}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/campaign/control-v2.json"))
	for cold: bool in [false,true]:
		for guest: bool in [false,true]: await _recover(cold,guest)
	await _later_transition()
	await _bad_source()
	await _source_holds()
	print("Campaign continuing source: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _setup(cold: bool = true, guest: bool = false) -> Dictionary:
	var h := Harness.new()
	root.add_child(h)
	var player := GUEST if guest else HOST
	h.player_id = player
	h.identity_value.player_id = player
	var anchor: String = fixture.active_view.campaign_room_id
	h.view = fixture.active_view.duplicate(true) if not cold else fixture.pending_result.campaign.duplicate(true)
	if cold: h.view.transition.phase = "source_sealed"
	if guest: _project_guest(h.view)
	var level := Registry.definition("high-and-low@1")
	var room := {"schema_version":2,"api_version":2,"simulation_version":6,"room_id":anchor,"revision":5,"branch":0,
		"stage_index":2,"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),
		"host_id":HOST,"guest_id":GUEST,"checkpoint":JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cooperative/high-and-low-final-checkpoint.json")),
		"a_turn_id":null,"completed_pair_ids":["p0-0","p0-1"],"invite_expires_at":"2026-10-04T13:00:00.000Z",
		"created_at":"2026-09-27T12:00:00Z","updated_at":"2026-09-27T12:00:00Z","active_role":"complete","first_player_id":null,
		"active_player_id":null,"player_slot":"p1" if guest else "p0","stage_id":"","recording_a":null,"validation":"structural_client_replay_required"}
	if not guest: room["invite_code"] = "AB".repeat(10)
	h.rooms[anchor] = room
	var online := Online.new(h,h.identity,h.store)
	if not cold: _check(await online.open_room(anchor), "Already displayed source has a real natively verified completed proof")
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	_check(owner.restore_owner() and owner.bind_campaign(anchor,Protocol.key(fixture.definition)), "Durable owner binds without selecting a source for play")
	_check(await owner.refresh(), "Strict control view is observed")
	if not cold:
		_check(await owner.select_current() and owner.adopt_selected(), "Warm setup legitimately adopts the previously active source")
		h.view = fixture.pending_result.campaign.duplicate(true)
		h.view.transition.phase = "source_sealed"
		if guest: _project_guest(h.view)
		_check(await owner.refresh(), "Partner transition is discovered after source adoption")
	online.capabilities = {"mutations_enabled":true}
	return {"h":h,"owner":owner,"online":online,"anchor":anchor,"player":player}

func _recover(cold: bool, guest: bool) -> void:
	var c := await _setup(cold,guest)
	var selected: String = c.owner.selected_room()
	var last_room: String = c.online.last_room()
	var source: RefCounted = c.online.coordinator
	_check(c.owner.pending().is_empty() and not c.owner.can_leave(), "No local Continue exists, and normal adoption hold remains strict")
	var calls: int = c.h.calls.size()
	_check(not await c.owner.continue_current() and c.h.calls.size() == calls, "Ordinary Continue cannot bypass the continuing-source recovery boundary")
	c.h.on_request = func():
		if c.h.calls[-1].path.ends_with("/continue"):
			_check(Canonical.same(c.owner.pending().body,c.h.calls[-1].body), "The recovered member's exact intent is durable before POST")
	_check(not await c.owner.resume_continuation(), "Lost recovery POST returns a retryable outcome")
	var pending: Dictionary = c.owner.pending()
	_check(not pending.is_empty() and Protocol.continue_valid(pending.get("body",{}),c.anchor,c.player,fixture.definition), "Isolated native proof authorizes the member's bounded original-origin request")
	_check(Canonical.same(Protocol.origin(pending.get("body",{})),fixture.pending_result.campaign.transition.origin), "Recovery never replaces the prepared source origin")
	_check(c.online.coordinator == source and c.online.last_room() == last_room and c.owner.selected_room() == selected, "Recovery changes no visible coordinator, ordinary pointer or campaign selection")
	var writes := 0
	var source_gets := 0
	for call: Dictionary in c.h.calls.slice(calls):
		if call.method == HTTPClient.METHOD_POST:
			writes += 1
			_check(call.path.ends_with("/continue"), "Only the exact Continue is submitted")
		if call.path == "/v2/rooms/"+c.anchor: source_gets += 1
	_check(writes == 1 and source_gets == 1, "Fresh or warm member probes only its source and sends one deliberate Continue")
	var after: int = c.h.calls.size()
	_check(not await c.owner.resume_continuation() and c.h.calls.size() == after, "A now-pending request uses Retry instead of manufacturing another recovery intent")
	c.h.free()

func _later_transition() -> void:
	var c := await _setup(false)
	var selected: String = c.owner.selected_room()
	var source: RefCounted = c.online.coordinator
	_check(not await c.owner.resume_continuation() and not c.owner.pending().is_empty(), "The earlier source has a real durable lost-reply intent")
	var old_body: Dictionary = c.owner.pending().body
	var prepared: Dictionary = fixture.accepted_result.campaign.duplicate(true)
	var room_id: String = prepared.chapters[1].room_id
	var room: Dictionary = c.h.rooms[c.anchor].duplicate(true)
	var level := Registry.definition("rolling-home@1")
	room.room_id = room_id
	room.revision = 8
	room.level_id = level.id
	room.level_version = level.version
	room.definition_hash = Canonical.digest(level)
	room.checkpoint = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cooperative/rolling-home-final-checkpoint.json"))
	c.h.rooms[room_id] = room
	var origin := {"expected_revision":prepared.revision,"from_index":1,"source":{"room_id":room_id,"revision":room.revision,"branch":room.branch,"checkpoint_hash":room.checkpoint.checkpoint_hash}}
	prepared.state = "continuing"
	prepared.revision += 1
	prepared.transition = {"transition_id":"e".repeat(64),"phase":"source_sealed","origin":origin.duplicate(true)}
	c.h.view = prepared
	var accepted: Dictionary = fixture.accepted_result.duplicate(true)
	accepted.campaign = prepared.duplicate(true)
	accepted.receipt.idempotency_key = old_body.idempotency_key
	accepted.receipt.request_hash = Protocol.request_hash(c.anchor,HOST,old_body)
	_check(Protocol.result_valid(accepted,old_body,c.anchor,HOST,fixture.definition), "Earlier acceptance and later source-sealed publication form a strict valid result")
	c.h.operation_reply = {"ok":true,"status":200,"data":accepted}
	var calls: int = c.h.calls.size()
	_check(await c.owner.retry_continue() and c.owner.pending().is_empty(), "Retry settles the old accepted operation while the friend is handing off a later chapter")
	_check(_only_gets(c.h.calls.slice(calls)) and c.owner.selected_room() == selected and c.online.coordinator == source and c.online.last_room() == selected, "Old acceptance performs no POST, target adoption, rewind or pointer change")
	c.h.operation_reply = {}
	calls = c.h.calls.size()
	_check(not await c.owner.resume_continuation() and not c.owner.pending().is_empty(), "A deliberate recovery can now resume the later real completed source")
	var pending: Dictionary = c.owner.pending()
	_check(Canonical.same(Protocol.origin(pending.get("body",{})),origin), "Later source uses its prepared original revision and exact Rolling Home proof")
	var posts := 0
	var probes := 0
	for call: Dictionary in c.h.calls.slice(calls):
		if call.method == HTTPClient.METHOD_POST: posts += 1
		if call.path == "/v2/rooms/"+room_id: probes += 1
	_check(posts == 1 and probes == 1, "Later recovery verifies one Rolling Home source and sends exactly one Continue")
	_check(c.owner.selected_room() == selected and c.online.coordinator == source and c.online.last_room() == selected, "Cross-chapter recovery preserves the displayed earlier source until explicit adoption")
	c.h.free()

func _bad_source() -> void:
	for mismatch: String in ["revision","branch","proof","member"]:
		var c := await _setup()
		match mismatch:
			"revision": c.h.rooms[c.anchor].revision += 1
			"branch": c.h.rooms[c.anchor].branch += 1
			"proof": c.h.rooms[c.anchor].checkpoint.checkpoint_hash = "f".repeat(64)
			"member": c.h.rooms[c.anchor].guest_id = "Z".repeat(22)
		var calls: int = c.h.calls.size()
		_check(not await c.owner.resume_continuation() and c.owner.pending().is_empty(), "Mismatched "+mismatch+" cannot authorize recovery")
		_check(_only_gets(c.h.calls.slice(calls)) and c.online.coordinator == null and c.online.last_room().is_empty(), "Failed proof probe neither POSTs nor adopts")
		c.h.free()

func _source_holds() -> void:
	for race: String in ["before","after","identity"]:
		var c := await _setup()
		if race == "before": c.h.leave_allowed = false
		else:
			c.h.on_request = func():
				if c.h.calls[-1].path == "/v2/rooms/"+c.anchor:
					if race == "identity": c.h.identity_value.epoch += 1
					else: c.h.leave_allowed = false
		var calls: int = c.h.calls.size()
		_check(not await c.owner.resume_continuation(), "Recovery respects the "+race+" source/owner boundary")
		_check(_only_gets(c.h.calls.slice(calls)) and c.online.coordinator == null, "Changed readiness never submits or replaces the scene")
		if race == "before": _check(c.h.calls.size() == calls, "An active unsaved/photo navigation hold does not even probe")
		c.h.free()

func _project_guest(view: Dictionary) -> void:
	view.player_slot = "p1"
	view.invite_code = null
	view.invite_expires_at = null

func _only_gets(calls: Array) -> bool:
	for call: Dictionary in calls:
		if call.method != HTTPClient.METHOD_GET: return false
	return true

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

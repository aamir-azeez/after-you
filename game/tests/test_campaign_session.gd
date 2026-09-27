extends SceneTree
const Session = preload("res://services/campaign_session.gd")
const Protocol = preload("res://services/campaign_protocol.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var fixture: Dictionary
var checks := 0
var failures := 0

class Source:
	extends RefCounted
	var room: Dictionary = {}
	var read_only := false
	var held := false
	func snapshot() -> Dictionary: return room.duplicate(true)
	func chapter_complete() -> bool: return true
	func pending() -> Dictionary: return {"write":"pending"} if held else {}

class Harness:
	extends Node
	var fixture: Dictionary
	var identity: Dictionary
	var saved: Dictionary = {}
	var remote: Dictionary
	var accepted: Dictionary = {}
	var calls: Array = []
	var validated: Array = []
	var writes := 0
	var fail_write := -1
	var posts := 0
	var drop_post := false
	var pending_post := false
	var native_ok := true
	var selection_ok := true
	var on_request: Callable
	var on_validate: Callable
	var on_save: Callable
	var lookup_error: Dictionary = {}
	func current_identity() -> Dictionary: return identity.duplicate(true)
	func load_store(scope: String) -> Dictionary: return {"ok":true,"found":saved.has(scope),"value":saved.get(scope,{}).duplicate(true)}
	func save_store(scope: String, value: Dictionary) -> Dictionary:
		writes += 1
		if on_save.is_valid(): on_save.call(value)
		if writes == fail_write: return {"ok":false}
		saved[scope] = value.duplicate(true)
		return {"ok":true}
	func can_select() -> bool: return selection_ok
	func verify_target(room: String, _pin: Dictionary, owner: String, epoch: int) -> Dictionary:
		validated.append({"room":room,"owner":owner,"epoch":epoch})
		if on_validate.is_valid(): on_validate.call()
		await get_tree().process_frame
		return {"ok":native_ok,"room_id":room}
	func project(value: Dictionary, owner: String) -> Dictionary:
		var result := value.duplicate(true)
		if owner == result.guest_id:
			result.player_slot = "p1"
			result.invite_code = null
			result.invite_expires_at = null
		return result
	func personalize(result: Dictionary, owner: String, body: Dictionary) -> Dictionary:
		var copy := result.duplicate(true)
		copy.campaign = project(copy.campaign,owner)
		var target: Dictionary = copy.receipt if copy.status == "accepted" else copy
		target.player_id = owner
		target.idempotency_key = body.idempotency_key
		target.request_hash = Protocol.request_hash(copy.campaign.campaign_room_id,owner,body)
		return copy
	func transport(request: Dictionary) -> Dictionary:
		calls.append(request.duplicate(true))
		if on_request.is_valid(): on_request.call(request)
		await get_tree().process_frame
		if request.path.ends_with("/continue"):
			posts += 1
			if pending_post:
				remote = fixture.pending_result.campaign.duplicate(true)
				return {"ok":true,"status":202,"data":personalize(fixture.pending_result,request.owner_player_id,request.body)}
			accepted = personalize(fixture.accepted_result,request.owner_player_id,request.body)
			remote = accepted.campaign.duplicate(true)
			if drop_post:
				drop_post = false
				return {"ok":false,"status":0,"code":"connection_interrupted"}
			return {"ok":true,"status":200,"data":accepted.duplicate(true)}
		if "/operations/" in request.path:
			if not lookup_error.is_empty(): return lookup_error.duplicate(true)
			if not accepted.is_empty() and request.path.ends_with(accepted.receipt.idempotency_key): return {"ok":true,"status":200,"data":accepted.duplicate(true)}
			return {"ok":false,"status":404,"code":"operation_not_found"}
		return {"ok":true,"status":200,"data":{"campaign":project(remote,request.owner_player_id)}}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/campaign/control-v1.json"))
	await _lost_response()
	await _storage_and_selection()
	await _identity_races()
	await _partner_continuation()
	await _deleting_and_history()
	await _later_transition()
	await _newer_selection()
	await _disappearing_transition()
	await _selection_race()
	print("CAMPAIGN SESSION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(label)

func _harness() -> Harness:
	var h := Harness.new()
	h.fixture = fixture.duplicate(true)
	h.identity = {"ready":true,"player_id":fixture.active_view.host_id,"epoch":1}
	h.remote = fixture.active_view.duplicate(true)
	root.add_child(h)
	return h

func _session(h: Harness) -> RefCounted:
	var session := Session.new(h.transport,h.load_store,h.save_store,h.current_identity,h.verify_target,h.can_select)
	_check(session.bind(fixture.active_view.campaign_room_id,fixture.definition),"Session binds its exact owner and bundled campaign")
	return session

func _source() -> Source:
	var source := Source.new()
	source.room = fixture.continue_body.source.duplicate(true)
	source.room.merge(fixture.definition.chapters[0])
	source.room.merge({"host_id":fixture.active_view.host_id,"guest_id":fixture.active_view.guest_id,"active_role":"complete","checkpoint":{"checkpoint_hash":fixture.continue_body.source.checkpoint_hash}})
	return source

func _lost_response() -> void:
	var h := _harness()
	var session := _session(h)
	_check(await session.refresh(),"Load active campaign without moving the selected room")
	h.on_request = func(request: Dictionary):
		if request.path.ends_with("/continue"):
			_check(not session.pending().is_empty() and h.saved.values()[0].pending.body == request.body,"Exact Continue intent is durable before the POST")
	h.drop_post = true
	_check(not await session.continue_from(_source()) and h.posts == 1 and not session.pending().is_empty(),"Lost accepted response preserves the original pending intent")
	var cold := _session(h)
	_check(await cold.retry() and h.posts == 1,"Cold retry reconciles accepted operation before any resend")
	_check(cold.pending().is_empty() and cold.selected_room() == fixture.accepted_result.receipt.next_room_id,"Native target verification and saved selection settle the exact pending operation")
	_check(h.validated.size() == 1,"Accepted target is independently verified once before selection")
	_check(cold.mark_story_seen(0,"completion") and cold.story_seen(0,"completion"),"Personal story reading is durable and separate from shared progression")
	_check(not cold.mark_story_seen(1,"completion"),"Unread future completion cannot be marked earned by advancing the story UI")
	h.free()

func _later_transition() -> void:
	var h := _harness()
	var session := _session(h)
	await session.refresh()
	h.native_ok = false
	await session.continue_from(_source())
	# Another device accepted this target and now begins its terminal Finish.
	var prepared: Dictionary = h.remote.duplicate(true)
	var previous_revision: int = prepared.revision
	var source_context := {"room_id":prepared.chapters[1].room_id,"revision":8,"branch":0,"checkpoint_hash":"f".repeat(64)}
	prepared.state = "continuing"
	prepared.revision += 1
	prepared.transition = {"transition_id":"e".repeat(64),"phase":"source_sealed","origin":{"expected_revision":previous_revision,"from_index":1,"source":source_context}}
	h.remote = prepared
	var cold := _session(h)
	var before := h.validated.size()
	_check(await cold.retry() and cold.pending().is_empty(),"Older accepted intent settles without blocking the partner's later continuation")
	_check(cold.selected_room().is_empty() and h.validated.size() == before,"Settling an old intent during a later handoff does not select an earlier room")
	var next_source := Source.new()
	next_source.room = source_context.duplicate(true)
	next_source.room.merge(fixture.definition.chapters[1])
	next_source.room.merge({"host_id":fixture.active_view.host_id,"guest_id":fixture.active_view.guest_id,"active_role":"complete","checkpoint":{"checkpoint_hash":source_context.checkpoint_hash}})
	h.fixture.pending_result.campaign = prepared.duplicate(true)
	h.fixture.pending_result.transition_id = prepared.transition.transition_id
	h.pending_post = true
	_check(not await cold.continue_from(next_source) and cold.last_code == "campaign_continuing","The same device can resume the later source-sealed transition deliberately")
	_check(cold.pending().body.from_index == 1 and cold.pending().body.expected_revision == previous_revision,"New pending intent uses the later transition's original source")
	# A device that missed both publication and the next prepare can refresh
	# directly across those phases, using the saved transition's completion.
	var missed := _harness()
	missed.remote = fixture.pending_result.campaign.duplicate(true)
	var observer := _session(missed)
	await observer.refresh()
	missed.remote = prepared.duplicate(true)
	_check(await observer.refresh() and observer.view().current_index == 1,"Published completion proves progression from one prepared handoff to a later handoff")
	missed.free()
	h.free()

func _newer_selection() -> void:
	var longer: Dictionary = fixture.definition.duplicate(true)
	longer.chapters.append(longer.chapters[0].duplicate(true))
	longer.erase("definition_hash")
	var digest := Canonical.digest(longer)
	longer["definition_hash"] = digest
	var h := _harness()
	h.remote = _extended_view(h.remote,longer)
	h.fixture.accepted_result.campaign = _extended_view(h.fixture.accepted_result.campaign,longer)
	h.fixture.accepted_result.receipt.campaign_key = Protocol.key(longer)
	var session := Session.new(h.transport,h.load_store,h.save_store,h.current_identity,h.verify_target,h.can_select)
	_check(session.bind(fixture.active_view.campaign_room_id,longer) and await session.refresh(),"Three-entry fixture begins with independently pinned chapter references")
	h.native_ok = false
	await session.continue_from(_source())
	var from_revision: int = h.remote.revision
	h.remote.chapters[1].completion = {"source_revision":9,"source_branch":0,"checkpoint_hash":"f".repeat(64),"transition_id":"e".repeat(64),"from_campaign_revision":from_revision,"accepted_campaign_revision":from_revision+1}
	h.remote.chapters[2].room_id = "Z".repeat(22)
	h.remote.current_index = 2
	h.remote.revision += 2
	var cold := Session.new(h.transport,h.load_store,h.save_store,h.current_identity,h.verify_target,h.can_select)
	_check(cold.bind(fixture.active_view.campaign_room_id,longer),"Cold process retains the older accepted operation")
	h.native_ok = true
	_check(await cold.retry() and cold.selected_room() == "Z".repeat(22),"Reconciliation selects the latest published room instead of rewinding to an old receipt target")
	_check(not h.validated.is_empty() and h.validated[-1].room == "Z".repeat(22) and h.posts == 1,"Latest child receives native validation without repeating Continue")
	h.free()

func _extended_view(original: Dictionary, definition: Dictionary) -> Dictionary:
	var value := original.duplicate(true)
	value.campaign_key = Protocol.key(definition)
	value.chapters.append({"chapter":definition.chapters[2].duplicate(true),"room_id":null,"completion":null})
	return value

func _storage_and_selection() -> void:
	var h := _harness()
	var session := _session(h)
	await session.refresh()
	h.fail_write = h.writes+1
	_check(not await session.continue_from(_source()) and h.calls.size() == 1 and session.pending().is_empty(),"Failed intent save sends no lookup or mutation")
	h.fail_write = -1
	h.native_ok = false
	_check(not await session.continue_from(_source()) and not session.pending().accepted_receipt.is_empty() and session.selected_room().is_empty(),"Invalid target keeps durable acceptance without a false room switch")
	var cold := _session(h)
	h.native_ok = true
	h.selection_ok = false
	_check(not await cold.retry() and cold.last_code == "previous_room_pending","Previous room's unresolved write prevents target selection")
	h.selection_ok = true
	h.on_validate = func(): h.selection_ok = false
	_check(not await cold.retry() and cold.last_code == "previous_room_pending" and not cold.pending().is_empty() and cold.selected_room().is_empty(),"A previous-room write starting during target verification preserves pending acceptance and selection")
	h.selection_ok = true
	h.on_validate = func(): h.fail_write = h.writes+1
	_check(not await cold.retry() and cold.selected_room().is_empty() and not cold.pending().is_empty(),"Disk failure after native verification retains acceptance and old selection")
	h.on_validate = Callable()
	h.fail_write = -1
	_check(await cold.retry() and h.posts == 1,"Retrying a failed selection never creates another chapter")
	h.free()

func _identity_races() -> void:
	var h := _harness()
	var session := _session(h)
	await session.refresh()
	h.on_request = func(request: Dictionary):
		if request.path.ends_with("/continue"): h.identity.epoch += 1
	_check(not await session.continue_from(_source()),"A reply to an old identity epoch cannot advance the local story")
	_check(h.saved.values()[0].selected_room == "" and not h.saved.values()[0].pending.is_empty(),"Late reply leaves the saved unresolved request intact")
	h.on_request = Callable()
	var recovered := _session(h)
	h.on_validate = func(): recovered.invalidate_identity()
	_check(not await recovered.retry() and h.saved.values()[0].selected_room == "","Identity invalidation during native verification never persists target selection")
	h.free()

func _partner_continuation() -> void:
	for phase: String in ["prepared","source_sealed"]:
		var h := _harness()
		h.identity.player_id = fixture.active_view.guest_id
		h.remote = fixture.pending_result.campaign.duplicate(true)
		h.remote.transition.phase = phase
		var session := _session(h)
		_check(await session.refresh(),"Offline partner sees the existing "+phase+" transition")
		_check(await session.continue_from(_source()),"Partner can deliberately resume the original transition after its initiator disappears")
		var posted: Dictionary = h.calls[-1].body
		_check(posted.expected_revision == fixture.continue_body.expected_revision and posted.idempotency_key != fixture.continue_body.idempotency_key,"Partner alias binds its owner and the original origin, not the newer control revision")
		_check(h.posts == 1 and session.selected_room() == fixture.accepted_result.receipt.next_room_id,"Partner continuation converges on the one published target")
		h.free()

func _deleting_and_history() -> void:
	var h := _harness()
	var session := _session(h)
	await session.refresh()
	h.native_ok = false
	await session.continue_from(_source())
	h.remote.state = "deleting"
	h.remote.revision += 1
	var cold := _session(h)
	h.native_ok = true
	var before := h.validated.size()
	_check(not await cold.retry() and cold.last_code == "campaign_deleting","Accepted receipt remains recoverable while whole-story deletion is in progress")
	_check(h.validated.size() == before and cold.selected_room().is_empty(),"Deleting control never selects a still-present gameplay child")
	var stored: Dictionary = h.saved.values()[0].duplicate(true)
	stored.schema_version = 77
	h.saved[h.saved.keys()[0]] = stored
	var held := Session.new(h.transport,h.load_store,h.save_store,h.current_identity,h.verify_target,h.can_select)
	_check(not held.bind(fixture.active_view.campaign_room_id,fixture.definition) and held.read_only,"Future campaign journal holds for an update")
	_check(not held.bind("Z".repeat(22),fixture.definition) and h.saved.values()[0].schema_version == 77,"Switching campaigns cannot bypass a held unreadable journal")
	h.free()

func _disappearing_transition() -> void:
	var h := _harness()
	h.remote = fixture.pending_result.campaign.duplicate(true)
	h.remote.transition.phase = "source_sealed"
	var session := _session(h)
	_check(await session.refresh(),"Observer retains the sealed source transition")
	var before := Canonical.digest(h.saved)
	h.remote = fixture.active_view.duplicate(true)
	h.remote.revision = int(session.view().revision)+1
	_check(not await session.refresh() and session.last_code == "campaign_transition_conflict" and Canonical.digest(h.saved) == before,"A sealed transition cannot disappear back to an active source")
	h.remote = fixture.accepted_result.campaign.duplicate(true)
	h.remote.chapters[0].completion.transition_id = "f".repeat(64)
	_check(not await session.refresh() and session.last_code == "campaign_transition_conflict" and Canonical.digest(h.saved) == before,"Advancement cannot replace the saved source transition with a different completion")
	h.remote = fixture.accepted_result.campaign.duplicate(true)
	_check(await session.refresh(),"The exact completion permits a transition to disappear into published advancement")
	h.free()

func _selection_race() -> void:
	var h := _harness()
	var session := _session(h)
	await session.refresh()
	var before := Canonical.digest(h.saved)
	h.on_validate = func(): h.selection_ok = false
	_check(not await session.select_current() and session.last_code == "previous_room_pending" and Canonical.digest(h.saved) == before,"Direct chapter selection also rechecks the previous room after asynchronous validation")
	h.on_validate = Callable()
	h.selection_ok = true
	_check(await session.select_current() and session.selected_room() == fixture.active_view.chapters[0].room_id,"A later deliberate selection succeeds after the prior write is reconciled")
	h.free()

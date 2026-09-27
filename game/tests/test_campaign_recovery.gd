extends SceneTree
const Session = preload("res://services/campaign_session.gd")
const Base = preload("res://tests/test_campaign_session.gd")
const Protocol = preload("res://services/campaign_protocol.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var fixture: Dictionary
var checks := 0
var failures := 0

class Harness:
	extends Base.Harness
	var lookup_reply: Dictionary = {}
	var resume_reply: Dictionary = {}
	var resume_posts := 0
	func transport(request: Dictionary) -> Dictionary:
		var is_resume: bool = request.path.ends_with("/resume")
		if not is_resume and not ("/operations/" in request.path and not lookup_reply.is_empty()):
			return await super.transport(request)
		calls.append(request.duplicate(true))
		if on_request.is_valid(): on_request.call(request)
		await get_tree().process_frame
		if is_resume:
			resume_posts += 1
			return resume_reply.duplicate(true)
		return lookup_reply.duplicate(true)

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/campaign/control-v2.json"))
	await _pending_repost()
	await _pending_observation_guards()
	await _deleting_lookup_guards()
	await _sealed_rejection()
	await _accepted_activation()
	await _unreceipted_activation()
	await _resume_failure_guards()
	await _fresh_guest_and_later_debt()
	print("Campaign explicit recovery: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _harness() -> Harness:
	var h := Harness.new()
	h.fixture = fixture.duplicate(true)
	h.identity = {"ready":true,"player_id":fixture.active_view.host_id,"epoch":1}
	h.remote = fixture.active_view.duplicate(true)
	root.add_child(h)
	return h

func _session(h: Harness) -> RefCounted:
	var session := Session.new(h.transport,h.load_store,h.save_store,h.current_identity,h.verify_target,h.can_select)
	_check(session.bind(h.remote.campaign_room_id,h.fixture.definition), "Exact owner and manifest bind")
	return session

func _source() -> RefCounted:
	var source := Base.Source.new()
	source.room = fixture.continue_body.source.duplicate(true)
	source.room.merge(fixture.definition.chapters[0])
	source.room.merge({"host_id":fixture.active_view.host_id,"guest_id":fixture.active_view.guest_id,
		"active_role":"complete","checkpoint":{"checkpoint_hash":fixture.continue_body.source.checkpoint_hash}})
	return source

func _pending(h: Harness) -> RefCounted:
	var session := _session(h)
	_check(await session.refresh(), "Initial read-only campaign view loads")
	h.post_error = {"ok":false,"status":503,"code":"unavailable"}
	_check(not await session.continue_from(_source()) and not session.pending().is_empty(), "Uncertain Continue leaves its durable original intent")
	h.post_error = {}
	return session

func _pending_reply(h: Harness, phase: String = "source_sealed") -> Dictionary:
	var result: Dictionary = fixture.pending_result.duplicate(true)
	result.campaign.transition.phase = phase
	var saved: Dictionary = h.saved.values()[0].pending.body
	return {"ok":true,"status":202,"data":h.personalize(result,h.identity.player_id,saved)}

func _pending_repost() -> void:
	for post_pending: bool in [false,true]:
		var h := _harness()
		var session := await _pending(h)
		var pending: Dictionary = session.pending()
		h.lookup_reply = _pending_reply(h)
		h.pending_post = post_pending
		h.fixture.pending_result = h.lookup_reply.data.duplicate(true)
		h.on_request = func(request: Dictionary):
			if request.path.ends_with("/continue"):
				_check(Canonical.same(request.body,pending.body), "Retry reuses the exact saved Continue body and key")
				_check(h.saved.values()[0].view.transition.phase == "source_sealed", "Observed source seal is durable before deliberate repost")
		var posts: int = h.posts
		var okay: bool = await session.retry()
		_check(h.posts == posts+1, "One deliberate Retry sends at most one Continue POST after GET202")
		_check(okay != post_pending and session.pending().is_empty() != post_pending, "Accepted result settles while another202 retains the same operation")
		if post_pending: _check(Canonical.same(session.pending(),pending), "Pending response cannot regenerate the request")
		h.free()

func _pending_observation_guards() -> void:
	for mode: String in ["save","unknown","malformed","wrong_key"]:
		var h := _harness()
		var session := await _pending(h)
		var before: Dictionary = h.saved.duplicate(true)
		var posts: int = h.posts
		h.lookup_reply = _pending_reply(h)
		match mode:
			"save": h.fail_write = h.writes+1
			"unknown": h.lookup_reply = {"ok":false,"status":503,"code":"unavailable"}
			"malformed": h.lookup_reply.data.campaign.extra = "unsupported"
			"wrong_key": h.lookup_reply.data.idempotency_key = "f".repeat(64)
		_check(not await session.retry() and h.posts == posts, mode+" cannot cause a speculative Continue POST")
		_check(Canonical.same(before,h.saved), mode+" preserves every durable request and view byte")
		h.free()

func _sealed_rejection() -> void:
	var h := _harness()
	var session := await _pending(h)
	h.lookup_reply = _pending_reply(h)
	h.reject_post = true
	_check(not await session.retry() and session.last_code == "campaign_transition_conflict", "A contradictory rejection cannot undo a seal learned from GET202")
	_check(session.view().transition.phase == "source_sealed" and not session.pending().is_empty(), "Failed rejection retains the durable observed phase and exact intent")
	h.free()

func _deleting_lookup_guards() -> void:
	for from_lookup: bool in [true,false]:
		var h := _harness()
		var session := await _pending(h)
		var pending: Dictionary = session.pending()
		if from_lookup:
			h.lookup_reply = _pending_reply(h)
			h.lookup_reply.data.campaign.state = "deleting"
		else:
			h.remote.state = "deleting"
			h.remote.revision += 1
			_check(await session.refresh(), "Deletion may be learned before operation lookup")
		var posts: int = h.posts
		_check(not await session.retry() and session.last_code == "campaign_deleting" and h.posts == posts, "Deleting control prevents both404 and202 Continue reposts")
		_check(session.view().state == "deleting" and Canonical.same(session.pending(),pending), "Deletion observation preserves the exact unresolved request")
		h.free()

func _accepted_debt(h: Harness, drop: bool = false) -> RefCounted:
	var session := _session(h)
	_check(await session.refresh(), "Initial view loads before accepted handoff")
	h.fixture.accepted_result.campaign.activation = {"transition_id":fixture.accepted_result.receipt.transition_id}
	h.drop_post = drop
	_check(not await session.continue_from(_source()), "Accepted activation is not yet ready for adoption")
	if drop: _check(await session.refresh(), "Read-only refresh can discover debt after a lost acceptance reply")
	return session

func _clear_reply(session: RefCounted) -> Dictionary:
	var view: Dictionary = session.view()
	view.activation = null
	view.revision += 1
	return {"ok":true,"status":200,"data":{"campaign":view}}

func _accepted_activation() -> void:
	var h := _harness()
	var session := await _accepted_debt(h)
	var cold := _session(h)
	h.resume_reply = _clear_reply(cold)
	var posts: int = h.posts
	h.on_request = func(request: Dictionary):
		if request.path.ends_with("/resume"):
			_check(request.method == HTTPClient.METHOD_POST and Protocol.resume_activation_valid(request.body,h.fixture.definition), "Explicit Resume sends only the bounded pinned activation request")
			_check(request.body.transition_id == fixture.accepted_result.receipt.transition_id, "Resume uses the saved marker, not a newly generated transition")
	_check(await cold.resume_activation(), "Restart can explicitly discharge activation and settle its accepted receipt")
	_check(cold.pending().is_empty() and cold.selected_room() == fixture.accepted_result.receipt.next_room_id and h.validated.size() == 1, "Accepted recovery uses native verification before durable selection")
	_check(h.posts == posts and h.resume_posts == 1, "Resume never rePOSTs Continue")
	_check(not await cold.resume_activation() and h.resume_posts == 1, "Already discharged local view sends no extra Resume")
	h.free()

func _unreceipted_activation() -> void:
	var h := _harness()
	var session := await _accepted_debt(h,true)
	var original: Dictionary = session.pending()
	h.resume_reply = _clear_reply(session)
	var calls: int = h.calls.size()
	_check(not await session.resume_activation() and session.last_code == "campaign_receipt_pending", "Activation discharge cannot replace a lost Continue receipt")
	_check(Canonical.same(original,session.pending()) and h.calls.size() == calls+1 and h.validated.is_empty(), "Unreceipted operation stays exact without hidden lookup or target selection")
	h.remote = h.resume_reply.data.campaign.duplicate(true)
	var posts: int = h.posts
	_check(await session.retry() and session.pending().is_empty() and h.posts == posts, "A later deliberate Retry recovers the accepted alias by GET and settles")
	h.free()

func _resume_failure_guards() -> void:
	for mode: String in ["unknown","pending","wrong_status","malformed","save","identity","deleting"]:
		var h := _harness()
		var session := await _accepted_debt(h)
		var before: Dictionary = h.saved.duplicate(true)
		var posts: int = h.posts
		h.resume_reply = _clear_reply(session)
		match mode:
			"unknown": h.resume_reply = {"ok":false,"status":503,"code":"unavailable"}
			"pending": h.resume_reply = {"ok":true,"status":202,"data":{"campaign":session.view()}}
			"wrong_status": h.resume_reply = {"ok":true,"status":200,"data":{"campaign":session.view()}}
			"malformed": h.resume_reply.data.campaign.extra = "unsupported"
			"save": h.fail_write = h.writes+1
			"identity": h.on_request = func(_request: Dictionary): h.identity.epoch += 1
			"deleting": h.resume_reply.data.campaign.state = "deleting"
		_check(not await session.resume_activation() and h.posts == posts and h.validated.is_empty(), mode+" cannot authorize native selection or a new Continue")
		if mode == "deleting":
			_check(session.view().state == "deleting" and not session.pending().is_empty(), "Authoritative deletion stays durable and retains the accepted intent")
		else:
			_check(Canonical.same(before,h.saved), mode+" preserves the exact stored debt and intent")
		h.free()

func _fresh_guest_and_later_debt() -> void:
	for later: bool in [false,true]:
		var h := _harness()
		h.identity.player_id = fixture.active_view.guest_id
		h.remote = fixture.accepted_result.campaign.duplicate(true)
		h.remote.activation = {"transition_id":fixture.accepted_result.receipt.transition_id}
		if later:
			h.fixture.definition.chapters.append(h.fixture.definition.chapters[0].duplicate(true))
			var body: Dictionary = h.fixture.definition.duplicate(true)
			body.erase("definition_hash")
			h.fixture.definition.definition_hash = Canonical.digest(body)
			h.remote.campaign_key = Protocol.key(h.fixture.definition)
			h.remote.chapters.append({"chapter":h.fixture.definition.chapters[2].duplicate(true),"room_id":null,"completion":null})
		var session := _session(h)
		_check(await session.refresh(), "Fresh guest can observe the exact activation debt without a local Continue")
		h.resume_reply = _clear_reply(session)
		if later:
			var next: Dictionary = h.resume_reply.data.campaign
			next.chapters[1].completion = {"source_revision":8,"source_branch":0,"checkpoint_hash":"d".repeat(64),"transition_id":"e".repeat(64),"from_campaign_revision":session.view().revision+1,"accepted_campaign_revision":session.view().revision+2}
			next.revision = session.view().revision+2
			next.current_index = 2
			next.chapters[2].room_id = "C".repeat(22)
			next.activation = {"transition_id":"e".repeat(64)}
		var okay: bool = await session.resume_activation()
		_check(okay != later and h.resume_posts == 1 and h.posts == 0 and h.validated.is_empty(), "Fresh-device Resume does not select, adopt or send Continue")
		if later: _check(session.view().activation.transition_id == "e".repeat(64) and session.view().current_index == 2, "A delayed prior Resume preserves and holds the later chapter's different debt")
		else: _check(session.view().activation == null and session.selected_room().is_empty(), "Discharged fresh-device view still requires separate target selection")
		h.free()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

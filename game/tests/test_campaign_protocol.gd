extends SceneTree
## Cross-language fixtures and adversarial control replies, without network I/O.
const Protocol = preload("res://services/campaign_protocol.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0
var fixture: Dictionary
var definition: Dictionary
var owner := ""
var anchor := ""

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/campaign/control-v1.json"))
	definition = fixture.definition
	owner = fixture.active_view.host_id
	anchor = fixture.active_view.campaign_room_id
	_cross_language()
	_projection()
	_continuation()
	_rejection()
	_maximum_history()
	_bounds()
	print("CAMPAIGN PROTOCOL: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)

func _rejection() -> void:
	for result: Dictionary in [fixture.rejected_result,fixture.rejected_newer_result,fixture.rejected_equal_result]:
		_check(Protocol.result_valid(result,fixture.continue_body,anchor,owner,definition),"Bound terminal fork receipt remains valid after a newer branch completes")
	for invalid: Dictionary in fixture.invalid_rejections:
		_check(not Protocol.result_valid(invalid.result,fixture.continue_body,anchor,owner,definition),"Reject contradictory terminal receipt: "+invalid.id)

func _cross_language() -> void:
	_check(fixture.test_only and Protocol.definition_valid(definition),"Synthetic manifest uses valid exact chapter and story pins")
	var body := Protocol.continue_body(anchor,owner,definition,Protocol.origin(fixture.continue_body))
	_check(Canonical.same(body,fixture.continue_body),"Native canonical Continue key exactly matches server fixture")
	_check(Protocol.request_hash(anchor,owner,body) == fixture.expected_request_hash,"Native request hash matches the full canonical server body")
	_check(Protocol.view_valid(fixture.active_view,definition,owner),"Host view binds its verified invitation to the campaign anchor")
	_check(Protocol.result_valid(fixture.pending_result,body,anchor,owner,definition),"A prepared response is valid pending control, not an accepted successor")
	_check(Protocol.result_valid(fixture.accepted_result,body,anchor,owner,definition),"Accepted receipt binds the exact request and published target")
	for example: Dictionary in fixture.invalid_views:
		_check(not Protocol.view_valid(example.view,definition,owner),"Shared server/client invalid fixture: "+str(example.id))
	var changed := definition.duplicate(true)
	changed.story.content_hash = "b".repeat(64)
	_check(not Protocol.definition_valid(changed),"Narrative content cannot silently change inside the pinned manifest")
	_rehash(changed)
	_check(Protocol.definition_valid(changed) and not Protocol.view_valid(fixture.active_view,changed,owner),"An intentionally repinned story remains distinct from an existing campaign")
	changed = definition.duplicate(true)
	changed.chapters[0].premium = true
	_rehash(changed)
	_check(not Protocol.definition_valid(changed),"Client-supplied premium policy cannot override the bundled chapter")
	changed = definition.duplicate(true)
	changed.chapters[0].simulation_version = 77
	_rehash(changed)
	_check(not Protocol.definition_valid(changed),"Unknown simulation does not fall back to a prior engine")

func _projection() -> void:
	var view: Dictionary = fixture.active_view.duplicate(true)
	view.player_slot = "p1"
	view.invite_code = null
	view.invite_expires_at = null
	_check(Protocol.view_valid(view,definition,view.guest_id),"Guest sees its own slot with explicit null invite fields")
	_check(not Protocol.view_valid(view,definition,owner),"A late guest reply cannot bind to the host")
	view.invite_code = fixture.active_view.invite_code
	_check(not Protocol.view_valid(view,definition,view.guest_id),"Guest projection cannot expose a host-only invite")
	view = fixture.active_view.duplicate(true)
	view.invite_code = "C".repeat(20)
	_check(not Protocol.view_valid(view,definition,owner),"A well-formed but unrelated invite cannot be copied as this campaign")
	for date: String in ["2026-02-30T13:00:00.000Z","2026-09-27T25:00:00Z","2026-09-27T13:00:00+01:00","2026-09-27T13:00:00Z"]:
		view = fixture.active_view.duplicate(true)
		view.invite_expires_at = date
		_check(not Protocol.view_valid(view,definition,owner),"Malformed or non-UTC invitation expiry is rejected")
	view = fixture.active_view.duplicate(true)
	view.guest_id = null
	view.state = "waiting"
	_check(Protocol.view_valid(view,definition,owner),"A host can retain the first room while waiting for its guest")
	view.state = "active"
	_check(not Protocol.view_valid(view,definition,owner),"A missing guest never appears as an active paired story")
	for field: String in fixture.active_view:
		view = fixture.active_view.duplicate(true)
		view.erase(field)
		_check(not Protocol.view_valid(view,definition,owner),"Missing required control field holds: "+field)
	view = fixture.active_view.duplicate(true)
	view.checkpoint = {"proof":"not allowed"}
	_check(not Protocol.view_valid(view,definition,owner),"Proof bodies cannot be smuggled into the bounded control envelope")
	view = fixture.accepted_result.campaign.duplicate(true)
	view.chapters[1].room_id = anchor
	_check(not Protocol.view_valid(view,definition,owner),"A published successor cannot alias an earlier room")
	view = fixture.accepted_result.campaign.duplicate(true)
	view.chapters[0].completion = null
	_check(not Protocol.view_valid(view,definition,owner),"Advanced control requires the exact completed prefix")

func _continuation() -> void:
	var body: Dictionary = fixture.continue_body.duplicate(true)
	body.idempotency_key = "d".repeat(64)
	_check(not Protocol.continue_valid(body,anchor,owner,definition),"Random aliases cannot fill the bounded operation journal")
	body = fixture.continue_body.duplicate(true)
	body.source.branch = 32
	_check(not Protocol.continue_valid(body,anchor,owner,definition),"An out-of-range source branch is not another valid origin")
	var result: Dictionary = fixture.accepted_result.duplicate(true)
	result.receipt.player_id = fixture.active_view.guest_id
	_check(not Protocol.result_valid(result,fixture.continue_body,anchor,owner,definition),"Other member's receipt cannot clear this owner's pending request")
	for field: String in ["request_hash","transition_id"]:
		result = fixture.accepted_result.duplicate(true)
		result.receipt[field] = "e".repeat(64)
		_check(not Protocol.result_valid(result,fixture.continue_body,anchor,owner,definition),"Mismatched accepted binding holds: "+field)
	result = fixture.accepted_result.duplicate(true)
	result.receipt.next_room_id = "X".repeat(22)
	_check(not Protocol.result_valid(result,fixture.continue_body,anchor,owner,definition),"Receipt cannot redirect into an unpublished child")
	result = fixture.accepted_result.duplicate(true)
	result.receipt.next_index = 0
	_check(not Protocol.result_valid(result,fixture.continue_body,anchor,owner,definition),"Receipt cannot rewind the campaign")
	result = fixture.pending_result.duplicate(true)
	result.campaign.transition.origin.source.checkpoint_hash = "e".repeat(64)
	_check(not Protocol.result_valid(result,fixture.continue_body,anchor,owner,definition),"Pending handoff must retain the exact completed source hash")
	result = fixture.pending_result.duplicate(true)
	result.campaign.transition.target_room_id = "X".repeat(22)
	_check(not Protocol.result_valid(result,fixture.continue_body,anchor,owner,definition),"Provisional child IDs are not part of public control")
	var equal_revision: Dictionary = fixture.pending_result.campaign.duplicate(true)
	equal_revision.transition.origin.expected_revision = equal_revision.revision
	_check(not Protocol.view_valid(equal_revision,definition,owner),"Persisting a transition must advance its control revision")
	var terminal: Dictionary = fixture.accepted_result.campaign.duplicate(true)
	terminal.state = "continuing"
	terminal.transition = {"transition_id":"e".repeat(64),"phase":"target_initialized","origin":{"expected_revision":terminal.revision,"from_index":1,"source":{"room_id":terminal.chapters[1].room_id,"revision":5,"branch":0,"checkpoint_hash":"a".repeat(64)}}}
	terminal.revision += 1
	_check(not Protocol.view_valid(terminal,definition,owner),"Terminal Finish cannot report an initialized successor phase")

func _maximum_history() -> void:
	var longest := definition.duplicate(true)
	longest.chapters = []
	for index in range(8): longest.chapters.append(definition.chapters[index%2].duplicate(true))
	_rehash(longest)
	var view: Dictionary = fixture.active_view.duplicate(true)
	view.campaign_key = Protocol.key(longest)
	view.revision = 17
	view.current_index = 7
	view.chapters = []
	for index in range(8):
		view.chapters.append({"chapter":longest.chapters[index].duplicate(true),"room_id":anchor if index == 0 else ("fixture-child-%d"%index).sha256_text().substr(0,22),"completion":_completion(index) if index < 7 else null})
	_check(Protocol.view_valid(view,longest,owner),"Maximum eight-room history remains small with independent completion references")
	view.state = "complete"
	view.chapters[7].completion = _completion(7)
	_check(Protocol.view_valid(view,longest,owner),"The last completed chapter ends the finite campaign")
	view.state = "deleting"
	_check(Protocol.view_valid(view,longest,owner),"Deleting a completed campaign retains its terminal prefix for recovery")
	var last: Dictionary = view.chapters[7]
	var request_origin := {"expected_revision":15,"from_index":7,"source":{"room_id":last.room_id,"revision":5,"branch":0,"checkpoint_hash":last.completion.checkpoint_hash}}
	var body := Protocol.continue_body(anchor,owner,longest,request_origin)
	var receipt := {"schema_version":1,"operation":"campaign_continue","campaign_room_id":anchor,"campaign_key":Protocol.key(longest),"player_id":owner,"idempotency_key":body.idempotency_key,"request_hash":Protocol.request_hash(anchor,owner,body),"transition_id":last.completion.transition_id,"origin":request_origin,"accepted_revision":16,"outcome":"finished","next_index":null,"next_room_id":null}
	var result := {"schema_version":1,"operation":"campaign_continue","status":"accepted","receipt":receipt,"campaign":view}
	_check(Protocol.result_valid(result,body,anchor,owner,longest),"Terminal Finish receipt accepts no extra child even during later deletion")
	result.receipt.next_room_id = "X".repeat(22)
	_check(not Protocol.result_valid(result,body,anchor,owner,longest),"Terminal Finish cannot manufacture a ninth room")
	# A lost earlier response can be reconciled after the partner finishes.
	var older: Dictionary = fixture.accepted_result.duplicate(true)
	older.campaign.state = "complete"
	older.campaign.revision = 10
	older.campaign.chapters[1].completion = {"source_revision":9,"source_branch":0,"checkpoint_hash":"9".repeat(64),"transition_id":"8".repeat(64),"from_campaign_revision":8,"accepted_campaign_revision":9}
	_check(Protocol.result_valid(older,fixture.continue_body,anchor,owner,definition),"An old exact receipt still reconciles against a newer completed control view")
	longest.chapters.append(definition.chapters[0].duplicate(true))
	_rehash(longest)
	_check(not Protocol.definition_valid(longest),"Authored campaigns cannot silently expand beyond eight rooms")

func _completion(index: int) -> Dictionary:
	return {"source_revision":5,"source_branch":0,"checkpoint_hash":("checkpoint-%d"%index).sha256_text(),"transition_id":("transition-%d"%index).sha256_text(),"from_campaign_revision":index*2+1,"accepted_campaign_revision":index*2+2}

func _rehash(value: Dictionary) -> void:
	value.erase("definition_hash")
	var digest := Canonical.digest(value)
	value["definition_hash"] = digest

func _bounds() -> void:
	var deep: Dictionary = {}
	for index in range(14): deep = {"child":deep}
	_check(not Protocol.bounded(deep),"Excessively deep control is held before recursive canonicalization")
	var wide: Array = []
	wide.resize(3000)
	_check(not Protocol.bounded(wide),"Node count is bounded independently from JSON bytes")
	_check(not Protocol.bounded({"text":"界".repeat(6000)}),"Control byte budget counts UTF-8, not characters")
	_check(not Protocol.bounded({"revision":INF}) and not Protocol.bounded({"revision":NAN}),"Non-finite numeric control cannot pass JSON validation")
	_check(not Protocol.bounded({"revision":9007199254740992}),"Numbers beyond the shared safe-integer range cannot bind revisions")
	_check(not Protocol.bounded({"revision":1.5}),"Fractional control counters are rejected")

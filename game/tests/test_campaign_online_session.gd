extends SceneTree
const Owner = preload("res://services/campaign_online_session.gd")
const Online = preload("res://services/relay_online_session.gd")
const Protocol = preload("res://services/campaign_protocol.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Boundaries = preload("res://tests/test_campaign_room_bridge.gd")
const Disk = preload("res://services/relay_online_store.gd")
const Cleanup = preload("res://services/deleted_identity_cache_cleanup.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const OTHER := "ZZZZZZZZZZZZZZZZZZZZZZ"
var fixture: Dictionary
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	fixture = _json("res://tests/fixtures/campaign/control-v2.json")
	await _pending_restart()
	await _adoption_restart_and_release()
	await _activation_restart_hold()
	await _explicit_activation_proxy()
	await _retained_control1_hold()
	await _bind_failure_holds()
	await _strict_saved_lobby()
	await _history_bound()
	await _ordinary_pending()
	await _identity_and_owner_gates()
	await _confirmed_cleanup()
	print("Campaign owner adapter: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _setup(complete: bool = false) -> Dictionary:
	var h := Boundaries.Harness.new()
	root.add_child(h)
	h.view = fixture.active_view.duplicate(true)
	var anchor: String = h.view.campaign_room_id
	var target: String = fixture.accepted_result.campaign.chapters[1].room_id
	h.rooms[anchor] = _room("high-and-low",anchor,complete)
	h.rooms[target] = _room("rolling-home",target,false)
	h.store.saved["photos:sentinel"] = {"bytes":"unchanged private rehearsal photo"}
	var online := Online.new(h,h.identity,h.store)
	_check(await online.open_room(anchor), "Existing source room is native-verified")
	online.capabilities = {"mutations_enabled":true}
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	var calls: int = h.calls.size()
	_check(owner.restore_owner() and h.calls.size() == calls, "Owner restore is a local lobby read")
	_check(owner.bind_campaign(anchor,Protocol.key(fixture.definition)), "Campaign pointer is saved before journal binding")
	_check(h.store.saved[_lobby()].bound_campaign.campaign_room_id == anchor, "Bound campaign is durable before its first control request")
	_check(await owner.refresh() and await owner.select_current() and owner.adopt_selected(), "Current campaign room is selected and adopted through the bridge")
	return {"h":h,"online":online,"owner":owner,"anchor":anchor,"target":target}

func _pending_restart() -> void:
	var c := await _setup(true)
	_check(not await c.owner.continue_current() and not c.owner.pending().is_empty(), "Lost Continue response leaves an exact durable control intent")
	var pending: Dictionary = c.owner.pending()
	var journal: Dictionary = c.h.store.saved[_journal(c.anchor)].duplicate(true)
	var room: Dictionary = c.h.store.saved[_room_scope(c.anchor)].duplicate(true)
	var calls: int = c.h.calls.size()
	var online := Online.new(c.h,c.h.identity,c.h.store)
	var owner := Owner.new(online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
	_check(owner.restore_owner() and Canonical.same(owner.pending(),pending), "Restart restores the bound anchor and exact pending Continue before navigation")
	_check(not owner.can_leave() and not owner.release_for_ordinary(), "Pending Continue blocks ordinary, legacy and notification departure through the common gate")
	_check(not owner.bind_campaign(OTHER,Protocol.key(fixture.definition)), "Pending Continue blocks choosing another campaign")
	_check(c.h.calls.size() == calls, "Navigation guards never lookup, retry or resubmit the saved Continue")
	_check(Canonical.same(c.h.store.saved[_journal(c.anchor)],journal) and Canonical.same(c.h.store.saved[_room_scope(c.anchor)],room), "Blocked navigation preserves control body/key and room proof")
	_check(c.h.store.saved[_lobby()].bound_campaign.campaign_room_id == c.anchor, "Failed replacement retains durable ownership")
	c.h.free()

func _adoption_restart_and_release() -> void:
	var c := await _setup()
	var old: RefCounted = c.online.coordinator
	c.h.view = fixture.accepted_result.campaign.duplicate(true)
	_check(await c.owner.refresh(), "Partner-published next chapter is accepted")
	var calls: int = c.h.calls.size()
	_check(not c.owner.can_leave() and not c.owner.bind_campaign(OTHER,Protocol.key(fixture.definition)), "Published but unselected next chapter blocks replacement")
	_check(c.h.calls.size() == calls, "Publication recovery guard performs no implicit GET")
	_check(await c.owner.select_current() and c.owner.selected_room() == c.target, "Next room selection is durably saved without adopting")
	c.h.store.fail_scope = "relay-lobby-v2:"+HOST
	_check(not c.owner.adopt_selected() and c.online.coordinator == old, "Local room-pointer failure retains source presentation")
	c.h.store.fail_scope = ""
	var online := Online.new(c.h,c.h.identity,c.h.store)
	var owner := Owner.new(online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
	calls = c.h.calls.size()
	_check(owner.restore_owner() and not owner.can_leave() and not owner.release_for_ordinary(), "Restart recognizes selected-but-unadopted room as recovery")
	_check(c.h.calls.size() == calls, "Cold adoption hold does not fetch automatically")
	_check(await owner.reopen_selected() and online.last_room() == c.target, "Explicit recovery adopts selected target with GET only")
	_check(_only_gets(c.h.calls), "No recovery request sends Continue")
	c.h.device_token = ""
	calls = c.h.calls.size()
	_check(owner.can_leave(), "Already adopted campaign may deliberately leave while offline")
	c.h.store.fail_scope = _lobby()
	var bound: Dictionary = owner.bound_campaign()
	_check(not owner.release_for_ordinary() and Canonical.same(owner.bound_campaign(),bound), "Failed release save preserves the bound session")
	c.h.store.fail_scope = ""
	var journal: Dictionary = c.h.store.saved[_journal(c.anchor)].duplicate(true)
	_check(owner.release_for_ordinary() and owner.bound_campaign().is_empty(), "Explicit successful release durably clears only the bound reference")
	_check(c.h.store.saved[_lobby()].campaigns.size() == 1 and Canonical.same(c.h.store.saved[_journal(c.anchor)],journal), "Ordinary departure preserves campaign history and journal")
	_check(c.h.calls.size() == calls, "Release and offline leave checks perform no network operation")
	var again := Owner.new(online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
	_check(again.restore_owner() and again.bound_campaign().is_empty() and again.can_leave(), "Restart distinguishes deliberate ordinary departure from adoption failure")
	c.h.free()

func _bind_failure_holds() -> void:
	var c := await _setup()
	var before: Dictionary = c.h.store.saved.duplicate(true)
	c.h.store.fail_scope = _lobby()
	_check(not c.owner.bind_campaign(OTHER,Protocol.key(fixture.definition)), "New-anchor pointer write can fail safely")
	_check(Canonical.same(c.h.store.saved,before) and c.owner.bound_campaign().campaign_room_id == c.anchor, "Failed pointer write leaves old room/photo/control scopes exact")
	c.h.store.fail_scope = ""
	c.h.store.fail_read = _journal(OTHER)
	_check(not c.owner.bind_campaign(OTHER,Protocol.key(fixture.definition)) and c.owner.read_only, "Unreadable new-anchor cache becomes a recovery hold")
	_check(c.h.store.saved[_lobby()].bound_campaign.campaign_room_id == OTHER and c.online.last_room() == c.anchor, "Successful pointer save remains durable when the new journal cannot load")
	var owner := Owner.new(c.online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
	var calls: int = c.h.calls.size()
	_check(not owner.restore_owner() and owner.read_only and not owner.release_for_ordinary(), "Restart does not bypass an unreadable bound journal")
	_check(c.h.calls.size() == calls and c.h.store.saved[_lobby()].bound_campaign.campaign_room_id == OTHER, "Bound-journal failure does not clear or rewrite the pointer")
	c.h.store.fail_read = ""
	_check(owner.restore_owner(true) and owner.bound_campaign().campaign_room_id == OTHER, "Explicit local retry can recover a temporarily unreadable journal")
	c.h.free()

func _activation_restart_hold() -> void:
	var c := await _setup()
	# Restore a strictly valid persisted control2 debt with matching selected
	# and ordinary room pointers. Pointer equality must not authorize departure.
	var publication: Dictionary = fixture.accepted_result.campaign.duplicate(true)
	publication.activation = {"transition_id":fixture.accepted_result.receipt.transition_id}
	var saved: Dictionary = c.h.store.saved[_journal(c.anchor)].duplicate(true)
	saved.view = publication.duplicate(true)
	saved.selected_room = c.target
	c.h.store.saved[_journal(c.anchor)] = saved
	_check(await c.online.open_room(c.target), "Activation fixture has a separately verified current room cache")
	var owner := Owner.new(c.online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
	_check(owner.restore_owner() and owner.selected_room() == c.online.last_room() and owner.view().chapters[1].room_id == c.target, "Cold control2 debt may coexist with matching selected/current/ordinary pointers")
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var calls: int = c.h.calls.size()
	_check(not owner.can_leave() and owner.last_code == "campaign_activation_pending", "Activation debt explicitly holds navigation despite matching pointers")
	_check(not owner.release_for_ordinary() and not owner.bind_campaign(OTHER,Protocol.key(fixture.definition)), "Ordinary departure and another campaign cannot clear activation debt")
	_check(owner.bind_campaign(c.anchor,Protocol.key(fixture.definition)) and owner.view().activation != null, "Idempotent bind of the same anchor cannot reset or infer activation")
	_check(not await owner.select_current() and not owner.adopt_selected() and not await owner.reopen_selected(), "Selection/adoption paths cannot bypass activation")
	_check(not await owner.continue_current() and not owner.mark_story_seen(0,"completion"), "Later Continue and completion acknowledgement wait for activation")
	_check(c.h.calls.size() == calls and Canonical.same(c.h.store.saved,before), "All activation holds preserve exact journals and perform no implicit request")
	c.h.view = publication.duplicate(true)
	_check(await owner.refresh() and not owner.can_leave(), "Read-only observation of unchanged activation retains the debt")
	c.h.view.activation = null
	c.h.view.revision += 1
	_check(await owner.refresh() and owner.can_leave(), "Only a validated later debt-free publication restores leave readiness")
	_check(owner.release_for_ordinary() and owner.bound_campaign().is_empty(), "Explicit release succeeds after activation is observed discharged")
	_check(_only_gets(c.h.calls), "Owner2 never invents or automatically sends an activation mutation")
	c.h.free()

func _retained_control1_hold() -> void:
	var c := await _setup()
	var legacy := _json("res://tests/fixtures/campaign/control-v1.json")
	c.h.store.saved[_journal(c.anchor)].view = legacy.active_view.duplicate(true)
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var calls: int = c.h.calls.size()
	var owner := Owner.new(c.online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
	_check(not owner.restore_owner() and owner.read_only, "Retained control1 owner journal is a read-only hold under control2")
	_check(not owner.can_leave() and not owner.release_for_ordinary() and not owner.bind_campaign(OTHER,Protocol.key(fixture.definition)), "Unsupported old control cannot release its durable bound anchor")
	_check(Canonical.same(c.h.store.saved,before) and c.h.calls.size() == calls, "Control1 bytes are preserved without inferring activation=null")
	c.h.free()

func _explicit_activation_proxy() -> void:
	var c := await _setup()
	c.h.view = fixture.accepted_result.campaign.duplicate(true)
	c.h.view.activation = {"transition_id":fixture.accepted_result.receipt.transition_id}
	_check(await c.owner.refresh() and not c.owner.can_leave(), "Owner observes activation while normal departure is held")
	var pending: Dictionary = c.h.store.saved.duplicate(true)
	var calls: int = c.h.calls.size()
	var old: RefCounted = c.online.coordinator
	# The retained transport deliberately returns an uncertain result for POST.
	# This composition check proves the explicit recovery dispatch is available
	# through the owner despite its normal adoption hold, without data loss.
	_check(not await c.owner.resume_activation(), "Uncertain explicit activation recovery remains recoverable")
	_check(c.h.calls.size() == calls+1 and c.h.calls[-1].method == HTTPClient.METHOD_POST and c.h.calls[-1].path.ends_with("/resume"), "Resume bypasses only the activation hold and dispatches one dedicated request")
	_check(Protocol.resume_activation_valid(c.h.calls[-1].body,fixture.definition), "Owner forwards the exact bounded native Resume body")
	_check(c.online.coordinator == old and Canonical.same(pending,c.h.store.saved) and not c.owner.can_leave(), "Unknown recovery preserves the source, ownership and activation debt")
	c.h.free()

func _strict_saved_lobby() -> void:
	for mode: String in ["future","wrong_owner","pending","unknown_manifest","duplicate","unknown_field","corrupt_journal"]:
		var c := await _setup()
		var changed: Dictionary = c.h.store.saved[_lobby()].duplicate(true)
		match mode:
			"future": changed.schema_version = 4
			"wrong_owner": changed.owner_player_id = GUEST
			"pending": changed.pending = {"operation":"future_join","key":"retain"}
			"unknown_manifest":
				changed.bound_campaign.campaign_key.definition_hash = "f".repeat(64)
				changed.campaigns[0] = changed.bound_campaign.duplicate(true)
			"duplicate": changed.campaigns.append(changed.campaigns[0].duplicate(true))
			"unknown_field": changed.extra = true
			"corrupt_journal": c.h.store.saved[_journal(c.anchor)] = {"schema_version":99,"retain":"future journal"}
		c.h.store.saved[_lobby()] = changed.duplicate(true)
		var before: Dictionary = c.h.store.saved.duplicate(true)
		var owner := Owner.new(c.online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
		var calls: int = c.h.calls.size()
		_check(not owner.restore_owner() and owner.read_only and not owner.can_leave(), "Saved "+mode+" state fails closed")
		_check(not owner.bind_campaign(OTHER,Protocol.key(fixture.definition)) and not owner.release_for_ordinary(), "Saved "+mode+" cannot be bypassed by another destination")
		_check(Canonical.same(c.h.store.saved,before) and c.h.calls.size() == calls, "Saved "+mode+" bytes are preserved without network requests")
		c.h.free()

func _identity_and_owner_gates() -> void:
	var c := await _setup()
	c.h.leave_allowed = false
	_check(not c.owner.can_leave() and not c.owner.release_for_ordinary(), "Unsaved child/photo work blocks owner departure")
	c.h.leave_allowed = true
	var empty_guard := Owner.new(c.online,c.h.identity,[fixture.definition],Callable(),c.h.store)
	_check(empty_guard.restore_owner() and not empty_guard.can_leave(), "Missing owner predicate cannot authorize departure")
	var before: Dictionary = c.h.store.saved[_journal(c.anchor)].duplicate(true)
	c.h.on_request = func() -> void: c.h.identity_value.epoch += 1
	_check(not await c.owner.refresh() and c.owner.get("_campaign") == null, "Identity change during refresh cannot publish stale campaign state")
	_check(Canonical.same(c.h.store.saved[_journal(c.anchor)],before), "Late foreign-epoch response does not rewrite the original journal")
	c.h.on_request = Callable()
	c.h.free()
	c = await _setup()
	var generations: Array = []
	c.h.on_request = func() -> void:
		c.h.identity_value.epoch += 1
		c.owner.invalidate_identity()
		_check(c.owner.restore_owner(), "New owner epoch may restore its saved campaign while an old request drains")
		generations.append(c.owner.get("_generation"))
	_check(not await c.owner.refresh(), "Superseded refresh result is discarded")
	_check(generations.size() == 1 and c.owner.get("_generation") == generations[0] and not c.owner.view().is_empty(), "Late old response cannot invalidate newly restored owner state")
	c.h.on_request = Callable()
	c.h.free()
	for operation: String in ["release","bind"]:
		c = await _setup()
		c.h.store.on_save = func(scope: String) -> void:
			if scope == _lobby(): c.h.identity_value.player_id = GUEST
		var okay: bool = c.owner.release_for_ordinary() if operation == "release" else c.owner.bind_campaign(OTHER,Protocol.key(fixture.definition))
		_check(not okay and c.owner.get("_campaign") == null, "Synchronous identity flip during "+operation+" invalidates old in-memory owner")
		_check(not c.h.store.saved.has("relay-campaign-lobby-v1:"+GUEST), "Synchronous "+operation+" save never writes another owner's scope")
		c.h.store.on_save = Callable()
		c.h.free()

func _history_bound() -> void:
	var c := await _setup()
	var value: Dictionary = c.h.store.saved[_lobby()].duplicate(true)
	for index in range(127):
		value.campaigns.append({"campaign_room_id":"A%021d" % index,"campaign_key":Protocol.key(fixture.definition)})
	c.h.store.saved[_lobby()] = value.duplicate(true)
	var owner := Owner.new(c.online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
	_check(owner.restore_owner() and owner.campaign_references().size() == 128, "Bounded local historical references load at the exact limit")
	_check(not owner.bind_campaign(OTHER,Protocol.key(fixture.definition)) and Canonical.same(c.h.store.saved[_lobby()],value), "Full local history holds a new reference without truncating prior entries")
	value.campaigns.append({"campaign_room_id":OTHER,"campaign_key":Protocol.key(fixture.definition)})
	c.h.store.saved[_lobby()] = value.duplicate(true)
	_check(not owner.restore_owner(true) and owner.read_only and Canonical.same(c.h.store.saved[_lobby()],value), "Oversized history is preserved as an unsupported save")
	c.h.free()

func _ordinary_pending() -> void:
	var c := await _setup()
	var record := _json("res://tests/fixtures/cooperative/upper-path-a.json")
	_check(not await c.online.coordinator.commit(record) and not c.online.coordinator.pending().is_empty(), "Lost source turn leaves a genuine durable gameplay request")
	var room: Dictionary = c.h.store.saved[_room_scope(c.anchor)].duplicate(true)
	var calls: int = c.h.calls.size()
	var online := Online.new(c.h,c.h.identity,c.h.store)
	var owner := Owner.new(online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
	_check(owner.restore_owner() and not owner.can_leave() and not owner.release_for_ordinary(), "Restored ordinary room pending also blocks campaign departure")
	_check(not owner.bind_campaign(OTHER,Protocol.key(fixture.definition)), "Room pending cannot be bypassed through another campaign")
	_check(c.h.calls.size() == calls and Canonical.same(c.h.store.saved[_room_scope(c.anchor)],room), "Room guard preserves pending proof without implicit reconciliation")
	c.h.free()

func _confirmed_cleanup() -> void:
	var c := await _setup()
	var directory := "user://campaign-owner-cleanup-"+Crypto.new().generate_random_bytes(8).hex_encode()
	var disk := Disk.new(directory+"/relay")
	for scope: String in [_lobby(),_journal(c.anchor),_room_scope(c.anchor)]:
		_check(disk.save_scope(scope,c.h.store.saved[scope]).ok, "Owned cleanup fixture is a real LocalSave envelope")
	var foreign := "relay-campaign-lobby-v1:"+GUEST
	_check(disk.save_scope(foreign,{"owner_player_id":GUEST,"retain":true}).ok, "Foreign owner cleanup fixture is separate")
	var foreign_path := directory+"/relay/"+foreign.sha256_text()+".json"
	var bytes := FileAccess.get_file_as_bytes(foreign_path)
	var cleanup := Cleanup.new()
	cleanup.relay_directory = directory+"/relay"
	cleanup.shared_directory = directory+"/shared"
	cleanup.safety_directory = directory+"/safety"
	_check(cleanup.erase_owner(HOST).ok, "Confirmed deletion removes the owner's campaign lobby and journal")
	_check(not FileAccess.file_exists(directory+"/relay/"+_lobby().sha256_text()+".json") and not FileAccess.file_exists(directory+"/relay/"+_journal(c.anchor).sha256_text()+".json"), "Confirmed cleanup includes both campaign scope kinds")
	_check(FileAccess.get_file_as_bytes(foreign_path) == bytes, "Confirmed cleanup preserves another owner's exact bytes")
	_check(cleanup.erase_owner(GUEST).ok, "Test cleanup removes only the remaining synthetic owner")
	for suffix: String in ["relay","shared","safety",""]:
		var path := directory.path_join(suffix) if suffix != "" else directory
		if DirAccess.dir_exists_absolute(path): DirAccess.remove_absolute(path)
	c.h.free()

func _room(chapter: String, room_id: String, complete: bool) -> Dictionary:
	var level := Registry.definition(chapter+"@1")
	return {"schema_version":2,"api_version":2,"simulation_version":6,"room_id":room_id,"revision":5 if complete else 1,"branch":0,
		"stage_index":2 if complete else 0,"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),
		"host_id":HOST,"guest_id":GUEST,"checkpoint":_json("res://tests/fixtures/cooperative/"+chapter+("-final-checkpoint" if complete else "-initial-checkpoint")+".json"),
		"a_turn_id":null,"completed_pair_ids":["p0-0","p0-1"] if complete else [],"invite_code":"AB".repeat(10),"invite_expires_at":"2026-10-04T13:00:00.000Z",
		"created_at":"2026-09-27T12:00:00Z","updated_at":"2026-09-27T12:00:00Z","active_role":"complete" if complete else "a","first_player_id":null if complete else HOST,
		"active_player_id":null if complete else HOST,"player_slot":"p0","stage_id":"" if complete else level.stages[0].id,"recording_a":null,"validation":"structural_client_replay_required"}

func _lobby() -> String: return "relay-campaign-lobby-v1:"+HOST
func _journal(anchor: String) -> String: return "relay-campaign-v1:"+HOST+":"+anchor
func _room_scope(room: String) -> String: return "relay-room-v2:"+HOST+":"+room
func _json(path: String) -> Dictionary: return JSON.parse_string(FileAccess.get_file_as_string(path))
func _only_gets(calls: Array) -> bool:
	for call: Dictionary in calls:
		if call.method != HTTPClient.METHOD_GET: return false
	return true
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

extends SceneTree
const Online = preload("res://services/relay_online_session.gd")
const Campaign = preload("res://services/campaign_session.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const SOURCE := "SSSSSSSSSSSSSSSSSSSSSS"
var fixture: Dictionary
var checks := 0
var failures := 0

class MemoryStore:
	extends RefCounted
	var saved: Dictionary = {}
	var writes: Array = []
	var fail_scope := ""
	var fail_read := ""
	var on_save: Callable
	func load_scope(scope: String) -> Dictionary:
		return {"ok":scope != fail_read,"found":saved.has(scope),"value":saved.get(scope,{}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		if scope == fail_scope: return {"ok":false}
		writes.append(scope)
		saved[scope] = JSON.parse_string(JSON.stringify(value))
		if on_save.is_valid(): on_save.call(scope)
		return {"ok":true}

class Harness:
	extends Node
	signal release
	var player_id := HOST
	var device_token := "synthetic-device-token"
	var base_url := "https://synthetic.invalid"
	var busy := false
	var identity_value := {"ready":true,"player_id":HOST,"epoch":1}
	var store := MemoryStore.new()
	var rooms: Dictionary = {}
	var view: Dictionary = {}
	var calls: Array = []
	var campaign_calls: Array = []
	var leave_allowed := true
	var hold := false
	var on_request: Callable
	func identity() -> Dictionary: return identity_value.duplicate(true)
	func leave_ready() -> bool: return leave_allowed
	func request_campaign_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		campaign_calls.append({"method":method,"path":path,"body":body.duplicate(true)})
		return await request_json(method,path,body)
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		busy = true
		calls.append({"method":method,"path":path,"body":body.duplicate(true)})
		if on_request.is_valid(): on_request.call()
		if hold: await release
		else: await get_tree().process_frame
		busy = false
		if method != HTTPClient.METHOD_GET: return {"ok":false,"status":0,"code":"connection_interrupted"}
		if path.begins_with("/v2/campaigns/"): return {"ok":true,"status":200,"data":{"campaign":view.duplicate(true)}}
		var room := path.get_slice("/",3)
		return {"ok":true,"status":200,"data":rooms[room].duplicate(true)} if rooms.has(room) else {"ok":false,"status":404}

static func campaign_capabilities(definition: Dictionary) -> Dictionary:
	return {"api_version":2,"simulation_version":2,"recording_version":2,"mutations_enabled":true,"validation":"structural_client_replay_required","chapters":[],
		"campaign_control_version":2,"campaign_creation_enabled":true,"campaign_mutations_enabled":true,"campaign_definitions":[definition.duplicate(true)]}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	fixture = _json("res://tests/fixtures/campaign/control-v2.json")
	await _isolated_selection()
	await _durable_retry()
	await _target_pending()
	await _holds_and_mismatches()
	await _await_guards()
	await _save_identity_guard()
	await _activation_hold()
	print("Campaign room bridge: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _setup(activation: bool = false) -> Dictionary:
	var h := Harness.new()
	root.add_child(h)
	h.view = fixture.accepted_result.campaign.duplicate(true)
	if activation: h.view.activation = {"transition_id":fixture.accepted_result.receipt.transition_id}
	var target: String = h.view.chapters[1].room_id
	h.rooms[SOURCE] = _room("high-and-low",SOURCE)
	h.rooms[target] = _room("rolling-home",target)
	h.store.saved["photos:sentinel"] = {"immutable":"draft photo bytes","state":"not uploaded"}
	var online := Online.new(h,h.identity,h.store)
	online.capabilities = {"mutations_enabled":true}
	_check(await online.open_room(SOURCE), "Ordinary source opens through existing API")
	# _ready initializes its owner and clears stale capabilities on first use.
	online.capabilities = {"mutations_enabled":true}
	var bridge: RefCounted = online.campaign_room_bridge(fixture.definition,h.leave_ready)
	var campaign := Campaign.new(online.transport,h.store.load_scope,h.store.save_scope,h.identity,bridge.validate_target,bridge.selection_ready)
	_check(campaign.bind(h.view.campaign_room_id,fixture.definition) and bridge.bind_campaign(campaign), "Bridge and durable campaign bind without a reference cycle")
	_check(await campaign.refresh(), "Published target is a strictly validated campaign view")
	return {"h":h,"online":online,"bridge":bridge,"campaign":campaign,"target":target}

func _activation_hold() -> void:
	var c := await _setup(true)
	var source: RefCounted = c.online.coordinator
	var count: int = c.h.calls.size()
	var checked: Dictionary = await c.bridge.validate_target(c.target,fixture.definition.chapters[1],HOST,1)
	_check(not checked.ok and c.h.calls.size() == count,"Direct bridge probe cannot bypass published activation debt")
	_check(not await c.campaign.select_current() and not await c.bridge.reopen_selected() and not c.bridge.adopt_selected(),"Activation debt holds selection, reopen and adoption")
	_check(c.online.coordinator == source and c.online.last_room() == SOURCE and c.h.calls.size() == count,"Activation hold preserves visible source and sends no target request")
	c.h.free()

func _isolated_selection() -> void:
	var c := await _setup()
	var source: RefCounted = c.online.coordinator
	var live: RefCounted = source.create_live_simulation()
	live.step({"move_x":1.0})
	_check(source.save_live_draft(live), "Source has a real saved rehearsal")
	var before: Dictionary = c.h.store.saved.duplicate(true)
	_check(await c.campaign.select_current(), "Target probe allows durable campaign selection")
	_check(c.online.coordinator == source and c.online.last_room() == SOURCE, "Probe leaves the visible coordinator and last-room pointer untouched")
	_check(Canonical.same(c.h.store.saved[_scope(SOURCE)],before[_scope(SOURCE)]) and Canonical.same(c.h.store.saved["photos:sentinel"],before["photos:sentinel"]), "Probe preserves source draft and photo bytes")
	_check(c.bridge.adopt_selected(), "Adoption succeeds after campaign selection is saved")
	_check(c.online.coordinator != source and c.online.coordinator.snapshot().room_id == c.target and c.online.last_room() == c.target, "Only adoption replaces the room and durable pointer")
	_check(c.online.room_ids() == [SOURCE], "Campaign child is not inserted into ordinary lobby rows")
	_check(Canonical.same(c.h.store.saved[_scope(SOURCE)],before[_scope(SOURCE)]) and source.draft().duration_ticks == 1, "Adoption retains previous saved draft for later return")
	_check(not c.bridge.adopt_selected(), "A consumed candidate cannot be adopted twice")
	_check(_only_gets(c.h.calls), "Selection and adoption do not submit gameplay or Continue")
	c.h.free()

func _durable_retry() -> void:
	var c := await _setup()
	var source: RefCounted = c.online.coordinator
	c.h.store.fail_scope = "relay-campaign-v1:"+HOST+":"+c.h.view.campaign_room_id
	_check(not await c.campaign.select_current() and c.campaign.selected_room().is_empty(), "Campaign save failure leaves selection absent")
	_check(not c.bridge.adopt_selected() and c.online.coordinator == source, "Verified target cannot bypass a failed campaign save")
	c.h.store.fail_scope = ""
	_check(await c.campaign.select_current(), "Selection can retry after campaign storage recovers")
	c.h.store.fail_scope = "relay-lobby-v2:"+HOST
	_check(not c.bridge.adopt_selected() and c.online.coordinator == source and c.online.last_room() == SOURCE, "Failed last-room save preserves current coordinator and pointer")
	_check(c.campaign.selected_room() == c.target and c.campaign.pending().is_empty(), "Accepted selection remains durable after local adoption failure")
	c.h.store.fail_scope = ""
	var restarted := Online.new(c.h,c.h.identity,c.h.store)
	var bridge: RefCounted = restarted.campaign_room_bridge(fixture.definition,c.h.leave_ready)
	var campaign := Campaign.new(restarted.transport,c.h.store.load_scope,c.h.store.save_scope,c.h.identity,bridge.validate_target,bridge.selection_ready)
	_check(campaign.bind(c.h.view.campaign_room_id,fixture.definition) and bridge.bind_campaign(campaign), "Restart restores accepted selection independently of old bridge")
	_check(await bridge.reopen_selected() and restarted.last_room() == c.target, "Restart repairs local adoption using target GET and native verification")
	_check(_only_gets(c.h.calls), "Restart recovery sends no second Continue or gameplay request")
	c.h.free()

func _target_pending() -> void:
	var c := await _setup()
	var target := Coordinator.new(c.online.transport,c.h.store.load_scope,c.h.store.save_scope,c.h.identity)
	_check(target.bind_room(c.target) and await target.refresh(), "Target has a native verified cache")
	var record := _json("res://tests/fixtures/cooperative/weight-of-a-friend-a.json")
	_check(target.save_draft(record), "Target has an accepted native rehearsal")
	_check(not await target.commit(record) and not target.pending().is_empty(), "Lost target commit leaves a durable pending operation")
	var pending: Dictionary = target.pending()
	var draft: Dictionary = target.draft()
	var before: Dictionary = c.h.store.saved[_scope(c.target)].duplicate(true)
	var posts_before: int = c.h.calls.size()
	_check(await c.campaign.select_current() and c.bridge.adopt_selected(), "Target pending turn is adopted into existing recovery UI")
	_check(Canonical.same(c.online.coordinator.pending(),pending) and Canonical.same(c.online.coordinator.draft(),draft), "Target pending key and draft are unchanged")
	_check(Canonical.same(c.h.store.saved[_scope(c.target)],before), "Identical target refresh leaves durable recovery bytes intact")
	_check(_only_gets(c.h.calls.slice(posts_before)), "Probe never reconciles or resubmits target pending data")
	c.h.free()

func _holds_and_mismatches() -> void:
	var c := await _setup()
	var source: RefCounted = c.online.coordinator
	var absent: RefCounted = c.online.campaign_room_bridge(fixture.definition)
	absent.bind_campaign(c.campaign)
	_check(not absent.selection_ready(), "Missing owner leave predicate holds unsaved/photo state")
	c.h.leave_allowed = false
	var count: int = c.h.calls.size()
	_check(not await c.campaign.select_current() and c.h.calls.size() == count, "Owner unsaved/photo guard blocks before any target request")
	c.h.leave_allowed = true
	source.read_only = true
	_check(not c.bridge.selection_ready(), "Source read-only cache blocks selection")
	source.read_only = false
	c.h.busy = true
	_check(not c.bridge.selection_ready(), "An active shared API/photo transfer blocks selection")
	c.h.busy = false
	var corrupt := {"schema_version":999,"preserve":"future target cache"}
	c.h.store.saved[_scope(c.target)] = corrupt.duplicate(true)
	var writes: int = c.h.store.writes.size()
	_check(not await c.campaign.select_current() and c.h.calls.size() == count and c.h.store.writes.size() == writes, "Unknown target cache holds without request or write")
	_check(Canonical.same(c.h.store.saved[_scope(c.target)],corrupt) and c.online.coordinator == source, "Unknown target bytes and current room are preserved")
	c.h.store.saved.erase(_scope(c.target))
	c.h.store.fail_read = _scope(c.target)
	_check(not await c.campaign.select_current() and c.h.calls.size() == count, "Unreadable target cache holds before GET")
	c.h.store.fail_read = ""
	var legitimate: Dictionary = c.h.rooms[c.target].duplicate(true)
	c.h.rooms[c.target].guest_id = "X".repeat(22)
	_check(not await c.campaign.select_current() and c.online.coordinator == source, "Native room with different campaign partner is not adoptable")
	c.h.rooms[c.target] = legitimate.duplicate(true)
	# A mismatched native cache is retained by its ordinary coordinator. A fresh
	# case avoids pretending a target chapter/person can be rewritten in place.
	c.h.store.saved.erase(_scope(c.target))
	c.h.rooms[c.target].checkpoint.players.p0.x += 8
	var cp: Dictionary = c.h.rooms[c.target].checkpoint.duplicate(true)
	cp.erase("checkpoint_hash")
	c.h.rooms[c.target].checkpoint.checkpoint_hash = Canonical.digest(cp)
	_check(not await c.campaign.select_current(), "Rehashed forged target checkpoint still fails native admission")
	c.h.rooms[c.target] = legitimate
	_check(await c.campaign.select_current(), "Valid target can be verified after failed probes")
	c.h.leave_allowed = false
	_check(not c.bridge.adopt_selected() and c.online.coordinator == source, "Photo/unsaved guard is checked again immediately before adoption")
	c.h.leave_allowed = true
	c.h.view.revision += 1
	_check(await c.campaign.refresh() and not c.bridge.adopt_selected(), "Changed publication invalidates a previously verified candidate")
	_check(await c.campaign.select_current(), "Current publication can be re-probed")
	_check(await c.online.open_room(SOURCE) and not c.bridge.adopt_selected(), "Ordinary same-room rebind invalidates the previous navigation lease")
	_check(await c.campaign.select_current(), "Rebound source can explicitly verify a new candidate")
	var live: RefCounted = source.create_live_simulation()
	live.step({"move_x":1.0})
	_check(source.save_live_draft(live) and not c.bridge.adopt_selected(), "Source draft change after verification prevents a stale swap")
	var record := _json("res://tests/fixtures/cooperative/upper-path-a.json")
	_check(not await source.commit(record) and not source.pending().is_empty(), "Source can acquire a genuine pending turn")
	count = c.h.calls.size()
	_check(not await c.campaign.select_current() and c.h.calls.size() == count, "Source pending blocks without implicit retry or reconciliation")
	var restarted := Online.new(c.h,c.h.identity,c.h.store)
	var restarted_bridge: RefCounted = restarted.campaign_room_bridge(fixture.definition,c.h.leave_ready)
	_check(not restarted_bridge.selection_ready() and c.h.calls.size() == count, "Cold bridge restores the existing last-room pending lock before leaving")
	c.h.free()

func _await_guards() -> void:
	for mode: String in ["identity","player","leave","readonly","pending","invalidate","publication","new_probe"]:
		var c := await _setup()
		var source: RefCounted = c.online.coordinator
		var publication: Dictionary = c.campaign.view()
		var results: Array = []
		c.h.on_request = func() -> void:
			match mode:
				"identity": c.h.identity_value.epoch += 1
				"player": c.h.identity_value.player_id = GUEST
				"leave": c.h.leave_allowed = false
				"readonly": source.read_only = true
				"pending": _source_pending(source,results)
				"invalidate": c.bridge.invalidate()
				"publication": c.campaign.invalidate_identity()
				"new_probe": _second_probe(c.bridge,publication,results)
		var checked: Dictionary = await c.bridge.validate_target(c.target,fixture.definition.chapters[1],HOST,1)
		_check(not checked.get("ok",false) and not c.bridge.adopt_selected(), "Await boundary rejects changed "+mode)
		_check(c.online.coordinator == source and c.h.store.saved["relay-lobby-v2:"+HOST].last_room == SOURCE, "Late "+mode+" response does not navigate")
		_check(_only_gets(c.h.calls), "Late "+mode+" performs no mutation request")
		if mode == "new_probe": _check(results.size() == 1 and not results[0].get("ok",false), "New probe retires the old in-flight candidate")
		if mode == "pending": _check(not source.pending().is_empty(), "Post-await hold is backed by a genuine saved source request")
		c.h.on_request = Callable()
		c.h.free()

func _second_probe(bridge: RefCounted, publication: Dictionary, result: Array) -> void:
	result.append(await bridge.validate_target(publication.chapters[1].room_id,fixture.definition.chapters[1],HOST,1))

func _source_pending(source: RefCounted, result: Array) -> void:
	result.append(await source.commit(_json("res://tests/fixtures/cooperative/upper-path-a.json")))

func _save_identity_guard() -> void:
	var c := await _setup()
	_check(await c.campaign.select_current(), "Identity-at-save case has a durably selected target")
	c.h.store.on_save = func(scope: String) -> void:
		if scope == "relay-lobby-v2:"+HOST: c.h.identity_value.epoch += 1
	_check(not c.bridge.adopt_selected() and c.online.coordinator == null, "Owner change inside pointer save cannot adopt a previous-epoch coordinator")
	_check(not c.h.store.saved.has("relay-lobby-v2:"+GUEST) and c.campaign.selected_room().is_empty(), "No foreign identity receives saved target or stale campaign access")
	c.h.store.on_save = Callable()
	c.h.free()

func _room(chapter: String, room_id: String) -> Dictionary:
	var level := Registry.definition(chapter+"@1")
	return {"schema_version":2,"api_version":2,"simulation_version":6,"room_id":room_id,"revision":1,"branch":0,
		"stage_index":0,"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),
		"host_id":HOST,"guest_id":GUEST,"checkpoint":_json("res://tests/fixtures/cooperative/"+chapter+"-initial-checkpoint.json"),
		"a_turn_id":null,"completed_pair_ids":[],"invite_code":"A1".repeat(10),"invite_expires_at":"2026-10-04T13:00:00.000Z",
		"created_at":"2026-09-27T12:00:00Z","updated_at":"2026-09-27T12:00:00Z","active_role":"a","first_player_id":HOST,
		"active_player_id":HOST,"player_slot":"p0","stage_id":level.stages[0].id,"recording_a":null,"validation":"structural_client_replay_required"}

func _scope(room_id: String) -> String: return "relay-room-v2:"+HOST+":"+room_id
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

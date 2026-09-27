extends "res://tests/test_campaign_flow.gd"
## Synthetic campaign/story, real accepted native checkpoints and actual Main swap.
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const LobbyProtocol = preload("res://services/campaign_lobby_protocol.gd")

class PresentationMain:
	extends "res://main.gd"
	var story_exits := 0
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func _sync_presence() -> void:
		# Keep test ticks/refresh deterministic; production swap itself is inherited.
		if is_instance_valid(relay_child):
			relay_child.set_process(false)
			relay_child.set_physics_process(false)
	func _turn_notification_status() -> Dictionary:
		# No native notification service is created by this isolated Main harness.
		return {"enabled":false,"registered":false,"busy":false,"message":""}
	func story_closed() -> void: story_exits += 1

func _run() -> void:
	for slot: String in ["p0","p1"]:
		await _ordered_handoff(slot,false)
		await _ordered_handoff(slot,true)
		await _second_transition(slot)
	await _skip_boundary()
	await _partial_cosmetic_failure()
	await _pointer_failure()
	await _pure_readiness()
	await _lobby_pending_arrival()
	await _target_pending()
	await _finale_and_history()
	await _changed_contexts()
	print("Campaign warm handoff: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _chapter_room(c: Dictionary, chapter: String, room_id: String, complete: bool) -> Dictionary:
	var level := Registry.definition(chapter+"@1")
	var room: Dictionary = c.h.rooms[c.anchor].duplicate(true)
	room.room_id = room_id
	room.level_id = level.id
	room.level_version = level.version
	room.definition_hash = Canonical.digest(level)
	room.simulation_version = level.simulation_version
	room.revision = 5 if complete else 1
	room.stage_index = 2 if complete else 0
	var family := "journey" if int(level.simulation_version) == 7 else "cooperative"
	room.checkpoint = _json("res://tests/fixtures/"+family+"/"+chapter+("-final-checkpoint.json" if complete else "-initial-checkpoint.json"))
	room.completed_pair_ids = ["p0-0","p0-1"] if complete else []
	room.active_role = "complete" if complete else "a"
	room.first_player_id = null if complete else HOST
	room.active_player_id = null if complete else HOST
	room.stage_id = "" if complete else level.stages[0].id
	return room

func _warm_setup(slot: String = "p0", target_complete: bool = false, definition_override: Dictionary = {}) -> Dictionary:
	var c := await _setup(slot,false,null,definition_override)
	c.h.rooms[c.anchor] = _chapter_room(c,"high-and-low",c.anchor,true)
	_check(await c.online.coordinator.refresh(), "Source completion is admitted from actual native A/B proof")
	_check(c.owner.mark_story_seen(0,"arrival"), "Prior source arrival is acknowledged independently")
	c.child.story_flow = c.flow
	c.child._show_ready()
	_check(c.child.mode == "complete" and c.child.journey.chapter_complete(), "Warm source is the actual settled completed scene")
	var fixture := _json("res://tests/fixtures/campaign/control-v2.json")
	var published: Dictionary = fixture.accepted_result.campaign.duplicate(true)
	published.campaign_key = c.owner.view().campaign_key
	var definition: Dictionary = c.owner.definition()
	while published.chapters.size() < definition.chapters.size():
		published.chapters.append({"chapter":definition.chapters[published.chapters.size()].duplicate(true),"room_id":null,"completion":null})
	published.player_slot = slot
	if slot == "p1":
		published.invite_code = null
		published.invite_expires_at = null
	var target_room: String = published.chapters[1].room_id
	c.h.rooms[target_room] = _chapter_room(c,"rolling-home",target_room,target_complete)
	c.h.view = published
	_check(await c.owner.refresh() and await c.owner.select_current(), "Accepted target is separately verified and its selection saved")
	_check(c.owner.adoption_ready() and c.online.coordinator == c.child.journey, "Readiness retains the completed source before adoption")
	var main := PresentationMain.new()
	main.saves.data = {"settings":{"sound":false,"music":false,"reduced_motion":true}}
	main.relay_session = c.online
	c.viewport.add_child(main)
	main.mode = "relay_online"
	main.relay_child = c.child
	c.child.reparent(main)
	c["main"] = main
	c["target"] = target_room
	c["replace"] = main._replace_campaign_relay_child.bind(c.owner,main.story_closed)
	return c

func _ordered_handoff(slot: String, target_complete: bool) -> void:
	var c := await _warm_setup(slot,target_complete)
	var source: RefCounted = c.online.coordinator
	var old_child: WeakRef = weakref(c.child)
	var calls: int = c.h.calls.size()
	_check(c.flow.present_handoff(c.child,0,c.replace), "A settled accepted source offers its completion: "+slot)
	var old_generation: int = c.child._story_hold
	_check(c.flow._active.phase == "completion" and c.flow._panel.dialogue.text == "Completed test line." and c.online.coordinator == source and c.child.is_inside_tree(), "Completion text remains on the source world until dismissal")
	c.child._begin()
	_check(not c.child.running, "Completion hold never starts gameplay")
	c.flow._panel._advance()
	var next: Node = c.main.relay_child
	_check(next != c.child and next.is_inside_tree() and not c.child.is_inside_tree() and c.online.coordinator != source, "Actual Main synchronously replaces the source after native adoption")
	_check(next.journey == c.online.coordinator and next.chapter_key == Registry.ROLLING_HOME and next.journey.snapshot().room_id == c.target, "The attached destination uses its own native engine and coordinator")
	_check(c.flow._panel.is_open() and c.flow._active.phase == "arrival" and c.flow._active.index == 1 and not next.running, "The next arrival follows completion without an automatic Begin")
	var arrival_generation: int = next._story_hold
	_check(c.replace.call(c.child,old_generation,c.target,1,c.flow) == null and c.main.relay_child == next and next._story_hold == arrival_generation and c.flow.busy(), "A late old Main replacement cannot adopt again or release the new passage")
	_check(next.mode == ("complete" if target_complete else "ready" if slot == "p0" else "online_waiting"), "Partner progress is retained even when the target is already complete")
	c.flow._panel._skip()
	_check(not c.flow.busy() and not next.running and c.owner.story_seen(0,"completion") and c.owner.story_seen(1,"arrival"), "Both passages settle cosmetically without advancing another chapter")
	_check(c.h.calls.size() == calls, "Warm presentation and adoption make no network request")
	await process_frame
	_check(old_child.get_ref() == null, "The old native child is disposed after its generation is retired")
	await _dispose(c)

func _second_transition(slot: String) -> void:
	var definition: Dictionary = _json("res://tests/fixtures/campaign/control-v2.json").definition
	var level := Registry.definition("conservatory@1")
	definition.chapters.append({"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),"simulation_version":7,"premium":true})
	var c := await _warm_setup(slot,true,definition)
	_check(c.flow.present_handoff(c.child,0,c.replace), "Three-chapter campaign begins with a native first handoff")
	c.flow._panel._skip()
	var source: Node = c.main.relay_child
	var room: Dictionary = source.journey.snapshot()
	var published: Dictionary = c.h.view.duplicate(true)
	published.revision = 6
	published.current_index = 2
	published.chapters[1].completion = {"source_revision":room.revision,"source_branch":room.branch,"checkpoint_hash":room.checkpoint.checkpoint_hash,"transition_id":"e".repeat(64),"from_campaign_revision":3,"accepted_campaign_revision":5}
	var target_room := "N".repeat(22)
	published.chapters[2].room_id = target_room
	c.h.rooms[target_room] = _chapter_room(c,"conservatory",target_room,false)
	c.h.view = published
	_check(await c.owner.refresh() and await c.owner.select_current() and c.owner.adoption_ready(), "Second accepted transition separately verifies the simulation7 destination")
	_check(c.flow.present_handoff(source,1,c.replace), "Rolling Home completion stays on its own native world: "+slot)
	c.flow._panel._advance()
	var next: Node = c.main.relay_child
	_check(next != source and next.chapter_key == "conservatory@1" and next.journey.snapshot().room_id == target_room and c.flow._active.index == 2 and c.flow._active.phase == "arrival", "Actual second handoff changes both chapter engine and story index")
	c.flow._panel._skip()
	_check(not next.running and c.owner.story_seen(1,"completion") and c.owner.story_seen(2,"arrival") and not c.owner.story_seen(2,"completion"), "Second transition acknowledges exactly its completion and arrival without inventing a finale")
	await _dispose(c)

func _skip_boundary() -> void:
	var c := await _warm_setup()
	var calls: int = c.h.calls.size()
	_check(c.flow.present_handoff(c.child,0,c.replace), "Skip starts from the settled accepted boundary")
	c.child._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(c.main.relay_child != c.child and not c.flow._panel.is_open() and not c.flow.busy(), "Native Skip skips the whole completion/arrival boundary")
	_check(c.owner.story_seen(0,"completion") and c.owner.story_seen(1,"arrival") and not c.main.relay_child.running and c.h.calls.size() == calls, "Skip saves only the two eligible markers and never sends Continue")
	await _dispose(c)

func _partial_cosmetic_failure() -> void:
	var c := await _warm_setup()
	var scope: String = "relay-campaign-v1:"+c.player+":"+c.anchor
	c.h.store.on_save = func(saved_scope: String):
		if saved_scope == scope and "0:completion" in c.h.store.saved[scope].seen:
			c.h.store.fail_scope = scope
	var source: RefCounted = c.online.coordinator
	_check(c.flow.present_handoff(c.child,0,c.replace), "Partial cosmetic failure starts on the source")
	c.flow._panel._skip()
	_check(c.owner.story_seen(0,"completion") and not c.owner.story_seen(1,"arrival") and c.flow._panel.next_button.text == "Retry", "The second marker may fail without undoing the first or opening a second passage")
	_check(c.online.coordinator == source and c.child.is_inside_tree(), "Cosmetic Retry/Close keeps the source scene")
	c.flow._panel._skip()
	_check(c.main.relay_child != c.child and not c.flow._panel.is_open() and not c.owner.story_seen(1,"arrival"), "Explicit Close adopts while suppressing only the unsaved arrival for this visit")
	c.h.store.fail_scope = ""
	c.h.store.on_save = Callable()
	_check(c.flow.configure(c.owner,c.h.identity,c.content) and c.flow.present_arrival(c.main.relay_child,1), "A fresh presentation owner can recover the unsaved eligible arrival")
	await _dispose(c)

func _pointer_failure() -> void:
	var c := await _warm_setup()
	var source: RefCounted = c.online.coordinator
	var last_room: String = c.online.last_room()
	c.h.store.fail_scope = "relay-lobby-v2:"+c.player
	_check(c.owner.adoption_ready(), "Read-only readiness does not probe a future pointer write")
	_check(c.flow.present_handoff(c.child,0,c.replace), "Verified selection can show completion before a transient pointer write failure")
	c.flow._panel._advance()
	_check(c.main.relay_child == c.child and c.child.is_inside_tree() and c.online.coordinator == source and c.online.last_room() == last_room, "Pointer-save failure preserves the source node and coordinator")
	_check(c.child.mode == "error" and not c.child.running and c.child.overlay.visible, "Failed adoption exposes bounded recovery without stale Record")
	await _dispose(c)

func _pure_readiness() -> void:
	var c := await _warm_setup()
	var candidate: RefCounted = c.owner._bridge._candidate
	var writes: int = c.h.store.writes.size()
	var calls: int = c.h.calls.size()
	c.owner.last_code = "owner-sentinel"
	c.owner._bridge.last_code = "bridge-sentinel"
	c.online.last_error = "online-sentinel"
	candidate.last_error = "candidate-sentinel"
	c.h.store.fail_read = "relay-lobby-v2:"+c.player
	_check(c.owner.adoption_ready(), "Readiness observes the loaded index without disk restore")
	_check(not c.online.observe_campaign_source_lease().is_empty(), "The public source observer reads the loaded source without restoring it")
	var original_lobby: Dictionary = c.owner._lobby.duplicate(true)
	for path: String in ["/v2/campaigns","/v2/campaigns/join"]:
		var definition: Dictionary = c.owner.definition()
		var body: Dictionary = LobbyProtocol.create_body(definition,"warm-pending-create-0001") if path == "/v2/campaigns" else LobbyProtocol.join_body(definition,"AB".repeat(10))
		var request := {"path":path,"body":body,"request_hash":LobbyProtocol.request_hash(c.player,path,body)}
		_check(LobbyProtocol.pending_valid(request,[definition],c.player), "The pending lobby request has an exact validated Create/Join identity")
		var pending: Dictionary = request.duplicate(true)
		pending["accepted_campaign"] = {}
		c.owner._lobby["schema_version"] = 2
		c.owner._lobby["pending"] = pending
		if c.owner.has_method("_valid_lobby_pending"):
			_check(c.owner._valid_lobby(c.owner._lobby), "The combined owner accepts this pending lobby journal shape")
		_check(not c.owner.adoption_ready() and c.owner._bridge._candidate == candidate and c.online.coordinator == c.child.journey, "Pending lobby admission holds readiness without clearing the retained target or source")
		c.owner._lobby = original_lobby.duplicate(true)
		_check(c.owner.adoption_ready(), "Readiness resumes only after the loaded lobby uncertainty is absent")
	c.h.identity_value.epoch += 1
	var state: Dictionary = candidate._state.duplicate(true)
	_check(not c.owner.adoption_ready() and Canonical.same(state,candidate._state), "Identity mismatch is unavailable without invalidating the retained candidate")
	_check(c.owner.last_code == "owner-sentinel" and c.owner._bridge.last_code == "bridge-sentinel" and c.online.last_error == "online-sentinel" and candidate.last_error == "candidate-sentinel" and c.h.store.writes.size() == writes and c.h.calls.size() == calls, "Readiness changes no diagnostics, durable state or network activity")
	c.h.identity_value.epoch -= 1
	c.online._index_loaded = false
	_check(not c.owner.adoption_ready() and not c.online._index_loaded, "An unready source index is not implicitly restored")
	c.online._index_loaded = true
	c.owner._bridge.invalidate()
	_check(not c.owner.adoption_ready(), "A selected pointer without a retained native candidate cannot advertise readiness")
	await _dispose(c)

func _lobby_pending_arrival() -> void:
	for path: String in ["/v2/campaigns","/v2/campaigns/join"]:
		var c := await _setup("p0",false)
		_check(c.owner.has_method("pending_lobby"), "Combined suite requires the lobby owner implementation")
		if not c.owner.has_method("pending_lobby"):
			await _dispose(c)
			return # This scenario requires the explicit combined lobby overlay.
		var definition: Dictionary = c.owner.definition()
		var body: Dictionary = LobbyProtocol.create_body(definition,"warm-pending-arrival-0001") if path == "/v2/campaigns" else LobbyProtocol.join_body(definition,"AB".repeat(10))
		c.owner._lobby["schema_version"] = 2
		c.owner._lobby["pending"] = {"path":path,"body":body,"request_hash":LobbyProtocol.request_hash(c.player,path,body),"accepted_campaign":{}}
		_check(c.owner._valid_lobby(c.owner._lobby), "Automatic arrival test uses a valid combined pending lobby journal")
		_check(not c.flow.present_arrival(c.child,0) and not c.flow.busy() and c.child.overlay.visible, "Pending admission keeps automatic arrival from hiding recovery controls")
		var source: RefCounted = c.online.coordinator
		var pending: Dictionary = c.owner.pending_lobby()
		var calls: int = c.h.calls.size()
		_check(c.flow.present_history(c.child,0,"arrival"), "Explicit same-context history stays available during lobby recovery")
		c.flow._panel._skip()
		_check(c.online.coordinator == source and Canonical.same(c.owner.pending_lobby(),pending) and c.h.calls.size() == calls, "History preserves the pending admission and source without sending requests")
		await _dispose(c)

func _target_pending() -> void:
	var c := await _warm_setup()
	var target: RefCounted = c.owner._bridge._candidate
	var recording := _json("res://tests/fixtures/cooperative/weight-of-a-friend-a.json")
	_check(target.save_draft(recording) and not await target.commit(recording), "The actual destination holds a native rehearsal and lost-response request")
	var pending: Dictionary = target.pending()
	var draft: Dictionary = target.draft()
	var calls: int = c.h.calls.size()
	_check(not pending.is_empty() and c.owner.adoption_ready() and c.flow.present_handoff(c.child,0,c.replace), "A target's existing recovery remains adoptable under the reviewed rules")
	c.flow._panel._advance()
	_check(c.main.relay_child.journey == target and Canonical.same(pending,target.pending()) and Canonical.same(draft,target.draft()), "Warm adoption preserves the exact target key and rehearsal")
	_check(not c.flow.busy() and not c.flow._panel.is_open() and c.main.relay_child.mode == "online_waiting" and c.h.calls.size() == calls, "Pending target shows recovery and defers arrival without resubmitting gameplay")
	await _dispose(c)

func _finale_and_history() -> void:
	var c := await _warm_setup("p0",true)
	_check(c.flow.present_handoff(c.child,0,c.replace), "Finale setup traverses a real warm boundary")
	c.flow._panel._skip()
	var final_child: Node = c.main.relay_child
	var publication: Dictionary = c.h.view.duplicate(true)
	publication.state = "complete"
	publication.revision = 6
	var room: Dictionary = final_child.journey.snapshot()
	publication.chapters[1].completion = {"source_revision":room.revision,"source_branch":room.branch,"checkpoint_hash":room.checkpoint.checkpoint_hash,"transition_id":"d".repeat(64),"from_campaign_revision":4,"accepted_campaign_revision":6}
	c.h.view = publication
	_check(await c.owner.refresh(), "Terminal Finish publication is strictly validated")
	var coordinator: RefCounted = c.online.coordinator
	var calls: int = c.h.calls.size()
	_check(c.flow.present_finale(final_child,1), "Accepted final completion opens over the retained native final world")
	c.flow._panel._advance()
	_check(c.main.relay_child == final_child and c.online.coordinator == coordinator and final_child.mode == "complete" and not final_child.running and not c.flow.busy(), "Final dismissal keeps the final scene without another room or arrival")
	var durable: Dictionary = c.h.store.saved.duplicate(true)
	_check(c.flow.history_entries().size() == 4 and c.flow.present_history(final_child,0,"completion"), "History includes published arrivals and accepted completions only")
	c.flow._panel._skip()
	_check(Canonical.same(durable,c.h.store.saved) and c.h.calls.size() == calls and c.online.coordinator == coordinator, "Reading an already-seen history passage changes no journal, request or selection")
	await _dispose(c)

func _changed_contexts() -> void:
	for change: String in ["identity","publication","selection"]:
		var c := await _warm_setup()
		var source: RefCounted = c.online.coordinator
		_check(c.flow.present_handoff(c.child,0,c.replace), "Context test begins on an eligible completed source")
		c.child._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		c.flow._panel._advance()
		_check(c.online.coordinator == source and c.flow._panel.is_open(), "Backgrounded completion neither acknowledges nor adopts")
		if change == "identity": c.h.identity_value.epoch += 1
		elif change == "publication": c.owner._campaign._state.view["state"] = "deleting"
		else: c.owner._campaign._state.selected_room = c.anchor
		c.child._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		_check(c.main.relay_child == c.child and c.child.is_inside_tree() and c.child.mode == "error" and not c.child.running, "Changed "+change+" cancels into source recovery without replacement")
		await _dispose(c)

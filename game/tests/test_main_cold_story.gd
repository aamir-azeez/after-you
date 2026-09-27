extends "res://tests/test_main_story.gd"
## Real Main input, owner/bridge, native proof admission and durable stores.
## The three-chapter story and transport replies are synthetic and unexposed.
const FAR_ROOM := "NNNNNNNNNNNNNNNNNNNNNN"

func _run() -> void:
	for guest: bool in [false,true]: await _distant_current(false,true,false,guest)
	await _distant_current(true,true,false)
	await _distant_current(true,false,false)
	await _distant_current(true,false,true)
	await _late_saved_b()
	for failure: String in ["missing","wrong_partner","pointer"]: await _target_failure(failure)
	for state: String in ["activation","deleting"]: await _authority_hold(state)
	for change: String in ["back","identity","retired","background"]: await _late_target(change)
	# Preserve the adjacent completion-before-adoption route through actual Main.
	_make_story_fixture()
	await _late_b_main()
	await _terminal_main()
	print("Main cold story recovery: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _three_fixture() -> void:
	_make_story_fixture()
	var level := Registry.definition("conservatory@1")
	var pin := {"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),"simulation_version":7,"premium":true}
	fixture.definition.chapters.append(pin)
	story_content.chapters.append({"level_id":level.id,"level_version":level.version,"arrival":[{"speaker":"p0","text":"Current test place."}],"completion":[{"speaker":"p1","text":"Final test place."}]})
	var story_body := story_content.duplicate(true)
	story_body.erase("content_hash")
	story_content["content_hash"] = Canonical.digest(story_body)
	fixture.definition["story"] = StorySource.pin(story_content)
	var definition_body: Dictionary = fixture.definition.duplicate(true)
	definition_body.erase("definition_hash")
	fixture.definition["definition_hash"] = Canonical.digest(definition_body)
	_replace_key(fixture,Protocol.key(fixture.definition))
	for view: Dictionary in [fixture.active_view,fixture.accepted_result.campaign]:
		view.chapters.append({"chapter":pin.duplicate(true),"room_id":null,"completion":null})
	_check(Protocol.definition_valid(fixture.definition),"Three bundled chapter pins and synthetic story form a valid immutable definition")

func _third_room(c: Dictionary, complete: bool) -> Dictionary:
	var level := Registry.definition("conservatory@1")
	var room: Dictionary = c.h.rooms[c.anchor].duplicate(true)
	room["room_id"] = FAR_ROOM
	room["level_id"] = level.id
	room["level_version"] = level.version
	room["definition_hash"] = Canonical.digest(level)
	room["simulation_version"] = 7
	room["revision"] = 5 if complete else 1
	room["stage_index"] = 2 if complete else 0
	room["checkpoint"] = _json("res://tests/fixtures/journey/conservatory"+("-final-checkpoint.json" if complete else "-initial-checkpoint.json"))
	room["completed_pair_ids"] = ["p0-0","p0-1"] if complete else []
	room["active_role"] = "complete" if complete else "a"
	room["first_player_id"] = null if complete else HOST
	room["active_player_id"] = null if complete else HOST
	room["stage_id"] = "" if complete else level.stages[0].id
	room["a_turn_id"] = null
	room["recording_a"] = null
	return room

func _advanced(c: Dictionary, terminal: bool) -> Dictionary:
	var published: Dictionary = fixture.accepted_result.campaign.duplicate(true)
	published["revision"] = 9 if terminal else 6
	published["current_index"] = 2
	published["state"] = "complete" if terminal else "active"
	published.chapters[1]["completion"] = {"source_revision":5,"source_branch":0,"checkpoint_hash":c.h.rooms[c.target].checkpoint.checkpoint_hash,"transition_id":"e".repeat(64),"from_campaign_revision":3,"accepted_campaign_revision":5}
	published.chapters[2]["room_id"] = FAR_ROOM
	if terminal:
		published.chapters[2]["completion"] = {"source_revision":5,"source_branch":0,"checkpoint_hash":c.h.rooms[FAR_ROOM].checkpoint.checkpoint_hash,"transition_id":"f".repeat(64),"from_campaign_revision":6,"accepted_campaign_revision":8}
	if c.h.player_id == GUEST:
		published["player_slot"] = "p1"
		published["invite_code"] = null
		published["invite_expires_at"] = null
	_check(Protocol.view_valid(published,fixture.definition,c.h.player_id),"Advanced control prefix is strictly valid independently of native cached progress")
	return published

func _gap(terminal: bool = false, complete_source: bool = true, same_index: bool = false, guest: bool = false, saved_b: bool = false, activation: bool = false) -> Dictionary:
	_three_fixture()
	var c := await _make(guest)
	c.online.capabilities = Boundaries.campaign_capabilities(fixture.definition)
	c.h.rooms[c.target] = _room("rolling-home",c.target,true)
	if guest:
		c.h.rooms[c.target]["player_slot"] = "p1"
		c.h.rooms[c.target].erase("invite_code")
	c.h.rooms[FAR_ROOM] = _third_room(c,false)
	if saved_b:
		c.h.rooms[c.anchor] = _prepare_b(c)
		_check(await c.online.coordinator.refresh(),"A real last-stage A proof prepares the saved B recovery")
		_check(not await c.online.coordinator.commit(_json("res://tests/fixtures/cooperative/down-and-around-b.json")),"Lost accepted-B response leaves the exact native request pending")
		c["saved_b"] = c.online.coordinator.pending()
	elif complete_source and not same_index:
		c.h.rooms[c.anchor] = _room("high-and-low",c.anchor,true)
		if guest:
			c.h.rooms[c.anchor]["player_slot"] = "p1"
			c.h.rooms[c.anchor].erase("invite_code")
		_check(await c.online.coordinator.refresh(),"Historical completion comes from both real native A/B pairs")
	if same_index:
		c.h.view = _advanced(c,false)
		_check(await c.owner.refresh() and await c.owner.select_current() and c.owner.adopt_selected(),"Current final chapter initially has an actual incomplete native cache")
	if terminal: c.h.rooms[FAR_ROOM] = _third_room(c,true)
	if saved_b: c.h.rooms[c.anchor] = _room("high-and-low",c.anchor,true)
	c.h.view = _advanced(c,terminal)
	if activation: c.h.view["activation"] = {"transition_id":c.h.view.chapters[1].completion.transition_id}
	_check(await c.owner.refresh(),"A later accepted publication is saved without replacing the retained native child")
	# Isolate selection/recovery from the independently owned cold narrative queue.
	# These prior local markers do not assert that earlier passages were seen.
	if not activation: _check(c.owner.mark_story_seen(2,"arrival"),"The current arrival marker is an explicit fixture precondition")
	var cold := _cold(c)
	c.online = cold.online
	c.owner = cold.owner
	c.merge(_main_for(c))
	await c.app._story_lobby_action("resume")
	_check(is_instance_valid(c.app.relay_child),"Cold Main restores the exact durable selected child before network recovery")
	c["source"] = c.app.relay_child
	c["source_journey"] = c.app.relay_child.journey
	c["source_room"] = c.online.last_room()
	c["source_bytes"] = c.h.store.saved["relay-room-v2:"+c.h.player_id+":"+c.source_room].duplicate(true)
	c["seen"] = c.h.store.saved["relay-campaign-v1:"+c.h.player_id+":"+c.anchor].seen.duplicate(true)
	_check(c.source.mode in ["campaign_recovery","complete"] and c.source.journey.campaign_recovery_only() and _button(c.source.overlay,"Record") == null,"Historical or stale terminal cache is recovery-only with no Record control")
	return c

func _finish_action(c: Dictionary) -> void:
	for frame in range(300):
		await process_frame
		if not c.app._campaign_action_busy and not c.owner.busy(): return
	_check(false,"Bounded Main recovery finishes or returns a stable hold")

func _distant_current(terminal: bool, complete_source: bool, same_index: bool, guest: bool = false) -> void:
	var c := await _gap(terminal,complete_source,same_index,guest)
	var old: WeakRef = weakref(c.source)
	var calls: int = c.h.calls.size()
	await _click_control(c,"Resume")
	await _finish_action(c)
	var child: Node = c.app.relay_child
	_check(child != old.get_ref() and child.story_chapter_index == 2 and child.journey == c.online.coordinator,"Actual Resume replaces only after native current-chapter adoption")
	_check(c.online.last_room() == FAR_ROOM and c.owner.selected_room() == FAR_ROOM and child.journey.snapshot().room_id == FAR_ROOM,"Visible, native and durable current-room pointers agree")
	_check(child.chapter_key == "conservatory@1" and not child.running,"The destination uses its real simulation7 chapter without starting a turn")
	_check(_only_gets(c.h.calls.slice(calls)) and c.h.calls.slice(calls).any(func(call: Dictionary): return call.path == "/v2/rooms/"+FAR_ROOM),"Explicit catch-up uses control and exact native target GETs, never Continue or gameplay POST")
	_check(Canonical.same(c.seen,c.h.store.saved["relay-campaign-v1:"+c.h.player_id+":"+c.anchor].seen),"Selection recovery does not mark any omitted dialogue as seen")
	if not same_index:
		_check(Canonical.same(c.source_bytes,c.h.store.saved["relay-room-v2:"+c.h.player_id+":"+c.source_room]),"Historical native proof and rehearsal bytes remain unchanged")
	if terminal:
		_check(child.journey.chapter_complete() and child.mode == "complete" and _button(child.overlay,"Read story") != null,"Terminal control is shown only with actual natively verified final completion")
	else:
		_check(not child.journey.chapter_complete() and child.mode == ("online_waiting" if guest else "ready"),"An active destination preserves the viewer's real turn role")
	await process_frame
	_check(old.get_ref() == null,"Retired source node is disposed after the synchronous replacement")
	await _dispose_ui(c)

func _late_saved_b() -> void:
	var c := await _gap(false,false,false,false,true)
	var before: Dictionary = c.source.journey.pending()
	await _click_control(c,"Check saved turn")
	await _finish_action(c)
	_check(c.app.relay_child == c.source and Canonical.same(before,c.source.journey.pending()) and c.online.last_room() == c.anchor,"Unknown gameplay acceptance cannot be bypassed by distant publication")
	c.h.operation_reply = {"ok":true,"status":200,"data":_b_receipt(c.saved_b,c.h.rooms[c.anchor])}
	var calls: int = c.h.calls.size()
	await _click_control(c,"Check saved turn")
	await _finish_action(c)
	_check(c.online.last_room() == FAR_ROOM and c.app.relay_child.story_chapter_index == 2,"Exact accepted-B receipt settles before distant current adoption")
	_check(_only_gets(c.h.calls.slice(calls)),"Known accepted-B recovery and target verification need no replacement POST")
	_check(c.h.store.saved["relay-room-v2:"+HOST+":"+c.anchor].pending.is_empty(),"The real accepted receipt, not catch-up, clears the original pending gameplay journal")
	await _dispose_ui(c)

func _target_failure(kind: String) -> void:
	var c := await _gap()
	if kind == "missing": c.h.rooms.erase(FAR_ROOM)
	elif kind == "wrong_partner": c.h.rooms[FAR_ROOM]["guest_id"] = OTHER
	else: c.h.store.fail_scope = "relay-lobby-v2:"+HOST
	await _click_control(c,"Resume")
	await _finish_action(c)
	_check(c.app.relay_child == c.source and c.source.is_inside_tree() and c.online.coordinator == c.source_journey and c.online.last_room() == c.anchor,"Target verification or pointer failure retains source node, coordinator and pointer: "+kind)
	_check(Canonical.same(c.source_bytes,c.h.store.saved["relay-room-v2:"+HOST+":"+c.anchor]),"Failed recovery preserves historical native evidence: "+kind)
	_check(not c.app._campaign_action_busy and _button(c.source.overlay,"Resume") != null and _button(c.source.overlay,"Record") == null,"Failure returns a deliberate recovery action without historical Record: "+kind)
	if kind == "pointer":
		c.h.store.fail_scope = ""
		await _click_control(c,"Resume")
		await _finish_action(c)
		_check(c.online.last_room() == FAR_ROOM,"Explicit Retry can repair a previously saved selection without clearing the source first")
	await _dispose_ui(c)

func _authority_hold(state: String) -> void:
	# First observe the debt as part of the new publication. Reintroducing it
	# after a saved discharge would correctly fail the independent merge guard.
	var c := await _gap(false,true,false,false,false,state == "activation")
	if state == "activation": c.h.view["activation"] = {"transition_id":c.h.view.chapters[1].completion.transition_id}
	else: c.h.view["state"] = "deleting"
	c.h.view["revision"] = 7
	var calls: int = c.h.calls.size()
	await _click_control(c,"Resume")
	await _finish_action(c)
	_check(c.app.relay_child == c.source and c.online.last_room() == c.anchor,"Unsettled activation or deletion cannot be skipped to enter a target: "+state)
	_check(not c.h.calls.slice(calls).any(func(call: Dictionary): return call.path == "/v2/rooms/"+FAR_ROOM),"Held control authority does not probe or adopt gameplay: "+state)
	if state == "activation":
		_check(c.h.calls.slice(calls).any(func(call: Dictionary): return call.path.ends_with("/resume")),"Explicit recovery still attempts the existing exact activation recovery before catch-up")
	await _dispose_ui(c)

func _late_target(change: String) -> void:
	var c := await _gap()
	var target_started := [false]
	c.h.on_request = func():
		if c.h.calls[-1].path == "/v2/rooms/"+FAR_ROOM:
			target_started[0] = true
			c.h.hold = true
	await _click_control(c,"Resume")
	for frame in range(120):
		await process_frame
		if target_started[0]: break
	_check(target_started[0] and c.app.relay_child == c.source,"Native target request leaves historical child attached while awaiting: "+change)
	var during: Dictionary = c.h.store.saved.duplicate(true)
	var calls: int = c.h.calls.size()
	var generation: int = c.app._campaign_generation
	_check(not c.app._campaign_depart_for_ordinary(),"Concurrent ordinary departure cannot borrow the explicit recovery allowance")
	await c.app._story_child_action("recover",c.source)
	_check(c.app._campaign_generation == generation and c.h.calls.size() == calls and Canonical.same(during,c.h.store.saved),"A concurrent recovery attempt neither replaces the operation token nor writes or dispatches")
	if change == "back":
		c.app._leave_story_child()
		_check(c.app._campaign_recovery_context.is_empty(),"Back retires the recovery observer before any delayed reply")
	elif change == "identity": c.h.identity_value["epoch"] += 1
	elif change == "retired": c.owner.invalidate_identity()
	else: c.app.application_backgrounded = true
	c.h.hold = false
	c.h.on_request = Callable()
	c.h.release.emit()
	await _finish_action(c)
	_check(c.app._campaign_recovery_context.is_empty(),"Success, refusal and stale completion retire only their own temporary recovery allowance")
	_check(c.online.last_room() == c.anchor,"A late target response cannot change the durable native pointer: "+change)
	if change == "back":
		_check(c.app.mode == "story_lobby" and not is_instance_valid(c.app.relay_child),"Late response cannot resurrect a child after explicit Back")
	else:
		_check(c.app.relay_child == c.source and c.source.is_inside_tree(),"Late callback cannot replace the retained scene after context retirement: "+change)
	await _dispose_ui(c)

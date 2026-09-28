extends "res://tests/test_main_story.gd"
## Real Main/Preview and scoped child contexts, with finite synthetic transport.
const Clock = preload("res://services/refresh_schedule.gd")
const PreviewSource = preload("res://relay_preview.gd")

class SceneHarness:
	extends UiHarness
	var fail_room := ""
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		if method == HTTPClient.METHOD_GET and path == "/v2/rooms/"+fail_room:
			calls.append({"method":method,"path":path,"body":body.duplicate(true)})
			await get_tree().process_frame
			return {"ok":false,"status":503,"code":"room_unavailable"}
		if "/operations/" in path:
			calls.append({"method":method,"path":path,"body":body.duplicate(true)})
			await get_tree().process_frame
			return {"ok":false,"status":404,"code":"operation_not_found"}
		return await super.request_json(method,path,body)

func _run() -> void:
	_make_story_fixture()
	await _waiting_join(false)
	await _waiting_join(true)
	for state: String in ["advanced","activation","continuing","deleting"]: await _changed_authority(state)
	for outcome: String in ["resume","failed_refresh","failed_room","different_source"]: await _completed_advance(outcome)
	await _saved_turn_direction()
	await _parent_saved_turn(false)
	await _parent_saved_turn(true)
	await _control_failure()
	for reason: String in ["background","back","identity"]: await _control_await(reason)
	await _unrelated_commit(false)
	await _unrelated_commit(true)
	print("Campaign in-scene refresh: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _scene_setup(waiting: bool = false) -> Dictionary:
	var h := SceneHarness.new()
	root.add_child(h)
	h.view = fixture.active_view.duplicate(true)
	if waiting:
		h.view.state = "waiting"
		h.view.guest_id = null
		h.view.revision = 0
	var anchor: String = h.view.campaign_room_id
	var target: String = fixture.accepted_result.campaign.chapters[1].room_id
	h.rooms[anchor] = _room("high-and-low",anchor,false)
	h.rooms[target] = _room("rolling-home",target,false)
	if waiting: h.rooms[anchor].guest_id = null
	var online := Online.new(h,h.identity,h.store)
	_check(await online.open_room(anchor),"Scene fixture loads real native initial proof")
	online.capabilities = Boundaries.campaign_capabilities(fixture.definition)
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	_check(owner.restore_owner() and owner.bind_campaign(anchor,Protocol.key(fixture.definition)) and await owner.refresh() and await owner.select_current() and owner.adopt_selected(),"Scene fixture owns and adopts its exact scoped child")
	var c := {"h":h,"online":online,"owner":owner,"anchor":anchor,"target":target}
	c.merge(_main_for(c))
	_check(c.app._enter_story_child(),"Actual Main attaches the existing selected Story child")
	if c.app.campaign_flow.busy(): c.app.campaign_flow._panel._skip()
	await _settle()
	_check(is_instance_valid(c.app.relay_child) and not c.app.relay_child.running,"Scene begins without new gameplay")
	return c

func _waiting_join(timer: bool) -> void:
	var c := await _scene_setup(true)
	var child: Node = c.app.relay_child
	var source: RefCounted = child.journey
	_check(child.mode in ["ready","online_waiting"] and c.owner.view().guest_id == null and _button(child.overlay,"Refresh") != null,"Host has an actual refresh action before its friend joins")
	c.h.view = fixture.active_view.duplicate(true)
	c.h.rooms[c.anchor].guest_id = GUEST
	c.h.rooms[c.anchor].revision += 1
	var before: int = c.h.calls.size()
	if timer:
		child.online_refresh_queued = true
		await child._service_online_refresh()
	else:
		await _click_control(c,"Refresh")
		await _finish_request(c,child)
	var calls: Array = c.h.calls.slice(before)
	_check(calls.size() == 2 and calls[0].path == "/v2/campaigns/"+c.anchor and calls[1].path == "/v2/rooms/"+c.anchor and _only_gets(calls),"Membership catch-up performs control GET then exact child GET only")
	_check(c.owner.view().guest_id == GUEST and child.journey.snapshot().guest_id == GUEST and child.journey.my_turn(),"Accepted membership is present in both authorities before Record is enabled")
	_check(child.mode == "ready" and _button(child.overlay,"Record") != null and not child.running,"Refresh redraws the genuine ready card without starting input")
	_check(child.journey == source and c.online.last_room() == c.anchor and c.owner.selected_room() == c.anchor,"Catch-up keeps the same scene, coordinator and both saved pointers")
	await _dispose_ui(c)

func _changed_authority(state: String) -> void:
	var c := await _scene_setup()
	var child: Node = c.app.relay_child
	var source: RefCounted = child.journey
	var checkpoint: Dictionary = source.checkpoint()
	match state:
		"advanced","activation":
			c.h.view = fixture.accepted_result.campaign.duplicate(true)
			if state == "activation": c.h.view.activation = {"transition_id":fixture.accepted_result.receipt.transition_id}
		"continuing": c.h.view = fixture.pending_result.campaign.duplicate(true)
		"deleting":
			c.h.view.state = "deleting"
			c.h.view.revision += 1
	var before: int = c.h.calls.size()
	child.online_refresh_queued = true
	await child._service_online_refresh()
	_check(_only_gets(c.h.calls.slice(before)),"Changed publication polling does not advance or retry control: "+state)
	_check(child.mode == "campaign_recovery" and _button(child.overlay,"Record") == null and child.journey.campaign_recovery_only(),"Changed authority redraws held recovery even when the room read cannot enable play: "+state)
	_check(child.journey == source and c.online.last_room() == c.anchor and c.owner.selected_room() == c.anchor and Canonical.same(checkpoint,source.checkpoint()),"Held publication retains the source proof and selection: "+state)
	_check(not child.running and source.pending().is_empty(),"Polling creates no gameplay request: "+state)
	_check(c.app._story_child_state(child).message == MainSource.PlayerCopy.MAIN_571E92F64ED1,"An incomplete source retains its recovery warning: "+state)
	await _dispose_ui(c)

func _completed_advance(outcome: String) -> void:
	var c := await _scene_setup()
	var child: Node = c.app.relay_child
	var source: RefCounted = child.journey
	c.h.rooms[c.anchor] = _room("high-and-low",c.anchor,true)
	_check(await source.refresh() and source.chapter_complete(),"Completed-source fixture verifies both native recording pairs")
	child.refresh_campaign_card()
	var checkpoint: Dictionary = source.checkpoint()
	c.h.view = fixture.accepted_result.campaign.duplicate(true)
	if outcome == "different_source": c.h.view.chapters[0].completion.source_revision += 1
	if outcome == "failed_room": c.h.fail_room = c.anchor
	var before: int = c.h.calls.size()
	child.online_refresh_queued = true
	await child._service_online_refresh()
	_check(not c.h.calls.slice(before).is_empty() and _only_gets(c.h.calls.slice(before)),"Completed-source catch-up reads authority without continuing the story")
	_check(c.owner.last_code.is_empty() and Canonical.same(c.owner.view(),c.h.view),"The advanced publication is accepted even when its completed source differs")
	_check(child.mode == "complete" and child.journey == source and _button(child.overlay,"Resume") != null and _button(child.overlay,"Record") == null,"The held completed source offers only deliberate Resume")
	_check(c.online.last_room() == c.anchor and c.owner.selected_room() == c.anchor and Canonical.same(checkpoint,source.checkpoint()) and not c.app.campaign_flow.busy(),"A newer publication keeps the exact completed source and both pointers until Resume")
	if outcome == "failed_room":
		_check(not source.last_error.is_empty() and c.app._story_child_state(child).message == MainSource.PlayerCopy.MAIN_571E92F64ED1,"An actual child-room read failure keeps its warning despite matching cached completion")
		await _dispose_ui(c)
		return
	if outcome == "different_source":
		_check(c.app._story_child_state(child).message == MainSource.PlayerCopy.MAIN_571E92F64ED1,"A completion that does not match the accepted source retains its warning")
		await _dispose_ui(c)
		return
	_check(c.app._story_child_state(child).message.is_empty() and child._campaign_actions.find_children("*","Label",true,false).is_empty(),"A confirmed adjacent handoff shows Resume without a false service warning")
	if outcome == "failed_refresh":
		c.h.fail_control = true
		before = c.h.calls.size()
		child.online_refresh_queued = true
		await child._service_online_refresh()
		var calls: Array = c.h.calls.slice(before)
		_check(calls.size() == 1 and _only_gets(calls) and calls[0].path == "/v2/campaigns/"+c.anchor,"A failed later control read sends no child or mutation request")
		_check(c.app._story_child_state(child).message == MainSource.PlayerCopy.MAIN_571E92F64ED1 and not child._campaign_actions.find_children("*","Label",true,false).is_empty(),"An actual failed refresh remains visible even with a previously confirmed handoff")
		_check(child.journey == source and c.online.last_room() == c.anchor and c.owner.selected_room() == c.anchor and Canonical.same(checkpoint,source.checkpoint()),"The failed read preserves the verified source and selection")
	else:
		before = c.h.calls.size()
		await _click_control(c,"Resume")
		for frame in range(120):
			if c.app.campaign_flow.busy(): break
			await process_frame
		_check(c.app.relay_child == child and c.app.campaign_flow._active.get("phase") == "completion" and c.online.last_room() == c.anchor,"Ordinary Resume presents completion before adopting the next chapter")
		_check(_only_gets(c.h.calls.slice(before)),"Confirmed handoff Resume uses only reads, with no Continue POST")
		c.app.campaign_flow._panel._advance()
		_check(c.app.relay_child != child and c.app.campaign_flow._active.get("phase") == "arrival" and c.online.last_room() == c.target,"Closing completion adopts the verified next chapter and opens its arrival")
	await _dispose_ui(c)

func _saved_turn_direction() -> void:
	var c := await _scene_setup()
	var child: Node = c.app.relay_child
	var recording := _json("res://tests/fixtures/cooperative/upper-path-a.json")
	_check(not await child.journey.commit(recording),"Lost actual native turn leaves recovery pending")
	var pending: Dictionary = child.journey.pending()
	_check(not pending.is_empty(),"Saved turn uses the real Coordinator journal")
	child._show_ready()
	var before: int = c.h.calls.size()
	child.online_refresh_queued = true
	await child._service_online_refresh()
	var automatic: Array = c.h.calls.slice(before)
	_check(automatic.size() == 2 and _only_gets(automatic) and automatic[0].path == "/v2/campaigns/"+c.anchor,"Timer checks control and room without receipt fallback POST")
	_check(Canonical.same(pending,child.journey.pending()),"Timer retains exact pending recording, key and body")
	child.refresh_schedule = Clock.new()
	before = c.h.calls.size()
	await child._online_refresh()
	var explicit: Array = c.h.calls.slice(before)
	_check(explicit.size() == 3 and explicit[0].path == "/v2/campaigns/"+c.anchor and "/operations/" in explicit[1].path and explicit[1].method == HTTPClient.METHOD_GET and explicit[2].method == HTTPClient.METHOD_POST,"Explicit saved-turn check preserves receipt GET then retry direction after control catch-up")
	_check(explicit.size() == 3 and Canonical.same(explicit[2].body,pending.body) and Canonical.same(pending,child.journey.pending()),"Only the exact saved gameplay request is retried; its failed reply remains recoverable")
	await _dispose_ui(c)

func _control_failure() -> void:
	var c := await _scene_setup()
	var child: Node = c.app.relay_child
	var checkpoint: Dictionary = child.journey.checkpoint()
	c.h.fail_control = true
	var before: int = c.h.calls.size()
	child.online_refresh_queued = true
	await child._service_online_refresh()
	var calls: Array = c.h.calls.slice(before)
	_check(calls.size() == 1 and calls[0].path == "/v2/campaigns/"+c.anchor and _only_gets(calls),"Failed control catch-up does not issue a child request using unconfirmed authority")
	_check(not child.refresh_schedule.busy() and Canonical.same(checkpoint,child.journey.checkpoint()) and c.online.last_room() == c.anchor,"Failed GET releases the scheduler while retaining the source")
	await _dispose_ui(c)

func _parent_saved_turn(fail_control: bool) -> void:
	var c := await _scene_setup()
	var child: Node = c.app.relay_child
	_check(not await child.journey.commit(_json("res://tests/fixtures/cooperative/upper-path-a.json")),"Parent recovery fixture retains a real lost native turn")
	var pending: Dictionary = child.journey.pending()
	c.h.view = fixture.pending_result.campaign.duplicate(true)
	_check(await c.owner.refresh(),"New published continuation makes the retained source structurally recovery-only")
	child._show_ready()
	_check(child.mode == "campaign_recovery" and _button(child.overlay,"Check saved turn") != null,"Actual parent recovery card exposes the saved turn check")
	_check(c.app._story_child_state(child).message == MainSource.PlayerCopy.MAIN_52C04F6029F5,"A saved gameplay submission keeps its receipt warning")
	c.h.view.revision += 1
	c.h.fail_control = fail_control
	var before: int = c.h.calls.size()
	await _click_control(c,"Check saved turn")
	for i in range(360):
		if not c.app._campaign_action_busy: break
		await process_frame
	var calls: Array = c.h.calls.slice(before)
	_check(not c.app._campaign_action_busy and not calls.is_empty() and calls[0].path == "/v2/campaigns/"+c.anchor and calls[0].method == HTTPClient.METHOD_GET,"Rendered parent saved-turn recovery refreshes control before any receipt traffic")
	if fail_control:
		_check(calls.size() == 1,"Failed parent control GET sends no gameplay or control mutation")
	else:
		_check(calls.size() == 3 and "/operations/" in calls[1].path and calls[1].method == HTTPClient.METHOD_GET and calls[2].method == HTTPClient.METHOD_POST and Canonical.same(calls[2].body,pending.body),"Parent recovery checks the exact saved receipt then retries only its original native body")
	_check(Canonical.same(pending,child.journey.pending()) and c.online.last_room() == c.anchor and _button(child.overlay,"Record") == null,"Unsettled parent recovery retains pending bytes and the held source scene")
	_check(c.app._story_child_state(child).message == MainSource.PlayerCopy.MAIN_52C04F6029F5,"Unsettled receipt recovery keeps its saved-turn warning after the attempt")
	await _dispose_ui(c)

func _control_await(reason: String) -> void:
	var c := await _scene_setup()
	var child: Node = c.app.relay_child
	var source: RefCounted = child.journey
	var before: int = c.h.calls.size()
	c.h.delay_next = true
	child._online_refresh.call_deferred()
	await _settle()
	_check(c.owner.busy() and child.refresh_schedule.busy(),"Delayed control GET owns one refresh ticket: "+reason)
	var card: Node = child.overlay.get_child(0)
	await child._online_refresh()
	await child._service_online_refresh()
	_check(child.overlay.get_child(0) == card and child.refresh_schedule.busy(),"A concurrent explicit or automatic refresh cannot redraw the active owner's card")
	_check(source.create_live_simulation() == null and not child.running and source.pending().is_empty(),"Transient scoped authority refresh holds new gameplay without replacing its Loading card: "+reason)
	match reason:
		"background": child._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		"back": c.app._leave_story_child()
		"identity": c.h.identity_value.epoch += 1
	c.h.release.emit()
	for i in range(8): await process_frame
	var calls: Array = c.h.calls.slice(before)
	_check(calls.size() == 1 and calls[0].path == "/v2/campaigns/"+c.anchor and _only_gets(calls),"Retired/backgrounded control reply does not send the child request: "+reason)
	if reason == "background":
		_check(child.backgrounded and child.mode == "online_request" and not child.running,"Background does not redraw or start the held chapter")
		child._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		await child._service_online_refresh()
		_check(child.mode == "ready" and not child.running and not child.refresh_schedule.busy(),"Foreground restores the stable card after the interrupted manual read")
	elif reason == "back":
		_check(c.app.mode == "story_lobby" and not is_instance_valid(c.app.relay_child),"Late reply cannot recreate a closed story scene")
	else:
		_check(not source.my_turn() and source.create_live_simulation() == null,"Identity change cannot reuse the old scene's gameplay authority")
	await _dispose_ui(c)

func _finish_request(c: Dictionary, child: Node) -> void:
	for i in range(360):
		if not c.owner.busy() and not child.refresh_schedule.busy(): return
		await process_frame
	_check(false,"Rendered refresh request settles within the bounded fixture run")

func _unrelated_commit(campaign: bool) -> void:
	var c: Dictionary
	var child: Node
	if campaign:
		c = await _scene_setup()
		child = c.app.relay_child
	else:
		var h := SceneHarness.new()
		root.add_child(h)
		var room: String = fixture.active_view.campaign_room_id
		h.rooms[room] = _room("high-and-low",room,false)
		var online := Online.new(h,h.identity,h.store)
		_check(await online.open_room(room),"Ordinary delayed-save fixture opens native proof without campaign ownership")
		online.capabilities = {"mutations_enabled":true}
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1280,720)
		viewport.own_world_3d = true
		root.add_child(viewport)
		child = PreviewSource.new()
		child.chapter_key = "high-and-low@1"
		child.online_session = online
		child.settings = {"sound":false,"music":false,"reduced_motion":true}
		viewport.add_child(child)
		child.set_process(false)
		child.set_physics_process(false)
		c = {"h":h,"online":online,"viewport":viewport}
	child.review = _json("res://tests/fixtures/cooperative/upper-path-a.json")
	child.mode = "review"
	c.h.delay_next = true
	child._accept.call_deferred()
	for i in range(1800):
		if not c.h.delay_next: break
		await process_frame
	_check(not c.h.delay_next and child.mode == "online_request" and child.journey.busy(),"Real native commit remains suspended on its saving card")
	var card: Node = child.overlay.get_child(0)
	await child._service_online_refresh()
	_check(child.mode == "online_request" and child.overlay.get_child(0) == card and child._suspended_manual_refresh.is_empty(),"Refresh recovery never steals an ordinary or campaign Save card")
	c.h.release.emit()
	for i in range(8): await process_frame
	_check(not child.journey.pending().is_empty() and child.mode == "online_waiting","The original failed commit alone controls its pending recovery handoff")
	await _dispose_ui(c)

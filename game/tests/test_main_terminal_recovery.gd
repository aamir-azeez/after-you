extends "res://tests/test_main_story.gd"

class TerminalHarness extends UiHarness:
	var removed := false
	var lose_cleanup := false
	var pause_cleanup := false
	var cleanup_started := false
	var removed_anchor := ""
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		var anchor: String = removed_anchor if not removed_anchor.is_empty() else view.campaign_room_id
		if removed and method == HTTPClient.METHOD_GET and path == "/v2/campaigns":
			calls.append({"method":method,"path":path,"body":body.duplicate(true)})
			await get_tree().process_frame
			return {"ok":false,"status":409,"code":"campaign_terminal_reconciliation_required","data":{"error":{"code":"campaign_terminal_reconciliation_required","campaign_room_id":anchor,"retryable":false}}}
		if removed and method == HTTPClient.METHOD_GET and path == "/v2/campaigns/"+anchor:
			calls.append({"method":method,"path":path,"body":body.duplicate(true)})
			await get_tree().process_frame
			return {"ok":false,"status":404,"code":"campaign_not_found"}
		if method == HTTPClient.METHOD_POST and path == "/v2/campaigns/"+anchor+"/reconcile-deletion":
			calls.append({"method":method,"path":path,"body":body.duplicate(true)})
			cleanup_started = true
			if pause_cleanup: await release
			else: await get_tree().process_frame
			if lose_cleanup: return {"ok":false,"status":0,"code":"connection_interrupted"}
			return {"ok":true,"status":200,"data":{"schema_version":1,"operation":"campaign_terminal_cleanup","status":"released","player_id":player_id,"campaign_room_id":anchor}}
		return await super.request_json(method,path,body)

func _run() -> void:
	_make_story_fixture()
	await _explicit_recovery(false)
	await _explicit_recovery(true)
	await _back_during_cleanup()
	await _local_pointer_retry()
	await _receipt_write_retry()
	await _other_story_preserved()
	print("Main terminal recovery: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _terminal_setup(pending_turn: bool = true) -> Dictionary:
	var h := TerminalHarness.new()
	root.add_child(h)
	h.view = fixture.active_view.duplicate(true)
	h.capabilities = Boundaries.campaign_capabilities(fixture.definition)
	var anchor: String = h.view.campaign_room_id
	h.rooms[anchor] = _room("high-and-low",anchor,false)
	var online := Online.new(h,h.identity,h.store)
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	_check(await owner.load_campaign_lobby(),"The real owner reads supported story capabilities before admission")
	var c := {"h":h,"online":online,"owner":owner,"anchor":anchor}
	c.merge(_main_for(c))
	await c.app._story_lobby_action("create",Protocol.key(fixture.definition))
	_check(is_instance_valid(c.app.relay_child),"Main opens the accepted native chapter before removal")
	c.app.campaign_flow._panel._skip()
	if pending_turn: _check(not await online.coordinator.commit(_json("res://tests/fixtures/cooperative/upper-path-a.json")) and not online.coordinator.pending().is_empty(),"Removal begins with a real saved contribution awaiting its response")
	c.app._leave_story_child()
	h.removed = true
	return c

func _explicit_recovery(lost: bool) -> void:
	var c := await _terminal_setup()
	var room_before: Dictionary = c.h.store.saved[_room_scope(c.anchor)].duplicate(true)
	var control_before: Dictionary = c.h.store.saved[_journal(c.anchor)].duplicate(true)
	var posts: int = _cleanup_posts(c).size()
	await c.app._show_story()
	_check(not c.owner.terminal_recovery().is_empty() and _cleanup_posts(c).size() == posts,"Opening Story discovers removal using GET without sending cleanup")
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(960,540)]:
		c.viewport.size = dimensions
		c.app._refresh_safe_area()
		c.app._draw_story_lobby()
		await _settle()
		var recover := _button(c.app.overlay,"Finish recovery")
		var resume := _button(c.app.overlay,"Resume")
		var scroll: Node = recover.get_parent() if recover != null else null
		while scroll != null and not scroll is ScrollContainer: scroll = scroll.get_parent()
		_check(recover != null and not recover.disabled and scroll != null and scroll.get_global_rect().encloses(recover.get_global_rect()) and c.viewport.get_visible_rect().encloses(recover.get_global_rect()),"Explicit recovery is visible and actionable at "+str(dimensions))
		_check(resume == null or resume.disabled,"A removed chapter cannot resume while recovery is available")
		_check(_button(c.app.overlay,"Copy invitation") == null,"A removed story does not offer a stale invitation to share")
		_check(_button(c.app.overlay,"Start").disabled and _button(c.app.overlay,"Join").disabled,"Fresh admission buttons wait for the same explicit recovery required by Owner")
		await _capture(c,"available-"+str(dimensions.x)+( "-lost" if lost else ""))
	c.h.lose_cleanup = lost
	if lost: await c.app._story_lobby_action("terminal")
	else: await _click_recovery(c)
	if lost:
		_check(c.owner.terminal_recovery().get("phase") == "pending" and not c.owner.bound_campaign().is_empty() and c.online.last_room() == c.anchor,"An unknown cleanup response preserves durable recovery and selection")
		_check(_button(c.app.overlay,"Finish recovery") != null,"The exact cleanup retry stays reachable after a lost reply")
		await _capture(c,"pending")
		c.h.lose_cleanup = false
		await c.app._story_lobby_action("terminal")
	var submitted := _cleanup_posts(c)
	_check(submitted.size() == (2 if lost else 1) and Canonical.same(submitted[0].body,{"schema_version":1}),"Only the explicit exact cleanup POST is submitted")
	if lost: _check(Canonical.same(submitted[0],submitted[1]),"Retry preserves the original cleanup path and body")
	_check(c.owner.bound_campaign().is_empty() and c.online.last_room().is_empty() and c.online.coordinator == null,"Typed durable cleanup clears the matching navigation pointers")
	_check(Canonical.same(room_before,c.h.store.saved[_room_scope(c.anchor)]) and Canonical.same(control_before,c.h.store.saved[_journal(c.anchor)]),"Main recovery preserves raw saved turn and campaign journals")
	_check(c.app.mode == "story_lobby" and not is_instance_valid(c.app.relay_child) and c.app._campaign_depart_for_ordinary(),"Recovery releases ordinary navigation without starting gameplay")
	_check(_button(c.app.overlay,"Test story") == null,"Retained classification history does not leave a removed story as a clickable saved row")
	_check(not _button(c.app.overlay,"Start").disabled and not _button(c.app.overlay,"Join").disabled,"Settled recovery restores fresh admission controls")
	await _dispose_ui(c)

func _back_during_cleanup() -> void:
	var c := await _terminal_setup()
	await c.app._show_story()
	c.h.pause_cleanup = true
	c.app._story_lobby_action.call_deferred("terminal")
	for frame in range(12):
		await process_frame
		if c.h.cleanup_started: break
	_check(c.h.cleanup_started and c.app._campaign_action_busy,"The explicit cleanup request owns only its current UI action")
	c.app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(c.app.mode == "journey" and not c.app._campaign_action_busy,"Android Back leaves the recovery screen while preserving service intent")
	c.h.release.emit()
	for frame in range(12): await process_frame
	_check(c.app.mode == "journey" and not is_instance_valid(c.app.relay_child) and c.owner.bound_campaign().is_empty(),"A late cleanup result settles durably without reopening a screen")
	await _dispose_ui(c)

func _local_pointer_retry() -> void:
	var c := await _terminal_setup()
	await c.app._show_story()
	c.h.store.fail_scope = _lobby()
	await c.app._story_lobby_action("terminal")
	_check(c.owner.terminal_anchor_released(c.anchor) and c.owner.terminal_recovery().get("phase") == "retiring" and _button(c.app.overlay,"Finish recovery") != null,"Failed Owner pointer save keeps receipt-backed local recovery visible")
	_check(c.app._campaign_message() == c.app.PlayerCopy.MAIN_EC79109D7607,"Unfinished local retirement uses the existing local-cleanup message")
	var count: int = _cleanup_posts(c).size()
	await _capture(c,"retiring")
	var calls: int = c.h.calls.size()
	c.viewport.queue_free()
	await process_frame
	await process_frame
	var cold := _cold(c)
	c.online = cold.online
	c.owner = cold.owner
	c.merge(_main_for(c),true)
	c.app._draw_story_lobby()
	_check(c.owner.terminal_recovery().get("phase") == "retiring" and _button(c.app.overlay,"Finish recovery") != null and c.h.calls.size() == calls,"An actual cold Main restores saved terminal recovery before any child or automatic request")
	c.h.store.fail_scope = ""
	await c.app._story_lobby_action("terminal")
	_check(_cleanup_posts(c).size() == count and c.owner.bound_campaign().is_empty(),"A local pointer retry uses the saved receipt without another cleanup POST")
	await _dispose_ui(c)

func _receipt_write_retry() -> void:
	var c := await _terminal_setup()
	await c.app._show_story()
	c.h.pause_cleanup = true
	c.app._story_lobby_action.call_deferred("terminal")
	for frame in range(12):
		await process_frame
		if c.h.cleanup_started: break
	c.h.store.fail_scope = "relay-campaign-terminal-v1:"+HOST
	c.h.release.emit()
	for frame in range(12): await process_frame
	_check(not c.owner.terminal_anchor_released(c.anchor) and c.owner.terminal_recovery().get("phase") == "pending" and not c.owner.bound_campaign().is_empty(),"An unsaved server receipt cannot retire a native story or clear its retry")
	c.h.store.fail_scope = ""
	c.h.pause_cleanup = false
	await c.app._story_lobby_action("terminal")
	_check(_cleanup_posts(c).size() == 2 and c.owner.bound_campaign().is_empty(),"The explicit saved request recovers a receipt write failure")
	await _dispose_ui(c)

func _cleanup_posts(c: Dictionary) -> Array:
	return c.h.calls.filter(func(call: Dictionary): return call.method == HTTPClient.METHOD_POST and str(call.path).ends_with("/reconcile-deletion"))

func _other_story_preserved() -> void:
	var c := await _terminal_setup(false)
	c.h.removed = false
	_check(c.owner.release_for_ordinary(),"The earlier story is retained as history before another story opens")
	var invitation := "CD".repeat(10)
	var anchor := ("v2:"+invitation).sha256_text().substr(0,22)
	c.h.view = fixture.active_view.duplicate(true)
	c.h.view.campaign_room_id = anchor
	c.h.view.invite_code = invitation
	c.h.view.chapters[0].room_id = anchor
	c.h.rooms[anchor] = _room("high-and-low",anchor,false)
	_check(c.owner.bind_campaign(anchor,Protocol.key(fixture.definition)) and await c.owner.refresh() and await c.owner.select_current() and c.owner.adopt_selected(),"A second real story owns a separate native room")
	_check(not await c.online.coordinator.commit(_json("res://tests/fixtures/cooperative/upper-path-a.json")),"The other story retains its own interrupted contribution")
	var pending: Dictionary = c.online.coordinator.pending()
	var coordinator: RefCounted = c.online.coordinator
	var before: Dictionary = c.h.store.saved[_room_scope(anchor)].duplicate(true)
	c.h.removed = true
	c.h.removed_anchor = c.anchor
	await c.app._show_story()
	var resume := _button(c.app.overlay,"Resume")
	_check(resume != null and not resume.disabled and _button(c.app.overlay,"Finish recovery") != null and _button(c.app.overlay,"Copy invitation") != null,"The other story's Resume and invitation remain available beside recovery of removed history")
	await c.app._story_lobby_action("terminal")
	resume = _button(c.app.overlay,"Resume")
	_check(c.owner.bound_campaign().get("campaign_room_id") == anchor and c.online.last_room() == anchor and c.online.coordinator == coordinator and resume != null and not resume.disabled,"Recovering a removed story preserves the unrelated bound story and Resume")
	_check(Canonical.same(pending,coordinator.pending()) and Canonical.same(before,c.h.store.saved[_room_scope(anchor)]),"The other story's exact pending contribution remains byte-equivalent")
	await _capture(c,"other-story-preserved")
	await _dispose_ui(c)

func _click_recovery(c: Dictionary) -> void:
	await _settle()
	var button := _button(c.app.overlay,"Finish recovery")
	_check(button != null and not button.disabled,"The real recovery button is ready before native input")
	if button == null: return
	var point := button.get_global_rect().get_center()
	var clicked: Array = []
	button.pressed.connect(func(): clicked.append(true))
	_pointer(c.viewport,point,true)
	_pointer(c.viewport,point,false)
	for frame in range(24):
		await process_frame
		if not clicked.is_empty() and not c.app._campaign_action_busy: break
	_check(clicked.size() == 1 and not c.app._campaign_action_busy,"Actual viewport input triggers exactly one recovery action and settles")

func _capture(c: Dictionary, name: String) -> void:
	var directory := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): directory = argument.trim_prefix("--capture-dir=")
	if directory.is_empty(): return
	c.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK and c.viewport.get_texture().get_image().save_png(directory.path_join(name+".png")) == OK,"Native recovery screen capture saved: "+name)

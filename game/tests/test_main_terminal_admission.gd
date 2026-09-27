extends "res://tests/test_main_terminal_recovery.gd"
## Actual Main buttons, Owner, mapping and cleanup services. Only network replies
## and the Store are injected; no campaign view or server result is inferred.
const AdmissionMapping = preload("res://services/campaign_terminal_admission.gd")
const AdmissionLobby = preload("res://services/campaign_lobby_protocol.gd")

class AdmissionHarness extends TerminalHarness:
	var pause_cancel := false
	var cancel_started := false
	var cancel_observations: Array = []
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		if method == HTTPClient.METHOD_POST and path == "/v2/campaigns":
			busy = true
			calls.append({"method":method,"path":path,"body":body.duplicate(true)})
			await get_tree().process_frame
			busy = false
			return {"ok":false,"status":0,"code":"connection_interrupted"}
		if method == HTTPClient.METHOD_POST and path == "/v2/campaigns/cancel":
			busy = true
			var original_owner := player_id
			var original_body := body.duplicate(true)
			var anchor: String = view.campaign_room_id
			calls.append({"method":method,"path":path,"body":original_body})
			cancel_observations.append(store.saved.duplicate(true))
			cancel_started = true
			if pause_cancel: await release
			else: await get_tree().process_frame
			busy = false
			return {"ok":true,"status":200,"data":{"schema_version":1,"operation":"campaign_terminal_admission","admission":"create","status":"terminal",
				"player_id":original_owner,"idempotency_key":original_body.idempotency_key,
				"request_hash":AdmissionLobby.request_hash(original_owner,"/v2/campaigns",original_body),"campaign_room_id":anchor}}
		return await super.request_json(method,path,body)

func _run() -> void:
	_make_story_fixture()
	await _unknown_create_restart()
	await _mapping_write_failure()
	await _late_cancel(false)
	await _late_cancel(true)
	print("Main terminal admission: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _admission_setup() -> Dictionary:
	var h := AdmissionHarness.new()
	root.add_child(h)
	h.view = fixture.active_view.duplicate(true)
	h.capabilities = Boundaries.campaign_capabilities(fixture.definition)
	h.store.saved["photos:sentinel"] = {"pending":{"asset":"original private photo"}}
	h.store.saved["keepsakes:sentinel"] = {"earned":["existing keepsake"]}
	var online := Online.new(h,h.identity,h.store)
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	_check(await owner.load_campaign_lobby(),"Actual Owner verifies synthetic campaign capabilities before the Main action")
	var c := {"h":h,"online":online,"owner":owner,"anchor":h.view.campaign_room_id}
	c.merge(_main_for(c))
	c.app._draw_story_lobby()
	await _tap_admission(c,"Start")
	var pending: Dictionary = c.owner.pending_lobby()
	_check(not pending.is_empty() and pending.path == "/v2/campaigns" and pending.accepted_campaign.is_empty(),"A real Start click leaves an exact unknown Create after its response is lost")
	_check(not is_instance_valid(c.app.relay_child) and c.owner.bound_campaign().is_empty() and c.online.last_room().is_empty(),"Lost Create does not invent a room binding or open gameplay")
	_check(_button(c.app.overlay,"Cancel") != null and _button(c.app.overlay,"Start") == null,"The saved attempt exposes explicit Cancel without a replacement Start")
	c["request"] = _original_request(pending)
	c["protected"] = {"photos:sentinel":h.store.saved["photos:sentinel"].duplicate(true),"keepsakes:sentinel":h.store.saved["keepsakes:sentinel"].duplicate(true)}
	h.removed = true
	return c

func _unknown_create_restart() -> void:
	var c := await _admission_setup()
	await _tap_admission(c,"Cancel")
	var pending: Dictionary = c.owner.pending_lobby()
	_check(pending.get("cancel_requested",false) and Canonical.same(_original_request(pending),c.request),"Typed terminal correlation retains the original Create and durable Cancel direction")
	var entry := _saved_mapping(c,c.request)
	_check(AdmissionMapping.mapped_anchor(entry,HOST) == c.anchor and entry.get("witness",{}).get("kind") == "server_create","Actual Cancel response is saved with its distinct genuine server witness")
	_check(c.owner.terminal_recovery().get("phase") == "available" and _button(c.app.overlay,"Finish recovery") != null,"Only saved correlation enables explicit Finish recovery")
	_check(_cleanup_posts(c).is_empty() and c.owner.bound_campaign().is_empty() and not is_instance_valid(c.app.relay_child),"Correlation does not automatically clean up, bind or start gameplay")
	var cancel: Array = _admission_posts(c,"/v2/campaigns/cancel")
	_check(cancel.size() == 1 and Canonical.same(cancel[0].body,c.request.body),"Cancel carries the exact original Create body/key")
	_check(c.h.cancel_observations[0][_lobby()].pending.cancel_requested,"Cancel direction was durable before the actual request")
	var saved_map: Dictionary = c.h.store.saved[AdmissionMapping.scope_for(HOST)].duplicate(true)
	var count: int = c.h.calls.size()
	await _restart_admission_main(c)
	_check(c.h.calls.size() == count and c.owner.terminal_recovery().get("phase") == "available","Cold Main restores the mapped recovery locally without repeating Create or Cancel")
	_check(Canonical.same(_original_request(c.owner.pending_lobby()),c.request) and _button(c.app.overlay,"Finish recovery") != null,"Restart preserves both the exact original request and reachable cleanup")
	await _click_recovery(c)
	_check(_cleanup_posts(c).size() == 1 and _admission_posts(c,"/v2/campaigns").size() == 1 and _admission_posts(c,"/v2/campaigns/cancel").size() == 1,"Only the explicit cleanup click sends the typed cleanup request")
	_check(c.owner.terminal_anchor_released(c.anchor) and c.owner.pending_lobby().is_empty(),"Durable typed cleanup permits clearing only the correlated pending admission")
	_check(Canonical.same(saved_map,c.h.store.saved[AdmissionMapping.scope_for(HOST)]) and Canonical.same(_saved_mapping(c,c.request).get("request"),c.request),"Original Create body/key/hash survives pending clearance in the unchanged evidence ledger")
	_check(c.owner.bound_campaign().is_empty() and c.online.last_room().is_empty() and not is_instance_valid(c.app.relay_child),"Terminal recovery leaves no fabricated chapter or adopted room")
	_check(c.app.mode == "story_lobby" and c.app._campaign_depart_for_ordinary(),"Successful recovery releases ordinary navigation while staying on the current screen")
	_check_protected(c)
	count = c.h.calls.size()
	await _restart_admission_main(c)
	_check(c.h.calls.size() == count and c.owner.pending_lobby().is_empty() and c.owner.terminal_recovery().is_empty(),"Second cold restart remains settled without another request")
	_check(AdmissionMapping.mapped_anchor(_saved_mapping(c,c.request),HOST) == c.anchor,"Settled restart still retains exact historical correlation")
	await _dispose_ui(c)

func _mapping_write_failure() -> void:
	var c := await _admission_setup()
	c.h.store.fail_scope = AdmissionMapping.scope_for(HOST)
	await _tap_admission(c,"Cancel")
	var pending: Dictionary = c.owner.pending_lobby()
	_check(_saved_mapping(c,c.request).is_empty() and c.owner.terminal_recovery().is_empty(),"Unsaved correlation exposes neither durable mapping nor terminal recovery")
	_check(pending.get("cancel_requested",false) and Canonical.same(_original_request(pending),c.request),"Mapping failure retains the exact sticky Cancel request")
	_check(_button(c.app.overlay,"Retry") != null and _button(c.app.overlay,"Finish recovery") == null and _cleanup_posts(c).is_empty(),"Failed mapping keeps explicit Retry and never enables cleanup")
	c.h.store.fail_scope = ""
	await _tap_admission(c,"Retry")
	var attempts := _admission_posts(c,"/v2/campaigns/cancel")
	_check(attempts.size() == 2 and Canonical.same(attempts[0],attempts[1]) and _admission_posts(c,"/v2/campaigns").size() == 1,"Retry resends only the identical Cancel, never a replacement Create")
	_check(AdmissionMapping.mapped_anchor(_saved_mapping(c,c.request),HOST) == c.anchor and _button(c.app.overlay,"Finish recovery") != null,"Successful mapping retry exposes the explicit cleanup action")
	await _click_recovery(c)
	_check(c.owner.pending_lobby().is_empty() and Canonical.same(_saved_mapping(c,c.request).get("request"),c.request),"Recovery after disk failure retains raw original admission evidence")
	_check_protected(c)
	await _dispose_ui(c)

func _late_cancel(identity_changes: bool) -> void:
	var c := await _admission_setup()
	c.h.pause_cancel = true
	await _tap_admission(c,"Cancel",false)
	for frame in range(12):
		await process_frame
		if c.h.cancel_started: break
	_check(c.h.cancel_started and c.app._campaign_action_busy,"Actual Cancel click is in flight before lifecycle change")
	var saved_pending: Dictionary = c.h.store.saved[_lobby()].pending.duplicate(true)
	if identity_changes:
		c.h.identity_value.player_id = GUEST
		c.h.identity_value.epoch += 1
		c.h.player_id = GUEST
		c.owner.invalidate_identity()
		c.online.invalidate_identity()
	else:
		c.app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		_check(c.app.mode == "journey" and not c.app._campaign_action_busy,"Native Back retires only the Main action while Cancel remains saved")
	c.h.release.emit()
	for frame in range(18): await process_frame
	_check(not is_instance_valid(c.app.relay_child) and _cleanup_posts(c).is_empty(),"A late correlation never enters a chapter or submits cleanup")
	_check(Canonical.same(c.h.store.saved[_lobby()].pending,saved_pending),"Late completion preserves the original saved Cancel bytes")
	if identity_changes:
		_check(not c.h.store.saved.has(AdmissionMapping.scope_for(HOST)) and not c.h.store.saved.has(AdmissionMapping.scope_for(GUEST)),"Retired identity cannot save old correlation under either owner")
	else:
		_check(c.app.mode == "journey" and AdmissionMapping.mapped_anchor(_saved_mapping(c,c.request),HOST) == c.anchor,"Same-owner late response persists evidence without pulling Main back to Story")
		var count: int = _admission_posts(c,"/v2/campaigns/cancel").size()
		await c.app._show_story()
		_check(_button(c.app.overlay,"Finish recovery") != null and _admission_posts(c,"/v2/campaigns/cancel").size() == count,"Explicit return to Story recovers the mapped action without another Cancel")
	_check_protected(c)
	await _dispose_ui(c)

func _restart_admission_main(c: Dictionary) -> void:
	c.viewport.queue_free()
	await process_frame
	await process_frame
	c.owner.invalidate_identity()
	c.online.invalidate_identity()
	var cold := _cold(c)
	c.online = cold.online
	c.owner = cold.owner
	c.merge(_main_for(c),true)
	c.app._draw_story_lobby()
	await _settle()

func _original_request(pending: Dictionary) -> Dictionary:
	return {"path":pending.get("path"),"body":pending.get("body",{}).duplicate(true),"request_hash":pending.get("request_hash")}

func _saved_mapping(c: Dictionary, request: Dictionary) -> Dictionary:
	var ledger: Dictionary = c.h.store.saved.get(AdmissionMapping.scope_for(HOST),{})
	for entry: Dictionary in ledger.get("mappings",[]):
		if Canonical.same(entry.get("request"),request): return entry.duplicate(true)
	return {}

func _admission_posts(c: Dictionary, path: String) -> Array:
	return c.h.calls.filter(func(call: Dictionary): return call.method == HTTPClient.METHOD_POST and call.path == path)

func _check_protected(c: Dictionary) -> void:
	for scope: String in c.protected:
		_check(Canonical.same(c.h.store.saved.get(scope),c.protected[scope]),"Admission recovery preserves unrelated saved evidence: "+scope)

func _tap_admission(c: Dictionary, label: String, wait_for_reply: bool = true) -> void:
	await _settle()
	var button := _button(c.app.overlay,label)
	_check(button != null and not button.disabled and button.is_visible_in_tree(),"Actual Main action is visible and enabled: "+label)
	if button == null: return
	var rect := button.get_global_rect()
	var scroll: Node = button.get_parent()
	while scroll != null and not scroll is ScrollContainer: scroll = scroll.get_parent()
	_check(c.viewport.get_visible_rect().encloses(rect) and (scroll == null or scroll.get_global_rect().encloses(rect)),"Actual Main action lies inside its viewport/scroll clip: "+label)
	var clicked: Array = []
	button.pressed.connect(func(): clicked.append(true))
	_pointer(c.viewport,rect.get_center(),true)
	_pointer(c.viewport,rect.get_center(),false)
	if wait_for_reply:
		for frame in range(40):
			await process_frame
			if not clicked.is_empty() and not c.app._campaign_action_busy: break
		_check(not c.app._campaign_action_busy,"Main action settles after its injected response: "+label)
	_check(clicked.size() == 1,"Viewport input invokes the actual Main button exactly once: "+label)

extends "res://tests/test_campaign_owned_restore.gd"
## Real Main/owner/Flow/Preview composition; transport and content are synthetic.
const MainSource = preload("res://main.gd")
const StorySource = preload("res://services/campaign_story.gd")
const LobbyTests = preload("res://tests/test_campaign_lobby_owner.gd")
const CancelTests = preload("res://tests/test_campaign_lobby_cancel.gd")
const CameraHold = preload("res://presentation/story_camera.gd")
var story_content: Dictionary

class SilentSound:
	extends Node
	func set_backgrounded(_value: bool) -> void: pass

class UiMain:
	extends "res://main.gd"
	var harness: Node
	var notices: Array[String] = []
	func _ready() -> void:
		_build_theme()
		_build_ui()
		world = Node3D.new()
		add_child(world)
		soundscape = SilentSound.new()
		add_child(soundscape)
		set_process(false)
		set_physics_process(false)
	func _relay_identity() -> Dictionary: return harness.identity()
	func _ensure_identity() -> bool: return harness.identity().ready
	func _sync_presence() -> void:
		if is_instance_valid(relay_child):
			relay_child.set_process(false)
			relay_child.set_physics_process(false)
	func _show_home() -> void: mode = "home"
	func _show_settings() -> void: mode = "settings" # Store SDK is outside this UI return-state harness.
	func _full_journey_access() -> bool: return false # This harness has no purchase SDK.
	func _toast(message: String) -> void: notices.append(message)
	func _turn_notification_status() -> Dictionary: return {"enabled":false,"registered":false,"busy":false,"message":""}

class UiHarness:
	extends CancelTests.CancelHarness
	var delay_next := false
	var continue_result: Dictionary = {}
	var continue_error: Dictionary = {}
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		if delay_next:
			delay_next = false
			await release
		if method == HTTPClient.METHOD_GET and "/operations/" in path and not continue_result.is_empty():
			calls.append({"method":method,"path":path,"body":body.duplicate(true)})
			await get_tree().process_frame
			return {"ok":false,"status":404,"code":"operation_not_found"}
		if method == HTTPClient.METHOD_POST and path.ends_with("/continue") and not continue_result.is_empty():
			calls.append({"method":method,"path":path,"body":body.duplicate(true)})
			await get_tree().process_frame
			if not continue_error.is_empty(): return continue_error.duplicate(true)
			var result := continue_result.duplicate(true)
			result.receipt.player_id = player_id
			result.receipt.idempotency_key = body.idempotency_key
			result.receipt.request_hash = Protocol.request_hash(view.campaign_room_id,player_id,body)
			view = result.campaign.duplicate(true)
			return {"ok":true,"status":200,"data":result}
		return await super.request_json(method,path,body)

func _run() -> void:
	_make_story_fixture()
	await _lobby_admission(false)
	await _lobby_admission(true)
	await _back_during_request(false)
	await _back_during_request(true)
	await _lost_create()
	await _cancel_admission(false)
	await _cancel_admission(true)
	await _accepted_cancel_ui()
	await _legacy_join_hold()
	await _late_b_main()
	await _continue_button()
	await _terminal_main()
	await _terminal_main(true)
	for state: String in ["pending","activation","continuing"]: await _explicit_control_recovery(state)
	await _departure_holds()
	await _ordinary_pending_reopen(false)
	await _ordinary_pending_reopen(true)
	await _access_return()
	await _bound_resume_layout()
	await _paid_continue_access()
	await _story_drag()
	print("Main Story composition: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _make_story_fixture() -> void:
	fixture = _json("res://tests/fixtures/campaign/control-v2.json")
	story_content = {"schema_version":1,"story_id":"main-story-test","story_version":1,"content_hash":"","title":"Test story","summary":"Synthetic dialogue","chapters":[]}
	for pin: Dictionary in fixture.definition.chapters:
		story_content.chapters.append({"level_id":pin.level_id,"level_version":pin.level_version,"arrival":[{"speaker":"p0","text":"First test line."},{"speaker":"p1","text":"Second test line."}],"completion":[{"speaker":"p1","text":"Completed test line."}]})
	var content_body := story_content.duplicate(true)
	content_body.erase("content_hash")
	story_content.content_hash = Canonical.digest(content_body)
	fixture.definition.story = StorySource.pin(story_content)
	var body: Dictionary = fixture.definition.duplicate(true)
	body.erase("definition_hash")
	fixture.definition.definition_hash = Canonical.digest(body)
	_replace_key(fixture,Protocol.key(fixture.definition))

func _replace_key(value: Variant, key: Dictionary) -> void:
	if value is Dictionary:
		if value.has("campaign_key"): value["campaign_key"] = key.duplicate(true)
		for field: Variant in value.keys():
			if field != "campaign_key": _replace_key(value[field],key)
	elif value is Array:
		for item: Variant in value: _replace_key(item,key)

func _main_for(c: Dictionary) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var app := UiMain.new()
	app.harness = c.h
	app.api = c.h
	app.saves.data = {"settings":{"sound":false,"music":false,"reduced_motion":true},"completed":[],"pending_turn":{},"room_draft":{}}
	app.relay_session = c.online
	app.campaign_owner = c.owner
	app.campaign_catalog = [{"definition":fixture.definition.duplicate(true),"story":story_content.duplicate(true)}]
	viewport.add_child(app)
	app.mode = "story_lobby"
	# Replace only the constructor-supplied pure UI observer, using the actual
	# Main boundary for all subsequent owner operations in this harness.
	c.owner._leave_ready = app._campaign_leave_ready
	return {"app":app,"viewport":viewport}

func _cold(c: Dictionary) -> Dictionary:
	var cold:=super._cold(c)
	# These direct Main-entry fixtures skip the ordinary Story capability GET.
	# Model its exact accepted capability value under the current transport gate.
	cold.online.capabilities=Boundaries.campaign_capabilities(fixture.definition)
	return cold

func _lobby_setup(guest: bool = false) -> Dictionary:
	var h := UiHarness.new()
	root.add_child(h)
	h.view = fixture.active_view.duplicate(true)
	if guest:
		h.player_id = GUEST
		h.identity_value.player_id = GUEST
		h.view.player_slot = "p1"
		h.view.invite_code = null
		h.view.invite_expires_at = null
		h.post_status = 200
	h.capabilities = {"api_version":2,"simulation_version":2,"recording_version":2,"mutations_enabled":true,"validation":"structural_client_replay_required","chapters":[],"campaign_control_version":2,"campaign_creation_enabled":true,"campaign_mutations_enabled":true,"campaign_definitions":[fixture.definition.duplicate(true)]}
	var anchor: String = h.view.campaign_room_id
	h.rooms[anchor] = _room("high-and-low",anchor,false)
	if guest:
		h.rooms[anchor].player_slot = "p1"
		h.rooms[anchor].erase("invite_code")
	var online := Online.new(h,h.identity,h.store)
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	_check(await owner.load_campaign_lobby(),"Real owner loads the synthetic Story capability and list")
	var c := {"h":h,"online":online,"owner":owner,"anchor":anchor}
	c.merge(_main_for(c))
	return c

func _lobby_admission(guest: bool) -> void:
	var c := await _lobby_setup(guest)
	c.app._draw_story_lobby()
	await process_frame
	_check(_button(c.app.overlay,"Start") != null and _button(c.app.overlay,"Join") != null,"Actual Story lobby presents Start and Join")
	var before: int = c.h.calls.size()
	await c.app._story_lobby_action("join" if guest else "create",Protocol.key(fixture.definition),"AB".repeat(10))
	_check(c.app.mode == "relay_online" and is_instance_valid(c.app.relay_child),"Accepted lobby response opens the actual native first chapter")
	_check(not c.app.relay_child.running and c.app.campaign_flow.busy(),"Arrival is attached before Ready and never starts a recording")
	_check(c.online.last_room() == c.anchor and c.owner.selected_room() == c.anchor,"Both durable selections belong to the accepted campaign")
	var posts: Array = c.h.calls.slice(before).filter(func(call: Dictionary): return call.method == HTTPClient.METHOD_POST)
	_check(posts.size() == 1 and posts[0].path == ("/v2/campaigns/join" if guest else "/v2/campaigns"),"Only the intended Story admission endpoint receives one POST")
	c.app.campaign_flow._panel._skip()
	c.app.relay_child._leave()
	_check(c.app.mode == "story_lobby" and not c.owner.bound_campaign().is_empty(),"Back returns to Story and retains its durable owner")
	await _dispose_ui(c)

func _back_during_request(post: bool) -> void:
	var c := await _lobby_setup()
	c.app._draw_story_lobby()
	c.h.delay_next = true
	c.app._story_lobby_action.call_deferred("create" if post else "refresh",Protocol.key(fixture.definition))
	await process_frame
	_check(c.app._campaign_action_busy,"Delayed Story request owns the UI busy token")
	c.app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(c.app.mode == "journey" and not c.app._campaign_action_busy,"Actual Android Back retires UI busy ownership without canceling the saved service request")
	c.h.release.emit()
	for i in range(8): await process_frame
	_check(c.app.mode == "journey" and not is_instance_valid(c.app.relay_child),"A late reply does not pull the player back into gameplay")
	await c.app._show_story()
	_check(c.app.mode == "story_lobby" and not c.app._campaign_action_busy,"Story can be entered again after the old request settles")
	if post: _check(not c.owner.bound_campaign().is_empty(),"Accepted admission remains durably resumable after Back")
	await _dispose_ui(c)

func _lost_create() -> void:
	var c := await _lobby_setup()
	c.h.fail_post = true
	await c.app._story_lobby_action("create",Protocol.key(fixture.definition))
	var pending: Dictionary = c.owner.pending_lobby()
	_check(not pending.is_empty() and _button(c.app.overlay,"Retry") != null and _button(c.app.overlay,"Start") == null,"An unknown admission exposes one saved Retry and no replacement Start")
	var count: int = c.h.calls.size()
	c.app._story_back()
	_check(not c.app._campaign_depart_for_ordinary() and c.h.calls.size() == count and Canonical.same(pending,c.owner.pending_lobby()),"Ordinary departure cannot clear or resend an unknown Story request")
	c.h.fail_post = false
	await c.app._show_story()
	await c.app._story_lobby_action("retry")
	var posts: Array = c.h.calls.filter(func(call: Dictionary): return call.method == HTTPClient.METHOD_POST)
	_check(posts.size() == 2 and Canonical.same(posts[0],posts[1]),"Visible Retry uses the original endpoint, body and idempotency key")
	await _dispose_ui(c)

func _late_b_main() -> void:
	var c := await _make()
	c.h.rooms[c.anchor] = _prepare_b(c)
	_check(await c.online.coordinator.refresh(),"Late-B UI fixture verifies its native source A")
	_check(not await c.online.coordinator.commit(_json("res://tests/fixtures/cooperative/down-and-around-b.json")),"Final B has an actual saved unknown response")
	var pending: Dictionary = c.online.coordinator.pending()
	var complete := _room("high-and-low",c.anchor,true)
	complete.revision = 5
	c.h.rooms[c.anchor] = complete
	c.h.view = fixture.accepted_result.campaign.duplicate(true)
	_check(await c.owner.refresh(),"Partner's next publication is retained before late B receipt")
	var cold := _cold(c)
	c.online = cold.online
	c.owner = cold.owner
	c.merge(_main_for(c))
	await c.app._story_lobby_action("resume")
	var source: Node = c.app.relay_child
	_check(source.mode == "campaign_recovery" and not source.journey.pending().is_empty(),"Cold Main opens the exact historical child behind recovery controls")
	source._begin()
	_check(not source.running and _button(source.overlay,"Record") == null,"Historical pending recovery cannot expose or begin Record")
	c.h.operation_reply = {"ok":true,"status":200,"data":_b_receipt(pending,complete)}
	var calls: int = c.h.calls.size()
	await _click_control(c,"Check saved turn")
	for frame in range(120):
		await process_frame
		if c.app.campaign_flow.busy(): break
	_check(c.app.relay_child == source and source.mode == "complete" and c.app.campaign_flow._panel.is_open(),"Late B retains its actual completed source until completion dialogue closes")
	_check(c.app.campaign_flow._active.phase == "completion" and c.online.last_room() == c.anchor,"Target verification does not adopt before the source passage")
	_check(c.h.calls.slice(calls).all(func(call: Dictionary): return call.method == HTTPClient.METHOD_GET),"Accepted-B receipt and target verification use only GETs")
	c.app.campaign_flow._panel._advance()
	_check(c.app.relay_child != source and c.app.campaign_flow._active.phase == "arrival" and c.online.last_room() == c.target,"Dismissing completion synchronously adopts before the next arrival")
	await _dispose_ui(c)

func _terminal_main(pending_finish: bool = false) -> void:
	var c := await _make()
	c.h.view = fixture.accepted_result.campaign.duplicate(true)
	_check(await c.owner.refresh() and await c.owner.select_current() and c.owner.adopt_selected(),"Terminal Main fixture owns the final chapter")
	var complete := _room("rolling-home",c.target,true)
	complete.revision = 5
	c.h.rooms[c.target] = complete
	_check(await c.online.coordinator.refresh(),"Terminal world derives from accepted native pairs")
	if pending_finish:
		_check(not await c.owner.continue_current() and not c.owner.pending().is_empty(),"An unknown Finish retains its exact request before a later complete publication")
	var publication: Dictionary = c.h.view.duplicate(true)
	publication.revision = 6
	publication.state = "complete"
	publication.chapters[1].completion = {"source_revision":5,"source_branch":0,"checkpoint_hash":complete.checkpoint.checkpoint_hash,"transition_id":"e".repeat(64),"from_campaign_revision":4,"accepted_campaign_revision":6}
	c.h.view = publication
	_check(await c.owner.refresh(),"Terminal publication is validated by the actual campaign protocol")
	c.merge(_main_for(c))
	await c.app._story_lobby_action("resume")
	var child: Node = c.app.relay_child
	var count: int = c.h.calls.size()
	if pending_finish:
		var pending: Dictionary=c.owner.pending()
		_check(_button(child.overlay,"Read story")==null and _button(child.overlay,"Retry")!=null,"Saved Finish uncertainty is labelled Retry even after published completion")
		await _click_control(c,"Retry")
		for frame in range(120):
			await process_frame
			if not c.app._campaign_action_busy: break
		_check(Canonical.same(pending,c.owner.pending()) and c.app.relay_child==child and not c.app.campaign_flow.busy(),"Unknown exact Finish retry stays on its retained final world")
		await _dispose_ui(c)
		return
	var explorer: Node=child.world.camera_exploration
	explorer.manual=true
	explorer.set_process(false)
	explorer.zoom_ratio=0.84
	explorer.pan=Vector2(0.07,-0.03)
	explorer._returning=true
	explorer._return_age=0.2
	explorer._return_zoom=0.78
	explorer._return_pan=Vector2(0.12,-0.05)
	explorer.apply_frame()
	child.world.set_process(false)
	var hold:=CameraHold.new()
	var camera_before: Dictionary=hold._capture_fields(child.world.camera,["global_transform","size","keep_aspect","h_offset","v_offset","projection","fov"])
	var exploration_before: Dictionary=hold._capture_fields(explorer,CameraHold.EXPLORATION_FIELDS)
	var follow_before: Dictionary=hold._capture_fields(child.world,CameraHold.FOLLOW_FIELDS)
	await _click_control(c,"Read story")
	_check(c.app.campaign_flow.busy() and c.app.campaign_flow._active.purpose == "finale","Read story presents the exact retained final scene")
	var old_token: int=child._story_hold
	c.app.campaign_flow._panel._advance()
	await _settle()
	_check(c.app.relay_child == child and c.owner.view().state == "complete" and c.h.calls.size() == count,"Final dismissal keeps both native scene and campaign terminal without HTTP")
	_check(hold._capture_fields(child.world.camera,["global_transform","size","keep_aspect","h_offset","v_offset","projection","fov"])==camera_before and hold._capture_fields(explorer,CameraHold.EXPLORATION_FIELDS)==exploration_before and hold._capture_fields(child.world,CameraHold.FOLLOW_FIELDS)==follow_before,"Actual Main completion and deferred action refresh preserve the exact camera, exploration return and follow state")
	_check(not _button(child.overlay,"Read story").disabled and not _button(child.overlay,"History").disabled,"Final dismissal restores reachable Read story and History controls")
	await _click_control(c,"History")
	var history_card: Node=child.overlay.get_child(0)
	child.release_story(old_token)
	await _settle()
	_check(child.mode=="story_history" and child.overlay.get_child(0)==history_card,"Old story release cannot redraw the later History card")
	await _click_control(c,"Back")
	await _click_control(c,"Read story")
	_check(c.app.campaign_flow._active.purpose == "history","After acknowledgement Read story explicitly rereads instead of becoming a dead button")
	await _dispose_ui(c)

func _departure_holds() -> void:
	var c := await _make()
	c.merge(_main_for(c))
	var count: int = c.h.calls.size()
	_check(not c.app._campaign_notification_unbound() and c.h.calls.size() == count,"Automatic notification routing cannot silently release a bound Story")
	_check(c.app._campaign_depart_for_ordinary() and c.owner.bound_campaign().is_empty(),"A stable explicit ordinary departure releases the owner locally")
	_check(c.h.calls.size() == count,"Ordinary departure never makes a speculative network request")
	await _dispose_ui(c)

func _access_return() -> void:
	var c:=await _lobby_setup()
	var count:int=c.h.calls.size()
	c.app._show_story_access()
	_button(c.app.overlay,"Back").pressed.emit()
	_check(c.app.mode=="story_lobby" and not c.app._story_access_return,"Leaving Hosting access directly does not arm a later Settings return")
	c.app._show_story_access()
	_button(c.app.overlay,"Settings").pressed.emit()
	_check(c.app.mode=="settings" and c.app._story_access_return,"Only the actual Hosting access Settings control arms Story return")
	c.app._story_settings_done()
	_check(c.app.mode=="story_lobby" and not c.app._story_access_return,"Done consumes the exact Story Settings return once")
	c.app._show_settings()
	c.app._story_settings_done()
	_check(c.app.mode=="home" and c.h.calls.size()==count,"A later ordinary Settings Done returns Home with no account or purchase request")
	await _dispose_ui(c)

func _bound_resume_layout() -> void:
	var c:=await _lobby_setup()
	await c.app._story_lobby_action("create",Protocol.key(fixture.definition))
	c.app.campaign_flow._panel._skip()
	c.app._leave_story_child()
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(960,540)]:
		c.viewport.size=dimensions
		c.app._refresh_safe_area()
		c.app._draw_story_lobby()
		await _settle()
		var resume:=_button(c.app.overlay,"Resume")
		var fresh:=_button(c.app.overlay,"Start")
		var scroll: Node=resume.get_parent()
		while not scroll is ScrollContainer: scroll=scroll.get_parent()
		_check(not resume.disabled and scroll.get_global_rect().encloses(resume.get_global_rect()) and c.viewport.get_visible_rect().encloses(resume.get_global_rect()) and resume.get_global_rect().end.y<=fresh.get_global_rect().position.y,"Bound Story Resume is immediately visible before new Start/Join: "+str(dimensions))
	c.h.fail_post=true
	await c.app._story_lobby_action("create",Protocol.key(fixture.definition))
	_check(not c.owner.pending_lobby().is_empty() and not c.owner.bound_campaign().is_empty(),"A separate unknown admission retains the existing bound story")
	await _settle()
	var retry:=_button(c.app.overlay,"Retry")
	var scroll: Node=retry.get_parent()
	while not scroll is ScrollContainer: scroll=scroll.get_parent()
	_check(not retry.disabled and scroll.get_global_rect().encloses(retry.get_global_rect()) and _button(c.app.overlay,"Resume").disabled and retry.get_global_rect().end.y<_button(c.app.overlay,"Resume").get_global_rect().position.y,"Saved admission Retry precedes disabled bound Resume and remains visible in the small viewport")
	c.h.fail_cancel=true
	await c.app._story_lobby_action("cancel")
	await _settle()
	retry=_button(c.app.overlay,"Retry")
	scroll=retry.get_parent()
	while not scroll is ScrollContainer: scroll=scroll.get_parent()
	_check(c.owner.pending_lobby().cancel_requested and scroll.get_global_rect().encloses(retry.get_global_rect()) and _button(c.app.overlay,"Cancel")==null,"Sticky cancellation recovery stays first even with an existing bound story")
	await _dispose_ui(c)

func _paid_continue_access() -> void:
	var c:=await _accepted_setup()
	c.h.continue_error={"ok":false,"status":402,"code":"host_unlock_required"}
	await _click_control(c,"Continue story")
	for frame in range(120):
		await process_frame
		if not c.app._campaign_action_busy: break
	var pending: Dictionary=c.owner.pending()
	var bound: Dictionary=c.owner.bound_campaign()
	_check(not pending.is_empty() and _button(c.app.relay_child.overlay,"Hosting access")!=null,"Paid next-chapter denial retains its exact Continue and exposes Hosting access")
	await _click_control(c,"Hosting access")
	_check(c.app.mode=="story_access" and Canonical.same(pending,c.owner.pending()) and Canonical.same(bound,c.owner.bound_campaign()),"Hosting access closes only presentation, preserving the denied request and campaign")
	_button(c.app.overlay,"Settings").pressed.emit()
	c.app._story_settings_done()
	_check(c.app.mode=="story_lobby" and Canonical.same(pending,c.owner.pending()),"Returning from Settings keeps the same pending Continue")
	await c.app._story_lobby_action("resume")
	_check(is_instance_valid(c.app.relay_child) and _button(c.app.relay_child.overlay,"Retry")!=null and Canonical.same(pending,c.owner.pending()),"Explicit Resume returns to the same source Retry without a new submission")
	_check(c.app.relay_child.journey.campaign_recovery_only() and _button(c.app.relay_child.overlay,"Record")==null,"Pending Continue keeps fresh gameplay held while exposing exact Retry")
	c.h.continue_error={}
	await _click_control(c,"Retry")
	for frame in range(120):
		await process_frame
		if c.app.campaign_flow.busy(): break
	var posts: Array=c.h.calls.filter(func(call: Dictionary):return call.method==HTTPClient.METHOD_POST and call.path.ends_with("/continue"))
	_check(posts.size()==2 and Canonical.same(posts[0].body,posts[1].body) and c.app.campaign_flow.busy(),"After access recovery, Retry reuses the original exact Continue and opens its verified handoff")
	await _dispose_ui(c)

func _story_drag() -> void:
	var c := await _lobby_setup()
	_check(c.owner.bind_campaign(c.anchor,Protocol.key(fixture.definition)) and await c.owner.refresh(),"Drag fixture has a retained real campaign row")
	c.app._draw_story_lobby()
	await process_frame
	await process_frame
	var scroll: ScrollContainer = c.app.overlay.find_children("*","ScrollContainer",true,false)[0]
	var button := _button(scroll,"Start")
	_check(button.mouse_filter == Control.MOUSE_FILTER_PASS,"Story's nested action button passes touch drags to its scroll body")
	var original_touch_emulation := Input.emulate_touch_from_mouse
	# Match the real native gesture setup used by test_scroll_lists, including
	# Headless CI. Missing gesture support still fails rather than skipping.
	Input.emulate_touch_from_mouse = true
	if DisplayServer.is_touchscreen_available():
		scroll.ensure_control_visible(button)
		await process_frame
		var count: int = c.h.calls.size()
		await _drag(c.viewport,button.get_global_rect().get_center(),Vector2(0,-130))
		_check(scroll.scroll_vertical > 0 and c.h.calls.size() == count and c.app.mode == "story_lobby","Actual native drag beginning on Start scrolls without admission")
	else:
		_check(false,"Story drag acceptance requires the touch-emulated DisplayServer used by existing scroll tests")
	Input.emulate_touch_from_mouse = original_touch_emulation
	_check(Input.emulate_touch_from_mouse == original_touch_emulation,"Story drag restores the process input setting")
	var back := _button(c.app.overlay,"Back")
	_check(c.viewport.get_visible_rect().encloses(back.get_global_rect()),"Back remains visible outside the bounded story list")
	await _dispose_ui(c)

func _ordinary_pending_reopen(cold: bool) -> void:
	var h := UiHarness.new()
	root.add_child(h)
	var room: String = fixture.active_view.campaign_room_id
	var other: String = fixture.accepted_result.campaign.chapters[1].room_id
	h.rooms[room] = _room("high-and-low",room,false)
	h.rooms[other] = _room("rolling-home",other,false)
	var online := Online.new(h,h.identity,h.store)
	_check(await online.open_room(room),"Ordinary recovery fixture verifies its real initial native room")
	online.capabilities = Boundaries.campaign_capabilities(fixture.definition)
	_check(not await online.coordinator.commit(_json("res://tests/fixtures/cooperative/upper-path-a.json")),"Lost ordinary native contribution remains pending")
	var pending: Dictionary = online.coordinator.pending()
	_check(not pending.is_empty(),"Ordinary fixture retains the exact pending key and recording")
	if cold: online = Online.new(h,h.identity,h.store)
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	_check(owner.restore_owner() and owner.bound_campaign().is_empty() and owner.pending_lobby().is_empty(),"A warm or cold empty campaign owner has no departure authority")
	var c := {"h":h,"online":online,"owner":owner}
	c.merge(_main_for(c))
	c.app.mode = "relay_rooms"
	c.app.selected_online_chapter = "high-and-low@1"
	await c.app._relay_lobby_action("open",other)
	_check(not is_instance_valid(c.app.relay_child) and c.online.last_room() == room and Canonical.same(c.online.coordinator.pending(),pending),"Ordinary Online still blocks switching away from its saved contribution")
	await c.app._relay_lobby_action("open",room)
	_check(is_instance_valid(c.app.relay_child) and c.app.relay_child.mode == "online_waiting" and Canonical.same(c.app.relay_child.journey.pending(),pending),"Actual Main reopens the selected ordinary room for exact pending recovery")
	_check(owner.bound_campaign().is_empty() and owner.pending_lobby().is_empty(),"Ordinary recovery does not bind or create campaign intent")
	await _dispose_ui(c)

func _button(node: Node, text: String) -> Button:
	for value: Button in node.find_children("*","Button",true,false):
		if value.text == text: return value
	return null

func _dispose_ui(c: Dictionary) -> void:
	c.viewport.queue_free()
	await process_frame
	await process_frame
	c.h.free()


# Same native gesture path used by the retained scroll-list regression.
func _pointer(viewport: Viewport, position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	viewport.push_input(event, true)


func _drag(viewport: Viewport, start: Vector2, distance: Vector2) -> void:
	_pointer(viewport, start, true)
	for step: int in range(1, 9):
		var event := InputEventMouseMotion.new()
		event.position = start + distance * float(step) / 8.0
		event.global_position = event.position
		event.relative = distance / 8.0
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		viewport.push_input(event, true)
	_pointer(viewport, start + distance, false)
	await _settle()


func _settle() -> void:
	await process_frame
	await process_frame



func _explicit_control_recovery(state: String) -> void:
	var c := await _make()
	var complete := _room("high-and-low",c.anchor,true)
	complete.revision = 5
	c.h.rooms[c.anchor] = complete
	_check(await c.online.coordinator.refresh(), "Control recovery fixture verifies the real completed source: "+state)
	var pending := {}
	if state == "pending":
		_check(not await c.owner.continue_current(), "A lost actual Continue leaves its exact durable request")
		pending = c.owner.pending()
		_check(not pending.is_empty(), "Saved Continue exists before cold Main recovery")
	c.h.view = fixture.accepted_result.campaign.duplicate(true) if state == "activation" else fixture.pending_result.campaign.duplicate(true)
	if state == "activation": c.h.view.activation = {"transition_id":fixture.accepted_result.receipt.transition_id}
	else: c.h.view.transition.phase = "source_sealed"
	_check(await c.owner.refresh(), "Strict control recovery phase is observed before restart: "+state)
	var cold := _cold(c)
	c.online = cold.online
	c.owner = cold.owner
	c.merge(_main_for(c))
	await c.app._story_lobby_action("resume")
	var child: Node = c.app.relay_child
	_check(is_instance_valid(child) and child.journey.campaign_recovery_only(), "Recovery-only native child remains owned: "+state)
	var count: int = c.h.calls.size()
	await c.app._story_child_action("recover",child)
	var calls: Array = c.h.calls.slice(count)
	var posts: Array = calls.filter(func(call: Dictionary): return call.method == HTTPClient.METHOD_POST)
	_check(posts.size() == 1 and posts[0].path.ends_with("/resume" if state == "activation" else "/continue"), "Explicit Resume dispatches the correct reviewed control recovery once: "+state)
	if state == "pending": _check(posts.size()==1 and Canonical.same(posts[0].body,pending.body), "Saved Continue recovery reuses its original request body and key")
	if state == "continuing": _check(not c.owner.pending().is_empty() and Protocol.continue_valid(c.owner.pending().body,c.anchor,HOST,fixture.definition), "Continuing recovery saves an exact native-authorized original-origin request")
	_check(c.app.relay_child == child and c.online.last_room() == c.anchor and not child.running, "Unknown control reply retains the same completed source, without adoption or play: "+state)
	await _dispose_ui(c)


func _accepted_setup() -> Dictionary:
	var c := await _lobby_setup()
	await c.app._story_lobby_action("create",Protocol.key(fixture.definition))
	c.app.campaign_flow._panel._skip()
	var complete := _room("high-and-low",c.anchor,true)
	complete.revision = 5
	c.h.rooms[c.anchor] = complete
	_check(await c.online.coordinator.refresh(), "Completed-card fixture admits actual native A/B pairs")
	c.app.relay_child.refresh_campaign_card()
	var target: String = fixture.accepted_result.campaign.chapters[1].room_id
	c.h.rooms[target] = _room("rolling-home",target,false)
	c.h.continue_result = fixture.accepted_result.duplicate(true)
	c["target"] = target
	return c

func _continue_button() -> void:
	var c := await _accepted_setup()
	var child: Node = c.app.relay_child
	_check(_button(child.overlay,"Continue story") != null,"Actual completed card exposes Continue story")
	_check(c.app.campaign_flow.present_history(child,0,"arrival"),"An explicit historical passage can own the same stable source")
	var before: int = c.h.calls.size()
	await c.app._story_child_action("progress",child)
	_check(c.h.calls.size() == before and c.app.campaign_flow.busy(),"An underlying Continue callback cannot advance while dialogue owns input")
	c.app.campaign_flow._panel._skip()
	await _press_continue(c)
	_check(c.app.relay_child == child and c.app.campaign_flow._active.get("purpose") == "handoff", "Actual Continue acceptance opens completion before replacing its source")
	if c.app.campaign_flow._active.get("purpose") != "handoff":
		await _dispose_ui(c)
		return
	var posts: Array = c.h.calls.slice(before).filter(func(call: Dictionary): return call.method == HTTPClient.METHOD_POST)
	_check(posts.size() == 1 and posts[0].path.ends_with("/continue") and c.owner.pending().is_empty(),"One exact Continue request receives a strictly verified accepted receipt")
	c.app.campaign_flow._panel._advance()
	_check(c.app.relay_child != child and c.online.last_room() == c.target and c.app.campaign_flow._active.phase == "arrival", "Main's actual completed-card action uses the guarded native swap before arrival")
	await _dispose_ui(c)


func _press_continue(c: Dictionary) -> void:
	await _click_control(c,"Continue story")
	for frame in range(120):
		await process_frame
		if c.app.campaign_flow.busy(): break
	if not c.app.campaign_flow.busy():
		print("Continue diagnostic ",JSON.stringify({"owner_code":c.owner.last_code,"pending":c.owner.pending(),"calls":c.h.calls,"mode":c.app.relay_child.mode,"hold":c.app.relay_child._story_hold,"action_busy":c.app._campaign_action_busy}))

func _click_control(c: Dictionary, label: String) -> void:
	await process_frame
	await process_frame
	var button := _button(c.app.relay_child.overlay,label)
	_check(button != null and not button.disabled,"Rendered control is available before touch: "+label)
	if button == null: return
	var ancestor: Node = button.get_parent()
	while ancestor != null and not ancestor is ScrollContainer: ancestor=ancestor.get_parent()
	if ancestor is ScrollContainer: ancestor.ensure_control_visible(button)
	await process_frame
	await process_frame
	_check(c.viewport.get_visible_rect().encloses(button.get_global_rect()),"Actual control is onscreen before the input event: "+label)
	var point := button.get_global_rect().get_center()
	var clicked: Array = []
	button.pressed.connect(func(): clicked.append(true))
	_pointer(c.viewport,point,true)
	await process_frame
	_pointer(c.viewport,point,false)
	await _settle()
	_check(clicked.size()==1,"Viewport input activates the actual callback once: "+label)

func _cancel_admission(guest: bool) -> void:
	var c := await _lobby_setup(guest)
	c.h.fail_post=true
	await c.app._story_lobby_action("join" if guest else "create",Protocol.key(fixture.definition),"AB".repeat(10))
	var before: Dictionary=c.owner.pending_lobby()
	_check(_button(c.app.overlay,"Cancel") != null and not before.is_empty(),"Unknown admission offers the reviewed Cancel control")
	c.h.fail_cancel=true
	await c.app._story_lobby_action("cancel")
	_check(c.owner.pending_lobby().get("cancel_requested") == true and Canonical.same(before.body,c.owner.pending_lobby().body),"Lost Cancel preserves its direction and original admission bytes")
	_check(_button(c.app.overlay,"Cancel")==null and _button(c.app.overlay,"Retry")!=null,"Sticky cancellation offers only its exact Retry, never a redundant Cancel")
	c.h.fail_cancel=false
	var count: int=c.h.calls.size()
	await c.app._story_lobby_action("retry")
	_check(c.owner.pending_lobby().is_empty() and c.owner.bound_campaign().is_empty() and not is_instance_valid(c.app.relay_child),"Fenced Cancel clears only the saved admission and never enters gameplay")
	_check(c.h.calls.size()==count+1 and c.h.calls[-1].path==before.path+"/cancel" and Canonical.same(c.h.calls[-1].body,before.body),"Visible Retry follows sticky Cancel with one exact cancellation request")
	_check(_button(c.app.overlay,"Start") != null and _button(c.app.overlay,"Cancel")==null,"Confirmed cancellation returns the normal Story lobby")
	await _dispose_ui(c)

func _accepted_cancel_ui() -> void:
	var c:=await _lobby_setup()
	c.h.fail_post=true
	await c.app._story_lobby_action("create",Protocol.key(fixture.definition))
	c.h.cancel_status="accepted"
	await c.app._story_lobby_action("cancel")
	_check(not c.owner.pending_lobby().accepted_campaign.is_empty() and _button(c.app.overlay,"Cancel")==null and _button(c.app.overlay,"Retry") != null,"An acceptance racing Cancel is retained behind deliberate recovery")
	var count: int=c.h.calls.size()
	await c.app._story_lobby_action("retry")
	_check(c.h.calls.slice(count).all(func(call: Dictionary): return call.method==HTTPClient.METHOD_GET),"Accepted admission settlement and native opening perform only verified reads")
	_check(is_instance_valid(c.app.relay_child) and c.app.campaign_flow.busy() and not c.app.relay_child.running,"Explicit accepted recovery attaches arrival without auto-Begin")
	await _dispose_ui(c)

func _legacy_join_hold() -> void:
	var c:=await _lobby_setup(true)
	var body: Dictionary={"schema_version":1,"invite_code":"AB".repeat(10),"campaign_key":Protocol.key(fixture.definition),"supported_simulation_versions":[6]}
	var value: Dictionary={"schema_version":2,"owner_player_id":GUEST,"campaigns":[],"bound_campaign":{},"pending":{"path":"/v2/campaigns/join","body":body,"request_hash":LobbyTests.LobbyProtocol.request_hash(GUEST,"/v2/campaigns/join",body),"accepted_campaign":{}}}
	c.h.store.saved["relay-campaign-lobby-v1:"+GUEST]=value.duplicate(true)
	c.owner=Owner.new(c.online,c.h.identity,[fixture.definition],c.app._campaign_leave_ready,c.h.store)
	c.app.campaign_owner=c.owner
	var before: Dictionary=c.h.store.saved.duplicate(true)
	var count: int=c.h.calls.size()
	await c.app._show_story()
	_check(c.owner.read_only and _button(c.app.overlay,"Join")==null and _button(c.app.overlay,"Cancel")==null,"A retained legacy Join1 is held, never rewritten or offered unsafe cancellation")
	_check(c.h.calls.size()==count and Canonical.same(before,c.h.store.saved),"Unsupported legacy admission bytes remain unchanged with no HTTP")
	await _dispose_ui(c)

extends SceneTree
const Flow = preload("res://presentation/campaign_flow.gd")
const Preview = preload("res://relay_preview.gd")
const Owner = preload("res://services/campaign_online_session.gd")
const Online = preload("res://services/relay_online_session.gd")
const Story = preload("res://services/campaign_story.gd")
const Protocol = preload("res://services/campaign_protocol.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const BoundaryTests = preload("res://tests/test_campaign_room_bridge.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	await _arrival("p0")
	await _arrival("p1")
	await _save_failure_and_restart()
	await _cancellation_and_foreign_owner()
	await _native_back()
	await _stale_context_refuses_record()
	await _overlay_visibility()
	await _active_turn_and_rehearsal()
	print("Campaign dialogue flow: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _setup(slot: String = "p0", offer: bool = true, presentation: Viewport = null) -> Dictionary:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/campaign/control-v2.json"))
	var definition: Dictionary = fixture.definition.duplicate(true)
	var content := {"schema_version":1, "story_id":"flow-test", "story_version":1,
		"content_hash":"", "title":"Test chapter", "summary":"Synthetic dialogue", "chapters":[]}
	for pin: Dictionary in definition.chapters:
		content.chapters.append({"level_id":pin.level_id,"level_version":pin.level_version,
			"arrival":[{"speaker":"p0","text":"First test line."},{"speaker":"p1","text":"Second test line."}],
			"completion":[{"speaker":"p1","text":"Completed test line."}]})
	content.content_hash = _hash(content,"content_hash")
	definition.story = Story.pin(content)
	definition.definition_hash = _hash(definition,"definition_hash")
	var h := BoundaryTests.Harness.new()
	root.add_child(h)
	var player := HOST if slot == "p0" else GUEST
	h.player_id = player
	h.identity_value.player_id = player
	h.view = fixture.active_view.duplicate(true)
	h.view.campaign_key = Protocol.key(definition)
	h.view.player_slot = slot
	if slot == "p1":
		h.view.invite_code = null
		h.view.invite_expires_at = null
	var anchor: String = h.view.campaign_room_id
	var level := Registry.definition("high-and-low@1")
	var room := {"schema_version":2,"api_version":2,"simulation_version":6,"room_id":anchor,"revision":1,"branch":0,
		"stage_index":0,"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),
		"host_id":HOST,"guest_id":GUEST,"checkpoint":JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cooperative/high-and-low-initial-checkpoint.json")),
		"a_turn_id":null,"completed_pair_ids":[],"invite_expires_at":"2026-10-04T13:00:00.000Z",
		"created_at":"2026-09-27T12:00:00Z","updated_at":"2026-09-27T12:00:00Z","active_role":"a","first_player_id":HOST,
		"active_player_id":HOST,"player_slot":slot,"stage_id":level.stages[0].id,"recording_a":null,"validation":"structural_client_replay_required"}
	if slot == "p0": room["invite_code"] = "AB".repeat(10)
	h.rooms[anchor] = room
	var online := Online.new(h,h.identity,h.store)
	_check(await online.open_room(anchor), "Actual room coordinator verifies the native initial checkpoint")
	online.capabilities = {"mutations_enabled":true}
	var owner := Owner.new(online,h.identity,[definition],h.leave_ready,h.store)
	_check(owner.restore_owner() and owner.bind_campaign(anchor,Protocol.key(definition)), "Actual campaign owner binds the synthetic story manifest")
	_check(await owner.refresh() and await owner.select_current() and owner.adopt_selected(), "Actual campaign selection and native adoption precede dialogue")
	var viewport: Viewport = presentation
	if viewport == null:
		viewport = SubViewport.new()
		viewport.size = Vector2i(960,540)
		viewport.own_world_3d = true
		root.add_child(viewport)
	var flow := Flow.new()
	viewport.add_child(flow)
	_check(flow.configure(owner,h.identity,content), "Exact synthetic story pin binds")
	var child := Preview.new()
	child.online_session = online
	child.reaction_photos_enabled = false
	child.settings = {"music":false,"sound":false,"reduced_motion":true}
	child.story_chapter_index = 0
	if offer: child.story_flow = flow
	viewport.add_child(child)
	child.set_physics_process(false)
	child.set_process(false)
	await process_frame
	return {"h":h,"online":online,"owner":owner,"flow":flow,"child":child,"viewport":viewport,
		"content":content,"anchor":anchor,"player":player}

func _arrival(slot: String) -> void:
	var c := await _setup(slot)
	var mode := "ready" if slot == "p0" else "online_waiting"
	_check(c.child.mode == mode and c.flow.busy() and c.flow._panel.is_open(), "Arrival opens at the actual "+slot+" stable boundary")
	_check(not c.child.overlay.visible, "Arrival hides the underlying ready or waiting card: "+slot)
	_check(not _world_badge(c,"p0").visible and not _world_badge(c,"p1").visible, "Story hides turn-relative world labels for both viewing roles: "+slot)
	var calls: int = c.h.calls.size()
	var before: Dictionary = c.online.coordinator.snapshot()
	c.child._begin()
	_check(not c.child.running and c.child.mode == mode and Canonical.same(before,c.online.coordinator.snapshot()), "Underlying Record cannot start or mutate a held room")
	c.flow._panel._advance()
	_check(c.flow._panel.dialogue.text == "Second test line.", "Dialogue advances independently of gameplay")
	c.child._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	c.flow._panel._skip()
	_check(c.flow.busy() and c.flow._panel.dialogue.text == "Second test line." and not c.owner.story_seen(0,"arrival"), "Background preserves the line and refuses acknowledgement")
	c.child._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	c.flow._panel._advance()
	_check(not c.flow.busy() and c.owner.story_seen(0,"arrival"), "Foreground dismissal saves exactly the eligible arrival")
	_check(not c.child.running and c.child.mode == mode and c.child._story_hold == -1, "Dismissal restores the same ready or waiting screen without starting a turn")
	_check(c.child.overlay.visible, "Dismissal restores the underlying ready or waiting card: "+slot)
	_check(_world_badge(c,"p0").visible and _world_badge(c,"p1").visible, "Dismissal restores both prior world-label visibilities: "+slot)
	_check(c.h.calls.size() == calls, "Reading and dismissing dialogue performs no network operation")
	_check(not c.flow.present_arrival(c.child,0), "Read arrival never repeats at an intermediate turn")
	await _dispose(c)

func _save_failure_and_restart() -> void:
	var c := await _setup()
	var journal: String = "relay-campaign-v1:"+c.player+":"+c.anchor
	c.h.store.fail_scope = journal
	var before: Dictionary = c.h.store.saved[journal].duplicate(true)
	c.flow._panel._skip()
	_check(c.flow.busy() and c.flow._panel.next_button.text == "Retry" and c.flow._panel.skip_button.text == "Close", "Cosmetic save failure offers explicit Retry and Close")
	_check(Canonical.same(before,c.h.store.saved[journal]), "A failed seen save changes no durable campaign byte")
	c.flow._panel._skip()
	_check(not c.flow.busy() and not c.owner.story_seen(0,"arrival") and not c.flow.present_arrival(c.child,0), "Close suppresses only this visit without pretending the read marker saved")
	c.h.store.fail_scope = ""
	_check(c.flow.configure(c.owner,c.h.identity,c.content) and c.flow.present_arrival(c.child,0), "A fresh presentation owner can recover the unsaved passage")
	c.flow._panel._skip()
	_check(c.owner.story_seen(0,"arrival"), "Deliberate retry visit saves the arrival once storage recovers")
	await _dispose(c)

func _cancellation_and_foreign_owner() -> void:
	var c := await _setup()
	var token: int = c.child._story_hold
	c.flow.invalidate()
	_check(not c.flow.busy() and not c.owner.story_seen(0,"arrival") and c.child._story_hold == -1, "Synchronous cancel neither acknowledges nor leaves a stuck input gate")
	_check(c.flow.present_arrival(c.child,0), "Same-context explicit revisit remains possible after cancellation")
	var next_token: int = c.child._story_hold
	c.child.release_story(token)
	_check(next_token != token and c.child._story_hold == next_token, "A retired gate token cannot release a newer passage")
	_check(not c.child.overlay.visible, "An old gate cannot reveal the underlying card during newer dialogue")
	_check(not _world_badge(c,"p0").visible and not _world_badge(c,"p1").visible, "An old gate cannot reveal turn-role badges during newer dialogue")
	var unrelated := Preview.new()
	c.flow.retire_child(unrelated)
	_check(c.flow.busy(), "An older or unrelated child cannot cancel the current passage")
	unrelated.free()
	c.h.identity_value.epoch += 1
	c.flow._panel._skip()
	_check(not c.flow.busy() and c.child._story_hold == -1 and not c.owner.story_seen(0,"arrival"), "Late identity change cancels without writing a different owner's seen marker")
	await _dispose(c)

func _active_turn_and_rehearsal() -> void:
	var c := await _setup("p0",false)
	c.child.story_flow = c.flow
	c.child._begin()
	_check(c.child.running and not c.flow.present_arrival(c.child,0), "Active input refuses dialogue without pausing or saving implicitly")
	c.child.advance_input({"move_x":1.0,"move_z":0.0,"interact":false})
	_check(c.child.sim.tick == 1, "The rehearsal contains an actual native input tick before pause")
	c.child._pause()
	_check(c.child.mode == "paused" and not c.flow.present_arrival(c.child,0), "Paused rehearsal is not mistaken for a ready boundary")
	c.child._show_ready()
	var draft: Dictionary = c.online.coordinator.draft()
	_check(not draft.is_empty() and c.flow.busy(), "Durably saved rehearsal permits an arrival at the later ready card")
	c.flow._panel._skip()
	_check(Canonical.same(draft,c.online.coordinator.draft()) and not c.child.running, "Arrival preserves the rehearsal and requires a separate Resume")
	await _dispose(c)

func _native_back() -> void:
	for slot: String in ["p0", "p1"]:
		var c := await _setup(slot)
		var mode: String = c.child.mode
		var before: Dictionary = c.online.coordinator.snapshot()
		var calls: int = c.h.calls.size()
		c.child._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		c.child._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		_check(c.flow.busy() and not c.owner.story_seen(0,"arrival"), "Native Back cannot acknowledge a backgrounded arrival: "+slot)
		c.child._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		c.child._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		_check(not c.flow.busy() and not c.flow._panel.is_open() and c.owner.story_seen(0,"arrival"), "Native Android Back deliberately skips and saves the active arrival: "+slot)
		_check(c.child.mode == mode and not c.child.running and not c.child._leaving and c.child._story_hold == -1, "Native Back restores the original stable screen without leaving or starting: "+slot)
		_check(c.child.overlay.visible, "Native Back restores the original underlying card: "+slot)
		_check(_world_badge(c,"p0").visible and _world_badge(c,"p1").visible, "Native Back restores the original world labels: "+slot)
		_check(Canonical.same(before,c.online.coordinator.snapshot()) and c.h.calls.size() == calls, "Native story Back changes neither gameplay nor network operations: "+slot)
		await _dispose(c)

func _stale_context_refuses_record() -> void:
	for boundary: String in ["foreground_publication", "dismiss_identity", "close_after_save_failure"]:
		var c := await _setup()
		var original_coordinator = c.online.coordinator
		var before: Dictionary = original_coordinator.snapshot()
		var durable: Dictionary = c.h.store.saved.duplicate(true)
		var calls: int = c.h.calls.size()
		if boundary == "foreground_publication":
			c.child._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
			c.owner._campaign._state.view["state"] = "deleting"
			c.child._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		elif boundary == "dismiss_identity":
			c.h.identity_value.epoch += 1
			c.child._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		else:
			c.h.store.fail_scope = "relay-campaign-v1:"+c.player+":"+c.anchor
			c.flow._panel._skip()
			_check(c.flow._panel.skip_button.text == "Close", "Cosmetic failure exposes Close before context replacement")
			c.h.identity_value.epoch += 1
			c.flow._panel._skip()
		_check(not c.flow.busy() and not c.flow._panel.is_open() and c.child._story_context_lost and c.child.mode == "error", "Stale "+boundary+" moves the actual child into recovery")
		_check(c.child.overlay.visible, "Stale context keeps its recovery card visible: "+boundary)
		_check(_world_badge(c,"p0").visible and _world_badge(c,"p1").visible, "Context cancellation restores prior world-label visibility: "+boundary)
		c.child._begin()
		c.child._resume_draft()
		c.child._start_play()
		c.child._show_ready()
		_check(c.child.mode == "error" and not c.child.running and c.child._story_hold == -1, "Record, Resume and ready redraw cannot bypass stale context: "+boundary)
		if boundary == "foreground_publication":
			_check(Canonical.same(before,original_coordinator.snapshot()), "Publication loss preserves the last verified gameplay snapshot")
		else:
			_check(c.online.coordinator == null and original_coordinator.snapshot().is_empty(), "Identity loss retires the old owner's in-memory gameplay access: "+boundary)
		_check(Canonical.same(durable,c.h.store.saved) and c.h.calls.size() == calls, "Stale context preserves durable gameplay journals and exact request count: "+boundary)
		await _dispose(c)

func _overlay_visibility() -> void:
	var c := await _setup("p0",false)
	c.child.overlay.hide()
	_world_badge(c,"p0").hide()
	_check(c.flow.present_arrival(c.child,0), "A clean boundary may present with an already hidden card")
	c.flow._panel._skip()
	_check(not c.child.overlay.visible, "Ordinary dismissal restores the exact prior hidden visibility")
	_check(not _world_badge(c,"p0").visible and _world_badge(c,"p1").visible, "Each badge restores its own prior visibility rather than showing all labels")
	await _dispose(c)
	c = await _setup("p0",false)
	c.child.overlay.hide()
	_world_badge(c,"p1").hide()
	_check(c.flow.present_arrival(c.child,0), "Recovery ordering test holds an initially hidden card")
	var token: int = c.child._story_hold
	c.child.story_context_changed()
	c.child.release_story(token)
	_check(c.child.mode == "error" and c.child.overlay.visible, "Late matching release cannot hide a new context-loss recovery card")
	_check(_world_badge(c,"p0").visible and not _world_badge(c,"p1").visible, "Late matching release restores exact badge visibility during recovery")
	await _dispose(c)

func _world_badge(c: Dictionary, slot: String) -> Label3D:
	for child: Node in c.child.world.actors[slot].get_children():
		if child is Label3D: return child
	return null

func _dispose(c: Dictionary) -> void:
	c.viewport.free()
	await process_frame
	c.h.free()
	await process_frame

func _hash(value: Dictionary, field: String) -> String:
	var body := value.duplicate(true)
	body.erase(field)
	return Canonical.digest(body)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

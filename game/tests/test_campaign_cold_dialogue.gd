extends "res://tests/test_campaign_handoff.gd"
## Synthetic control/story; real Owner, native current-child verification and UI.
## Previous completion is accepted control evidence, not a fabricated old replay.

class SeenObserver:
	extends RefCounted
	# Delegate every authority/read/write to the actual Owner. Hooks exercise
	# synchronous observer reentrancy without inventing any native room proof.
	var inner: RefCounted
	var after_seen: Callable
	var after_mark: Callable
	var read_only: bool:
		get: return inner.read_only
	func _init(owner: RefCounted) -> void: inner = owner
	func busy() -> bool: return inner.busy()
	func pending() -> Dictionary: return inner.pending()
	func pending_lobby() -> Dictionary: return inner.pending_lobby()
	func view() -> Dictionary: return inner.view()
	func bound_campaign() -> Dictionary: return inner.bound_campaign()
	func definition() -> Dictionary: return inner.definition()
	func selected_room() -> String: return inner.selected_room()
	func adoption_ready() -> bool: return inner.adoption_ready()
	func story_seen(index: int, phase: String) -> bool:
		var result: bool = inner.story_seen(index,phase)
		var callback := after_seen
		after_seen = Callable()
		if callback.is_valid(): callback.call()
		return result
	func mark_story_seen(index: int, phase: String) -> bool:
		var result: bool = inner.mark_story_seen(index,phase)
		var callback := after_mark
		after_mark = Callable()
		if callback.is_valid(): callback.call()
		return result

func _run() -> void:
	for slot: String in ["p0","p1"]:
		await _cold_order(slot)
		await _skip_cold(slot)
		await _terminal_cold(slot)
	for mask in range(4): await _already_seen(mask)
	await _partial_save(false)
	await _partial_save(true)
	await _restart_between_beats()
	await _first_save_failure()
	await _context_changes()
	await _synchronous_new_generation()
	await _seen_observer_generation()
	await _refusal_boundaries()
	await _pending_boundaries()
	print("Campaign cold dialogue: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _cold_setup(slot: String = "p0", terminal: bool = false, native_complete: bool = false) -> Dictionary:
	var definition: Dictionary = _json("res://tests/fixtures/campaign/control-v2.json").definition
	var level := Registry.definition("conservatory@1")
	definition.chapters.append({"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),"simulation_version":7,"premium":true})
	var c := await _setup(slot,false,null,definition)
	var published: Dictionary = _json("res://tests/fixtures/campaign/control-v2.json").accepted_result.campaign
	published.campaign_key = c.owner.view().campaign_key
	published.player_slot = slot
	if slot == "p1":
		published.invite_code = null
		published.invite_expires_at = null
	var predecessor: Dictionary = _chapter_room(c,"rolling-home",published.chapters[1].room_id,true)
	published.chapters[1].completion = {"source_revision":predecessor.revision,"source_branch":predecessor.branch,"checkpoint_hash":predecessor.checkpoint.checkpoint_hash,"transition_id":"e".repeat(64),"from_campaign_revision":3,"accepted_campaign_revision":5}
	published.chapters.append({"chapter":c.owner.definition().chapters[2].duplicate(true),"room_id":"N".repeat(22),"completion":null})
	published.current_index = 2
	published.revision = 6
	var target: String = published.chapters[2].room_id
	c.h.rooms[target] = _chapter_room(c,"conservatory",target,terminal or native_complete)
	if terminal:
		var room: Dictionary = c.h.rooms[target]
		published.state = "complete"
		published.revision = 8
		published.chapters[2].completion = {"source_revision":room.revision,"source_branch":room.branch,"checkpoint_hash":room.checkpoint.checkpoint_hash,"transition_id":"d".repeat(64),"from_campaign_revision":6,"accepted_campaign_revision":8}
	_check(Protocol.view_valid(published,c.owner.definition(),c.player),"Three-chapter cold publication satisfies the actual control validator")
	c.h.view = published
	_check(await c.owner.refresh() and await c.owner.select_current() and c.owner.adopt_selected(),"Cold current child is independently native-verified and durably adopted")
	c.child.free()
	c["target"] = target
	_attach_cold_child(c)
	await process_frame
	_check(c.child.journey == c.online.coordinator and c.child.journey.snapshot().room_id == target,"Presentation uses the adopted current coordinator rather than historical gameplay")
	return c

func _attach_cold_child(c: Dictionary) -> void:
	var child := Preview.new()
	child.chapter_key = "conservatory@1"
	child.online_session = c.online
	child.reaction_photos_enabled = false
	child.settings = {"music":false,"sound":false,"reduced_motion":true}
	child.story_chapter_index = 2
	c.viewport.add_child(child)
	child.story_flow = c.flow
	child.set_process(false)
	child.set_physics_process(false)
	c.child = child

func _campaign_scope(c: Dictionary) -> String:
	return "relay-campaign-v1:"+c.player+":"+c.anchor

func _without_seen(c: Dictionary) -> Dictionary:
	var saved: Dictionary = c.h.store.saved.duplicate(true)
	if saved.has(_campaign_scope(c)): saved[_campaign_scope(c)].seen = []
	return saved

func _cold_order(slot: String) -> void:
	var c := await _cold_setup(slot)
	var saved := _without_seen(c)
	var native: Dictionary = c.online.coordinator.snapshot()
	var calls: int = c.h.calls.size()
	var reveals: Array = []
	c.child.overlay.visibility_changed.connect(func():
		if c.child.overlay.visible: reveals.append(true))
	_check(c.flow.present_arrival(c.child,2),"Cold current arrival offers a bounded catch-up for "+slot)
	_check(c.flow._cold.size() == 2 and c.flow._active.index == 1 and c.flow._active.phase == "completion" and c.flow._panel.speaker.text == "Blue","Only immediately preceding accepted completion opens first with its original speaker")
	var generation: int = c.child._story_hold
	c.child._begin()
	_check(not c.child.running and not c.child.overlay.visible,"Record stays held while the completion is recalled")
	c.flow._panel._advance()
	var old_request: int = c.flow._panel._request_id
	_check(c.flow._active.index == 2 and c.flow._active.phase == "arrival" and c.flow._panel.speaker.text == "Gold","Current arrival follows the preceding completion on the current world")
	_check(c.child._story_hold == generation and c.child._story_last_release == -1 and reveals.is_empty(),"Both beats share one uninterrupted native input, camera and overlay hold")
	c.flow._panel.resolve_dismissal(old_request,true)
	_check(c.flow.busy() and c.flow._active.phase == "arrival" and c.child._story_hold == generation,"A retired panel request cannot dismiss the synchronously opened next beat")
	c.flow._panel._advance()
	_check(c.flow._panel.speaker.text == "Blue","The second arrival speaker remains in its authored physical slot")
	c.flow._panel._advance()
	_check(not c.flow.busy() and c.owner.story_seen(1,"completion") and c.owner.story_seen(2,"arrival"),"Normal reading durably saves exactly the two current-boundary phases")
	_check(not c.owner.story_seen(0,"arrival") and not c.owner.story_seen(0,"completion") and not c.owner.story_seen(1,"arrival"),"Older unread phases are left unread rather than silently caught up")
	_check(c.flow.history_entries().size() == 5,"Older published phases remain available explicitly in History")
	_check(c.child._story_hold == -1 and c.child.overlay.visible and reveals.size() == 1 and not c.child.running,"Only the final dismissal releases the original stable card")
	_check(Canonical.same(saved,_without_seen(c)) and Canonical.same(native,c.online.coordinator.snapshot()) and c.h.calls.size() == calls,"Catch-up changes only cosmetic seen markers: no gameplay, selection, draft or network mutation")
	_check(not c.flow.present_arrival(c.child,2),"Ready redraw cannot autoplay older unseen History after the bounded plan")
	_check(c.flow.present_history(c.child,0,"arrival"),"Explicit History can still show an older unread arrival")
	c.flow._panel._skip()
	_check(c.owner.story_seen(0,"arrival") and not c.owner.story_seen(0,"completion") and Canonical.same(saved,_without_seen(c)),"Explicit History affects only its requested cosmetic marker")
	await _dispose(c)

func _skip_cold(slot: String) -> void:
	var c := await _cold_setup(slot)
	var saved := _without_seen(c)
	_check(c.flow.present_arrival(c.child,2),"Native Back case starts the captured cold plan")
	c.child._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	c.child._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(c.flow.busy() and not c.owner.story_seen(1,"completion") and not c.owner.story_seen(2,"arrival"),"Backgrounded native Back saves neither planned marker")
	c.child._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	c.child._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(not c.flow.busy() and c.owner.story_seen(1,"completion") and c.owner.story_seen(2,"arrival"),"Foreground Skip acknowledges only the captured two-beat remainder")
	_check(not c.owner.story_seen(0,"arrival") and not c.owner.story_seen(0,"completion") and not c.owner.story_seen(1,"arrival") and Canonical.same(saved,_without_seen(c)),"Whole-plan Skip does not consume older History or gameplay")
	await _dispose(c)

func _already_seen(mask: int) -> void:
	var c := await _cold_setup()
	if mask & 1: _check(c.owner.mark_story_seen(1,"completion"),"Preceding completion was already acknowledged")
	if mask & 2: _check(c.owner.mark_story_seen(2,"arrival"),"Current arrival was already acknowledged")
	var opened: bool = c.flow.present_arrival(c.child,2)
	_check(opened == (mask != 3),"Already-seen combination determines whether any bounded cold phase remains")
	if opened:
		var expected_index := 2 if mask & 1 else 1
		_check(c.flow._active.index == expected_index and c.flow._cold.size() == (2 if mask == 0 else 1),"Seen phases are omitted without pulling any older phase into the plan")
		c.flow._panel._skip()
	_check(c.owner.story_seen(1,"completion") and c.owner.story_seen(2,"arrival") and not c.owner.story_seen(1,"arrival"),"Each seen combination finishes with only the two permitted markers")
	await _dispose(c)

func _partial_save(close: bool) -> void:
	var c := await _cold_setup()
	var scope := _campaign_scope(c)
	var saved := _without_seen(c)
	c.h.store.on_save = func(saved_scope: String):
		if saved_scope == scope and "1:completion" in c.h.store.saved[scope].seen:
			c.h.store.fail_scope = scope
	_check(c.flow.present_arrival(c.child,2),"Partial failure begins with a fixed two-phase plan")
	var generation: int = c.child._story_hold
	c.flow._panel._skip()
	_check(c.owner.story_seen(1,"completion") and not c.owner.story_seen(2,"arrival") and c.flow._panel.next_button.text == "Retry" and c.flow._cold.size() == 2,"Second marker failure preserves the first save and the original unexpanded Retry plan")
	_check(c.child._story_hold == generation and not c.child.overlay.visible and Canonical.same(saved,_without_seen(c)),"Failed cosmetic save keeps the native hold and all non-seen state")
	if close:
		c.flow._panel._skip()
		_check(not c.flow.busy() and not c.owner.story_seen(2,"arrival") and not c.flow.present_arrival(c.child,2),"Close suppresses the entire remaining visit without claiming the unsaved arrival")
		c.h.store.on_save = Callable()
		c.h.store.fail_scope = ""
		await _restart_cold(c)
		_check(c.flow.present_arrival(c.child,2) and c.flow._cold.size() == 1 and c.flow._active.phase == "arrival","Cold restart recovers only the unsaved arrival from the durable first marker")
		c.flow._panel._skip()
	else:
		c.h.store.on_save = Callable()
		c.h.store.fail_scope = ""
		c.flow._panel._advance()
	_check(not c.flow.busy() and c.owner.story_seen(1,"completion") and c.owner.story_seen(2,"arrival") and not c.owner.story_seen(1,"arrival"),"Retry or restarted reading settles only the original boundary")
	await _dispose(c)

func _restart_cold(c: Dictionary) -> void:
	var definition: Dictionary = c.owner.definition()
	c.child.free()
	c.flow.free()
	c.owner.invalidate_identity()
	c.online.invalidate_identity()
	c.online = Online.new(c.h,c.h.identity,c.h.store)
	c.owner = Owner.new(c.online,c.h.identity,[definition],c.h.leave_ready,c.h.store)
	_check(c.owner.restore_owner() and c.owner.restore_selected_room(),"Fresh Owner and Online restore the durable selected current native checkpoint")
	c.flow = Flow.new()
	c.viewport.add_child(c.flow)
	_check(c.flow.configure(c.owner,c.h.identity,c.content),"Fresh Flow binds the same immutable story after restart")
	_attach_cold_child(c)
	await process_frame

func _restart_between_beats() -> void:
	var c := await _cold_setup()
	_check(c.flow.present_arrival(c.child,2),"Restart test begins on the previous completion")
	c.flow._panel._advance()
	_check(c.flow._active.phase == "arrival" and c.owner.story_seen(1,"completion"),"First normal dismissal is durably saved before arrival")
	await _restart_cold(c)
	_check(c.flow.present_arrival(c.child,2) and c.flow._cold.size() == 1 and c.flow._active.phase == "arrival","Restart between panels does not replay the saved preceding completion")
	c.flow._panel._skip()
	await _restart_cold(c)
	_check(not c.flow.present_arrival(c.child,2) and c.flow.history_entries().size() == 5,"Restart after both markers leaves older unseen text in explicit History")
	await _dispose(c)

func _first_save_failure() -> void:
	var c := await _cold_setup()
	var scope := _campaign_scope(c)
	c.h.store.fail_scope = scope
	var before: Dictionary = c.h.store.saved.duplicate(true)
	_check(c.flow.present_arrival(c.child,2),"First-marker failure starts at an eligible stable boundary")
	c.flow._panel._advance()
	_check(c.flow._panel.next_button.text == "Retry" and Canonical.same(before,c.h.store.saved),"Failed normal completion dismissal saves nothing and stays on the first beat")
	c.flow._panel._skip()
	_check(not c.flow.busy() and not c.flow.present_arrival(c.child,2) and not c.owner.story_seen(1,"completion") and not c.owner.story_seen(2,"arrival"),"Close after normal-dismiss failure suppresses both captured phases for this visit")
	c.h.store.fail_scope = ""
	await _restart_cold(c)
	_check(c.flow.present_arrival(c.child,2) and c.flow._cold.size() == 2,"No false read marker survives first-save failure across restart")
	c.flow._panel._skip()
	await _dispose(c)

func _context_changes() -> void:
	for change: String in ["publication","identity","deletion","selection","snapshot"]:
		var c := await _cold_setup()
		var observer := SeenObserver.new(c.owner)
		_check(c.flow.configure(observer,c.h.identity,c.content),"Synchronous observer delegates to the exact real Owner")
		_check(c.flow.present_arrival(c.child,2),"Context-fence test opens the frozen cold plan")
		var scope := _campaign_scope(c)
		observer.after_mark = func():
			if change == "identity": c.h.identity_value.epoch += 1
			elif change == "publication": c.owner._campaign._state.view.revision += 1
			elif change == "deletion": c.owner._campaign._state.view.state = "deleting"
			elif change == "selection": c.owner._campaign._state.selected_room = c.anchor
			else: c.online.coordinator._state.snapshot.revision += 1
		c.flow._panel._skip()
		_check(not c.flow.busy() and not c.flow._panel.is_open() and c.child._story_hold == -1 and c.child._story_context_lost,"Changed "+change+" after the first seen write cancels instead of saving/appending another beat")
		_check("1:completion" in c.h.store.saved[scope].seen and "2:arrival" not in c.h.store.saved[scope].seen,"Only the already durable first marker survives "+change+" drift")
		await _dispose(c)

func _seen_observer_generation() -> void:
	var c := await _cold_setup()
	var observer := SeenObserver.new(c.owner)
	_check(c.flow.configure(observer,c.h.identity,c.content),"Planning observer uses the actual owner and immutable story")
	var replaced: Array = []
	observer.after_seen = func():
		replaced.append(c.flow.configure(observer,c.h.identity,c.content) and c.flow.present_arrival(c.child,2))
	_check(not c.flow.present_arrival(c.child,2),"Old planning call refuses to install a queue after synchronous observer replacement")
	_check(replaced == [true] and c.flow.busy() and c.flow._cold.size() == 2 and c.flow._active.phase == "completion" and c.child._story_hold >= 0,"Replacement queue and its uninterrupted native hold survive the old return")
	c.flow._panel._skip()
	_check(c.owner.story_seen(1,"completion") and c.owner.story_seen(2,"arrival") and not c.flow.busy(),"The surviving queue saves only its own two captured phases")
	await _dispose(c)

func _synchronous_new_generation() -> void:
	var c := await _cold_setup()
	var scope := _campaign_scope(c)
	_check(c.flow.present_arrival(c.child,2),"Synchronous ownership test starts an old cold plan")
	var old_generation: int = c.child._story_hold
	var changed: Array = []
	c.h.store.on_save = func(saved_scope: String):
		if saved_scope != scope: return
		c.h.store.on_save = Callable()
		changed.append(c.flow.configure(c.owner,c.h.identity,c.content) and c.flow.present_arrival(c.child,2))
	c.flow._panel._skip()
	_check(changed == [true] and c.flow.busy() and c.flow._panel.is_open() and c.child._story_hold > old_generation and not c.child._story_context_lost,"Retired save/dismissal cannot cancel a new synchronous Flow generation")
	c.child.release_story(old_generation)
	_check(c.flow.busy() and c.child._story_hold > old_generation and not c.child.overlay.visible,"Stale native release cannot reveal gameplay underneath the replacement queue")
	c.flow._panel._skip()
	_check(not c.flow.busy() and c.owner.story_seen(1,"completion") and c.owner.story_seen(2,"arrival"),"New generation can independently settle after the old callback returns")
	await _dispose(c)

func _refusal_boundaries() -> void:
	var c := await _cold_setup()
	var publication: Dictionary = c.owner._campaign._state.view.duplicate(true)
	c.owner._campaign._state.view.activation = {"transition_id":publication.chapters[1].completion.transition_id}
	_check(not c.flow.present_arrival(c.child,2),"Activation debt prevents the cold plan")
	c.owner._campaign._state.view = publication.duplicate(true)
	var original_lobby: Dictionary = c.owner._lobby.duplicate(true)
	var body := LobbyProtocol.create_body(c.owner.definition(),"cold-pending-create-0001")
	c.owner._lobby.pending = {"path":"/v2/campaigns","body":body,"request_hash":LobbyProtocol.request_hash(c.player,"/v2/campaigns",body),"accepted_campaign":{}}
	_check(not c.flow.present_arrival(c.child,2),"Saved lobby admission retains its recovery controls rather than starting dialogue")
	c.owner._lobby = original_lobby
	c.child._begin()
	_check(c.child.running and not c.flow.present_arrival(c.child,2),"Live current recording cannot be interrupted by cold text")
	c.child._pause()
	_check(not c.flow.present_arrival(c.child,2),"Paused rehearsal is still not a story boundary")
	await _dispose(c)

func _terminal_cold(slot: String) -> void:
	var c := await _cold_setup(slot,true)
	var saved := _without_seen(c)
	_check(c.child.mode == "complete" and not c.flow.present_arrival(c.child,2) and c.flow._cold.is_empty(),"Terminal cold entry prioritizes the actual completed final scene rather than obsolete arrival")
	_check(c.flow.present_finale(c.child,2) and c.flow._active.phase == "completion","Verified final native scene retains its explicit finale path")
	c.flow._panel._advance()
	_check(c.owner.story_seen(2,"completion") and not c.owner.story_seen(1,"completion") and not c.owner.story_seen(2,"arrival"),"Finale does not acknowledge a discarded cold queue")
	_check(Canonical.same(saved,_without_seen(c)) and c.child.mode == "complete" and not c.child.running,"Finale preserves terminal native scene and all non-cosmetic state")
	await _dispose(c)

func _pending_boundaries() -> void:
	var c := await _cold_setup()
	var recording := _json("res://tests/fixtures/journey/a-light-above-a.json")
	_check(c.online.coordinator.save_draft(recording) and not await c.online.coordinator.commit(recording) and not c.online.coordinator.pending().is_empty(),"Actual native A commit with unknown transport outcome remains durably pending")
	var saved: Dictionary = c.h.store.saved.duplicate(true)
	_check(not c.flow.present_arrival(c.child,2) and Canonical.same(saved,c.h.store.saved),"Gameplay request recovery cannot be hidden or mutated by cold dialogue")
	await _dispose(c)
	c = await _cold_setup("p0",false,true)
	_check(not await c.owner._campaign.continue_from(c.online.coordinator) and not c.owner.pending().is_empty(),"Actual CampaignSession records an exact unresolved Continue from a native completed current child")
	saved = c.h.store.saved.duplicate(true)
	_check(not c.flow.present_arrival(c.child,2) and Canonical.same(saved,c.h.store.saved),"Control request recovery prevents any automatic cold plan or seen write")
	await _dispose(c)

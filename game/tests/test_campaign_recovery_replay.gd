extends "res://tests/test_campaign_cold_dialogue.gd"
## Synthetic control transport; actual Owner cold restore, native accepted pairs,
## real Preview controls and world transforms. Replay never writes gameplay.

func _run() -> void:
	# Both viewing roles and motion settings; the authority matrix has its own
	# bounded suite rather than repeating expensive full proof setup here.
	await _completed_collection("p0",false)
	await _completed_collection("p1",true)
	print("Campaign recovery replay: %d checks, %d failures" % [checks,failures])
	await create_timer(0.2).timeout
	quit(0 if failures == 0 else 1)

func _replay_setup(slot: String = "p0") -> Dictionary:
	var c := await _cold_setup(slot,true)
	await _restart_cold(c)
	c.child.world.set_process(false)
	_check(c.child.mode == "complete" and c.child.journey.campaign_recovery_only(),"Actual cold complete Owner restricts fresh play but retains its verified final scene: "+slot)
	return c

func _attach_cold_child(c: Dictionary) -> void:
	# Load the registered production scene, including its shared premium wrapper.
	# An invited online guest still needs no independent local purchase.
	var child: Node = load(Registry.solo_scene("conservatory@1")).instantiate()
	child.online_session = c.online
	child.reaction_photos_enabled = false
	child.settings = {"music":false,"sound":false,"reduced_motion":true}
	child.story_chapter_index = 2
	c.viewport.add_child(child)
	child.story_flow = c.flow
	child.set_process(false)
	child.set_physics_process(false)
	c.child = child

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child: Node in node.get_children():
		var result := _find_button(child,text)
		if result != null: return result
	return null

func _press_replays(c: Dictionary) -> void:
	var button := _find_button(c.child.overlay,"Replays")
	_check(button != null,"The real completed card exposes its saved Replays action")
	if button != null: button.pressed.emit()
	_check(c.child.mode == "replay" and c.child.running and c.child.replay_cursor == 0,"Replays starts the first actual native pair from tick zero")

func _click_replays(c: Dictionary) -> void:
	await process_frame
	await process_frame
	var button := _find_button(c.child.overlay,"Replays")
	_check(button != null and not button.disabled,"Completed Replay control is available for actual viewport input")
	if button == null: return
	var ancestor: Node = button.get_parent()
	while ancestor != null and not ancestor is ScrollContainer: ancestor = ancestor.get_parent()
	if ancestor is ScrollContainer: ancestor.ensure_control_visible(button)
	await process_frame
	await process_frame
	_check(c.viewport.get_visible_rect().encloses(button.get_global_rect()),"Replays is visibly reachable before the native pointer gesture")
	var point := button.get_global_rect().get_center()
	var clicked: Array = []
	button.pressed.connect(func(): clicked.append(true))
	for down: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		c.viewport.push_input(event,true)
		await process_frame
	await process_frame
	_check(clicked.size() == 1 and c.child.mode == "replay" and c.child.running and c.child.replay_cursor == 0,"Actual viewport click starts the saved collection exactly once")

func _pose(world: Node) -> Dictionary:
	var result := {}
	for slot: String in world.actors: result[slot] = world.actors[slot].position
	return result

func _drive_pair(c: Dictionary, pair_index: int, reduced: bool) -> void:
	var child: Node = c.child
	var initial: Dictionary = child.sim.snapshot()
	var initial_pose := _pose(child.world)
	var native_moved := false
	var drawn_moved := false
	var largest_tick := 0
	for _frame in range(child.replay_frames.size()+2):
		if child.mode != "replay": break
		child._physics_process(1.0/30.0)
		if child.mode in ["replay","bloom"]: child.world._process(1.0/30.0)
		var state: Dictionary = child.sim.snapshot()
		largest_tick = maxi(largest_tick,int(state.tick))
		native_moved = native_moved or not Canonical.same(initial.players,state.players)
		for slot: String in initial_pose:
			drawn_moved = drawn_moved or initial_pose[slot].distance_to(child.world.actors[slot].position) > 0.25
	_check(largest_tick > 30 and native_moved and drawn_moved,"Recorded pair%d advances native poses and visible spirits, not only its frame cursor" % pair_index)
	_check(child.sim.snapshot().complete and child.mode == "bloom" and not child.running and not child.overlay.visible,"Actual accepted pair%d reaches its finite visible replay bloom" % pair_index)
	_check(child.world.bloomed and child.world.garden_state == "completed" and not child.world.flowers.is_empty(),"Recorded completion opens the real garden meshes")
	var tick: int = child.sim.tick
	var state_hash: String = child.sim.state_hash()
	var before_height: float = child.world.flowers[-1].scale.y
	var before_dance: Vector3 = child.world.actors["p0"].upper_body.position
	child.world._process(0.3)
	var danced: bool = child.world.actors["p0"].upper_body.position != before_dance
	child.world._process(0.8)
	child._process(1.1)
	child.world.set_process(false)
	if reduced:
		_check(is_equal_approx(child.world.garden_bloom_age,child.world.GARDEN_BLOOM_SECONDS) and is_equal_approx(before_height,1.0),"Reduced motion shows the lasting completed garden immediately")
		_check(is_equal_approx(child.world.actors["p0"].celebration_age,child.world.actors["p0"].CELEBRATION_DURATION),"Reduced motion retains its settled spirit pose")
	else:
		_check(child.world.flowers[-1].scale.y > before_height and child.world.garden_bloom_age >= 1.1,"Replayed completion visibly grows the existing flower meshes")
		_check(danced and child.world.actors["p0"]._celebration_complete,"The completed recorded world starts the shared finite spirit dance")
	_check(child.sim.tick == tick and child.sim.state_hash() == state_hash,"Bloom and dance advance presentation only")

func _completed_collection(slot: String, reduced: bool) -> void:
	var c := await _replay_setup(slot)
	c.child.world.reduced_motion = reduced
	c.child.settings.reduced_motion = reduced
	var reunions := {"count":0}
	c.child.world.reunion.connect(func(): reunions.count += 1)
	var saved: Dictionary = c.h.store.saved.duplicate(true)
	var writes: int = c.h.store.writes.size()
	var calls: int = c.h.calls.size()
	var room: Dictionary = c.child.journey.snapshot()
	if reduced: _press_replays(c)
	else: await _click_replays(c)
	var playback: Dictionary = c.child._replay_context.duplicate(true)
	# Background and a native Pause must preserve both clocks before rendering.
	var cursor: int = c.child.replay_cursor
	var tick: int = c.child.sim.tick
	c.child._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	c.child._physics_process(20.0)
	_check(c.child.mode == "paused" and c.child.replay_cursor == cursor and c.child.sim.tick == tick,"Background consumes neither a recorded frame nor a native tick")
	c.child._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	var resume := _find_button(c.child.overlay,"Resume")
	_check(resume != null,"Background replay exposes the real Resume action")
	if resume != null: resume.pressed.emit()
	_drive_pair(c,0,reduced)
	var remaining: float = c.child.completion_remaining
	c.child._pause()
	c.child._process(20.0)
	_check(c.child.mode == "paused" and c.child.completion_remaining == remaining,"Pause preserves the replay bloom's remaining display time")
	resume = _find_button(c.child.overlay,"Resume")
	if resume != null: resume.pressed.emit()
	c.child._process(Preview.COMPLETION_DURATION)
	c.child.world.set_process(false)
	_check(c.child.mode == "replay" and c.child.replay_pair_index == 1 and c.child.sim.tick == 0 and Canonical.same(playback,c.child._replay_context),"Finite bloom continues into the second retained pair without recapturing playback authority")
	_drive_pair(c,1,reduced)
	c.child._process(Preview.COMPLETION_DURATION)
	c.child.world.set_process(false)
	_check(c.child.mode == "complete" and not c.child.running and c.child.world.bloomed,"Both saved pairs return to the actual completed chapter card")
	_check(reunions.count == 0 if reduced else reunions.count > 0,"Recorded partner approach respects the shared reunion/reduced-motion behavior")
	c.child._begin()
	c.child._resume_draft()
	c.child._accept()
	_check(c.child.mode == "complete" and not c.child.running and c.child.journey.create_live_simulation() == null,"Repaired replay grants no fresh recording, draft, commit or live simulation")
	_check(Canonical.same(saved,c.h.store.saved) and c.h.store.writes.size() == writes and c.h.calls.size() == calls and Canonical.same(room,c.child.journey.snapshot()),"The full rendered collection, pauses and bloom preserve every durable gameplay/control/photo byte and send no request")
	await _dispose(c)

func _authority_changes() -> void:
	var c := await _replay_setup()
	var publication: Dictionary = c.owner._campaign._state.view.duplicate(true)
	var selected: String = c.owner._campaign._state.selected_room
	var coordinator: RefCounted = c.online.coordinator
	var room: Dictionary = coordinator._state.snapshot.duplicate(true)
	var original_api: Node = c.online._api
	var binding: Dictionary = coordinator._transport_lifetime._binding.duplicate(true)
	var definitions: Dictionary = c.owner._definitions.duplicate(true)
	for change: String in ["identity","publication","publication_shape","definition","pin","selection","coordinator","coordinator_generation","device","api","members","deleting","story_hold"]:
		if change != "identity":
			c.child.free()
			_attach_cold_child(c)
			c.child.world.set_process(false)
		_press_replays(c)
		for _frame in range(8): c.child._physics_process(1.0/30.0)
		c.child._pause()
		var cursor: int = c.child.replay_cursor
		var native: String = c.child.sim.state_hash()
		var writes: int = c.h.store.writes.size()
		var calls: int = c.h.calls.size()
		var replacement: Node
		match change:
			"identity": c.h.identity_value.epoch += 1
			"publication": c.owner._campaign._state.view.revision += 1
			"publication_shape": c.owner._campaign._state.view["future_field"] = true
			"definition": c.owner._definitions.values()[0]["future_field"] = true
			"pin": coordinator._transport_lifetime._binding.pin.simulation_version = 6
			"selection": c.owner._campaign._state.selected_room = c.anchor
			"coordinator": c.online.coordinator = null
			"coordinator_generation": _check(coordinator.bind_room(c.target),"Same-room cache rebind advances the actual Coordinator generation")
			"device": c.h.device_token += "-rotated"
			"api":
				replacement = BoundaryTests.Harness.new()
				replacement.player_id = c.player
				replacement.identity_value = c.h.identity_value.duplicate(true)
				root.add_child(replacement)
				c.online._api = replacement
			"members": coordinator._state.snapshot.guest_id = null
			"deleting": c.owner._campaign._state.view.state = "deleting"
			"story_hold": c.child._story_hold = 123
		if change in ["publication_shape","definition","pin","members"]:
			_check(coordinator.playback_context().is_empty(),"Warmed validation cannot authorize changed raw publication/definition/pin/member bytes without a generation bump: "+change)
		c.child._resume_replay()
		c.child._physics_process(1.0/30.0)
		c.child._process(1.0)
		_check(c.child.replay_cursor == cursor and c.child.sim.state_hash() == native and not c.child.running,"Paused replay consumes no invisible frame after "+change)
		_check(c.h.calls.size() == calls and c.h.store.writes.size() == writes,"Playback's "+change+" observer neither dispatches nor writes")
		if change != "story_hold": _check(c.child._story_context_lost and c.child._replay_context.is_empty(),"Authority drift retires the captured replay before another tick: "+change)
		else:
			c.child._story_hold = -1
			c.child._resume_replay()
			c.child._physics_process(1.0/30.0)
			_check(c.child.replay_cursor == cursor+1 and not c.child._story_context_lost,"A temporary story hold suspends the exact replay rather than retiring its authority")
		c.h.identity_value.epoch = 1
		c.h.device_token = "synthetic-device-token"
		c.owner._campaign._state.view = publication.duplicate(true)
		c.owner._campaign._state.selected_room = selected
		c.online.coordinator = coordinator
		coordinator._state.snapshot = room.duplicate(true)
		c.online._api = original_api
		coordinator._transport_lifetime._binding = binding.duplicate(true)
		c.owner._definitions = definitions.duplicate(true)
		if replacement != null: replacement.free()
	var ordinary := Coordinator.new(c.online.transport,c.h.store.load_scope,c.h.store.save_scope,c.h.identity)
	_check(ordinary.bind_room(c.target) and ordinary.playback_context().get("kind") == "ordinary","An ordinary cached coordinator has an explicitly distinct playback context")
	ordinary.restrict_campaign_recovery()
	_check(ordinary.playback_context().is_empty(),"The existing unclassified ordinary-entry restriction cannot fall back to read playback authority")
	await _dispose(c)

func _pending_recovery() -> void:
	var c := await _cold_setup("p0",false,false)
	var record := _json("res://tests/fixtures/journey/a-light-above-a.json")
	_check(c.online.coordinator.save_draft(record) and not await c.online.coordinator.commit(record) and not c.online.coordinator.pending().is_empty(),"Actual native contribution has a durable uncertain POST to recover")
	var saved: Dictionary = c.h.store.saved.duplicate(true)
	var calls: int = c.h.calls.size()
	c.child._start_replay(record,Registry.initial_checkpoint("conservatory@1"),{})
	_check(not c.child.running and c.child._replay_context.is_empty() and Canonical.same(saved,c.h.store.saved) and c.h.calls.size() == calls,"Replay cannot hide, retry, rewrite or clear a pending gameplay contribution")
	await _dispose(c)
	c = await _cold_setup("p0",false,true)
	_check(not await c.owner._campaign.continue_from(c.online.coordinator) and not c.owner.pending().is_empty(),"Actual completed child retains an uncertain exact Continue")
	saved = c.h.store.saved.duplicate(true)
	calls = c.h.calls.size()
	c.child.replay_pair_index = 0
	c.child._play_collection_pair()
	_check(not c.child.running and c.child._replay_context.is_empty() and Canonical.same(saved,c.h.store.saved) and c.h.calls.size() == calls,"Recovery-only playback introduces no implicit Continue or pending settlement")
	await _dispose(c)

func _terminal_during_bloom() -> void:
	var c := await _replay_setup()
	_press_replays(c)
	for _frame in range(c.child.replay_frames.size()+2):
		if c.child.mode != "replay": break
		c.child._physics_process(1.0/30.0)
	_check(c.child.mode == "bloom","Terminal retirement begins during actual accepted replay bloom")
	var owner_id: String = c.player
	var anchor: String = c.anchor
	c.owner._terminal._transport = func(_request: Dictionary) -> Dictionary:
		return {"ok":true,"status":200,"data":{"schema_version":1,"operation":"campaign_terminal_cleanup","status":"released","player_id":owner_id,"campaign_room_id":anchor}}
	_check(c.owner._terminal.begin(anchor) and await c.owner._terminal.reconcile(),"Exact typed terminal evidence is durably accepted by the real cleanup service")
	var saved: Dictionary = c.h.store.saved.duplicate(true)
	var remaining: float = c.child.completion_remaining
	var cursor: int = c.child.replay_cursor
	var native: String = c.child.sim.state_hash()
	c.child._process(20.0)
	c.child._physics_process(1.0/30.0)
	_check(c.child._story_context_lost and c.child._replay_context.is_empty() and c.child.completion_remaining == remaining and c.child.replay_cursor == cursor and c.child.sim.state_hash() == native,"Saved terminal proof retires playback before bloom continuation or another pair")
	_check(Canonical.same(saved,c.h.store.saved),"Replay retirement itself preserves the cleanup receipt and raw journals")
	await _dispose(c)

extends "res://tests/test_main_cold_story.gd"
## Actual Main/Owner/factory/Collection/View; only replies and cache I/O are synthetic.
const Collection = preload("res://services/shared_replay_collection.gd")

class ReplayCache:
	extends RefCounted
	var values: Dictionary = {}
	var writes := 0
	var fail := false
	func load_scope(scope: String) -> Dictionary:
		return {"ok":true,"found":values.has(scope),"value":values.get(scope,{}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> bool:
		if fail: return false
		writes += 1
		values[scope] = value.duplicate(true)
		return true

class ReplayHarness:
	extends RestoreHarness
	var offline := false
	var replay_replies: Dictionary = {}
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		if offline:
			calls.append({"method":method,"path":path,"body":body.duplicate(true)})
			return {"ok":false,"status":0,"code":"offline"}
		if replay_replies.has(path):
			busy = true
			calls.append({"method":method,"path":path,"body":body.duplicate(true)})
			var result: Dictionary = replay_replies[path].duplicate(true)
			if hold: await release
			else: await get_tree().process_frame
			busy = false
			return result
		return await super.request_json(method,path,body)

class HeldFactory:
	extends RefCounted
	func current() -> bool: return true
	func for_room(_room: String, _purpose: String) -> RefCounted: return null

class CacheTarget:
	extends RefCounted
	func current() -> bool: return true
	func request(_envelope: Dictionary) -> Dictionary: return {"ok":false,"status":0}

class CacheFactory:
	extends RefCounted
	func current() -> bool: return true
	func for_room(_room: String, _purpose: String) -> RefCounted: return CacheTarget.new()

func _run() -> void:
	for guest: bool in [false,true]: await _actual_player_route(guest)
	await _preserve_pending()
	await _cold_pending_return()
	await _relay_adapter()
	await _comfort_adapter()
	for version: int in [4,5]: await _first_steps_adapter(version)
	await _later_pair_pin()
	await _running_retirement()
	await _cache_and_authority()
	await _simulation_pin()
	await _publication_rows()
	for kind: String in ["wrong_member","wrong_pin","bad_proof","missing","capacity","save"]: await _refusal(kind)
	for kind: String in ["back","identity","retired"]: await _late_result(kind)
	await _busy_reentry()
	for operation: String in ["refresh","pair"]:
		for identity_change: bool in [false,true]: await _late_memory(operation,identity_change)
	await _seven_rows()
	print("Story shared replays: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _replay_case(guest: bool = false, activation: bool = false, prefix: int = 2, opening: String = Registry.HIGH_AND_LOW, comfort: bool = false, first_rules: int = 0) -> Dictionary:
	_three_fixture()
	var opening_checkpoint: Dictionary = {}
	if opening == Registry.RELAY or opening == Registry.FIRST_STEPS or comfort:
		var descriptor := Registry.descriptor(opening)
		var rules: int = 8 if comfort else first_rules if opening == Registry.FIRST_STEPS else 2
		var pin := {"level_id":descriptor.level_id,"level_version":descriptor.level_version,"definition_hash":descriptor.definition_hash,"simulation_version":rules,"premium":false}
		if opening == Registry.FIRST_STEPS:
			opening_checkpoint = _json("res://tests/fixtures/first_steps/"+("final-checkpoint.json" if first_rules == 4 else "cumulative-garden-checkpoint.json"))
		else:
			opening_checkpoint = _json("res://tests/fixtures/comfort8/recordings.json")["high-and-low"].checkpoints[2].duplicate(true) if comfort else _json("res://tests/fixtures/v2/final-checkpoint.json")
		fixture.definition.chapters[0] = pin
		story_content.chapters[0]["level_id"] = descriptor.level_id
		story_content.chapters[0]["level_version"] = descriptor.level_version
		var story_body: Dictionary = story_content.duplicate(true)
		story_body.erase("content_hash")
		story_content["content_hash"] = Canonical.digest(story_body)
		fixture.definition["story"] = StorySource.pin(story_content)
		var definition_body: Dictionary = fixture.definition.duplicate(true)
		definition_body.erase("definition_hash")
		fixture.definition["definition_hash"] = Canonical.digest(definition_body)
		_replace_key(fixture,Protocol.key(fixture.definition))
		for view: Dictionary in [fixture.active_view,fixture.accepted_result.campaign]: view.chapters[0]["chapter"] = pin.duplicate(true)
		fixture.accepted_result.campaign.chapters[0].completion["checkpoint_hash"] = opening_checkpoint.checkpoint_hash
	var h := ReplayHarness.new()
	h.store = RestoreStore.new()
	root.add_child(h)
	h.view = fixture.active_view.duplicate(true)
	if guest:
		h.player_id = GUEST
		h.identity_value.player_id = GUEST
		h.view["player_slot"] = "p1"
		h.view["invite_code"] = null
		h.view["invite_expires_at"] = null
	var anchor: String = h.view.campaign_room_id
	var target: String = fixture.accepted_result.campaign.chapters[1].room_id
	h.rooms[anchor] = _room("high-and-low",anchor,true)
	if opening == Registry.RELAY or opening == Registry.FIRST_STEPS or comfort:
		for field: String in ["level_id","level_version","definition_hash"]: h.rooms[anchor][field] = fixture.definition.chapters[0][field]
		if comfort: h.rooms[anchor]["simulation_version"] = 8
		elif opening == Registry.FIRST_STEPS: h.rooms[anchor]["simulation_version"] = first_rules
		else: h.rooms[anchor].erase("simulation_version")
		h.rooms[anchor]["checkpoint"] = opening_checkpoint.duplicate(true)
	h.rooms[target] = _room("rolling-home",target,true)
	var c := {"h":h,"anchor":anchor,"target":target}
	h.rooms[FAR_ROOM] = _third_room(c,false)
	if guest:
		for room: Dictionary in h.rooms.values():
			room["player_slot"] = "p1"
			room.erase("invite_code")
	var online := Online.new(h,h.identity,h.store)
	_check(await online.open_room(anchor),"Source proof is natively verified before Story discovery")
	online.capabilities = Boundaries.campaign_capabilities(fixture.definition)
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	_check(owner.restore_owner() and owner.bind_campaign(anchor,Protocol.key(fixture.definition)),"Replay fixture has a real durable bound owner")
	h.view = _advanced(c,false) if prefix == 2 else fixture.accepted_result.campaign.duplicate(true)
	if activation: h.view["activation"] = {"transition_id":h.view.chapters[int(h.view.current_index)-1].completion.transition_id}
	_check(await owner.refresh(),"Current control is independently validated before replay navigation")
	if not activation: _check(await owner.select_current() and owner.adopt_selected(),"Current native chapter is independently selected before replay navigation")
	c["online"] = online
	c["owner"] = owner
	c["cache"] = ReplayCache.new()
	c.merge(_main_for(c))
	c.viewport.handle_input_locally = true
	c.app.shared_replays = Collection.new(h,h.identity,c.cache,h.store,online.auxiliary_context_factory())
	c.app._draw_story_lobby()
	c["before"] = h.store.saved.duplicate(true)
	c["coordinator"] = online.coordinator
	c["selection"] = {"room_id":anchor,"chapter":fixture.definition.chapters[0].duplicate(true),"host_id":HOST,"guest_id":GUEST}
	return c

func _main_click(c: Dictionary, text: String, target: Node = null) -> void:
	await _settle()
	var button := _button(c.app.overlay if target == null else target,text)
	_check(button != null and not button.disabled,"Actual replay control is available: "+text)
	if button == null: return
	var ancestor: Node = button.get_parent()
	while ancestor != null and not ancestor is ScrollContainer: ancestor = ancestor.get_parent()
	if ancestor is ScrollContainer: ancestor.ensure_control_visible(button)
	await _settle()
	var pressed: Array = []
	button.pressed.connect(func(): pressed.append(true))
	var point := button.get_global_rect().get_center()
	_pointer(c.viewport,point,true)
	await process_frame
	_pointer(c.viewport,point,false)
	await _settle()
	_check(pressed.size() == 1,"Viewport input reached the rendered callback once: "+text)

func _wait_replay(c: Dictionary, expected: String) -> void:
	for frame in range(240):
		if c.app.mode == expected and not c.h.busy and not c.app.shared_replays.busy(): return
		await process_frame
	_check(false,"Replay route reaches its bounded stable state: "+expected)

func _unchanged(c: Dictionary, text: String) -> void:
	_check(Canonical.same(c.before,c.h.store.saved) and c.online.coordinator == c.coordinator and c.online.last_room() == FAR_ROOM and c.owner.selected_room() == FAR_ROOM,text)

func _actual_player_route(guest: bool) -> void:
	var c := await _replay_case(guest)
	c.online.capabilities["mutations_enabled"] = false
	var calls: int = c.h.calls.size()
	await _main_click(c,"Shared replays")
	_check(c.app.mode == "story_replay_chapters" and c.app._story_replay_rows().size() == 3 and c.cache.writes == 0 and c.h.calls.size() == calls,"Chooser discovery reads one accepted publication without network or cache writes")
	await _main_click(c,"1 · "+str(Registry.descriptor(Registry.HIGH_AND_LOW).title))
	await _wait_replay(c,"shared_memories")
	_check(c.h.calls.size() == calls+1 and c.h.calls[-1].path == "/v2/rooms/"+c.anchor and c.h.campaign_calls[-1].path == c.h.calls[-1].path,"Only the explicitly opened old child is fetched with campaign marking")
	var rows: Array = c.app.shared_replays.memories("chapter:"+c.anchor)
	_check(rows.size() == 2 and c.app.shared_replays.rooms().size() == 1,"Native snapshot reconstructs its two accepted pairs without flattening other chapters")
	_unchanged(c,"Replay discovery preserves every owner/gameplay journal, coordinator and selected pointer")
	await _main_click(c,str(rows[0].title)+" · On this device")
	await _wait_replay(c,"shared_replay")
	var viewer: Node = c.app.shared_replay_child
	_check(is_instance_valid(viewer) and viewer.mode == "replay" and viewer.entry.room.room_id == c.anchor and not viewer.controls.stick.visible,"Actual immutable SharedReplayView plays the historical native proof for either member")
	viewer.set_process(false)
	viewer.set_physics_process(false)
	viewer.world.set_process(false)
	viewer._notification(NOTIFICATION_APPLICATION_RESUMED)
	for tick in range(6): viewer._physics_process(1.0/30.0)
	_check(viewer.cursor > 0,"Historical replay consumes actual accepted inputs")
	if guest:
		viewer._pause()
		await _main_click(c,"Back",viewer.controls.overlay)
	else:
		var cursor: int = viewer.cursor
		await _dispatch_replay_escape(c.viewport)
		_check(is_instance_valid(viewer) and viewer.mode == "paused" and not viewer.running and viewer.cursor == cursor and c.app.mode == "shared_replay" and c.app.shared_replay_child == viewer,"Dispatched Escape pauses only the active viewer without navigating Main")
		await _dispatch_replay_escape(c.viewport)
		_check(c.app.mode == "shared_memories" and not is_instance_valid(c.app.shared_replay_child) and not c.app._story_replay_return.is_empty(),"Dispatched paused Escape closes once to this Story's stage list without falling through to chooser or Home")
	await _wait_replay(c,"shared_memories")
	await _main_click(c,"Back")
	_check(c.app.mode == "story_replay_chapters","Viewer and stage Back preserve the Story-specific return route")
	await _main_click(c,"Back")
	_check(c.app.mode == "story_lobby" and _button(c.app.overlay,"Resume") != null,"Second Back returns to the same bound Story with Resume")
	_unchanged(c,"Playing and closing an earlier replay never selects it or changes pending/control/seen state")
	_check(_only_gets(c.h.calls.slice(calls)) and not c.online.capabilities.mutations_enabled,"Story replay navigation never submits or re-enables gameplay/Continue")
	await _dispose_ui(c)

func _dispatch_replay_escape(viewport: SubViewport) -> void:
	# Exercise SceneTree event routing, including the synchronous child-close
	# callback. Calling either private handler directly would miss fallthrough.
	var pressed := InputEventKey.new()
	pressed.physical_keycode = KEY_ESCAPE
	pressed.keycode = KEY_ESCAPE
	pressed.pressed = true
	viewport.push_input(pressed,true)
	_check(viewport.is_input_handled(),"The viewer owns and consumes the dispatched Escape before returning to Main")
	await process_frame
	var released := InputEventKey.new()
	released.physical_keycode = KEY_ESCAPE
	released.keycode = KEY_ESCAPE
	viewport.push_input(released,true)
	await _settle()

func _cache_and_authority() -> void:
	var c := await _replay_case()
	var key: String = await c.app.shared_replays.open_story_chapter(c.selection)
	_check(not key.is_empty(),"Concrete historical context admits a real completed source")
	var restarted := Collection.new(c.h,c.h.identity,c.cache,c.h.store,c.online.auxiliary_context_factory())
	c.h.offline = true
	var calls: int = c.h.calls.size()
	_check(restarted.cached_story_chapter(c.selection) == key and not (await restarted.open_memory(key,"p0-0")).is_empty() and c.h.calls.size() == calls,"Restarted unchanged authority can replay verified local evidence completely offline")
	var raw: Dictionary = c.cache.values.duplicate(true)
	restarted.configure_context_factory(HeldFactory.new())
	_check(restarted.cached_story_chapter(c.selection).is_empty() and (await restarted.open_story_chapter(c.selection)).is_empty() and c.h.calls.size() == calls,"Supplied held factory refuses both local Story entry and remote fallback")
	c.h.offline = false
	c.h.view["state"] = "deleting"
	c.h.view["revision"] += 1
	_check(await c.owner.refresh(),"Known deleting publication is accepted through the normal control validator")
	restarted.configure_context_factory(c.online.auxiliary_context_factory())
	calls = c.h.calls.size()
	_check(restarted.cached_story_chapter(c.selection).is_empty() and c.h.calls.size() == calls and Canonical.same(raw,c.cache.values),"Known deletion holds cached Story entry without deleting previously accepted evidence")
	await _dispose_ui(c)

func _relay_adapter() -> void:
	var c := await _replay_case(false,false,2,Registry.RELAY)
	_check(not c.h.rooms[c.anchor].has("simulation_version"),"Real Relay Isles snapshot preserves the existing omitted-version schema")
	await _main_click(c,"Shared replays")
	await _main_click(c,"1 · "+str(Registry.descriptor(Registry.RELAY).title))
	await _wait_replay(c,"shared_memories")
	var key: String = "chapter:"+c.anchor
	var rows: Array = c.app.shared_replays.memories(key)
	_check(rows.size() == 2 and c.app.shared_replays.cached_story_chapter(c.selection) == key,"Explicit Relay Story GET admits authored version2 and both real native cached pairs")
	var entry: Dictionary = await c.app.shared_replays.open_memory(key,"p0-1")
	_check(not entry.is_empty() and Collection.verify_entry(entry,HOST) and entry.pair.a.simulation_version == 2 and entry.pair.b.simulation_version == 2,"Relay cached playback keeps exact version2 proof admission")
	_unchanged(c,"Relay replay discovery never mutates current coordinator, pointers or journals")
	await _dispose_ui(c)

func _comfort_adapter() -> void:
	var c := await _replay_case(false,false,2,Registry.HIGH_AND_LOW,true)
	var proof: Dictionary = c.h.rooms[c.anchor].checkpoint.duplicate(true)
	_check(c.selection.chapter.simulation_version == 8 and proof.proof.a.simulation_version == 8 and proof.proof.b.simulation_version == 8,"Comfort replay uses actual immutable version8 native proof, not relabeled old recordings")
	await _main_click(c,"Shared replays")
	await _main_click(c,"1 · "+str(Registry.descriptor(Registry.HIGH_AND_LOW).title))
	await _wait_replay(c,"shared_memories")
	var key := "chapter:"+str(c.anchor)
	var entry: Dictionary = await c.app.shared_replays.open_memory(key,"p0-1")
	_check(not entry.is_empty() and Collection.verify_entry(entry,HOST) and Canonical.same(entry.pair.checkpoint,proof),"Historical comfort8 discovery and cached replay preserve the complete native proof")
	var raw: Dictionary = c.cache.values.duplicate(true)
	var calls: int = c.h.calls.size()
	for version: int in [6,7,9]:
		var wrong: Dictionary = c.selection.duplicate(true)
		wrong.chapter.simulation_version = version
		_check(c.app.shared_replays.cached_story_chapter(wrong).is_empty(),"Cached version8 recordings cannot satisfy a different historical or future pin")
	_check(Canonical.same(raw,c.cache.values) and c.h.calls.size() == calls,"Wrong replay pins neither rewrite proof bytes nor issue network fallback")
	_unchanged(c,"Version8 historical replay remains independent of the current version7 Story room")
	await _dispose_ui(c)

func _running_retirement() -> void:
	var c := await _replay_case()
	await _main_click(c,"Shared replays")
	await _main_click(c,"1 · "+str(Registry.descriptor(Registry.HIGH_AND_LOW).title))
	await _wait_replay(c,"shared_memories")
	var rows: Array = c.app.shared_replays.memories("chapter:"+c.anchor)
	await _main_click(c,str(rows[0].title)+" · On this device")
	await _wait_replay(c,"shared_replay")
	var viewer: Node = c.app.shared_replay_child
	viewer.set_process(false)
	viewer.set_physics_process(false)
	viewer.world.set_process(false)
	viewer._notification(NOTIFICATION_APPLICATION_RESUMED)
	var immutable := Canonical.digest(viewer.entry)
	c.owner.invalidate_identity() # Same numeric account identity, retired Story owner.
	var calls: int = c.h.calls.size()
	var cursor: int = viewer.cursor
	for tick in range(4): viewer._physics_process(1.0/30.0)
	_check(viewer.cursor > cursor and Canonical.digest(viewer.entry) == immutable,"Existing same-identity immutable local playback may finish after Story-owner retirement")
	_check(c.app.shared_replays.cached_story_chapter(c.selection).is_empty() and (await c.app.shared_replays.open_story_chapter(c.selection)).is_empty() and c.h.calls.size() == calls,"Retirement prevents scoped re-entry and new remote work without ordinary fallback")
	viewer._pause()
	await _main_click(c,"Back",viewer.controls.overlay)
	_check(c.app.mode == "home" and c.app._story_replay_return.is_empty(),"Late viewer Back cannot reopen the retired Story lobby")
	_check(Canonical.same(c.before,c.h.store.saved),"Retirement/playback presentation never rewrites the retained journals")
	await _dispose_ui(c)

func _first_steps_adapter(version: int) -> void:
	var c := await _replay_case(false,false,2,Registry.FIRST_STEPS,false,version)
	await _main_click(c,"Shared replays")
	await _main_click(c,"1 · "+str(Registry.descriptor(Registry.FIRST_STEPS).title))
	await _wait_replay(c,"shared_memories")
	var rows: Array = c.app.shared_replays.memories("chapter:"+str(c.anchor))
	_check(rows.size() == 2,"Actual Story First Steps"+str(version)+" discovery yields both preserved native stages")
	if rows.size() != 2: await _dispose_ui(c); return
	await _main_click(c,str(rows[1].title)+" · On this device")
	await _wait_replay(c,"shared_replay")
	var viewer: Node = c.app.shared_replay_child
	_check(is_instance_valid(viewer),"Actual Main opens retained First Steps"+str(version)+" in the immutable viewer")
	if is_instance_valid(viewer):
		viewer.set_process(false)
		viewer.set_physics_process(false)
		viewer._notification(NOTIFICATION_APPLICATION_RESUMED)
		for tick in range(6): viewer._physics_process(1.0/30.0)
		_check(viewer.cursor > 0 and viewer.entry.pair.a.simulation_version == version and viewer.entry.pair.b.simulation_version == version,"Successful playback preserves the exact First Steps rules instead of substituting preferred8")
		viewer._pause()
		await _main_click(c,"Back",viewer.controls.overlay)
	_unchanged(c,"Successful old First Steps playback leaves the current Story selection and journals unchanged")
	await _dispose_ui(c)

func _archive_pair(checkpoint: Dictionary) -> Dictionary:
	return {"pair_id":"p0-0","branch":0,"stage_index":0,"a":checkpoint.proof.a.duplicate(true),"b":checkpoint.proof.b.duplicate(true),"checkpoint":checkpoint.duplicate(true)}

func _archive_summary(pair: Dictionary) -> Dictionary:
	return {"pair_id":pair.pair_id,"branch":pair.branch,"stage_index":pair.stage_index,"a_hash":pair.a.recording_hash,"b_hash":pair.b.recording_hash,"checkpoint_hash":pair.checkpoint.checkpoint_hash}

func _empty_replay_cache(c: Dictionary) -> String:
	var key := "chapter:"+str(c.anchor)
	# A legal cold index may retain its known room after its pair cache is absent.
	# Reconstruct the collection rather than carrying any decoded memory forward.
	c.cache.values.erase("shared-replays:"+HOST+":"+key)
	c.app.shared_replays = Collection.new(c.h,c.h.identity,c.cache,c.h.store,c.online.auxiliary_context_factory())
	_check(c.app.shared_replays.cached_story_chapter(c.selection) == key and c.app.shared_replays.memories(key).is_empty(),"Cold exact Story discovery restores the pin even with an empty pair cache")
	return key

func _later_pair_pin() -> void:
	var c := await _replay_case(false,false,2,Registry.HIGH_AND_LOW,true)
	_check(not (await c.app.shared_replays.open_story_chapter(c.selection)).is_empty(),"A real version8 room is verified before later archive reads")
	var key := _empty_replay_cache(c)
	var wrong := _archive_pair(_json("res://tests/fixtures/cooperative/upper-path-checkpoint.json"))
	var entry := {"schema_version":1,"room":c.app.shared_replays._rooms[key].duplicate(true),"pair":wrong}
	_check(Collection.verify_entry(entry,HOST),"Wrong-version archive is independently valid native6 evidence, not a malformed-proof fixture")
	var path := "/v2/rooms/"+str(c.anchor)
	c.h.replay_replies[path+"/collection"] = {"ok":true,"status":200,"data":{"pairs":[_archive_summary(wrong)]}}
	c.h.replay_replies[path+"/pairs/p0-0"] = {"ok":true,"status":200,"data":wrong}
	var raw: Dictionary = c.cache.values.duplicate(true)
	var rows: Array = await c.app.shared_replays.refresh_memories(key)
	_check(rows.size() == 1 and not rows[0].cached and Canonical.same(raw,c.cache.values),"A collection summary remains an unverified hint and creates no cached pair")
	if rows.size() == 1:
		_check((await c.app.shared_replays.open_memory(key,"p0-0",rows[0])).is_empty() and Canonical.same(raw,c.cache.values),"Later pair GET refuses native6 under the selected full8 pin before cache or return")
	_check(not c.app.shared_replays._cache(entry) and Canonical.same(raw,c.cache.values),"The shared accepted-proof cache path also refuses the conflicting Story pin")
	var other_room := _room("high-and-low",c.anchor,true)
	_check(not c.app.shared_replays._remember_room(other_room,"chapter") and Canonical.same(raw,c.cache.values),"Generic room refresh cannot replace the known Story room with another supported rules version")
	var conflicting: Dictionary = c.selection.duplicate(true)
	conflicting.chapter.simulation_version = 6
	var calls: int = c.h.calls.size()
	_check(c.app.shared_replays.cached_story_chapter(conflicting).is_empty() and (await c.app.shared_replays.open_story_chapter(conflicting)).is_empty() and c.h.calls.size() == calls,"A later conflicting selection cannot replace the retained full pin or fetch with enlarged authority")
	var good := _archive_pair(_json("res://tests/fixtures/comfort8/recordings.json")["high-and-low"].checkpoints[1])
	c.h.replay_replies[path+"/pairs/p0-0"] = {"ok":true,"status":200,"data":good}
	var accepted: Dictionary = await c.app.shared_replays.open_memory(key,"p0-0")
	_check(not accepted.is_empty() and accepted.pair.a.simulation_version == 8 and Collection.verify_entry(accepted,HOST),"A later exact native8 pair still downloads and caches after a wrong-version refusal")
	c.app.shared_replays.invalidate_identity()
	_check(c.app.shared_replays._story_selections.is_empty(),"Retirement clears every transient Story pin constraint")
	await _dispose_ui(c)

func _cold_pending_return() -> void:
	var c := await _replay_case()
	var record := _json("res://tests/fixtures/journey/a-light-above-a.json")
	_check(c.online.coordinator.save_draft(record) and not await c.online.coordinator.commit(record),"Cold replay fixture preserves a genuine current rehearsal and lost native A request")
	var pending: Dictionary = c.online.coordinator.pending()
	_check(not pending.is_empty(),"Cold replay return starts with actual unresolved gameplay")
	var before: Dictionary = c.h.store.saved.duplicate(true)
	c.viewport.queue_free()
	await _settle()
	var restored := _cold(c)
	c.online = restored.online
	c.owner = restored.owner
	c.merge(_main_for(c),true)
	c.viewport.handle_input_locally = true
	c.app.shared_replays = Collection.new(c.h,c.h.identity,c.cache,c.h.store,c.online.auxiliary_context_factory())
	c.app._draw_story_lobby()
	_check(Canonical.same(before,c.h.store.saved),"Fresh Owner/Online/Main restoration preserves every saved scope before replay entry")
	var calls: int = c.h.calls.size()
	await _main_click(c,"Shared replays")
	await _main_click(c,"1 · "+str(Registry.descriptor(Registry.HIGH_AND_LOW).title))
	await _wait_replay(c,"shared_memories")
	var rows: Array = c.app.shared_replays.memories("chapter:"+str(c.anchor))
	_check(not rows.is_empty(),"Cold pending Story can discover an accepted historical memory")
	if rows.is_empty():
		await _dispose_ui(c)
		return
	await _main_click(c,str(rows[0].title)+" · On this device")
	await _wait_replay(c,"shared_replay")
	var viewer: Node = c.app.shared_replay_child
	_check(is_instance_valid(viewer) and viewer.mode == "replay" and viewer.entry.room.room_id == c.anchor,"Cold pending Story opens the actual historical replay viewer")
	if not is_instance_valid(viewer):
		await _dispose_ui(c)
		return
	viewer.set_process(false)
	viewer.set_physics_process(false)
	viewer.world.set_process(false)
	viewer._notification(NOTIFICATION_APPLICATION_RESUMED)
	var cursor: int = viewer.cursor
	for tick in range(6): viewer._physics_process(1.0/30.0)
	_check(viewer.cursor > cursor and Canonical.same(before,c.h.store.saved),"Actual cold replay consumes accepted inputs while the original pending turn and every saved scope stay unchanged")
	viewer._pause()
	await _main_click(c,"Back",viewer.controls.overlay)
	await _wait_replay(c,"shared_memories")
	await _main_click(c,"Back")
	await _main_click(c,"Back")
	await _main_click(c,"Resume")
	for frame in range(120):
		if is_instance_valid(c.app.relay_child): break
		await process_frame
	var child: Node = c.app.relay_child
	_check(is_instance_valid(child) and child.mode == "online_waiting" and not child.running and Canonical.same(child.journey.pending(),pending),"Replay Back then Resume returns to the exact cold pending current room instead of replacing or resubmitting it")
	_check(Canonical.same(before,c.h.store.saved) and _only_gets(c.h.calls.slice(calls)) and c.online.last_room() == FAR_ROOM and c.owner.selected_room() == FAR_ROOM,"Cold replay round trip preserves request, draft, selection and all control bytes with GET-only traffic")
	await _dispose_ui(c)

func _preserve_pending() -> void:
	var c := await _replay_case()
	var record := _json("res://tests/fixtures/journey/a-light-above-a.json")
	_check(c.online.coordinator.save_draft(record) and not await c.online.coordinator.commit(record),"Current chapter retains a genuine native rehearsal and lost A request")
	var pending: Dictionary = c.online.coordinator.pending()
	_check(not pending.is_empty(),"The pending preservation case contains a real idempotent request")
	c.before = c.h.store.saved.duplicate(true)
	await _main_click(c,"Shared replays")
	await _main_click(c,"1 · "+str(Registry.descriptor(Registry.HIGH_AND_LOW).title))
	await _wait_replay(c,"shared_memories")
	_unchanged(c,"Read-only older chapter discovery preserves the actual pending request and rehearsal byte-for-byte")
	_check(Canonical.same(pending,c.online.coordinator.pending()) and Canonical.same(record,c.online.coordinator.draft()),"Replay reading neither reconciles nor discards the current contribution")
	await _dispose_ui(c)

func _simulation_pin() -> void:
	var c := await _replay_case()
	var old := _room("high-and-low","FFFFFFFFFFFFFFFFFFFFFF",true)
	var level := Registry.definition(Registry.FIRST_STEPS)
	old["level_id"] = level.id
	old["level_version"] = level.version
	old["definition_hash"] = Canonical.digest(level)
	old["simulation_version"] = 4
	old["checkpoint"] = _json("res://tests/fixtures/first_steps/final-checkpoint.json")
	var collection := Collection.new(c.h,c.h.identity,c.cache,c.h.store,CacheFactory.new())
	_check(collection.rooms().is_empty() and collection._owner == HOST,"Public collection discovery binds the actual owner before importing retained ordinary evidence")
	_check(collection._remember_room(old,"chapter"),"Retained real First Steps simulation4 proof remains a valid ordinary replay")
	var descriptor := Registry.descriptor(Registry.FIRST_STEPS)
	var pin := {"level_id":descriptor.level_id,"level_version":descriptor.level_version,"definition_hash":descriptor.definition_hash,"simulation_version":5,"premium":false}
	var selection := {"room_id":old.room_id,"chapter":pin,"host_id":HOST,"guest_id":GUEST}
	var raw: Dictionary = c.cache.values.duplicate(true)
	_check(collection.cached_story_chapter(selection).is_empty() and Canonical.same(raw,c.cache.values),"Same level/hash/members cannot silently reuse simulation4 for a Story simulation5 pin")
	var scope: String = "shared-replays:"+HOST+":index"
	c.cache.values[scope]["schema_version"] = 99
	raw = c.cache.values.duplicate(true)
	var future := Collection.new(c.h,c.h.identity,c.cache,c.h.store,CacheFactory.new())
	_check(future.cached_story_chapter(selection).is_empty() and (await future.open_story_chapter(selection)).is_empty() and Canonical.same(raw,c.cache.values),"Future replay envelope is held and preserved without overwrite")
	await _dispose_ui(c)

func _refusal(kind: String) -> void:
	var c := await _replay_case()
	if kind == "wrong_member": c.h.rooms[c.anchor]["guest_id"] = OTHER
	elif kind == "wrong_pin": c.h.rooms[c.anchor]["simulation_version"] = 5
	elif kind == "bad_proof": c.h.rooms[c.anchor].checkpoint.proof.b["final_state_hash"] = "0".repeat(64)
	elif kind == "missing": c.h.rooms.erase(c.anchor)
	elif kind == "save": c.cache.fail = true
	elif kind == "capacity":
		var rooms := {}
		for index in range(256):
			var id := ("cache-room-"+str(index)).sha256_text().substr(0,22)
			rooms["chapter:"+id] = {"family":"chapter","room_id":id,"host_id":HOST,"guest_id":GUEST,"chapter_key":Registry.HIGH_AND_LOW,"title":"High and Low"}
		c.cache.values["shared-replays:"+HOST+":index"] = {"schema_version":1,"owner":HOST,"rooms":rooms}
	var raw: Dictionary = c.cache.values.duplicate(true)
	_check((await c.app.shared_replays.open_story_chapter(c.selection)).is_empty(),"Exact Story discovery holds "+kind)
	_check(Canonical.same(raw,c.cache.values),"Failed discovery preserves the full replay cache: "+kind)
	_unchanged(c,"Failed discovery preserves active native authority and every pending journal: "+kind)
	if kind == "capacity":
		# Preserve the same legal 256-entry count, with the explicit target already
		# indexed. Existing-room cache refresh must still work at capacity.
		var index_scope := "shared-replays:"+HOST+":index"
		var entries: Dictionary = c.cache.values[index_scope].rooms
		entries.erase(entries.keys()[0])
		entries["chapter:"+c.anchor] = {"family":"chapter","room_id":c.anchor,"host_id":HOST,"guest_id":GUEST,"chapter_key":Registry.HIGH_AND_LOW,"title":"High and Low"}
		var existing := Collection.new(c.h,c.h.identity,c.cache,c.h.store,c.online.auxiliary_context_factory())
		_check(not (await existing.open_story_chapter(c.selection)).is_empty() and existing.rooms().size() == 256,"Existing indexed Story room stays usable at the unchanged256-room capacity")
		_unchanged(c,"Capacity reuse still changes no active or pending gameplay state")
	await _dispose_ui(c)

func _publication_rows() -> void:
	for activation: bool in [false,true]:
		var c := await _replay_case(false,activation,2 if activation else 1)
		await _main_click(c,"Shared replays")
		var rows: Array = c.app._story_replay_rows()
		_check(rows.size() == 2 and not rows.any(func(row: Dictionary): return row.selection.room_id == FAR_ROOM),"Chooser excludes "+("activation debt" if activation else "unpublished target"))
		var selection := {"room_id":FAR_ROOM,"chapter":fixture.definition.chapters[2].duplicate(true),"host_id":HOST,"guest_id":GUEST}
		var calls: int = c.h.calls.size()
		await c.app._open_story_replay_chapter(selection)
		_check(c.h.calls.size() == calls and c.app.mode == "story_replay_chapters" and Canonical.same(c.before,c.h.store.saved),"A stale direct row callback cannot activate, fetch or select the unavailable target")
		await _dispose_ui(c)

func _late_result(kind: String) -> void:
	var c := await _replay_case()
	await _main_click(c,"Shared replays")
	c.h.hold = true
	var done := {"value":false}
	var open := func():
		await c.app._open_story_replay_chapter(c.selection)
		done.value = true
	open.call()
	await process_frame
	_check(c.h.busy,"Target GET is genuinely in flight before the lifetime change")
	if kind == "back": c.app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	elif kind == "identity":
		c.h.identity_value["epoch"] += 1
	else: c.owner.invalidate_identity()
	c.h.hold = false
	c.h.release.emit()
	for frame in range(240):
		if done.value: break
		await process_frame
	_check(done.value and c.app.mode != "shared_memories" and not is_instance_valid(c.app.shared_replay_child),"Late result cannot reopen a dismissed or retired Story: "+kind)
	_check(Canonical.same(c.before,c.h.store.saved),"Late result cannot alter gameplay/control journals: "+kind)
	if kind != "back": _check(c.cache.writes == 0,"Retired authority cannot write replay evidence after the await")
	await _dispose_ui(c)

func _busy_reentry() -> void:
	var c := await _replay_case()
	await _main_click(c,"Shared replays")
	c.h.hold = true
	var done := {"value":false}
	var open := func():
		await c.app._open_story_replay_chapter(c.selection)
		done.value = true
	open.call()
	await process_frame
	_check(c.h.busy and c.app.shared_replays.busy(),"Discovery is actually delayed before Back and immediate reentry")
	c.app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(c.app.mode == "story_lobby","Back leaves the outstanding discovery on a usable Story lobby")
	var calls: int = c.h.calls.size()
	await _main_click(c,"Shared replays")
	_check(c.app.mode == "story_lobby" and c.h.calls.size() == calls,"Immediate reentry defers until the original request settles instead of drawing disabled rows")
	c.h.hold = false
	c.h.release.emit()
	for frame in range(240):
		if done.value: break
		await process_frame
	_check(done.value and c.app.mode == "story_lobby" and not is_instance_valid(c.app.shared_replay_child),"Dismissed discovery never repaints or opens its obsolete view")
	await _main_click(c,"Shared replays")
	await _main_click(c,"1 · "+str(Registry.descriptor(Registry.HIGH_AND_LOW).title))
	await _wait_replay(c,"shared_memories")
	_unchanged(c,"Explicit entry after idle works without changing the active Story or pending stores")
	await _dispose_ui(c)

func _late_memory(operation: String, identity_change: bool) -> void:
	var c := await _replay_case()
	await _main_click(c,"Shared replays")
	await _main_click(c,"1 · "+str(Registry.descriptor(Registry.HIGH_AND_LOW).title))
	await _wait_replay(c,"shared_memories")
	var key := _empty_replay_cache(c)
	var pair := _archive_pair(_json("res://tests/fixtures/cooperative/upper-path-checkpoint.json"))
	var path := "/v2/rooms/"+str(c.anchor)
	c.h.replay_replies[path+"/collection"] = {"ok":true,"status":200,"data":{"pairs":[_archive_summary(pair)]}}
	c.h.replay_replies[path+"/pairs/p0-0"] = {"ok":true,"status":200,"data":pair}
	var rows: Array = await c.app.shared_replays.refresh_memories(key)
	_check(rows.size() == 1 and not rows[0].cached,"Delayed archive case starts with an uncached real native pair")
	if rows.size() != 1:
		await _dispose_ui(c)
		return
	c.app._draw_shared_replay_memories(rows)
	var saved: Dictionary = c.h.store.saved.duplicate(true)
	var cached: Dictionary = c.cache.values.duplicate(true)
	var calls: int = c.h.calls.size()
	var done := {"value":false}
	c.h.hold = true
	var request := func():
		if operation == "refresh": await c.app._refresh_shared_replay_memories()
		else: await c.app._open_shared_memory(key,rows[0])
		done.value = true
	request.call()
	await process_frame
	_check(c.h.busy and c.app.shared_replays.busy(),"The actual Main "+operation+" handler waits on a real scoped GET")
	c.app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(c.app.mode == "story_replay_chapters","Back from delayed "+operation+" returns to the chapter chooser")
	if identity_change:
		c.h.identity_value["epoch"] += 1
		c.app._show_home()
	c.h.hold = false
	c.h.release.emit()
	for frame in range(240):
		if done.value and not c.h.busy and not c.app.shared_replays.busy(): break
		await process_frame
	await _settle()
	_check(done.value and not is_instance_valid(c.app.shared_replay_child),"A delayed "+operation+" cannot open a viewer after Back or identity replacement")
	_check(Canonical.same(saved,c.h.store.saved) and _only_gets(c.h.calls.slice(calls)),"Delayed archive work never changes gameplay/control scopes or sends a mutation")
	if identity_change:
		_check(c.app.mode == "home" and Canonical.same(cached,c.cache.values),"Retired identity receives neither the old screen nor a late cached pair")
	else:
		var first := _button(c.app.overlay,"1 · "+str(Registry.descriptor(Registry.HIGH_AND_LOW).title))
		_check(c.app.mode == "story_replay_chapters" and first != null and not first.disabled,"Current chooser repaints usable rows after the older "+operation+" settles")
		await _main_click(c,"1 · "+str(Registry.descriptor(Registry.HIGH_AND_LOW).title))
		await _wait_replay(c,"shared_memories")
		_unchanged(c,"Explicit replay reopening after a delayed "+operation+" preserves current native selection")
	await _dispose_ui(c)

func _seven_rows() -> void:
	var c := await _replay_case()
	# Extend the finite synthetic definition before replacing its real owner.
	var keys: Array[String] = [Registry.HOUSE,Registry.FIRST_STEPS,Registry.RELAY,Registry.LONG_WAY_HOME]
	for key: String in keys:
		var descriptor := Registry.descriptor(key)
		fixture.definition.chapters.append({"level_id":descriptor.level_id,"level_version":descriptor.level_version,"definition_hash":descriptor.definition_hash,"simulation_version":descriptor.simulation_version,"premium":descriptor.premium})
		story_content.chapters.append({"level_id":descriptor.level_id,"level_version":descriptor.level_version,"arrival":[{"speaker":"p0","text":"Synthetic replay place."}],"completion":[{"speaker":"p1","text":"Synthetic replay memory."}]})
	var content: Dictionary = story_content.duplicate(true)
	content.erase("content_hash")
	story_content["content_hash"] = Canonical.digest(content)
	fixture.definition["story"] = StorySource.pin(story_content)
	var body: Dictionary = fixture.definition.duplicate(true)
	body.erase("definition_hash")
	fixture.definition["definition_hash"] = Canonical.digest(body)
	var publication: Dictionary = c.h.view.duplicate(true)
	publication["campaign_key"] = Protocol.key(fixture.definition)
	publication["current_index"] = 6
	publication["revision"] = 20
	for index in range(2,7):
		if index >= publication.chapters.size(): publication.chapters.append({"chapter":fixture.definition.chapters[index].duplicate(true),"room_id":("published-"+str(index)).sha256_text().substr(0,22),"completion":null})
		if index < 6: publication.chapters[index]["completion"] = {"source_revision":5,"source_branch":0,"checkpoint_hash":"a".repeat(64),"transition_id":("complete-"+str(index)).sha256_text(),"from_campaign_revision":index*2+2,"accepted_campaign_revision":index*2+3}
	_check(Protocol.view_valid(publication,fixture.definition,HOST),"Seven published entries remain a strictly bounded valid control prefix")
	# Use a fresh owner/store for this alternate immutable synthetic manifest.
	c.owner.invalidate_identity()
	c.h.store = RestoreStore.new()
	c.h.view = publication
	c.online = Online.new(c.h,c.h.identity,c.h.store)
	c.owner = Owner.new(c.online,c.h.identity,[fixture.definition],c.h.leave_ready,c.h.store)
	_check(c.owner.restore_owner() and c.owner.bind_campaign(c.anchor,Protocol.key(fixture.definition)) and await c.owner.refresh(),"Finite seven-row fixture is admitted through the real owner")
	c.app.campaign_owner = c.owner
	c.app.relay_session = c.online
	c.app.campaign_catalog = [{"definition":fixture.definition.duplicate(true),"story":story_content.duplicate(true)}]
	c.app.shared_replays = Collection.new(c.h,c.h.identity,c.cache,c.h.store,c.online.auxiliary_context_factory())
	c.app._draw_story_lobby()
	var calls: int = c.h.calls.size()
	await _main_click(c,"Shared replays")
	_check(c.app._story_replay_rows().size() == 7 and c.cache.writes == 0 and c.h.calls.size() == calls,"Displaying seven chapters performs no bulk room materialization or HTTP")
	var button := _button(c.app.overlay,"1 · "+str(Registry.descriptor(Registry.HIGH_AND_LOW).title))
	var scroll: Node = button.get_parent()
	while scroll != null and not scroll is ScrollContainer: scroll = scroll.get_parent()
	var old_emulation: bool = Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	await _drag(c.viewport,button.get_global_rect().get_center(),Vector2(0,-190))
	Input.emulate_touch_from_mouse = old_emulation
	_check(scroll.scroll_vertical > 0 and c.app.mode == "story_replay_chapters" and c.h.calls.size() == calls,"A real drag beginning on a nested chapter button scrolls without opening or fetching it")
	_check(c.viewport.get_visible_rect().encloses(_button(c.app.overlay,"Back").get_global_rect()),"Fixed chooser Back stays visible below seven scrollable rows")
	await _dispose_ui(c)

extends "res://tests/test_campaign_handoff.gd"
const CameraHold = preload("res://presentation/story_camera.gd")

func _run() -> void:
	await _held_source("p0")
	await _held_source("p1")
	await _context_loss_camera()
	await _suspended_relayout()
	await _compact_native_frame(true)
	await _compact_native_frame(false)
	await _compact_flow_cancel()
	print("Story camera ownership: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _camera_state(camera: Camera3D) -> Dictionary:
	return {"transform":camera.global_transform,"size":camera.size,"keep_aspect":camera.keep_aspect,"h_offset":camera.h_offset,"v_offset":camera.v_offset,"projection":camera.projection,"fov":camera.fov}

func _held_source(slot: String) -> void:
	var c := await _warm_setup(slot)
	var camera: Camera3D = c.child.world.camera
	var exploration: Node = c.child.world.camera_exploration
	exploration.zoom_ratio = 0.84
	exploration.pan = Vector2(0.07,-0.03)
	exploration._idle = 5.2
	exploration._returning = true
	exploration._return_age = 0.2
	exploration._return_zoom = 0.78
	exploration._return_pan = Vector2(0.12,-0.05)
	exploration.apply_frame()
	var before := _camera_state(camera)
	var hold := CameraHold.new()
	var explorer_before: Dictionary = hold._capture_fields(exploration,CameraHold.EXPLORATION_FIELDS)
	var follow_before: Dictionary = hold._capture_fields(c.child.world,CameraHold.FOLLOW_FIELDS)
	var room: Dictionary = c.child.journey.snapshot()
	var actor_positions := {}
	for key: String in c.child.world.actors: actor_positions[key] = c.child.world.actors[key].global_transform
	_check(c.flow.present_handoff(c.child,0,c.replace), "Camera frame starts only at an accepted stable source: "+slot)
	await process_frame
	await process_frame
	_check(exploration.manual and not exploration.is_processing() and not c.child.world.is_processing(), "Story suspends both exploration and authored follow updates")
	_check(_points_above_card(c), "Both spirit bounds and the garden sit above the settled dialogue rectangle")
	var token: int = c.child._story_hold
	var framed := _camera_state(camera)
	c.child.release_story(token-1)
	_check(_camera_state(camera) == framed, "A stale hold cannot restore or move the current Story camera")
	_check(c.viewport.size != Vector2i(1280,720), "Resize test actually changes the viewport size")
	c.viewport.size = Vector2i(1280,720)
	await process_frame
	await process_frame
	_check(_points_above_card(c), "Viewport resize recomputes framing from the settled card instead of accumulating pan")

	c.flow._panel.safe_rect_override = Rect2(130,30,1030,660)
	c.flow._panel.text_scale = 1.5
	c.flow._panel._layout()
	await process_frame
	await process_frame
	_check(_points_above_card(c), "Large-text relayout and landscape cutouts keep both spirits and garden within the shared safe area")
	c.h.store.fail_scope = "relay-campaign-v1:"+c.player+":"+c.anchor
	c.flow._panel._advance()
	await process_frame
	await process_frame
	_check(c.flow._panel.error.visible and _points_above_card(c), "A save-error card relayout remains framed without changing passage ownership")
	for key: String in actor_positions:
		_check(c.child.world.actors[key].global_transform == actor_positions[key], "Framing never moves native actor roots: "+key)
	_check(Canonical.same(room,c.child.journey.snapshot()), "Framing does not rewrite a checkpoint or recording")
	c.flow.invalidate()
	_check(_camera_state(camera) == before, "Ordinary cancellation restores the exact original camera projection and transform")
	_check(hold._capture_fields(exploration,CameraHold.EXPLORATION_FIELDS) == explorer_before and hold._capture_fields(c.child.world,CameraHold.FOLLOW_FIELDS) == follow_before, "Cancellation restores prior exploration return state and authored follow targets")
	await _dispose(c)

func _points_above_card(c: Dictionary) -> bool:
	var helper := CameraHold.new()
	var camera: Camera3D = c.child.world.camera
	var bounds: Rect2 = helper._screen_bounds(camera,helper._points(c.child.world,true))
	var viewport: Rect2 = c.flow._story_safe_rect()
	return bounds.position.x >= viewport.position.x+12 and bounds.end.x <= viewport.end.x-12 and bounds.position.y >= viewport.position.y+12 and bounds.end.y <= c.flow._panel.card.get_global_rect().position.y-12

func _context_loss_camera() -> void:
	var c := await _warm_setup()
	var camera: Camera3D = c.child.world.camera
	var before := _camera_state(camera)
	_check(c.flow.present_handoff(c.child,0,c.replace), "Context-loss camera test opens a genuine stable passage")
	await process_frame
	c.h.identity_value.epoch += 1
	c.flow._panel._advance()
	_check(c.child.mode == "error" and c.child.overlay.visible and not c.child.running and _camera_state(camera) == before, "Identity loss restores the source camera before leaving its recovery card visible")
	await _dispose(c)


func _suspended_relayout() -> void:
	var c := await _warm_setup()
	_check(c.flow.present_handoff(c.child,0,c.replace), "Background test holds an actual completed source")
	var line: String = c.flow._panel.dialogue.text
	var token: int = c.child._story_hold
	c.flow._queue_story_frame()
	c.child._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	c.viewport.size = Vector2i(1280,720)
	await process_frame
	await process_frame
	_check(c.flow.busy() and c.flow._panel.dialogue.text == line and c.child._story_hold == token and c.child.mode == "complete", "Queued frame and resize while suspended preserve the exact passage instead of entering recovery")
	c.child._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await process_frame
	await process_frame
	_check(c.flow.busy() and _points_above_card(c), "Foreground validates context then reframes the still-owned passage")
	await _dispose(c)


func _compact_native_frame(initially_visible: bool) -> void:
	var c := await _warm_setup()
	c.viewport.size = Vector2i(960,540)
	await process_frame
	await process_frame
	var world: Node3D = c.child.world
	world.visible = initially_visible
	var camera: Camera3D = world.camera
	var before := _camera_state(camera)
	var hold := CameraHold.new()
	var native: Dictionary = c.child.journey.snapshot()
	var saved: Dictionary = c.h.store.saved.duplicate(true)
	var actor_positions := {}
	for key: String in world.actors: actor_positions[key] = world.actors[key].global_transform
	var world_processing := world.is_processing()
	var exploration: Node = world.camera_exploration
	var exploration_processing := exploration.is_processing()
	var exploration_input := exploration.is_processing_input()
	var explorer_before := hold._capture_fields(exploration,CameraHold.EXPLORATION_FIELDS)
	var follow_before := hold._capture_fields(world,CameraHold.FOLLOW_FIELDS)
	var normal := Rect2(50,210,860,310)
	var compact := Rect2(50,55,860,465) # Actual960/1.5 card leaves a7px world strip.
	var safe := Rect2(0,0,960,540)
	_check(hold.begin(world,701) and hold.frame(701,normal,true,safe),"Native completed scene accepts a token-owned normal camera frame")
	var framed := _camera_state(camera)
	var bounds := hold._screen_bounds(camera,hold._points(world,true))
	_check(world.visible == initially_visible and Rect2(12,12,936,186).encloses(bounds),"Normal frame preserves original visibility and fits real spirit/garden bounds above the card")
	_check(hold.frame(701,compact,true,safe) and not world.visible and _camera_state(camera) == before,"Actual compact card gets a neutral world fallback with the exact original camera, not a zoomed miniature")
	_check(hold.frame(701,Rect2(50,20,860,500),true,safe) and not world.visible and _camera_state(camera) == before,"No remaining above-card space also uses the stable neutral fallback")
	_check(not hold.frame(700,normal,true,safe),"An older token cannot re-show or reframe a compact world")
	hold.restore(700)
	_check(not world.visible and _camera_state(camera) == before and not world.is_processing(),"Stale restore preserves the current compact hold and suspended presentation")
	_check(hold.frame(701,normal,true,safe) and world.visible == initially_visible and _camera_state(camera) == framed,"Compact-to-normal relayout restores exactly the prior visibility and repeatable normal frame")
	_check(hold.frame(701,compact,true,safe),"A second compact frame stays owned until release")
	hold.restore(701)
	_check(world.visible == initially_visible and _camera_state(camera) == before and world.is_processing() == world_processing,"Valid release from compact restores the original hidden/visible state, camera and world processing")
	_check(exploration.is_processing() == exploration_processing and exploration.is_processing_input() == exploration_input and hold._capture_fields(exploration,CameraHold.EXPLORATION_FIELDS) == explorer_before and hold._capture_fields(world,CameraHold.FOLLOW_FIELDS) == follow_before,"Compact release preserves exploration and follow state exactly")
	_check(not hold.frame(701,compact,true,safe) and world.visible == initially_visible,"Retired token cannot hide a restored world")
	for key: String in actor_positions:
		_check(world.actors[key].global_transform == actor_positions[key],"Compact fallback never changes native actor transform: "+key)
	_check(Canonical.same(native,c.child.journey.snapshot()) and Canonical.same(saved,c.h.store.saved),"Normal/compact/release never mutate native proof, gameplay or Story journals")
	await _dispose(c)

func _compact_flow_cancel() -> void:
	var c := await _warm_setup()
	c.viewport.size = Vector2i(960,540)
	c.child.settings["text_scale"] = 1.5
	await process_frame
	await process_frame
	var world: Node3D = c.child.world
	var camera: Camera3D = world.camera
	var before := _camera_state(camera)
	var was_visible := world.visible
	var saved: Dictionary = c.h.store.saved.duplicate(true)
	var native: Dictionary = c.child.journey.snapshot()
	_check(c.flow.present_handoff(c.child,0,c.replace),"Real completion Flow opens large text over the verified native source")
	await process_frame
	await process_frame
	_check(c.flow.busy() and c.flow._panel.is_open() and c.flow._active.memory_token < 0 and not world.visible and _camera_state(camera) == before,"Actual native completion uses compact neutral fallback without substituting a memory illustration")
	var text: String = c.flow._panel.dialogue.text
	c.flow.invalidate()
	_check(not c.flow.busy() and world.visible == was_visible and _camera_state(camera) == before and not c.child.running,"Flow cancellation restores the source world and camera without starting gameplay")
	_check(not text.is_empty() and c.online.coordinator == c.child.journey and Canonical.same(native,c.child.journey.snapshot()) and Canonical.same(saved,c.h.store.saved),"Cancelled compact dialogue neither adopts a target nor persists seen progress or native changes")
	await _dispose(c)

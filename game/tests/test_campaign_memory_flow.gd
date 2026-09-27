extends "res://tests/test_campaign_cold_dialogue.gd"
## Actual Flow, panel and isolated illustration; synthetic story and transport.
const MemorySource = preload("res://presentation/story_memory_backdrop.gd")
const PanelSource = preload("res://presentation/story_panel.gd")

class RefusingMemory:
	extends MemorySource
	func present(_generation: int, _passage: String, _chapter: String, _phase: String, _title: String, _panel: Rect2, _safe: Rect2) -> int:
		return -1

class RefusingPanel:
	extends PanelSource
	func present(_title: String, _lines: Array, _between_turns: bool) -> bool:
		return false

func _run() -> void:
	for slot: String in ["p0","p1"]:
		await _illustrated_arrival(slot)
		await _cold_tokens(slot)
	await _history_setting()
	await _actual_completion_worlds()
	await _save_error_and_compact()
	await _suspended_memory()
	await _replacement_during_save()
	await _failed_memory_open(false)
	await _failed_memory_open(true)
	await _retired_child()
	print("Campaign memory composition: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _native_camera(c: Dictionary) -> Dictionary:
	var camera: Camera3D = c.child.world.camera
	return {"transform":camera.global_transform,"size":camera.size,"projection":camera.projection,
		"keep_aspect":camera.keep_aspect,"fov":camera.fov,"h_offset":camera.h_offset,"v_offset":camera.v_offset}

func _memory_matches(c: Dictionary, key: String, phase: String) -> bool:
	var context: Dictionary = c.flow._active
	if context.is_empty() or not is_instance_valid(c.flow._memory._world): return false
	return c.flow._memory.matches(int(context.get("memory_token",-1)),int(context.generation),str(context.get("passage_identity",""))) and c.flow._memory._world.chapter_key == key and c.flow._memory._world.phase == phase

func _illustrated_arrival(slot: String) -> void:
	var c := await _setup(slot,false)
	c.child.story_flow = c.flow
	var camera := _native_camera(c)
	var saved := _without_seen(c)
	var snapshot: Dictionary = c.child.journey.snapshot()
	var calls: int = c.h.calls.size()
	_check(c.flow.present_arrival(c.child,0),"Actual arrival opens for both physical viewing roles: "+slot)
	_check(_memory_matches(c,Registry.HIGH_AND_LOW,"arrival"),"Arrival illustrates its immutable chapter pin rather than current route geometry")
	_check(c.flow._panel.heading.text == Registry.descriptor(Registry.HIGH_AND_LOW).title+" · Arrival","Dialogue heading identifies the chapter even without illustration space")
	_check(c.flow._memory.layer < c.flow._panel.layer and c.flow._memory._root.mouse_filter == Control.MOUSE_FILTER_IGNORE,"Memory sits below the existing input-owning panel")
	_check(c.flow._memory._viewport.world_3d != c.viewport.world_3d and c.flow._memory._viewport.gui_disable_input,"Memory never becomes the gameplay world or an input destination")
	await process_frame
	await process_frame
	_check(_native_camera(c) == camera and Canonical.same(snapshot,c.child.journey.snapshot()),"Opening and settling memory does not reframe or mutate the native route")
	var old: WeakRef = weakref(c.flow._memory._root)
	c.child._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(not c.flow.busy() and c.flow._memory._root == null and c.child._story_hold == -1,"Native Back disposes the matching illustration and releases the existing hold")
	_check(c.owner.story_seen(0,"arrival") and Canonical.same(saved,_without_seen(c)) and c.h.calls.size() == calls,"Explicit Skip changes only its existing seen marker, without network or rewards")
	await process_frame
	_check(old.get_ref() == null,"The detached artwork tree is actually disposed")
	await _dispose(c)

func _cold_tokens(slot: String) -> void:
	var c := await _cold_setup(slot)
	var camera := _native_camera(c)
	var saved := _without_seen(c)
	var calls: int = c.h.calls.size()
	_check(c.flow.present_arrival(c.child,2),"Cold queue begins with the accepted previous completion")
	_check(_memory_matches(c,Registry.ROLLING_HOME,"completion"),"Previous completion has its own earlier-place illustration")
	var old: Dictionary = c.flow._active.duplicate()
	var old_root: WeakRef = weakref(c.flow._memory._root)
	var hold: int = c.child._story_hold
	c.flow._queue_story_frame() # Deliberately leave an old frame callback queued.
	c.flow._panel._advance()
	_check(c.child._story_hold == hold and c.flow._active.passage_serial != old.passage_serial and c.flow._active.memory_token != old.memory_token,"Same native hold does not reuse passage identity or artwork token")
	_check(_memory_matches(c,Registry.CONSERVATORY,"arrival") and c.flow._panel.heading.text == Registry.descriptor(Registry.CONSERVATORY).title+" · Arrival","The next beat changes both illustration and visible chapter context")
	var current: Dictionary = c.flow._active.duplicate()
	var rect: Rect2 = c.flow._memory._picture.get_rect()
	c.flow._panel.card.position.y -= 20
	c.flow._frame_active_story(int(old.generation),int(old.passage_serial))
	c.flow._clear_memory(old)
	c.flow._release(old)
	c.flow._context_lost(old)
	_check(c.flow._memory._picture.get_rect() == rect and _memory_matches(c,Registry.CONSERVATORY,"arrival"),"Stale same-hold frame, clear, release and context-loss callbacks cannot affect the next beat")
	_check(c.flow.busy() and c.child._story_hold == hold and not c.child.overlay.visible,"An old beat cannot release the shared native hold")
	c.flow._panel._layout()
	await process_frame
	await process_frame
	_check(old_root.get_ref() == null and _memory_matches(c,Registry.CONSERVATORY,"arrival"),"Queued stale layout cannot restore the disposed previous illustration")
	_check(_native_camera(c) == camera and c.flow._active.passage_identity == current.passage_identity,"Both cold phases preserve the exact native camera and current passage identity")
	c.flow._panel._skip()
	_check(c.flow._memory._root == null and not c.flow.busy() and c.owner.story_seen(1,"completion") and c.owner.story_seen(2,"arrival"),"Only the captured cold phases settle after the last illustration closes")
	_check(Canonical.same(saved,_without_seen(c)) and c.h.calls.size() == calls and not c.owner.story_seen(0,"arrival"),"Memory sequencing leaves older unread history and all non-cosmetic state intact")
	await _dispose(c)

func _history_setting() -> void:
	var c := await _cold_setup("p0",true)
	var camera := _native_camera(c)
	var snapshot: Dictionary = c.child.journey.snapshot()
	var saved := _without_seen(c)
	var calls: int = c.h.calls.size()
	_check(c.flow.present_history(c.child,0,"arrival") and _memory_matches(c,Registry.HIGH_AND_LOW,"arrival"),"Old History uses its own setting even while the current native chapter is complete")
	_check(c.flow._panel.heading.text == Registry.descriptor(Registry.HIGH_AND_LOW).title+" · Arrival","History identifies the recalled chapter and phase")
	c.flow._panel._skip()
	_check(c.flow.present_history(c.child,1,"completion") and _memory_matches(c,Registry.ROLLING_HOME,"completion"),"An earlier accepted completion is illustrated without restoring an old gameplay room")
	c.flow._panel._skip()
	_check(_native_camera(c) == camera and Canonical.same(snapshot,c.child.journey.snapshot()) and Canonical.same(saved,_without_seen(c)) and c.h.calls.size() == calls,"History memory preserves the actual final world, selection, pending data and transport")
	_check(c.flow.present_history(c.child,2,"completion") and c.flow._memory._root == null and c.flow._active.memory_token == -1,"Exact verified current completion History keeps its actual native finale scene")
	_check(c.flow._panel.heading.text == Registry.descriptor(Registry.CONSERVATORY).title+" · Completion","Actual-scene History retains the same explicit chapter heading")
	c.flow._panel._skip()
	await _dispose(c)

func _actual_completion_worlds() -> void:
	var c := await _warm_setup()
	var calls: int = c.h.calls.size()
	_check(c.flow.present_handoff(c.child,0,c.replace) and c.flow._memory._root == null,"Warm source completion stays on the real completed native world")
	var old: Dictionary = c.flow._active.duplicate()
	c.flow._panel._advance()
	var next: Node = c.main.relay_child
	_check(next != c.child and _memory_matches(c,Registry.ROLLING_HOME,"arrival"),"Authoritative warm adoption finishes before the destination arrival illustration opens")
	c.flow._clear_memory(old)
	c.flow._release(old)
	_check(c.flow.busy() and c.flow._memory._root != null and next._story_hold >= 0,"Retired source cleanup cannot clear the destination's arrival")
	c.flow._panel._skip()
	_check(c.h.calls.size() == calls and c.flow._memory._root == null,"Warm presentation and memory disposal add no network request")
	await _dispose(c)
	c = await _cold_setup("p0",true)
	_check(c.flow.present_finale(c.child,2) and c.flow._memory._root == null and c.child.journey.chapter_complete(),"Terminal finale preserves its verified native completion instead of an illustration")
	c.flow._panel._advance()
	await _dispose(c)

func _save_error_and_compact() -> void:
	var c := await _cold_setup()
	var camera := _native_camera(c)
	c.h.store.fail_scope = _campaign_scope(c)
	_check(c.flow.present_arrival(c.child,2),"Save-error case owns an actual illustrated cold phase")
	var context: Dictionary = c.flow._active.duplicate()
	c.flow._panel._advance()
	await process_frame
	_check(c.flow._panel.error.visible and _memory_matches(c,Registry.ROLLING_HOME,"completion") and c.flow._active.memory_token == context.memory_token,"Cosmetic save failure keeps the same illustration/token for Retry")
	c.flow._panel.text_scale = 1.5
	c.flow._panel.safe_rect_override = Rect2(20,30,920,500)
	c.flow._panel._layout()
	await process_frame
	await process_frame
	# Simulate the settled compact card geometry through Flow's real frame path.
	c.flow._panel.card.position.y = c.flow._story_safe_rect().position.y+45
	c.flow._frame_active_story(int(context.generation),int(context.passage_serial))
	_check(not c.flow._memory._caption.visible and not c.flow._memory._picture.visible and c.flow._panel.heading.text == Registry.descriptor(Registry.ROLLING_HOME).title+" · Completion","Compact fallback retains passage context in the unchanged panel heading")
	_check(_native_camera(c) == camera,"Save-error and compact reframing leave gameplay camera untouched")
	c.flow._panel._skip()
	_check(c.flow._memory._root == null and not c.flow.busy() and not c.owner.story_seen(1,"completion"),"Close after failed save disposes memory without inventing a read marker")
	await _dispose(c)

func _suspended_memory() -> void:
	var c := await _setup("p0",false)
	c.child.story_flow = c.flow
	_check(c.flow.present_arrival(c.child,0),"Foreground-redraw fixture opens a real arrival")
	var context: Dictionary = c.flow._active.duplicate()
	var camera := _native_camera(c)
	c.flow._memory._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	c.flow._queue_story_frame()
	c.child._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	c.viewport.size = Vector2i(1280,720)
	await process_frame
	await process_frame
	_check(c.flow.busy() and c.flow._active.memory_token == context.memory_token and c.flow._memory._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"Suspended queued layouts keep the same passage without requesting new art renders")
	c.child._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_check(c.flow._memory._viewport.render_target_update_mode == SubViewport.UPDATE_ONCE,"Validated foreground resume requests one fresh render even before changed-bounds framing")
	await process_frame
	await process_frame
	_check(_memory_matches(c,Registry.HIGH_AND_LOW,"arrival") and _native_camera(c) == camera,"Foreground preserves the active passage and does not reframe the hidden native world")
	c.h.identity_value.epoch += 1
	c.flow._queue_story_frame()
	await process_frame
	_check(not c.flow.busy() and c.flow._memory._root == null and c.child._story_context_lost,"Identity drift disposes illustration before exposing the existing recovery card")
	await _dispose(c)

func _replacement_during_save() -> void:
	var c := await _cold_setup()
	var observer := SeenObserver.new(c.owner)
	_check(c.flow.configure(observer,c.h.identity,c.content),"Post-save observer delegates every authority check to the actual Owner")
	_check(c.flow.present_arrival(c.child,2),"Synchronous callback case begins with an old illustrated passage")
	var old: Dictionary = c.flow._active.duplicate()
	var switched := [false]
	observer.after_mark = func():
		switched[0] = c.flow.configure(c.owner,c.h.identity,c.content) and c.flow.present_arrival(c.child,2)
	c.flow._panel._skip()
	_check(switched[0] and _memory_matches(c,Registry.CONSERVATORY,"arrival") and c.flow._active.generation > old.generation,"A synchronous new generation replaces only its own memory after the first durable marker")
	c.flow._clear_memory(old)
	c.flow._release(old)
	c.flow._frame_active_story(int(old.generation),int(old.passage_serial))
	_check(_memory_matches(c,Registry.CONSERVATORY,"arrival") and c.child._story_hold == c.flow._active.generation,"Old save/clear/frame completion cannot retire a newer illustration or input hold")
	c.flow._panel._skip()
	await _dispose(c)

func _failed_memory_open(panel_failure: bool) -> void:
	var c := await _setup("p0",false)
	c.child.story_flow = c.flow
	if panel_failure:
		c.flow._panel.free()
		c.flow._panel = RefusingPanel.new()
		c.flow.add_child(c.flow._panel)
	else:
		c.flow._memory.free()
		c.flow._memory = RefusingMemory.new()
		c.flow.add_child(c.flow._memory)
	var saved: Dictionary = c.h.store.saved.duplicate(true)
	_check(not c.flow.present_arrival(c.child,0),"Refused panel or artwork creation cannot leave a half-open passage")
	_check(not c.flow.busy() and not c.flow._panel.is_open() and c.flow._memory._root == null and c.child._story_hold == -1,"Failed opening releases exactly its own panel/artwork/native hold")
	_check(Canonical.same(saved,c.h.store.saved) and not c.owner.story_seen(0,"arrival"),"Failed presentation writes no cosmetic or gameplay evidence")
	await _dispose(c)

func _retired_child() -> void:
	var c := await _setup("p0",false)
	c.child.story_flow = c.flow
	_check(c.flow.present_arrival(c.child,0),"Child-retirement case starts an attached illustration")
	var retired: Dictionary = c.flow._active.duplicate()
	var old: WeakRef = weakref(c.flow._memory._root)
	c.child.free()
	_check(not c.flow.busy() and c.flow._memory._root == null and not c.flow._panel.is_open(),"Actual child exit retires its active illustration and panel")
	c.flow._frame_active_story(int(retired.generation),int(retired.passage_serial))
	c.flow._clear_memory(retired)
	await process_frame
	_check(old.get_ref() == null and not c.owner.story_seen(0,"arrival"),"Retired child callbacks cannot recreate art or acknowledge an unread passage")
	await _dispose(c)

extends "res://tests/test_main_cold_story.gd"
## Actual Main controls retain the native-current History boundary.

func _run() -> void:
	for guest: bool in [false,true]: await _history_after_recovery(guest)
	print("Main memory History: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _history_after_recovery(guest: bool) -> void:
	var c := await _gap(false,true,false,guest)
	var flow: Node = c.app.campaign_flow
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var calls: int = c.h.calls.size()
	var mode: String = c.source.mode
	_check(not flow.history_entries().is_empty() and flow.history_entries(c.source_room).is_empty(),"Historical publication entries do not become usable in an old native child")
	_check(_button(c.source.overlay,"History") == null and _button(c.source.overlay,"Resume") != null,"Historical completed recovery offers its usable Resume without a dead-end History button")
	await c.app._story_child_action("history",c.source)
	_check(c.source.mode == mode and not flow.busy() and Canonical.same(before,c.h.store.saved) and c.h.calls.size() == calls,"A stale direct History callback cannot replace recovery UI, change state or issue traffic")
	await _click_control(c,"Resume")
	await _finish_action(c)
	_check(c.app.relay_child.story_chapter_index == 2 and c.online.last_room() == FAR_ROOM,"History becomes eligible only after actual verified current adoption")
	# The separately reviewed cold queue may offer the previous completion even
	# though this fixture already saw the current arrival. Settle it explicitly.
	if flow.busy(): flow._panel._skip()
	await process_frame
	await process_frame
	var child: Node = c.app.relay_child
	_check(not flow.history_entries(FAR_ROOM).is_empty() and _button(child.overlay,"History") != null,"Current native room exposes reachable History for both physical viewing roles")
	before = c.h.store.saved.duplicate(true)
	calls = c.h.calls.size()
	await _click_control(c,"History")
	_check(child.mode == "story_history" and _button(child.overlay,"1 · Arrival") != null,"The actual History button opens the bounded chapter list")
	await _click_control(c,"1 · Arrival")
	_check(flow.busy() and flow._memory._world.chapter_key == Registry.HIGH_AND_LOW and flow._panel.heading.text == Registry.descriptor(Registry.HIGH_AND_LOW).title+" · Arrival","A real History row presents the older setting over the unchanged current room")
	_check(child.journey.snapshot().room_id == FAR_ROOM and Canonical.same(before,c.h.store.saved) and c.h.calls.size() == calls,"Opening remembered History leaves native selection, saved proofs and transport untouched")
	flow._panel._skip()
	await _dispose_ui(c)

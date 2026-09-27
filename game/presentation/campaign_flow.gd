extends Node
## Local dialogue ownership only. Shared progression stays in CampaignOnlineSession.
## Shared Continue/recovery is external. Warm handoff consumes accepted selection.
const Story = preload("res://services/campaign_story.gd")
const StoryPanel = preload("res://presentation/story_panel.gd")
const Registry = preload("res://services/chapter_registry.gd")
const MemoryBackdrop = preload("res://presentation/story_memory_backdrop.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var last_code := ""
var _owner: RefCounted
var _identity: Callable
var _story: RefCounted
var _panel: CanvasLayer
var _memory: CanvasLayer
var _passage_serial := 0
var _generation := 0
var _active: Dictionary = {}
var _suppressed: Dictionary = {}
var _backgrounded := false
var _configured_campaign := ""
var _handoff: Dictionary = {}
# At most the preceding accepted completion and the current arrival. Each
# context pins the same publication/native host; it never verifies an old room.
var _cold: Array[Dictionary] = []

func configure(owner: RefCounted, identity: Callable, content: Dictionary) -> bool:
	invalidate()
	_owner = owner
	_identity = identity
	_story = Story.new()
	_configured_campaign = ""
	if owner == null or not _story.bind(content, owner.definition()):
		last_code = "story_unavailable"
		return false
	var bound: Dictionary = owner.bound_campaign()
	if bound.is_empty():
		last_code = "story_unavailable"
		return false
	_configured_campaign = Canonical.digest(bound)
	last_code = ""
	return true

func _ready() -> void:
	_memory = MemoryBackdrop.new()
	add_child(_memory)
	_panel = StoryPanel.new()
	add_child(_panel)
	_panel.dismissal_requested.connect(_dismissal_requested)
	_panel.dismissed.connect(_dismissed)
	_panel.card.item_rect_changed.connect(_queue_story_frame)
	_panel.card.minimum_size_changed.connect(_queue_story_frame)
	get_viewport().size_changed.connect(_queue_story_frame)

func busy() -> bool:
	return not _active.is_empty() or not _handoff.is_empty() or not _cold.is_empty()

func present_arrival(child: Node, index: int) -> bool:
	if busy() or _backgrounded or not is_node_ready() or _story == null:
		return false
	var generation := _generation
	var context := _capture(child, index, "arrival", "arrival")
	if context.is_empty(): return false
	var plan: Array[Dictionary] = []
	if index > 0:
		var previous := _capture(child,index-1,"completion","cold")
		if not previous.is_empty() and not _suppressed.has(_marker(previous)) and not _owner.story_seen(index-1,"completion"):
			plan.append(previous)
	if not _suppressed.has(_marker(context)) and not _owner.story_seen(index,"arrival"):
		plan.append(context)
	# Seen observers may restore storage. Do not open a plan if that changed its
	# owner, publication, selection or already-verified current native snapshot.
	if plan.is_empty() or not _same_capture(context,_capture(child,index,"arrival","arrival")): return false
	if generation != _generation or busy() or _backgrounded: return false
	_cold = plan
	if not _open_passage(_cold[0]):
		_cold = []
		return false
	return true

func present_handoff(child: Node, index: int, replace_child: Callable) -> bool:
	if busy() or _backgrounded or not is_node_ready() or _story == null or not replace_child.is_valid(): return false
	var context := _capture(child,index,"completion","handoff")
	if context.is_empty(): return false
	_handoff = {"context":context,"replace":replace_child,"retired":false}
	if _suppressed.has(_marker(context)) or _owner.story_seen(index,"completion"):
		if not _hold_context(context):
			_handoff = {}
			return false
		_adopt_handoff(context,false)
		return true
	if not _open_passage(context):
		_handoff = {}
		return false
	return true

func present_finale(child: Node, index: int) -> bool:
	if busy() or _backgrounded or not is_node_ready() or _story == null: return false
	var context := _capture(child,index,"completion","finale")
	if context.is_empty() or _suppressed.has(_marker(context)) or _owner.story_seen(index,"completion"): return false
	return _open_passage(context)

func history_entries(room_id: String = "") -> Array:
	var result: Array = []
	if _owner == null or _story == null or _owner.read_only or _owner.busy(): return result
	if Canonical.digest(_owner.bound_campaign()) != _configured_campaign: return result
	var publication: Dictionary = _owner.view()
	if publication.is_empty() or publication.state not in ["waiting","active","complete"] or publication.activation != null: return result
	# Publication history is readable only from its verified selected chapter.
	# Main passes its observed native room; the original no-argument listing API
	# remains available to non-UI callers. present_history still checks authority.
	if not room_id.is_empty() and (publication.chapters[int(publication.current_index)].room_id != room_id or _owner.selected_room() != room_id): return result
	for index in range(int(publication.current_index)+1):
		result.append({"index":index,"phase":"arrival"})
		if publication.chapters[index].completion != null: result.append({"index":index,"phase":"completion"})
	return result

func present_history(child: Node, index: int, phase: String) -> bool:
	if busy() or _backgrounded or not is_node_ready() or _story == null: return false
	var context := _capture(child,index,phase,"history")
	return not context.is_empty() and _open_passage(context)

func _hold_context(context: Dictionary) -> bool:
	var child: Node = context.child.get_ref()
	_generation += 1
	context["generation"] = _generation
	_active = context
	if not child.hold_story(_generation,true):
		_active = {}
		return false
	return true

func _open_passage(context: Dictionary) -> bool:
	var lines: Array = _story.lines(int(context.index),str(context.phase))
	if lines.is_empty(): return false
	if not _hold_context(context): return false
	return _present_held_passage(context,lines)

func _present_held_passage(context: Dictionary, lines: Array) -> bool:
	if not _current(context):
		_context_lost(context)
		return false
	var child: Node = context.child.get_ref()
	var definition: Dictionary = _owner.definition()
	if not _current(context) or not definition.get("chapters") is Array or int(context.index) >= definition.chapters.size():
		_context_lost(context)
		return false
	var chapter := Registry.resolve(definition.chapters[int(context.index)])
	var title := str(Registry.descriptor(chapter).get("title",""))
	var illustrated := _illustrated_passage(context)
	if title.is_empty() or not _current(context):
		_context_lost(context)
		return false
	# A cold pair deliberately shares its native hold, but every displayed beat
	# owns a different artwork token and deferred-layout identity.
	_passage_serial += 1
	context["passage_serial"] = _passage_serial
	context["passage_identity"] = Canonical.digest({"bound":context.bound,"owner":context.owner,
		"publication":context.publication,"room":context.room_id,"index":context.index,
		"phase":context.phase,"purpose":context.purpose,"serial":_passage_serial})
	context["memory_token"] = -1
	_panel.text_scale = float(child.settings.get("text_scale", 1.0))
	if not _panel.present(title+" · "+str(context.phase).capitalize(), lines, true):
		return _failed_passage(context)
	if not _current(context):
		_context_lost(context)
		return false
	if not _passage_matches(context): return false
	if illustrated:
		context["memory_token"] = _memory.present(int(context.generation),context.passage_identity,
			chapter,str(context.phase),title,_panel.card.get_global_rect(),_story_safe_rect())
		if int(context.memory_token) < 0:
			last_code = "story_memory_unavailable"
			return _failed_passage(context)
	_frame_active_story(int(context.generation),int(context.passage_serial))
	_queue_story_frame()
	return true

func _illustrated_passage(context: Dictionary) -> bool:
	if context.phase == "arrival" or context.purpose == "cold": return true
	if context.purpose != "history": return false
	var publication: Dictionary = _owner.view()
	if publication.is_empty() or not publication.get("chapters") is Array or int(context.index) >= publication.chapters.size(): return true
	var child: Node = context.child.get_ref()
	return int(context.index) != int(publication.current_index) or not _completed_source(child,
		child.journey.snapshot(),publication.chapters[int(context.index)])

func _failed_passage(context: Dictionary) -> bool:
	_clear_memory(context)
	if not _active.is_empty() and _active.get("passage_serial") == context.get("passage_serial"):
		_active = {}
		_panel.cancel()
	_release(context)
	return false

func _clear_memory(context: Dictionary) -> void:
	if context.is_empty() or not is_instance_valid(_memory): return
	var token := int(context.get("memory_token",-1))
	if token >= 0 and _memory.matches(token,int(context.generation),str(context.get("passage_identity",""))):
		_memory.clear(token)

func _passage_matches(context: Dictionary) -> bool:
	return not _active.is_empty() and context.get("generation") == _generation and context.get("passage_serial") == _active.get("passage_serial")

func _queue_story_frame() -> void:
	if not _active.is_empty() and _active.has("passage_serial"):
		_frame_active_story.call_deferred(int(_active.generation),int(_active.passage_serial))

func _frame_active_story(generation: int, passage_serial: int) -> void:
	if _backgrounded: return
	if generation != _generation or _active.is_empty() or _active.get("passage_serial") != passage_serial or not _panel.is_open(): return
	var context := _active
	if not _current(context):
		_context_lost(context)
		return
	if not _passage_matches(context): return
	var token := int(context.get("memory_token",-1))
	if token >= 0:
		if _memory.matches(token,generation,str(context.passage_identity)):
			_memory.frame(token,_panel.card.get_global_rect(),_story_safe_rect())
		return
	var child: Node = context.child.get_ref()
	if not child.frame_story_camera(generation,_panel.card.get_global_rect(),_story_safe_rect()): last_code = "story_framing_unavailable"

func set_backgrounded(value: bool) -> void:
	_backgrounded = value
	if is_instance_valid(_panel): _panel.set_suspended(value)
	if not value and not _active.is_empty():
		var context := _active
		if not _current(context): _context_lost(context)
		elif _passage_matches(context):
			var token := int(context.get("memory_token",-1))
			if token >= 0 and _memory.matches(token,int(context.generation),str(context.passage_identity)):
				_memory.refresh(token)
			_queue_story_frame()

func skip_from_system_back(child: Node) -> void:
	if not _backgrounded and not _active.is_empty() and _active.child.get_ref() == child:
		_panel.skip_dialogue()

func invalidate() -> void:
	# cancel() emits synchronously. Retire the context before it can do so.
	_generation += 1
	var retired := _active
	_active = {}
	_handoff = {}
	_cold = []
	_suppressed = {}
	_clear_memory(retired)
	if is_instance_valid(_panel): _panel.cancel()
	_release(retired)

func retire_child(child: Node) -> void:
	if not _active.is_empty() and _active.child.get_ref() == child: invalidate()

func _context_lost(context: Dictionary = {}) -> void:
	# A synchronous save callback may have installed a newer presentation.
	if not context.is_empty() and context.get("generation") != _generation: return
	if context.has("passage_serial") and not _active.is_empty() and context.passage_serial != _active.get("passage_serial"): return
	var child: Variant = _active.child.get_ref() if not _active.is_empty() else null
	invalidate()
	if is_instance_valid(child) and child.is_inside_tree(): child.story_context_changed()

func _capture(child: Node, index: int, phase: String, purpose: String) -> Dictionary:
	if _owner == null or _owner.read_only or _owner.busy() or not _owner.pending().is_empty(): return {}
	if not is_instance_valid(child) or not child.is_inside_tree() or not child.story_boundary_ready(true): return {}
	var identity: Variant = _identity.call() if _identity.is_valid() else null
	if not identity is Dictionary or identity.get("ready") != true: return {}
	var publication: Dictionary = _owner.view()
	var bound: Dictionary = _owner.bound_campaign()
	if bound.is_empty() or publication.is_empty() or publication.get("activation") != null or publication.state not in ["waiting", "active", "complete"]: return {}
	if Canonical.digest(bound) != _configured_campaign: return {}
	if index < 0 or index > int(publication.current_index) or phase not in ["arrival","completion"]: return {}
	var entry: Dictionary = publication.chapters[index]
	var room: Dictionary = child.journey.snapshot()
	if room.get("host_id") != publication.host_id or room.get("guest_id") != publication.guest_id or room.get("player_slot") != publication.player_slot: return {}
	var target: Dictionary = publication.chapters[int(publication.current_index)]
	if purpose in ["arrival","cold"] and (child.online_session == null or child.online_session.coordinator != child.journey): return {}
	if purpose == "handoff":
		if index+1 != int(publication.current_index) or publication.state != "active" or target.completion != null or _owner.selected_room() != target.room_id or not _owner.adoption_ready(): return {}
		if not _completed_source(child,room,entry): return {}
	elif purpose == "finale":
		if publication.state != "complete" or index != int(publication.current_index) or index+1 != publication.chapters.size() or _owner.selected_room() != entry.room_id or not _completed_source(child,room,entry): return {}
	elif purpose == "arrival":
		# A saved admission needs its recovery controls; explicit History remains
		# available against the same bound story and never changes selection.
		if not _owner.pending_lobby().is_empty(): return {}
		if index != int(publication.current_index) or publication.state == "complete" or room.get("room_id") != entry.room_id or _owner.selected_room() != entry.room_id: return {}
	elif purpose == "cold":
		# The old completion is accepted control evidence, presented on the
		# verified current child. It supplies no gameplay or historical proof.
		if not _owner.pending_lobby().is_empty(): return {}
		if phase != "completion" or index+1 != int(publication.current_index) or not entry.completion is Dictionary or publication.state == "complete": return {}
		if room.get("room_id") != target.room_id or _owner.selected_room() != target.room_id: return {}
	elif purpose == "history":
		if room.get("room_id") != target.room_id or _owner.selected_room() != target.room_id: return {}
		if phase == "completion" and entry.completion == null: return {}
	else: return {}
	return {"owner":identity.player_id, "epoch":identity.epoch,
		"bound":Canonical.digest(bound), "publication":Canonical.digest(publication),
		"room_id":room.room_id, "snapshot":Canonical.digest(room),"target_room":target.room_id,
		"index":index,"phase":phase,"purpose":purpose,"child":weakref(child)}

func _completed_source(child: Node, room: Dictionary, entry: Dictionary) -> bool:
	if child.mode != "complete" or not child.journey.chapter_complete() or room.get("active_role") != "complete" or room.get("room_id") != entry.room_id or not entry.completion is Dictionary: return false
	var accepted: Dictionary = entry.completion
	return room.get("revision") == accepted.source_revision and room.get("branch") == accepted.source_branch and room.get("checkpoint",{}).get("checkpoint_hash") == accepted.checkpoint_hash

func _current(context: Dictionary) -> bool:
	if context.is_empty() or context.generation != _generation: return false
	var child: Variant = context.child.get_ref()
	if not is_instance_valid(child) or not child.is_inside_tree(): return false
	# The same stable boundary remains eligible while its own input hold is set.
	var now := _capture(child, int(context.index),str(context.phase),str(context.purpose))
	return context.generation == _generation and _same_capture(context,now)

func _same_capture(context: Dictionary, now: Dictionary) -> bool:
	if context.is_empty() or now.is_empty(): return false
	for field: String in ["owner", "epoch", "bound", "publication", "room_id", "snapshot", "target_room", "index", "phase", "purpose"]:
		if now[field] != context[field]: return false
	return true

func _save_seen(context: Dictionary, index: int, phase: String) -> bool:
	if not _current(context): return false
	var seen: bool = _owner.story_seen(index,phase)
	if not _current(context): return false
	return seen or _owner.mark_story_seen(index,phase)

func _dismissal_requested(request_id: int, skipped: bool) -> void:
	if _backgrounded: return
	var context := _active.duplicate()
	if not _current(context):
		_context_lost(context)
		return
	var remaining: Array = _cold.duplicate() if skipped and not _cold.is_empty() else [context]
	var saved := true
	for phase: Dictionary in remaining:
		saved = _save_seen(context,int(phase.index),str(phase.phase))
		if not _current(context):
			_context_lost(context)
			return
		if not saved: break
	if saved and skipped and context.purpose == "handoff":
		saved = _save_seen(context,int(context.index)+1,"arrival")
		if not _current(context):
			_context_lost(context)
			return
	# resolve may synchronously close and transfer ownership; do nothing after it.
	_panel.resolve_dismissal(request_id, saved, "Save failed.")

func _dismissed(skipped: bool, seen_saved: bool) -> void:
	var context := _active
	if context.is_empty(): return
	if not _current(context):
		_context_lost(context)
		return
	_clear_memory(context)
	_suppressed[_marker(context)] = true
	if context.purpose == "handoff":
		_adopt_handoff(context,skipped)
		return
	if not _cold.is_empty():
		if skipped or not seen_saved:
			# Close after a failed save suppresses only this captured remainder;
			# unsaved markers stay eligible after a fresh presentation/restart.
			for phase: Dictionary in _cold: _suppressed[_marker(phase)] = true
			_cold = []
		else:
			_cold.pop_front()
			if not _cold.is_empty():
				var next: Dictionary = _cold[0].duplicate()
				next["generation"] = context.generation
				if not _current(next):
					_context_lost(context)
					return
				# StoryPanel has retired its old request before emitting dismissed.
				# Keep the same native input/camera hold while replacing the beat.
				_active = next
				if not _present_held_passage(next,_story.lines(int(next.index),str(next.phase))):
					_cold = []
				return
	_active = {}
	_generation += 1
	_release(context)

func handoff_matches(child: Node, generation: int, room_id: String, index: int) -> bool:
	if _handoff.is_empty() or _handoff.retired or _backgrounded: return false
	var context: Dictionary = _handoff.context
	return context.child.get_ref() == child and context.generation == generation and context.target_room == room_id and int(context.index)+1 == index and _current(context)

func retire_for_replacement(child: Node, generation: int) -> bool:
	if _handoff.is_empty() or _handoff.retired: return false
	var context: Dictionary = _handoff.context
	if context.child.get_ref() != child or context.generation != generation: return false
	# Main calls this after synchronous adoption, before remove_child/_exit_tree.
	_clear_memory(context)
	_active = {}
	_handoff.retired = true
	_generation += 1
	return true

func _adopt_handoff(context: Dictionary, skipped: bool) -> void:
	if _handoff.is_empty() or not _current(context):
		_context_lost(context)
		return
	if skipped:
		var arrival := context.duplicate()
		arrival.index = int(context.index)+1
		arrival.phase = "arrival"
		_suppressed[_marker(arrival)] = true
	var source: Node = context.child.get_ref()
	var replace: Callable = _handoff.replace
	_clear_memory(context)
	_active = {}
	var next: Variant = replace.call(source,int(context.generation),str(context.target_room),int(context.index)+1,self)
	_handoff = {}
	if not is_instance_valid(next) or not next is Node or not next.is_inside_tree():
		_generation += 1
		_release(context)
		if is_instance_valid(source) and source.is_inside_tree(): source.story_context_changed()
		last_code = "adoption_unavailable"
		return
	last_code = ""
	if not skipped: present_arrival(next,int(context.index)+1)

func _release(context: Dictionary) -> void:
	if context.is_empty(): return
	_clear_memory(context)
	# An old beat cannot release the one native hold retained by its successor.
	if not _active.is_empty() and _active.get("generation") == context.get("generation") and _active.get("passage_serial") != context.get("passage_serial"): return
	var child: Variant = context.child.get_ref()
	if is_instance_valid(child): child.release_story(int(context.generation))

func _marker(context: Dictionary) -> String:
	return "%s:%s:%s:%s:%s" % [context.owner, context.epoch, context.bound, context.index, context.phase]

func _exit_tree() -> void:
	invalidate()


func _story_safe_rect() -> Rect2:
	var bounds := get_viewport().get_visible_rect()
	if _panel.safe_rect_override.has_area(): return _panel.safe_rect_override.intersection(bounds)
	if OS.has_feature("android"): return SafeArea.viewport_rect(Rect2(DisplayServer.get_display_safe_area()),get_viewport().get_screen_transform(),bounds)
	return bounds

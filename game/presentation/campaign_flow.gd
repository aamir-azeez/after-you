extends Node
## Local dialogue ownership only. Shared progression stays in CampaignOnlineSession.
## This first integration slice presents arrivals; it never advances or adopts a room.
const Story = preload("res://services/campaign_story.gd")
const StoryPanel = preload("res://presentation/story_panel.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var last_code := ""
var _owner: RefCounted
var _identity: Callable
var _story: RefCounted
var _panel: CanvasLayer
var _generation := 0
var _active: Dictionary = {}
var _suppressed: Dictionary = {}
var _backgrounded := false
var _configured_campaign := ""

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
	_panel = StoryPanel.new()
	add_child(_panel)
	_panel.dismissal_requested.connect(_dismissal_requested)
	_panel.dismissed.connect(_dismissed)

func busy() -> bool:
	return not _active.is_empty()

func present_arrival(child: Node, index: int) -> bool:
	if busy() or _backgrounded or not is_node_ready() or _story == null:
		return false
	var context := _capture(child, index)
	if context.is_empty(): return false
	var marker := _marker(context)
	if _suppressed.has(marker) or _owner.story_seen(index, "arrival"): return false
	var lines: Array = _story.lines(index, "arrival")
	if lines.is_empty(): return false
	_generation += 1
	context.generation = _generation
	_active = context
	if not child.hold_story(_generation):
		_active = {}
		return false
	_panel.text_scale = float(child.settings.get("text_scale", 1.0))
	if not _panel.present(_story.title(), lines, true):
		_release(context)
		_active = {}
		return false
	return true

func set_backgrounded(value: bool) -> void:
	_backgrounded = value
	if is_instance_valid(_panel): _panel.set_suspended(value)
	if not value and not _active.is_empty() and not _current(_active): _context_lost()

func skip_from_system_back(child: Node) -> void:
	if not _backgrounded and not _active.is_empty() and _active.child.get_ref() == child:
		_panel.skip_dialogue()

func invalidate() -> void:
	# cancel() emits synchronously. Retire the context before it can do so.
	_generation += 1
	var retired := _active
	_active = {}
	_suppressed = {}
	if is_instance_valid(_panel): _panel.cancel()
	_release(retired)

func retire_child(child: Node) -> void:
	if not _active.is_empty() and _active.child.get_ref() == child: invalidate()

func _context_lost() -> void:
	var child: Variant = _active.child.get_ref() if not _active.is_empty() else null
	invalidate()
	if is_instance_valid(child) and child.is_inside_tree(): child.story_context_changed()

func _capture(child: Node, index: int) -> Dictionary:
	if _owner == null or _owner.read_only or _owner.busy() or not _owner.pending().is_empty(): return {}
	if not is_instance_valid(child) or not child.is_inside_tree() or not child.story_boundary_ready(): return {}
	var identity: Variant = _identity.call() if _identity.is_valid() else null
	if not identity is Dictionary or identity.get("ready") != true: return {}
	var publication: Dictionary = _owner.view()
	var bound: Dictionary = _owner.bound_campaign()
	if bound.is_empty() or publication.is_empty() or publication.get("activation") != null or publication.state not in ["waiting", "active"]: return {}
	if Canonical.digest(bound) != _configured_campaign: return {}
	if index != int(publication.current_index): return {}
	var entry: Dictionary = publication.chapters[index]
	var room: Dictionary = child.journey.snapshot()
	if room.get("room_id") != entry.room_id or _owner.selected_room() != entry.room_id: return {}
	if room.get("host_id") != publication.host_id or room.get("guest_id") != publication.guest_id or room.get("player_slot") != publication.player_slot: return {}
	return {"owner":identity.player_id, "epoch":identity.epoch,
		"bound":Canonical.digest(bound), "publication":Canonical.digest(publication),
		"room_id":entry.room_id, "index":index, "child":weakref(child)}

func _current(context: Dictionary) -> bool:
	if context.is_empty() or context.generation != _generation: return false
	var child: Variant = context.child.get_ref()
	if not is_instance_valid(child) or not child.is_inside_tree(): return false
	# The same stable boundary remains eligible while its own input hold is set.
	var now := _capture(child, int(context.index))
	if now.is_empty(): return false
	for field: String in ["owner", "epoch", "bound", "publication", "room_id", "index"]:
		if now[field] != context[field]: return false
	return true

func _dismissal_requested(request_id: int, _skipped: bool) -> void:
	if _backgrounded: return
	var context := _active.duplicate()
	if not _current(context):
		_context_lost()
		return
	var saved: bool = _owner.mark_story_seen(int(context.index), "arrival")
	if not _current(context):
		_context_lost()
		return
	# resolve may synchronously close and transfer ownership; do nothing after it.
	_panel.resolve_dismissal(request_id, saved, "Save failed.")

func _dismissed(_skipped: bool, _seen_saved: bool) -> void:
	var context := _active
	if context.is_empty(): return
	if not _current(context):
		_context_lost()
		return
	_active = {}
	_generation += 1
	_suppressed[_marker(context)] = true
	_release(context)

func _release(context: Dictionary) -> void:
	if context.is_empty(): return
	var child: Variant = context.child.get_ref()
	if is_instance_valid(child): child.release_story(int(context.generation))

func _marker(context: Dictionary) -> String:
	return "%s:%s:%s:%s:arrival" % [context.owner, context.epoch, context.bound, context.index]

func _exit_tree() -> void:
	invalidate()

extends "res://presentation/cooperative_world.gd"
## View adapter for the sealed simulation7 snapshot. The physical renderer and
## Lighthouse optical geometry remain shared; this file adds no game state.
const LabelBubble = preload("res://presentation/kit/label_bubble.gd")
## The tail's tip: just over a lever's knob.
const LEVER_TOP := Vector3(0,0.80,0)
## A spirit's height on screen with its badge, and half its width, in metres.
const SPIRIT_TOP := 1.75
const SPIRIT_HALF_WIDTH := 0.42
## How much of a spirit's screen box a bubble may cover before it rises.
const SPIRIT_COVER := 0.10
## A raised bubble clears a badge or another bubble by this much (metres).
const BUBBLE_CLEARANCE := 0.06
var _journey_switches: Dictionary = {}
var _bubbles: Array = []
## Screen boxes of bubbles already placed this frame: the first _placed_count
## entries. The array only grows, so a frame allocates nothing.
var _placed: Array[Rect2] = []
var _placed_count := 0
var _journey_handles: Dictionary = {}
var _waiting_ring: MeshInstance3D
var _remembered: Node3D

func show_stage(stage: Dictionary) -> void:
	if str(stage.get("id", "")) == displayed_stage_id: return
	_journey_switches.clear()
	_bubbles.clear()
	_journey_handles.clear()
	_waiting_ring = null
	super.show_stage(stage)
	# Lowest on screen first: see _lift_bubbles.
	var up := LabelBubble.screen_up()
	_bubbles.sort_custom(func(a: LabelBubble, b: LabelBubble) -> bool: return a.anchor.dot(up) < b.anchor.dot(up))
	var endpoint: Dictionary = stage.get("source_policy", {}).get("endpoint", {})
	if not endpoint.is_empty():
		var at := _at(endpoint)
		_waiting_ring = ring(float(endpoint.radius_cm)/100.0,CREAM,at+Vector3(0,0.018,0),terrain)
		_waiting_ring.name = "SourceWaitingRegion"
		_ownership_mark(str(endpoint.owner_slot),at+Vector3(0,0.025,0),terrain)

func _configure_shared_view(view: Dictionary) -> void:
	# The renderer receives a detached stage view. Native optical dictionaries
	# and their exact canonical keys never gain presentation-only metadata.
	view["optics"] = view.get("optical_field", {"emitters":[],"receivers":[]}).duplicate(true)
	for slot: String in view.starts:
		if view.starts[slot] is Dictionary: view.starts[slot] = view.starts[slot].position_cm.duplicate()

func _beam_height() -> float: return 2.4
func _uses_lower_cutaway() -> bool: return true
func _uses_scrolling_camera() -> bool: return true

func _control_base_height(entity: Dictionary) -> float:
	if entity.has("surface_id"): return _surface_height(str(entity.surface_id))
	var position: Array = entity.position_cm
	var height := 0.0
	for island: Dictionary in chapter_definition.islands:
		var rect: Array = island.rect_cm
		if position[0] >= rect[0] and position[0] <= rect[2] and position[1] >= rect[1] and position[1] <= rect[3]:
			height = maxf(height,float(island.get("height_cm",0))/100.0)
	return height

func _build_mirror(control: Dictionary) -> void:
	super._build_mirror(control)
	# The optical face stays on the common ray plane. A hand wheel at the
	# authored interaction position shows that a ground player can turn it.
	var at := _at(control)
	var hand := Node3D.new()
	hand.name = "MirrorHandControl_"+str(control.id)
	hand.position = at+Vector3(0,0.54,0.10)
	terrain.add_child(hand)
	var wheel := ring(0.14,GOLD if control.owner_slot == "p0" else TEAL,Vector3.ZERO,hand)
	wheel.rotation.x = PI/2.0
	box(Vector3(0.035,0.26,0.035),CREAM,Vector3.ZERO,hand)
	_journey_handles[control.id] = hand
	_ownership_mark(str(control.owner_slot),at+Vector3(0,0.025,0.35),terrain)

## One speech bubble per selector, over the lever and pointing down at it,
## with one pill per value. `labels` keeps one Label3D per value (meta
## "backing" is its pill) for worlds that restyle a single value.
func _build_selector(control: Dictionary) -> void:
	_build_lever(control)
	var bubble := _label_bubble(control.values,_at(control)+LEVER_TOP,terrain,_selector_bubble_shift(control))
	_journey_switches[control.id] = {"values":control.values.duplicate(),"labels":bubble.labels,"bubble":bubble}
	_physical_levers[control.id].name = "RouteSwitch_"+str(control.id)

## A named place (a pad, a door): the same bubble with one word, its tail
## pointing down at `at`.
func _world_label(value: String, at: Vector3, parent: Node3D) -> Label3D:
	return _label_bubble([value],at,parent).labels[0]

## Sideways screen offset (metres) of a selector's bubble body, for a world
## whose prop stands where the bubble would float. Its tail stays on the lever.
func _selector_bubble_shift(_control: Dictionary) -> float:
	return 0.0

func _label_bubble(values: Array, at: Vector3, parent: Node3D, shift: float = 0.0) -> LabelBubble:
	var bubble := LabelBubble.new()
	bubble.build(parent,at,values,shift)
	_bubbles.append(bubble)
	return bubble

func _frame_camera() -> void:
	super._frame_camera()
	_lift_bubbles()

## A bubble rises straight up, tail still over its control, while a spirit or
## its badge shares its place on screen, so a label never hides anyone and
## no badge sits on a label; it settles back once they move away. Decided
## from the current state alone, so a frame never depends on the last.
## Bubbles a world draws over scenery (Turn of the Tide's chips) are left to
## that world's own clearing.
## Worked out on the fixed journey view plane in metres (LabelBubble.plane_rect)
## from the bubbles and the snapshot's spirit positions, never the live
## viewport or animation, and rounded up to whole centimetres, so every
## platform, window size and frame rate places bubbles alike.
func _lift_bubbles() -> void:
	if _bubbles.is_empty(): return
	var rise := LabelBubble.screen_up().y
	if _placed.size() < _bubbles.size(): _placed.resize(_bubbles.size())
	_placed_count = 0
	for bubble: LabelBubble in _bubbles:
		if not is_instance_valid(bubble) or bubble.labels[0].no_depth_test: continue
		var rect := bubble.plane_rect(true)
		var need := 0.0
		for slot: String in actors:
			var actor: Node3D = actors[slot]
			if not actor.visible or not actor_targets.has(slot) or not actor.get_parent() is Node3D: continue
			# Where the snapshot puts the spirit, not where its walk animation
			# has got to: the same on every platform and frame rate.
			var at: Vector3 = (actor.get_parent() as Node3D).global_transform*(actor_targets[slot] as Vector3)
			var feet := LabelBubble.plane_point(at)
			var top := LabelBubble.plane_point(at+Vector3(0,SPIRIT_TOP,0))
			var spirit := Rect2(feet.x-SPIRIT_HALF_WIDTH,top.y,SPIRIT_HALF_WIDTH*2.0,feet.y-top.y)
			if rect.intersection(spirit).get_area() > spirit.get_area()*SPIRIT_COVER:
				need = maxf(need,(rect.end.y-spirit.position.y)/rise+BUBBLE_CLEARANCE)
		# Bubbles are placed from the lowest on screen up, so a bubble that would
		# overlap one already placed climbs straight up over it: tails never cross.
		for index in range(_placed_count):
			var other := _placed[index]
			var raised := Rect2(rect.position-Vector2(0,need*rise),rect.size)
			if raised.intersects(other): need += (raised.end.y-other.position.y)/rise+BUBBLE_CLEARANCE
		need = ceilf(need*100.0)/100.0
		_placed[_placed_count] = Rect2(rect.position-Vector2(0,need*rise),rect.size)
		_placed_count += 1
		bubble.set_lift(need)

func _build_gate_links(view: Dictionary) -> void:
	# Only draw a cable where a mechanism and its route share a real floor.
	# Distant relationships use matching crests, never a false path over void.
	for gate: Dictionary in view.get("gates",[]):
		var route: Dictionary = {}
		for candidate: Dictionary in view.bridges+view.get("stairs",[]):
			if candidate.id == gate.route_id: route = candidate
		if route.is_empty(): continue
		var references := _predicate_references(gate.get("when",{}))
		var r: Array = route.rect_cm
		var end := point([r[0]-18,(r[1]+r[3])*0.5])+Vector3(0,float(route.get("from_height_cm",0))/100.0+0.025,0)
		for id: String in references:
			# Each reference keeps its own crest beside the route's end, so two
			# crests never lie on one another.
			var crest_end := end + Vector3(0, 0, (float(references.find(id)) - float(references.size() - 1) * 0.5) * 0.22)
			var entity: Dictionary = {}
			for item: Dictionary in view.get("controls",[])+view.get("levers",[])+view.get("pressure_pads",[])+view.optics.receivers:
				if item.id == id: entity = item
			if entity.is_empty(): continue
			var start := point(entity.position_cm)+Vector3(0,_control_base_height(entity)+0.025,0)
			var color := _route_color(id)
			_route_crest(id,start+Vector3(0.33,0.01,0),color,terrain)
			_route_crest(id,crest_end,color,terrain)
			if _shares_floor(start,end):
				var elbow := Vector3(end.x,start.y,start.z)
				if start.distance_to(elbow)>0.01: _bar_between(start,elbow,0.016,color.darkened(0.25),terrain)
				if elbow.distance_to(end)>0.01: _bar_between(elbow,end,0.016,color.darkened(0.25),terrain)

func _predicate_references(predicate: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: String in ["control_id","signal_id","pad_id","lever_id"]:
		if predicate.has(key): result.append(str(predicate[key]))
	for key: String in ["all","any"]:
		for child: Dictionary in predicate.get(key,[]):
			for id: String in _predicate_references(child):
				if id not in result: result.append(id)
	return result

func _route_color(id: String) -> Color:
	return GOLD if id in ["path-selector","high-light","crossing-light","near-window"] else TEAL

func _route_crest(id: String, at: Vector3, color: Color, parent: Node3D) -> void:
	var count := 1 if id in ["path-selector","high-light","crossing-light","near-window"] else 2
	for index in range(count):
		# A few millimetres above the gate cable that meets it.
		box(Vector3(0.07,0.014,0.18),color,at+Vector3((float(index)-float(count-1)*0.5)*0.12,0.006,0),parent)

func _shares_floor(a: Vector3, b: Vector3) -> bool:
	if absf(a.y-b.y)>0.05: return false
	for island: Dictionary in chapter_definition.islands:
		var r: Array = island.rect_cm
		if a.x*100>=r[0] and a.x*100<=r[2] and a.z*100>=r[1] and a.z*100<=r[3] and b.x*100>=r[0] and b.x*100<=r[2] and b.z*100>=r[1] and b.z*100<=r[3]: return true
	return false

func present_history(checkpoint: Dictionary) -> void:
	super.present_history(checkpoint)
	if is_instance_valid(_remembered):
		_remembered.get_parent().remove_child(_remembered)
		_remembered.queue_free()
	_remembered = Node3D.new()
	_remembered.name = "RememberedJourneyRoutes"
	terrain.add_child(_remembered)
	for route: Dictionary in chapter_definition.bridges:
		if route.id not in _latched_bridge_ids: continue
		var r: Array = route.rect_cm
		var at := point([r[0]+12,r[3]-12])+Vector3(0,0.02,0)
		box(Vector3(0.20,0.035,0.14),CREAM,at,_remembered)
		box(Vector3(0.04,0.035,0.20),GOLD,at+Vector3(0,0.02,0),_remembered)

func present(state: Dictionary, immediate: bool = false) -> void:
	var visual := state.duplicate()
	visual["mirrors"] = state.get("controls",{}).duplicate()
	visual["emitter_powered"] = not state.get("optics",{}).get("segments",[]).is_empty()
	# Detach the one nested dictionary this adapter extends. Every other
	# snapshot branch is consumed without mutation by the physical renderer.
	visual["route_progress"] = state.get("route_progress",{}).duplicate()
	visual.route_progress["kept_bridges"] = state.get("route_progress",{}).get("entered_routes",[])
	super.present(visual,immediate)
	for id: String in _journey_handles:
		_journey_handles[id].rotation.z = PI/4.0 if state.get("controls",{}).get(id,"backslash") == "slash" else -PI/4.0
	for id: String in _journey_switches:
		var switch: Dictionary = _journey_switches[id]
		var chosen: int = switch.values.find(state.get("controls",{}).get(id,""))
		_physical_levers[id].rotation.z = -0.60 if chosen == 0 else 0.60
		(switch.bubble as LabelBubble).highlight(chosen)
	if is_instance_valid(_waiting_ring): _glow(_waiting_ring,CREAM,0.6 if state.get("can_commit",false) else 0.0)

func _should_cutaway(raised: Node3D, state: Dictionary) -> bool:
	if not _completion_view: return super._should_cutaway(raised,state)
	return Cutaway.anyone_below(raised,state)

func _camera_center() -> Vector3:
	var target := super._camera_center()
	if not _completion_view: target.z = clampf(actors[_active_player].position.z,-1.1,2.0)
	target.y = 0.45
	return target

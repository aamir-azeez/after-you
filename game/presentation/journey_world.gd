extends "res://presentation/cooperative_world.gd"
## View adapter for the sealed simulation7 snapshot. The physical renderer and
## Lighthouse optical geometry remain shared; this file adds no game state.
const LabelBubble = preload("res://presentation/kit/label_bubble.gd")
## A selector's bubble body stands as if its tail ended here, just over the
## lever's knob; the tail's tip itself lands on the knob's top (_knob_top).
const LEVER_TOP := Vector3(0,0.80,0)
## A lever's knob (cooperative_world._build_lever): its centre in the pivot's
## space, and its radius.
const KNOB := Vector3(0,0.40,0)
const KNOB_RADIUS := 0.09
## A spirit's height on screen with its badge, and half its width, in metres.
const SPIRIT_TOP := 1.75
const SPIRIT_HALF_WIDTH := 0.42
## A spirit's head and torso, without the badge (spirit_visual.gd): the
## height of each sphere's centre over its feet and its radius (metres). On
## screen each is a disc; a tail must never be seen across either.
const SPIRIT_HEAD := Vector2(0.57,0.34)
const SPIRIT_TORSO := Vector2(0.24,0.29)
## Where a control itself lies over a spirit on screen, the last this much of
## its tail (metres) may run over the spirit too, to reach it.
const TIP_OVER_SPIRIT := 0.4
## How much of a spirit's screen box a bubble may cover before it rises.
const SPIRIT_COVER := 0.10
## A raised bubble clears a badge or another bubble by this much (metres).
const BUBBLE_CLEARANCE := 0.06
## A spirit no further than this behind a tail's card (metres along the view)
## hides the tail where they meet on screen (its body is wider than this).
const SPIRIT_HIDES := 0.12
## A leaning tail runs at most this far sideways from its root to its tip
## (metres on screen).
const LEAN_MAX := 1.6
## What a metre of lift costs against a metre of lean when a bubble picks
## where to stand: a lean keeps the tail short.
const LIFT_COST := 2.0
## How much further out than just beside a spirit a bubble may try (metres).
const LEAN_STEPS: Array[float] = [0.0,0.3,0.6]
var _journey_switches: Dictionary = {}
var _bubbles: Array = []
## Screen boxes of bubbles already placed this frame: the first _placed_count
## entries. The array only grows, so a frame allocates nothing.
var _placed: Array[Rect2] = []
var _placed_count := 0
## This frame's spirits on the view plane: their boxes with badges, their
## bodies, and where they stand (world). The first _spirit_count entries; the
## arrays only grow.
var _spirit_boxes: Array[Rect2] = []
var _spirit_heads: Array[Rect2] = []
var _spirit_torsos: Array[Rect2] = []
var _spirit_feet: Array[Vector3] = []
var _spirit_count := 0
## Scenery that could hide a leaning bubble's body from the camera: per bubble,
## the world boxes of the stage's meshes near where it may stand. Gathered the
## first time any bubble leans in a stage.
var _sceneries: Dictionary = {}
var _journey_handles: Dictionary = {}
var _waiting_ring: MeshInstance3D
var _remembered: Node3D

func show_stage(stage: Dictionary) -> void:
	if str(stage.get("id", "")) == displayed_stage_id: return
	_journey_switches.clear()
	_bubbles.clear()
	_sceneries.clear()
	_journey_handles.clear()
	_waiting_ring = null
	await super.show_stage(stage)
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
	var bubble := _label_bubble(control.values,_selector_anchor(control),terrain,_selector_bubble_shift(control))
	_journey_switches[control.id] = {"values":control.values.duplicate(),"labels":bubble.labels,"bubble":bubble}
	_physical_levers[control.id].name = "RouteSwitch_"+str(control.id)
	bubble.set_anchor(_knob_top(str(control.id)))

## Every selector's tail to its knob's top, as the levers now tilt: after a
## world sets its levers (present) and before bubbles are placed.
func _follow_knobs() -> void:
	for id: String in _journey_switches:
		var bubble: LabelBubble = _journey_switches[id].bubble
		if is_instance_valid(bubble) and _physical_levers.has(id): bubble.set_anchor(_knob_top(id))

## The top of a selector lever's knob (terrain space), as the lever now tilts:
## where its bubble's tail lands.
func _knob_top(id: String) -> Vector3:
	return (_physical_levers[id] as Node3D).transform*KNOB+Vector3(0,KNOB_RADIUS,0)

## A named place (a pad, a door): the same bubble with one word, its tail
## pointing down at `at`.
func _world_label(value: String, at: Vector3, parent: Node3D) -> Label3D:
	return _label_bubble([value],at,parent).labels[0]

## Where a selector's bubble is built to point (terrain space): just over its
## lever's knob, which places its body; the tip then follows the knob's top.
func _selector_anchor(control: Dictionary) -> Vector3:
	return _at(control)+LEVER_TOP

## Sideways screen offset (metres) of a selector's bubble body, for a world
## whose prop stands where the bubble would float. Its tail stays on its anchor.
func _selector_bubble_shift(_control: Dictionary) -> float:
	return 0.0

func _label_bubble(values: Array, at: Vector3, parent: Node3D, shift: float = 0.0) -> LabelBubble:
	var bubble := LabelBubble.new()
	bubble.build(parent,at,values,shift)
	if not reduced_motion: bubble.set_bob(true)
	_bubbles.append(bubble)
	return bubble

## Bubbles bob on the world's clock: they hold still whenever the world does
## (pause, review, a card), and settle under Reduce motion.
func _process(delta: float) -> void:
	super._process(delta)
	_advance_bubbles(delta)

## A card holds the bob, but Reduce motion turned on still settles it.
func _idle_card_frame() -> void:
	super._idle_card_frame()
	_advance_bubbles(0.0)

func _advance_bubbles(delta: float) -> void:
	for bubble: LabelBubble in _bubbles:
		if not is_instance_valid(bubble): continue
		if bubble.is_bobbing() == reduced_motion: bubble.set_bob(not reduced_motion)
		bubble.advance_bob(delta)

func _frame_camera() -> void:
	super._frame_camera()
	_lift_bubbles()

## A bubble rises straight up, tail still over its control, while a spirit or
## its badge shares its place on screen, so a label never hides anyone and
## no badge sits on a label; it settles back once they move away. When that
## straight lift would run its tail across a spirit, the bubble slides aside
## instead (lifting only as much as still needed), so its tail leans past the
## spirit to the control; a spirit standing at the control hides the tail
## that runs behind it (LabelBubble draws a tail on its anchor's card), and
## no tail is ever seen across a spirit standing behind its control.
## Selector tails first follow their knobs as the levers tilt. Decided from
## the current state alone, so a frame never depends on the last. Bubbles a
## world draws over scenery are left to that world's own clearing. Worked out
## on the fixed journey view plane in metres (LabelBubble.plane_rect) from the
## bubbles and the snapshot's spirit positions, never the live viewport or
## animation, and rounded to whole centimetres, so every platform, window size
## and frame rate places bubbles alike.
func _lift_bubbles() -> void:
	if _bubbles.is_empty(): return
	_follow_knobs()
	var rise := LabelBubble.screen_up().y
	if _placed.size() < _bubbles.size(): _placed.resize(_bubbles.size())
	_placed_count = 0
	_find_spirits()
	for bubble: LabelBubble in _bubbles:
		if not is_instance_valid(bubble) or bubble.labels[0].no_depth_test: continue
		var rect := bubble.plane_rect(true)
		var anchor := (bubble.get_parent() as Node3D).to_global(bubble.anchor)
		var tip := LabelBubble.plane_point(anchor)
		var best_lean := 0.0
		var best_need := _need(rect,rise,bubble)
		if _tail_meets_spirit(Rect2(rect.position-Vector2(0,best_need*rise),rect.size),tip,anchor,false):
			# Beside each spirit, the side the world already shifted the body to
			# (else the left) first: stepping out a little further each time.
			# A straight lift whose tail only runs behind a spirit at the control
			# still competes; one seen across a spirit never does.
			var straight := Rect2(rect.position-Vector2(0,best_need*rise),rect.size)
			var cost := INF if _tail_meets_spirit(straight,tip,anchor,true) else best_need*LIFT_COST
			var first := 1.0 if rect.get_center().x > tip.x+0.01 else -1.0
			for index in range(_spirit_count):
				var box := _spirit_boxes[index]
				for turn in range(2):
					var side := first if turn == 0 else -first
					var beside := box.position.x-BUBBLE_CLEARANCE-rect.end.x if side < 0.0 else box.end.x+BUBBLE_CLEARANCE-rect.position.x
					for step: float in LEAN_STEPS:
						var lean := roundf((beside+side*step)*100.0)/100.0
						var moved := Rect2(rect.position+Vector2(lean,0),rect.size)
						if absf(LabelBubble.tail_root(moved,tip).x-tip.x) > LEAN_MAX: continue
						var need := _need(moved,rise,bubble)
						var placed := Rect2(moved.position-Vector2(0,need*rise),moved.size)
						if absf(lean)+need*LIFT_COST >= cost or _tail_meets_spirit(placed,tip,anchor,true) or _tail_meets_bubble(placed,tip) or _behind_scenery(bubble,lean,need): continue
						cost = absf(lean)+need*LIFT_COST
						best_lean = lean
						best_need = need
		_placed[_placed_count] = Rect2(rect.position+Vector2(best_lean,-best_need*rise),rect.size)
		_placed_count += 1
		bubble.set_lean(best_lean)
		bubble.set_lift(best_need)

## How far a bubble whose settled box is `rect` must rise: clear of every
## spirit it covers and of the world's own scenery (_scenery_need), then
## straight up over any bubble already placed (they are placed from the lowest
## on screen up), in whole centimetres.
func _need(rect: Rect2, rise: float, bubble: LabelBubble) -> float:
	var need := 0.0
	for index in range(_spirit_count):
		var spirit := _spirit_boxes[index]
		if rect.intersection(spirit).get_area() > spirit.get_area()*SPIRIT_COVER:
			need = maxf(need,(rect.end.y-spirit.position.y)/rise+BUBBLE_CLEARANCE)
	for _pass in range(4):
		var climb := _scenery_need(Rect2(rect.position-Vector2(0,need*rise),rect.size),bubble)
		need += climb
		for index in range(_placed_count):
			var other := _placed[index]
			var raised := Rect2(rect.position-Vector2(0,need*rise),rect.size)
			if raised.intersects(other): need += (raised.end.y-other.position.y)/rise+BUBBLE_CLEARANCE
		if climb <= 0.0: break
	return ceilf(need*100.0)/100.0

## How much further (metres) a bubble whose box is `rect` (as plane_rect, on
## the view plane) must climb to clear what the world keeps in view, for a
## world with scenery a bubble must not cover; none by default.
func _scenery_need(_rect: Rect2, _bubble: LabelBubble) -> float:
	return 0.0

## Whether the tail of a bubble standing at `placed` runs across a spirit's
## head or torso. visible_only: only where it would be seen. A spirit no
## further than SPIRIT_HIDES behind the tail's card hides it; where the
## control itself lies over a spirit on screen, the tail's last
## TIP_OVER_SPIRIT may run over it.
func _tail_meets_spirit(placed: Rect2, tip: Vector2, anchor: Vector3, visible_only: bool) -> bool:
	for index in range(_spirit_count):
		var head := _spirit_heads[index]
		var torso := _spirit_torsos[index]
		var trim := 0.0
		if visible_only:
			if LabelBubble.behind_card(_spirit_feet[index],anchor) <= SPIRIT_HIDES: continue
			if head.has_point(tip) or torso.has_point(tip): trim = TIP_OVER_SPIRIT
		if LabelBubble.tail_crosses(placed,tip,head,trim) or LabelBubble.tail_crosses(placed,tip,torso,trim): return true
	return false

## Whether that tail runs across the body of a bubble already placed.
func _tail_meets_bubble(placed: Rect2, tip: Vector2) -> bool:
	for index in range(_placed_count):
		var other := _placed[index]
		if LabelBubble.tail_crosses(placed,tip,Rect2(other.position,other.size-Vector2(0,LabelBubble.TAIL))): return true
	return false

## Whether scenery would hide a bubble leaning `lean` and lifted `need`
## (metres) from the camera: at least two of nine points across its body
## (a 3 by 3 grid) seen through a box of the stage's scenery.
func _behind_scenery(bubble: LabelBubble, lean: float, need: float) -> bool:
	if _sceneries.is_empty(): _gather_scenery()
	var boxes: Array = _sceneries.get(bubble,_sceneries[&"none"])
	if boxes.is_empty(): return false
	var up := LabelBubble.screen_up()
	var toward := LabelBubble.VIEW.normalized()
	var right := up.cross(toward)
	var center: Vector3 = bubble.body.global_position-bubble.position+right*lean+Vector3(0,need,0)
	var half := Vector2(bubble.body.scale.x*0.5,(bubble.body.scale.y-LabelBubble.TAIL)*0.5)
	var seen_through := 0
	for point in range(9):
		var at := center+right*(half.x*0.9*(float(point%3)-1.0))+up*(half.y*0.8*(floorf(float(point)/3.0)-1.0))
		for box: AABB in boxes:
			if box.intersects_ray(at,toward):
				seen_through += 1
				break
		if seen_through >= 2: return true
	return false

## Gathers, for every bubble, the boxes of the stage's meshes (not spirits,
## not bubbles, nothing flat) on screen where it may lean or rise to.
func _gather_scenery() -> void:
	_sceneries[&"none"] = []
	var boxes: Array[AABB] = []
	var rects: Array[Rect2] = []
	for node: Node in terrain.find_children("*","MeshInstance3D",true,false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree() or _moves_with_play(mesh): continue
		# A folded batch counts as the pieces it draws (kit/static_batch.gd).
		for box: AABB in StaticBatch.part_boxes(mesh):
			if box.size.y < 0.1: continue
			var low := Vector2.INF
			var high := -Vector2.INF
			for corner in range(8):
				var point := LabelBubble.plane_point(box.get_endpoint(corner))
				low = low.min(point)
				high = high.max(point)
			boxes.append(box)
			rects.append(Rect2(low,high-low))
	for bubble: LabelBubble in _bubbles:
		if not is_instance_valid(bubble): continue
		var rect := bubble.plane_rect(true)
		var reach := Rect2(rect.position-Vector2(LEAN_MAX,LabelBubble.MAX_TAIL+1.0),rect.size+Vector2(LEAN_MAX*2.0,LabelBubble.MAX_TAIL+1.0))
		var near: Array[AABB] = []
		for index in range(boxes.size()):
			if rects[index].intersects(reach): near.append(boxes[index])
		_sceneries[bubble] = near

## A spirit's or a bubble's own mesh, which never hides a bubble for good.
func _moves_with_play(node: Node) -> bool:
	while node != null and node != terrain:
		if node is LabelBubble or node in actors.values(): return true
		node = node.get_parent()
	return false

## Every visible spirit on the view plane this frame, where the snapshot puts
## it, not where its walk animation has got to: the same on every platform
## and frame rate.
func _find_spirits() -> void:
	_spirit_count = 0
	for slot: String in actors:
		var actor: Node3D = actors[slot]
		if not actor.visible or not actor_targets.has(slot) or not actor.get_parent() is Node3D: continue
		var at: Vector3 = (actor.get_parent() as Node3D).global_transform*(actor_targets[slot] as Vector3)
		var feet := LabelBubble.plane_point(at)
		var top := LabelBubble.plane_point(at+Vector3(0,SPIRIT_TOP,0))
		var head := LabelBubble.plane_point(at+Vector3(0,SPIRIT_HEAD.x,0))
		var torso := LabelBubble.plane_point(at+Vector3(0,SPIRIT_TORSO.x,0))
		if _spirit_boxes.size() <= _spirit_count:
			_spirit_boxes.resize(_spirit_count+2)
			_spirit_heads.resize(_spirit_count+2)
			_spirit_torsos.resize(_spirit_count+2)
			_spirit_feet.resize(_spirit_count+2)
		_spirit_boxes[_spirit_count] = Rect2(feet.x-SPIRIT_HALF_WIDTH,top.y,SPIRIT_HALF_WIDTH*2.0,feet.y-top.y)
		_spirit_heads[_spirit_count] = Rect2(head-Vector2.ONE*SPIRIT_HEAD.y,Vector2.ONE*SPIRIT_HEAD.y*2.0)
		_spirit_torsos[_spirit_count] = Rect2(torso-Vector2.ONE*SPIRIT_TORSO.y,Vector2.ONE*SPIRIT_TORSO.y*2.0)
		_spirit_feet[_spirit_count] = at
		_spirit_count += 1

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
				var last := elbow if elbow.distance_to(end)>0.01 else start
				# An owned route's end has its ownership mark at the cable's
				# height: the cable stops at the mark's edge, never under it.
				var stop := end
				if not str(route.get("owner_slot","")).is_empty(): stop = end-(end-last).normalized()*clampf(last.distance_to(end)-0.01,0.0,MARK_REACH+0.01)
				if elbow.distance_to(end)<=0.01: elbow = stop
				if start.distance_to(elbow)>0.01: _bar_between(start,elbow,0.016,color.darkened(0.25),terrain)
				if elbow.distance_to(stop)>0.01: _bar_between(elbow,stop,0.016,color.darkened(0.25),terrain)

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
	_follow_knobs()
	if is_instance_valid(_waiting_ring): _glow(_waiting_ring,CREAM,0.6 if state.get("can_commit",false) else 0.0)

func _should_cutaway(raised: Node3D, state: Dictionary) -> bool:
	if not _completion_view: return super._should_cutaway(raised,state)
	return Cutaway.anyone_below(raised,state)

func _camera_center() -> Vector3:
	var target := super._camera_center()
	if not _completion_view: target.z = clampf(actors[_camera_slot(_active_player)].position.z,-1.1,2.0)
	target.y = 0.45
	return target

extends "res://presentation/cooperative_world.gd"
## View adapter for the sealed simulation7 snapshot. The physical renderer and
## Lighthouse optical geometry remain shared; this file adds no game state.
const LabelBubble = preload("res://presentation/kit/label_bubble.gd")
const WaitHints = preload("res://presentation/wait_hints.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const CarriedItems = preload("res://core/physical/carried_items.gd")
const CarriedItemKit = preload("res://presentation/kit/pieces/carried_item.gd")
const CurrentKit = preload("res://presentation/kit/pieces/current.gd")
const ItemParts = preload("res://presentation/kit/pieces/parts.gd")
## The soft honey dashes round a crossing a wait hint names.
const HINT_DASH := Color("f2d39b")
## A selector's bubble body stands as if its tail ended here, just over the
## lever's knob; the tail's tip itself lands on the knob's top (_knob_top).
const LEVER_TOP := Vector3(0,0.80,0)
## A lever's knob (kit/pieces/lever.gd): its centre in the pivot's space, and
## its radius.
const KNOB := Vector3(0,LeverPiece.KNOB_CENTRE,0)
const KNOB_RADIUS := LeverPiece.KNOB_RADIUS
## A spirit's height on screen with its badge, and half its width, in metres.
const SPIRIT_TOP := 1.75
const SPIRIT_HALF_WIDTH := 0.42
## A spirit's head and torso, without the badge (spirit_look.gd): the
## height of each part's centre over its feet and a radius that covers it
## (metres, kept from the older, rounder spirit, so a little generous). On
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
## The view bubbles are laid out on: the world's camera_from() (kit/view_fit.gd).
var _view_from: Vector3:
	get: return camera_from()
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
## Placement (_place_bubbles) reads only what a snapshot, a stage or a history
## sets: the spirits' targets, the levers, wheels and pads, the bubbles' pills
## and the fixed view plane, never the live camera or any animation. So it runs
## once after one of those changes, not on every rendered frame.
var _placement_due := true
## Placement passes run so far (tests and profiling read it).
var placement_passes := 0
var _waiting_ring: MeshInstance3D
var _remembered: Node3D
## Wait hints (wait_hints.gd): off until the screen turns them on for a turn
## played beside a memory (set_wait_hints, WaitHints.wanted).
var _wait_hints := WaitHints.new()
var _wait_hints_on := false
## Hidden while the screen's fast-forward mark is over the world (hush_wait_hints).
var _wait_hints_hushed := false
## Per crossing the stage can hint about, built hidden with the stage and
## then only shown, hidden or reworded:
## route id -> {"bubble": LabelBubble, "dashes": MeshInstance3D, "anchor"}.
var _wait_marks: Dictionary = {}
## The stage on show, for the hints' anchors, and whether its build is done.
var _shown_stage: Dictionary = {}
var _stage_built := false
## Step seats (descriptor "seats"): [{"pad", "params"}], params being the
## sit pose's ({"seat": global point, "seat_radius"}); and each seat holder's
## last snapshot position, so it sits only while still.
var _seats: Array = []
var _seat_last: Dictionary = {}
## Rules 16's carried items and floats by id, and the stage's current
## (kit/pieces/carried_item.gd, current.gd); none on other rules.
var _item_pieces: Dictionary = {}
## Item id -> [where it rests, the platform stop it rests on]: it rides that
## stop's deck (kit/new_pieces.gd ride).
var _item_decks: Dictionary = {}
var _current_piece: RefCounted

func show_stage(stage: Dictionary) -> void:
	if str(stage.get("id", "")) == displayed_stage_id: return
	_journey_switches.clear()
	_bubbles.clear()
	_sceneries.clear()
	_journey_handles.clear()
	_waiting_ring = null
	_wait_marks.clear()
	_seats.clear()
	_seat_last.clear()
	_item_pieces.clear()
	_item_decks.clear()
	_current_piece = null
	_shown_stage = stage
	_stage_built = false
	# Before the build awaits: a present meanwhile reads this stage's crossings.
	_wait_hints.setup(stage, _descriptor(), PlayerCopy.WAIT_HINT_CROSSING)
	await super.show_stage(stage)
	_build_seats(stage)
	await _build_step()
	await _build_items(stage)
	_stage_built = true
	_build_wait_marks()
	_sort_bubbles()
	_placement_due = true
	var endpoint: Dictionary = stage.get("source_policy", {}).get("endpoint", {})
	if not endpoint.is_empty():
		var at := _at(endpoint)
		_waiting_ring = ring(float(endpoint.radius_cm)/100.0,CREAM,at+Vector3(0,0.018,0),terrain)
		_waiting_ring.name = "SourceWaitingRegion"

## Lowest on screen first: see _lift_bubbles.
func _sort_bubbles() -> void:
	var up := LabelBubble.screen_up(_view_from)
	_bubbles.sort_custom(func(a: LabelBubble, b: LabelBubble) -> bool: return a.anchor.dot(up) < b.anchor.dot(up))

func _configure_shared_view(view: Dictionary) -> void:
	# The renderer receives a detached stage view. Native optical dictionaries
	# and their exact canonical keys never gain presentation-only metadata.
	view["optics"] = view.get("optical_field", {"emitters":[],"receivers":[]}).duplicate(true)
	for slot: String in view.starts:
		if view.starts[slot] is Dictionary: view.starts[slot] = view.starts[slot].position_cm.duplicate()

func _beam_height() -> float: return 2.4
func _uses_lower_cutaway() -> bool: return true

## A control without a floor of its own stands on the highest island under it.
func _pair_control_anchor(entity: Dictionary) -> Vector3:
	return point(entity.position_cm)+Vector3(0,_control_base_height(entity),0)

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
	var owner := str(control.get("owner_slot", ""))
	var wheel := ring(0.14,CREAM if owner.is_empty() else GOLD if owner == "p0" else TEAL,Vector3.ZERO,hand)
	wheel.rotation.x = PI/2.0
	box(Vector3(0.035,0.26,0.035),CREAM,Vector3.ZERO,hand)
	_journey_handles[control.id] = hand
	mark_sound("control:%s" % control.id, hand)

## One speech bubble per selector, over the lever and pointing down at it,
## with one pill per value under its name from the descriptor's
## "selector_names" (else the value). `labels` keeps one Label3D per value
## (meta "backing" is its pill) for worlds that restyle a single value.
func _build_selector(control: Dictionary) -> void:
	_build_lever(control)
	var named: Dictionary = _descriptor().get("selector_names",{}).get(str(control.id),{})
	var names: Array = control.values.map(func(value: Variant) -> String: return str(named.get(str(value),value)))
	var bubble := _label_bubble(control.values,_selector_anchor(control),terrain,_selector_bubble_shift(control),names)
	_journey_switches[control.id] = {"values":control.values.duplicate(),"labels":bubble.labels,"bubble":bubble}
	_physical_levers[control.id].name = "RouteSwitch_"+str(control.id)
	bubble.set_anchor(_knob_top(str(control.id)))

## Every selector's tail to its knob's top, as the levers now tilt: after a
## world sets its levers (present) and before bubbles are placed.
func _follow_knobs() -> void:
	for id: String in _journey_switches:
		var bubble: LabelBubble = _journey_switches[id].bubble
		if is_instance_valid(bubble) and _physical_levers.has(id): bubble.set_anchor(_knob_top(id))
	for route: String in _wait_marks:
		var mark: Dictionary = _wait_marks[route]
		if (mark.bubble as LabelBubble).visible and _physical_levers.has(mark.anchor): (mark.bubble as LabelBubble).set_anchor(_knob_top(mark.anchor))

## The top of a selector lever's knob (terrain space), as the lever now tilts:
## where its bubble's tail lands.
func _knob_top(id: String) -> Vector3:
	var piece: RefCounted = _lever_pieces.get(id)
	var at: Transform3D = piece.anchor_rest() if piece != null else (_physical_levers[id] as Node3D).transform
	return at*KNOB+Vector3(0,KNOB_RADIUS,0)

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

func _label_bubble(values: Array, at: Vector3, parent: Node3D, shift: float = 0.0, names: Array = []) -> LabelBubble:
	var bubble := LabelBubble.new()
	bubble.build(parent,at,values,shift,names)
	if not reduced_motion: bubble.set_bob(true)
	_bubbles.append(bubble)
	return bubble

## Bubbles bob on the world's clock: they hold still whenever the world does
## (pause, review, a card), and settle under Reduce motion.
func _process(delta: float) -> void:
	super._process(delta)
	_advance_bubbles(delta)
	_advance_items(delta)

## A card holds the bob, but Reduce motion turned on still settles it.
func _idle_card_frame() -> void:
	super._idle_card_frame()
	_advance_bubbles(0.0)
	_advance_items(0.0)

## After the spirits have moved: a carried item follows its carrier's head, a
## float bobs (not with Reduce motion), a pick-up or set-down eases on.
func _advance_items(delta: float) -> void:
	for piece: RefCounted in _item_pieces.values():
		piece.reduced_motion = reduced_motion
		if piece.moving(): piece.advance(delta)

func _advance_bubbles(delta: float) -> void:
	for bubble: LabelBubble in _bubbles:
		if not is_instance_valid(bubble) or not bubble.visible: continue
		if bubble.is_bobbing() == reduced_motion: bubble.set_bob(not reduced_motion)
		bubble.advance_bob(delta)

## A world shown again (a staged build stays hidden until it is whole) gathers
## its scenery again and places its bubbles: while hidden, every mesh read as
## no scenery at all.
## A staged reveal shows the world before its parts (island_world.reveal_staged):
## its end counts as shown again too.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and is_visible_in_tree(): _regather_scenery()

func _regather_scenery() -> void:
	_sceneries.clear()
	_placement_due = true

func _frame_camera() -> void:
	super._frame_camera()
	if not _placement_due: return
	_placement_due = false
	_place_bubbles()

## One placement pass: each bubble refitted to its pills first (as its own
## frame would refit it), then placed. A world that clears its own scenery
## after the shared placement extends this.
func _place_bubbles() -> void:
	placement_passes += 1
	for bubble: LabelBubble in _bubbles:
		if is_instance_valid(bubble) and bubble.visible: bubble.sync()
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
	var rise := LabelBubble.screen_up(_view_from).y
	if _placed.size() < _bubbles.size(): _placed.resize(_bubbles.size())
	_placed_count = 0
	_find_spirits()
	for bubble: LabelBubble in _bubbles:
		if not is_instance_valid(bubble) or not bubble.visible or bubble.labels[0].no_depth_test: continue
		var rect := bubble.plane_rect(true)
		var anchor := (bubble.get_parent() as Node3D).to_global(bubble.anchor)
		var tip := LabelBubble.plane_point(anchor, _view_from)
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
			if LabelBubble.behind_card(_spirit_feet[index],anchor,_view_from) <= SPIRIT_HIDES: continue
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
	var up := LabelBubble.screen_up(_view_from)
	var toward := _view_from.normalized()
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
				var point := LabelBubble.plane_point(box.get_endpoint(corner), _view_from)
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
		var feet := LabelBubble.plane_point(at, _view_from)
		var top := LabelBubble.plane_point(at+Vector3(0,SPIRIT_TOP,0), _view_from)
		var head := LabelBubble.plane_point(at+Vector3(0,SPIRIT_HEAD.x,0), _view_from)
		var torso := LabelBubble.plane_point(at+Vector3(0,SPIRIT_TORSO.x,0), _view_from)
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
	# Only draw a cable where a mechanism and its route share a real floor;
	# every pair also wears its pair tags (pair_tags), never a path over void.
	for gate: Dictionary in view.get("gates",[]):
		var route: Dictionary = {}
		for candidate: Dictionary in view.bridges+view.get("stairs",[]):
			if candidate.id == gate.route_id: route = candidate
		if route.is_empty(): continue
		var references := PairTags.predicate_references(gate.get("when",{}))
		var r: Array = route.rect_cm
		# At the crossing's west end (its near end mark for a crossing that runs west
		# to east; kit/owner_mark.gd route_ends_of), owned or not.
		var end := OwnerMark.route_end_points(r)[0]+Vector3(0,float(route.get("from_height_cm",0))/100.0+OwnerMark.ROUTE_LIFT,0)
		for id: String in references:
			var entity: Dictionary = {}
			for item: Dictionary in view.get("controls",[])+view.get("levers",[])+view.get("pressure_pads",[])+view.optics.receivers:
				if item.id == id: entity = item
			if entity.is_empty(): continue
			var start := point(entity.position_cm)+Vector3(0,_control_base_height(entity)+0.025,0)
			var color := _route_color(id)
			if _shares_floor(start,end):
				var elbow := Vector3(end.x,start.y,start.z)
				var last := elbow if elbow.distance_to(end)>0.01 else start
				# An owned route's end has its ownership mark at the cable's
				# height: the cable stops at the mark's edge, never under it.
				var stop := end
				if not str(route.get("owner_slot","")).is_empty(): stop = end-(end-last).normalized()*clampf(last.distance_to(end)-0.01,0.0,OwnerMark.REACH+0.01)
				if elbow.distance_to(end)<=0.01: elbow = stop
				if start.distance_to(elbow)>0.01: _bar_between(start,elbow,0.016,color.darkened(0.25),terrain)
				if elbow.distance_to(stop)>0.01: _bar_between(elbow,stop,0.016,color.darkened(0.25),terrain)
				_cabled[str(route.id)] = true

func _route_color(id: String) -> Color:
	return GOLD if id in ["path-selector","high-light","crossing-light","near-window"] else TEAL

func _shares_floor(a: Vector3, b: Vector3) -> bool:
	if absf(a.y-b.y)>0.05: return false
	for island: Dictionary in chapter_definition.islands:
		var r: Array = island.rect_cm
		if a.x*100>=r[0] and a.x*100<=r[2] and a.z*100>=r[1] and a.z*100<=r[3] and b.x*100>=r[0] and b.x*100<=r[2] and b.z*100>=r[1] and b.z*100<=r[3]: return true
	return false

func present_history(checkpoint: Dictionary) -> void:
	super.present_history(checkpoint)
	_placement_due = true
	_wait_hints.set_start(checkpoint)
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
	_placement_due = true
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
		# Each style shows the value itself (kit/pieces/selector.gd).
		_lever_pieces[id].set_value(chosen, immediate or reduced_motion)
		(switch.bubble as LabelBubble).highlight(chosen)
	_follow_knobs()
	# Open turns never light the spot when a turn is ready (owner, 2026-11-16).
	if is_instance_valid(_waiting_ring): _glow(_waiting_ring,CREAM,0.6 if state.get("can_commit",false) and not OpenTurns.pinned(chapter_definition) else 0.0)
	_present_seats(state, immediate)
	_present_items(state, immediate)
	if _wait_hints_on and _wait_hints.update(state): _show_wait_marks()
	# What a world sets after this (its own levers and wheels) is read by the
	# next pass, not by the one an immediate present already ran.
	_placement_due = true

func _should_cutaway(raised: Node3D, state: Dictionary) -> bool:
	if not _completion_view: return super._should_cutaway(raised,state)
	return Cutaway.anyone_below(raised,state)

func _camera_center() -> Vector3:
	var target := super._camera_center()
	# A level with its own follow data (island_world._follow_data) follows
	# across and up as that data says.
	if str(_follow_data().get("axes", "x")) == "xz": return target
	if not _completion_view: target.z = clampf(_focus_point().z,-1.1,2.0)
	target.y = 0.45
	return target

# --- Wait hints ---

## Turns wait hints on for the live spirit's turn beside a memory, with the
## memory's length in ticks (MemoryWait.prior_ticks), or off.
func set_wait_hints(on: bool, memory_ticks: int = -1) -> void:
	_wait_hints_on = on
	_wait_hints.set_memory_ticks(memory_ticks if on else -1)
	# Turned on for a stage already built (the turn starts on the stage the
	# ready card showed): its marks are built now, before any play, and the
	# scenery the bubbles clear is gathered again with them.
	if on and _stage_built and _wait_marks.is_empty() and _wait_hints.has_candidates():
		_build_wait_marks()
		_sort_bubbles()
		_sceneries.clear()
		_placement_due = true
	if not on:
		_wait_hints.shown = []
		_show_wait_marks()

## The hints on screen now: [{"route", "anchor", "text"}].
func wait_hints() -> Array:
	return _wait_hints.shown if _wait_hints_on and not _wait_hints_hushed else []

## Hides the hint marks while the screen shows its fast-forward mark (a
## skipped or fast-forwarded wait), so the two never overlap, and shows the
## current ones again after. They keep being worked out meanwhile.
func hush_wait_hints(hushed: bool) -> void:
	if hushed == _wait_hints_hushed: return
	_wait_hints_hushed = hushed
	_show_wait_marks()

## How many times the hints were worked out.
func wait_hint_evaluations() -> int:
	return _wait_hints.evaluations

## With hints on, every crossing the stage can hint about gets its bubble
## (over the live spirit's lever or selector) and dashes, hidden, so the
## bubble is placed and cleared like every other and nothing is built
## mid-play. Solo play and replays build none.
func _build_wait_marks() -> void:
	if not _wait_hints_on or not _wait_marks.is_empty(): return
	for candidate: Dictionary in _wait_hints.candidates():
		var bubble := LabelBubble.new()
		bubble.build_sentence(terrain, _hint_anchor(str(candidate.anchor)), str(_descriptor().get("wait_hints", {}).get("fallback", "")))
		if not reduced_motion: bubble.set_bob(true)
		_bubbles.append(bubble)
		var dashes := _wait_dashes(str(candidate.route))
		_wait_marks[candidate.route] = {"bubble": bubble, "dashes": dashes, "anchor": str(candidate.anchor)}
		_show_mark(_wait_marks[candidate.route], false)

## Shows each hinted crossing's mark with its words; hides the rest. The
## next placement pass (_place_bubbles) places what changed.
func _show_wait_marks() -> void:
	var live: Dictionary = {}
	for hint: Dictionary in wait_hints():
		var mark: Dictionary = _wait_marks.get(hint.route, {})
		if mark.is_empty(): continue
		live[hint.route] = true
		(mark.bubble as LabelBubble).set_sentence(str(hint.text))
		_show_mark(mark, true)
	for route: String in _wait_marks:
		if not live.has(route): _show_mark(_wait_marks[route], false)
	_placement_due = true

## A hidden bubble also stops refitting itself every frame.
func _show_mark(mark: Dictionary, shown: bool) -> void:
	var bubble: LabelBubble = mark.bubble
	bubble.visible = shown
	bubble.set_process(shown)
	(mark.dashes as Node3D).visible = shown
	if shown: bubble.set_anchor(_hint_anchor(str(mark.anchor)))

## Where a hint's tail points: the top of its lever's knob, as the lever now
## tilts, else just over the stage's control or lever.
func _hint_anchor(id: String) -> Vector3:
	if _physical_levers.has(id): return _knob_top(id)
	for key: String in ["controls", "levers"]:
		for item: Dictionary in _shown_stage.get(key, []):
			if str(item.id) == id: return _at(item)+LEVER_TOP
	return Vector3.ZERO

## The dashes show and hide with their hints: never folded (_static_keep).
func _static_keep() -> Array:
	var keep := super._static_keep()
	for mark: Dictionary in _wait_marks.values(): keep.append(mark.dashes)
	for piece: RefCounted in _item_pieces.values(): keep.append_array(piece.moving_parts())
	if _current_piece != null: keep.append_array(_current_piece.moving_parts())
	return keep

## Soft dashes along a crossing's edges at its deck height: one mesh, shown or
## hidden with its hint.
func _wait_dashes(route_id: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "WaitDashes_"+route_id
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain.add_child(node)
	var route: Dictionary = {}
	for candidate: Dictionary in chapter_definition.get("bridges", []) + chapter_definition.get("stairs", []):
		if str(candidate.id) == route_id: route = candidate
	if route.is_empty(): return node
	var r: Array = route.rect_cm
	var y := float(route.get("height_cm", route.get("from_height_cm", 0)))/100.0+0.02
	var low := Vector2(float(r[0]), float(r[1]))/100.0+Vector2.ONE*0.04
	var high := Vector2(float(r[2]), float(r[3]))/100.0-Vector2.ONE*0.04
	var along_x := Primitives.shared_mesh("box", 0.11, 0.02, 0.045)
	var along_z := Primitives.shared_mesh("box", 0.045, 0.02, 0.11)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge: Array in [[low, Vector2(high.x, low.y)], [Vector2(low.x, high.y), high], [low, Vector2(low.x, high.y)], [Vector2(high.x, low.y), high]]:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		var count := int(a.distance_to(b)/0.20)
		for index in range(count):
			var at := a.lerp(b, (float(index)+0.5)/float(count))
			tool.append_from(along_x if absf(b.x-a.x) > 0.01 else along_z, 0, Transform3D(Basis.IDENTITY, Vector3(at.x, y, at.y)))
	node.mesh = tool.commit()
	# An opaque shaded kit material: no shader variant the stage lacks.
	node.material_override = Primitives.shared_material(HINT_DASH)
	return node

# --- Step seats ---

func _seated(pad_id: String) -> bool:
	return _descriptor().get("seats", {}).has(pad_id)

## A seat prop on each pad the descriptor's "seats" names
## ({pad id: a kit/props.gd spec without "at"}).
func _build_seats(stage: Dictionary) -> void:
	var seats: Dictionary = _descriptor().get("seats", {})
	if seats.is_empty(): return
	for pad: Dictionary in stage.get("pressure_pads", []):
		if not seats.has(str(pad.id)): continue
		var spec: Dictionary = seats[pad.id].duplicate()
		spec["at"] = pad.position_cm
		var base := _at(pad).y
		var prop := Props.build(spec, terrain, base, false)
		if prop == null: continue
		# A seat is the pad's, not the chapter's dressing.
		prop.name = "Seat_"+str(pad.id)
		prop.remove_meta("dressing_kind")
		var extent := Props.extent(spec)
		var top := terrain.to_global(Vector3(prop.position.x, base+float(extent.height), prop.position.z))
		_seats.append({"pad": pad, "params": {"seat": top, "seat_radius": (extent.rect as Rect2).size.x*0.5}})

## Whoever holds a seat's pad sits on it while standing still, and stands
## the moment its snapshot moves. A dozing spirit (memory wait) keeps its
## doze: only the live spirit dozes, so a chapter whose seats are all the
## first spirit's never sees a seat holder doze. A chapter that seats the
## live spirit would see it doze inside its seat.
func _present_seats(state: Dictionary, immediate: bool) -> void:
	if _seats.is_empty() or not state.has("players"): return
	for seat: Dictionary in _seats:
		# A pad either pip holds (open controls) seats either.
		var owner := str(seat.pad.get("owner_slot", ""))
		for slot: String in ([owner] if not owner.is_empty() else ["p0", "p1"]):
			if not actors.has(slot) or not state.players.has(slot): continue
			var player: Dictionary = state.players[slot]
			var here := Vector3i(int(player.x), int(player.height), int(player.z))
			var still: bool = immediate or _seat_last.get(slot) == here
			_seat_last[slot] = here
			var actor: SpiritVisual = actors[slot]
			var pose := actor.pose()
			if still and Seven.near(player, seat.pad):
				if pose != SpiritVisual.SpiritIdle.DOZE: actor.set_pose(SpiritVisual.SpiritIdle.SIT, seat.params, immediate)
			elif pose == SpiritVisual.SpiritIdle.SIT: actor.set_pose(SpiritVisual.SpiritIdle.REST, {}, true)

# --- Rules 16: carried items, floats, currents and both-hands crossings ---

## Every item of the level in its style (a pin by id, else the dressing's
## "carried_item" pick; a float nobody carries is a raft unless pinned), every
## item spot in its "item_spot" style (a pedestal, a planter, a nest or none:
## kit/pieces/socket.gd item_spot), the stage's current legs, and the rungs
## that mark a crossing needing both hands (core/physical/carried_items.gd): a
## carrier stops at a ladder. A rope bridge (kit/pieces/deck.gd) needs no rungs.
func _build_items(stage: Dictionary) -> void:
	var view: Dictionary = CooperativeCatalog.stage_definition(chapter_definition, str(stage.get("id", "")))
	if view.get("items", []).is_empty(): return
	for spot: Dictionary in view.get("item_spots", []):
		var look := _piece_style("item_spot", str(spot.id))
		if look == "none": continue
		var root := Node3D.new()
		root.name = "ItemSpot_" + str(spot.id)
		root.position = _at(spot)
		terrain.add_child(root)
		SocketKit.item_spot(look, root, spot)
	var start: Dictionary = CarriedItems.initial(view)
	for item: Dictionary in view.items:
		var id := str(item.id)
		var pin := PieceStyles.pinned_style("carried_item", id, _descriptor())
		var look := pin if not pin.is_empty() else _piece_style("carried_item", id) if CarriedItems.carriable(item) else "raft"
		var at := _item_point(start.get(id, {})) if str(start.get(id, {}).get("holder", "")).is_empty() else Vector3.ZERO
		_item_pieces[id] = CarriedItemKit.build(look, at, terrain, {"id": id})
		# On a world with the water kit, rings spread from it while it floats.
		var water: Variant = get("waters")
		if water != null: water.ripple_from(_item_pieces[id].root)
		await _build_step()
	var legs: Array = []
	for leg: Dictionary in view.get("current_legs", []):
		legs.append({"from": _item_point(CarriedItems.at_spot(CarriedItems.spot(view, str(leg.from)))), "to": _item_point(CarriedItems.at_spot(CarriedItems.spot(view, str(leg.to)))), "control_id": str(leg.get("control_id", "")), "value": str(leg.get("value", ""))})
	if not legs.is_empty():
		_current_piece = CurrentKit.build(_piece_style("current", str(view.current_legs[0].get("control_id", ""))), legs, terrain, _current_water.bind(view))
		_ride_current(legs)
	await _build_step()
	var hands := CarriedItems.hands_routes(view)
	for route: Dictionary in view.get("bridges", []) + view.get("stairs", []):
		# A rope bridge's slats and hand ropes are its own cause; rungs that
		# stay would draw over its gap while it is shut.
		var rope: bool = new_pieces != null and view.get("bridges", []).has(route) and new_pieces.deck_style(str(route.id)) == "rope"
		if hands.has(str(route.id)) and not rope:
			_ladder_rungs(route)
			await _build_step()
	# A throw's mark is a cream ring where the thrower stands; its landing the
	# seed landing's ring of ticks (kit/pieces/socket.gd).
	for thrown: Dictionary in view.get("throws", []):
		var mark := ring(float(thrown.mark.get("radius_cm", CarriedItems.SPOT_RADIUS_CM)) / 100.0, CREAM, _at(thrown.mark) + Vector3(0, 0.03, 0), terrain)
		mark.name = "ThrowMark_" + str(thrown.id)
		var landing := Node3D.new()
		landing.name = "ThrowLanding_" + str(thrown.id)
		landing.position = _at(CarriedItems.spot(view, str(thrown.to)))
		terrain.add_child(landing)
		SocketKit.landing(landing)

## The node drawing item `id` (over its carrier's head or where it rests), or
## null: an ending scene hides it while its own stands in for it.
func item_node(id: String) -> Node3D:
	return _item_pieces[id].root if _item_pieces.has(id) else null

## Where an item state rests in the terrain's space (on the water when its
## floor is none).
## Whether a current's mark may lie at `at` (terrain m): off every floor and
## crossing of the stage, so no mark ever draws on dry ground; a water world
## also wants water there.
func _current_water(at: Vector3, view: Dictionary) -> bool:
	var point := Vector2(at.x, at.z) * 100.0
	for surface: Dictionary in view.get("islands", []) + view.get("bridges", []) + view.get("stairs", []):
		var r: Array = surface.rect_cm
		if point.x >= float(r[0]) and point.x <= float(r[2]) and point.y >= float(r[1]) and point.y <= float(r[3]): return false
	return true

## A world with water rides each leg's marks on its body (water_world).
func _ride_current(_legs: Array) -> void:
	pass

func _item_point(state: Dictionary) -> Vector3:
	if state.is_empty(): return Vector3.ZERO
	# Thrown: where its arc has it.
	if CarriedItems.in_flight(state): return Vector3(float(state.x), float(state.height), float(state.z)) / 100.0
	# On a platform's stop: at that stop's height (its deck carries it there).
	if new_pieces != null and not new_pieces.ride(str(state.surface_id)).is_empty(): return Vector3(float(state.x), float(state.height), float(state.z)) / 100.0
	var at := _at({"position_cm": [int(state.x), int(state.z)], "surface_id": str(state.surface_id)})
	# At a drawn item spot: on its pedestal, in its planter's soil or its nest.
	var spot := str(state.get("spot", ""))
	return at if spot.is_empty() else at + Vector3(0, SocketKit.rest_height(_piece_style("item_spot", spot)), 0)

## Rungs across a both-hands crossing every RUNG_CM along it, at its height
## there, with a post at each end: plain leaves the static fold batches.
const RUNG_CM := 14
## How far in from the crossing's long edge each end post stands (m).
const RUNG_POST_IN := 0.075
func _ladder_rungs(route: Dictionary) -> void:
	var rect: Array = route.rect_cm
	var ends := CarriedItems.route_ends(route)
	var axis := 0 if int(ends[0].x) != int(ends[1].x) else 1
	var low := int(rect[axis])
	var high := int(rect[axis + 2])
	var across := float(int(rect[3 - axis]) - int(rect[1 - axis])) / 100.0
	var middle := (float(rect[1 - axis]) + float(rect[3 - axis])) / 200.0
	var at := low + RUNG_CM / 2
	while at < high:
		var rise := float(ends[0].height) + float(int(ends[1].height) - int(ends[0].height)) * float(at - low) / float(maxi(1, high - low))
		var spot := Vector3(float(at) / 100.0, rise / 100.0 + 0.03, middle) if axis == 0 else Vector3(middle, rise / 100.0 + 0.03, float(at) / 100.0)
		var rung := ItemParts.rod(0.018, across - 0.08, ItemParts.TIMBER_LIGHT, spot, terrain)
		if axis == 0: rung.rotation = Vector3(PI / 2.0, 0, 0)
		at += RUNG_CM
	for end: Dictionary in ends:
		for side: float in [-1.0, 1.0]:
			# In from the crossing's edge, clear of the light strip along it.
			var post := Vector3(float(end.x) / 100.0, float(end.height) / 100.0 + 0.2, middle + side * (across / 2.0 - RUNG_POST_IN)) if axis == 0 else Vector3(middle + side * (across / 2.0 - RUNG_POST_IN), float(end.height) / 100.0 + 0.2, float(end.z) / 100.0)
			ItemParts.box(Vector3(0.04, 0.4, 0.04), ItemParts.TIMBER, post, terrain)

## Each item where the snapshot has it: held over its holder's head the way a
## seed or a lens is, resting at its place, or bobbing on the water; the
## current's legs lit by their wheels. A pip that lets an item go throws it
## (into its arc) or settles its head, as it does for the seed and the lens.
func _present_items(state: Dictionary, immediate: bool = false) -> void:
	if _item_pieces.is_empty(): return
	var items: Dictionary = state.get("mechanisms", {}).get("items", {})
	for id: String in _item_pieces:
		var item_state: Dictionary = items.get(id, {})
		_item_decks.erase(id)
		if item_state.is_empty(): continue
		var piece: RefCounted = _item_pieces[id]
		# Away (carried_items.gd): not in the level, so nothing shows.
		piece.root.visible = not CarriedItems.is_away(item_state)
		if not piece.root.visible: continue
		var holder := str(item_state.holder)
		piece.reduced_motion = reduced_motion
		if not holder.is_empty() and actors.has(holder): piece.carry(actors[holder], immediate)
		else:
			var flying := CarriedItems.in_flight(item_state)
			if not immediate and is_instance_valid(piece.holder):
				if flying: piece.holder.play_throw()
				else: piece.holder.play_carry_release()
			piece.rest(_item_point(item_state), terrain, str(item_state.surface_id).is_empty() and not flying, flying, immediate)
			if new_pieces != null and not new_pieces.ride(str(item_state.surface_id)).is_empty(): _item_decks[id] = [_item_point(item_state), str(item_state.surface_id)]
	_ride_items()
	if _current_piece != null: _current_piece.set_controls(state.get("controls", {}))

## The platforms move first, then the items resting on their decks with them.
func _advance_carriers(delta: float) -> void:
	super._advance_carriers(delta)
	_ride_items()

## Each item resting on a platform's stop, as far from its place as the deck
## stands from that stop (the one rider rule, kit/new_pieces.gd ride).
func _ride_items() -> void:
	for id: String in _item_decks:
		var deck: Array = new_pieces.ride(str(_item_decks[id][1]))
		if not deck.is_empty(): _item_pieces[id].place((_item_decks[id][0] as Vector3) + (deck[1] as Vector3))
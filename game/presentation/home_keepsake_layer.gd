extends Node3D
## Home's keepsakes: one per card on the Chapters page, standing on the Home
## islands and the keepsake isles (presentation/keepsakes/home_isles.gd;
## services/home_keepsake_states.gd decides what each shows; a chapter's
## descriptor names its builder, presentation/keepsakes/). A view of earned
## records, never an award source.
##
## The props carry no script: their geometry sits under one plain "Props" node
## that this layer folds into shared batches (kit/static_batch.gd), while the
## moving parts a builder returns stay their own nodes, held in _held. A change
## of state waits REBUILD_DELAY, so a burst of awards (the backfill, a cloud
## merge) rebuilds once; the new set is built unseen, folded a slice a frame and
## swapped in whole, so nothing flickers. A tap, an Explore press or the pip
## walking into one plays one keepsake: this layer owns the Tween, ignores a
## second start while it plays, waits with any rebuild until it ends, then eases
## every part back to its rest pose, except what its beats keep (a flower left
## grown, a lamp left on): that is held, and only turns (advance_held()), until
## the keepsake is pressed again or the set is rebuilt. Nothing held is saved.
## Leaving Home frees the layer, and the Tween with it.
##
## In Explore the stage reports each step the pip takes (walked()); nothing
## here runs while the pip stands still. A step can set a keepsake off (its
## builder's trigger()), carry the pip on a ride, or take it in and out of a
## keepsake's stay (a house, a lantern path). The pip walks on the islands, the
## bridges and a keepsake's walkways, and never into a keepsake's solids or
## under its low parts (the Rolling Rail's dip, builder.ride_overhead()).
const States = preload("res://services/home_keepsake_states.gd")
const Parts = preload("res://presentation/keepsakes/keepsake_parts.gd")
const Anim = preload("res://presentation/keepsakes/keepsake_anim.gd")
const Card = preload("res://presentation/keepsakes/keepsake_card.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const Isles = preload("res://presentation/keepsakes/home_isles.gd")
const Builder = preload("res://presentation/keepsakes/keepsake_builder.gd")
const Explore = preload("res://presentation/keepsakes/keepsake_explore.gd")
const Approach = preload("res://presentation/keepsakes/ride_approach.gd")
## Home draws each keepsake this many island metres per prop unit.
const HOME_SCALE := 1.0
## A keepsake faces the Home camera (its +z along the camera's ground
## direction) unless its descriptor turns it with a "yaw".
const CAMERA_FLAT := Vector3(0.5547, 0, 0.8321)
## Taps pick the nearest keepsake within this many viewport pixels.
const PICK_RADIUS := 40.0
const REBUILD_DELAY := 0.5
const FOLD_SLICE_USEC := 2000
## Reduced motion holds the lit pose this long.
const REDUCED_HOLD := 1.0
const HIGHLIGHT := Color("f6efd2")
## A crossing carries the spirit from CROSSING_PAD before its start to as far
## past its end, and over a plank once it is within DECK_TOLERANCE of its deck.
const CROSSING_PAD := 0.4
const DECK_TOLERANCE := 0.05
## An island's walkable floor stops this far inside its edges.
const FLOOR_INSET := 0.25

var _world: Node3D
var _free_only := false
var together_hard := false
## (cue: String, variant: int) -> void: plays one keepsake sound. Variant n is
## the n-th drop of a water run (soundscape fixed_pitch); 0 for everything else.
var cue: Callable
## A ride's joy (keepsake_anim.gd): (pip: Node3D) -> void pops a heart over the
## pip, and () -> void taps the phone lightly (Settings' Haptics decides).
var pop_heart: Callable
var haptic: Callable
var _entries: Array = []
var _builders: Dictionary = {}
var _result: Dictionary = {}
var _items: Dictionary = {}
## Keepsakes shown now (keepsake, started or next), in Home order.
var _shown: Array[String] = []
var selected_index := 0
## The set drawn now and the one being built: {"root", "props": {id: {"name",
## "parts", "state", "look", "solids", "overhead"}}, "keys": {id: look key}};
## "overhead" holds the solids that keep the pip from under low parts.
var _set: Dictionary = {}
var _next: Dictionary = {}
## Every moving part of both sets, so no fold ever takes them.
var _held: Array[Node] = []
var _fold: Dictionary = {}
var _rebuild_in := -1.0
## The tap playing now: {"id", "tween", "anim", "rest", "settling", "spins"}.
var _play: Dictionary = {}
## Keepsakes holding what their last tap kept (keepsake_anim.gd keep, spin),
## by id: {"rest", "spawned", "fx", "made", "spins"}. A rebuilt set has none.
var _kept: Dictionary = {}
## Every spin turning now, held or in a tap's ease back (advance_held()).
var _spins: Array[Dictionary] = []
var _highlight: MeshInstance3D
## Walkable floors and island middles by island id ("left", "right" and the isles).
var _floors: Dictionary = {}
var _islands: Dictionary = {}
var _crossings: Array[Dictionary] = []
## Per keepsake, worked out once: {"placed", "inverse", "trigger", "stay",
## "walkways", "gated": whether it has gates (builder.gates()), "reach":
## [middle, radius] round everything a step can meet}.
var _frames: Dictionary = {}
var _explore := Explore.new(self)
## Sets built since configure(), for tests that prove a burst rebuilds once,
## and steps walked() was asked about, for tests that prove a still pip asks nothing.
var builds := 0
var steps := 0

## `earned`: the ledger's places (HomeKeepsakes.earned_descriptors()); `hard`:
## HardMode.marks(); `free_only`: a build that sells nothing.
func configure(world: Node3D, earned: Array, hard: Dictionary, together: bool, free_only: bool = false) -> void:
	_world = world
	_free_only = free_only
	together_hard = together
	name = "HomeKeepsakes"
	_entries = States.entries(free_only)
	for entry: Dictionary in _entries: _builders[entry.id] = load(str(entry.keepsake.builder)).new()
	_build_ground()
	for entry: Dictionary in _entries: _frames[entry.id] = _frame_of(str(entry.id))
	_highlight = Primitives.mesh_node(Primitives.ring_mesh(0.62), Primitives.shared_material(HIGHLIGHT, 0.6, HIGHLIGHT, 0.6), Vector3(0, 0.06, 0), self)
	_highlight.name = "SelectedSlot"
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply(earned, hard, true)

## New marks: the card follows at once, the props after REBUILD_DELAY.
func set_marks(earned: Array, hard: Dictionary, together: bool) -> void:
	together_hard = together
	_apply(earned, hard, false)

func _apply(earned: Array, hard: Dictionary, first: bool) -> void:
	var before := _items.duplicate(true)
	var selected_id := "" if _shown.is_empty() else _shown[selected_index]
	_result = States.states(_entries, earned, hard, together_hard)
	_items.clear()
	_shown.clear()
	for item: Dictionary in _result.items:
		_items[item.id] = item
		if item.look != "none": _shown.append(item.id)
	var advanced := ""
	for id: String in _shown:
		if before.has(id) and _rank(_items[id]) > _rank(before[id]): advanced = id
	if not advanced.is_empty(): selected_id = advanced
	selected_index = _shown.find(selected_id) if _shown.has(selected_id) else _first_unfinished()
	if first:
		_set = _make_set(true)
		_start_fold(_set)
	elif _keys() != _set.get("keys", {}) and (_next.is_empty() or _keys() != _next.keys):
		_rebuild_in = REBUILD_DELAY
		set_process(true)
	_show_selected()

## How far a keepsake has come, to follow progress with the selection.
static func _rank(item: Dictionary) -> int:
	return {"none": 0, "next": 0, "started": 1, "keepsake": 2}.get(item.look, 0) + int(item.together) + int(item.hard) + int(item.top)

## What each shown keepsake looks like, for telling when a rebuild is due.
func _keys() -> Dictionary:
	var keys := {}
	for id: String in _shown:
		var item: Dictionary = _items[id]
		keys[id] = [item.look, item.together, item.hard, item.top, item.stages if item.look == "started" or id == States.EARLIER else []]
	return keys

func _entry(id: String) -> Dictionary:
	for entry: Dictionary in _entries:
		if entry.id == id: return entry
	return {}

# --- building and folding ---------------------------------------------------------

## Where a keepsake stands: its slot from its island's middle, facing the
## camera unless its descriptor gives a yaw.
func slot_transform(id: String) -> Transform3D:
	if _frames.has(id): return _frames[id].placed
	var entry := _entry(id)
	var middle: Vector2 = _islands.get(str(entry.keepsake.island), Vector2.ZERO)
	var slot: Array = entry.keepsake.slot
	var yaw := float(entry.keepsake.get("yaw", atan2(CAMERA_FLAT.x, CAMERA_FLAT.z)))
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * HOME_SCALE), Vector3(middle.x + float(slot[0]), 0.0, middle.y + float(slot[1])))

## Everything about a keepsake that never changes with its state.
func _frame_of(id: String) -> Dictionary:
	var placed := slot_transform(id)
	var builder: RefCounted = _builders[id]
	var trigger: Dictionary = builder.trigger()
	var stay: Rect2 = builder.stay()
	var walkways: Array[Rect2] = builder.walkways()
	var reach := builder.footprint() as Rect2
	if trigger.has("area"): reach = reach.merge(trigger.area)
	if trigger.has("line"): reach = reach.expand(trigger.line[0]).expand(trigger.line[1])
	if stay.has_area(): reach = reach.merge(stay)
	var middle := placed * Vector3(reach.get_center().x, 0, reach.get_center().y)
	return {"placed": placed, "inverse": placed.affine_inverse(), "trigger": trigger, "stay": stay, "walkways": walkways,
		"gated": not builder.gates({}, {}, Vector2(INF, INF)).is_empty(), "reach": [Vector2(middle.x, middle.z), reach.size.length() * 0.5 * HOME_SCALE + 0.3]}

## The state a builder draws: the earned upgrades, and the Lantern Walk's lanterns.
func _look(id: String) -> Dictionary:
	var item: Dictionary = _items[id]
	var state := {"together": item.together, "hard": item.hard, "top": item.top}
	if id == States.EARLIER: state.lanterns = item.stages.map(func(stage: Array) -> bool: return stage[0] or stage[1])
	return state

func _make_set(shown_now: bool) -> Dictionary:
	var root := Node3D.new()
	root.name = "Props" if shown_now else "NextProps"
	root.visible = shown_now
	add_child(root)
	var props := {}
	for id: String in _shown:
		var item: Dictionary = _items[id]
		var holder := Node3D.new()
		holder.name = "Keepsake_" + id.replace("-", "_")
		holder.transform = slot_transform(id)
		root.add_child(holder)
		var builder: RefCounted = _builders[id]
		var parts: Dictionary = {}
		var state := _look(id)
		if item.look == "keepsake":
			parts = builder.build(holder, state)
		else:
			var plain := {}
			if id == States.EARLIER: plain.lanterns = state.lanterns.map(func(_lit: bool) -> bool: return false)
			Parts.outline(holder, builder, "%s|%d" % [id, item.stages.size()], item.stages if item.look == "started" else [], plain)
		for part: Node in _moving(parts): _held.append(part)
		var drawn := state if item.look == "keepsake" else {}
		var solids: Array[Rect2] = builder.solids(drawn)
		var overhead := Approach.kept_off(builder.ride_overhead(drawn), WALK_CLEARANCE)
		props[id] = {"name": holder.name, "parts": parts, "state": state, "look": item.look, "solids": solids, "overhead": overhead}
	builds += 1
	return {"root": root, "props": props, "keys": _keys()}

## A builder's moving parts: its parts that are nodes.
static func _moving(parts: Dictionary) -> Array[Node]:
	var result: Array[Node] = []
	for part: Variant in parts.values():
		if part is Node: result.append(part)
	return result

func _start_fold(target: Dictionary) -> void:
	_fold = StaticBatch.start(target.root, [self], {"containers": true})

func _process(delta: float) -> void:
	if _rebuild_in >= 0.0:
		_rebuild_in -= delta
		if _rebuild_in < 0.0:
			if not _play.is_empty(): _rebuild_in = 0.0
			else: _begin_rebuild()
	if not _fold.is_empty() and StaticBatch.step(_fold, FOLD_SLICE_USEC): _fold = {}
	if not _next.is_empty() and _fold.is_empty() and _play.is_empty(): _swap()
	if _rebuild_in < 0.0 and _fold.is_empty() and _next.is_empty(): set_process(false)

func _begin_rebuild() -> void:
	if not _next.is_empty():
		remove_child(_next.root)
		(_next.root as Node).queue_free()
		_next = {}
		_fold = {}
	_next = _make_set(false)
	_start_fold(_next)

func _swap() -> void:
	var old: Node3D = _set.get("root")
	_set = _next
	_next = {}
	(_set.root as Node3D).visible = true
	if is_instance_valid(old):
		remove_child(old)
		old.queue_free()
	(_set.root as Node3D).name = "Props"
	# What the old set held went with it.
	_kept.clear()
	_sync_spins()
	_held.clear()
	for id: String in _set.props:
		for part: Node in _moving(_set.props[id].parts): _held.append(part)
	_explore.set_swapped()

## Whether the set drawn now is still being built or folded.
func settling() -> bool:
	return not _next.is_empty() or not _fold.is_empty() or _rebuild_in >= 0.0

# --- playing ------------------------------------------------------------------------

## Whether a keepsake can play now: drawn earned in the set on screen (a
## keepsake just earned plays once its rebuilt set is swapped in).
func playable(id: String) -> bool:
	return _set.get("props", {}).get(id, {}).get("look") == "keepsake"

## Plays a keepsake. A second start on the one playing changes nothing until
## its beats are over (as it eases back, it counts as pressed again); a
## start on another ends the first in its rest pose and plays the new one,
## except during a ride, which always finishes. A keepsake holding what its
## last tap kept goes back to rest and plays from the start, or, if its
## builder SWITCHes, plays its "off" beat from where it stands. `rider`: the
## pip, when it set the keepsake off in Explore. False for a keepsake that is
## not drawn earned.
func play(id: String, rider: Node3D = null) -> bool:
	if not playable(id) or (_play.get("id") == id and not _play.settling) or riding(): return false
	# A tap easing back ends holding what it kept (_end_play), so this press finds it held.
	if not _play.is_empty(): _end_play()
	var prop: Dictionary = _set.props[id]
	var holder := (_set.root as Node3D).get_node_or_null(NodePath(prop.name)) as Node3D
	if holder == null: return false
	var builder: RefCounted = _builders[id]
	var held: Dictionary = _kept.get(id, {})
	var off: bool = not held.is_empty() and builder.press_again() == Builder.SWITCH
	if off: _kept.erase(id)
	else: _release(id)
	var state: Dictionary = prop.state.duplicate()
	state.sounds = _entry(id).keepsake.get("sounds", {})
	# Where the other spirit stands, in the keepsake's frame (the Crossroads points there).
	var other: Variant = _world.get("actors").get("b") if is_instance_valid(_world) and _world.get("actors") is Dictionary else null
	if other is Node3D and is_instance_valid(other):
		var toward := (transform * slot_transform(id)).affine_inverse() * (other as Node3D).position
		state.toward = Vector2(toward.x, toward.z)
	var anim := Anim.new()
	anim.cue = cue
	anim.pop_heart = pop_heart
	anim.haptic = haptic
	anim.reduced = _reduced()
	if off:
		# The off beat starts from what was held: its parts go when it ends.
		anim.fx = held.fx
		anim.made = held.made
		anim.spawned.append_array(held.spawned)
	else:
		anim.fx = Node3D.new()
		anim.fx.name = "Tap"
		holder.add_child(anim.fx)
	if is_instance_valid(rider):
		anim.rider = rider
		anim.rider_frame = transform * slot_transform(id)
		anim.rider_from = anim.rider_frame.affine_inverse() * rider.position
	var tween := create_tween().set_parallel(true)
	if not anim.reduced: anim.tween = tween
	var time := _approach(id, builder, state, anim)
	for beat: Dictionary in [{"beat": "off", "time": builder.off_time()}] if off else builder.beats(state):
		anim.start = time
		builder.play(str(beat.beat), anim, prop.parts, state)
		time += float(beat.time)
	# Held parts go back to the rest they had before the tap that kept them.
	var rest: Array = held.rest.duplicate() if off else []
	var known := {}
	for entry: Array in rest: known[entry[0]] = true
	for node: Variant in anim.touched:
		if is_instance_valid(node) and not anim.spawned.has(node) and not known.has(node): rest.append(_rest_of(node))
	if anim.reduced: anim.apply_jumps()
	# A ride gives the pip back the moment it lands, while the rest still plays.
	elif anim.landing != null: tween.tween_callback(_land.bind(anim, true)).set_delay(anim.landing_time())
	tween.tween_interval(REDUCED_HOLD if anim.reduced else time)
	tween.finished.connect(_settle)
	# A held turn keeps turning through the off beat.
	_play = {"id": id, "tween": tween, "anim": anim, "rest": rest, "settling": false, "spins": held.spins if off else [], "off": off}
	_sync_spins()
	return true

## A ride set off where the pip cannot ride from (the Explore action beside or
## behind the Giant Steps, the Rolling Rail's stand or the Turn of the Tide's
## pool): the pip hops round the keepsake's solids, on ground it may walk, to
## where it can (builder.ride_start(), ride_approach.gd), and the ride starts
## from there. With no way round it plays as a tap and the pip stays put, so
## no ride ever hops it through the keepsake. Returns when it gets there (0
## for no hops).
func _approach(id: String, builder: RefCounted, state: Dictionary, anim: RefCounted) -> float:
	if anim.rider == null: return 0.0
	var goal: Variant = builder.ride_start(state, anim.rider_from)
	if goal == null: return 0.0
	var placed := slot_transform(id)
	var ground := func(at: Vector2) -> bool: return approach_ground(id, placed * Vector3(at.x, 0, at.y))
	var hops := Approach.route(anim.rider_from, goal, _set.props[id].solids, WALK_CLEARANCE, ground, builder.ride_overhead(state))
	if hops.is_empty():
		anim.rider = null
		return 0.0
	anim.start = 0.0
	var time: float = anim.hop_steps(hops, 0.0, Approach.HOP_TIME, Approach.HOP_HEIGHT)
	anim.rider_from = hops[hops.size() - 1]
	return time

static func _rest_of(node: Node) -> Array:
	var shape := node as Node3D
	var look: Material = (node as MeshInstance3D).material_override if node is MeshInstance3D else null
	return [node, shape.transform if shape != null else Transform3D.IDENTITY, shape.visible if shape != null else true, look]

static func _restore(rest: Array) -> void:
	var node: Variant = rest[0]
	if not is_instance_valid(node): return
	if node is Node3D:
		(node as Node3D).transform = rest[1]
		(node as Node3D).visible = rest[2]
	if node is MeshInstance3D: (node as MeshInstance3D).material_override = rest[3]

static func _free_part(part: Variant) -> void:
	if not is_instance_valid(part): return
	var node := part as Node
	if node.get_parent() != null: node.get_parent().remove_child(node)
	node.queue_free()

## The beats are over: the pip lands, the tap's own parts go, and every moved
## part eases back to rest over SETTLE seconds (at once with Reduce motion);
## what the beats kept stays, and a kept spin starts turning now.
func _settle() -> void:
	if _play.is_empty() or _play.settling: return
	var anim: RefCounted = _play.anim
	_land(anim)
	if is_instance_valid(anim.fx):
		if anim.kept.is_empty(): anim.fx.visible = false
		else:
			for part: Variant in anim.spawned:
				if is_instance_valid(part) and part is Node3D and not anim.kept.has(part): (part as Node3D).visible = false
	var moved: Array = (_play.rest as Array).filter(func(rest: Array) -> bool: return is_instance_valid(rest[0]) and rest[0] is Node3D and not anim.kept.has(rest[0]) and (rest[0] as Node3D).transform != rest[1])
	if not anim.spins.is_empty():
		_play.spins = anim.spins
		_sync_spins()
		# Lights its answers from where the beam stands now (and for good under Reduce motion).
		Anim.advance_spins(anim.spins, 0.0)
	if anim.reduced or moved.is_empty():
		_end_play(true)
		return
	var tween := create_tween().set_parallel(true)
	for rest: Array in moved: tween.tween_property(rest[0], "transform", rest[1], Builder.SETTLE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_end_play.bind(true))
	_play.tween = tween
	_play.settling = true

## A ride's face stays this long after it lands, through its bounce.
const LANDED_FACE := 0.4

## Puts a carried pip down where its ride ends, out of any ride pose: its face
## stays through the bounce when it `landed`, and goes at once when the ride is
## cut off.
func _land(anim: RefCounted, landed: bool = false) -> void:
	if anim.landing != null and is_instance_valid(anim.rider):
		anim.rider.position = anim.landing
		if anim.rider.has_method("end_ride"): anim.rider.end_ride(LANDED_FACE if landed else 0.0)
	anim.landing = null

## Ends the tap: everything goes back to rest and its parts go, except, once
## its beats have all played (`finished`, or cut off while easing back), what
## they kept, which the keepsake holds.
func _end_play(finished: bool = false) -> void:
	if _play.is_empty(): return
	var anim: RefCounted = _play.anim
	if is_instance_valid(_play.tween): (_play.tween as Tween).kill()
	_land(anim)
	var keeping: Dictionary = anim.kept if finished or _play.settling else {}
	var held_rest: Array = []
	for rest: Array in _play.rest:
		if keeping.has(rest[0]): held_rest.append(rest)
		else: _restore(rest)
	var held_parts: Array[Node] = []
	for part: Variant in anim.spawned:
		if keeping.has(part) and is_instance_valid(part): held_parts.append(part)
		else: _free_part(part)
	if not keeping.is_empty(): _kept[str(_play.id)] = {"rest": held_rest, "spawned": held_parts, "fx": anim.fx, "made": anim.made, "spins": anim.spins}
	else: _free_part(anim.fx)
	_play = {}
	_sync_spins()

## Puts a held keepsake back to rest at once, its kept parts gone.
func _release(id: String) -> void:
	var held: Dictionary = _kept.get(id, {})
	if held.is_empty(): return
	_kept.erase(id)
	for rest: Array in held.rest: _restore(rest)
	for part: Variant in held.spawned: _free_part(part)
	_free_part(held.fx)
	_sync_spins()

func _sync_spins() -> void:
	_spins.clear()
	for id: String in _kept: _spins.append_array(_kept[id].spins)
	if not _play.is_empty(): _spins.append_array(_play.get("spins", []))

## Whether a keepsake holds what its last tap kept (a flower grown, a lamp on).
func holding(id: String) -> bool:
	return _kept.has(id)

## Whether a keepsake is on: holding what its tap keeps, or playing a tap
## that is not its switch off (a lamp waking counts as on).
func switched_on(id: String) -> bool:
	return holding(id) or (_play.get("id") == id and not _play.get("off", false))

## Turns what the keepsakes hold turning (a lighthouse left on) on by `step`
## seconds. Home's stage calls it each frame it runs (Home showing, in the
## foreground); nothing turns while a screen covers the 3D world, or under
## Reduce motion, where a held beam stands still. Nothing held: one check.
func advance_held(step: float) -> void:
	if _spins.is_empty() or _reduced() or get_viewport().disable_3d: return
	Anim.advance_spins(_spins, step)

## Ends a tap now, in its rest pose (a carried pip lands at its ride's end).
func stop_play() -> void:
	_end_play()

## Whether a keepsake is playing or easing back to rest.
func playing() -> bool:
	return not _play.is_empty()

## Whether a ride is carrying the pip: the stage leaves it to the ride.
func riding() -> bool:
	return not _play.is_empty() and not _play.settling and (_play.anim as RefCounted).landing != null

func _reduced() -> bool:
	return is_instance_valid(_world) and bool(_world.get("reduced_motion"))

# --- Explore --------------------------------------------------------------------------

## The pip took a step in Explore, from `from` to `to` (keepsakes/keepsake_explore.gd):
## it sets off what it walked into or through, and walks in, along and out of a
## stay. Called only for a step, so nothing here runs while the pip stands still.
func walked(from: Vector3, to: Vector3, walker: Node3D) -> void:
	steps += 1
	_explore.walked(from, to, walker)

## The pip left its stay: the keepsake is put back as it was.
func leave_stay() -> void:
	_explore.leave_stay()

## The stay the pip is in, or "".
func staying() -> String:
	return _explore.staying()

## How high the pip stands at `at`: a stay's floor (a raised house), else 0.
func ground_height(at: Vector3) -> float:
	return _explore.ground_height(at)

## Explore ended (or Home is closing): any ride lands, any stay is left, and
## nothing is half set off.
func end_explore() -> void:
	if riding(): stop_play()
	_explore.end()

# --- the card ---------------------------------------------------------------------------

## The selected keepsake for the card: its entry's words and its state.
func selected_item() -> Dictionary:
	if _shown.is_empty(): return {}
	var id := _shown[selected_index]
	var entry := _entry(id)
	var item: Dictionary = _items[id]
	return {"id": id, "name": entry.keepsake.copy.name, "line": Card.line(entry, item, together_hard), "look": item.look,
		"together": item.together, "hard": item.hard, "top": item.top, "has_together": entry.together, "has_hard": entry.hard,
		"top_offered": entry.hard and entry.together and (together_hard or item.top), "action": _action(entry.keepsake.copy, id), "playable": playable(id)}

## The Explore button's words: its words for while it is on, when it has them.
func _action(copy: Dictionary, id: String) -> String:
	return str(copy.held_action) if copy.has("held_action") and switched_on(id) else str(copy.action)

func count_line() -> String:
	return Card.count_line(_result)

## Every status line and the widest count line, to size the card once.
func every_line() -> Array[String]:
	return Card.every_line(_entries)

func widest_count() -> String:
	return Card.widest_count(_entries)

func select_offset(offset: int) -> void:
	if _shown.is_empty(): return
	selected_index = posmod(selected_index + offset, _shown.size())
	_show_selected()

func select_id(id: String) -> bool:
	var index := _shown.find(id)
	if index < 0: return false
	selected_index = index
	_show_selected()
	return true

func shown_ids() -> Array[String]:
	return _shown.duplicate()

## Every keepsake this Home can stand, shown now or not, in Home order.
func keepsake_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry: Dictionary in _entries: ids.append(str(entry.id))
	return ids

## The keepsake's holder in the set drawn now, or null.
func prop_node(id: String) -> Node3D:
	if not _set.get("props", {}).has(id): return null
	return (_set.root as Node3D).get_node_or_null(NodePath(_set.props[id].name)) as Node3D

## Every keepsake drawn now: {id: {"name", "parts", "state", "look", "solids", "overhead"}}.
func current_props() -> Dictionary:
	return _set.get("props", {})

## The moving parts of a keepsake drawn now.
func parts_of(id: String) -> Dictionary:
	return _set.get("props", {}).get(id, {}).get("parts", {})

func _first_unfinished() -> int:
	for index in range(_shown.size()):
		var item: Dictionary = _items[_shown[index]]
		if item.look != "keepsake": return index
	return 0

func _show_selected() -> void:
	if not is_instance_valid(_highlight): return
	_highlight.visible = not _shown.is_empty()
	if _shown.is_empty(): return
	_highlight.position = slot_transform(_shown[selected_index]).origin + Vector3(0, 0.04, 0)
	_highlight.scale = Vector3.ONE * HOME_SCALE

## Where the selected keepsake stands, in this layer's space (for the camera).
func selected_point() -> Vector3:
	return Vector3.ZERO if _shown.is_empty() else point_of(_shown[selected_index])

## A keepsake's middle, a little above its ground, in this layer's space.
func point_of(id: String) -> Vector3:
	var middle: Vector2 = _builders[id].footprint().get_center()
	return slot_transform(id) * Vector3(middle.x, 0.6, middle.y)

# --- picking, walking and the ground ------------------------------------------------------

## The nearest shown keepsake to a viewport point, or "" when none is in reach.
func pick(camera: Camera3D, point: Vector2, radius: float = PICK_RADIUS) -> String:
	var best := ""
	var best_distance := radius
	for id: String in _shown:
		var placed := slot_transform(id)
		var middle: Vector2 = _builders[id].footprint().get_center()
		for local: Vector3 in [Vector3(0, 0.45, 0), Vector3(0, 0.15, 0), Vector3(middle.x, 0.3, middle.y), Vector3(middle.x, 1.1, middle.y)]:
			var anchor := global_transform * (placed * local)
			if camera.is_position_behind(anchor): continue
			var distance := camera.unproject_position(anchor).distance_to(point)
			if distance <= best_distance:
				best = id
				best_distance = distance
	return best

## The shown keepsake whose ground is within `reach` metres of a point, or "".
func nearest(point: Vector3, reach: float) -> String:
	var best := ""
	var best_distance := INF
	for id: String in _shown:
		var gap := distance(id, point)
		if gap <= reach and gap < best_distance:
			best = id
			best_distance = gap
	return best

## Whether a spirit standing at `point`, `margin` metres round, would stand in
## a keepsake's solids or under its low parts (any but `under`'s own).
func blocks(point: Vector3, margin: float, under: String = "") -> bool:
	for id: String in _shown:
		if _solid_distance(id, point) < margin: return true
		if id == under: continue
		for rect: Rect2 in _overhead(id):
			if _rect_distance(rect, _local(id, point)) < margin: return true
	return false

## Whether a step from `from` to `to` takes a spirit nearer than `margin` to a
## keepsake's solids, or to the ground under one of its low parts, and nearer
## than it already was, so a spirit a keepsake appeared beside, or over, can
## always walk away from it. Each low part counts on its own, so a spirit
## under one still never walks into the solids (the rail's posts) beneath it.
## A gate counts as it stands for a spirit at `from`.
func blocks_step(from: Vector3, to: Vector3, margin: float) -> bool:
	for id: String in _shown:
		var after := _solid_distance(id, to, from)
		if after < margin and after < _solid_distance(id, from, from): return true
		for rect: Rect2 in _overhead(id):
			after = _rect_distance(rect, _local(id, to))
			if after < margin and after < _rect_distance(rect, _local(id, from)): return true
	return false

## The solids that keep a spirit from under a keepsake's low parts, in its frame.
func _overhead(id: String) -> Array:
	return _set.get("props", {}).get(id, {}).get("overhead", [])

## How far a point is outside a keepsake's ground (0 inside), in metres.
func distance(id: String, point: Vector3) -> float:
	return _rect_distance(_builders[id].footprint(), _local(id, point))

## How far a point is from a keepsake's nearest solid (0 inside one), its
## gates as they stand for a spirit at `at`.
func _solid_distance(id: String, point: Vector3, at: Vector3 = point) -> float:
	var local := _local(id, point)
	var best := INF
	for rect: Rect2 in _rects(id, at): best = minf(best, _rect_distance(rect, local))
	return best

## A keepsake's solids, and the gates it stands shut now for a spirit at `at`.
func _rects(id: String, at: Vector3) -> Array[Rect2]:
	var prop: Dictionary = _set.get("props", {}).get(id, {})
	if prop.is_empty(): return []
	var rects: Array[Rect2] = prop.solids
	if not _frames[id].gated: return rects
	var all := rects.duplicate()
	var keepsake: bool = prop.look == "keepsake"
	all.append_array(_builders[id].gates(prop.parts if keepsake else {}, prop.state if keepsake else {}, _local(id, at)))
	return all

func _local(id: String, point: Vector3) -> Vector2:
	var local: Vector3 = (_frames[id].inverse if _frames.has(id) else slot_transform(id).affine_inverse()) * Vector3(point.x, 0.0, point.z)
	return Vector2(local.x, local.z)

static func _rect_distance(area: Rect2, flat: Vector2) -> float:
	var inside := Vector2(clampf(flat.x, area.position.x, area.end.x), clampf(flat.y, area.position.y, area.end.y))
	return flat.distance_to(inside) * HOME_SCALE

## The ground a keepsake covers, in island metres: its footprint's corners.
func ground(id: String) -> PackedVector2Array:
	return _corners(slot_transform(id), _builders[id].footprint())

## The ground each of a keepsake's solids covers, in island metres.
func solid_grounds(id: String) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for rect: Rect2 in _set.get("props", {}).get(id, {}).get("solids", []): result.append(_corners(slot_transform(id), rect))
	return result

## Where a keepsake's trigger area or stay is, in island metres (its middle), or null.
func trigger_point(id: String) -> Variant:
	var trigger: Dictionary = _frames[id].trigger
	var area: Rect2 = trigger.get("area", _frames[id].stay)
	if not area.has_area(): return null
	return slot_transform(id) * Vector3(area.get_center().x, 0, area.get_center().y)

static func _corners(placed: Transform3D, area: Rect2) -> PackedVector2Array:
	var corners := PackedVector2Array()
	for corner: Vector2 in [area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)]:
		var at := placed * Vector3(corner.x, 0, corner.y)
		corners.append(Vector2(at.x, at.z))
	return corners

## The island floors, their middles and the bridges: the two Home islands and
## their lowering bridge from the level the world shows (its planks are the
## world's own, so its deck is read as drawn), and the isles a keepsake stands
## on (presentation/keepsakes/home_isles.gd), built here with their fixed
## plank bridges.
func _build_ground() -> void:
	var level: Dictionary = _world.current_level
	var bounds: Array = level.get("bounds", [-560, -290, 560, 290])
	var gap: Array = level.get("gap", [-100, 100])
	var bridge: Dictionary = level.get("bridge", {"z": 0, "width": 180})
	var left := Rect2(float(bounds[0]) / 100.0, float(bounds[1]) / 100.0, float(gap[0] - bounds[0]) / 100.0, float(bounds[3] - bounds[1]) / 100.0)
	var right := Rect2(float(gap[1]) / 100.0, float(bounds[1]) / 100.0, float(bounds[2] - gap[1]) / 100.0, float(bounds[3] - bounds[1]) / 100.0)
	var isles: Array = []
	for entry: Dictionary in _entries:
		var island := str(entry.keepsake.island)
		if Isles.is_isle(island) and not isles.has(island): isles.append(island)
	Isles.build(_world, _world.terrain, isles)
	_islands = {"left": left.get_center(), "right": right.get_center()}
	_floors = {"left": left.grow(-FLOOR_INSET), "right": right.grow(-FLOOR_INSET)}
	var isle_floors: Dictionary = Isles.floors(isles, FLOOR_INSET)
	for id: String in isle_floors:
		_floors[id] = isle_floors[id]
		_islands[id] = Isles.ISLES[id].center
	var start := Vector3(float(gap[0]) / 100.0, 0.0, float(bridge.get("z", 0)) / 100.0)
	var planks: Array = _world.bridge_parts if "bridge_parts" in _world else []
	var deck: float = _world.BRIDGE_RAISED_Y if "home_bridge_raised" in _world else -0.10
	_crossings.assign([{"inverse": Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), start).affine_inverse(),
		"half": float(bridge.get("width", 180)) / 200.0 - 0.2, "length": float(gap[1] - gap[0]) / 100.0, "planks": planks, "deck": deck, "fixed": false}])
	for ends: Array in Isles.bridges(isles):
		var from: Vector2 = ends[0]
		var to: Vector2 = ends[1]
		var toward := Vector3(to.x - from.x, 0, to.y - from.y)
		_crossings.append({"inverse": Transform3D(Basis.looking_at(toward, Vector3.UP), Vector3(from.x, 0, from.y)).affine_inverse(),
			"half": Isles.BRIDGE_WIDTH * 0.5 - 0.2, "length": toward.length(), "planks": [], "deck": 0.0, "fixed": true})

## An island's floor (inset from its edges) in island metres, by island id.
func island_floor(island: String) -> Rect2:
	return _floors.get(island, Rect2())

## The island ids this Home stands keepsakes on, and the isles built.
func island_ids() -> Array:
	return _floors.keys()

## The gold spirit's room round a keepsake in Explore.
const WALK_CLEARANCE := 0.12

## Whether `point` is within `reach` metres of a shown keepsake's trigger (its
## area or line) or stay, where the explorer sets one off: the other spirit
## roams clear of them in Explore.
func near_trigger(point: Vector3, reach: float) -> bool:
	for id: String in _shown:
		var frame: Dictionary = _frames[id]
		var local := _local(id, point)
		var trigger: Dictionary = frame.trigger
		if trigger.has("area") and _rect_distance(trigger.area, local) <= reach: return true
		if trigger.has("line") and local.distance_to(Geometry2D.get_closest_point_to_segment(local, trigger.line[0], trigger.line[1])) * HOME_SCALE <= reach: return true
		if (frame.stay as Rect2).has_area() and _rect_distance(frame.stay, local) <= reach: return true
	return false

## True where an Explore walk may stand: on an island, a crossing that carries
## the spirit or a keepsake's walkway, and not inside a keepsake or under its
## low parts.
func walkable(point: Vector3) -> bool:
	if blocks(point, WALK_CLEARANCE): return false
	return _ground(point)

## Where the hops round to `id`'s ride may go: walkable, or under its own low
## parts, which the way round (ride_approach.gd) keeps off itself once it has
## hopped a pip standing under them out.
func approach_ground(id: String, point: Vector3) -> bool:
	return not blocks(point, WALK_CLEARANCE, id) and _ground(point)

## An Explore step: onto ground, and never deeper into a keepsake.
func can_step(from: Vector3, to: Vector3) -> bool:
	return _ground(to) and not blocks_step(from, to, WALK_CLEARANCE)

## A slide steps this far off the face it runs along, so rounding never
## counts it as walking in.
const SLIDE_NUDGE := 0.0005

## A push this nearly straight into a face holds the pip still instead of
## sliding it (a fraction of the step left along the face).
const SLIDE_LEAST := 0.1

## Where an Explore step of `move` from `from` ends: straight on; else along
## the face of the solid in the way, in its keepsake's own turned frame, so a
## push into a turned keepsake runs the pip along it instead of stopping it;
## else along x or z (the island and bridge edges); else where it stands. A
## push into a shut gate (the house's door) opens it, as walking up to it does.
func step(from: Vector3, move: Vector3) -> Vector3:
	if can_step(from, from + move): return from + move
	_push_gate(from, from + move)
	var away := _away(from, from + move)
	if away != Vector3.ZERO and move.dot(away) < 0.0:
		var along := move - away * move.dot(away)
		if along.length() <= move.length() * SLIDE_LEAST: return from
		along += away * SLIDE_NUDGE
		if can_step(from, from + along): return from + along
	for part: Vector3 in [Vector3(move.x, 0, 0), Vector3(0, 0, move.z)]:
		if part != Vector3.ZERO and can_step(from, from + part): return from + part
	return from

## A step from `from` to `to` that a shut gate stops sets its keepsake off
## (the door swings open), while nothing else plays: a pip that waited at the
## door, or came while another keepsake played, is never left at it.
func _push_gate(from: Vector3, to: Vector3) -> void:
	if playing(): return
	for id: String in _shown:
		if not _frames[id].gated or not playable(id): continue
		var prop: Dictionary = _set.props[id]
		var local := _local(id, to)
		for rect: Rect2 in _builders[id].gates(prop.parts, prop.state, _local(id, from)):
			if _rect_distance(rect, local) < WALK_CLEARANCE:
				play(id)
				return

## The flat way out to `from` from the solid nearest `to` (its gates as they
## stand for a spirit at `from`), in island space; zero when none is within
## twice the walk clearance. Taken at `from`, where the pip touches it, so
## round a corner the slide follows the corner's curve and never cuts in.
func _away(from: Vector3, to: Vector3) -> Vector3:
	var best := WALK_CLEARANCE * 2.0
	var away := Vector3.ZERO
	for id: String in _shown:
		var local := _local(id, to)
		var here := _local(id, from)
		for rect: Rect2 in _rects(id, from) + _overhead(id):
			var gap := _rect_distance(rect, local)
			if gap <= 0.0 or gap >= best: continue
			var edge := Vector2(clampf(here.x, rect.position.x, rect.end.x), clampf(here.y, rect.position.y, rect.end.y))
			if here == edge: continue
			best = gap
			var out := (here - edge).normalized()
			away = (_frames[id].placed.basis * Vector3(out.x, 0, out.y)).normalized()
	return away

func _ground(point: Vector3) -> bool:
	var at := Vector2(point.x, point.z)
	for rect: Rect2 in _floors.values():
		if rect.has_point(at): return true
	for crossing: Dictionary in _crossings:
		if _carries(crossing, point): return true
	for id: String in _shown:
		var walkways: Array[Rect2] = _frames[id].walkways
		if walkways.is_empty(): continue
		var local := _local(id, point)
		for rect: Rect2 in walkways:
			if rect.has_point(local): return true
	return false

## How far along the crossing `point` is, or NAN when it is off to one side
## (beyond the half width grown by `reach`).
func _along(crossing: Dictionary, point: Vector3, reach: float) -> float:
	var local: Vector3 = crossing.inverse * point
	return -local.z if absf(local.x) <= float(crossing.half) + reach else NAN

func _carries(crossing: Dictionary, point: Vector3) -> bool:
	var along := _along(crossing, point, 0.0)
	var length: float = crossing.length
	if is_nan(along) or along < -CROSSING_PAD or along > length + CROSSING_PAD: return false
	if crossing.fixed or along <= 0.0 or along >= length: return true
	var planks: Array = crossing.planks
	if planks.is_empty(): return false
	var plank: Node3D = planks[mini(int(along / length * planks.size()), planks.size() - 1)]
	return is_instance_valid(plank) and plank.position.y >= float(crossing.deck) - DECK_TOLERANCE

## True while `point` is within `reach` of the Home bridge, so Explore should
## raise it. The isles' plank bridges never lower.
func near_lowering_crossing(point: Vector3, reach: float) -> bool:
	for crossing: Dictionary in _crossings:
		if crossing.fixed: continue
		var along := _along(crossing, point, reach)
		if not is_nan(along) and along >= -CROSSING_PAD - reach and along <= float(crossing.length) + CROSSING_PAD + reach: return true
	return false

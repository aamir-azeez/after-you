extends Node3D
## Home's keepsakes: one per card on the Chapters page, standing on the two
## Home islands (services/home_keepsake_states.gd decides what each shows; a
## chapter's descriptor names its builder, presentation/keepsakes/). A view of
## earned records, never an award source.
##
## The props carry no script: their geometry sits under one plain "Props" node
## that this layer folds into shared batches (kit/static_batch.gd), while the
## moving parts a builder returns stay their own nodes, held in _held. A change
## of state waits REBUILD_DELAY, so a burst of awards (the backfill, a cloud
## merge) rebuilds once; the new set is built unseen, folded a slice a frame and
## swapped in whole, so nothing flickers. A tap or an Explore press plays one
## keepsake: this layer owns the Tween, ignores a second tap while it plays,
## waits with any rebuild until it ends, and puts every part back in its rest
## pose. Leaving Home frees the layer, and the Tween with it.
const States = preload("res://services/home_keepsake_states.gd")
const Parts = preload("res://presentation/keepsakes/keepsake_parts.gd")
const Anim = preload("res://presentation/keepsakes/keepsake_anim.gd")
const Card = preload("res://presentation/keepsakes/keepsake_card.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
## Home draws each keepsake this many island metres per prop unit: the size
## at which five keepsakes with every upgrade stand on one island clear of each
## other, the trees and the spirits' start spots.
const HOME_SCALE := 1.0
## Every keepsake faces the Home camera (its +z along the camera's ground direction).
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

var _world: Node3D
var _free_only := false
var together_hard := false
## (cue: String) -> void: plays one keepsake beat's sound.
var cue: Callable
var _entries: Array = []
var _builders: Dictionary = {}
var _result: Dictionary = {}
var _items: Dictionary = {}
## Keepsakes shown now (keepsake, started or next), in Home order.
var _shown: Array[String] = []
var selected_index := 0
## The set drawn now and the one being built: {"root", "props": {id: {"name",
## "parts", "state"}}, "keys": {id: look key}}.
var _set: Dictionary = {}
var _next: Dictionary = {}
## Every moving part of both sets, so no fold ever takes them.
var _held: Array[Node] = []
var _fold: Dictionary = {}
var _rebuild_in := -1.0
## The tap playing now: {"id", "tween", "anim", "rest"}.
var _play: Dictionary = {}
var _highlight: MeshInstance3D
var _floors: Array[Rect2] = []
var _islands: Dictionary = {}
var _crossings: Array[Dictionary] = []
## Sets built since configure(), for tests that prove a burst rebuilds once.
var builds := 0

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

## Where a keepsake stands: its slot from its island's middle, facing the camera.
func slot_transform(id: String) -> Transform3D:
	var entry := _entry(id)
	var middle: Vector2 = _islands.get(str(entry.keepsake.island), Vector2.ZERO)
	var slot: Array = entry.keepsake.slot
	var yaw := atan2(CAMERA_FLAT.x, CAMERA_FLAT.z)
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * HOME_SCALE), Vector3(middle.x + float(slot[0]), 0.0, middle.y + float(slot[1])))

## The state a builder draws: the earned upgrades, and the Lantern Line's lanterns.
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
		for part: Variant in parts.values():
			if part is Node: _held.append(part)
		props[id] = {"name": holder.name, "parts": parts, "state": state, "look": item.look}
	builds += 1
	return {"root": root, "props": props, "keys": _keys()}

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
	_held.clear()
	for id: String in _set.props:
		for part: Variant in _set.props[id].parts.values():
			if part is Node: _held.append(part)

## Whether the set drawn now is still being built or folded.
func settling() -> bool:
	return not _next.is_empty() or not _fold.is_empty() or _rebuild_in >= 0.0

# --- taps ---------------------------------------------------------------------------

## Whether a keepsake can play now: drawn earned in the set on screen (a
## keepsake just earned plays once its rebuilt set is swapped in).
func playable(id: String) -> bool:
	return _set.get("props", {}).get(id, {}).get("look") == "keepsake"

## Plays a keepsake's tap. A second tap on the one playing changes nothing; a
## tap on another ends the first in its rest pose and plays the new one. False
## for a keepsake that is not drawn earned.
func play(id: String) -> bool:
	if not playable(id) or _play.get("id") == id: return false
	if not _play.is_empty(): _end_play()
	var prop: Dictionary = _set.props[id]
	var holder := (_set.root as Node3D).get_node_or_null(NodePath(prop.name)) as Node3D
	if holder == null: return false
	var builder: RefCounted = _builders[id]
	var state: Dictionary = prop.state.duplicate()
	state.sounds = _entry(id).keepsake.get("sounds", {})
	var anim := Anim.new()
	anim.cue = cue
	anim.reduced = _reduced()
	anim.fx = Node3D.new()
	anim.fx.name = "Tap"
	holder.add_child(anim.fx)
	var tween := create_tween().set_parallel(true)
	if not anim.reduced: anim.tween = tween
	var time := 0.0
	for beat: Dictionary in builder.beats(state):
		anim.start = time
		builder.play(str(beat.beat), anim, prop.parts, state)
		time += float(beat.time)
	var rest: Array = []
	for node: Variant in anim.touched:
		if is_instance_valid(node) and not anim.spawned.has(node): rest.append(_rest_of(node))
	if anim.reduced: anim.apply_jumps()
	tween.tween_interval(REDUCED_HOLD if anim.reduced else time)
	tween.finished.connect(_end_play)
	_play = {"id": id, "tween": tween, "anim": anim, "rest": rest}
	return true

static func _rest_of(node: Node) -> Array:
	var shape := node as Node3D
	var look: Material = (node as MeshInstance3D).material_override if node is MeshInstance3D else null
	return [node, shape.transform if shape != null else Transform3D.IDENTITY, shape.visible if shape != null else true, look]

func _end_play() -> void:
	if _play.is_empty(): return
	var anim: RefCounted = _play.anim
	if is_instance_valid(_play.tween): (_play.tween as Tween).kill()
	for rest: Array in _play.rest:
		var node: Variant = rest[0]
		if not is_instance_valid(node): continue
		if node is Node3D:
			(node as Node3D).transform = rest[1]
			(node as Node3D).visible = rest[2]
		if node is MeshInstance3D: (node as MeshInstance3D).material_override = rest[3]
	for part: Node in anim.spawned:
		if is_instance_valid(part): part.queue_free()
	if is_instance_valid(anim.fx): anim.fx.queue_free()
	_play = {}

## Ends a tap now, in its rest pose.
func stop_play() -> void:
	_end_play()

func playing() -> bool:
	return not _play.is_empty()

func _reduced() -> bool:
	return is_instance_valid(_world) and bool(_world.get("reduced_motion"))

# --- the card ---------------------------------------------------------------------------

## The selected keepsake for the card: its entry's words and its state.
func selected_item() -> Dictionary:
	if _shown.is_empty(): return {}
	var id := _shown[selected_index]
	var entry := _entry(id)
	var item: Dictionary = _items[id]
	return {"id": id, "name": entry.keepsake.copy.name, "line": Card.line(entry, item, together_hard), "look": item.look,
		"together": item.together, "hard": item.hard, "top": item.top, "has_together": entry.together, "has_hard": entry.hard,
		"top_offered": entry.hard and entry.together and (together_hard or item.top), "action": entry.keepsake.copy.action, "playable": playable(id)}

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

# --- picking, walking and the ground ------------------------------------------------------

## The nearest shown keepsake to a viewport point, or "" when none is in reach.
func pick(camera: Camera3D, point: Vector2, radius: float = PICK_RADIUS) -> String:
	var best := ""
	var best_distance := radius
	for id: String in _shown:
		var placed := slot_transform(id)
		for local: Vector3 in [Vector3(0, 0.45, 0), Vector3(0, 0.15, 0), Parts.BESIDE + Vector3(0, 0.25, 0)]:
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

## Whether a spirit standing at `point`, `margin` metres round, would stand in a keepsake.
func blocks(point: Vector3, margin: float) -> bool:
	for id: String in _shown:
		if distance(id, point) < margin: return true
	return false

## Whether a step from `from` to `to` takes a spirit nearer than `margin` to a
## keepsake and nearer than it already was, so a spirit a keepsake appeared
## beside can always walk away from it.
func blocks_step(from: Vector3, to: Vector3, margin: float) -> bool:
	for id: String in _shown:
		var after := distance(id, to)
		if after < margin and after < distance(id, from): return true
	return false

## How far a point is outside a keepsake's ground (0 inside), in metres.
func distance(id: String, point: Vector3) -> float:
	var local := slot_transform(id).affine_inverse() * Vector3(point.x, 0.0, point.z)
	var area: Rect2 = _builders[id].footprint()
	var flat := Vector2(local.x, local.z)
	var inside := Vector2(clampf(flat.x, area.position.x, area.end.x), clampf(flat.y, area.position.y, area.end.y))
	return flat.distance_to(inside) * HOME_SCALE

## The ground a keepsake covers, in island metres: its footprint's corners.
func ground(id: String) -> PackedVector2Array:
	var area: Rect2 = _builders[id].footprint()
	var placed := slot_transform(id)
	var corners := PackedVector2Array()
	for corner: Vector2 in [area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)]:
		var at := placed * Vector3(corner.x, 0, corner.y)
		corners.append(Vector2(at.x, at.z))
	return corners

## The Home island floors, their middles and the Home bridge, from the level
## the world shows. The bridge's planks are the world's own, so its deck is
## read as drawn.
func _build_ground() -> void:
	var level: Dictionary = _world.current_level
	var bounds: Array = level.get("bounds", [-560, -290, 560, 290])
	var gap: Array = level.get("gap", [-100, 100])
	var bridge: Dictionary = level.get("bridge", {"z": 0, "width": 180})
	var left := Rect2(float(bounds[0]) / 100.0, float(bounds[1]) / 100.0, float(gap[0] - bounds[0]) / 100.0, float(bounds[3] - bounds[1]) / 100.0)
	var right := Rect2(float(gap[1]) / 100.0, float(bounds[1]) / 100.0, float(bounds[2] - gap[1]) / 100.0, float(bounds[3] - bounds[1]) / 100.0)
	_islands = {"left": left.get_center(), "right": right.get_center()}
	_floors.assign([left.grow(-0.25), right.grow(-0.25)])
	var start := Vector3(float(gap[0]) / 100.0, 0.0, float(bridge.get("z", 0)) / 100.0)
	var planks: Array = _world.bridge_parts if "bridge_parts" in _world else []
	var deck: float = _world.BRIDGE_RAISED_Y if "home_bridge_raised" in _world else -0.10
	_crossings.assign([{"inverse": Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), start).affine_inverse(),
		"half": float(bridge.get("width", 180)) / 200.0 - 0.2, "length": float(gap[1] - gap[0]) / 100.0, "planks": planks, "deck": deck}])

## An island's floor (inset from its edges) in island metres: "left" or "right".
func island_floor(island: String) -> Rect2:
	return _floors[0 if island == "left" else 1]

## The gold spirit's room round a keepsake in Explore.
const WALK_CLEARANCE := 0.12

## True where an Explore walk may stand: on a Home island or a crossing that
## carries the spirit, and not inside a keepsake.
func walkable(point: Vector3) -> bool:
	if blocks(point, WALK_CLEARANCE): return false
	return _ground(point)

## An Explore step: onto ground, and never deeper into a keepsake.
func can_step(from: Vector3, to: Vector3) -> bool:
	return _ground(to) and not blocks_step(from, to, WALK_CLEARANCE)

func _ground(point: Vector3) -> bool:
	var at := Vector2(point.x, point.z)
	for rect: Rect2 in _floors:
		if rect.has_point(at): return true
	for crossing: Dictionary in _crossings:
		if _carries(crossing, point): return true
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
	if along <= 0.0 or along >= length: return true
	var planks: Array = crossing.planks
	if planks.is_empty(): return false
	var plank: Node3D = planks[mini(int(along / length * planks.size()), planks.size() - 1)]
	return is_instance_valid(plank) and plank.position.y >= float(crossing.deck) - DECK_TOLERANCE

## True while `point` is within `reach` of the Home bridge, so Explore should raise it.
func near_lowering_crossing(point: Vector3, reach: float) -> bool:
	for crossing: Dictionary in _crossings:
		var along := _along(crossing, point, reach)
		if not is_nan(along) and along >= -CROSSING_PAD - reach and along <= float(crossing.length) + CROSSING_PAD + reach: return true
	return false

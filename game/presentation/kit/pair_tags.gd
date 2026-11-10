extends RefCounted
## World kit: pair tags, the small lettered tiles that tie a control (a pad, a
## lever, a selector, a receiver) to each gate it works. The pairs come from
## the stage's own control-to-gate wiring (its gates' pad_id, lever_id,
## second_lever_id, ball_pad_id and `when` references): each wired control
## gets the next letter A to J and a muted colour, shown on a tile beside the
## control and again at every gate it works. A gate several controls work
## shows their tiles side by side in one short row; a control whose tile and
## gate tile would touch shows it once, and every row is placed on its own
## floor clear of the controls, the ownership marks, the decks and other rows,
## by the gate's entrance or, without room there, by its far end. A world overrides with skip() (a control or gate it shows some other
## way) and tag() (a tile on a sign it builds itself); it supplies the floor
## point of a control (_pair_control_anchor), of a gate's crossing's ends,
## the entrance first (_pair_gate_anchors) and anything else of its own a tile keeps clear of
## (_pair_keep_clear: discs {centre, radius} or {rect}, with an optional y).
##
## States, from the snapshot alone: faint (a soft wash of the colour and a
## whisper of the letter), clear while either spirit stands within NEAR_CM of
## the control on its floor, and glowing at both ends while the control is
## active (a lever on, a pad held, a selector or receiver while a gate it
## works is open with the selector at a value that gate asks of it). The world
## hands the stage over with prepare() and the tiles are laid out when first
## shown or read, after every world has built its own scenery.
## Past ten pairs the letters start again with an inner band on the tile (one
## band for K to T as A to J, two for the next ten), the colours repeating.
##
## Presentation only: built from the hashed stage and fed the snapshot;
## nothing here feeds the simulation, a recording or a checkpoint, so a replay
## shows what play showed. Cost: one mesh and one material per stage (a sign
## tile adds one small mesh); present() works out the states, a few distance
## checks, and sets the material only when they change. The letter meshes and
## the shader are made once a session and let go through SessionRelease.
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const OwnerMark = preload("res://presentation/kit/owner_mark.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const SHADER := preload("res://presentation/kit/pair_tags.gdshader")
## The game's rounded bold heading font.
const FONT := preload("res://assets/fonts/fredoka.ttf")
## A tile is TAG across; tiles keep GAP from each other and from what they avoid.
const TAG := 0.28
const GAP := 0.05
const RIM_WIDTH := 0.012
## Tags whose places are closer than this (same floor) join one row.
const CLUSTER := 0.34
## Every layer (rim, face, bands, letter) lies this far over the floor: 3 mm or
## more from the floor lines' tops (6 mm, kit/surfaces.gd) and a crossing's
## remembered footsteps (13.5 mm), under a spirit's ground shadow. The layers
## write no depth and draw in order, so they share the height.
const LIFT := 0.0095
## The letter's height on the tile, and an inner band's width past J.
const LETTER_HEIGHT := 0.15
const BAND := 0.012
const LETTERS := "ABCDEFGHIJ"
## Ten muted colours, each at least 20 (CIE76) from the others and from the
## owners' gold and teal (tests/test_pair_tags.gd measures it).
const PALETTE := [Color("c8806a"), Color("8fa87a"), Color("6f8fb0"), Color("c9a443"), Color("9c7aa3"), Color("4f8a8c"), Color("d99fac"), Color("7a7438"), Color("8a6a52"), Color("c2b6e6")]
const INK := Color("2f3534")
## The shader keeps a state for this many pairs; past MAX_PAIRS (three bands)
## a stage warns, and pairs from the last slot on share its state.
const MAX_STATES := 32
const MAX_PAIRS := 30
## A spirit this close (cm, across the floor) and this near in height (under a
## terrace's step) shows its pair.
const NEAR_CM := 120
const NEAR_HEIGHT_CM := 40
## A floor's edge trims and strips run this far in from its rectangle.
const FLOOR_INSET := 0.045
## Where a row may go from its place, nearest first: its place, then steps of
## STEP in eight directions, out to RINGS steps.
const STEP := 0.12
const RINGS := 10
## A control with no room on its own floor shows its tile on a floor this near.
const BESIDE := 1.0
## Which end of a pair a hand-placed tile marks.
const CONTROL := &"control"
const GATE := &"gate"
const SIGN := &"sign"
## Gate keys that name a control, besides a `when` tree.
const GATE_KEYS := ["pad_id", "lever_id", "second_lever_id", "ball_pad_id"]

## Letter meshes ([positions, triangles] lying flat, LETTER_HEIGHT tall, centred), by letter.
static var _letters: Dictionary = {}

var _world: Node3D
var _skips: Array = []
var _signs: Array = []
var _pairs: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
var _material: ShaderMaterial
var _node: MeshInstance3D
var _states := PackedVector2Array()
var _next := PackedVector2Array()
## The stage waiting to be laid out (prepare()), until it is first shown or read.
var _view: Dictionary = {}

func _init(world: Node3D = null) -> void:
	_world = world

## A new stage: its overrides, pairs and tiles start over (the nodes went with the terrain).
func clear() -> void:
	_skips.clear()
	_signs.clear()
	_pairs.clear()
	_rows.clear()
	_material = null
	_node = null
	_states = PackedVector2Array()
	_view = {}

## Leaves out control `control_id` (every gate when `gate_id` is ""), or every
## control of gate `gate_id` when `control_id` is "".
func skip(control_id: String, gate_id: String = "") -> void:
	_skips.append([control_id, gate_id])

## A tile the world places itself: on a sign it builds (side SIGN, `at` in
## `parent`'s space, lying in the parent's x and z).
func tag(control_id: String, side: StringName, at: Vector3, parent: Node3D) -> void:
	if side == SIGN: _signs.append({"control": control_id, "at": at, "parent": parent})

## The stage's pairs, from `view`'s wiring: {control, entity, kind (lever,
## pad or other), gates (route dictionaries), values (route id -> the values
## a gate needs of a selector, [] for any), index}, in the order the gates
## meet them.
static func pairs_of(view: Dictionary, skips: Array = []) -> Array[Dictionary]:
	var entities := _entities(view)
	var routes: Dictionary = {}
	for route: Dictionary in view.get("bridges", []) + view.get("stairs", []): routes[str(route.id)] = route
	var found: Array[Dictionary] = []
	var by_control: Dictionary = {}
	for gate: Dictionary in view.get("gates", []):
		var route_id := str(gate.get("route_id", ""))
		if not routes.has(route_id): continue
		for control: String in references(gate):
			if not entities.has(control) or _skipped(skips, control, route_id): continue
			if not by_control.has(control):
				by_control[control] = {"control": control, "entity": entities[control], "kind": _kind(view, control), "gates": [], "values": {}, "index": found.size()}
				found.append(by_control[control])
			if routes[route_id] not in by_control[control].gates: by_control[control].gates.append(routes[route_id])
			by_control[control].values[route_id] = _values(gate.get("when", {}), control)
	return found

## The controls a gate names: its GATE_KEYS and every reference in its `when` tree.
static func references(gate: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for key: String in GATE_KEYS:
		var id := str(gate.get(key, ""))
		if not id.is_empty() and id not in found: found.append(id)
	for id: String in predicate_references(gate.get("when", {})):
		if id not in found: found.append(id)
	return found

## The controls a `when` predicate reads, nested all and any included.
static func predicate_references(predicate: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for key: String in ["control_id", "signal_id", "pad_id", "lever_id"]:
		if predicate.has(key) and str(predicate[key]) not in found: found.append(str(predicate[key]))
	for key: String in ["all", "any"]:
		for child: Dictionary in predicate.get(key, []):
			for id: String in predicate_references(child):
				if id not in found: found.append(id)
	return found

## The values a `when` predicate asks of control `id` ([] when it asks none).
static func _values(predicate: Dictionary, id: String) -> Array:
	var found: Array = []
	if str(predicate.get("control_id", "")) == id and predicate.has("value"): found.append(str(predicate.value))
	for key: String in ["all", "any"]:
		for child: Dictionary in predicate.get(key, []):
			for value: String in _values(child, id):
				if value not in found: found.append(value)
	return found

## Pair `index`'s letter, band (0 for A to J, 1 for the next ten...) and colour.
static func letter_of(index: int) -> String:
	return LETTERS[index % LETTERS.length()]

static func band_of(index: int) -> int:
	return index / LETTERS.length()

static func colour_of(index: int) -> Color:
	return PALETTE[index % PALETTE.size()]

## Takes the stage to lay out once everything else on it is built: when it
## is first shown (present) or read (placed, states).
func prepare(view: Dictionary) -> void:
	_view = view

func _ensure_built() -> void:
	if _view.is_empty(): return
	var view := _view
	_view = {}
	build(view)

## Works out the stage's pairs, lays out their tiles and draws them under the
## world's terrain, now.
func build(view: Dictionary) -> void:
	_pairs = pairs_of(view, _skips)
	if _pairs.size() > MAX_PAIRS: push_warning("PairTags: %d pairs on one stage; past %d their tiles share a state and their bands crowd the letter" % [_pairs.size(), MAX_PAIRS])
	_rows = _layout(view)
	_states.resize(MAX_STATES)
	_states.fill(Vector2.ZERO)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	# Under the spirits' ground shadows, which are see-through too.
	_material.render_priority = -1
	_material.set_shader_parameter(&"states", _states)
	if not _rows.is_empty():
		_node = MeshInstance3D.new()
		_node.name = "PairTags"
		_node.mesh = _bake(_rows)
		_node.material_override = _material
		_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Measured row by row, like a folded batch: one mesh spanning floors at
		# several heights is still only flat tiles to code that looks for scenery.
		_node.set_meta(StaticBatch.PARTS_META, _rows.map(func(row: Dictionary) -> Array: return [Transform3D(Basis.IDENTITY, row.at), AABB(Vector3(-(row.rect as Rect2).size.x * 0.5, 0, -TAG * 0.5), Vector3((row.rect as Rect2).size.x, LIFT, TAG))]))
		_world.get("terrain").add_child(_node)
	for sign: Dictionary in _signs:
		var pair := _pair(str(sign.control))
		if pair.is_empty() or not is_instance_valid(sign.parent): continue
		var node := MeshInstance3D.new()
		node.name = "PairTagSign"
		node.mesh = _bake([{"at": sign.at, "pairs": [pair.index]}])
		node.material_override = _material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(sign.parent as Node3D).add_child(node)

## Every tile the stage shows: {control, letter, band, index, sides (CONTROL
## and or GATE), gates (route ids), at (terrain space, the floor under its
## centre), row (its row's rect across the floor), squeezed (no clear place)}.
func placed() -> Array[Dictionary]:
	_ensure_built()
	var found: Array[Dictionary] = []
	for row: Dictionary in _rows:
		for slot in range(row.pairs.size()):
			var index: int = row.pairs[slot]
			var pair: Dictionary = _pairs[index]
			found.append({"control": pair.control, "letter": letter_of(index), "band": band_of(index), "index": index, "sides": row.sides[index], "gates": row.gates[index], "at": _slot_at(row, slot), "row": row.rect, "squeezed": row.squeezed, "clash": row.clash})
	return found

## The overrides the world declared this stage: [control, gate] per skip().
func skips() -> Array:
	return _skips.duplicate(true)

## The pairs' states now: control -> {clear, lit}.
func states() -> Dictionary:
	_ensure_built()
	var found: Dictionary = {}
	for pair: Dictionary in _pairs:
		var state := _states[mini(pair.index, MAX_STATES - 1)] if not _states.is_empty() else Vector2.ZERO
		found[pair.control] = {"clear": state.x > 0.5, "lit": state.y > 0.5}
	return found

## Sets the tiles' states from snapshot `state`: clear while a spirit is near
## a pair's control, glowing while the control is active. The same snapshot
## always gives the same states, in play and in a replay.
func present(state: Dictionary) -> void:
	_ensure_built()
	if _pairs.is_empty() or _material == null: return
	if _next.size() != MAX_STATES: _next.resize(MAX_STATES)
	_next.fill(Vector2.ZERO)
	var players: Dictionary = state.get("players", {})
	for pair: Dictionary in _pairs:
		var slot := mini(int(pair.index), MAX_STATES - 1)
		var near := _spirit_near(pair, players)
		var lit := _active(pair, state)
		_next[slot] = Vector2(maxf(_next[slot].x, 1.0 if near or lit else 0.0), maxf(_next[slot].y, 1.0 if lit else 0.0))
	if _next == _states: return
	var shown := _states
	_states = _next
	_next = shown
	_material.set_shader_parameter(&"states", _states)

func _spirit_near(pair: Dictionary, players: Dictionary) -> bool:
	var at: Vector3 = pair.get("anchor", Vector3.INF)
	if not at.is_finite(): return false
	for slot: String in players:
		var player: Variant = players[slot]
		if not player is Dictionary or not player.has("x") or not player.has("z"): continue
		var across := Vector2(float(player.x) - at.x * 100.0, float(player.z) - at.z * 100.0).length()
		if across <= NEAR_CM and absf(float(player.get("height", at.y * 100.0)) - at.y * 100.0) <= NEAR_HEIGHT_CM: return true
	return false

func _active(pair: Dictionary, state: Dictionary) -> bool:
	var id := str(pair.control)
	match pair.kind:
		&"lever": return bool(state.get("levers", {}).get(id, false))
		&"pad": return bool(state.get("hold_pads", {}).get(id, false))
	# A selector or receiver is active while a gate it works stands open with
	# the selector at a value that gate asks of it.
	var open: Dictionary = state.get("bridges", {})
	var value := str(state.get("controls", {}).get(id, ""))
	for route: Dictionary in pair.gates:
		var asked: Array = pair.values.get(str(route.id), [])
		if bool(open.get(str(route.id), false)) and (asked.is_empty() or value in asked): return true
	return false

func _pair(control: String) -> Dictionary:
	for pair: Dictionary in _pairs:
		if pair.control == control: return pair
	return {}

static func _skipped(skips: Array, control: String, gate: String) -> bool:
	for entry: Array in skips:
		if (entry[0] == control or str(entry[0]).is_empty()) and (str(entry[1]).is_empty() or entry[1] == gate): return true
	return false

## How a control is worked: a lever, a pad (held), or anything else (a
## selector, a receiver) read through its gates.
static func _kind(view: Dictionary, id: String) -> StringName:
	for lever: Dictionary in view.get("levers", []):
		if str(lever.get("id", "")) == id: return &"lever" if str(lever.get("kind", "")) != "selector" else &"other"
	for pad: Dictionary in view.get("pressure_pads", []) + view.get("ball_pads", []):
		if str(pad.get("id", "")) == id: return &"pad"
	return &"other"

static func _is_receiver(view: Dictionary, id: String) -> bool:
	var receivers: Array = view.get("optics", {}).get("receivers", view.get("optical_field", {}).get("receivers", []))
	return receivers.any(func(receiver: Dictionary) -> bool: return str(receiver.get("id", "")) == id)

static func _entities(view: Dictionary) -> Dictionary:
	var found: Dictionary = {}
	var receivers: Array = view.get("optics", {}).get("receivers", view.get("optical_field", {}).get("receivers", []))
	for entity: Dictionary in view.get("pressure_pads", []) + view.get("ball_pads", []) + view.get("levers", []) + view.get("controls", []) + receivers:
		if entity.has("id") and entity.has("position_cm"): found[str(entity.id)] = entity
	return found

# --- Layout -----------------------------------------------------------------------

## Rows: {at (floor point of the row's centre), pairs (indices left to right),
## sides and gates per index, rect, squeezed, clash}.
func _layout(view: Dictionary) -> Array[Dictionary]:
	# Each place a tile belongs: beside its control, and at each gate it works.
	var places: Array[Dictionary] = []
	var floors := _floors(view)
	for pair: Dictionary in _pairs:
		var anchor: Vector3 = _world.call(&"_pair_control_anchor", pair.entity)
		pair["anchor"] = anchor
		# Beside the control on its floor, else on the nearest floor beside it
		# (a bucket hanging in a shaft shows its tile on the rim above).
		var ends: Array = [anchor]
		for f: Dictionary in floors:
			if f.crossing or absf(float(f.y) - anchor.y) < 0.06: continue
			var rect: Rect2 = f.rect
			var nearest := Vector2(clampf(anchor.x, rect.position.x, rect.end.x), clampf(anchor.z, rect.position.y, rect.end.y))
			if nearest.distance_to(_flat(anchor)) <= BESIDE: ends.append(Vector3(nearest.x, float(f.y), nearest.y))
		places.append({"kind": CONTROL, "at": anchor, "ends": ends, "pairs": [pair.index], "sides": {pair.index: [CONTROL]}, "gates": {pair.index: []}, "surfaces": []})
	for pair: Dictionary in _pairs:
		for route: Dictionary in pair.gates:
			var ends: Array = _world.call(&"_pair_gate_anchors", route)
			if ends.is_empty(): continue
			var joined := false
			for place: Dictionary in places:
				if place.kind == GATE and (place.at as Vector3).is_equal_approx(ends[0]):
					_join(place, pair.index, GATE, str(route.id))
					joined = true
			# A gate's tiles lie on the floors its crossing joins, by its entrance
			# or, where that has no room, by its far end.
			if not joined: places.append({"kind": GATE, "at": ends[0], "ends": ends, "pairs": [pair.index], "sides": {pair.index: [GATE]}, "gates": {pair.index: [str(route.id)]}, "surfaces": [str(route.get("from_surface", "")), str(route.get("to_surface", ""))]})
	# A pair whose control's place and gate's place would touch shows once,
	# in one row; other rows step apart as they are placed.
	var merged: Array[Dictionary] = []
	for place: Dictionary in places:
		var into: Dictionary = {}
		for row: Dictionary in merged:
			if absf((row.at as Vector3).y - (place.at as Vector3).y) < 0.06 and _flat(row.at).distance_to(_flat(place.at)) < CLUSTER and (row.pairs as Array).any(func(index: int) -> bool: return index in place.pairs): into = row
		if into.is_empty():
			merged.append(place)
			continue
		for index: int in place.pairs:
			for side: StringName in place.sides[index]: _join(into, index, side, "")
			for gate: String in place.gates[index]: _join(into, index, GATE, gate)
		into.surfaces.append_array(place.surfaces)
	var avoid := _avoid(view)
	var done: Array[Dictionary] = []
	for row: Dictionary in merged:
		row.pairs.sort()
		_place(row, floors, avoid, done)
		done.append(row)
	return done

func _join(place: Dictionary, index: int, side: StringName, gate: String) -> void:
	if index not in place.pairs:
		place.pairs.append(index)
		place.sides[index] = []
		place.gates[index] = []
	if side not in place.sides[index]: place.sides[index].append(side)
	if not gate.is_empty() and gate not in place.gates[index]: place.gates[index].append(gate)

## Puts `row` at the nearest spot to its place that lies on its floor and keeps
## GAP from everything in `avoid` and from the rows already placed.
func _place(row: Dictionary, floors: Array, avoid: Array, done: Array[Dictionary]) -> void:
	var width := _width(row.pairs.size())
	var best := {"cost": INF}
	var ends: Array = row.get("ends", [row.at])
	for end in range(ends.size()):
		var at: Vector3 = ends[end]
		# Only what lies within reach of this place can meet a row placed from it.
		var reach := width * 0.5 + TAG + STEP * float(RINGS) + 0.6
		var close := avoid.filter(func(thing: Dictionary) -> bool: return _near_place(thing, _flat(at), reach))
		var close_rows := done.filter(func(other: Dictionary) -> bool: return (other.rect as Rect2).grow(reach).has_point(_flat(at)))
		# Islands at its height, and a crossing only when its place is on it (a
		# stub its control stands on): a tile never lies on a crossing that may
		# not be there.
		var home := floors.filter(func(f: Dictionary) -> bool: return absf(float(f.y) - at.y) < 0.06 and (f.rect as Rect2).grow(reach).has_point(_flat(at)) and (not f.crossing or (row.kind == CONTROL and (f.rect as Rect2).grow(0.05).has_point(_flat(at)))))
		# A gate's row may also lie on either floor its crossing joins, at that floor's height.
		for id: String in row.surfaces:
			for f: Dictionary in floors:
				if f.id == id and not f.crossing and f not in home: home.append(f)
		for offset: Vector2 in _offsets():
			var centre := _flat(at) + offset
			var rect := Rect2(centre - Vector2(width, TAG) * 0.5, Vector2(width, TAG))
			var y := at.y
			for f: Dictionary in home:
				if (f.rect as Rect2).has_point(centre): y = float(f.y)
			var standing := home.filter(func(f: Dictionary) -> bool: return absf(float(f.y) - y) < 0.06)
			var clash := _clash(rect, y, standing, close, close_rows)
			var cost := float(clash.size()) * 100.0 + offset.length() + float(end) * 10.0
			if cost < float(best.cost): best = {"cost": cost, "centre": centre, "rect": rect, "clash": clash, "y": y}
			if clash.is_empty(): break
		if (best.clash as Array).is_empty(): break
	row.at = Vector3(best.centre.x, best.y, best.centre.y)
	row.rect = best.rect
	row.clash = best.clash
	row.squeezed = not (best.clash as Array).is_empty()

## What `rect` at height `y` runs into: its floor's edge, something to avoid
## (its own control too: a tile never covers its control), an earlier row.
func _clash(rect: Rect2, y: float, home: Array, avoid: Array, done: Array) -> Array:
	var found: Array = []
	var inside := not home.is_empty()
	for corner: Vector2 in [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)]:
		if not home.any(func(f: Dictionary) -> bool: return (f.rect as Rect2).grow(-FLOOR_INSET).has_point(corner)): inside = false
	if not inside: found.append("off its floor" if not home.is_empty() else "off its floor (no floor at %.2f m here)" % y)
	var wide := rect.grow(GAP)
	for thing: Dictionary in avoid:
		if thing.has("y") and absf(float(thing.y) - y) > 0.3: continue
		var hit := false
		if thing.has("rect"): hit = wide.intersects(thing.rect)
		else: hit = _disc_hits(wide, thing.centre, float(thing.radius))
		if hit: found.append(str(thing.what))
	for other: Dictionary in done:
		if absf((other.at as Vector3).y - y) < 0.3 and wide.intersects(other.rect): found.append("tags of " + ", ".join((other.pairs as Array).map(func(i: int) -> String: return str(_pairs[i].control))))
	return found

static func _near_place(thing: Dictionary, at: Vector2, reach: float) -> bool:
	if thing.has("rect"): return (thing.rect as Rect2).grow(reach).has_point(at)
	return (thing.centre as Vector2).distance_to(at) <= reach + float(thing.radius)

static func _disc_hits(rect: Rect2, centre: Vector2, radius: float) -> bool:
	var nearest := Vector2(clampf(centre.x, rect.position.x, rect.end.x), clampf(centre.y, rect.position.y, rect.end.y))
	return nearest.distance_to(centre) < radius

## The floors a tile may lie on: islands and crossings, at their heights.
static func _floors(view: Dictionary) -> Array:
	var found: Array = []
	for island: Dictionary in view.get("islands", []): found.append({"rect": _rect(island.rect_cm), "y": float(island.get("height_cm", 0)) / 100.0, "id": str(island.id), "crossing": false})
	for route: Dictionary in view.get("bridges", []): found.append({"rect": _rect(route.rect_cm), "y": float(route.get("height_cm", route.get("from_height_cm", 0))) / 100.0, "id": str(route.id), "crossing": true})
	return found

## What a tile keeps clear of: stairs, obstacles, drops, every control's
## disc, the goal, the handoff and every ownership mark.
func _avoid(view: Dictionary) -> Array:
	var found: Array = []
	var heights: Dictionary = {}
	for island: Dictionary in view.get("islands", []): heights[str(island.id)] = float(island.get("height_cm", 0)) / 100.0
	for stair: Dictionary in view.get("stairs", []): found.append({"rect": _rect(stair.rect_cm), "what": "stair " + str(stair.id)})
	for key: String in ["obstacles", "drops"]:
		for thing: Dictionary in view.get(key, []):
			var entry := {"rect": _rect(thing.rect_cm), "what": "%s %s" % [key.trim_suffix("s"), thing.get("id", "")]}
			if heights.has(str(thing.get("surface_id", ""))): entry["y"] = heights[str(thing.surface_id)]
			found.append(entry)
	for entity: Dictionary in _entities(view).values():
		var at: Vector3 = _world.call(&"_pair_control_anchor", entity)
		# A pad is its disc; a lever, selector or receiver its post.
		# A pad is its disc; a receiver its lamp and rosette; a lever or selector its post.
		var radius := 0.2
		match _kind(view, str(entity.id)):
			&"pad": radius = float(entity.get("radius_cm", 20)) / 100.0
			&"other": radius = 0.3 if _is_receiver(view, str(entity.id)) else 0.2
		found.append({"centre": _flat(at), "radius": radius, "y": at.y, "what": "control " + str(entity.id)})
	var goal: Dictionary = view.get("goal", {})
	if goal.has("position_cm"): found.append({"centre": Vector2(float(goal.position_cm[0]), float(goal.position_cm[1])) / 100.0, "radius": float(goal.get("radius_cm", 40)) / 100.0, "what": "the goal"})
	if view.get("handoff") is Dictionary and view.handoff.has("position_cm"): found.append({"centre": Vector2(float(view.handoff.position_cm[0]), float(view.handoff.position_cm[1])) / 100.0, "radius": 0.6 + OwnerMark.RING_RADIUS + 0.025, "what": "the handoff"})
	found.append_array(_world.call(&"_pair_keep_clear"))
	var marks: Variant = _world.get("owner_marks")
	if marks != null:
		for mark: Dictionary in marks.placed():
			found.append({"centre": _flat(mark.at), "radius": OwnerMark.REACH if mark.slot == "p0" else OwnerMark.RING_RADIUS + 0.025, "y": (mark.at as Vector3).y, "what": "%s mark %s" % [mark.kind, mark.id]})
	return found

static func _offsets() -> Array[Vector2]:
	var found: Array[Vector2] = [Vector2.ZERO]
	for ring in range(1, RINGS + 1):
		for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1, -1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			found.append(direction * STEP * float(ring))
	return found

static func _width(count: int) -> float:
	return float(count) * TAG + float(maxi(count - 1, 0)) * GAP

static func _slot_at(row: Dictionary, slot: int) -> Vector3:
	var count: int = row.pairs.size()
	return row.at + Vector3((float(slot) - float(count - 1) * 0.5) * (TAG + GAP), 0, 0)

static func _flat(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)

static func _rect(r: Array) -> Rect2:
	return Rect2(Vector2(float(r[0]), float(r[1])) / 100.0, Vector2(float(r[2] - r[0]), float(r[3] - r[1])) / 100.0)

# --- Drawing ------------------------------------------------------------------------

## One mesh for `rows`: per tile its rim, face, bands and letter, each vertex
## carrying its pair (UV2.x) and layer (UV2.y), drawn in that order.
func _bake(rows: Array) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	for row: Dictionary in rows:
		var count: int = row.pairs.size()
		for slot in range(count):
			var index: int = row.pairs[slot]
			var at: Vector3 = row.at + Vector3((float(slot) - float(count - 1) * 0.5) * (TAG + GAP), 0, 0)
			var colour := colour_of(index)
			_quad(tool, at + Vector3(0, LIFT, 0), Vector2(TAG, TAG), colour.darkened(0.35), index, 0.0)
			_quad(tool, at + Vector3(0, LIFT, 0), Vector2(TAG - RIM_WIDTH * 2.0, TAG - RIM_WIDTH * 2.0), colour, index, 1.0)
			for band in range(band_of(index)):
				var z := TAG * 0.5 - RIM_WIDTH - BAND * (float(band) * 2.0 + 1.5)
				_quad(tool, at + Vector3(0, LIFT, z), Vector2(TAG - RIM_WIDTH * 4.0, BAND), INK, index, 2.0)
			var letter: Array = _letter(letter_of(index))
			var positions: PackedVector3Array = letter[0]
			tool.set_color(INK)
			tool.set_uv2(Vector2(float(mini(index, MAX_STATES - 1)), 2.0))
			for vertex: int in letter[1]: tool.add_vertex(at + Vector3(0, LIFT, 0) + positions[vertex])
	return tool.commit()

static func _quad(tool: SurfaceTool, centre: Vector3, size: Vector2, colour: Color, index: int, layer: float) -> void:
	tool.set_color(colour)
	tool.set_uv2(Vector2(float(mini(index, MAX_STATES - 1)), layer))
	var half := size * 0.5
	var corners := [centre + Vector3(-half.x, 0, -half.y), centre + Vector3(half.x, 0, -half.y), centre + Vector3(half.x, 0, half.y), centre + Vector3(-half.x, 0, half.y)]
	for vertex: int in [0, 1, 2, 0, 2, 3]: tool.add_vertex(corners[vertex])

## A letter lying flat, LETTER_HEIGHT tall and centred: [positions, triangle indices].
static func _letter(letter: String) -> Array:
	if _letters.has(letter): return _letters[letter]
	SessionRelease.on_exit(release_cached)
	var text := TextMesh.new()
	text.font = FONT
	text.text = letter
	text.font_size = 64
	text.pixel_size = 0.01
	text.depth = 0.0
	text.curve_step = 1.0
	var arrays := text.get_mesh_arrays()
	var raw: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays.size() > Mesh.ARRAY_NORMAL and arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var triangles: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if triangles.is_empty():
		for vertex in range(raw.size()): triangles.append(vertex)
	# Front faces only, turned to lie flat facing up, the letter's top away from the camera.
	var kept := PackedInt32Array()
	for corner in range(0, triangles.size(), 3):
		if normals.is_empty() or normals[triangles[corner]].z > 0.5: kept.append_array([triangles[corner], triangles[corner + 1], triangles[corner + 2]])
	var low := Vector2.INF
	var high := -Vector2.INF
	for vertex: Vector3 in raw:
		low = low.min(Vector2(vertex.x, vertex.y))
		high = high.max(Vector2(vertex.x, vertex.y))
	var scale := LETTER_HEIGHT / maxf(high.y - low.y, 0.0001)
	var middle := (low + high) * 0.5
	var flat := PackedVector3Array()
	for vertex: Vector3 in raw: flat.append(Vector3((vertex.x - middle.x) * scale, 0, -(vertex.y - middle.y) * scale))
	_letters[letter] = [flat, kept]
	return _letters[letter]

## Lets go of the letter meshes (SessionRelease at exit; tests).
static func release_cached() -> void:
	_letters.clear()

## How many letters are cached (tests).
static func cached_letters() -> int:
	return _letters.size()

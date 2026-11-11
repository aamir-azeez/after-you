extends RefCounted
## A chapter's floors and crossings as a graph, built from the real Navigation:
## surfaces (islands, bridges, stairs), and per slot the edges a walker can
## step along. Shared by the level checker (tests/test_level_checker.gd), the
## flat map plan (tests/level_tools/map_plan.gd) and Turn of the Tide's own
## graph (tests/turn_of_the_tide_graph.gd, which adds its phases and explorer).
##
## Edges: a walker of one slot can step from surface a onto surface b. Each is
## found by walking 1 cm at a time with Navigation.at across the place where
## the two meet, with only a and b open as routes (islands always support), so
## an edge needs exactly the routes among {a, b}. Drops are probed separately
## with their lever on and become one-way edges that need that lever.
##
## Reach (reach()): which floors each pip could stand on during one stage, an
## over-approximation found as a fixed point. A crossing counts as open once
## its gate could hold with what the pips can already reach: a selector at any
## value once its owner reaches it (else its start value), a lever on once its
## owner reaches it, a pad held once its owner reaches it, a beam signal or a
## ball pad always. Gates are judged by the engine's own rule for the family:
## a journey gate's `when` tree through Seven.predicate, a cooperative gate's
## lever, pad and ball keys all at once (an empty gate always holds). So a
## floor this finds no way to is a floor no real play can reach.
const Navigation = preload("res://core/cooperative/navigation.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const RADIUS := 12
const WALK := 28
const LATERAL_STEP := 8

var level: Dictionary
var surfaces: Array = []          # [{id, rect, kind, height|stair}]
var index: Dictionary = {}        # id -> surface index
var route_bit: Dictionary = {}    # route id -> bit
var edges: Dictionary = {}        # slot -> Array (per surface) of [to, required bits, lever id]
var pairs: Dictionary = {}        # slot -> {"a>b": [bits, lever]}
var reverse: Dictionary = {}      # slot -> Array (per surface) of [from, required bits, lever]

func _init(definition: Dictionary) -> void:
	level = definition
	for island: Dictionary in level.islands: _add(island, "island")
	for bridge: Dictionary in level.get("bridges", []): _add(bridge, "bridge")
	for stair: Dictionary in level.get("stairs", []): _add(stair, "stair")

func _add(item: Dictionary, kind: String) -> void:
	index[item.id] = surfaces.size()
	surfaces.append({"id": item.id, "rect": item.rect_cm, "kind": kind, "item": item})
	if kind != "island": route_bit[item.id] = 1 << route_bit.size()

func id_of(surface: int) -> String:
	return surfaces[surface].id

func bits_of(routes: Array) -> int:
	var mask := 0
	for id: Variant in routes:
		if route_bit.has(str(id)): mask |= int(route_bit[str(id)])
	return mask

func routes_of(mask: int) -> Array:
	var result: Array = []
	for id: String in route_bit:
		if mask & int(route_bit[id]): result.append(id)
	return result

func height_at(surface: int, x: int, z: int) -> int:
	var item: Dictionary = surfaces[surface].item
	if surfaces[surface].kind == "stair": return Navigation.stair_height(item, Vector2i(x, z))
	return int(item.height_cm)

func owns(surface: int, slot: String) -> bool:
	return surfaces[surface].kind == "island" or Navigation._owns(surfaces[surface].item, slot)

# ---------------------------------------------------------------- edges

## Build the slot's edges. `open_all` probes with every route open instead,
## to show that no edge depends on a third route.
func build(slot: String, open_all: bool = false) -> Dictionary:
	var found: Dictionary = {}
	var all_routes: Dictionary = {}
	for id: String in route_bit: all_routes[id] = true
	for a in range(surfaces.size()):
		if not owns(a, slot): continue
		for b in range(surfaces.size()):
			if a == b or not owns(b, slot) or not _close(surfaces[a].rect, surfaces[b].rect, 2 * RADIUS + 2): continue
			var routes: Dictionary = all_routes if open_all else {}
			if not open_all:
				for s: int in [a, b]:
					if route_bit.has(id_of(s)): routes[id_of(s)] = true
			if _probe(a, b, slot, routes, {}):
				found["%s>%s" % [id_of(a), id_of(b)]] = [bits_of([id_of(a), id_of(b)]), ""]
	for drop: Dictionary in level.get("drops", []):
		var lever := str(drop.get("requires_lever", ""))
		var levers := {lever: true} if not lever.is_empty() else {}
		var from := int(index[drop.surface_id])
		var to := int(index[drop.destination_surface])
		if _probe_drop(drop, from, to, slot, all_routes, levers):
			found["%s>%s" % [drop.surface_id, drop.destination_surface]] = [bits_of([drop.surface_id, drop.destination_surface]), lever]
	if not open_all:
		pairs[slot] = found
		var lists: Array = []
		for _s in range(surfaces.size()): lists.append([])
		for key: String in found:
			var ends := key.split(">")
			lists[int(index[ends[0]])].append([int(index[ends[1]]), int(found[key][0]), str(found[key][1])])
		edges[slot] = lists
		var back: Array = []
		for _s in range(surfaces.size()): back.append([])
		for from in range(lists.size()):
			for edge: Array in lists[from]: back[int(edge[0])].append([from, edge[1], edge[2]])
		reverse[slot] = back
	return found

func _close(a: Array, b: Array, gap: int) -> bool:
	return int(a[0]) - gap <= int(b[2]) and int(b[0]) - gap <= int(a[2]) and int(a[1]) - gap <= int(b[3]) and int(b[1]) - gap <= int(a[3])

## Walk across every place a can hand over to b, both at a's own edge and at
## b's edge where b starts inside a (overlapping islands hand over by order).
func _probe(a: int, b: int, slot: String, routes: Dictionary, levers: Dictionary) -> bool:
	var ra: Array = surfaces[a].rect
	var rb: Array = surfaces[b].rect
	for axis: int in [0, 1]:
		var other := 1 - axis
		var lo := maxi(int(ra[other]), int(rb[other])) + RADIUS
		var hi := mini(int(ra[other + 2]), int(rb[other + 2])) - RADIUS
		if lo > hi: continue
		for sign: int in [1, -1]:
			var crossings: Array = []
			if sign > 0: crossings = [int(ra[axis + 2]), int(rb[axis])]
			else: crossings = [int(ra[axis]), int(rb[axis + 2])]
			for t: int in crossings:
				# b must lie beyond the crossing and a before it.
				if sign > 0 and (int(rb[axis + 2]) <= t or int(ra[axis]) >= t): continue
				if sign < 0 and (int(rb[axis]) >= t or int(ra[axis + 2]) <= t): continue
				var lateral := lo
				while true:
					if _walk(a, b, slot, routes, levers, axis, sign, t, lateral): return true
					if lateral == hi: break
					lateral = mini(lateral + LATERAL_STEP, hi)
	return false

func _walk(a: int, b: int, slot: String, routes: Dictionary, levers: Dictionary, axis: int, sign: int, t: int, lateral: int) -> bool:
	var start := Vector2i.ZERO
	start[axis] = t - sign * (WALK / 2)
	start[1 - axis] = lateral
	if not Navigation.inside(start, surfaces[a].rect): return false
	var position := Navigation.at(level, routes, levers, {"height": height_at(a, start.x, start.y), "surface_id": id_of(a)}, start.x, start.y, slot, RADIUS)
	if position.is_empty() or position.surface_id != id_of(a): return false
	for step in range(1, WALK + 1):
		var next := start
		next[axis] += sign * step
		position = Navigation.at(level, routes, levers, position, next.x, next.y, slot, RADIUS)
		if position.is_empty(): return false
		if position.surface_id == id_of(b): return true
		if position.surface_id != id_of(a): return false
	return false

func _probe_drop(drop: Dictionary, from: int, to: int, slot: String, routes: Dictionary, levers: Dictionary) -> bool:
	var rect: Array = drop.rect_cm
	for axis: int in [0, 1]:
		for sign: int in [1, -1]:
			var t := int(rect[axis]) if sign > 0 else int(rect[axis + 2])
			var lateral := int(rect[1 - axis])
			while lateral <= int(rect[3 - axis]):
				var start := Vector2i.ZERO
				start[axis] = t - sign * (RADIUS + 2)
				start[1 - axis] = lateral
				var position := Navigation.at(level, routes, {}, {"height": height_at(from, start.x, start.y), "surface_id": id_of(from)}, start.x, start.y, slot, RADIUS)
				if not position.is_empty() and position.surface_id == id_of(from):
					for step in range(1, RADIUS + 4):
						var next := start
						next[axis] += sign * step
						position = Navigation.at(level, routes, levers, position, next.x, next.y, slot, RADIUS)
						if position.is_empty(): break
						if position.surface_id == id_of(to): return true
				lateral += LATERAL_STEP
	return false

# ---------------------------------------------------------------- reach

## Every floor a pip could stand on during `stage`, starting from
## `checkpoint` (its players and kept crossings), with `journey` choosing the
## engine's gate rule. Returns {"floors": {slot: {surface id: true}}, "open":
## {route id: true}, "settable": {id: [values] or true}}: the fixed point
## described at the top. Builds the slots' edges on first use.
func reach(stage: Dictionary, checkpoint: Dictionary, journey: bool) -> Dictionary:
	for slot: String in ["p0", "p1"]:
		if not edges.has(slot): build(slot)
	var mechanisms: Dictionary = checkpoint.get("mechanisms", {})
	var open: Dictionary = {}
	for id: Variant in mechanisms.get("latched_bridges", []): open[str(id)] = true
	var floors: Dictionary = {"p0": {}, "p1": {}}
	var settable: Dictionary = _settable(stage, mechanisms, floors)
	# Floors, what is settable and what is open only ever grow, so this ends.
	while true:
		var size := open.size()
		for slot: String in ["p0", "p1"]:
			var player: Dictionary = checkpoint.get("players", {}).get(slot, {})
			floors[slot] = _walkable_from(slot, str(player.get("surface_id", "")), open, settable)
		var before := JSON.stringify(settable)
		settable = _settable(stage, mechanisms, floors)
		for gate: Dictionary in stage.get("gates", []):
			var route := str(gate.get("route_id", ""))
			if open.has(route) or not route_bit.has(route): continue
			if gate_can_hold(gate, stage, settable, mechanisms, journey): open[route] = true
		if open.size() == size and JSON.stringify(settable) == before: break
	return {"floors": floors, "open": open, "settable": settable}

## Surfaces `slot` walks to from `start` with `open` routes; a drop needs its
## lever settable on.
func _walkable_from(slot: String, start: String, open: Dictionary, settable: Dictionary) -> Dictionary:
	var seen: Dictionary = {}
	if not index.has(start): return seen
	seen[start] = true
	var queue: Array = [int(index[start])]
	var head := 0
	while head < queue.size():
		var from: int = queue[head]
		head += 1
		for edge: Array in edges[slot][from]:
			var to: int = edge[0]
			if seen.has(id_of(to)): continue
			var passable := true
			for surface: int in [from, to]:
				if route_bit.has(id_of(surface)) and not open.has(id_of(surface)): passable = false
			if not passable: continue
			if not str(edge[2]).is_empty() and not settable.has(str(edge[2])): continue
			seen[id_of(to)] = true
			queue.append(to)
	return seen

## What the pips can set on this stage once they stand on `floors`: a
## selector's values (all of them once its owner reaches it), a lever or a pad
## (true once its owner reaches it). Unreached ones keep their start value.
func _settable(stage: Dictionary, mechanisms: Dictionary, floors: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	# Controls an earlier stage set and this one does not offer keep their value.
	var start_controls: Dictionary = mechanisms.get("controls", {})
	for id: Variant in start_controls: result[str(id)] = [str(start_controls[id])]
	for control: Dictionary in stage.get("controls", []):
		var reached: bool = floors.get(str(control.get("owner_slot", "")), {}).has(str(control.get("surface_id", "")))
		if reached and control.has("values"): result[control.id] = control.values.duplicate()
		else: result[control.id] = [str(mechanisms.get("controls", {}).get(control.id, control.get("initial", "")))]
	for kind: String in ["levers", "pressure_pads"]:
		for item: Dictionary in stage.get(kind, []):
			if floors.get(str(item.get("owner_slot", "")), {}).has(str(item.get("surface_id", ""))): result[item.id] = true
	var start_levers: Dictionary = mechanisms.get("levers", {})
	for lever: Variant in start_levers:
		if bool(start_levers[lever]): result[str(lever)] = true
	return result

## Whether `gate` holds now, by the engine's rule for the family: a journey
## gate's `when` tree (Seven.predicate), a cooperative gate's lever, pad and
## ball keys all at once (a ball pad counts as held here; the level tools
## never move the ball).
static func gate_holds(gate: Dictionary, stage: Dictionary, players: Dictionary, mechanisms: Dictionary, journey: bool) -> bool:
	if journey: return Seven.predicate(gate.get("when", {}), stage, players, mechanisms)
	for key: String in ["lever_id", "second_lever_id"]:
		var id := str(gate.get(key, ""))
		if not id.is_empty() and not bool(mechanisms.get("levers", {}).get(id, false)): return false
	var pad_id := str(gate.get("pad_id", ""))
	if not pad_id.is_empty():
		for pad: Dictionary in stage.get("pressure_pads", []):
			if pad.id == pad_id: return pad_held(pad, players, false)
		return false
	return true

## Whether `pad`'s owner stands on it: the journey engine also matches the
## pad's height (Seven.near); the cooperative one only its floor and reach.
static func pad_held(pad: Dictionary, players: Dictionary, journey: bool) -> bool:
	var player: Dictionary = players.get(str(pad.get("owner_slot", "")), {})
	if player.is_empty(): return false
	if journey: return Seven.near(player, pad)
	return str(player.get("surface_id", "")) == str(pad.surface_id) and Vector2i(int(player.x), int(player.z)).distance_squared_to(Vector2i(int(pad.position_cm[0]), int(pad.position_cm[1]))) <= int(pad.radius_cm) ** 2

## Whether `gate` could hold with what is settable, by the family's rule.
func gate_can_hold(gate: Dictionary, stage: Dictionary, settable: Dictionary, mechanisms: Dictionary, journey: bool) -> bool:
	if not journey:
		for key: String in ["lever_id", "second_lever_id", "pad_id"]:
			var id := str(gate.get(key, ""))
			if not id.is_empty() and not settable.has(id): return false
		# A ball pad holds once the ball is pushed there: always possible here.
		return true
	var when: Dictionary = gate.get("when", {})
	var references: Dictionary = {"controls": {}, "pads": {}, "signals": {}}
	_references(when, references)
	# Levers only ever count while on, so a settable one is simply on.
	var levers: Dictionary = mechanisms.get("levers", {}).duplicate()
	for lever: Dictionary in stage.get("levers", []):
		if settable.has(lever.id): levers[lever.id] = true
	var signals: Dictionary = {}
	for id: String in references.signals: signals[id] = true
	var choices: Array = []
	for id: String in references.controls:
		var values: Variant = settable.get(id, [""])
		choices.append([id, values if values is Array else [""]])
	var pads: Array = references.pads.keys().filter(func(id: String) -> bool: return settable.has(id))
	return _any_assignment(when, stage, choices, 0, {}, levers, signals, _pad_placings(stage, pads))

func _references(value: Dictionary, found: Dictionary) -> void:
	for key: String in ["all", "any"]:
		for child: Dictionary in value.get(key, []): _references(child, found)
	if value.has("control_id"): found.controls[str(value.control_id)] = true
	if value.has("pad_id"): found.pads[str(value.pad_id)] = true
	if value.has("signal_id"): found.signals[str(value.signal_id)] = true

## Tries every value of each referenced control, with the pips on each
## placing of the settable pads, through the engine's own predicate.
func _any_assignment(when: Dictionary, stage: Dictionary, choices: Array, at: int, controls: Dictionary, levers: Dictionary, signals: Dictionary, placings: Array) -> bool:
	if at < choices.size():
		for value: Variant in choices[at][1]:
			controls[choices[at][0]] = str(value)
			if _any_assignment(when, stage, choices, at + 1, controls, levers, signals, placings): return true
		return false
	var mechanisms := {"controls": controls, "levers": levers}
	for placing: Dictionary in placings:
		if Seven.predicate(when, stage, placing, mechanisms, signals): return true
	return false

## Each way of standing the pips on the settable pads (at most one pad each).
func _pad_placings(stage: Dictionary, pads: Array) -> Array:
	var away := {"x": 1000000, "z": 1000000, "height": -100000, "surface_id": ""}
	var by_slot: Dictionary = {"p0": [away], "p1": [away]}
	for pad: Dictionary in stage.get("pressure_pads", []):
		if pad.id in pads and by_slot.has(str(pad.owner_slot)):
			by_slot[str(pad.owner_slot)].append({"x": pad.position_cm[0], "z": pad.position_cm[1], "height": int(pad.get("height_cm", 0)), "surface_id": pad.surface_id})
	var result: Array = []
	for p0: Dictionary in by_slot.p0:
		for p1: Dictionary in by_slot.p1: result.append({"p0": p0, "p1": p1})
	return result

## Whether `slot` can stand within `entity`'s radius on its surface with
## `open` routes: the engine's own walker test at the centre and at points
## round the circle (a control's floor may be a narrow catwalk end).
func can_stand_at(entity: Dictionary, slot: String, open: Dictionary) -> bool:
	var surface := str(entity.get("surface_id", ""))
	if not index.has(surface): return false
	var radius := maxi(0, int(entity.get("radius_cm", 28)) - 2)
	var at := Vector2i(int(entity.position_cm[0]), int(entity.position_cm[1]))
	var spots: Array[Vector2i] = [at]
	for turn in range(8):
		var offset := Vector2.from_angle(TAU * float(turn) / 8.0) * float(radius)
		spots.append(at + Vector2i(roundi(offset.x), roundi(offset.y)))
	for spot: Vector2i in spots:
		var height := height_at(int(index[surface]), spot.x, spot.y)
		var found := Navigation.at(level, open, {}, {"height": height, "surface_id": surface}, spot.x, spot.y, slot, RADIUS, false)
		if not found.is_empty() and str(found.surface_id) == surface: return true
	return false

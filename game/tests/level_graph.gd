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
## On open controls (core/physical/runtime.gd OPEN_RULES_VERSION) a control,
## lever or pad has no owner: it is settable once either pip reaches its
## floor, and a pad may be held by either pip.
##
## A frozen pip (reach's `frozen`): the memory doing nothing. It stays where
## it starts, works no control or lever, and holds only a pad it starts on.
## The probe also lights beams exactly: each settable mirror at each of its
## values through the engine's own BeamField, where reach otherwise counts a
## beam signal as always lit.
##
## A walking pip (reach's `walker`): the other pip works every control, lever
## and pad while this one only walks. The walker goes wherever the crossings
## open, but works nothing and stands on no pad. The presser cannot hold a pad
## and walk a crossing that pad opens at the same time, so for its own walking
## a gate counts only the pads within a step of that crossing (where standing
## on the pad could already put it on the crossing); for the walker every pad
## the presser reaches counts. Beams are lit exactly, as for a frozen pip.
##
## The new pieces (rules 16, core/physical/pieces_rules.gd): a gate may hold
## while a lever is off ("not"), so a settable lever a gate reads is tried
## both ways, and a pad both held and not (as before). A moving platform's
## stops are joined by ride edges, each needing both stops: a pip on one stop
## rides to every other. A one way stair's direction comes from Navigation.
const Navigation = preload("res://core/cooperative/navigation.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const BeamField = preload("res://core/beam_field.gd")
const CarriedItems = preload("res://core/physical/carried_items.gd")
const RADIUS := 12
const WALK := 28
const LATERAL_STEP := 8
## A choice in gate_can_hold that sets a lever rather than a control.
const LEVER_CHOICE := "lever:"

var level: Dictionary
var surfaces: Array = []          # [{id, rect, kind, height|stair}]
var index: Dictionary = {}        # id -> surface index
var route_bit: Dictionary = {}    # route id -> bit
var edges: Dictionary = {}        # slot -> Array (per surface) of [to, required bits, lever id]
var pairs: Dictionary = {}        # slot -> {"a>b": [bits, lever]}
var reverse: Dictionary = {}      # slot -> Array (per surface) of [from, required bits, lever]
var open_controls := false        # the definition pins open controls
var _frozen: Dictionary = {}      # reach's frozen pip: {"slot", "at": player} or {}
var _walker := ""                 # reach's walking pip, or ""
var _beside := ""                 # while judging a gate for the presser's own walking: its route

func _init(definition: Dictionary) -> void:
	level = definition
	open_controls = OpenControls.pinned(definition)
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
	# Rules 16: riding a moving platform from any of its stops to any other.
	for stage: Dictionary in level.get("stages", []):
		for platform: Dictionary in stage.get("platforms", []):
			for from: Variant in platform.get("stops", []):
				for to: Variant in platform.get("stops", []):
					if from != to and index.has(str(from)) and index.has(str(to)): found["%s>%s" % [from, to]] = [bits_of([str(from), str(to)]), ""]
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
## With `walker`, that pip only walks and the other works everything (top);
## the result's "own" holds the routes open for the presser's own walking.
func reach(stage: Dictionary, checkpoint: Dictionary, journey: bool, frozen: String = "", walker: String = "") -> Dictionary:
	for slot: String in ["p0", "p1"]:
		if not edges.has(slot): build(slot)
	var mechanisms: Dictionary = checkpoint.get("mechanisms", {})
	_frozen = {} if frozen.is_empty() else {"slot": frozen, "at": checkpoint.get("players", {}).get(frozen, {})}
	_walker = walker
	var open: Dictionary = {}
	for id: Variant in mechanisms.get("latched_bridges", []): open[str(id)] = true
	var own: Dictionary = open.duplicate()
	var floors: Dictionary = {"p0": {}, "p1": {}}
	var settable: Dictionary = _settable(stage, mechanisms, floors)
	# Floors, what is settable and what is open only ever grow, so this ends.
	while true:
		var size := open.size() + own.size()
		for slot: String in ["p0", "p1"]:
			var player: Dictionary = checkpoint.get("players", {}).get(slot, {})
			var start := str(player.get("surface_id", ""))
			var routes := own if not walker.is_empty() and slot != walker else open
			floors[slot] = {start: true} if slot == frozen else _walkable_from(slot, start, routes, settable)
		var before := JSON.stringify(settable)
		settable = _settable(stage, mechanisms, floors)
		_reach_items(stage, checkpoint, floors, open, settable)
		for gate: Dictionary in stage.get("gates", []):
			var route := str(gate.get("route_id", ""))
			if not route_bit.has(route): continue
			if not open.has(route) and gate_can_hold(with_items(gate, settable), stage, settable, mechanisms, journey, floors): open[route] = true
			if walker.is_empty() or own.has(route) or not open.has(route): continue
			_beside = route
			if gate_can_hold(with_items(gate, settable), stage, settable, mechanisms, journey, floors): own[route] = true
			_beside = ""
		if open.size() + own.size() == size and JSON.stringify(settable) == before: break
	return {"floors": floors, "open": open, "settable": settable, "own": own if not walker.is_empty() else open}

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
		var reached := _reached(control, floors)
		if reached and control.has("values"): result[control.id] = control.values.duplicate()
		else: result[control.id] = [str(mechanisms.get("controls", {}).get(control.id, control.get("initial", "")))]
	for kind: String in ["levers", "pressure_pads"]:
		for item: Dictionary in stage.get(kind, []):
			if _reached(item, floors): result[item.id] = true
	var start_levers: Dictionary = mechanisms.get("levers", {})
	for lever: Variant in start_levers:
		if bool(start_levers[lever]): result[str(lever)] = true
	return result

## Whether the pip that may work `item` reaches its floor: its owner, or on
## open controls either pip.
func _reached(item: Dictionary, floors: Dictionary) -> bool:
	var surface := str(item.get("surface_id", ""))
	for still: String in ([_frozen.slot] if not _frozen.is_empty() else []) + ([_walker] if not _walker.is_empty() else []):
		floors = floors.duplicate()
		floors[still] = {}
	if not open_controls: return floors.get(str(item.get("owner_slot", "")), {}).has(surface)
	return floors.get("p0", {}).has(surface) or floors.get("p1", {}).has(surface)

## Whether `gate` could hold with what is settable, by the family's rule.
## `floors` places pads by who reaches them (open controls); {} lets each
## settable pad be held by its owner, as before.
func gate_can_hold(gate: Dictionary, stage: Dictionary, settable: Dictionary, mechanisms: Dictionary, journey: bool, floors: Dictionary = {}) -> bool:
	if not journey:
		for key: String in ["lever_id", "second_lever_id", "pad_id"]:
			var id := str(gate.get(key, ""))
			if not id.is_empty() and not settable.has(id): return false
		# A ball pad holds once the ball is pushed there: always possible here.
		return true
	var when: Dictionary = gate.get("when", {})
	var references: Dictionary = {"controls": {}, "pads": {}, "signals": {}, "levers": {}}
	_references(when, references)
	# A settable lever is simply on, unless a gate holds only while one is off
	# (rules 16's "not"): then each settable lever it reads is tried both ways.
	var levers: Dictionary = mechanisms.get("levers", {}).duplicate()
	var negated := _negates(when)
	for lever: Dictionary in stage.get("levers", []):
		if settable.has(lever.id) and not (negated and references.levers.has(str(lever.id))): levers[lever.id] = true
	var signals: Dictionary = {}
	for id: String in references.signals: signals[id] = true
	var choices: Array = []
	# The frozen probe lights beams exactly, so every settable mirror is a choice.
	var exact: bool = _exact_beams() and stage.has("optical_field") and not references.signals.is_empty()
	if exact:
		for control: Dictionary in stage.get("controls", []):
			if str(control.get("kind", "")) == "mirror" and not references.controls.has(str(control.id)): references.controls[str(control.id)] = true
	for id: String in references.controls:
		var values: Variant = settable.get(id, [""])
		choices.append([id, values if values is Array else [""]])
	if negated:
		for id: String in references.levers:
			if settable.has(id): choices.append([LEVER_CHOICE + id, [true, false]])
	var pads: Array = references.pads.keys().filter(func(id: String) -> bool: return settable.has(id))
	return _any_assignment(when, stage, choices, 0, {}, levers, signals, _pad_placings(stage, pads, floors))

func _references(value: Dictionary, found: Dictionary) -> void:
	for key: String in ["all", "any"]:
		for child: Dictionary in value.get(key, []): _references(child, found)
	if value.get("not") is Dictionary: _references(value["not"], found)
	if value.has("lever_id") and found.has("levers"): found.levers[str(value.lever_id)] = true
	if value.has("control_id"): found.controls[str(value.control_id)] = true
	if value.has("pad_id"): found.pads[str(value.pad_id)] = true
	if value.has("signal_id"): found.signals[str(value.signal_id)] = true

## Tries every value of each referenced control, with the pips on each
## placing of the settable pads, through the engine's own predicate.
func _any_assignment(when: Dictionary, stage: Dictionary, choices: Array, at: int, controls: Dictionary, levers: Dictionary, signals: Dictionary, placings: Array) -> bool:
	if at < choices.size():
		var id := str(choices[at][0])
		for value: Variant in choices[at][1]:
			if id.begins_with(LEVER_CHOICE): levers[id.trim_prefix(LEVER_CHOICE)] = value
			else: controls[id] = str(value)
			if _any_assignment(when, stage, choices, at + 1, controls, levers, signals, placings): return true
		return false
	var mechanisms := {"controls": controls, "levers": levers}
	if _exact_beams() and stage.has("optical_field") and not signals.is_empty():
		var overrides: Dictionary = {}
		for control: Dictionary in stage.get("controls", []):
			if str(control.get("kind", "")) == "mirror": overrides[control.id] = {"orientation": str(controls.get(str(control.id), control.get("initial", "")))}
		var lit: Dictionary = BeamField.evaluate(stage.optical_field, overrides).get("signals", {})
		signals = {}
		for id: Variant in lit: signals[id] = bool(lit[id])
	for placing: Dictionary in placings:
		if Seven.predicate(when, stage, placing, mechanisms, signals, open_controls): return true
	return false

## Each way of standing the pips on the settable pads (at most one pad each):
## its owner's, or on open controls any pip that reaches its floor.
func _pad_placings(stage: Dictionary, pads: Array, floors: Dictionary = {}) -> Array:
	var away := {"x": 1000000, "z": 1000000, "height": -100000, "surface_id": ""}
	var by_slot: Dictionary = {"p0": [away], "p1": [away]}
	for pad: Dictionary in stage.get("pressure_pads", []):
		if pad.id not in pads: continue
		var spot := {"x": pad.position_cm[0], "z": pad.position_cm[1], "height": int(pad.get("height_cm", 0)), "surface_id": pad.surface_id}
		if not open_controls:
			if by_slot.has(str(pad.owner_slot)): by_slot[str(pad.owner_slot)].append(spot)
			continue
		for slot: String in by_slot:
			if not _frozen.is_empty() and slot == _frozen.slot: continue
			# The walker stands on no pad; for the presser's own walking only a
			# pad beside the crossing counts.
			if slot == _walker or (not _beside.is_empty() and not _pad_beside(pad, _beside)): continue
			if floors.is_empty() or floors.get(slot, {}).has(str(pad.surface_id)): by_slot[slot].append(spot)
	if not _frozen.is_empty(): by_slot[_frozen.slot] = [_frozen.at]
	var result: Array = []
	for p0: Dictionary in by_slot.p0:
		for p1: Dictionary in by_slot.p1: result.append({"p0": p0, "p1": p1})
	return result

## Whether the frozen or walking probe lights beams exactly.
func _exact_beams() -> bool:
	return not _frozen.is_empty() or not _walker.is_empty()

## Whether a pip holding `pad` could already touch `route`'s rect: within the
## pad's radius and a pip's (the engine latches a crossing a pip's edge enters).
func _pad_beside(pad: Dictionary, route: String) -> bool:
	if not index.has(route): return false
	var r: Array = surfaces[int(index[route])].rect
	var at := Vector2(float(pad.position_cm[0]), float(pad.position_cm[1]))
	var nearest := Vector2(clampf(at.x, float(r[0]), float(r[2])), clampf(at.y, float(r[1]), float(r[3])))
	return at.distance_to(nearest) <= float(int(pad.get("radius_cm", 28)) + RADIUS + 2)

## Whether a gate tree holds anywhere only while something is off (rules 16).
static func _negates(when: Dictionary) -> bool:
	if when.has("not"): return true
	for key: String in ["all", "any"]:
		for child: Variant in when.get(key, []):
			if child is Dictionary and _negates(child): return true
	return false

## Whether `slot` can stand within `entity`'s radius on its surface with
## `open` routes: the engine's own walker test at the centre and at points
## round the circle (a control's floor may be a narrow catwalk end). A journey
## control also needs the pip at its height (Seven.near), so one whose
## height_cm is not its floor's can never be worked.
func can_stand_at(entity: Dictionary, slot: String, open: Dictionary, journey: bool = false) -> bool:
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
		if found.is_empty() or str(found.surface_id) != surface: continue
		if not journey or Seven.near({"x": spot.x, "z": spot.y, "height": int(found.height), "surface_id": surface}, entity): return true
	return false

# ---------------------------------------------------------------- items

## Rules 16's carried items and currents (core/physical/carried_items.gd), as
## part of reach: for each item of `stage` (a plan, which carries the level's
## items and item spots and the stage's current legs), the floors a pip could
## hold it on and the item spots it could rest at, written into `settable` as
## "item:<id>": {"carried": [floors], "spots": [spot ids]}. A pip that reaches
## a floor the item rests on may pick it up; a carrier walks every open
## crossing but those needing both hands; across one of those it is handed up
## when some pip reaches the far end; it rests at an item spot on any floor it
## is carried to; a current leg carries it on once the leg's selector can show
## the leg's value (`when` and `stop` are not judged: an over-approximation).
## A hand up across a both-hands crossing needs both pips, one at each end.
## The frozen pip (the solo probe) and the walker (the both-pips probe) handle
## nothing, but an item one starts holding stays carried on its start floor;
## it is never handed anything. So the presser makes every pipsport move, as
## the design solver's strict one pip test asks.
func _reach_items(stage: Dictionary, checkpoint: Dictionary, floors: Dictionary, open: Dictionary, settable: Dictionary) -> void:
	if stage.get("items", []).is_empty(): return
	var mechanisms: Dictionary = checkpoint.get("mechanisms", {})
	var players: Dictionary = checkpoint.get("players", {})
	var actors: Dictionary = floors.duplicate()
	if not _frozen.is_empty(): actors[_frozen.slot] = {}
	# The walker only walks: every pick up, put down and hand over is the presser's.
	if not _walker.is_empty(): actors[_walker] = {}
	var hands := CarriedItems.hands_routes(stage)
	var walk: Dictionary = open.duplicate()
	for id: String in hands: walk.erase(id)
	var starts: Dictionary = stage.get("item_starts", {})
	for item: Dictionary in stage.items:
		var id := str(item.id)
		var state: Dictionary = CarriedItems.placed(stage, str(starts[id])) if starts.has(id) else mechanisms.get("items", {}).get(id, CarriedItems.placed(stage, str(item.get("at", ""))))
		var carried: Dictionary = {}
		var lying: Dictionary = {}
		var spots: Dictionary = {}
		if not str(state.get("holder", "")).is_empty():
			carried[str(players.get(str(state.holder), {}).get("surface_id", ""))] = true
		elif not str(state.get("spot", "")).is_empty(): spots[str(state.spot)] = true
		if not str(state.get("surface_id", "")).is_empty(): lying[str(state.surface_id)] = true
		var carry := CarriedItems.carriable(item)
		while true:
			var size := carried.size() + lying.size() + spots.size()
			for floor: String in lying:
				if carry and (actors.p0.has(floor) or actors.p1.has(floor)): carried[floor] = true
			for floor: String in carried.keys():
				for slot: String in ["p0", "p1"]:
					if actors[slot].has(floor):
						for reached: String in _walkable_from(slot, floor, walk, settable): carried[reached] = true
				for route: String in hands:
					if not open.has(route): continue
					var ends := _route_floors(route)
					if not ends.has(floor): continue
					# A hand up needs two pips: one at this end, the other at the far end.
					for other: String in ends:
						if (actors.p0.has(floor) and actors.p1.has(other)) or (actors.p1.has(floor) and actors.p0.has(other)): carried[other] = true
			for place: Dictionary in stage.get("item_spots", []):
				if carry and carried.has(str(place.get("surface_id", ""))): spots[str(place.id)] = true
			for leg: Dictionary in stage.get("current_legs", []):
				var values: Variant = settable.get(str(leg.get("control_id", "")), [])
				if spots.has(str(leg.from)) and (not leg.has("control_id") or (values is Array and str(leg.value) in values.map(func(v: Variant) -> String: return str(v)))):
					spots[str(leg.to)] = true
					var to := str(CarriedItems.spot(stage, str(leg.to)).get("surface_id", ""))
					if not to.is_empty(): lying[to] = true
			if carried.size() + lying.size() + spots.size() == size: break
		var carried_list := carried.keys().filter(func(floor: String) -> bool: return not floor.is_empty())
		carried_list.sort()
		var spot_list := spots.keys()
		spot_list.sort()
		settable["item:" + id] = {"carried": carried_list, "spots": spot_list}

## The floors a crossing joins, by the slots' edges.
func _route_floors(route: String) -> Dictionary:
	var ends: Dictionary = {}
	for slot: String in pairs:
		for key: String in pairs[slot]:
			var sides := key.split(">")
			if sides[0] == route and not route_bit.has(sides[1]): ends[sides[1]] = true
			if sides[1] == route and not route_bit.has(sides[0]): ends[sides[0]] = true
	return ends

## `gate` with its item terms judged by reach (_reach_items in `settable`):
## each becomes always true where it could hold, else never. "carried" holds
## on any floor a pip could hold the item, or only on the gate's own
## "surface_id" when it names one (the goal: the carrier stands there).
func with_items(gate: Dictionary, settable: Dictionary) -> Dictionary:
	var when: Variant = gate.get("when", {})
	if not when is Dictionary or not _has_item_term(when): return gate
	var judged := gate.duplicate()
	judged.when = _judge_items(when, settable, str(gate.get("surface_id", "")))
	return judged

func _has_item_term(value: Dictionary) -> bool:
	if CarriedItems.is_term(value): return true
	for child: Variant in value.values():
		if child is Dictionary and _has_item_term(child): return true
		if child is Array and child.any(func(entry: Variant) -> bool: return entry is Dictionary and _has_item_term(entry)): return true
	return false

## Under a "not" (rules 16, train/new-pieces-b) an item term may always be
## false (the item is elsewhere), so it becomes never there and the "not" holds.
func _judge_items(value: Dictionary, settable: Dictionary, at: String, negated: bool = false) -> Dictionary:
	if CarriedItems.is_term(value):
		if negated: return {"control_id": "@item", "value": "never"}
		var reach: Dictionary = settable.get("item:" + str(value.item_id), {"carried": [], "spots": []})
		var can := false
		if value.has("carried"): can = not bool(value.carried) or (not reach.carried.is_empty() and (at.is_empty() or at in reach.carried))
		elif value.has("spot_id"): can = str(value.spot_id) in reach.spots
		return {} if can else {"control_id": "@item", "value": "never"}
	var judged: Dictionary = {}
	for key: Variant in value:
		var child: Variant = value[key]
		var under := negated != (str(key) == "not")
		if child is Dictionary: judged[key] = _judge_items(child, settable, at, under)
		elif child is Array: judged[key] = child.map(func(entry: Variant) -> Variant: return _judge_items(entry, settable, at, under) if entry is Dictionary else entry)
		else: judged[key] = child
	return judged
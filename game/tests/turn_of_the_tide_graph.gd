extends RefCounted
## Surface-level reachability for turn-of-the-tide@1, built from the real
## Navigation and judged by the real gate predicates (Seven.predicate).
##
## Edges: a walker of one slot can step from surface a onto surface b. Each is
## found by walking 1 cm at a time with Navigation.at across the place where
## the two meet, with only a and b open as routes (islands always support), so
## an edge needs exactly the routes among {a, b}. Drops are probed separately
## with their lever on and become one-way edges that need that lever.
##
## States: (surface, the explorer's own control and lever values, entry
## latches). The explorer may press its own controls and levers while standing
## on their surface (each marker is standable on it, checked separately), and,
## as role b, latches every entry-latch route it steps onto. The other player's
## values come from "phases": every tick of a real recording, with consecutive
## identical ticks merged. A phase's closure lets the explorer move freely, so
## the reachable set over-approximates what a real walker can reach in time.
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
	for bridge: Dictionary in level.bridges: _add(bridge, "bridge")
	for stair: Dictionary in level.stairs: _add(stair, "stair")

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

## The link set the spec draws: each bridge and stair joins its from and to
## surfaces (a stub only its parent), the aqueduct feeder meets the terrace
## and the span, and the spout drops onto the beach.
func intended(slot: String) -> Dictionary:
	var links: Dictionary = {}
	for route: Dictionary in level.bridges + level.stairs:
		if not Navigation._owns(route, slot): continue
		links[_pair_key(route.from_surface, route.id)] = true
		if route.to_surface != route.id: links[_pair_key(route.id, route.to_surface)] = true
	links[_pair_key("aq-feeder", "m-terrace")] = true
	links[_pair_key("aq-feeder", "aq-span")] = true
	return links

func _pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

## Undirected view of the found edges (drops listed separately).
func undirected(slot: String) -> Dictionary:
	var result: Dictionary = {}
	for key: String in pairs[slot]:
		if not str(pairs[slot][key][1]).is_empty(): continue
		var ends := key.split(">")
		result[_pair_key(ends[0], ends[1])] = true
	return result

# ---------------------------------------------------------------- phases

## The other player's values at every tick of a real recording, as the
## explorer's world sees them (a receiver standing still replays it); runs of
## identical ticks merge into one phase. A pad held by the recorder appears
## as the recorder standing on it.
static func phases(definition: Dictionary, stage_id: String, checkpoint: Dictionary, first: Dictionary, simulation: Script) -> Array:
	var sim: RefCounted = simulation.new()
	sim.simulation_version = int(first.simulation_version)
	sim._reset_trusted(definition, stage_id, checkpoint, first, "b")
	var source: String = sim.first_player_slot
	var result: Array = []
	var last := ""
	for tick in range(int(first.duration_ticks) + 1):
		var phase := {"controls": {}, "levers": {}, "players": {}}
		for control: Dictionary in sim.stage.controls:
			if control.owner_slot == source: phase.controls[control.id] = str(sim._mechanisms.controls[control.id])
		for lever: Dictionary in sim.stage.levers:
			if lever.owner_slot == source: phase.levers[lever.id] = bool(sim._mechanisms.levers.get(lever.id, false))
		for pad: Dictionary in sim.stage.pressure_pads:
			if pad.owner_slot == source and Seven.near(sim._players[source], pad):
				phase.players[source] = {"x": pad.position_cm[0], "z": pad.position_cm[1], "height": int(pad.height_cm), "surface_id": pad.surface_id}
		var key := JSON.stringify(phase)
		if key != last: result.append(phase)
		last = key
		if tick < int(first.duration_ticks): sim.step({})
	return result

# ---------------------------------------------------------------- explorer

## An explorer: who moves, the stage, the checkpoint it starts from, its own
## controls and levers, and the other player's phases.
class Explorer:
	var graph: RefCounted
	var slot: String
	var role: String
	var stage: Dictionary
	var base_mechanisms: Dictionary
	var base_latched := 0
	var latch_mask := 0
	var own_controls: Array = []      # [{id, values, surface}]
	var own_levers: Array = []        # [{id, surface}]
	var frozen: Dictionary = {}       # own control id -> fixed value (not pressable)
	var radix: Array = []
	var combos := 1
	var gates: Array = []             # [bit, when]
	var pads: Array = []
	var goal := -1
	var _open_cache: Dictionary = {}
	var _phase_key := ""
	var phase: Dictionary = {"controls": {}, "levers": {}, "players": {}}

	func _init(g: RefCounted, definition: Dictionary, stage_id: String, explorer_slot: String, checkpoint: Dictionary) -> void:
		graph = g
		slot = explorer_slot
		for item: Dictionary in definition.stages:
			if item.id == stage_id: stage = item
		role = "a" if stage.first_player_slot == slot else "b"
		base_mechanisms = checkpoint.mechanisms.duplicate(true)
		base_latched = graph.bits_of(base_mechanisms.latched_bridges)
		if role == "b": latch_mask = graph.bits_of(stage.get("entry_latch_routes", [])) & ~base_latched
		for control: Dictionary in stage.controls:
			if control.owner_slot == slot: own_controls.append({"id": control.id, "values": control.values, "surface": int(graph.index[control.surface_id])})
		for lever: Dictionary in stage.levers:
			if lever.owner_slot == slot: own_levers.append({"id": lever.id, "surface": int(graph.index[lever.surface_id])})
		for gate: Dictionary in stage.gates:
			gates.append([int(graph.route_bit[gate.route_id]), gate.get("when", {})])
		pads = stage.get("pressure_pads", [])
		goal = int(graph.index[stage.goal.surface_id])
		_radix()

	## Exact reductions for a run of phases: a latch on a route that is open in
	## every phase for every own value never matters, and an own control or
	## lever that never changes which routes are open can stay at its start
	## value (states that differ only there behave the same). Returns what it
	## dropped.
	func prepare(all_phases: Array) -> Dictionary:
		var always := -1
		var irrelevant: Array = []
		for value: Dictionary in all_phases:
			set_phase(value)
			for combo in range(combos): always &= open_bits(combo)
		var dropped_latches: Array = graph.routes_of(latch_mask & always)
		latch_mask &= ~always
		var start := _values(combo_of(base_mechanisms))
		var digit := 0
		var scale := 1
		var names: Array = []
		for control: Dictionary in own_controls: names.append(control.id)
		for lever: Dictionary in own_levers: names.append(lever.id)
		for name: String in names:
			var n: int = radix[digit]
			var matters := false
			if n > 1:
				for value: Dictionary in all_phases:
					set_phase(value)
					for combo in range(combos):
						var v := (combo / scale) % n
						var base := combo - v * scale
						for w in range(n):
							if open_bits(base + w * scale) != open_bits(combo): matters = true
						if matters: break
					if matters: break
			if n > 1 and not matters: irrelevant.append(name)
			scale *= n
			digit += 1
		var fixed := frozen.duplicate()
		for name: String in irrelevant:
			fixed[name] = start.controls[name] if start.controls.has(name) else start.levers[name]
		freeze(fixed)
		set_phase(all_phases[-1])
		return {"latches": dropped_latches, "frozen": irrelevant}

	func freeze(values: Dictionary) -> void:
		frozen = values
		_radix()

	func _radix() -> void:
		radix = []
		combos = 1
		for control: Dictionary in own_controls:
			var n: int = 1 if frozen.has(control.id) else control.values.size()
			radix.append(n)
			combos *= n
		for lever: Dictionary in own_levers:
			var n := 1 if frozen.has(lever.id) else 2
			radix.append(n)
			combos *= n
		_open_cache = {}

	## The combo index of the explorer's own values in a mechanisms dictionary.
	func combo_of(mechanisms: Dictionary) -> int:
		var value := 0
		var scale := 1
		var digit := 0
		for control: Dictionary in own_controls:
			var v: int = 0 if frozen.has(control.id) else control.values.find(str(mechanisms.controls.get(control.id, "")))
			value += v * scale
			scale *= int(radix[digit])
			digit += 1
		for lever: Dictionary in own_levers:
			var v: int = 0 if frozen.has(lever.id) else (1 if bool(mechanisms.levers.get(lever.id, false)) else 0)
			value += v * scale
			scale *= int(radix[digit])
			digit += 1
		return value

	func _values(combo: int) -> Dictionary:
		var controls: Dictionary = {}
		var levers: Dictionary = {}
		var rest := combo
		var digit := 0
		for control: Dictionary in own_controls:
			var n: int = radix[digit]
			controls[control.id] = str(frozen[control.id]) if frozen.has(control.id) else str(control.values[rest % n])
			rest /= n
			digit += 1
		for lever: Dictionary in own_levers:
			var n: int = radix[digit]
			levers[lever.id] = bool(frozen[lever.id]) if frozen.has(lever.id) else rest % n == 1
			rest /= n
			digit += 1
		return {"controls": controls, "levers": levers}

	func set_phase(value: Dictionary) -> void:
		phase = value
		_phase_key = JSON.stringify(value)
		_open_cache = {}

	func mechanisms_for(combo: int) -> Dictionary:
		var mechanisms := base_mechanisms.duplicate(true)
		var own := _values(combo)
		for id: String in phase.controls: mechanisms.controls[id] = phase.controls[id]
		for id: String in phase.levers: mechanisms.levers[id] = phase.levers[id]
		for id: String in own.controls: mechanisms.controls[id] = own.controls[id]
		for id: String in own.levers: mechanisms.levers[id] = own.levers[id]
		return mechanisms

	## Routes open by gate or by a stage-1 latch, for the explorer's values.
	func open_bits(combo: int) -> int:
		if _open_cache.has(combo): return _open_cache[combo][0]
		var mechanisms := mechanisms_for(combo)
		var players: Dictionary = {"p0": {"x": 100000, "z": 100000, "height": -1000, "surface_id": ""}, "p1": {"x": 100000, "z": 100000, "height": -1000, "surface_id": ""}}
		for id: String in phase.players: players[id] = phase.players[id]
		var mask := base_latched
		for gate: Array in gates:
			if Seven.predicate(gate[1], stage, players, mechanisms): mask |= int(gate[0])
		var result := [mask, mechanisms.levers]
		_open_cache[combo] = result
		return result[0]

	func levers_for(combo: int) -> Dictionary:
		open_bits(combo)
		return _open_cache[combo][1]

	static func key(surface: int, combo: int, latches: int) -> int:
		return surface | (combo << 6) | (latches << 16)

	static func surface_of(state: int) -> int: return state & 63
	static func combo_of_state(state: int) -> int: return (state >> 6) & 1023
	static func latches_of(state: int) -> int: return state >> 16

	## Successors of a state in the current phase: [state, cost] (cost 1 = a press).
	func successors(state: int) -> Array:
		var result: Array = []
		var surface := surface_of(state)
		var combo := combo_of_state(state)
		var latches := latches_of(state)
		var open := open_bits(combo) | latches
		var levers := levers_for(combo)
		for edge: Array in graph.edges[slot][surface]:
			var required: int = edge[1]
			if (required & open) != required: continue
			if not str(edge[2]).is_empty() and not bool(levers.get(edge[2], false)): continue
			var to: int = edge[0]
			var gained := latches
			var bit: int = graph.route_bit.get(graph.id_of(to), 0)
			if bit & latch_mask: gained |= bit
			result.append([key(to, combo, gained), 0])
		var scale := 1
		var digit := 0
		for control: Dictionary in own_controls:
			var n: int = radix[digit]
			if n > 1 and control.surface == surface:
				var v := (combo / scale) % n
				result.append([key(surface, combo + (((v + 1) % n) - v) * scale, latches), 1])
			scale *= n
			digit += 1
		for lever: Dictionary in own_levers:
			var n: int = radix[digit]
			if n > 1 and lever.surface == surface:
				var v := (combo / scale) % n
				result.append([key(surface, combo + ((1 - v) - v) * scale, latches), 1])
			scale *= n
			digit += 1
		return result

	## Everything reachable from `states` in the current phase.
	func closure(states: Dictionary) -> Dictionary:
		var seen := states.duplicate()
		var queue: Array = states.keys()
		var head := 0
		while head < queue.size():
			var state: int = queue[head]
			head += 1
			for next: Array in successors(state):
				if not seen.has(next[0]):
					seen[next[0]] = true
					queue.append(next[0])
		return seen

	## Every state reachable from the checkpoint start on `surface` while the
	## phases play in order (the explorer may wait through any of them).
	func reach_over(surface: int, all_phases: Array) -> Dictionary:
		set_phase(all_phases[0])
		var reached: Dictionary = {key(surface, combo_of(base_mechanisms), 0): true}
		for value: Dictionary in all_phases:
			set_phase(value)
			reached = closure(reached)
		return reached

	## States of `reached` (closed under the current phase) that cannot reach `targets`.
	func strands(reached: Dictionary, targets: Array) -> int:
		var ok := good(reached, targets)
		var count := 0
		for state: int in reached:
			if not ok.has(state): count += 1
		return count

	## Fewest presses to a target while the phases play in order: the explorer
	## may wait, and may use any phase's routes while it lasts.
	func min_presses_over(surface: int, all_phases: Array, targets: Array) -> int:
		set_phase(all_phases[0])
		return _cheapest({key(surface, combo_of(base_mechanisms), 0): 0}, targets, all_phases)

	## States in `universe` (closed under the current phase) that reach a target.
	func good(universe: Dictionary, targets: Array) -> Dictionary:
		var result: Dictionary = {}
		var queue: Array = []
		for state: int in universe:
			if surface_of(state) in targets:
				result[state] = true
				queue.append(state)
		var head := 0
		while head < queue.size():
			var state: int = queue[head]
			head += 1
			for previous: int in _predecessors(state):
				if universe.has(previous) and not result.has(previous):
					# Confirm the move really leads here in this phase.
					for next: Array in successors(previous):
						if next[0] == state:
							result[previous] = true
							queue.append(previous)
							break
		return result

	## Candidates that may step or press into `state` (the caller checks them).
	func _predecessors(state: int) -> Array:
		var result: Array = []
		var surface := surface_of(state)
		var combo := combo_of_state(state)
		var latches := latches_of(state)
		var bit: int = int(graph.route_bit.get(graph.id_of(surface), 0)) & latch_mask
		for edge: Array in graph.reverse[slot][surface]:
			result.append(key(edge[0], combo, latches))
			if bit != 0 and (latches & bit) != 0: result.append(key(edge[0], combo, latches & ~bit))
		var scale := 1
		var digit := 0
		for control: Dictionary in own_controls:
			var n: int = radix[digit]
			if n > 1 and control.surface == surface:
				var v := (combo / scale) % n
				result.append(key(surface, combo + (((v + n - 1) % n) - v) * scale, latches))
			scale *= n
			digit += 1
		for lever: Dictionary in own_levers:
			var n: int = radix[digit]
			if n > 1 and lever.surface == surface:
				var v := (combo / scale) % n
				result.append(key(surface, combo + ((1 - v) - v) * scale, latches))
			scale *= n
			digit += 1
		return result

	## Fewest presses from `start` to a target in the current phase (-1: none).
	func min_presses(start: int, targets: Array) -> int:
		return _cheapest({start: 0}, targets, [phase])

	## Dijkstra with 0/1 costs over the phases in order. A state is skipped
	## when one on the same surface and values, with at least its latches, was
	## reached no dearer: more latches never close a route, so this is exact.
	func _cheapest(seed: Dictionary, targets: Array, all_phases: Array) -> int:
		var front: Dictionary = {}
		var best: Dictionary = {}
		for state: int in seed: _admit(front, best, state, int(seed[state]))
		var found := -1
		for value: Dictionary in all_phases:
			set_phase(value)
			var buckets: Array = []
			for state: int in best:
				var c0: int = best[state]
				while buckets.size() <= c0: buckets.append([])
				buckets[c0].append(state)
			var cost := 0
			while cost < buckets.size():
				if found >= 0 and cost >= found: break
				var queue: Array = buckets[cost]
				var head := 0
				while head < queue.size():
					var state: int = queue[head]
					head += 1
					if int(best.get(state, -1)) != cost: continue
					if surface_of(state) in targets:
						found = cost
						break
					for next: Array in successors(state):
						var to_cost: int = cost + int(next[1])
						if _admit(front, best, next[0], to_cost):
							while buckets.size() <= to_cost: buckets.append([])
							buckets[to_cost].append(next[0])
				cost += 1
		return found

	func _admit(front: Dictionary, best: Dictionary, state: int, cost: int) -> bool:
		var group := state & 65535
		var latches := latches_of(state)
		var kept: Array = front.get(group, [])
		for item: Array in kept:
			if (int(item[0]) & latches) == latches and int(item[1]) <= cost: return false
		var survivors: Array = []
		for item: Array in kept:
			if (latches & int(item[0])) == int(item[0]) and cost <= int(item[1]):
				best.erase(key(group & 63, group >> 6, int(item[0])))
			else:
				survivors.append(item)
		survivors.append([latches, cost])
		front[group] = survivors
		best[state] = cost
		return true

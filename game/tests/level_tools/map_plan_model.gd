extends RefCounted
## A stage's flat map plan as plain data, from its definition alone (no world
## needed, so a layout can be judged before any scenery exists): the floors
## with their heights, the crossings and whether this stage can open them,
## every control, which control works which gate (the pair tags' own letters
## and colours, kit/pair_tags.gd), who owns what, the goal and where the pips
## start, and rules 20's item spots, items, current legs and both-hands
## crossings (core/physical/carried_items.gd). map_plan_view.gd draws it;
## tests/test_level_tools.gd checks it.
## Coordinates stay the definition's centimetres (x across, z down the page).
const PairTags = preload("res://presentation/kit/pair_tags.gd")
const LevelGraph = preload("res://tests/level_graph.gd")
const Stages = preload("res://tests/level_tools/level_stages.gd")
const CarriedItems = preload("res://core/physical/carried_items.gd")

## The plan of `view` (a stage's plan, services/level_layout.gd). `checkpoint`
## (in the plan's terms, level_stages.gd floor_checkpoint) places the pips
## and the crossings kept from earlier ({} draws no starts and marks no
## reach); `skips` are the world's pair_tags.skips() (none without a world).
static func build(level: Dictionary, view: Dictionary, checkpoint: Dictionary, journey: bool, skips: Array = []) -> Dictionary:
	var stage_index := 0
	for index in range(level.get("stages", []).size()):
		if str(level.stages[index].id) == str(view.get("stage_id", "")): stage_index = index
	var authored: Dictionary = level.stages[stage_index] if not level.get("stages", []).is_empty() else {}
	var plan := {
		"title": str(level.get("title", level.get("id", ""))),
		"stage_title": str(authored.get("title", str(view.get("stage_id", "")).replace("-", " ").capitalize())),
		"stage_index": stage_index,
		"stage_count": level.get("stages", []).size(),
		"turns": Stages.turns_label(level, authored),
		"floors": [], "crossings": [], "drops": [], "obstacles": [], "zones": [],
		"controls": [], "pairs": [], "goal": {}, "starts": [], "first_slot": str(view.get("first_player_slot", "p0")),
		"item_spots": [], "items": [], "legs": [],
	}
	var reach := _reach(level, view, checkpoint, journey)
	var bounds := Rect2()
	for island: Dictionary in view.get("islands", []):
		plan.floors.append({"id": str(island.id), "rect": _rect(island.rect_cm), "height": int(island.get("height_cm", 0)), "reached": reach.is_empty() or reach.has(str(island.id))})
		bounds = _grow(bounds, _rect(island.rect_cm))
	var gated: Dictionary = {}
	for gate: Dictionary in view.get("gates", []): gated[str(gate.route_id)] = gate
	var kept: Array = checkpoint.get("mechanisms", {}).get("latched_bridges", [])
	for kind: String in ["bridges", "stairs"]:
		for route: Dictionary in view.get(kind, []):
			var id := str(route.id)
			var state := "shut"
			if id in kept: state = "kept"
			elif gated.has(id): state = "gated" if not PairTags.references(gated[id]).is_empty() else "open"
			var item := {"id": id, "kind": kind.trim_suffix("s"), "rect": _rect(route.rect_cm), "state": state, "owner": str(route.get("owner_slot", "")), "reached": reach.is_empty() or reach.has(id), "hands": bool(route.get("hands", false))}
			# Rules 20: a gate an item opens (a raft at its berth) is named at it.
			var terms := _item_terms(gated.get(id, {}).get("when", {}))
			if not terms.is_empty():
				if state == "open": item.state = "gated"
				item["unlettered"] = terms
			if kind == "stairs":
				item.merge({"axis": str(route.get("axis", "x")), "low": int(route.from_height_cm), "high": int(route.to_height_cm)})
			else:
				item["height"] = int(route.get("height_cm", 0))
			plan.crossings.append(item)
			bounds = _grow(bounds, _rect(route.rect_cm))
	for drop: Dictionary in view.get("drops", []):
		plan.drops.append({"id": str(drop.id), "rect": _rect(drop.rect_cm), "lever": str(drop.get("requires_lever", ""))})
	for obstacle: Dictionary in view.get("obstacles", []): plan.obstacles.append({"id": str(obstacle.id), "rect": _rect(obstacle.rect_cm)})
	for zone: Dictionary in view.get("access_zones", []): plan.zones.append({"id": str(zone.id), "rect": _rect(zone.rect_cm), "owner": str(zone.get("owner_slot", ""))})
	var pairs := PairTags.pairs_of(view, skips)
	var pair_of: Dictionary = {}
	for pair: Dictionary in pairs: pair_of[str(pair.control)] = int(pair.index)
	for kind: Array in [["controls", "selector"], ["levers", "lever"], ["pressure_pads", "pad"], ["ball_pads", "ball pad"]]:
		for entity: Dictionary in view.get(kind[0], []):
			var item := {"id": str(entity.id), "kind": kind[1], "at": _point(entity.position_cm), "radius": float(entity.get("radius_cm", 28)), "owner": str(entity.get("owner_slot", "")), "pair": int(pair_of.get(str(entity.id), -1))}
			if entity.has("values"): item.merge({"values": entity.values.duplicate(), "initial": str(checkpoint.get("mechanisms", {}).get("controls", {}).get(entity.id, entity.get("initial", "")))})
			plan.controls.append(item)
	var routes: Dictionary = {}
	for item: Dictionary in plan.crossings: routes[item.id] = item
	for pair: Dictionary in pairs:
		var index := int(pair.index)
		var gates: Array = []
		for route: Dictionary in pair.gates:
			gates.append({"route": str(route.id), "at": (routes[str(route.id)].rect as Rect2).get_center(), "values": pair.values.get(str(route.id), [])})
		plan.pairs.append({"index": index, "control": str(pair.control), "letter": PairTags.letter_of(index), "band": PairTags.band_of(index), "colour": PairTags.colour_of(index), "at": _point(pair.entity.position_cm), "gates": gates})
	# A control the world shows its own way (no tile) is named at its gates
	# instead: "tide half" by a crossing the half tide opens.
	for pair: Dictionary in PairTags.pairs_of(view):
		if pair_of.has(str(pair.control)): continue
		for route: Dictionary in pair.gates:
			var asked: Array = pair.values.get(str(route.id), [])
			routes[str(route.id)].get_or_add("unlettered", []).append(str(pair.control) + ("" if asked.is_empty() else " " + "/".join(asked)))
	# The new pieces (rules 20), named by their crossings: a platform's stops,
	# the sinking stones, a pull-up ladder, and a crossing a control floods.
	for platform: Dictionary in view.get("platforms", []):
		for stop: Variant in platform.get("stops", []):
			if routes.has(str(stop)): routes[str(stop)].get_or_add("unlettered", []).append("%s stop" % platform.id)
	for stone: Variant in view.get("sinking", []):
		if routes.has(str(stone)): routes[str(stone)].get_or_add("unlettered", []).append("sinks under two")
	for stair: Dictionary in view.get("stairs", []):
		if stair.has("one_way") and routes.has(str(stair.id)): routes[str(stair.id)].get_or_add("unlettered", []).append("ladder: up only")
	for gate: Dictionary in view.get("gates", []):
		var when: Dictionary = gate.get("when", {})
		for term: Dictionary in [when] + when.get("all", []):
			if term.get("not") is Dictionary and term["not"].has("lever_id") and routes.has(str(gate.route_id)):
				routes[str(gate.route_id)].get_or_add("unlettered", []).append("flooded while %s is on" % term["not"].lever_id)
	var goal: Dictionary = view.get("goal", {})
	if not goal.is_empty():
		plan.goal = {"id": str(goal.id), "at": _point(goal.position_cm), "radius": float(goal.get("radius_cm", 28)), "owner": str(goal.get("owner_slot", "")), "kind": str(view.get("goal_policy", {}).get("kind", "ring"))}
	for slot: String in checkpoint.get("players", {}):
		var player: Dictionary = checkpoint.players[slot]
		plan.starts.append({"slot": slot, "at": Vector2(float(player.x), float(player.z))})
	_items(view, checkpoint, plan)
	plan["bounds"] = bounds
	return plan

## Rules 20: the item spots (on the water when they have no floor), where
## each item is as the stage starts, and each current leg with its wheel's value.
static func _items(view: Dictionary, checkpoint: Dictionary, plan: Dictionary) -> void:
	for spot: Dictionary in view.get("item_spots", []):
		plan.item_spots.append({"id": str(spot.id), "at": _point(spot.position_cm), "water": str(spot.get("surface_id", "")).is_empty()})
	var states: Dictionary = checkpoint.get("mechanisms", {}).get("items", CarriedItems.initial(view))
	var starts: Dictionary = view.get("item_starts", {})
	for item: Dictionary in view.get("items", []):
		var id := str(item.id)
		var state: Dictionary = CarriedItems.placed(view, str(starts[id])) if starts.has(id) else states.get(id, {})
		if state.is_empty() or CarriedItems.is_away(state): continue
		var holder := str(state.holder)
		var player: Dictionary = checkpoint.get("players", {}).get(holder, {})
		var at := Vector2(float(player.get("x", 0)), float(player.get("z", 0))) if not holder.is_empty() else Vector2(float(state.x), float(state.z))
		plan.items.append({"id": id, "at": at, "holder": holder, "float": not CarriedItems.carriable(item)})
	for leg: Dictionary in view.get("current_legs", []):
		var from := CarriedItems.spot(view, str(leg.from))
		var to := CarriedItems.spot(view, str(leg.to))
		if from.is_empty() or to.is_empty(): continue
		plan.legs.append({"from": _point(from.position_cm), "to": _point(to.position_cm), "label": ("%s %s" % [leg.control_id, leg.get("value", "")]).strip_edges() if leg.has("control_id") else "current", "stop": leg.has("stop")})

## The item terms of a gate's tree, as words ("raft at berth", "pipsport carried").
static func _item_terms(value: Variant) -> Array:
	var found: Array = []
	if value is Dictionary:
		if CarriedItems.is_term(value): found.append("%s %s" % [value.item_id, "carried" if value.has("carried") else "at " + str(value.get("spot_id", ""))])
		for child: Variant in value.values(): found.append_array(_item_terms(child))
	elif value is Array:
		for child: Variant in value: found.append_array(_item_terms(child))
	return found

## Floors and crossings either pip could reach on the stage ({} without a
## checkpoint: nothing is marked out of reach).
static func _reach(level: Dictionary, view: Dictionary, checkpoint: Dictionary, journey: bool) -> Dictionary:
	if checkpoint.is_empty() or checkpoint.get("players", {}).is_empty(): return {}
	var found: Dictionary = LevelGraph.new(view).reach(view, checkpoint, journey)
	var result: Dictionary = {}
	for slot: String in found.floors:
		for id: String in found.floors[slot]: result[id] = true
	return result

static func _rect(r: Array) -> Rect2:
	return Rect2(Vector2(float(r[0]), float(r[1])), Vector2(float(r[2]) - float(r[0]), float(r[3]) - float(r[1])))

static func _point(at: Array) -> Vector2:
	return Vector2(float(at[0]), float(at[1]))

static func _grow(bounds: Rect2, rect: Rect2) -> Rect2:
	return rect if not bounds.has_area() else bounds.merge(rect)

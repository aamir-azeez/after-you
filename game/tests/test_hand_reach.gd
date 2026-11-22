extends SceneTree
## Hand controls (core/solid_footprint.gd with_hands): on every registered
## chapter's every stage, each solid lever, switch, selector and mirror leaves
## its level whole for both pips, walked with the engine's own Navigation and
## every crossing open:
## - a pip can stand within its reach, beside the footprint, at its height;
## - the free floor round its footprint stays one piece (a pip that could walk
##   from one side to the other still can), so no way a level needs is cut;
## - every other spot a pip stands at (pads, ball pads, the goal, item spots,
##   starts) keeps floor a pip can stand on inside it;
## - each bell goal's two pads, one per pip, lie inside the goal on floor
##   that pip stands on;
## - nothing on its floor that blocks a pip (an obstacle, an owned zone) comes
##   within its reach, so it is never worked through a wall.
## A control on a floor too small for its footprint (fits()) keeps its plain
## spot, and the suite lists them. Sleeping Lighthouse's stages embed their
## own stage of flat islands (core/lighthouse): the same checks walk those
## islands on a grid (_check_native).
const Solid = preload("res://core/solid_footprint.gd")
const Navigation = preload("res://core/cooperative/navigation.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const ChapterIndex = preload("res://content/chapters/index.gd")
const Placement = preload("res://content/dressing/placement.gd")
const LightCatalog = preload("res://core/lighthouse/stage_catalog.gd")
const GoalPiece = preload("res://presentation/kit/pieces/goal.gd")
const STEP := 8
const BODY := Solid.BODY_CM
## How far the walk round one footprint may spread before it counts as cut.
const MOST_NODES := 40000
const SPOT_LISTS := ["pressure_pads", "ball_pads"]
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	_rule_checks()
	var solid_count := 0
	var goal_pads := 0
	var plain: Array[String] = []
	for key: String in ChapterIndex.keys():
		var level := Placement.definition(key)
		if not level.get("stages") is Array: continue
		var routes: Dictionary = {}
		for list: String in ["bridges", "stairs"]:
			for route: Dictionary in level.get(list, []): routes[route.id] = true
		var cells := Navigation.index_for(level, Canonical.digest(level))
		for stage: Variant in level.stages:
			if not stage is Dictionary: continue
			if stage.get("native") is Dictionary:
				solid_count += _check_native(key, stage, plain)
				continue
			var hands: Array = stage.get("levers", []) + stage.get("controls", [])
			var solids := Solid.solids(hands + level.get("item_spots", []))
			goal_pads += _check_goal_pads(level, routes, cells, solids, stage, "%s, stage %s" % [key, stage.id])
			for control: Dictionary in hands:
				if Solid.of(control).is_empty(): plain.append("%s %s %s" % [key, stage.id, control.id])
			if solids.is_empty(): continue
			for control: Dictionary in Solid.solids(hands):
				solid_count += 1
				var where := "%s, stage %s, %s" % [key, stage.id, control.id]
				_check(Solid.of(control) == Solid.HAND, "%s: a hand control's footprint is HAND" % where)
				_check_clear(level, control, where)
				for slot: String in ["p0", "p1"]:
					_check_control(level, routes, cells, solids, control, slot, where)
			for spot: Dictionary in _stand_spots(level, stage):
				for slot: String in ["p0", "p1"]:
					_check_spot(level, routes, cells, solids, spot, slot, "%s, stage %s, %s" % [key, stage.id, str(spot.get("id", "start"))])
	_check(solid_count > 0, "Some chapter has a solid hand control")
	_check(goal_pads > 0, "Some chapter's goal stands its two pads")
	print("HAND REACH: %d solid hand controls; plain on floors too small: %s" % [solid_count, ", ".join(plain)])
	print("HAND REACH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## A Lighthouse stage (core/lighthouse/room_catalog.gd): each mirror and
## selector on its island the same as above, that island's free floor walked
## on a STEP grid (core/lighthouse/borrowed_light.gd keeps a pip's body on its
## island). Returns how many hand controls are solid.
func _check_native(key: String, stage: Dictionary, plain: Array[String]) -> int:
	var native: Dictionary = stage.native
	var hands := LightCatalog.controls_of(native)
	var solids := Solid.solids(hands)
	for control: Dictionary in hands:
		if Solid.of(control).is_empty(): plain.append("%s %s %s" % [key, stage.id, control.id])
	for control: Dictionary in solids:
		var where := "%s, stage %s, %s" % [key, stage.id, control.id]
		_check(Solid.of(control) == Solid.HAND, "%s: a hand control's footprint is HAND" % where)
		var rect: Array = _island_under(native, control).get("rect_cm", [])
		_check(not rect.is_empty(), "%s: stands on an island" % where)
		if rect.is_empty(): continue
		var centre := Vector2i(int(control.position_cm[0]), int(control.position_cm[1]))
		var keep := int(Solid.of(control).radius_cm) + BODY
		var stands := 0
		var boundary: Array[Vector2i] = []
		var span := (keep + int(Solid.of(control).reach_cm)) / STEP + 1
		for i in range(-span, span + 1):
			for j in range(-span, span + 1):
				var point := centre + Vector2i(i, j) * STEP
				if not _on_island(rect, point) or Solid.blocked(solids, point, BODY): continue
				if Solid.within_reach(control, point, BODY): stands += 1
				if point.distance_squared_to(centre) <= (keep + STEP * 2) * (keep + STEP * 2): boundary.append(point)
		_check(stands > 0, "%s: no free floor within reach" % where)
		_check(boundary.size() < 2 or _walk_island(rect, solids, boundary), "%s: its footprint cuts the floor round it in two" % where)
	# Every spot a pip stands at keeps floor to stand on inside it.
	var spots: Array = native.get("hold_pads", []) + native.get("sockets", []) + native.get("props", [])
	for one: String in ["plate", "goal"]:
		if native.get(one) is Dictionary: spots.append(native[one])
	for spot: Dictionary in spots:
		var rect: Array = _island_under(native, spot).get("rect_cm", [])
		var centre := Vector2i(int(spot.position_cm[0]), int(spot.position_cm[1]))
		var radius := int(spot.radius_cm)
		var room := false
		for i in range(-radius / STEP, radius / STEP + 1):
			for j in range(-radius / STEP, radius / STEP + 1):
				var point := centre + Vector2i(i, j) * STEP
				room = room or (point.distance_squared_to(centre) <= radius * radius and _on_island(rect, point) and not Solid.blocked(solids, point, BODY))
		_check(room, "%s, stage %s, %s: a hand control's footprint leaves no floor to stand on inside it" % [key, stage.id, spot.id])
	return solids.size()

## The island of `native` that holds `entity`'s centre, else {}.
func _island_under(native: Dictionary, entity: Dictionary) -> Dictionary:
	for island: Dictionary in native.islands:
		if _on_island(island.rect_cm, Vector2i(int(entity.position_cm[0]), int(entity.position_cm[1])), 0): return island
	return {}

## Whether a pip of BODY (or `body`) radius centred at `point` stands wholly on `rect`.
func _on_island(rect: Array, point: Vector2i, body: int = BODY) -> bool:
	return rect.size() == 4 and point.x - body >= int(rect[0]) and point.x + body <= int(rect[2]) and point.y - body >= int(rect[1]) and point.y + body <= int(rect[3])

## Whether every point of `wanted` is reached from the first over `rect`'s free floor.
func _walk_island(rect: Array, solids: Array, wanted: Array[Vector2i]) -> bool:
	var left := {}
	for point: Vector2i in wanted: left[point] = true
	var seen := {wanted[0]: true}
	var queue: Array[Vector2i] = [wanted[0]]
	var head := 0
	while head < queue.size() and not left.is_empty():
		if head >= MOST_NODES: return false
		var at := queue[head]
		head += 1
		left.erase(at)
		for offset: Vector2i in [Vector2i(STEP, 0), Vector2i(-STEP, 0), Vector2i(0, STEP), Vector2i(0, -STEP)]:
			var next := at + offset
			if seen.has(next) or not _on_island(rect, next) or Solid.blocked(solids, next, BODY): continue
			seen[next] = true
			queue.append(next)
	return left.is_empty()

## The rule on made-up floors.
func _rule_checks() -> void:
	var lever := {"id": "l", "position_cm": [0, 0], "radius_cm": 28, "surface_id": "f"}
	_check(Solid.fits(lever, [-200, -200, 200, 200], Solid.HAND, BODY), "A lever in a wide floor fits")
	_check(Solid.fits(lever, [-200, -20, 200, 200], Solid.HAND, BODY), "A lever at one edge fits: the way round is on its other side")
	_check(not Solid.fits(lever, [-28, -32, 28, 32], Solid.HAND, BODY), "A lever on a catwalk it fills does not fit")
	_check(not Solid.fits(lever, [-200, -50, 200, 50], Solid.HAND, BODY), "A lever across a walk with less than GAP_CM past it does not fit")
	_check(not Solid.fits({"position_cm": [-150, -150]}, [-200, -200, 200, 200], Solid.HAND, BODY), "A lever that shuts off a corner of its floor does not fit")
	var level := {"islands": [{"id": "f", "rect_cm": [-200, -200, 200, 200], "height_cm": 0}, {"id": "c", "rect_cm": [300, 0, 356, 64], "height_cm": 0}],
		"stages": [{"id": "s", "levers": [lever.duplicate(true), {"id": "k", "position_cm": [328, 32], "radius_cm": 28, "surface_id": "c"}],
			"controls": [{"id": "m", "position_cm": [100, 100], "radius_cm": 28, "surface_id": "f", "solid": {"radius_cm": 1}}],
			"pressure_pads": [{"id": "p", "position_cm": [-100, 0], "radius_cm": 32, "surface_id": "f"}]}]}
	var made := Solid.with_hands(level.duplicate(true))
	var stage: Dictionary = made.stages[0]
	_check(Solid.of(stage.levers[0]) == Solid.HAND and Solid.of(stage.levers[1]).is_empty(), "with_hands makes a lever solid where it fits and leaves a catwalk's plain")
	_check(Solid.of(stage.controls[0]) == Solid.HAND, "with_hands works a control's footprint out again by the rule")
	_check(not stage.pressure_pads[0].has("solid"), "A pad stays a spot a pip stands on")
	_check(Canonical.same(Solid.with_hands(made.duplicate(true)), made), "with_hands gives the same definition again")
	_check(Solid.within_reach(stage.levers[0], Vector2i(52, 0), BODY) and not Solid.within_reach(stage.levers[0], Vector2i(53, 0), BODY), "A hand control is worked from up to 52 cm off its centre")
	_check(Solid.blocked([stage.levers[0]], Vector2i(31, 0), BODY) and not Solid.blocked([stage.levers[0]], Vector2i(32, 0), BODY), "A pip's centre keeps 32 cm off a hand control's")

## Nothing on the control's floor that stops a pip lies within its reach.
func _check_clear(level: Dictionary, control: Dictionary, where: String) -> void:
	var solid := Solid.of(control)
	var reach := float(int(solid.radius_cm) + BODY + int(solid.reach_cm))
	var at := Vector2(float(control.position_cm[0]), float(control.position_cm[1]))
	for list: String in ["obstacles", "access_zones"]:
		for item: Dictionary in level.get(list, []):
			if str(item.get("surface_id", "")) != str(control.surface_id): continue
			var r: Array = item.rect_cm
			var nearest := Vector2(clampf(at.x, minf(r[0], r[2]), maxf(r[0], r[2])), clampf(at.y, minf(r[1], r[3]), maxf(r[1], r[3])))
			_check(at.distance_to(nearest) > reach, "%s: %s %s stands within its reach, so it could be worked through it" % [where, list, item.get("id", "")])

## The control can be worked from walkable free floor, and the free floor
## round its footprint is one piece.
func _check_control(level: Dictionary, routes: Dictionary, cells: Dictionary, solids: Array, control: Dictionary, slot: String, where: String) -> void:
	var centre := Vector2i(int(control.position_cm[0]), int(control.position_cm[1]))
	var surface := str(control.surface_id)
	var height := int(control.get("height_cm", _floor_height(level, surface)))
	var keep := int(Solid.of(control).radius_cm) + BODY
	var reach := keep + int(Solid.of(control).reach_cm)
	var stands := 0
	var boundary: Array[Vector2i] = []
	var nodes := {}
	var span := reach / STEP + 1
	for i in range(-span, span + 1):
		for j in range(-span, span + 1):
			var point := centre + Vector2i(i, j) * STEP
			var found := Navigation.at(level, routes, {}, {"height": height, "surface_id": surface}, point.x, point.y, slot, BODY, false, cells)
			if found.is_empty() or _blocked(solids, found): continue
			nodes[point] = found
			if str(found.surface_id) == surface and int(found.height) == height and Solid.within_reach(control, point, BODY): stands += 1
			# Free floor beside the footprint: what a pip walking past it skirts.
			if str(found.surface_id) == surface and point.distance_squared_to(centre) <= (keep + STEP * 2) * (keep + STEP * 2): boundary.append(point)
	if slot == "p0" or stands == 0:
		_check(stands > 0, "%s: no free floor within reach for %s" % [where, slot])
	if boundary.size() < 2: return
	var reached := _walk(level, routes, cells, solids, boundary[0], nodes[boundary[0]], slot, boundary)
	_check(reached, "%s: its footprint cuts the floor round it in two for %s" % [where, slot])

## Whether every point of `wanted` is reached from `start` over free floor.
func _walk(level: Dictionary, routes: Dictionary, cells: Dictionary, solids: Array, start: Vector2i, state: Dictionary, slot: String, wanted: Array[Vector2i]) -> bool:
	var left := {}
	for point: Vector2i in wanted: left[point] = true
	left.erase(start)
	var seen := {_key(start, state): true}
	var queue: Array = [[start, state]]
	var head := 0
	while head < queue.size() and not left.is_empty():
		if head >= MOST_NODES: return false
		var at: Vector2i = queue[head][0]
		var from: Dictionary = queue[head][1]
		head += 1
		for offset: Vector2i in [Vector2i(STEP, 0), Vector2i(-STEP, 0), Vector2i(0, STEP), Vector2i(0, -STEP)]:
			var next := at + offset
			var found := Navigation.at(level, routes, {}, from, next.x, next.y, slot, BODY, false, cells)
			if found.is_empty() or _blocked(solids, found): continue
			var key := _key(next, found)
			if seen.has(key): continue
			seen[key] = true
			left.erase(next)
			queue.append([next, found])
	return left.is_empty()

## A spot a pip stands at keeps free floor inside it.
func _check_spot(level: Dictionary, routes: Dictionary, cells: Dictionary, solids: Array, spot: Dictionary, slot: String, where: String) -> void:
	var centre := Vector2i(int(spot.position_cm[0]), int(spot.position_cm[1]))
	var radius := int(spot.get("radius_cm", 28))
	var near := solids.any(func(solid: Dictionary) -> bool:
		var keep := int(Solid.of(solid).radius_cm) + BODY + radius
		return str(solid.get("surface_id", "")) == str(spot.surface_id) and centre.distance_squared_to(Vector2i(int(solid.position_cm[0]), int(solid.position_cm[1]))) < keep * keep)
	if not near: return
	var surface := str(spot.surface_id)
	var height := int(spot.get("height_cm", _floor_height(level, surface)))
	var span := radius / STEP
	for i in range(-span, span + 1):
		for j in range(-span, span + 1):
			var point := centre + Vector2i(i, j) * STEP
			if point.distance_squared_to(centre) > radius * radius: continue
			var found := Navigation.at(level, routes, {}, {"height": height, "surface_id": surface}, point.x, point.y, slot, BODY, false, cells)
			if not found.is_empty() and str(found.surface_id) == surface and not _blocked(solids, found): return
	_check(false, "%s: a hand control's footprint leaves no floor to stand on inside it for %s" % [where, slot])

## A goal's plate halves (presentation/kit/pieces/goal.gd), one per pip: the
## middle of each lies inside the goal's radius with a pip's body to spare, so
## a pip standing in the middle of its half is at the goal, and that middle is
## floor that pip stands on, on the goal's floor, clear of every solid
## footprint. Returns how many halves it checked.
func _check_goal_pads(level: Dictionary, routes: Dictionary, cells: Dictionary, solids: Array, stage: Dictionary, where: String) -> int:
	var goal: Variant = stage.get("goal")
	if not goal is Dictionary or not goal.has("surface_id") or str(stage.get("goal_policy", {}).get("kind", "")) != "ring": return 0
	var radius := float(goal.radius_cm)
	var surface := str(goal.surface_id)
	var height := int(goal.get("height_cm", _floor_height(level, surface)))
	for slot: String in GoalPiece.PAD_SLOTS:
		var offset := GoalPiece.pad_offset(slot, radius)
		_check(offset.length() + BODY <= radius, "%s: the middle of %s's goal half lies inside the goal" % [where, slot])
		var centre := Vector2i(int(goal.position_cm[0]) + roundi(offset.x), int(goal.position_cm[1]) + roundi(offset.z))
		var found := Navigation.at(level, routes, {}, {"height": height, "surface_id": surface}, centre.x, centre.y, slot, BODY, false, cells)
		_check(not found.is_empty() and str(found.surface_id) == surface and not _blocked(solids, found), "%s: %s's goal pad stands on floor that pip stands on" % [where, slot])
	return GoalPiece.PAD_SLOTS.size()

func _stand_spots(level: Dictionary, stage: Dictionary) -> Array:
	var spots: Array = []
	for list: String in SPOT_LISTS:
		for spot: Variant in stage.get(list, []):
			if spot is Dictionary and spot.has("surface_id"): spots.append(spot)
	if stage.get("goal") is Dictionary and stage.goal.has("surface_id"): spots.append(stage.goal)
	for spot: Variant in level.get("item_spots", []):
		if spot is Dictionary and spot.has("surface_id") and Solid.of(spot).is_empty(): spots.append(spot)
	var starts: Variant = level.get("starts", {})
	if starts is Dictionary:
		for slot: String in starts:
			var start: Variant = starts[slot]
			if start is Dictionary and start.has("surface_id"): spots.append({"id": "start " + slot, "position_cm": start.position_cm, "surface_id": start.surface_id, "radius_cm": BODY, "height_cm": int(start.get("height_cm", 0))})
	return spots

func _blocked(solids: Array, at: Dictionary) -> bool:
	var floor := str(at.surface_id)
	return Solid.blocked(solids.filter(func(spot: Dictionary) -> bool: return str(spot.get("surface_id", "")) == floor), Vector2i(int(at.x), int(at.z)), BODY)

func _floor_height(level: Dictionary, surface: String) -> int:
	for island: Dictionary in level.get("islands", []):
		if str(island.id) == surface: return int(island.get("height_cm", 0))
	return 0

static func _key(point: Vector2i, state: Dictionary) -> String:
	return "%d,%d,%s" % [point.x, point.y, state.surface_id]

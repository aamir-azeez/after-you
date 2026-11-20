extends SceneTree
## The level checker's view half: every stage of every chapter laid out as
## floors and crossings, built as its world on an 800x360 view (a phone held
## sideways), with a pip standing at each control, lever, pad and goal in turn
## (tests/level_tools/stage_shots.gd), the camera framed by the world's own
## follow rule and the bubbles placed by its own placement. A failure names
## the chapter, the stage, the spot and what went wrong:
##  - the spot itself lies outside the view (or within EDGE_PX of its edge);
##  - a selector's own bubble is cut off by the view's edge while its pip
##    stands at it;
##  - two bubbles on the view overlap;
##  - a refusal with no cause shown: an end of an owned crossing with no owner
##    gate, a stair that can be closed with neither its chain nor the world's
##    own drawing of it (a folding stair, water: the world's skip(), with why),
##    or a stretch of an owned zone's edge with no rope
##    (presentation/kit/route_barriers.gd). A gap, a folded piece and water
##    are the world's own; everything else is a barrier;
##  - a pip inside a wall: every spot a pip can stand (the engine's own
##    Navigation.at, its walk radius, every crossing open), near each floor's
##    edge, keeps its walk circle out of every wall that stands up beside it
##    (the water kit's walls, each floor's walls down to the water);
##  - a wall that holds nothing: a wall standing up over a floor's edge faces
##    water that can rise over that floor (else it is a fender);
##  - a boat that leaks: every boat on a water world floats by the float rule
##    (kit/floats.gd), its keel in the water and its inside floor over it at
##    every level its water stands at and all through its bob, and no boat
##    prop stands over water unfloated;
##  - a stone that vanishes: a stepping stone that is down (shut, or pushed
##    under by a drowning) stays in view just under its water, and a drowning
##    on it shows the shared drown (kit/drowning.gd).
## KNOWN lists what fails on purpose, by the start of its message, with why;
## an entry that stops failing fails the suite. The definitions-only half is
## tests/test_level_checker.gd.
const Registry = preload("res://services/chapter_registry.gd")
const Stages = preload("res://tests/level_tools/level_stages.gd")
const Shots = preload("res://tests/level_tools/stage_shots.gd")
const LabelBubble = preload("res://presentation/kit/label_bubble.gd")
const RouteBarriers = preload("res://presentation/kit/route_barriers.gd")
const LevelGraph = preload("res://tests/level_graph.gd")
const Navigation = preload("res://core/cooperative/navigation.gd")
const WaterBodies = preload("res://presentation/kit/water_bodies.gd")
## The engine's walk radius (cm, core/physical/runtime.gd PLAYER_RADIUS).
const WALK_RADIUS := 12
## A wall may touch a walk circle by this much (cm: a coping's 2.5 cm lip
## over the edge), and counts only while it stands this far (m) over the
## pip's floor and starts under its head.
const WALL_TOUCH := 3.0
const WALL_OVER := 0.06
const PIP_TALL := 0.85
## A wall standing this far (m) over a floor beside it is a wall, not a fender.
const WALL_UP := 0.30
## How far in from a floor's edge (cm) spots are tried, and how far apart.
const EDGE_BAND := 24
const EDGE_STEP := 4
const Floats = preload("res://presentation/kit/floats.gd")
const Props = preload("res://presentation/kit/props.gd")
const Models = preload("res://presentation/kit/models.gd")
## Bob phases tried round a boat's full heave.
const BOB_STEPS := 16
const VIEW := Vector2i(800, 360)
## A spot this close to the view's edge (px) counts as outside it.
const EDGE_PX := 16.0
## Bubbles overlapping by less than this (px squared) only touch.
const OVERLAP_PX2 := 16.0
## Known failures, matched by the start of the failure id: {prefix: why}.
const KNOWN := {}
var checks := 0
var failures := 0
var _found: Dictionary = {}
var _spots := 0
var _bubbles_seen := 0
## Spots off the view while the pip stands at its start: proof the framing
## check can fail at all.
var _off_view := 0
## Selector bubbles cut by the view's edge while the pips stand at their
## starts: proof the bubble check can fail at all.
var _cut_from_start := 0
## Refusals a world with no barriers would leave unexplained: proof the
## barrier check can fail at all.
var _unshown := 0
var _refusals_seen := 0
## Wall checks made (walk spots against walls) and walls beside floors seen:
## proof the wall checks ran on the water worlds.
var _wall_spots := 0
var _walls_by_floors := 0
## Boats and stepping stones checked on the water worlds.
var _boats_seen := 0
var _stones_seen := 0
## The rowboat model's floorboards (its "inside" slot), read once.
var _rowboat_floor := NAN

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = VIEW
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	for key: String in _keys():
		var started := Time.get_ticks_msec()
		await _chapter(viewport, key)
		print("LEVEL VIEW: %s in %d ms" % [key, Time.get_ticks_msec() - started])
	_check(_spots > 80 and _bubbles_seen > 100, "The view checks stand a pip at every spot (%d), with bubbles in view (%d)" % [_spots, _bubbles_seen])
	_check(_off_view > 0, "From the starts, some spots lie off the view, so the framing check can fail (%d)" % _off_view)
	_check(_cut_from_start > 0, "From the starts, some selector bubbles are cut by the view's edge, so the bubble check can fail (%d)" % _cut_from_start)
	_check(_meets(Rect2(0, 0, 60, 30), Rect2(50, 10, 60, 30)) and not _meets(Rect2(0, 0, 60, 30), Rect2(61, 0, 60, 30)), "Bubbles that share a corner overlap; bubbles side by side do not")
	_check(_boats_seen >= 5 and _stones_seen >= 1, "Every water world's boats float by the float rule (%d boats on stages) and its stepping stones go under, never away (%d)" % [_boats_seen, _stones_seen])
	_check(_wall_spots > 1000 and _walls_by_floors > 20, "The wall checks stand pips by the water worlds' walls (%d spots) and read the walls beside floors (%d)" % [_wall_spots, _walls_by_floors])
	_check(_refusals_seen > 50 and _unshown > 50, "Every refusal is checked for a shown cause (%d), and a world with no barriers leaves many unexplained, so the check can fail (%d)" % [_refusals_seen, _unshown])
	for prefix: String in KNOWN:
		_check(_found.has(prefix), "Known failure still fails, or comes off the list: %s (%s)" % [prefix, KNOWN[prefix]])
	print("LEVEL VIEW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The chapters this suite walks: every registered chapter (each family lays
## its stages out; the level checker fails one that does not); a split suite
## narrows it.
func _keys() -> Array[String]:
	return Registry.keys()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _expect(ok: bool, id: String, message: String) -> void:
	if not ok:
		for prefix: String in KNOWN:
			if id.begins_with(prefix):
				_found[prefix] = true
				print("KNOWN: %s (%s)" % [message, KNOWN[prefix]])
				ok = true
				break
	_check(ok, message)

func _chapter(viewport: SubViewport, key: String) -> void:
	var level := Registry.definition(key)
	var world: Node3D = Registry.world_script(key).new()
	viewport.add_child(world)
	world.set_process(false)
	world.configure_camera_exploration(func() -> bool: return false, func(_point: Vector2) -> bool: return false)
	await world.load_level(level)
	for item: Dictionary in Stages.stages(key, level):
		var view: Dictionary = item.view
		var where := "%s %s" % [key, view.stage_id]
		_check(not item.checkpoint.is_empty(), "%s: the stage opens from a saved checkpoint" % where)
		if item.checkpoint.is_empty(): continue
		var ends := _route_ends(view)
		await world.show_stage(item.stage)
		world.present_history(item.opening)
		_walls(world, where, view)
		_barriers(world, where, view, item.checkpoint, ends)
		var shots := Shots.new(key, level, str(view.stage_id), item.opening)
		var base := shots.snapshot()
		_check(not base.is_empty(), "%s: the engine opens the stage" % where)
		if base.is_empty(): continue
		_present(world, base)
		_floats(world, where)
		_current_marks(world, where, view)
		_stones(world, where, base)
		for spot: Dictionary in shots.spots():
			if not _inside(world, spot.entity): _off_view += 1
			if spot.kind == "selector" and "_journey_switches" in world and world._journey_switches.has(spot.id):
				var own: Rect2 = (world._journey_switches[spot.id].bubble as LabelBubble).screen_rect(world.camera)
				if not Rect2(Vector2.ZERO, Vector2(VIEW)).encloses(own): _cut_from_start += 1
		for spot: Dictionary in shots.spots():
			_present(world, shots.snapshot(shots.beside({}, spot.entity, spot.slot)))
			_look(world, where, spot)
			_spots += 1
	world.queue_free()
	await process_frame

## Shows `state` as the game's next frame would: an immediate present, then
## the placement pass it leaves due (what the world sets after it, its own
## levers and wheels, is read by the next pass).
static func _present(world: Node3D, state: Dictionary) -> void:
	world.present(state, true)
	world._frame_camera()

## Where the entity's floor point lands on the view (px).
static func _shown(world: Node3D, entity: Dictionary) -> Vector2:
	return world.camera.unproject_position(world.terrain.to_global(world._at(entity)))

static func _inside(world: Node3D, entity: Dictionary) -> bool:
	return Rect2(Vector2.ZERO, Vector2(VIEW)).grow(-EDGE_PX).has_point(_shown(world, entity))

func _look(world: Node3D, where: String, spot: Dictionary) -> void:
	var camera: Camera3D = world.camera
	var screen := Rect2(Vector2.ZERO, Vector2(VIEW))
	var label := "%s %s" % [spot.kind, spot.id]
	_expect(_inside(world, spot.entity), "%s %s framing" % [where, label], "%s: with its pip at the %s, it lies outside the view at %s px" % [where, label, _shown(world, spot.entity).round()])
	if not "_bubbles" in world: return
	var boxes: Array = []
	for bubble: Node in world._bubbles:
		if not is_instance_valid(bubble) or not (bubble as Node3D).is_visible_in_tree(): continue
		var box: Rect2 = (bubble as LabelBubble).screen_rect(camera)
		if box.has_area() and box.intersects(screen): boxes.append([bubble, box])
	_bubbles_seen += boxes.size()
	if spot.kind == "selector" and world._journey_switches.has(spot.id):
		var own: LabelBubble = world._journey_switches[spot.id].bubble
		var box := own.screen_rect(camera)
		_expect(box.has_area() and screen.encloses(box), "%s %s bubble cut" % [where, label], "%s: with its pip at the %s, its bubble is cut off by the view's edge at %s" % [where, label, _px(box)])
	for a in range(boxes.size()):
		for b in range(a + 1, boxes.size()):
			var meet: Rect2 = (boxes[a][1] as Rect2).intersection(boxes[b][1])
			_expect(not _meets(boxes[a][1], boxes[b][1]), "%s %s bubbles overlap" % [where, label], "%s: with a pip at the %s, the bubbles of %s and %s overlap (%s)" % [where, label, _name(world, boxes[a][0]), _name(world, boxes[b][0]), _px(meet)])

## Every refusal of the stage shows its cause in the built world (its route
## barriers' layout and the stairs it draws itself), and the same check finds
## them unexplained in a world that builds no barriers.
func _barriers(world: Node3D, where: String, view: Dictionary, checkpoint: Dictionary, ends: Dictionary) -> void:
	var kit: Variant = world.get("route_barriers")
	_check(kit != null, "%s: the world keeps route barriers" % where)
	if kit == null: return
	var kept: Array = checkpoint.get("mechanisms", {}).get("latched_bridges", [])
	_refusals_seen += _unexplained(where, view, kit.placed(), kit.skips(), kept, ends, true)
	for mouth: Dictionary in kit.placed().get("mouths", []):
		var clash: Array = mouth.get("clash", [])
		_expect(clash.is_empty(), "%s crossing %s posts" % [where, mouth.route], "%s: a post of the gate at the %s end of %s stands in %s" % [where, "%s" % mouth.get("floor", ""), mouth.route, ", ".join(clash)])
	_unshown += _unexplained(where, view, {"mouths": [], "spans": []}, {}, kept, ends, false)

## How many refusals of `view` show no cause with `placed` barriers and the
## world's `skips`; with `report`, each is a failure naming the chapter, the
## stage, the crossing or zone, and the pip refused.
func _unexplained(where: String, view: Dictionary, placed: Dictionary, skips: Dictionary, kept: Array, ends: Dictionary, report: bool) -> int:
	var floors := RouteBarriers.floors_of(view)
	var count := 0
	var seen := 0
	for kind: String in ["bridges", "stairs"]:
		for route: Dictionary in view.get(kind, []):
			var id := str(route.id)
			var owner := str(route.get("owner_slot", ""))
			var closes: bool = kind == "stairs" and id not in kept
			# The floors the engine lets a pip step to from this crossing, were
			# owners no rule (tests/level_graph.gd): each needs its cause shown.
			for end: String in ends.get(id, {}):
				var built: Array = placed.get("mouths", []).filter(func(found: Dictionary) -> bool: return found.route == id and str(found.get("floor", "")) == end)
				if not owner.is_empty():
					seen += 1
					var other := "p1" if owner == "p0" else "p0"
					var shown := built.any(func(found: Dictionary) -> bool: return found.owner == owner)
					if not shown: count += 1
					if report: _expect(shown, "%s crossing %s %s gate" % [where, id, end], "%s: the %s %s refuses %s at its end on %s and nothing there shows why (no owner gate)" % [where, kind.trim_suffix("s"), id, other, end])
				if closes:
					seen += 1
					var shown := skips.has(id) or built.any(func(found: Dictionary) -> bool: return bool(found.stair_gate))
					if not shown: count += 1
					if report: _expect(shown, "%s crossing %s %s chain" % [where, id, end], "%s: the stair %s, closed, refuses both pips at its end on %s and nothing there shows why (no chain, and the world draws nothing of its own)" % [where, id, end])
	for zone: Dictionary in view.get("access_zones", []):
		var owner := str(zone.get("owner_slot", ""))
		if owner.is_empty(): continue
		var other := "p1" if owner == "p0" else "p0"
		var wanted := RouteBarriers.zone_edges(zone, view, floors).size()
		var built: int = placed.get("spans", []).filter(func(found: Dictionary) -> bool: return found.zone == str(zone.get("id", ""))).size()
		seen += wanted
		if built < wanted: count += wanted - built
		if report: _expect(built >= wanted, "%s zone %s rope" % [where, zone.get("id", "")], "%s: the zone %s refuses %s along %d stretches of its edge and only %d show a rope" % [where, zone.get("id", ""), other, wanted, built])
	return seen if report else count

## No pip stands inside a wall, and no wall stands over a floor's edge with
## nothing to hold: the water kit's walls (parapets, sea walls, crossing and
## lock walls) and each floor's walls down to the water, against every spot the
## engine lets a pip stand near a floor's edge.
func _walls(world: Node3D, where: String, view: Dictionary) -> void:
	var kit: Variant = world.get("waters")
	if kit == null or kit.water.is_empty(): return
	var walls: Array = []
	var to_terrain: Transform3D = world.terrain.global_transform.affine_inverse()
	for box: AABB in kit.walls: walls.append([box, "water wall", ""])
	# The locks' capped walls and spillway stones.
	for stones: Node in world.terrain.find_children("WaterLockStone", "", true, false):
		for piece: Node in stones.find_children("*", "MeshInstance3D", true, false):
			walls.append([to_terrain * (piece as MeshInstance3D).global_transform * (piece as MeshInstance3D).get_aabb(), "a lock wall", ""])
	for island: Dictionary in view.get("islands", []):
		var wall := world.terrain.find_child(str(island.id) + "Wall", true, false) as MeshInstance3D
		if wall != null: walls.append([to_terrain * wall.global_transform * wall.get_aabb(), "the wall of " + str(island.id), str(island.id)])
	var cells := Navigation.index_for(view, "level-view " + where)
	var routes: Dictionary = {}
	for route: Dictionary in view.get("bridges", []) + view.get("stairs", []): routes[str(route.id)] = true
	var worst: Dictionary = {}
	for surface: Dictionary in view.get("islands", []) + view.get("bridges", []) + view.get("stairs", []):
		var r: Array = surface.rect_cm
		var reach := Rect2(float(r[0]), float(r[1]), float(r[2] - r[0]), float(r[3] - r[1])).grow(float(WALK_RADIUS) + 1.0)
		var beside: Array = walls.filter(func(entry: Array) -> bool: return entry[2] != str(surface.id) and reach.intersects(Rect2((entry[0] as AABB).position.x * 100.0, (entry[0] as AABB).position.z * 100.0, (entry[0] as AABB).size.x * 100.0, (entry[0] as AABB).size.z * 100.0)))
		if beside.is_empty(): continue
		for x in range(int(r[0]), int(r[2]) + 1, EDGE_STEP):
			for z in range(int(r[1]), int(r[3]) + 1, EDGE_STEP):
				if mini(mini(x - int(r[0]), int(r[2]) - x), mini(z - int(r[1]), int(r[3]) - z)) > EDGE_BAND: continue
				var start := Navigation.stair_height(surface, Vector2i(x, z)) if surface.has("axis") else int(surface.get("height_cm", 0))
				var at := Navigation.at(view, routes, {}, {"height": start}, x, z, "p0", WALK_RADIUS, false, cells)
				if at.is_empty() or str(at.surface_id) != str(surface.id): continue
				_wall_spots += 1
				var feet := float(at.height) / 100.0
				for entry: Array in beside:
					var box: AABB = entry[0]
					if box.end.y <= feet + WALL_OVER or box.position.y >= feet + PIP_TALL: continue
					var near := Vector2(clampf(x, box.position.x * 100.0, box.end.x * 100.0), clampf(z, box.position.z * 100.0, box.end.z * 100.0))
					var into := float(WALK_RADIUS) - Vector2(x, z).distance_to(near)
					var id := "%s %s in %s" % [where, surface.id, entry[1]]
					if into > WALL_TOUCH and into > float(worst.get(id, [0.0])[0]): worst[id] = [into, x, z, box]
	for id: String in worst:
		_expect(false, id, "%s: a pip standing at (%d, %d) runs %.0f cm into a wall at %s (%s)" % [id.get_slice(" ", 0) + " " + id.get_slice(" ", 1), worst[id][1], worst[id][2], worst[id][0], worst[id][3], id])
	# Each parapet that stands up over a floor's edge holds water that can rise over that floor.
	for parapet: Node in world.terrain.find_children("Parapet*", "MeshInstance3D", true, false):
		var box: AABB = to_terrain * (parapet as MeshInstance3D).global_transform * (parapet as MeshInstance3D).get_aabb()
		var centre := [box.get_center().x * 100.0, box.get_center().z * 100.0]
		var top := -INF
		for body: Dictionary in kit.open_bodies():
			if WaterBodies.covered(centre[0], centre[1], body.rects):
				for level: float in body.levels.values(): top = maxf(top, level)
		for island: Dictionary in view.get("islands", []):
			var r: Array = island.rect_cm
			var floor_top := float(island.get("height_cm", 0)) / 100.0
			if box.end.y < floor_top + WALL_UP: continue
			var flat := Rect2(box.position.x * 100.0, box.position.z * 100.0, box.size.x * 100.0, box.size.z * 100.0)
			if not flat.grow(3.0).intersects(Rect2(float(r[0]), float(r[1]), float(r[2] - r[0]), float(r[3] - r[1]))): continue
			_walls_by_floors += 1
			_expect(top > floor_top, "%s wall by %s" % [where, island.id], "%s: a wall stands %.2f m up beside %s, over water that never rises over that floor (its highest %.2f m): a fender, not a wall" % [where, box.end.y - floor_top, island.id, top])

## Every boat rides its water by the float rule at every level its water
## stands at and all through its bob: its keel in the water, its floorboards
## over it. No still boat prop stands over water.
func _floats(world: Node3D, where: String) -> void:
	var kit: Variant = world.get("waters")
	if kit == null or kit.water.is_empty(): return
	if is_nan(_rowboat_floor):
		var probe := Node3D.new()
		var model := Models.still(Props.ROWBOAT, "rowboat", Props.rowboat_colors(), probe, false)
		_rowboat_floor = (model.find_child("inside", false, false) as MeshInstance3D).get_aabb().end.y
		probe.free()
	for prop: Node in world.terrain.find_children("Prop_boat", "", true, false):
		var at: Vector3 = world.terrain.to_local((prop as Node3D).global_position) * 100.0
		var over: String = kit.body_of([at.x, at.z, at.x, at.z])
		var dry: bool = world.current_level.get("islands", []).any(func(island: Dictionary) -> bool: return WaterBodies._inside([at.x, at.z], island.rect_cm))
		_check(dry or over.is_empty(), "%s: a boat prop stands over the %s water at (%d, %d) without floating: the water world floats every boat" % [where, over, at.x, at.z])
	var spec: Dictionary = Floats.kind("rowboat")
	var reduced: bool = world.reduced_motion
	world.reduced_motion = false
	for boat: Node3D in world._boats:
		_boats_seen += 1
		var water := ""
		for rider: Array in kit._riders:
			if (rider[1] as Callable).get_bound_arguments().has(boat): water = str(rider[0])
		_check(not water.is_empty(), "%s: a boat at %s rides no water" % [where, boat.position])
		var hull := boat.find_child("rowboat", true, false) as Node3D
		var floor_at: float = (hull.transform * AABB(Vector3(0, _rowboat_floor, 0), Vector3.ZERO)).position.y if hull != null else 0.0
		var low := INF
		var high := -INF
		for level: float in kit.levels_of(water).values():
			for step in range(BOB_STEPS):
				world._clock = float(step) / float(BOB_STEPS) * TAU / float(spec.rate)
				world._float_boat(level, boat)
				low = minf(low, boat.position.y + floor_at - level)
				high = maxf(high, boat.position.y - level)
		_check(low >= Floats.MARGIN - 0.0001 and high < 0.0, "%s: a boat on the %s water keeps its floorboards %.3f m over the water and its keel %.3f m under it at every level and bob (floor at least %.2f over, keel under)" % [where, water, low, -high, Floats.MARGIN])
	world.reduced_motion = reduced

## A current's marks lie on the water, never on a floor or a crossing: no
## mark's corner stands more than a mark's half length inside one.
func _current_marks(world: Node3D, where: String, view: Dictionary) -> void:
	var piece: Variant = world.get("_current_piece")
	if piece == null: return
	for marks: Node in (piece.root as Node3D).find_children("Marks", "MeshInstance3D", true, false):
		var mesh := marks as MeshInstance3D
		var to_terrain: Transform3D = world.terrain.global_transform.affine_inverse() * mesh.global_transform
		var points: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var inside := ""
		for vertex: Vector3 in points:
			var at := to_terrain * vertex * 100.0
			for surface: Dictionary in view.get("islands", []) + view.get("bridges", []) + view.get("stairs", []):
				var r: Array = surface.rect_cm
				if at.x > float(r[0]) + 9.0 and at.x < float(r[2]) - 9.0 and at.z > float(r[1]) + 9.0 and at.z < float(r[3]) - 9.0: inside = str(surface.id)
		_check(inside.is_empty(), "%s: a current's mark lies on %s, not on the water" % [where, inside])

## A stepping stone that is down stays in view just under its water, at once
## for a snap and by sinking otherwise; a drowning on it shows the shared drown.
func _stones(world: Node3D, where: String, base: Dictionary) -> void:
	var stones: Variant = world.get("_stones")
	if stones == null: return
	for id: String in stones:
		_stones_seen += 1
		var stone: Dictionary = stones[id]
		var deck: Node3D = stone.deck
		var down := base.duplicate(true)
		down.bridges[id] = false
		world.present(down, true)
		var body: Node3D = world.waters.bodies.get(str(stone.water))
		var level: float = float(body.get_meta("shown")) if body != null else float(stone.rest)
		_check(deck.is_visible_in_tree() and deck.position.y <= minf(float(stone.rest), level - world.STONE_UNDER) + 0.001 and deck.position.y > level - 0.3, "%s: the stone %s, down, stays in view just under its water (top %.2f, water %.2f)" % [where, id, deck.position.y, level])
		var up := base.duplicate(true)
		up.bridges[id] = true
		world.present(up, true)
		var rest_y := deck.position.y
		var sunk := up.duplicate(true)
		sunk["drowned"] = {"slot": "p0", "route": id, "tick": 1}
		world.present(sunk, false)
		var start_y := deck.position.y
		world._advance_water(0.1)
		_check(deck.is_visible_in_tree() and deck.position.y < start_y and deck.position.y > float(stone.y) - 0.001 and is_equal_approx(start_y, rest_y), "%s: the stone %s sinks under a pip pushing it under, in view" % [where, id])
		_check(world.drowning.slot == "p0" and world.drowning.ring.visible and world.actor_targets.p0.y < level, "%s: a drowning on the stone %s shows the shared drown: the pip under the water, a ring spreading" % [where, id])
		world.present(up, true)
		_check(world.drowning.slot.is_empty() and is_equal_approx(deck.position.y, rest_y), "%s: without the drowning the stone %s stands again" % [where, id])
		world.present(base, true)

## Crossing ends found so far, by the stage floors they were read from.
var _ends_by_floors: Dictionary = {}

## Each crossing's ends as the engine walks them: route id -> {floor id: true},
## the floors a pip can step to from it once no crossing has an owner. Read
## from the stage's plan (its floors, as the level checker reads them), so
## every family is walked alike.
func _route_ends(view: Dictionary) -> Dictionary:
	var bare: Dictionary = {}
	for field: String in ["islands", "bridges", "stairs", "drops", "obstacles", "access_zones"]: bare[field] = view.get(field, []).duplicate(true)
	for kind: String in ["bridges", "stairs"]:
		for route: Dictionary in bare.get(kind, []): route.erase("owner_slot")
	var id := JSON.stringify(bare)
	if _ends_by_floors.has(id): return _ends_by_floors[id]
	var graph: RefCounted = LevelGraph.new(bare)
	var ends: Dictionary = {}
	for pair: String in graph.build("p0"):
		var sides := pair.split(">")
		for index in range(2):
			if graph.route_bit.has(sides[index]): (ends.get_or_add(sides[index], {}) as Dictionary)[sides[1 - index]] = true
	_ends_by_floors[id] = ends
	return ends

## Whether two bubble boxes overlap by more than a touch.
static func _meets(a: Rect2, b: Rect2) -> bool:
	return a.intersection(b).get_area() >= OVERLAP_PX2

## A bubble's name for a message: its selector, else what it says.
static func _name(world: Node3D, bubble: LabelBubble) -> String:
	for id: String in world._journey_switches:
		if world._journey_switches[id].bubble == bubble: return "the %s selector" % id
	return "\"%s\"" % bubble.labels[0].text if not bubble.labels.is_empty() else "a bubble"

static func _px(box: Rect2) -> String:
	return "(%d, %d) to (%d, %d) px" % [roundi(box.position.x), roundi(box.position.y), roundi(box.end.x), roundi(box.end.y)]

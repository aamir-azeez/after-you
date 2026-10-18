extends SceneTree
## Water locks (presentation/kit/water_locks.gd): placed from a world's water
## alone. On small plans: a door where a walkway meets water that can differ
## and match, a wall where water meets open air or a floor elsewhere, a
## spillway where two waters always differ, nothing where the sides always
## match; doors rise while their sides differ and sink while they match, and
## rest without work once settled; a raised door dips while a spirit stands in
## its mouth and rises once it leaves. On Turn of the Tide: the number of
## pieces each stage gets, doors following the wheels, no water surface or
## flooded crossing running into a door, no work on idle frames, kept
## crossings never showing an empty pit, a kept door dipping for a spirit the
## same way live, sought and with reduced motion, and the definition
## unchanged. Every other chapter builds no locks.
const WaterLocks = preload("res://presentation/kit/water_locks.gd")
const Registry = preload("res://services/chapter_registry.gd")
const JourneyCatalog = preload("res://core/journey/stage_catalog.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const LighthouseWorld = preload("res://presentation/lighthouse_world.gd")
const LightCatalog = preload("res://core/lighthouse/stage_catalog.gd")
const KEY := "turn-of-the-tide@1"
const LIGHTHOUSE := "sleeping-lighthouse@1"
## Pieces per Turn of the Tide stage: {kind: count}.
const TIDE_PIECES := {"set-the-tide": {"door": 22, "wall": 4}, "slack-water": {"door": 27, "wall": 10}}
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_small_plans()
	await _tide()
	await _sand_bar_not_kept()
	_other_chapters()
	print("WATER LOCKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

# --- Small plans ---

## Two basins side by side, x 0..100 and 100..200, both 100 wide in z, with a
## walkway across their shared edge when `mouth`.
func _basins(states: Array, mouth: bool) -> Dictionary:
	return {"areas": [{"id": "west", "kind": "water", "rects": [[0, 0, 100, 100]]}, {"id": "east", "kind": "water", "rects": [[100, 0, 200, 100]]},
		{"id": "rim", "kind": "floor", "rects": [[-50, -50, 250, 0], [-50, 100, 250, 150], [-50, 0, 0, 100], [200, 0, 250, 100]], "height": 1.0}],
		"bounds": [-50, -50, 250, 150], "mouths": [{"id": "walk", "rect": [80, 0, 120, 100]}] if mouth else [], "walls": [], "states": states, "seabed": -0.5, "wall_top": 0.8}

func _kinds(plan: Dictionary) -> Dictionary:
	var counts := {}
	for run: Dictionary in WaterLocks.find_runs(plan): counts[run.kind] = int(counts.get(run.kind, 0)) + 1
	return counts

func _small_plans() -> void:
	var level := {"west": 0.2, "east": 0.2}
	var apart := {"west": 0.6, "east": 0.2}
	_check(_kinds(_basins([level, apart], true)) == {"door": 1}, "A walkway between two waters that can differ and match gets one door")
	_check(_kinds(_basins([level, apart], false)) == {"wall": 1}, "Two waters that can differ and match, with no walkway between them, get a wall")
	_check(_kinds(_basins([apart, {"west": 0.7, "east": 0.1}], false)) == {"spill": 1}, "Two waters that always differ get a spillway")
	_check(_kinds(_basins([level, {"west": 0.4, "east": 0.4}], true)).is_empty(), "Waters that always match get nothing")
	var open_air := _basins([level], false)
	open_air.areas = [open_air.areas[0]]
	_check(_kinds(open_air) == {"wall": 4}, "Water that ends against open air gets a wall on each open side")
	var held := _basins([level, apart], true)
	held.walls = [AABB(Vector3(0.99, -0.5, 0.0), Vector3(0.02, 1.4, 1.0))]
	_check(_kinds(held).is_empty(), "A wall already standing on the edge needs nothing more")
	# A door rises while its sides differ and sinks while they match.
	var locks: WaterLocks = WaterLocks.new()
	var parent := Node3D.new()
	root.add_child(parent)
	locks.build(_basins([level, apart], true), parent)
	locks.present(apart, true)
	_check(locks.door_states() == ["shut"], "The door is up while the two waters differ")
	locks.present(level, true)
	_check(locks.door_states() == ["open"], "The door is down while the two waters match")
	parent.free()
	_small_dip(_basins([level, apart], true), level, apart)
	# Walls only a centimetre above the high water: the door, capped at that
	# height, still comes to rest while it holds the water.
	var low_walls := _basins([level, apart], true)
	low_walls.wall_top = 0.61
	var capped: WaterLocks = WaterLocks.new()
	var capped_parent := Node3D.new()
	root.add_child(capped_parent)
	capped.build(low_walls, capped_parent)
	capped.present(level, true)
	capped.present(apart, false)
	for _frame in range(120): capped.advance(1.0 / 60.0, apart)
	var door: MeshInstance3D = capped.door_nodes()[0]
	_check(not capped.moving() and capped.door_states() == ["shut"] and is_equal_approx(door.position.y, 0.61), "A door held under low walls rests at its shut height")
	capped_parent.free()
	# A spillway shows its sheet while the higher water stands over its lip.
	var spill_plan := _basins([apart, {"west": 0.7, "east": 0.1}], false)
	var spill: WaterLocks = WaterLocks.new()
	var holder := Node3D.new()
	root.add_child(holder)
	spill.build(spill_plan, holder)
	var sheet := spill.find_child("SpillSheet", true, false) as MeshInstance3D
	spill.present(apart, true)
	_check(sheet != null and sheet.visible, "Water falls over a spillway while the higher side stands over its lip")
	spill.present({"west": 0.3, "east": 0.3}, true)
	_check(sheet != null and not sheet.visible, "No water falls while both sides stand under the lip")
	holder.free()

## A raised door dips while a spirit stands in its mouth, easing down in about
## 0.2 s, and rises again once the spirit leaves; told at once it snaps. A
## spirit outside the walkway, or at a door that is down, changes nothing.
func _small_dip(plan: Dictionary, level: Dictionary, apart: Dictionary) -> void:
	var locks: WaterLocks = WaterLocks.new()
	var parent := Node3D.new()
	root.add_child(parent)
	locks.build(plan, parent)
	locks.present(apart, true)
	var door: MeshInstance3D = locks.door_nodes()[0]
	var inside := PackedVector2Array([Vector2(110, 50)])
	locks.occupy(PackedVector2Array([Vector2(50, 50)]))
	_check(locks.door_states() == ["shut"] and not locks.moving(), "A spirit outside the walkway leaves the door up")
	locks.occupy(inside)
	_check(locks.door_states() == ["dipped"] and locks.moving(), "A spirit in the mouth sets the raised door dipping")
	for _frame in range(12): locks.advance(1.0 / 60.0, apart)
	var shut := float(locks.runs[0].shut)
	_check(not locks.moving() and not door.visible and door.position.y < shut, "The door is down out of the way within 0.2 s")
	locks.occupy(PackedVector2Array())
	_check(locks.door_states() == ["shut"] and locks.moving(), "Once the spirit leaves the door rises")
	for _frame in range(12): locks.advance(1.0 / 60.0, apart)
	_check(not locks.moving() and door.visible and is_equal_approx(door.position.y, shut), "The door is back up within 0.2 s")
	locks.occupy(inside, true)
	_check(not locks.moving() and not door.visible and door.position.y < shut, "Told at once, the door snaps down")
	locks.occupy(PackedVector2Array(), true)
	locks.present(level, true)
	locks.occupy(inside)
	_check(locks.door_states() == ["open"] and not locks.moving(), "A spirit at a door that is down changes nothing")
	parent.free()

# --- Turn of the Tide ---

func _tide() -> void:
	var level := Registry.definition(KEY)
	var digest := Canonical.digest(level)
	for index in range(level.stages.size()):
		var stage: Dictionary = level.stages[index]
		var checkpoint := _checkpoint(level, index)
		var world: Node3D = Registry.world_script(KEY).new()
		root.add_child(world)
		world.load_level(level)
		await world.show_stage(stage)
		world.present_history(checkpoint)
		var locks: WaterLocks = _locks(world)
		_check(locks != null, "Turn of the Tide builds its locks: " + str(stage.id))
		if locks == null:
			world.free()
			continue
		var counts := {}
		for run: Dictionary in locks.runs: counts[run.kind] = int(counts.get(run.kind, 0)) + 1
		_check(counts == TIDE_PIECES[stage.id], "Each stage gets its pieces from its water: %s %s" % [stage.id, counts])
		var sim := Simulation.new()
		sim.simulation_version = 9
		sim._reset_trusted(level, str(stage.id), checkpoint, {}, "a")
		for tide: String in ["low", "half", "high"]:
			sim._mechanisms.controls["tide"] = tide
			sim._refresh_routes()
			var state: Dictionary = sim.snapshot()
			world.present(state, true)
			_doors_follow(locks, state, tide, "%s %s" % [stage.id, tide])
			_no_water_in_doors(world, locks, "%s %s" % [stage.id, tide])
		await _idle(world, locks, sim, str(stage.id))
		_rise_and_sink(world, locks, sim, stage)
		_every_edge_covered(world, locks, str(stage.id))
		_kept_crossings(world, locks, sim, stage)
		_never_empty(world, sim, stage)
		_kept_door_dips(world, locks, sim, stage)
		world.free()
	_check(Canonical.digest(level) == digest, "Building and showing the locks never changes the definition")

func _checkpoint(level: Dictionary, index: int) -> Dictionary:
	var checkpoint := JourneyCatalog.initial_checkpoint(level)
	# The sand bar and slipway are kept (entered earlier): walked while flooded.
	checkpoint.mechanisms.latched_bridges = ["sand-1", "slipway"]
	if index == 0: return checkpoint
	checkpoint.stage_index = index
	checkpoint.completed_stage_id = str(level.stages[index - 1].id)
	checkpoint.next_stage_id = str(level.stages[index].id)
	checkpoint.players = {"p0": {"x": 192, "z": -512, "height": 96, "surface_id": "wheel-step"}, "p1": {"x": 1440, "z": 0, "height": 48, "surface_id": "r-terrace"}}
	return checkpoint

func _locks(world: Node3D) -> WaterLocks:
	for node: Node in world.terrain.get_children():
		if node is WaterLocks: return node
	return null

## At low water every door is down. At high water the stepping stones (open
## only at half) are flooded above the terraces, so both doors of each are up.
## At half the sand bar and slipway (open only at low) are flooded above the
## beaches, so theirs are up, and the stones can be walked, so theirs are down.
func _doors_follow(locks: WaterLocks, state: Dictionary, tide: String, label: String) -> void:
	match tide:
		"low": _check(not "shut" in locks.door_states(), "Every door is down at low water: " + label)
		"high":
			for id: String in ["stones-1", "stones-2", "stones-3"]:
				_check(_states_at(locks, id) == ["shut", "shut"], "Both doors of a flooded crossing are up: %s %s" % [label, id])
		"half":
			for id: String in ["sand-1", "slipway"]:
				if not bool(state.bridges.get(id, false)): _check(_states_at(locks, id) == ["shut", "shut"], "Both doors of a flooded crossing are up: %s %s" % [label, id])
			for id: String in ["stones-1", "stones-2", "stones-3"]:
				if bool(state.bridges.get(id, false)): _check(_states_at(locks, id) == ["open", "open"], "An open crossing's doors are down: %s %s" % [label, id])

## The door states of the openings onto one walkway, in build order.
func _states_at(locks: WaterLocks, mouth: String) -> Array:
	var found: Array = []
	var states := locks.door_states()
	var index := 0
	for run: Dictionary in locks.runs:
		if run.kind != WaterLocks.DOOR: continue
		if run.mouth == mouth: found.append(states[index])
		index += 1
	return found

## No water surface or flooded crossing reaches into a door's footprint.
func _no_water_in_doors(world: Node3D, locks: WaterLocks, label: String) -> void:
	var doors: Array = []
	var prints: Array = locks.footprints()
	for index in range(locks.runs.size()):
		if locks.runs[index].kind == WaterLocks.DOOR:
			var f: Array = prints[index]
			doors.append(Rect2(float(f[0]) / 100.0, float(f[1]) / 100.0, float(f[2] - f[0]) / 100.0, float(f[3] - f[1]) / 100.0))
	var crossing := 0
	for body: Node3D in world._water.values():
		var water := body.get_node_or_null("Water") as MeshInstance3D
		if water != null:
			var vertices: PackedVector3Array = water.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for index in range(0, vertices.size(), 3):
				var area := Rect2(Vector2(vertices[index].x, vertices[index].z), Vector2.ZERO).expand(Vector2(vertices[index + 1].x, vertices[index + 1].z)).expand(Vector2(vertices[index + 2].x, vertices[index + 2].z))
				for door: Rect2 in doors:
					var overlap := area.intersection(door)
					if overlap.size.x > 0.001 and overlap.size.y > 0.001: crossing += 1
		for child: Node in body.get_children():
			if not str(child.name).begins_with("FloodedCrossing") or not (child as MeshInstance3D).visible: continue
			var flood := child as MeshInstance3D
			var size: Vector3 = (flood.mesh as BoxMesh).size
			var area := Rect2(Vector2(flood.position.x, flood.position.z) - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z))
			for door: Rect2 in doors:
				var overlap := area.intersection(door)
				if overlap.size.x > 0.001 and overlap.size.y > 0.001: crossing += 1
	_check(crossing == 0, "No water runs into a door: %s (%d)" % [label, crossing])

## Settled doors cost nothing: repeated snapshots and idle frames do no lock
## work at all. A turn of the tide moves doors; a snapshot shown at once snaps
## them; settled, each door rests on its target, shown only while up.
func _idle(world: Node3D, locks: WaterLocks, sim: Simulation, label: String) -> void:
	sim._mechanisms.controls["tide"] = "low"
	sim._refresh_routes()
	var low: Dictionary = sim.snapshot()
	world.present(low, true)
	var updates := locks.updates
	for _frame in range(20):
		world.present(low, false)
		await process_frame
	var frames := locks.frames
	world._advance_water(1.0 / 60.0)
	_check(locks.updates == updates and locks.frames == frames and not locks.moving(), "Idle frames and repeated snapshots do no lock work: " + label)
	sim._mechanisms.controls["tide"] = "high"
	sim._refresh_routes()
	var high: Dictionary = sim.snapshot()
	world.present(high, false)
	_check(locks.updates == updates + 1 and locks.moving(), "Turning the tide sets doors moving: " + label)
	world._advance_water(1.0 / 60.0)
	world.present(high, true)
	_check(not locks.moving() and _resting(locks), "A snapshot shown at once snaps travelling doors to their targets: " + label)
	world.present(low, false)
	for _frame in range(240): world._advance_water(1.0 / 60.0)
	_check(not locks.moving() and _resting(locks), "Doors come to rest on their targets after the tide turns: " + label)
	var settled := locks.frames
	world._advance_water(1.0 / 60.0)
	_check(locks.frames == settled, "A rested harbour does no lock work on the next frame: " + label)

## Every door stands at its target height, shown while up and hidden while down
## (open, or dipped for a spirit).
func _resting(locks: WaterLocks) -> bool:
	var states := locks.door_states()
	var nodes := locks.door_nodes()
	var doors := locks.runs.filter(func(run: Dictionary) -> bool: return run.kind == WaterLocks.DOOR)
	for index in range(nodes.size()):
		var door: MeshInstance3D = nodes[index]
		if states[index] == "shut" and (not door.visible or not is_equal_approx(door.position.y, float(doors[index].shut))): return false
		if states[index] != "shut" and (door.visible or door.position.y >= float(doors[index].shut) - 0.001): return false
	return true

## Every change of a wheel that moves water, frame by frame as it is shown:
## no door ever stands below the water it holds back, and the doors settle.
func _rise_and_sink(world: Node3D, locks: WaterLocks, sim: Simulation, stage: Dictionary) -> void:
	var wheels := {"tide": ["low", "half", "high"]}
	if str(stage.id) == "slack-water": wheels["basin"] = ["shut", "low", "half", "high"]
	var worst := INF
	for wheel: String in wheels:
		for from: String in wheels[wheel]:
			for to: String in wheels[wheel]:
				if from == to: continue
				sim._mechanisms.controls[wheel] = from
				sim._refresh_routes()
				world.present(sim.snapshot(), true)
				sim._mechanisms.controls[wheel] = to
				sim._refresh_routes()
				var state: Dictionary = sim.snapshot()
				world.present(state, false)
				worst = minf(worst, _clearance(world, locks))
				for _frame in range(240):
					world._advance_water(1.0 / 60.0)
					worst = minf(worst, _clearance(world, locks))
				_check(not locks.moving() and _resting(locks), "Doors settle after %s turns %s to %s: %s" % [wheel, from, to, stage.id])
				# Turned back while the water is still on its way: still never below it.
				world.present(sim.snapshot(), true)
				sim._mechanisms.controls[wheel] = from
				sim._refresh_routes()
				world.present(sim.snapshot(), true)
				sim._mechanisms.controls[wheel] = to
				sim._refresh_routes()
				world.present(sim.snapshot(), false)
				for _frame in range(15):
					world._advance_water(1.0 / 60.0)
					worst = minf(worst, _clearance(world, locks))
				sim._mechanisms.controls[wheel] = from
				sim._refresh_routes()
				var back: Dictionary = sim.snapshot()
				world.present(back, false)
				for _frame in range(240):
					world._advance_water(1.0 / 60.0)
					worst = minf(worst, _clearance(world, locks))
				_check(not locks.moving() and _resting(locks), "Doors settle after %s turns back from %s to %s mid-flow: %s" % [wheel, to, from, stage.id])
	_check(worst >= 0.0, "No door ever stands below the water it holds, on any turn of a wheel: %s (worst %.3f m)" % [stage.id, worst])
	sim._mechanisms.controls["tide"] = "low"
	if wheels.has("basin"): sim._mechanisms.controls["basin"] = "shut"
	sim._refresh_routes()
	world.present(sim.snapshot(), true)

## The least height by which any door's top clears the water on its wet side
## this frame, among doors holding water above the other side; INF if none.
func _clearance(world: Node3D, locks: WaterLocks) -> float:
	var shown: Dictionary = world._lock_levels("shown")
	var nodes := locks.door_nodes()
	var least := INF
	var index := 0
	for run: Dictionary in locks.runs:
		if run.kind != WaterLocks.DOOR: continue
		var door: MeshInstance3D = nodes[index]
		index += 1
		for side: String in [str(run.a), str(run.b)]:
			if not shown.has(side): continue
			var water := float(shown[side])
			var other := _floor_or_water(world, str(run.b) if side == str(run.a) else str(run.a), shown)
			if water > other + WaterLocks.LEVEL and water > float(run.top) + WaterLocks.LEVEL: least = minf(least, door.position.y - water)
	return least

func _floor_or_water(world: Node3D, id: String, shown: Dictionary) -> float:
	if shown.has(id): return float(shown[id])
	for island: Dictionary in world.chapter_definition.islands:
		if "island:" + str(island.id) == id: return float(island.height_cm) / 100.0
	return world.SEABED

## The sweep: every water edge that any single set of levels (every tide,
## sea and chamber, gated crossings dry and flooded) leaves standing over the
## other side with nothing holding it lies inside a piece built for it. A
## floor skipped, a run lost as a sliver or a misread mouth fails here.
func _every_edge_covered(world: Node3D, locks: WaterLocks, label: String) -> void:
	var plan: Dictionary = world._water_plan()
	var missing: Array[String] = []
	for state: Dictionary in plan.states:
		var single := plan.duplicate()
		single.states = [state]
		for edge: Dictionary in WaterLocks.find_runs(single):
			# The pieces on this line must cover the edge between them.
			var spans: Array = []
			for run: Dictionary in locks.runs:
				if run.along_x == edge.along_x and is_equal_approx(float(run.line), float(edge.line)): spans.append([float(run.from), float(run.to)])
			spans.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
			var reach := float(edge.from)
			for span: Array in spans:
				if float(span[0]) <= reach + 0.5: reach = maxf(reach, float(span[1]))
			if reach < float(edge.to) - 0.5: missing.append("%s|%s line %d %d..%d" % [edge.a, edge.b, roundi(float(edge.line)), roundi(float(edge.from)), roundi(float(edge.to))])
	# The single-state plans were cached; drop them so later checks start clean.
	WaterLocks._found.clear()
	_check(missing.is_empty(), "Every water edge any set of levels leaves unheld has a piece: %s %s" % [label, missing])

## The owner's rule for a crossing walked while the water covers it: dry while
## the water stands shallow over its deck (the sand bar and slipway at half,
## the terrace-high stones, stage and gate at high), flooded behind raised
## doors once it is deep (the sand bar and slipway at high).
const KEPT_SHOWN := {
	"half": {"sand-1": "dry", "slipway": "dry"},
	"high": {"sand-1": "flooded", "slipway": "flooded", "stones-1": "dry", "stones-2": "dry", "stones-3": "dry", "race-stage": "dry", "sea-gate-out": "dry"},
}

## Every crossing that can be kept is walled along each side no floor meets.
## Kept, it shows as the owner's rule says, its doors down while dry and up
## while flooded. Not kept and covered, it floods behind its raised doors as
## any shut crossing does.
func _kept_crossings(world: Node3D, locks: WaterLocks, sim: Simulation, stage: Dictionary) -> void:
	var kept: Array = world._kept_walled
	_check(not kept.is_empty(), "The stage has crossings it can keep: " + str(stage.id))
	for route: String in kept: _check(_walled_sides(world, route), "A crossing the stage can keep is walled along each open side: %s %s" % [stage.id, route])
	for tide: String in ["half", "high"]:
		sim._mechanisms.controls["tide"] = tide
		sim._refresh_routes()
		var plain: Dictionary = sim.snapshot()
		for route: String in kept:
			if not KEPT_SHOWN[tide].has(route): continue
			var state := plain.duplicate(true)
			state.bridges[route] = true
			world.present(state, true)
			var doors := _states_at(locks, route)
			var flooded: bool = KEPT_SHOWN[tide][route] == "flooded"
			_check(doors.size() == _mouth_count(world, route) and doors.all(func(door: String) -> bool: return door == ("shut" if flooded else "open")) and _resting(locks), "A kept crossing shows %s at %s: %s %s %s" % [KEPT_SHOWN[tide][route], tide, stage.id, route, doors])
			# Flooded, the water stands over the walkway behind its doors. Dry, the
			# water in its pit stands under the walkway: for stepping stones, 3 to
			# 5 cm under the stone tops, so they poke out of it.
			var calm: bool = world._calm[route].visible
			var water := _top(world._calm[route] if calm else world._floods[route])
			var stones: bool = world.DECK_KINDS.get(route, "") == "stones"
			var under := (_stone_top(world, route) if stones else float(world._low_cm(world._route(route))) / 100.0) - water
			var fits := under < 0.0 if flooded else (under >= 0.03 and under <= 0.05) if stones else under > 0.0
			_check(world._floods[route].visible != calm and fits, "A kept crossing shown %s has its water %.3f m under its walkway: %s %s %s" % [KEPT_SHOWN[tide][route], under, stage.id, tide, route])
		# Not kept (never latched here): covered, it floods behind raised doors.
		for route: String in kept:
			if route in world._latched_bridge_ids or not KEPT_SHOWN.high.has(route): continue
			var state := plain.duplicate(true)
			state.bridges[route] = false
			world.present(state, true)
			var covered: bool = float(world._floods[route].get_parent().get_meta("target")) > float(world._low_cm(world._route(route))) / 100.0
			var doors := _states_at(locks, route)
			_check(world._floods[route].visible and doors.size() == _mouth_count(world, route) and doors.all(func(door: String) -> bool: return door == ("shut" if covered else "open")), "A crossing not kept floods behind its doors: %s %s %s %s" % [stage.id, tide, route, doors])
	sim._mechanisms.controls["tide"] = "low"
	sim._refresh_routes()
	world.present(sim.snapshot(), true)

## A crossing that can be kept never shows an empty pit: at every tide, kept
## or not, either its flood or its calm water stands in it.
func _never_empty(world: Node3D, sim: Simulation, stage: Dictionary) -> void:
	for tide: String in ["low", "half", "high"]:
		sim._mechanisms.controls["tide"] = tide
		sim._refresh_routes()
		var plain: Dictionary = sim.snapshot()
		for route: String in world._kept_walled:
			for kept: bool in [true, false]:
				var state := plain.duplicate(true)
				state.bridges[route] = kept
				world.present(state, true)
				var calm: bool = world._calm[route].visible
				_check(world._floods[route].visible != calm, "A crossing that can be kept always holds water: %s %s %s kept %s" % [stage.id, tide, route, kept])
	sim._mechanisms.controls["tide"] = "low"
	sim._refresh_routes()
	world.present(sim.snapshot(), true)

## At high water the kept sand bar floods behind its raised doors; a spirit in
## one of its mouths dips that door (the other stays up) and leaving raises it
## again, each in about 0.2 s. The same positions shown at once, as a seek or
## replay does, give the same doors; reduced motion snaps them.
func _kept_door_dips(world: Node3D, locks: WaterLocks, sim: Simulation, stage: Dictionary) -> void:
	sim._mechanisms.controls["tide"] = "high"
	sim._refresh_routes()
	var away: Dictionary = sim.snapshot()
	away.bridges["sand-1"] = true
	away.players.p0.x = 1440
	away.players.p0.z = 0
	var door_index := -1
	var index := 0
	var spot := Vector2.ZERO
	var r: Array = world._route("sand-1").rect_cm
	var crossing := Rect2(float(r[0]), float(r[1]), float(r[2] - r[0]), float(r[3] - r[1]))
	for run: Dictionary in locks.runs:
		if run.kind != WaterLocks.DOOR: continue
		if run.mouth == "sand-1" and door_index < 0:
			door_index = index
			var middle := (float(run.from) + float(run.to)) * 0.5
			for step: float in [15.0, -15.0]:
				var at := Vector2(middle, float(run.line) + step) if run.along_x else Vector2(float(run.line) + step, middle)
				if crossing.has_point(at): spot = at
		index += 1
	var inside := away.duplicate(true)
	inside.players.p0.x = spot.x
	inside.players.p0.z = spot.y
	world.present(away, true)
	_check(_states_at(locks, "sand-1") == ["shut", "shut"], "The kept sand bar's doors are up at high water: " + str(stage.id))
	var door: MeshInstance3D = locks.door_nodes()[door_index]
	world.present(inside, false)
	_check(locks.door_states()[door_index] == "dipped" and _states_at(locks, "sand-1").count("shut") == 1, "A spirit in the kept sand bar's mouth dips that door alone: %s %s" % [stage.id, _states_at(locks, "sand-1")])
	for _frame in range(12): world._advance_water(1.0 / 60.0)
	var dipped_at := door.position.y
	_check(not locks.moving() and _resting(locks) and not door.visible, "The dipped door is out of the way within 0.2 s: %s (%.3f m)" % [stage.id, door.position.y])
	world.present(away, true)
	world.present(inside, true)
	_check(locks.door_states()[door_index] == "dipped" and is_equal_approx(door.position.y, dipped_at) and _resting(locks), "Shown at once, as a seek or replay does, the spirit's door is the same: " + str(stage.id))
	world.present(away, false)
	_check(locks.door_states()[door_index] == "shut", "Leaving the mouth raises the door: " + str(stage.id))
	for _frame in range(12): world._advance_water(1.0 / 60.0)
	_check(not locks.moving() and _resting(locks) and door.visible, "The door is back up within 0.2 s: " + str(stage.id))
	world.reduced_motion = true
	world.present(inside, false)
	_check(not locks.moving() and is_equal_approx(door.position.y, dipped_at) and _resting(locks), "With reduced motion the door snaps down: " + str(stage.id))
	world.present(away, false)
	_check(not locks.moving() and door.visible and _resting(locks), "With reduced motion the door snaps back up: " + str(stage.id))
	world.reduced_motion = false
	sim._mechanisms.controls["tide"] = "low"
	sim._refresh_routes()
	world.present(sim.snapshot(), true)

## The top of a mesh in world space (m).
func _top(mesh: MeshInstance3D) -> float:
	return (mesh.global_transform * mesh.get_aabb()).end.y

## The tops of a stepping-stone crossing's stones (m).
func _stone_top(world: Node3D, route: String) -> float:
	var top := -INF
	for stone: Node in world._decks[route].find_children("SteppingStone", "", true, false): top = maxf(top, _top(stone as MeshInstance3D))
	return top

## A crossing's doors: one at each floor it joins, so one for a stub.
func _mouth_count(world: Node3D, route: String) -> int:
	return 1 if world._is_stub(world._route(route)) else 2

## Whether a recorded water wall stands along each side of a crossing that no
## floor meets.
func _walled_sides(world: Node3D, route: String) -> bool:
	var r: Array = world._route(route).rect_cm
	var sides := [[true, float(r[1])], [true, float(r[3])], [false, float(r[0])], [false, float(r[2])]]
	for side: Array in sides:
		var along_x: bool = side[0]
		var line: float = side[1]
		var floor_met := false
		for island: Dictionary in world.chapter_definition.islands:
			var q: Array = island.rect_cm
			if along_x and (is_equal_approx(float(q[1]), line) or is_equal_approx(float(q[3]), line)) and float(q[0]) < float(r[2]) and float(q[2]) > float(r[0]): floor_met = true
			if not along_x and (is_equal_approx(float(q[0]), line) or is_equal_approx(float(q[2]), line)) and float(q[1]) < float(r[3]) and float(q[3]) > float(r[1]): floor_met = true
		if floor_met: continue
		var held := false
		for wall: AABB in world._water_walls:
			if wall.end.y < world.PARAPET_TOP - 0.01: continue
			var near: bool = absf((wall.get_center().z if along_x else wall.get_center().x) - line / 100.0) < 0.15
			var spans: bool = (wall.position.x < float(r[2]) / 100.0 and wall.end.x > float(r[0]) / 100.0) if along_x else (wall.position.z < float(r[3]) / 100.0 and wall.end.z > float(r[1]) / 100.0)
			if near and spans: held = true
		if not held: return false
	return true

## A sand bar nobody kept, from a stage that never latched it: covered at half
## and high, it floods behind its raised doors.
func _sand_bar_not_kept() -> void:
	var level := Registry.definition(KEY)
	var world: Node3D = Registry.world_script(KEY).new()
	root.add_child(world)
	world.load_level(level)
	await world.show_stage(level.stages[0])
	var checkpoint := JourneyCatalog.initial_checkpoint(level)
	world.present_history(checkpoint)
	var locks: WaterLocks = _locks(world)
	var sim := Simulation.new()
	sim.simulation_version = 9
	sim._reset_trusted(level, str(level.stages[0].id), checkpoint, {}, "a")
	for tide: String in ["half", "high"]:
		sim._mechanisms.controls["tide"] = tide
		sim._refresh_routes()
		world.present(sim.snapshot(), true)
		var doors := _states_at(locks, "sand-1")
		_check(world._floods["sand-1"].visible and doors == ["shut", "shut"], "A sand bar nobody kept floods behind its raised doors at %s: %s" % [tide, doors])
	world.free()

# --- Other chapters ---

func _other_chapters() -> void:
	for key: String in Registry.keys():
		if key.begins_with("turn-of-the-tide"): continue
		var world: Node3D = LighthouseWorld.new() if key == LIGHTHOUSE else Registry.world_script(key).new()
		root.add_child(world)
		world.process_mode = Node.PROCESS_MODE_DISABLED
		if key == LIGHTHOUSE:
			world.load_level(LightCatalog.definition(LightCatalog.STAGE_IDS[0]))
		else:
			var level := Registry.definition(key)
			world.load_level(level)
			if world.has_method("show_stage"): world.show_stage(level.stages[0])
		_check(world.find_children("WaterLocks", "", true, false).is_empty() and world.find_children("WaterLockStone", "", true, false).is_empty(), "No locks in a chapter without water levels: " + key)
		world.free()

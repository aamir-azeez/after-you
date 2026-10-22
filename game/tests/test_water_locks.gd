extends SceneTree
## Water locks (presentation/kit/water_locks.gd): placed from a world's water
## alone. On small plans: a door where a walkway meets water that can differ
## and match, a wall where water meets open air or a floor elsewhere, a
## spillway where two waters always differ, nothing where the sides always
## match; doors rise while their sides differ and sink while they match, and
## rest without work once settled; a raised door dips while a spirit stands in
## its mouth and rises once it leaves. On Turn of the Tide: the number of
## pieces each stage gets, doors following the wheels, no water surface running
## into a door, no work on idle frames, every walled crossing a sealed pit that
## never holds water, stepping stones unwalled in the open water and exactly
## the lever stubs open under their water walled, a door dipping for a spirit the same way live, sought and with
## reduced motion (and never for a walkway nobody may walk), and the definition
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
const TIDE_PIECES := {"set-the-tide": {"door": 14, "wall": 4}, "slack-water": {"door": 6, "wall": 10}}
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
	await _unwalkable_mouth()
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
## spirit away from the mouth, at a walkway nobody may enter, or at a door that
## is down, changes nothing.
func _small_dip(plan: Dictionary, level: Dictionary, apart: Dictionary) -> void:
	var locks: WaterLocks = WaterLocks.new()
	var parent := Node3D.new()
	root.add_child(parent)
	locks.build(plan, parent)
	locks.present(apart, true)
	var door: MeshInstance3D = locks.door_nodes()[0]
	var inside := PackedVector2Array([Vector2(110, 50)])
	var open := {"walk": true}
	locks.occupy(PackedVector2Array([Vector2(50, 50)]), open)
	_check(locks.door_states() == ["shut"] and not locks.moving(), "A spirit away from the mouth leaves the door up")
	locks.occupy(inside, {"walk": false})
	_check(locks.door_states() == ["shut"] and not locks.moving(), "A spirit at a walkway nobody may enter leaves its door up")
	locks.occupy(PackedVector2Array([Vector2(90, 50)]), open, true)
	_check(locks.door_states() == ["dipped"], "A spirit about to step through the mouth, on either side, dips the door")
	locks.occupy(PackedVector2Array(), open, true)
	locks.occupy(inside, open)
	_check(locks.door_states() == ["dipped"] and locks.moving(), "A spirit in the mouth sets the raised door dipping")
	for _frame in range(12): locks.advance(1.0 / 60.0, apart)
	var shut := float(locks.runs[0].shut)
	_check(not locks.moving() and not door.visible and door.position.y < shut, "The door is down out of the way within 0.2 s")
	locks.occupy(PackedVector2Array(), open)
	_check(locks.door_states() == ["shut"] and locks.moving(), "Once the spirit leaves the door rises")
	for _frame in range(12): locks.advance(1.0 / 60.0, apart)
	_check(not locks.moving() and door.visible and is_equal_approx(door.position.y, shut), "The door is back up within 0.2 s")
	locks.occupy(inside, open, true)
	_check(not locks.moving() and not door.visible and door.position.y < shut, "Told at once, the door snaps down")
	locks.occupy(PackedVector2Array(), open, true)
	locks.present(level, true)
	locks.occupy(inside, open)
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
			_doors_follow(world, locks, tide, "%s %s" % [stage.id, tide])
			_no_water_in_doors(world, locks, "%s %s" % [stage.id, tide])
		await _idle(world, locks, sim, str(stage.id))
		_rise_and_sink(world, locks, sim, stage)
		_every_edge_covered(world, locks, str(stage.id))
		_sealed_pits(world, locks, sim, stage)
		_in_open_water(world, stage)
		_kept_door_dips(world, locks, sim, stage)
		world.free()
	_check(Canonical.digest(level) == digest, "Building and showing the locks never changes the definition")

func _checkpoint(level: Dictionary, index: int) -> Dictionary:
	var checkpoint := JourneyCatalog.initial_checkpoint(level)
	# The sand bar, slipway and middle stones are kept (entered earlier): walked
	# while the water covers them.
	checkpoint.mechanisms.latched_bridges = ["sand-1", "slipway", "stones-2"]
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

## At low water every door is down. At high water the water stands over the
## terraces, so both doors of each set of stepping stones are up, kept or not;
## at half the stones can be walked, so theirs are down. A walled crossing is a
## sealed pit and has no door at all.
func _doors_follow(world: Node3D, locks: WaterLocks, tide: String, label: String) -> void:
	match tide:
		"low": _check(not "shut" in locks.door_states(), "Every door is down at low water: " + label)
		"high":
			for id: String in ["stones-1", "stones-2", "stones-3"]:
				_check(_states_at(locks, id) == ["shut", "shut"], "Both doors of stepping stones under water are up: %s %s" % [label, id])
		"half":
			for id: String in ["stones-1", "stones-2", "stones-3"]:
				_check(_states_at(locks, id) == ["open", "open"], "Stepping stones above the water have their doors down: %s %s" % [label, id])
	for id: String in world._walled:
		_check(_states_at(locks, id).is_empty(), "A walled crossing is sealed and has no door: %s %s" % [label, id])

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

## No water surface reaches into a door's footprint.
func _no_water_in_doors(world: Node3D, locks: WaterLocks, label: String) -> void:
	var doors: Array[Rect2] = []
	var prints: Array = locks.footprints()
	for index in range(locks.runs.size()):
		if locks.runs[index].kind == WaterLocks.DOOR:
			var f: Array = prints[index]
			doors.append(Rect2(float(f[0]) / 100.0, float(f[1]) / 100.0, float(f[2] - f[0]) / 100.0, float(f[3] - f[1]) / 100.0))
	_check(_water_over(world, doors) == 0, "No water runs into a door: %s (%d)" % [label, _water_over(world, doors)])

## How many water surface faces of the bodies reach into any of `areas` (m,
## seen from above).
func _water_over(world: Node3D, areas: Array[Rect2]) -> int:
	var count := 0
	for body: Node3D in world._water.values():
		var water := body.get_node_or_null("Water") as MeshInstance3D
		if water == null: continue
		var vertices: PackedVector3Array = water.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for index in range(0, vertices.size(), 3):
			var face := Rect2(Vector2(vertices[index].x, vertices[index].z), Vector2.ZERO).expand(Vector2(vertices[index + 1].x, vertices[index + 1].z)).expand(Vector2(vertices[index + 2].x, vertices[index + 2].z))
			for area: Rect2 in areas:
				var overlap := face.intersection(area)
				if overlap.size.x > 0.001 and overlap.size.y > 0.001: count += 1
	return count

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
	var worst := INF
	var wheels := _wheels(stage)
	for wheel: String in wheels:
		for from: String in wheels[wheel]:
			for to: String in wheels[wheel]:
				if from == to: continue
				sim._mechanisms.controls[wheel] = from
				sim._refresh_routes()
				world.present(sim.snapshot(), true)
				sim._mechanisms.controls[wheel] = to
				sim._refresh_routes()
				world.present(sim.snapshot(), false)
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
				world.present(sim.snapshot(), false)
				for _frame in range(240):
					world._advance_water(1.0 / 60.0)
					worst = minf(worst, _clearance(world, locks))
				_check(not locks.moving() and _resting(locks), "Doors settle after %s turns back from %s to %s mid-flow: %s" % [wheel, to, from, stage.id])
	_check(worst >= 0.0, "No door ever stands below the water it holds, on any turn of a wheel: %s (worst %.3f m)" % [stage.id, worst])
	_reset(world, sim, stage)

## The wheels that move water in a stage, with their values.
func _wheels(stage: Dictionary) -> Dictionary:
	var wheels := {"tide": ["low", "half", "high"]}
	if str(stage.id) == "slack-water": wheels["basin"] = ["shut", "low", "half", "high"]
	return wheels

## Back to low tide (and a shut sea), shown at once.
func _reset(world: Node3D, sim: Simulation, stage: Dictionary) -> void:
	sim._mechanisms.controls["tide"] = "low"
	if _wheels(stage).has("basin"): sim._mechanisms.controls["basin"] = "shut"
	sim._refresh_routes()
	world.present(sim.snapshot(), true)

## The floor a door's walkway opens onto (m): the higher floor beside it.
func _mouth_floor(world: Node3D, run: Dictionary) -> float:
	var floor_top := -INF
	for side: String in [str(run.a), str(run.b)]:
		if side.begins_with("island:"): floor_top = maxf(floor_top, _floor_or_water(world, side, {}))
	return floor_top

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

## The sweep: every water edge that any single set of levels (every tide, sea
## and chamber) leaves standing over the other side with nothing holding it
## lies inside a piece built for it. A floor skipped, a run lost as a sliver or
## a misread mouth fails here.
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

## Every walled crossing is a sealed pit: walled along each side no floor
## meets, never given water of its own by the plan, never touched by a lock
## piece, and with no water in it at any level of any wheel, open or shut,
## while the water stands or moves.
func _sealed_pits(world: Node3D, locks: WaterLocks, sim: Simulation, stage: Dictionary) -> void:
	var pits: Array[Rect2] = []
	for id: String in world._walled:
		_check(_walled_sides(world, id), "A walled crossing is walled along each open side: %s %s" % [stage.id, id])
		var r: Array = world._route(id).rect_cm
		pits.append(Rect2(float(r[0]) / 100.0, float(r[1]) / 100.0, float(r[2] - r[0]) / 100.0, float(r[3] - r[1]) / 100.0).grow(-0.01))
	var plan: Dictionary = world._water_plan()
	var named := 0
	for state: Dictionary in plan.states:
		for key: String in state:
			if key.begins_with("crossing:"): named += 1
	_check(named == 0, "No state gives a sealed pit water of its own: " + str(stage.id))
	var touching := locks.runs.filter(func(run: Dictionary) -> bool: return str(run.a).begins_with("crossing:") or str(run.b).begins_with("crossing:"))
	_check(touching.is_empty(), "No lock piece stands at a sealed pit: %s %d" % [stage.id, touching.size()])
	var wet := 0
	var wheels := _wheels(stage)
	for wheel: String in wheels:
		for value: String in wheels[wheel]:
			sim._mechanisms.controls[wheel] = value
			sim._refresh_routes()
			for open: bool in [true, false]:
				var state: Dictionary = sim.snapshot()
				for id: String in world._walled: state.bridges[id] = open
				world.present(state, false)
				for _frame in range(30):
					world._advance_water(1.0 / 60.0)
					wet += _water_over(world, pits)
					for body: Node3D in world._water.values():
						wet += body.get_children().filter(func(child: Node) -> bool: return child.name != "Water" and child is MeshInstance3D and (child as MeshInstance3D).visible).size()
	_check(wet == 0, "No water ever stands in a sealed pit: %s (%d)" % [stage.id, wet])
	_reset(world, sim, stage)

## Stepping stones are never walled, nor a stub (lever pad, post or catwalk)
## whose gate opens it only over dry water: they stand in the open channel, its
## water all round them. The posts and the gate and bar catwalks have gates
## that tie them to no tide value, so Slack Water can hold them open at high
## tide over their
## terrace-high decks, and the race stage can be kept (entered at low tide) and
## walked at high: those are walled dry like any crossing.
func _in_open_water(world: Node3D, stage: Dictionary) -> void:
	var walled_stubs: Array = world._walled.filter(func(id: String) -> bool: return world._is_stub(world._route(id)))
	walled_stubs.sort()
	var expected: Array = ["bar-catwalk", "boom-post", "gate-catwalk", "gate-post", "punt-post", "race-stage"] if str(stage.id) == "slack-water" else []
	_check(walled_stubs == expected, "Only the stubs open under their water are walled: %s %s" % [stage.id, walled_stubs])
	for route: Dictionary in world.chapter_definition.bridges:
		var id := str(route.id)
		var r: Array = route.rect_cm
		if not (world._is_stub(route) or world.DECK_KINDS.get(id, "") == "stones") or id in expected or world._gate_for_stage(stage, id).is_empty() or world._body_of(r).is_empty(): continue
		var area: Array[Rect2] = [Rect2(float(r[0]) / 100.0, float(r[1]) / 100.0, float(r[2] - r[0]) / 100.0, float(r[3] - r[1]) / 100.0).grow(-0.01)]
		_check(id not in world._walled and _water_over(world, area) > 0, "%s stands unwalled in the open water: %s" % [id, stage.id])

## At high water kept stepping stones stand under it, their raised doors
## holding it off the terraces; a spirit in one of their mouths dips that door
## (the other stays up) and leaving raises it again, each in about 0.2 s. The
## same positions shown at once, as a seek or replay does, give the same doors;
## reduced motion snaps them; the tide rising under a spirit in the mouth never
## shows its door above the floor.
func _kept_door_dips(world: Node3D, locks: WaterLocks, sim: Simulation, stage: Dictionary) -> void:
	sim._mechanisms.controls["tide"] = "high"
	sim._refresh_routes()
	var away: Dictionary = sim.snapshot()
	away.players.p0.x = 1440
	away.players.p0.z = 0
	_check(bool(away.bridges["stones-2"]), "Kept stones can be walked at high water: " + str(stage.id))
	var door_index := -1
	var index := 0
	var spot := Vector2.ZERO
	var r: Array = world._route("stones-2").rect_cm
	var crossing := Rect2(float(r[0]), float(r[1]), float(r[2] - r[0]), float(r[3] - r[1]))
	for run: Dictionary in locks.runs:
		if run.kind != WaterLocks.DOOR: continue
		if run.mouth == "stones-2" and door_index < 0:
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
	_check(_states_at(locks, "stones-2") == ["shut", "shut"], "The kept stones' doors are up at high water: " + str(stage.id))
	var door: MeshInstance3D = locks.door_nodes()[door_index]
	world.present(inside, false)
	_check(locks.door_states()[door_index] == "dipped" and _states_at(locks, "stones-2").count("shut") == 1, "A spirit in the kept stones' mouth dips that door alone: %s %s" % [stage.id, _states_at(locks, "stones-2")])
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
	# The tide rising under a spirit standing in the mouth never shows the door.
	sim._mechanisms.controls["tide"] = "low"
	sim._refresh_routes()
	var low_inside: Dictionary = sim.snapshot()
	low_inside.players = inside.players.duplicate(true)
	world.present(low_inside, true)
	world.present(inside, false)
	var floor_top := _mouth_floor(world, locks.runs.filter(func(run: Dictionary) -> bool: return run.kind == WaterLocks.DOOR)[door_index])
	var shown := door.visible and door.position.y > floor_top
	for _frame in range(240):
		world._advance_water(1.0 / 60.0)
		shown = shown or (door.visible and door.position.y > floor_top)
	_check(not shown and locks.door_states()[door_index] == "dipped", "The tide rising under a spirit in the mouth never shows the door above its floor: " + str(stage.id))
	_reset(world, sim, stage)

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

## A crossing that cannot be walked at high water (the west stepping stones,
## open only at half tide and not kept here): its raised doors stay up for a
## spirit waiting on the terrace at its mouth, and stay in view.
func _unwalkable_mouth() -> void:
	var level := Registry.definition(KEY)
	var world: Node3D = Registry.world_script(KEY).new()
	root.add_child(world)
	world.load_level(level)
	await world.show_stage(level.stages[1])
	var checkpoint := _checkpoint(level, 1)
	world.present_history(checkpoint)
	var locks: WaterLocks = _locks(world)
	var sim := Simulation.new()
	sim.simulation_version = 9
	sim._reset_trusted(level, str(level.stages[1].id), checkpoint, {}, "a")
	sim._mechanisms.controls["tide"] = "high"
	sim._mechanisms.controls["basin"] = "shut"
	sim._refresh_routes()
	var state: Dictionary = sim.snapshot()
	state.players.p1.x = -140
	state.players.p1.z = 0
	world.present(state, true)
	var doors := _states_at(locks, "stones-1")
	var shown := locks.door_nodes().filter(func(door: MeshInstance3D) -> bool: return door.visible).size()
	_check(not bool(state.bridges["stones-1"]) and not doors.is_empty() and doors.all(func(door: String) -> bool: return door == "shut") and shown == locks.door_states().count("shut"), "A crossing nobody may walk keeps its raised doors up for a spirit at its mouth: %s" % [doors])
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

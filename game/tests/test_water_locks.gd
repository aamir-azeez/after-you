extends SceneTree
## Water locks (presentation/kit/water_locks.gd): placed from a world's water
## alone. On small plans: a door where a walkway meets water that can differ
## and match, a wall where water meets open air or a floor elsewhere, a
## spillway where two waters always differ, nothing where the sides always
## match; doors rise while their sides differ and sink while they match, and
## rest without work once settled. On Turn of the Tide: the number of pieces
## each stage gets, doors following the wheels, no water surface or flooded
## crossing running into a door, no work on idle frames, and the definition
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
const TIDE_PIECES := {"set-the-tide": {"door": 22}, "slack-water": {"door": 27, "wall": 6}}
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
	locks.present(apart, {}, true)
	_check(locks.door_states() == ["shut"], "The door is up while the two waters differ")
	locks.present(level, {}, true)
	_check(locks.door_states() == ["open"], "The door is down while the two waters match")
	locks.present(apart, {"walk": true}, true)
	_check(locks.door_states() == ["open"], "A walkway that can be walked now keeps its door down")
	parent.free()
	# A spillway shows its sheet while the higher water stands over its lip.
	var spill_plan := _basins([apart, {"west": 0.7, "east": 0.1}], false)
	var spill: WaterLocks = WaterLocks.new()
	var holder := Node3D.new()
	root.add_child(holder)
	spill.build(spill_plan, holder)
	var sheet := spill.find_child("SpillSheet", true, false) as MeshInstance3D
	spill.present(apart, {}, true)
	_check(sheet != null and sheet.visible, "Water falls over a spillway while the higher side stands over its lip")
	spill.present({"west": 0.3, "east": 0.3}, {}, true)
	_check(sheet != null and not sheet.visible, "No water falls while both sides stand under the lip")
	holder.free()

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
		world.show_stage(stage)
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
		# A crossing that can be walked while flooded (a kept sand bar) keeps its doors down.
		sim._mechanisms.controls["tide"] = "half"
		sim._refresh_routes()
		var kept: Dictionary = sim.snapshot()
		kept.bridges["sand-1"] = true
		world.present(kept, true)
		_check(_states_at(locks, "sand-1") == ["open", "open"], "A walkable flooded crossing keeps both its doors down: " + str(stage.id))
		await _idle(world, locks, sim, str(stage.id))
		world.free()
	_check(Canonical.digest(level) == digest, "Building and showing the locks never changes the definition")

func _checkpoint(level: Dictionary, index: int) -> Dictionary:
	var checkpoint := JourneyCatalog.initial_checkpoint(level)
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

## Settled doors cost nothing a frame; a change moves them, then they rest.
func _idle(world: Node3D, locks: WaterLocks, sim: Simulation, label: String) -> void:
	sim._mechanisms.controls["tide"] = "low"
	sim._refresh_routes()
	var low: Dictionary = sim.snapshot()
	world.present(low, true)
	var changes := locks.changes
	for _frame in range(20):
		world.present(low, false)
		await process_frame
	_check(locks.changes == changes and not locks.moving() and not locks.advance(1.0 / 60.0), "Idle frames and repeated snapshots move no door: " + label)
	sim._mechanisms.controls["tide"] = "high"
	sim._refresh_routes()
	world.present(sim.snapshot(), false)
	_check(locks.changes > changes and locks.moving(), "Turning the tide sets doors moving: " + label)
	for _frame in range(240): locks.advance(1.0 / 60.0)
	_check(not locks.moving(), "Doors come to rest after the tide turns: " + label)
	var settled := locks.changes
	_check(not locks.advance(1.0 / 60.0) and locks.changes == settled, "A rested lock does no work on the next frame: " + label)

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

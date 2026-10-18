extends SceneTree
## Nothing the scenery fold folds is ever touched again. For every offered
## chapter that folds and each of its stages, an unfolded world is shown its
## stage as a chapter screen shows it, and StaticBatch.plan() names every leaf
## the world's fold would fold and the node its batch would go under. Then
## both of the stage's fixture turns play in normal motion, a snapshot every
## tick and a frame after each, and after every few ticks each planned leaf
## must be exactly as it was: in the tree, in the same place relative to its
## batch's node, shown (and so is everything between them), with the same
## mesh and the same material, colour, glow and see-through. A world that
## moves, hides, fades or recolours anything it folds fails here. Water locks'
## stone walls are planned to fold and their doors never are.
const Registry = preload("res://services/chapter_registry.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const Golden = preload("res://tests/golden_support.gd")
const ReplayGolden = preload("res://tests/test_replay_golden.gd")
const IslandWorld = preload("res://presentation/island_world.gd")
const DELTA := 1.0 / 60.0
const CHECK_EVERY := 10
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _chain(key: String) -> Array:
	for name: String in ReplayGolden.CHAINS.get(key, {}):
		var spec: Dictionary = ReplayGolden.CHAINS[key][name]
		if spec.has("stages"): return spec.stages
	for name: String in ReplayGolden.CHAINS.get(key, {}):
		var spec: Dictionary = ReplayGolden.CHAINS[key][name]
		if not spec.has("bundle") or not str(spec.get("entry", "")).is_empty(): continue
		var bundle := Golden.fixture(spec.bundle)
		if not bundle.get("pairs") is Array or not bundle.get("checkpoints") is Array or bundle.checkpoints.size() != bundle.pairs.size() + 1: continue
		var stages: Array = []
		for index in range(bundle.pairs.size()): stages.append([bundle.pairs[index].a, bundle.pairs[index].b, bundle.checkpoints[index + 1]])
		return stages
	return []

## A stage and its history, as the solo controllers show them.
func _history(world: Node3D, stage: Dictionary, checkpoint: Dictionary) -> void:
	if world.has_method("show_stage"): world.show_stage(stage)
	if world.has_method("present_history"): world.present_history(checkpoint)

## Every processing node under the world, in engine order.
func _processors(world: Node) -> Array:
	var found: Array = []
	_processing(world, found)
	var order: Array = []
	for index in range(found.size()): order.append([found[index].process_priority, index])
	order.sort()
	return order.map(func(item: Array) -> Node: return found[item[1]])

## One emulated frame of those nodes.
func _frame(nodes: Array) -> void:
	for node: Node in nodes:
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.is_inside_tree(): node._process(DELTA)

func _processing(node: Node, found: Array) -> void:
	if node.is_queued_for_deletion(): return
	if node.get_script() != null and node.has_method("_process") and node.is_processing(): found.append(node)
	for child: Node in node.get_children(): _processing(child, found)

## How a planned leaf stands now: [false, whether its batch's node is still
## there] once it has gone, else [true, transform relative to its
## batch's node, shown (it and everything up to that node), mesh, material
## (colour, glow, see-through; a fade copies a shared material, so not its
## identity), shadow]. The cutaway is the one change
## a batch shares with its leaves (kit/cutaway.gd fades a raised floor's
## batches like its pieces), so a faded leaf reads as unfaded, and only a leaf
## whose batch goes under its own container may be faded.
func _state(leaf: MeshInstance3D, base: Node3D, terrain: Node3D) -> Array:
	if not is_instance_valid(leaf) or not leaf.is_inside_tree(): return [false, is_instance_valid(base) and base.is_inside_tree()]
	var shown := true
	var node: Node = leaf
	while node != null and node != base:
		if node is Node3D and not (node as Node3D).visible: shown = false
		node = node.get_parent()
	var faded: bool = leaf.get_meta("cutaway", false)
	var material := leaf.material_override as StandardMaterial3D
	var tone: Array = []
	if material != null:
		var colour := material.albedo_color
		if faded: colour.a = 1.0
		tone = [colour, material.emission_enabled, material.emission, material.emission_energy_multiplier, BaseMaterial3D.TRANSPARENCY_DISABLED if faded else material.transparency]
	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if faded else leaf.cast_shadow
	return [true, base.global_transform.affine_inverse() * leaf.global_transform, shown, leaf.mesh.get_instance_id() if leaf.mesh != null else 0, tone, shadow, faded and base == terrain]

func _same(was: Array, now: Array) -> bool:
	# A leaf may go only with the node its batch would sit under (a rebuilt
	# container takes its batch along); gone from under a node that stays,
	# its batch would be left behind.
	if not now[0]: return not now[1]
	if was.size() != now.size(): return false
	if now[6]: return false
	var tone_same: bool = was[4].size() == now[4].size()
	for i in range(mini(was[4].size(), now[4].size())):
		var a: Variant = was[4][i]
		var b: Variant = now[4][i]
		if a is Color: tone_same = tone_same and (a as Color).is_equal_approx(b)
		elif a is float: tone_same = tone_same and is_equal_approx(a, b)
		else: tone_same = tone_same and a == b
	return (was[1] as Transform3D).is_equal_approx(now[1]) and was[2] == now[2] and was[3] == now[3] and tone_same and was[5] == now[5]

func _run() -> void:
	var tested := 0
	for key: String in Registry.offered_keys():
		if key not in IslandWorld.STATIC_FOLD_CHAPTERS: continue
		var stages := _chain(key)
		_check(not stages.is_empty(), key + ": fixture stages found")
		var level := Registry.definition(key)
		var engine: Script = Registry.simulation_script(key)
		var checkpoint := Registry.initial_checkpoint(key)
		var started := Time.get_ticks_msec()
		for index in range(stages.size()):
			var files: Array = stages[index]
			var a: Dictionary = files[0] if files[0] is Dictionary else Golden.fixture(files[0])
			var b: Dictionary = files[1] if files[1] is Dictionary else Golden.fixture(files[1])
			var name := "%s stage %d" % [key, index + 1]
			var world: Node3D = Registry.world_script(key).new()
			root.add_child(world)
			world.process_mode = Node.PROCESS_MODE_DISABLED
			GraphicsPolicy.apply(world, {"graphics_quality": "balanced"})
			world.configure_camera_exploration(func() -> bool: return false, func(_point: Vector2) -> bool: return false)
			world.load_level(level)
			var stage: Dictionary = engine.stage_by_id(level, str(a.stage_id))
			_history(world, stage, checkpoint)
			# Marked folded, so the world's own frames never fold it: it stays
			# the unfolded world the plan is checked against.
			world.terrain.set_meta(StaticBatch.FOLDED_META, true)
			var sims: Array = []
			for pair: Array in [[a, {}], [b, a]]:
				var sim: RefCounted = engine.new()
				sim.catch_assistance = bool(pair[0].get("catch_assistance", true))
				if Registry.reset_simulation(sim, key, level, str(pair[0].stage_id), checkpoint, pair[1], str(pair[0].role), pair[0]): sims.append([sim, engine.expand_recording_inputs(pair[0])])
			_check(sims.size() == 2, name + ": both fixture turns reset")
			if sims.size() < 2:
				world.free()
				break
			# As a chapter screen shows a stage before its fold starts.
			world.present(sims[0][0].snapshot(), true)
			for i in range(3): _frame(_processors(world))
			world.terrain.remove_meta(StaticBatch.FOLDED_META)
			var planned: Array = StaticBatch.plan(world.terrain, [world], world._fold_options())
			world.terrain.set_meta(StaticBatch.FOLDED_META, true)
			_check(planned.size() > 20, "%s: the fold plans to fold %d leaves" % [name, planned.size()])
			var terrain: Node3D = world.terrain
			# Water locks (kit/water_locks.gd): their stone walls fold with the
			# scenery; the doors that rise and fall, their posts and the water
			# sheets, all under the locks' own node, never fold.
			var locks: Variant = world.get("_locks")
			if locks is Node3D and is_instance_valid(locks):
				var stone := terrain.find_child("WaterLockStone", false, false)
				# A stage whose water meets only walkways has doors and no stone.
				_check(stone != null and (stone.get_child_count() == 0 or planned.any(func(entry: Array) -> bool: return stone.is_ancestor_of(entry[0]))), name + ": the water locks' stone walls, where the stage has any, fold")
				_check(not (locks as Node3D).door_nodes().is_empty() and not planned.any(func(entry: Array) -> bool: return (locks as Node3D).is_ancestor_of(entry[0])), name + ": no water-lock door, post or water sheet folds")
			var before: Array = planned.map(func(entry: Array) -> Array: return _state(entry[0], entry[1], terrain))
			var paths: Array = planned.map(func(entry: Array) -> String: return str(terrain.get_path_to(entry[0])))
			var untouched := true
			var where := ""
			var ticks := 0
			for turn: Array in sims:
				var sim: RefCounted = turn[0]
				var inputs: Array = turn[1]
				_history(world, stage, checkpoint)
				world.present(sim.snapshot(), true)
				var nodes := _processors(world)
				for tick in range(inputs.size()):
					world.present(sim.step(inputs[tick]))
					_frame(nodes)
					ticks += 1
					if tick % CHECK_EVERY != 0 and tick != inputs.size() - 1: continue
					# Nodes made in play (trails, beams) process from here on.
					nodes = _processors(world)
					for i in range(planned.size()):
						if not untouched: break
						var now := _state(planned[i][0], planned[i][1], terrain)
						if not _same(before[i], now):
							untouched = false
							where = "%s tick %d: %s\n  was %s\n  now %s" % ["B" if turn == sims[1] else "A", tick, paths[i], str(before[i]), str(now)]
				for i in range(60): _frame(nodes)
			_check(untouched, "%s: no planned leaf moves, hides or changes material across %d ticks %s" % [name, ticks, where])
			tested += 1
			world.free()
			checkpoint = files[2] if files[2] is Dictionary else Golden.fixture(files[2])
		print("fold_untouched %s: %d ms" % [key, Time.get_ticks_msec() - started])
	_check(tested >= 10, "Every folding chapter's stages were played (%d)" % tested)
	print("FOLD UNTOUCHED: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

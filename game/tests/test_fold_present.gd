extends SceneTree
## Every folded chapter world keeps working once its scenery is folded,
## whatever the timing. For each chapter and each of its stages, from the
## chapter's own fixture recordings, the same snapshots are shown on three
## worlds: one never folded; one folded to completion before the first
## snapshot; and one folded over frames a step at a time between snapshots
## (a screen's fold, with present() making nodes while the job runs, as the
## Lighthouse's beams are). After every snapshot each folded world must look
## like the unfolded one wherever anything changes: every node the world's
## variables name, and everything under them, in the same place, shown or
## hidden alike, in the same colour and glow, and every piece the terrain
## draws the same. Script errors fail the suite.
const Registry = preload("res://services/chapter_registry.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const Golden = preload("res://tests/golden_support.gd")
const ReplayGolden = preload("res://tests/test_replay_golden.gd")
const Light = preload("res://core/lighthouse/borrowed_light.gd")
const LightCatalog = preload("res://core/lighthouse/stage_catalog.gd")
const LighthouseWorld = preload("res://presentation/lighthouse_world.gd")
const FoldLook = preload("res://tests/fold_look.gd")
const LIGHTHOUSE := "sleeping-lighthouse@1"
const DELTA := 1.0 / 60.0
## Snapshots shown per stage: the start, then every this many ticks of the
## first recording, then its end.
const STRIDE := 45
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

func _native_chain(key: String) -> Dictionary:
	for name: String in ReplayGolden.CHAINS.get(key, {}):
		var spec: Dictionary = ReplayGolden.CHAINS[key][name]
		if spec.has("stages"): return spec
	for name: String in ReplayGolden.CHAINS.get(key, {}):
		var spec: Dictionary = ReplayGolden.CHAINS[key][name]
		if not spec.has("bundle") or not str(spec.get("entry", "")).is_empty(): continue
		var bundle := Golden.fixture(spec.bundle)
		if not bundle.get("pairs") is Array or not bundle.get("checkpoints") is Array or bundle.checkpoints.size() != bundle.pairs.size() + 1: continue
		var stages: Array = []
		for index in range(bundle.pairs.size()): stages.append([bundle.pairs[index].a, bundle.pairs[index].b, bundle.checkpoints[index + 1]])
		return {"stages": stages}
	return _own_chain(key)

## A chapter with no chain in test_replay_golden.gd yet (one in development):
## its own stage fixtures, where its family keeps them, once they are written.
func _own_chain(key: String) -> Dictionary:
	var prefix: String = Golden.fixture_prefixes(key).get("stages", "")
	var stages: Array = []
	for stage: Dictionary in Registry.definition(key).get("stages", []):
		var files: Array = []
		for suffix: String in ["-a.json", "-b.json", "-checkpoint.json"]: files.append(prefix + str(stage.id) + suffix)
		if prefix.is_empty() or not files.all(func(path: String) -> bool: return FileAccess.file_exists("res://tests/fixtures/" + path)): return {}
		stages.append(files)
	return {"stages": stages}

## Per stage: {stage, checkpoint, states}, from the chapter's fixtures.
func _stages(key: String) -> Array:
	var result: Array = []
	if key == LIGHTHOUSE:
		var fixture := Golden.fixture("lighthouse/complete-six-v3.json")
		var pairs: Array = fixture.get("pairs", [])
		var checkpoints: Array = fixture.get("checkpoints", [])
		for index in range(pairs.size()):
			var sim := Light.new()
			if not sim.reset("a", {}, pairs.slice(0, index), int(pairs[index].a.simulation_version)): break
			result.append({"stage": LightCatalog.definition(LightCatalog.STAGE_IDS[index]), "checkpoint": checkpoints[index], "states": _states(sim, Light.expand_recording_inputs(pairs[index].a))})
		return result
	var spec := _native_chain(key)
	var level := Registry.definition(key)
	var engine: Script = Registry.simulation_script(key)
	var checkpoint := Registry.initial_checkpoint(key)
	for files: Array in spec.get("stages", []):
		var a: Dictionary = files[0] if files[0] is Dictionary else Golden.fixture(files[0])
		var sim: RefCounted = engine.new()
		sim.catch_assistance = bool(a.get("catch_assistance", true))
		if not Registry.reset_simulation(sim, key, level, str(a.stage_id), checkpoint, {}, str(a.role), a): break
		result.append({"stage": engine.stage_by_id(level, str(a.stage_id)), "checkpoint": checkpoint, "states": _states(sim, engine.expand_recording_inputs(a))})
		checkpoint = files[2] if files[2] is Dictionary else Golden.fixture(files[2])
	return result

func _states(sim: RefCounted, frames: Array) -> Array:
	var states: Array = [sim.snapshot().duplicate(true)]
	for index in range(frames.size()):
		sim.step(frames[index])
		if index % STRIDE == STRIDE - 1 or index == frames.size() - 1: states.append(sim.snapshot().duplicate(true))
	return states

func _world(key: String, entry: Dictionary) -> Node3D:
	var world: Node3D = LighthouseWorld.new() if key == LIGHTHOUSE else Registry.world_script(key).new()
	root.add_child(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	GraphicsPolicy.apply(world, {"graphics_quality": "balanced"})
	world.reduced_motion = true
	if key == LIGHTHOUSE:
		world.load_level(entry.stage)
	else:
		world.load_level(Registry.definition(key))
		if world.has_method("show_stage"): world.show_stage(entry.stage)
	if world.has_method("present_history"): world.present_history(entry.checkpoint)
	return world

## Every named node, and every piece the terrain draws (tests/fold_look.gd).
func _named_look(world: Node3D) -> Array:
	return FoldLook.look(world)

## Whether two looks match; on the first mismatch, a few rows of each side.
func _same(expected: Array, actual: Array, label: String) -> bool:
	if expected == actual: return true
	var shown := 0
	for row: String in expected:
		if row not in actual and shown < 2:
			print("  %s, unfolded only: %s" % [label, row.substr(0, 240)])
			shown += 1
	shown = 0
	for row: String in actual:
		if row not in expected and shown < 2:
			print("  %s, folded only: %s" % [label, row.substr(0, 240)])
			shown += 1
	return false

func _show(world: Node3D, state: Dictionary, immediate: bool) -> void:
	# The world's own frame would move an over-frames fold on by a timed step:
	# here only the suite moves it, one piece of work at a time.
	world._fold_frame = Engine.get_process_frames()
	world.present(state.duplicate(true), immediate)
	for i in range(2): world._process(DELTA)

func _run() -> void:
	var keys: Array = []
	for key: String in Registry.keys():
		if key in LighthouseWorld.STATIC_FOLD_CHAPTERS: keys.append(key)
	keys.append(LIGHTHOUSE)
	for key: String in keys:
		var started := Time.get_ticks_msec()
		var stages := _stages(key)
		_check(not stages.is_empty(), key + ": fixture stages found")
		for index in range(stages.size()):
			var entry: Dictionary = stages[index]
			var name := "%s stage %d" % [key, index + 1]
			var plain := _world(key, entry)
			# Marked as folded, so it never folds.
			plain.terrain.set_meta(StaticBatch.FOLDED_META, true)
			var whole := _world(key, entry)
			var stepped := _world(key, entry)
			# Folded to completion before the first snapshot.
			if "_bubbles_placed" in whole: whole._bubbles_placed = true
			whole.fold_over_frames = false
			whole._fold_static_scenery()
			_check(whole.terrain.has_meta(StaticBatch.FOLDED_META) and not whole.scenery_folding(), name + ": folds to completion first")
			# Started as the world starts it, then moved on one piece of work
			# per snapshot, while present() keeps making and changing nodes.
			stepped.fold_over_frames = true
			stepped._fold_job = StaticBatch.start(stepped.terrain, [stepped], stepped._fold_options())
			_check(not stepped._fold_job.is_empty(), name + ": the stepped fold starts")
			var stepping := true
			var same_whole := true
			var same_stepped := true
			var where := ""
			var shown := 0
			for state: Dictionary in entry.states:
				var immediate := shown % 2 == 0
				for world: Node3D in [plain, whole, stepped]: _show(world, state, immediate)
				# One tiny step of the over-frames fold between snapshots.
				if stepping and not stepped._fold_job.is_empty():
					if StaticBatch.step(stepped._fold_job, 1): stepped._fold_job = {}
				stepping = not stepped._fold_job.is_empty()
				var look := _named_look(plain)
				if same_whole and not _same(look, _named_look(whole), name + " folded first"):
					same_whole = false
					where = "snapshot %d" % shown
				if same_stepped and not _same(look, _named_look(stepped), name + " folded between"):
					same_stepped = false
					where = "snapshot %d" % shown
				shown += 1
			# Finish the stepped fold, then show every snapshot again on all.
			while not stepped._fold_job.is_empty():
				if StaticBatch.step(stepped._fold_job, 0): stepped._fold_job = {}
			for state: Dictionary in entry.states:
				for world: Node3D in [plain, whole, stepped]: _show(world, state, true)
				var look := _named_look(plain)
				if same_whole and not _same(look, _named_look(whole), name + " folded first, replayed"):
					same_whole = false
					where = "replayed snapshot"
				if same_stepped and not _same(look, _named_look(stepped), name + " folded between, replayed"):
					same_stepped = false
					where = "replayed snapshot"
			_check(whole.terrain.find_children("StaticBatch*", "MeshInstance3D", true, false).size() > 0, name + ": the folded world has batches")
			_check(same_whole, "%s: folded first, every named node looks as unfolded across %d snapshots (%s)" % [name, shown, where])
			_check(same_stepped, "%s: folded between snapshots, every named node looks as unfolded across %d snapshots (%s)" % [name, shown, where])
			for world: Node3D in [plain, whole, stepped]: world.free()
		print("fold_present %s: %d ms" % [key, Time.get_ticks_msec() - started])
	await process_frame
	_check(preload("res://presentation/kit/primitives.gd").changed_shared_materials().is_empty(), "Every kit look shared between meshes is as it was made; code that changes a mesh's material takes its own copy (Primitives.own_material): %s" % [preload("res://presentation/kit/primitives.gd").changed_shared_materials()])
	print("FOLD PRESENT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

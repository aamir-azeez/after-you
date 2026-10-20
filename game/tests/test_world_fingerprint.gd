extends SceneTree
## Golden G3: a structural fingerprint of each chapter world's node tree at
## fixed moments of its published fixture replay, so a presentation refactor can
## prove "no visual change". Per node it records the class, the name (engine
## counters stripped), visibility, the global transform (mm, 1/1000), meshes,
## materials, labels, lights, environment and camera; nodes queued for deletion
## are skipped. Sibling order does not count: children are hashed as a sorted
## set. The child-order hash is advisory only and never fails the suite.
##
## Everything runs synchronously, so no engine frame ticks a world with wall-
## clock time. A frame is emulated by calling _process(1/60) on each processing
## node in engine order (process_priority, then tree order).
##
## Scenarios per stage (stage index s, fixture pair A then B), as the solo
## controller drives them: s.start (history, A reset, immediate, 30 frames),
## s.a.end (A's final snapshot, 60 frames), s.b.mid (B reset, B's halfway
## snapshot, 20 frames), s.b.below (physical chapters with a raised floor: the
## first B tick whose active player is under it, the cutaway case, 20 frames;
## its tick is recorded), s.b.end (B's final snapshot, 180 frames). The fixture
## replays run once per chapter; each chapter then runs a normal-motion pass
## twice in fresh worlds (determinism self-check) and a reduced-motion pass.
##
## Chapters are split over suites (SUITES) to stay inside CI's 120 s limit;
## each has tests/fixtures/golden/<suite>.json. A failure names the chapter,
## pass, scenario and top-level branch that changed. Set
## AFTER_YOU_FINGERPRINT_DUMP to a folder to write a readable dump of every
## fingerprint (one line per node), then diff two dumps to see the exact nodes.
## See tests/golden_support.gd to regenerate after an intended visual change.
const Golden = preload("res://tests/golden_support.gd")
const Registry = preload("res://services/chapter_registry.gd")
const ReplayGolden = preload("res://tests/test_replay_golden.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const Light = preload("res://core/lighthouse/borrowed_light.gd")
const LightCatalog = preload("res://core/lighthouse/stage_catalog.gd")
const LighthouseWorld = preload("res://presentation/lighthouse_world.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
const LIGHTHOUSE := "sleeping-lighthouse@1"
const LIGHTHOUSE_FIXTURE := "lighthouse/complete-six-v3.json"
const DUMP_ENV := "AFTER_YOU_FINGERPRINT_DUMP"
const DELTA := 1.0 / 60.0
## Every pinned chapter is fingerprinted in exactly one suite.
const SUITES := {
	"world_fingerprint": ["first-steps@1", "relay-isles@2", "the-wishing-well@1", "turn-of-the-tide@1"],
	"world_fingerprint_physical": ["high-and-low@1", "rolling-home@1", "a-house-for-two@1"],
	"world_fingerprint_journey": ["conservatory@1", "long-way-home@1", "long-way-home@2"],
	"world_fingerprint_lighthouse": [LIGHTHOUSE],
	"world_fingerprint_lighthouse_v2": ["sleeping-lighthouse@2"],
	"world_fingerprint_tide_v2": ["turn-of-the-tide@2"],
}
## Properties never fingerprinted on resources: identity and bookkeeping only.
const SKIPPED_PROPERTIES := ["resource_local_to_scene", "resource_path", "resource_name", "resource_scene_unique_id", "script"]
var checks := 0
var failures := 0
var _property_names: Dictionary = {}
var _defaults: Dictionary = {}
var _dump_root := ""
var _frame_usec := 0
var _fingerprint_usec := 0
var _stages: Dictionary = {}
var _collect := false
var _captured: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _suite() -> String:
	return "world_fingerprint"

func _run() -> void:
	var started := Time.get_ticks_msec()
	var suite := _suite()
	_dump_root = OS.get_environment(DUMP_ENV)
	if suite == "world_fingerprint": _check_split()
	var chapters: Dictionary = {}
	var orders: Dictionary = {}
	for key: String in SUITES.get(suite, []):
		var chapter_started := Time.get_ticks_msec()
		var passes: Dictionary = {}
		var stages := _lighthouse_snapshots() if key == LIGHTHOUSE else _snapshots(key)
		_stages[key] = stages
		var normal := _passes(key, false, stages)
		var again := _passes(key, false, stages)
		_check(not normal.is_empty() and _hashes(normal) == _hashes(again), "World fingerprint is deterministic across fresh worlds: " + key)
		passes["normal"] = normal
		passes["reduced"] = _passes(key, true, stages)
		_check(Primitives.changed_shared_looks().is_empty(), "Every kit look shared between meshes is as it was made after %s's scenarios; code that changes a mesh's material takes its own copy (Primitives.own_material): %s" % [key, Primitives.changed_shared_looks()])
		orders[key] = {}
		for name: String in passes:
			orders[key][name] = {}
			for scenario: String in passes[name]:
				orders[key][name][scenario] = passes[name][scenario].order_hash
				passes[name][scenario].erase("order_hash")
		chapters[key] = passes
		print("%s %s %d ms (frames %d ms, fingerprints %d ms)" % [suite, key, Time.get_ticks_msec() - chapter_started, _frame_usec / 1000, _fingerprint_usec / 1000])
		_frame_usec = 0
		_fingerprint_usec = 0
	var golden := suite + ".json"
	# Child order is advisory only: some code reads children by index, so a
	# reorder is reported without failing; the sorted fingerprint is the gate.
	var result := Golden.check(golden, {"chapters": chapters, "child_order": orders}, ["child_order"])
	for message: String in result.messages:
		push_error(message)
	for message: String in result.advisories:
		print("ADVISORY child order changed, not a failure: " + message)
	_check(result.ok, "World fingerprints match golden " + golden)
	if not result.ok and not Golden.write_mode(): _explain(golden, chapters)
	print("%s time %d ms" % [suite, Time.get_ticks_msec() - started])
	print("%s: %d checks, %d failures" % [suite.to_upper().replace("_", " "), checks, failures])
	quit(1 if failures else 0)

func _check_split() -> void:
	var counted: Dictionary = {}
	for suite: String in SUITES:
		for key: String in SUITES[suite]: counted[key] = int(counted.get(key, 0)) + 1
	for key: String in Golden.GOLDEN_KEYS:
		_check(counted.get(key, 0) == 1, "Pinned chapter %s is fingerprinted in exactly one suite (SUITES in tests/test_world_fingerprint.gd)" % key)

## On a mismatch, replays the differing passes with node lines kept and prints
## the current lines of every changed top-level branch, so a CI-only failure
## can be diffed against a local AFTER_YOU_FINGERPRINT_DUMP in one round.
func _explain(golden: String, chapters: Dictionary) -> void:
	var path := Golden.GOLDEN_DIR + golden
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not parsed is Dictionary or not parsed.get("chapters") is Dictionary: return
	for key: String in chapters:
		var printed := 0
		for pass_name: String in ["normal", "reduced"]:
			var now: Dictionary = chapters[key].get(pass_name, {})
			var before: Dictionary = parsed.chapters.get(key, {}).get(pass_name, {})
			var wanted: Dictionary = {}
			for scenario: String in now:
				var old: Dictionary = before.get(scenario, {})
				if str(old.get("hash", "")) == str(now[scenario].hash): continue
				var branches: Dictionary = {}
				var old_branches: Dictionary = old.get("subtrees", {})
				for slot: String in now[scenario].subtrees:
					if str(old_branches.get(slot, "")) != str(now[scenario].subtrees[slot]): branches[slot.get_slice("#", 0)] = true
				for slot: String in old_branches:
					if not now[scenario].subtrees.has(slot): branches[slot.get_slice("#", 0)] = true
				wanted[scenario] = branches
				print("FINGERPRINT DIFF %s %s %s branches %s story_camera %s" % [key, pass_name, scenario, JSON.stringify(branches.keys()), JSON.stringify(now[scenario].story_camera)])
			if wanted.is_empty() or not _stages.has(key): continue
			_collect = true
			_captured.clear()
			_passes(key, pass_name == "reduced", _stages[key])
			_collect = false
			for scenario: String in wanted:
				for line: String in _captured.get("%s %s" % [pass_name, scenario], []):
					var parts := line.get_slice(" ", 0).split("/")
					if parts.size() < 3 or not wanted[scenario].has(parts[2]): continue
					if printed >= 400: break
					print("FINGERPRINT NOW %s %s %s %s" % [key, pass_name, scenario, line])
					printed += 1

func _hashes(pass_result: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for scenario: String in pass_result: result[scenario] = pass_result[scenario].get("hash", "")
	return result

## Simulation snapshots for every scenario, replayed once per chapter and
## shared by its passes (replay determinism itself is the replay golden's job).
## Per stage: {stage, checkpoint, a_start, a_end, b_start, b_mid, b_end}.
func _snapshots(key: String) -> Array:
	var stages: Array = []
	var spec: Dictionary = _native_chain(key)
	if not _check(not spec.is_empty(), "Pinned chapter has a native fixture chain: " + key): return stages
	var level := Registry.definition(key)
	var engine: Script = Registry.simulation_script(key)
	var checkpoint := Registry.initial_checkpoint(key)
	for index in range(spec.stages.size()):
		var files: Array = spec.stages[index]
		var a: Dictionary = files[0] if files[0] is Dictionary else Golden.fixture(files[0])
		var b: Dictionary = files[1] if files[1] is Dictionary else Golden.fixture(files[1])
		var sim_a := _sim(key, engine, level, checkpoint, a, {})
		var sim_b := _sim(key, engine, level, checkpoint, b, a)
		if sim_a == null or sim_b == null: break
		var entry := {"stage": engine.stage_by_id(level, str(a.stage_id)), "checkpoint": checkpoint, "a_start": sim_a.snapshot(), "b_start": sim_b.snapshot()}
		for frame: Dictionary in engine.expand_recording_inputs(a): sim_a.step(frame)
		_check(sim_a.state_hash() == str(a.final_state_hash), "Fixture A replays before fingerprinting: %s %d" % [key, index])
		entry["a_end"] = sim_a.snapshot()
		var inputs: Array = engine.expand_recording_inputs(b)
		var half := inputs.size() / 2
		var raised := _raised_islands(key, level, str(a.stage_id))
		entry["b_below_tick"] = -1
		for tick in range(inputs.size()):
			var state: Dictionary = sim_b.step(inputs[tick])
			if int(entry.b_below_tick) < 0 and _below_raised(state, raised):
				entry["b_below_tick"] = int(state.tick)
				entry["b_below"] = state.duplicate(true)
			if tick + 1 == half: entry["b_mid"] = sim_b.snapshot()
		# Engines expose `complete`; the Lighthouse room facade reports it in its snapshot.
		var complete: Variant = sim_b.get("complete")
		if complete == null: complete = sim_b.snapshot().get("complete", false)
		_check(sim_b.state_hash() == str(b.final_state_hash) and bool(complete), "Fixture B completes before fingerprinting: %s %d" % [key, index])
		entry["b_end"] = sim_b.snapshot()
		stages.append(entry)
		checkpoint = files[2] if files[2] is Dictionary else Golden.fixture(files[2])
	return stages

## Raised floors as the physical worlds build them: islands above 50 cm.
func _raised_islands(key: String, level: Dictionary, stage_id: String) -> Array:
	if not Registry.is_cooperative(key): return []
	var raised: Array = []
	for island: Dictionary in CooperativeCatalog.stage_definition(level, stage_id).get("islands", []):
		if int(island.get("height_cm", 0)) > 50: raised.append(island)
	return raised

## The active player stands under a raised floor's span: the case the cutaway
## presentation handles (player height below the floor, x within its reach).
func _below_raised(state: Dictionary, raised: Array) -> bool:
	if raised.is_empty() or not state.get("players") is Dictionary: return false
	var player: Dictionary = state.players.get(str(state.get("active_slot", "")), {})
	if player.is_empty(): return false
	for island: Dictionary in raised:
		var span: Array = island.rect_cm
		if int(player.get("height", 0)) + 50 < int(island.height_cm) and int(player.x) >= int(span[0]) - 200 and int(player.x) <= int(span[2]) + 100: return true
	return false

## One fresh world driven through every scenario; returns scenario -> fingerprint.
func _passes(key: String, reduced: bool, stages: Array) -> Dictionary:
	if key == LIGHTHOUSE: return _lighthouse_pass(reduced, stages)
	var result: Dictionary = {}
	if stages.is_empty(): return result
	var viewport := _viewport()
	var world: Node3D = Registry.world_script(key).new()
	_mount(viewport, world, reduced)
	world.load_level(Registry.definition(key))
	for index in range(stages.size()):
		var entry: Dictionary = stages[index]
		var prefix := "s%d." % index
		_history(world, entry.stage, entry.checkpoint)
		world.present(entry.a_start.duplicate(true), true)
		_frames(world, 30)
		result[prefix + "start"] = _fingerprint(world, key, reduced, prefix + "start")
		world.present(entry.a_end.duplicate(true))
		_frames(world, 60)
		result[prefix + "a.end"] = _fingerprint(world, key, reduced, prefix + "a.end")
		_history(world, entry.stage, entry.checkpoint)
		world.present(entry.b_start.duplicate(true), true)
		# B's moments in tick order: halfway, and the first tick under a raised floor.
		var moments: Array = [[int(entry.b_mid.tick), "b.mid", entry.b_mid]]
		if int(entry.b_below_tick) >= 0: moments.append([int(entry.b_below_tick), "b.below", entry.b_below])
		moments.sort_custom(func(first: Array, second: Array) -> bool: return first[0] < second[0] or (first[0] == second[0] and first[1] < second[1]))
		for moment: Array in moments:
			world.present(moment[2].duplicate(true))
			_frames(world, 20)
			result[prefix + moment[1]] = _fingerprint(world, key, reduced, prefix + moment[1])
			result[prefix + moment[1]]["tick"] = moment[0]
		world.present(entry.b_end.duplicate(true))
		_frames(world, 180)
		result[prefix + "b.end"] = _fingerprint(world, key, reduced, prefix + "b.end")
	viewport.free()
	return result

## A chapter's file chain, or else its bundle chain as {stages: [[a, b, checkpoint]]}.
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
	return {}

func _viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	return viewport

## Mirrors the controllers: graphics policy after _ready, then reduced motion.
func _mount(viewport: SubViewport, world: Node3D, reduced: bool) -> void:
	viewport.add_child(world)
	GraphicsPolicy.apply(world, {"graphics_quality": "balanced"})
	world.reduced_motion = reduced
	world.configure_camera_exploration(func() -> bool: return false, func(_point: Vector2) -> bool: return false)

func _history(world: Node3D, stage: Dictionary, checkpoint: Dictionary) -> void:
	if world.has_method("show_stage"): world.show_stage(stage)
	if world.has_method("present_history"): world.present_history(checkpoint)

func _sim(key: String, engine: Script, level: Dictionary, checkpoint: Dictionary, record: Dictionary, prior: Dictionary) -> RefCounted:
	var sim: RefCounted = engine.new()
	sim.catch_assistance = bool(record.get("catch_assistance", true))
	if not _check(Registry.reset_simulation(sim, key, level, str(record.stage_id), checkpoint, prior, str(record.role), record), "Registry reset accepts the fixture: %s %s" % [key, record.stage_id]): return null
	return sim

## Lighthouse snapshots, as _snapshots: {stage, checkpoint, a_start, a_end, b_start, b_end}.
func _lighthouse_snapshots() -> Array:
	var stages: Array = []
	var fixture := Golden.fixture(LIGHTHOUSE_FIXTURE)
	var pairs: Array = fixture.get("pairs", [])
	var checkpoints: Array = fixture.get("checkpoints", [])
	if not _check(pairs.size() == 6 and checkpoints.size() == 7, "Six-stage Lighthouse fixture is complete"): return stages
	for index in range(pairs.size()):
		var history := pairs.slice(0, index)
		var pair: Dictionary = pairs[index]
		var sim_a := Light.new()
		var sim_b := Light.new()
		if not _check(sim_a.reset("a", {}, history, int(pair.a.simulation_version)) and sim_b.reset("b", pair.a, history, int(pair.b.simulation_version)), "Lighthouse fixture resets: %d" % index): break
		var entry := {"stage": LightCatalog.definition(LightCatalog.STAGE_IDS[index]), "checkpoint": checkpoints[index], "a_start": sim_a.snapshot(), "b_start": sim_b.snapshot()}
		for frame: Dictionary in Light.expand_recording_inputs(pair.a): sim_a.step(frame)
		entry["a_end"] = sim_a.snapshot()
		for frame: Dictionary in Light.expand_recording_inputs(pair.b): sim_b.step(frame)
		_check(sim_a.state_hash() == str(pair.a.final_state_hash) and sim_b.state_hash() == str(pair.b.final_state_hash), "Lighthouse fixture replays before fingerprinting: %d" % index)
		entry["b_end"] = sim_b.snapshot()
		stages.append(entry)
	return stages

## The Lighthouse controller reloads the stage world for every reset.
func _lighthouse_pass(reduced: bool, stages: Array) -> Dictionary:
	var result: Dictionary = {}
	if stages.is_empty(): return result
	var viewport := _viewport()
	var world: Node3D = LighthouseWorld.new()
	_mount(viewport, world, reduced)
	for index in range(stages.size()):
		var entry: Dictionary = stages[index]
		var prefix := "s%d." % index
		world.load_level(entry.stage)
		world.present_history(entry.checkpoint)
		world.present(entry.a_start.duplicate(true), true)
		_frames(world, 30)
		result[prefix + "start"] = _fingerprint(world, LIGHTHOUSE, reduced, prefix + "start")
		world.present(entry.a_end.duplicate(true))
		_frames(world, 60)
		result[prefix + "a.end"] = _fingerprint(world, LIGHTHOUSE, reduced, prefix + "a.end")
		world.load_level(entry.stage)
		world.present_history(entry.checkpoint)
		world.present(entry.b_start.duplicate(true), true)
		world.present(entry.b_end.duplicate(true))
		_frames(world, 180)
		result[prefix + "b.end"] = _fingerprint(world, LIGHTHOUSE, reduced, prefix + "b.end")
	viewport.free()
	return result

## One emulated engine frame per step: every processing node, in engine order.
func _frames(world: Node, count: int) -> void:
	var started := Time.get_ticks_usec()
	_frames_inner(world, count)
	_frame_usec += Time.get_ticks_usec() - started

func _frames_inner(world: Node, count: int) -> void:
	for _frame in range(count):
		var found: Array = []
		_processing(world, found)
		var order: Array = []
		for index in range(found.size()): order.append([found[index].process_priority, index])
		order.sort()
		for item: Array in order:
			var node: Node = found[item[1]]
			if is_instance_valid(node) and not node.is_queued_for_deletion(): node._process(DELTA)

func _processing(node: Node, found: Array) -> void:
	if node.is_queued_for_deletion(): return
	if node.get_script() != null and node.has_method("_process") and node.is_processing() and node.can_process(): found.append(node)
	for child: Node in node.get_children(): _processing(child, found)

func _fingerprint(world: Node3D, key: String, reduced: bool, scenario: String) -> Dictionary:
	var started := Time.get_ticks_usec()
	var cache: Dictionary = {}
	var classes: Dictionary = {}
	var lines: Array = []
	var top := _node(world, cache, classes, lines, "")
	# Top-level subtrees, sorted like the hash, so a difference names its branch.
	var branches: Array = top.children.duplicate()
	branches.sort()
	var subtrees: Dictionary = {}
	for branch: Array in branches:
		var slot: String = branch[0]
		var suffix := 2
		while subtrees.has(slot):
			slot = "%s#%d" % [branch[0], suffix]
			suffix += 1
		subtrees[slot] = str(branch[1]).substr(0, 16)
	var camera: Camera3D = world.get("camera")
	var story: Dictionary = {}
	for field: String in ["_follow_center", "_view_center", "_view_size", "_follow_size"]:
		if field in world: story[field] = _value(world.get(field), 0)
	if _collect:
		lines.sort()
		_captured["%s %s" % ["reduced" if reduced else "normal", scenario]] = lines
	if not _dump_root.is_empty():
		lines.sort()
		var folder := _dump_root.path_join(key.replace("@", "_")).path_join("reduced" if reduced else "normal")
		DirAccess.make_dir_recursive_absolute(folder)
		var file := FileAccess.open(folder.path_join(scenario + ".txt"), FileAccess.WRITE)
		if file != null:
			file.store_string("\n".join(PackedStringArray(lines)) + "\n")
			file.close()
	var result := {"hash": top.hash, "order_hash": top.order, "nodes": top.count, "classes": classes, "subtrees": subtrees,
		"camera": _describe(camera, cache) if is_instance_valid(camera) else "", "story_camera": story}
	_fingerprint_usec += Time.get_ticks_usec() - started
	return result

## Returns {hash, order, count, children: [[name, hash]]} for node and its subtree.
func _node(node: Node, cache: Dictionary, classes: Dictionary, lines: Array, path: String) -> Dictionary:
	var own := _describe(node, cache)
	var here := path + "/" + _name(node)
	if _collect or not _dump_root.is_empty(): lines.append(here + " " + own)
	classes[node.get_class()] = int(classes.get(node.get_class(), 0)) + 1
	var hashes: Array = []
	var ordered: Array = []
	var children: Array = []
	var count := 1
	for child: Node in node.get_children():
		if child.is_queued_for_deletion(): continue
		var entry := _node(child, cache, classes, lines, here)
		hashes.append(entry.hash)
		ordered.append(entry.order)
		children.append([_name(child), entry.hash])
		count += int(entry.count)
	hashes.sort()
	return {"hash": (own + "|" + ",".join(PackedStringArray(hashes))).sha256_text(), "order": (own + "|" + ",".join(PackedStringArray(ordered))).sha256_text(), "count": count, "children": children}

## Engine-generated names carry a process-wide counter (@Class@123); drop it.
func _name(node: Node) -> String:
	var name := str(node.name)
	if name.begins_with("@"):
		var parts := name.split("@", false)
		return "@" + (parts[0] if parts.size() > 0 else "")
	# A duplicate of an engine-named node keeps the counter as "_<Class>_<n>".
	var copied := "_" + node.get_class() + "_"
	if name.begins_with(copied) and name.substr(copied.length()).is_valid_int(): return "@" + node.get_class()
	return name

func _describe(node: Node, cache: Dictionary) -> String:
	var fields: Array = [node.get_class(), _name(node)]
	if node is Node3D:
		fields.append_array([node.visible, _value(node.global_transform, 0)])
	if node is GeometryInstance3D:
		fields.append_array([node.cast_shadow, _value(node.transparency, 0), _resource(node.material_override, cache, 0), _resource(node.material_overlay, cache, 0)])
	if node is MeshInstance3D:
		fields.append(_resource(node.mesh, cache, 0))
		var surfaces: Array = []
		for index in range(node.get_surface_override_material_count()): surfaces.append(_resource(node.get_surface_override_material(index), cache, 0))
		fields.append(surfaces)
	if node is MultiMeshInstance3D:
		fields.append(_multimesh(node.multimesh, cache))
	if node is Label3D:
		fields.append_array([node.text, node.font_size, _value(node.pixel_size, 0), node.outline_size, _value(node.modulate, 0), _value(node.outline_modulate, 0),
			node.billboard, node.no_depth_test, node.double_sided, node.fixed_size, node.horizontal_alignment, node.vertical_alignment, _value(node.width, 0), node.render_priority, node.outline_render_priority, _resource(node.font, cache, 0)])
	if node is SpriteBase3D:
		fields.append_array([_value(node.modulate, 0), _value(node.pixel_size, 0), node.billboard])
		if node is Sprite3D: fields.append(_resource(node.texture, cache, 0))
	if node is Light3D:
		fields.append_array([_value(node.light_color, 0), _value(node.light_energy, 0), _value(node.light_indirect_energy, 0), node.shadow_enabled])
		if node is DirectionalLight3D: fields.append(_value(node.directional_shadow_max_distance, 0))
		if node is OmniLight3D: fields.append_array([_value(node.omni_range, 0), _value(node.omni_attenuation, 0)])
		if node is SpotLight3D: fields.append_array([_value(node.spot_range, 0), _value(node.spot_angle, 0)])
	if node is WorldEnvironment:
		fields.append(_resource(node.environment, cache, 0))
	if node is Camera3D:
		fields.append_array([node.projection, _value(node.size, 0), _value(node.fov, 0), _value(node.h_offset, 0), _value(node.v_offset, 0), node.keep_aspect, _value(node.near, 0), _value(node.far, 0), node.current])
	if node is GPUParticles3D or node is CPUParticles3D:
		fields.append_array([node.emitting, node.amount, _value(node.lifetime, 0)])
	return JSON.stringify(fields)

## Quantised, platform-stable values: lengths and factors to 1/1000, colours to 1/255.
func _value(value: Variant, depth: int) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			return roundi(value * 1000.0) if is_finite(value) else str(value)
		TYPE_INT, TYPE_BOOL, TYPE_STRING, TYPE_NIL:
			return value
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4:
			var parts: Array = []
			for index in range({TYPE_VECTOR2: 2, TYPE_VECTOR3: 3, TYPE_VECTOR4: 4}[typeof(value)]): parts.append(roundi(value[index] * 1000.0))
			return parts
		TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I, TYPE_RECT2I:
			return str(value)
		TYPE_COLOR:
			return [roundi(value.r * 255.0), roundi(value.g * 255.0), roundi(value.b * 255.0), roundi(value.a * 255.0)]
		TYPE_TRANSFORM3D:
			var t: Transform3D = value
			return [_value(t.origin, 0), _value(t.basis.x, 0), _value(t.basis.y, 0), _value(t.basis.z, 0)]
		TYPE_BASIS:
			return [_value(value.x, 0), _value(value.y, 0), _value(value.z, 0)]
		TYPE_QUATERNION:
			return [roundi(value.x * 1000.0), roundi(value.y * 1000.0), roundi(value.z * 1000.0), roundi(value.w * 1000.0)]
		TYPE_AABB:
			return [_value(value.position, 0), _value(value.size, 0)]
		TYPE_RECT2:
			return [_value(value.position, 0), _value(value.size, 0)]
		TYPE_TRANSFORM2D:
			return [_value(value.origin, 0), _value(value.x, 0), _value(value.y, 0)]
		TYPE_PLANE:
			return [_value(value.normal, 0), roundi(value.d * 1000.0)]
		TYPE_PACKED_BYTE_ARRAY:
			var context := HashingContext.new()
			context.start(HashingContext.HASH_SHA256)
			if not value.is_empty(): context.update(value)
			return "bytes:%d:%s" % [value.size(), context.finish().hex_encode().substr(0, 16)]
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			var items: Array = []
			for item: Variant in value: items.append(_value(item, depth + 1))
			return items
		TYPE_DICTIONARY:
			var keys: Array = []
			for item: Variant in value: keys.append(str(item))
			keys.sort()
			var result: Dictionary = {}
			for item: Variant in value: result[str(item)] = _value(value[item], depth + 1)
			var ordered: Array = []
			for item: String in keys: ordered.append([item, result[item]])
			return ordered
		TYPE_OBJECT:
			return _resource(value, {}, depth + 1) if value is Resource else ("<%s>" % value.get_class() if value != null else null)
	return "<%s>" % type_string(typeof(value))

## A resource's stored properties, recursively; files are named by path.
func _resource(resource: Variant, cache: Dictionary, depth: int) -> Variant:
	if resource == null or not resource is Resource: return null
	var path: String = resource.resource_path
	if not path.is_empty() and not path.contains("::"): return resource.get_class() + ":" + path
	var id: int = resource.get_instance_id()
	if cache.has(id): return cache[id]
	if depth > 3: return resource.get_class() + ":deep"
	cache[id] = resource.get_class() + ":cycle"
	var fields: Array = [resource.get_class()]
	if resource is Mesh and not resource is PrimitiveMesh:
		var surfaces: Array = []
		for index in range(resource.get_surface_count()):
			surfaces.append([resource.surface_get_array_len(index) if resource is ArrayMesh else -1, _resource(resource.surface_get_material(index), cache, depth + 1)])
		fields.append_array([surfaces, _value(resource.get_aabb(), 0)])
	else:
		# Only values that differ from a fresh instance of the class are listed;
		# a value quantising to the default counts as the default.
		var defaults := _class_defaults(resource)
		for name: String in _stored(resource):
			var raw: Variant = resource.get(name)
			if defaults.has(name):
				var default: Array = defaults[name]
				if typeof(raw) == typeof(default[0]) and raw == default[0]: continue
				var quantised: Variant = _value(raw, depth)
				if quantised == default[1]: continue
				fields.append([name, quantised])
			else:
				fields.append([name, _value(raw, depth)])
	var described := JSON.stringify(fields).sha256_text().substr(0, 24)
	cache[id] = described
	return described

## Raw and quantised default values of a plain engine resource class.
func _class_defaults(resource: Resource) -> Dictionary:
	if resource.get_script() != null or resource is ShaderMaterial: return {}
	var name := resource.get_class()
	if _defaults.has(name): return _defaults[name]
	var result: Dictionary = {}
	if ClassDB.can_instantiate(name):
		var fresh: Object = ClassDB.instantiate(name)
		for property: String in _stored(resource):
			var value: Variant = fresh.get(property)
			if typeof(value) != TYPE_OBJECT or value == null: result[property] = [value, _value(value, 1)]
	_defaults[name] = result
	return result

func _stored(resource: Resource) -> Array:
	var script: Script = resource.get_script()
	var class_key: String = resource.get_class() + ("|" + script.resource_path if script != null else "")
	if _property_names.has(class_key) and not resource is ShaderMaterial: return _property_names[class_key]
	var names: Array = []
	for property: Dictionary in resource.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_STORAGE): continue
		if str(property.name) in SKIPPED_PROPERTIES: continue
		names.append(str(property.name))
	names.sort()
	if not resource is ShaderMaterial: _property_names[class_key] = names
	return names

func _multimesh(multimesh: MultiMesh, cache: Dictionary) -> Variant:
	if multimesh == null: return null
	var instances: Array = []
	for index in range(multimesh.instance_count):
		instances.append(_value(multimesh.get_instance_transform(index), 0))
	return [multimesh.instance_count, multimesh.visible_instance_count, _resource(multimesh.mesh, cache, 0), JSON.stringify(instances).sha256_text()]

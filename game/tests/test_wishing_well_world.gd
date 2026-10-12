extends SceneTree
## Recorded inputs cross the actual journal, chapter controls and well world.
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Preview = preload("res://cooperative_preview.gd")
const World = preload("res://presentation/wishing_well_world.gd")
const Simulation = preload("res://core/cooperative/simulation.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0
var directory := "user://wishing-well-world-" + Crypto.new().generate_random_bytes(8).hex_encode()

class SoundProbe:
	extends "res://services/soundscape.gd"
	var heard: Array = []
	func consume_events(events: Array, live_play: bool) -> void:
		heard.append_array(events)
		super.consume_events(events, live_play)

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(directory)
	var level := Registry.definition(Registry.WISHING_WELL)
	for index in range(2):
		for role: String in ["a", "b"]:
			await _stage(level, index, role)
	await _lowering(level)
	for filename: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	print("AFTER YOU WISHING WELL WORLD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _stage(level: Dictionary, index: int, role: String) -> void:
	var id: String = level.stages[index].id
	var journal := Journey.new(directory.path_join(id + "-" + role + ".json"), null, Registry.WISHING_WELL)
	journal.load_data()
	for earlier in range(index):
		for prior_role: String in ["a", "b"]:
			if not journal.accept_recording(_fixture(level.stages[earlier].id + "-" + prior_role)):
				_check(false, "Earlier well pair is accepted: " + journal.last_error)
				return
	if role == "b" and not journal.accept_recording(_fixture(id + "-a")):
		_check(false, "Well source is accepted before its receiver: " + journal.last_error)
		return
	var screen := Preview.new()
	screen.chapter_key = Registry.WISHING_WELL
	screen.journey = journal
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true}
	root.add_child(screen)
	screen.set_physics_process(false)
	screen.set_process(false)
	screen.world.set_process(false)
	var probe := SoundProbe.new()
	screen.remove_child(screen.soundscape)
	screen.soundscape.queue_free()
	screen.soundscape = probe
	screen.add_child(probe)
	var world: Node3D = screen.world
	_check(world.get_script() == World and screen.mode == "ready", "Real chapter admission selects the well world")
	_check(screen.admission == null, "The free chapter opens without a purchase gate")
	_check(world._uses_scrolling_camera() and not world._uses_lower_cutaway(), "The well scrolls and never needs a cutaway")
	var bucket: Node3D = world.terrain.find_child("RopeBucket_*", true, false)
	if index == 0: _check(is_instance_valid(bucket) and absf(bucket.position.y - World.BUCKET_RAISE) < 0.01 and absf(bucket.position.x - 11.6) < 0.01, "The empty bucket hangs up under its pulley before anyone drops in")
	else: _check(is_instance_valid(bucket) and bucket.position.y < 0.01, "The friend still holding on waits in the lowered bucket")
	_check(is_instance_valid(world._decks.get(level.bridges[0].id)) and absf(world._decks[level.bridges[0].id].position.y - 1.6) < 0.01, "The rope-walk hangs at the cliff height, not on the ground")
	screen._begin()
	_check(screen.mode == "play", "The actual chapter controls start this recorded role")
	if index == 1 and role == "a":
		var state: Dictionary = screen.sim.snapshot()
		var friend: Node3D = world.actors["p0"]
		_check(world._role_badge_text(state, "p0") == "Waiting" and friend.visible and absf(friend.position.y) < 0.01 and friend.position.x > 11.2 and friend.position.x < 12.0, "The friend still holding on is shown waiting, visible in the open well")
		_check(bool(state.bridges["rope-walk-west"]) and world._decks["rope-walk-west"].visible, "Their held rope shows the rope-walk open from the start")
	var observed := {}
	var definition_hash := Canonical.digest(level)
	for frame: Dictionary in Simulation.expand_recording_inputs(_fixture(id + "-" + role)):
		var heard_before := probe.heard.size()
		screen.advance_input(frame)
		var state: Dictionary = screen.sim.snapshot()
		var me: Dictionary = state.players[state.active_slot]
		for raised: Node3D in world._upper_islands:
			if raised.get_child_count() > 0 and raised.get_child(0).get_meta("cutaway", false): observed.faded = true
		if id == "go-on-ahead" and role == "a" and "drop" in state.events:
			observed.drop = true
			observed.drop_sound = "seed_landed" in probe.heard.slice(heard_before)
			_check(int(me.height) == 0 and str(me.surface_id) == "well-floor" and bool(state.hold_pads["bucket-rope"]), "The drop lands in the bucket and the rope is held")
			_check(float(world._folds["long-stair"].target) == 1.0, "The long stair starts to unfold as the friend lands")
			_check(bucket.position.y < 0.01 and absf(world.actor_targets["p0"].y) < 0.01, "Under reduced motion the bucket and its rider settle on the floor at once")
		if id == "go-on-ahead" and role == "b" and not bool(state.bridges["long-stair"]):
			observed.folded = observed.get("folded", true) and float(world._folds["long-stair"].open) == 0.0
		if id == "back-for-you" and role == "b" and str(me.surface_id) == "well-ladder":
			observed.climb = true
			var shown := 0
			for rung: Node3D in world._ladder_rungs: shown += int(rung.visible)
			observed.ladder_shown = shown == world._ladder_rungs.size()
			if not bool(state.hold_pads["still-holding"]): observed.bucket_up = bucket.position.y > World.BUCKET_RAISE - 0.01
	_check(screen.sim.can_commit(), "Rendered real inputs remain committable: " + id + " " + role)
	_check(Canonical.digest(screen.sim.level) == definition_hash, "Presentation never changes the authored chapter")
	_check(not observed.has("faded"), "No floor ever fades: the open well needs no cutaway")
	if id == "go-on-ahead" and role == "a":
		_check(observed.has("drop") and bool(observed.get("drop_sound", false)), "The drop into the well is heard on that tick (it reuses the landing cue)")
		var pad: MeshInstance3D = world._physical_pads["bucket-rope"]
		_check((pad.material_override as StandardMaterial3D).emission_enabled, "The bucket floor glows while the rope is held")
	elif id == "go-on-ahead":
		_check(bool(observed.get("folded", false)) and float(world._folds["long-stair"].open) == 1.0, "The stair stays folded until the friend lands, then lies open")
	elif role == "b":
		_check(observed.has("climb") and bool(observed.get("ladder_shown", false)), "The friend climbs a fully unrolled ladder")
		_check(bool(observed.get("bucket_up", false)), "The empty bucket goes back up once the friend climbs out")
		_check(screen.sim.complete and is_instance_valid(world.garden) and world.garden_state == "completed", "Completion blooms the garden on the wall beside both spirits")
	root.remove_child(screen)
	screen.free()
	await process_frame

## Normal motion, one rendered frame per tick: the friend drops into the raised
## bucket and rides it down while the drum turns and the stair settles with it.
## A retry shows the raised bucket again at once. The simulation never moves.
func _lowering(level: Dictionary) -> void:
	var world: Node3D = World.new()
	root.add_child(world)
	world.set_process(false)
	world.load_level(level)
	var sim := Simulation.new()
	sim.reset(level, "go-on-ahead", _fixture("the-wishing-well-initial-checkpoint"), {}, "a")
	var start: Dictionary = sim.snapshot()
	world.present(start, true)
	var bucket: Node3D = world._bucket
	var drum_start: float = world._windlass.rotation.x
	var rope_start: float = world._bucket_rope.scale.y
	var seen := {}
	for frame: Dictionary in Simulation.expand_recording_inputs(_fixture("go-on-ahead-a")):
		var state: Dictionary = sim.step(frame)
		world.present(state, false)
		world._process(1.0 / 30.0)
		if "drop" in state.events:
			seen.landing_y = bucket.position.y
			seen.rider_y = world.actor_targets["p0"].y
			seen.sim_y = float(state.players.p0.height)
			seen.stair = float(world._folds["long-stair"].pivot.rotation.x)
			seen.ticks = 0
		elif seen.has("ticks"):
			seen.ticks += 1
			if seen.ticks == 8: seen.mid_y = bucket.position.y
	for _frame in range(40): world._process(1.0 / 30.0)
	seen.rest_y = bucket.position.y
	seen.rest_rider = world.actor_targets["p0"].y
	seen.rest_sim = float(sim.snapshot().players.p0.height)
	seen.drum = float(world._windlass.rotation.x)
	seen.rope = float(world._bucket_rope.scale.y)
	seen.stair_open = absf(float(world._folds["long-stair"].pivot.rotation.x)) < 0.001
	_check(float(seen.get("landing_y", 0.0)) > 0.8 and float(seen.get("rider_y", 0.0)) > 0.8 and float(seen.get("sim_y", -1.0)) == 0.0, "The friend lands in the bucket near the top while the simulation stands them on the floor")
	_check(float(seen.get("mid_y", 0.0)) > 0.05 and float(seen.get("mid_y", 1.0)) < float(seen.get("landing_y", 0.0)), "The bucket is part way down a quarter second later")
	_check(float(seen.get("stair", 0.0)) > 0.5, "The long stair is still folded on the landing frame")
	_check(float(seen.get("rest_y", 1.0)) < 0.001 and absf(float(seen.get("rest_rider", 1.0))) < 0.001 and float(seen.get("rest_sim", -1.0)) == 0.0, "The bucket and its rider settle on the floor")
	_check(absf(float(seen.get("drum", drum_start)) - drum_start) > TAU and float(seen.get("rope", 0.0)) > rope_start + 0.8, "The rope pays out and the drum turns as it lowers")
	_check(bool(seen.get("stair_open", false)), "The long stair lies open once the bucket has settled")
	world.present(start, true)
	_check(absf(bucket.position.y - World.BUCKET_RAISE) < 0.001 and absf(world._windlass.rotation.x - drum_start) < 0.001, "A retry shows the empty bucket back up at once")
	world.free()
	await process_frame

func _fixture(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cooperative/" + name + ".json"))
	return parsed if parsed is Dictionary else {}

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)

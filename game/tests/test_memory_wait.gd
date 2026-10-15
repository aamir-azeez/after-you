extends SceneTree
## Waiting for the friend's memory (presentation/memory_wait.gd): the doze,
## the held ring, Hold to fast-forward and Skip to end. Presentation only:
## every way through the wait must leave the simulation and its recording
## byte-identical to a still player waiting at normal speed.
const MemoryWait = preload("res://presentation/memory_wait.gd")
const Soundscape = preload("res://services/soundscape.gd")
const ChapterSoundMap = preload("res://services/chapter_sound_map.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Simulation = preload("res://core/cooperative/simulation.gd")
const Catalog = preload("res://core/cooperative/stage_catalog.gd")
const Witness = preload("res://tests/cooperative_witness.gd")
const SpiritIdle = preload("res://presentation/spirit_idle.gd")
const ChapterControls = preload("res://presentation/chapter_controls.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Golden = preload("res://tests/golden_support.gd")
const ReplayGolden = preload("res://tests/test_replay_golden.gd")
const Light = preload("res://core/lighthouse/borrowed_light.gd")

const LEVEL := "high-and-low"
const KEY := Registry.HIGH_AND_LOW
const STAGE := "upper-path"
## Extra seconds the friend's memory lingers after its route, so the second
## spirit rings the bell well before the memory ends.
const LINGER_TICKS := 240
const STILL := {"move_x": 0.0, "move_z": 0.0, "interact": false}
const FRAME := 1.0 / 60.0

var checks := 0
var failures := 0
var level: Dictionary
var checkpoint: Dictionary
var first: Dictionary
## The receiver's inputs up to and including the bell press.
var to_ring: Array = []

## Records every cue that actually sounds, with its pitch.
class CueLog extends "res://services/soundscape.gd":
	var played: Array = []
	func _play_cue(key: String, step: float, gain: float, live_play: bool) -> void:
		played.append({"key": key, "step": step, "gain": gain})

class WorldStub extends Node3D:
	var presented: Array = []
	func present(state: Dictionary, _immediate: bool = false) -> void: presented.append(state)

class ControlsStub extends CanvasLayer:
	var held := false
	var waits: Array = []
	var stick := Control.new()
	func update_state(_title: String, _remaining: float, _state: Dictionary, _live: bool) -> void: pass
	func show_memory_wait(text: String, ratio: float) -> void: waits.append([text, ratio])
	func hide_memory_wait() -> void: pass
	func fast_forward_held() -> bool: return held
	func dim_stick(_dim: bool) -> void: pass

## The chapter screen with its save and turn check left out.
class Preview extends "res://relay_preview.gd":
	var finishes := 0
	func _persist_draft(_after_retry: String = "play", _periodic: bool = false) -> bool: return true
	func _finish() -> void:
		finishes += 1
		running = false

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok

func _run() -> void:
	level = Catalog.definition(LEVEL)
	checkpoint = Catalog.initial_checkpoint(level)
	var a := Witness.source(level, STAGE, checkpoint)
	Witness.wait_ticks(a, LINGER_TICKS)
	_check(a.error.is_empty() and a.can_commit(), "The lingering memory is still a valid first turn")
	first = a.export_recording()
	_find_ring()
	if _check(not to_ring.is_empty(), "The receiver rings the bell before the memory ends"):
		for part: Callable in [_test_detection, _test_identity, _test_ring_once_and_pitch, _test_draft_resume,
				_test_world_doze_and_replay.bind(false), _test_world_doze_and_replay.bind(true),
				_test_lighthouse_world.bind(false), _test_lighthouse_world.bind(true), _test_hud_strip]:
			_timed(part)
	_timed(_test_every_chapter)
	print("AFTER YOU MEMORY WAIT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _timed(part: Callable) -> void:
	var started := Time.get_ticks_msec()
	part.call()
	print("TIME %s %d ms" % [part.get_method(), Time.get_ticks_msec() - started])

## Walks the witness receiver route, keeping its inputs, until the bell rings.
func _find_ring() -> void:
	var recorder := Simulation.new()
	recorder.reset(level, STAGE, checkpoint, first, "b")
	var probe := Witness.receiver(level, STAGE, checkpoint, first)
	var inputs: Array = Simulation.expand_recording_inputs(probe.export_recording())
	for input: Dictionary in inputs:
		var state: Dictionary = recorder.step(input)
		to_ring.append(input)
		if MemoryWait.objective_done(state):
			if bool(state.complete): to_ring.clear()
			return
	to_ring.clear()

func _receiver() -> RefCounted:
	var sim := Simulation.new()
	sim.reset(level, STAGE, checkpoint, first, "b")
	return sim

func _sounds(state: Dictionary, seen: Dictionary) -> Dictionary:
	return ChapterSoundMap.cues(KEY, state, seen)

func _test_detection() -> void:
	var sim := _receiver()
	var wait := MemoryWait.new()
	wait.begin("b", MemoryWait.prior_ticks(first))
	var ring_tick := -1
	for input: Dictionary in to_ring:
		var state: Dictionary = sim.step(input)
		wait.step_silently(state, {"cues": [], "sources": []})
		if MemoryWait.objective_done(state): ring_tick = int(state.tick)
	_check(wait.waiting(), "The wait starts on the tick the bell is rung")
	_check(ring_tick < int(first.duration_ticks), "The ring comes before the memory ends")
	_check(is_equal_approx(wait.remaining_seconds(), float(int(first.duration_ticks) - ring_tick) / 30.0), "The remaining time counts the memory still to play")
	_check(is_equal_approx(wait.remaining_ratio(), 1.0), "The bar starts full")
	var first_wait := MemoryWait.new()
	first_wait.begin("a", 0)
	var source := Simulation.new()
	source.reset(level, STAGE, checkpoint)
	for _tick in range(30): first_wait.step_silently(source.step(STILL), {"cues": [], "sources": []})
	_check(not first_wait.waiting(), "A first turn never waits")

## A still player at normal speed, Hold to fast-forward and Skip to end all
## leave the same simulation and the same recording, byte for byte.
func _test_identity() -> void:
	var still := _receiver()
	for input: Dictionary in to_ring: still.step(input)
	while not still.finished: still.step(STILL)
	var expected: Dictionary = still.export_recording()
	_check(bool(still.complete), "At normal speed the stage completes when the memory ends")
	for way: String in ["normal", "fast_forward", "skip", "fast_forward_slow_phone", "skip_slow_phone"]:
		var run := _preview_to_ring()
		var preview: Preview = run.preview
		var controls: ControlsStub = run.controls
		# A huge budget pins the speed checks; a slow phone (1 usec) still
		# reaches the very same end, only over more frames.
		var slow := way.ends_with("_slow_phone")
		preview.memory_wait.step_budget_usec = 1 if slow else 1 << 40
		if slow:
			controls.held = way.begins_with("fast_forward")
			if not controls.held: preview._skip_memory_wait()
			var frames := 0
			while preview.running and frames < 20000:
				preview._physics_process(1.0 / 30.0)
				frames += 1
		elif way == "normal":
			while preview.running: preview.advance_input(STILL)
		elif way == "fast_forward":
			controls.held = true
			var physics_ticks := 0
			while preview.running and physics_ticks < 10000:
				preview._physics_process(1.0 / 30.0)
				physics_ticks += 1
			var waited := int(first.duration_ticks) - to_ring.size()
			_check(physics_ticks <= int(ceil(float(waited) / MemoryWait.FAST_FORWARD_TICKS)) + 1, "Fast-forward plays the wait about %d times faster" % MemoryWait.FAST_FORWARD_TICKS)
		else:
			preview._skip_memory_wait()
			var skip_ticks := 0
			while preview.running and skip_ticks < 10000:
				preview._physics_process(1.0 / 30.0)
				skip_ticks += 1
			_check(skip_ticks <= 2, "With frame time to spare, Skip reaches the end at once")
		_check(preview.finishes == 1, "The turn ends once: " + way)
		_check(preview.sim.state_hash() == still.state_hash(), "The final state is byte-identical: " + way)
		_check(Canonical.same(preview.sim.export_recording(), expected) and JSON.stringify(preview.sim.export_recording()) == JSON.stringify(expected), "The recording is byte-identical: " + way)
		_free_preview(run)

func _preview_to_ring() -> Dictionary:
	var preview := Preview.new()
	preview.memory_wait.step_budget_usec = 1 << 40
	var controls := ControlsStub.new()
	var sound := CueLog.new()
	var world := WorldStub.new()
	preview.chapter_key = KEY
	preview.chapter = Registry.descriptor(KEY)
	preview.definition = Registry.definition(KEY)
	preview.checkpoint = Registry.initial_checkpoint(KEY).duplicate()
	preview.checkpoint["stage_index"] = 0
	preview.settings = {"sound": true, "haptics": false, "reduced_motion": false}
	preview.controls = controls
	preview.soundscape = sound
	preview.world = world
	preview.sim = _receiver()
	preview.role = "b"
	preview.mode = "play"
	preview.running = true
	sound.begin_turn(KEY, STAGE)
	preview._begin_memory_wait("b", first)
	for input: Dictionary in to_ring: preview.advance_input(input)
	_check(preview.memory_wait.waiting(), "The screen sees the wait after the bell")
	return {"preview": preview, "controls": controls, "sound": sound, "world": world}

func _free_preview(run: Dictionary) -> void:
	run.controls.stick.free()
	for part: String in ["controls", "sound", "world", "preview"]: run[part].free()

## The bell's cue is held at the press, sounds once after the friend arrives
## and the spirit has woken, and keeps the pitch it would have had at once.
func _test_ring_once_and_pitch() -> void:
	# Reference: the same ticks with nothing held, as before this change.
	var plain := CueLog.new()
	plain.begin_turn(KEY, STAGE)
	var plain_seen := {}
	var sim := _receiver()
	var plain_bell: Array = []
	while not sim.finished:
		var state: Dictionary = sim.step(to_ring[int(sim.tick)] if int(sim.tick) < to_ring.size() else STILL)
		var sounds := _sounds(state, plain_seen)
		plain.consume_turn_events(sounds.cues, sounds.sources, true)
	for cue: Dictionary in plain.played:
		if cue.key == "bell_rung": plain_bell.append(cue)
	_check(plain_bell.size() == 1, "Without a wait the bell sounds once")
	for way: String in ["normal", "fast_forward", "skip"]:
		var run := _preview_to_ring()
		var preview: Preview = run.preview
		var sound: CueLog = run.sound
		_check(_count(sound.played, "bell_rung") == 0, "The bell is silent at the press: " + way)
		if way == "normal":
			while preview.running: preview.advance_input(STILL)
		elif way == "fast_forward":
			run.controls.held = true
			while preview.running: preview._physics_process(1.0 / 30.0)
		else:
			preview._skip_memory_wait()
			while preview.running: preview._physics_process(1.0 / 30.0)
		_check(_count(sound.played, "bell_rung") == 0 and preview.memory_wait.ring_pending(), "The friend arrives and the spirit wakes before the bell: " + way)
		var elapsed := 0.0
		while preview.memory_wait.ring_pending() and elapsed < 2.0:
			preview.memory_wait.advance(FRAME)
			elapsed += FRAME
		_check(absf(elapsed - preview.memory_wait.ring_at()) <= FRAME * 1.5, "The bell rings just after the startled wake: " + way)
		_check(_count(sound.played, "bell_rung") == 1, "The bell sounds exactly once: " + way)
		var bell: Dictionary = _first(sound.played, "bell_rung")
		_check(not bell.is_empty() and bell.step == plain_bell[0].step and bell.gain == plain_bell[0].gain, "The held bell keeps its pitch and gain: " + way)
		var bloom_index := _index(sound.played, "island_bloomed")
		_check(bloom_index > _index(sound.played, "bell_rung"), "The bloom follows the bell: " + way)
		_check(_count(sound.played, "island_bloomed") == _count(plain.played, "island_bloomed"), "No cue is lost or doubled: " + way)
		for _frame in range(120): preview.memory_wait.advance(FRAME)
		_check(_count(sound.played, "bell_rung") == 1, "Nothing rings again later: " + way)
		var last: Dictionary = run.world.presented[-1]
		_check(bool(last.get("complete", false)) and not last.has("ring_held"), "After the ring the world sees the finished stage: " + way)
		_free_preview(run)

## A draft saved during the wait and resumed still rings once, same pitch.
func _test_draft_resume() -> void:
	var cut := to_ring.size() + 40
	var sound := CueLog.new()
	sound.begin_turn(KEY, STAGE)
	var world := WorldStub.new()
	var wait := MemoryWait.new()
	wait.world = world
	wait.soundscape = sound
	wait.begin("b", MemoryWait.prior_ticks(first))
	var sim := _receiver()
	var seen := {}
	for tick in range(cut):
		var state: Dictionary = sim.step(to_ring[tick] if tick < to_ring.size() else STILL)
		wait.step_silently(state, _sounds(state, seen))
	wait.show(sim.snapshot(), true)
	_check(wait.waiting() and bool(world.presented[-1].get("ring_held", false)), "A resumed draft is still waiting with the bell held")
	while not sim.finished:
		var state: Dictionary = sim.step(STILL)
		wait.step(state, _sounds(state, seen), true)
	for _frame in range(60): wait.advance(FRAME)
	_check(_count(sound.played, "bell_rung") == 1, "The resumed wait rings once")
	var reference := _receiver()
	var plain := CueLog.new()
	plain.begin_turn(KEY, STAGE)
	var plain_seen := {}
	while not reference.finished:
		var state: Dictionary = reference.step(to_ring[int(reference.tick)] if int(reference.tick) < to_ring.size() else STILL)
		var sounds := _sounds(state, plain_seen)
		plain.consume_turn_events(sounds.cues, sounds.sources, true)
	_check(_first(sound.played, "bell_rung").get("step") == _first(plain.played, "bell_rung").get("step"), "The resumed bell keeps its pitch")
	sound.free()
	world.free()

## In a real world: the spirit dozes (z's float), the camera follows the
## memory, the wake comes at the arrival and the goal lights and rings only
## after it. Replayed from the turn's recording, as every replay does.
func _test_world_doze_and_replay(reduced: bool) -> void:
	var still := _receiver()
	for input: Dictionary in to_ring: still.step(input)
	while not still.finished: still.step(STILL)
	var frames: Array = Simulation.expand_recording_inputs(still.export_recording())
	var definition := Registry.definition(KEY)
	_world_replay(KEY, definition, definition.stages[0], Registry.initial_checkpoint(KEY), _receiver, frames, MemoryWait.prior_ticks(first), reduced, "High and Low")

## The six-stage Lighthouse: "After the first bell" from the shared chain,
## whose second turn rings the tower bell before the memory ends.
func _test_lighthouse_world(reduced: bool) -> void:
	var key := Registry.LIGHTHOUSE_V2
	var chain := Golden.fixture("lighthouse/v2-chain.json")
	var index := 3
	var pair: Dictionary = chain.pairs[index]
	var at: Dictionary = chain.checkpoints[index]
	var definition := Registry.definition(key)
	var engine: Script = Registry.simulation_script(key)
	var make := func() -> RefCounted:
		var sim: RefCounted = engine.new()
		Registry.reset_simulation(sim, key, definition, str(pair.b.stage_id), at, pair.a, "b", pair.b)
		return sim
	_world_replay(key, definition, definition.stages[index], at, make, engine.expand_recording_inputs(pair.b), MemoryWait.prior_ticks(pair.a), reduced, "Lighthouse " + str(pair.b.stage_id))

func _world_replay(key: String, definition: Dictionary, stage: Dictionary, at: Dictionary, make_sim: Callable, frames: Array, prior_end: int, reduced: bool, name: String) -> void:
	var label := " (%s%s)" % [name, ", Reduce motion" if reduced else ""]
	# What the turn sounds like with nothing held.
	var plain := CueLog.new()
	plain.begin_turn(key, str(stage.id))
	var plain_seen := {}
	var reference: RefCounted = make_sim.call()
	for input: Dictionary in frames:
		var state: Dictionary = reference.step(input)
		var sounds := ChapterSoundMap.cues(key, state, plain_seen)
		plain.consume_turn_events(sounds.cues, sounds.sources, false)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1560, 720)
	root.add_child(viewport)
	var world: Node3D = Registry.world_script(key).new()
	world.reduced_motion = reduced
	viewport.add_child(world)
	world.load_level(definition)
	world.show_stage(stage)
	if world.has_method("present_history"): world.present_history(at)
	var sound := CueLog.new()
	viewport.add_child(sound)
	sound.begin_turn(key, str(stage.id))
	var wait := MemoryWait.new()
	wait.world = world
	wait.soundscape = sound
	wait.reduced_motion = reduced
	wait.begin("b", prior_end)
	var sim: RefCounted = make_sim.call()
	var seen := {}
	wait.show(sim.snapshot(), true)
	var live := ""
	var memory := ""
	var dozed := false
	var followed := false
	var lit_early := false
	var held_quiet := true
	var zs := 0
	for input: Dictionary in frames:
		var state: Dictionary = sim.step(input)
		live = str(state.active_slot)
		for slot: Variant in state.players:
			if bool(state.players[slot].get("ghost", false)): memory = str(slot)
		wait.step(state, ChapterSoundMap.cues(key, state, seen), false)
		world._process(1.0 / 30.0)
		wait.advance(1.0 / 30.0)
		if wait.waiting():
			var actor: Node3D = world.actors[live]
			dozed = dozed or actor.pose() == SpiritIdle.DOZE
			followed = followed or world.camera_focus == memory
			zs = 0
			for child: Node in actor.get_children():
				if str(child.name).begins_with("DozeZ") and child.visible: zs += 1
			lit_early = lit_early or bool(world.get("_wake"))
			held_quiet = held_quiet and _count(sound.played, "bell_rung") == 0
	_check(wait.waited, "The fixture turn waits for the memory" + label)
	_check(dozed, "The waiting spirit dozes in the replay" + label)
	_check(zs == 3, "Three z's float over the dozing spirit" + label)
	_check(followed, "The camera follows the memory while the spirit waits" + label)
	_check(not lit_early, "The goal does not light during the wait" + label)
	_check(held_quiet, "No ring sounds during the wait" + label)
	var actor: Node3D = world.actors[live]
	_check(actor.pose() == SpiritIdle.REST, "The friend's arrival wakes the spirit" + label)
	if reduced:
		_check(not actor.waking() and wait.rings_released == 1, "Reduce motion: no hop, and the ring comes on the arrival tick" + label)
	else:
		_check(actor.waking() and wait.ring_pending(), "The startled wake plays before the ring" + label)
		var lifted := false
		for _frame in range(40):
			world._process(FRAME)
			wait.advance(FRAME)
			lifted = lifted or actor.upper_body.position.y > 0.05
		_check(lifted, "The wake is a little hop" + label)
	_check(wait.rings_released == 1 and bool(world.get("_wake")), "Then the goal rings once and lights" + label)
	var same := true
	for cue: String in Soundscape.CLIPS:
		if _count(sound.played, cue) != _count(plain.played, cue): same = false
	_check(same, "Every cue sounds as often as with nothing held" + label)
	_check(_first(sound.played, "bell_rung").get("step") == _first(plain.played, "bell_rung").get("step"), "A held bell keeps its pitch" + label)
	_check(world.camera_focus.is_empty(), "After the ring the camera returns to its own framing" + label)
	for child: Node in actor.get_children():
		if str(child.name).begins_with("DozeZ"): _check(not child.visible, "The z's are gone once awake" + label)
	plain.free()
	viewport.free()

func _test_hud_strip() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 360)
	root.add_child(viewport)
	var controls := ChapterControls.new()
	viewport.add_child(controls)
	var state := {"duration_ticks": 600, "tick": 10, "context_action": {"label": "Ring bell", "enabled": false}, "can_commit": false}
	controls.update_state("High and Low", 10.0, state, true)
	_check(not controls.wait_row.visible and not controls.fast_forward_button.visible and controls.action_button.visible, "No wait row or wait buttons outside a wait")
	controls.show_memory_wait("Waiting for Sam", 0.5)
	controls.update_state("High and Low", 10.0, state, true)
	_check(controls.wait_row.visible and controls.wait_label.text == "Waiting for Sam" and is_equal_approx(controls.wait_bar.value, 0.5), "The wait row names the friend and shows the memory left")
	_check(controls.fast_forward_button.visible and controls.skip_wait_button.visible and not controls.action_button.visible and not controls.finish_button.visible, "Fast-forward and Skip take the action and finish places")
	var button := controls.fast_forward_button
	var before := button.get_instance_id()
	var touch := InputEventScreenTouch.new()
	touch.index = 1
	touch.pressed = true
	touch.position = button.get_global_rect().get_center()
	button._gui_input(touch)
	_check(controls.fast_forward_held(), "A second finger can hold Fast-forward")
	controls.show_memory_wait("Waiting for Sam", 0.4)
	controls.update_state("High and Low", 9.0, state, true)
	_check(controls.fast_forward_button.get_instance_id() == before and controls.fast_forward_held(), "Updates never rebuild the button under the finger")
	touch.pressed = false
	button._gui_input(touch)
	_check(not controls.fast_forward_held(), "Lifting the finger lets go")
	touch.pressed = true
	button._gui_input(touch)
	controls.hide_memory_wait()
	_check(not controls.fast_forward_held() and not button.held(), "The end of the wait lets go of a held Fast-forward")
	viewport.free()

static func _count(played: Array, key: String) -> int:
	var total := 0
	for cue: Dictionary in played: if cue.key == key: total += 1
	return total

static func _first(played: Array, key: String) -> Dictionary:
	for cue: Dictionary in played: if cue.key == key: return cue
	return {}

static func _index(played: Array, key: String) -> int:
	for index in range(played.size()): if played[index].key == key: return index
	return -1

## Every pinned chapter's fixture turns, the six-stage Lighthouse on both
## engines included: the wait is seen exactly when the engine's own objective
## is done before the memory ends, it lasts until the tick the memory ends, and
## only ringing cues are held.
var waits_seen: Dictionary = {}
## Worst microseconds per silently stepped tick, per chapter (what Skip pays).
var skip_cost: Dictionary = {}
## The pinned chapters whose fixture turns wait, plus First Steps, whose wait
## is read from its outcome rather than an objective flag. The other chapters
## read objective_done straight from their snapshot (see objective_done()),
## and replaying all of them here would take too long for one suite.
const SWEEP := [Registry.FIRST_STEPS, Registry.RELAY, Registry.LONG_WAY_HOME, Registry.LONG_WAY_HOME_V2, Registry.WISHING_WELL, Registry.LIGHTHOUSE_V2]
func _test_every_chapter() -> void:
	for key: String in SWEEP:
		var level := Registry.definition(key)
		var engine: Script = Registry.simulation_script(key)
		for name: String in ReplayGolden.CHAINS[key]:
			for pair: Dictionary in _fixture_pairs(key, ReplayGolden.CHAINS[key][name]):
				# A wait ends the turn exactly when the memory ends; First Steps
				# is followed throughout for its outcome-based reading.
				if key != Registry.FIRST_STEPS and int(pair.b.duration_ticks) != int(pair.a.duration_ticks): continue
				var sim: RefCounted = engine.new()
				sim.catch_assistance = bool(pair.b.get("catch_assistance", true))
				var label := "%s %s %s" % [key, name, pair.b.stage_id]
				if not _check(Registry.reset_simulation(sim, key, level, str(pair.b.stage_id), pair.at, pair.a, "b", pair.b), "Fixture resets: " + label): continue
				_follow(key, sim, engine.expand_recording_inputs(pair.b), pair.a, label)
	var six := Golden.fixture(ReplayGolden.LIGHTHOUSE_FIXTURE)
	for index in range(six.get("pairs", []).size()):
		var pair: Dictionary = six.pairs[index]
		if int(pair.b.duration_ticks) != int(pair.a.duration_ticks): continue
		var sim := Light.new()
		if not _check(sim.reset("b", pair.a, six.pairs.slice(0, index), int(pair.b.simulation_version)), "Lighthouse fixture resets: %d" % index): continue
		_follow(ReplayGolden.LIGHTHOUSE, sim, Light.expand_recording_inputs(pair.b), pair.a, "sleeping-lighthouse@1 %d" % index)
	print("Waits in fixture turns: ", waits_seen)
	print("Skip cost, usec per tick: ", skip_cost)
	for key: String in [Registry.RELAY, Registry.LONG_WAY_HOME_V2, Registry.WISHING_WELL, Registry.LIGHTHOUSE_V2, ReplayGolden.LIGHTHOUSE]:
		_check(waits_seen.has(key), "The fixture turns that wait are found: " + key)

## A chain's pairs, each with the checkpoint it starts from (the fixture's own,
## so nothing is re-derived here).
func _fixture_pairs(key: String, spec: Dictionary) -> Array:
	var pairs: Array = []
	var starts: Array = []
	if spec.has("bundle"):
		var bundle := Golden.fixture(spec.bundle)
		var source: Dictionary = bundle.get(spec.entry, {}) if not str(spec.entry).is_empty() else bundle
		pairs = source.get("pairs", []).duplicate()
		var checkpoints: Array = source.get("checkpoints", [])
		if checkpoints.size() == pairs.size() + 1: starts = checkpoints.slice(0, pairs.size())
		else:
			starts = [Registry.initial_checkpoint(key)]
			for index in range(pairs.size() - 1): starts.append(pairs[index].get("checkpoint", {}))
	else:
		starts = [Golden.fixture(spec.initial)]
		for files: Array in spec.stages:
			pairs.append({"a": Golden.fixture(files[0]), "b": Golden.fixture(files[1])})
			starts.append(Golden.fixture(files[2]))
	var result: Array = []
	for index in range(pairs.size()):
		result.append({"a": pairs[index].a, "b": pairs[index].b, "at": starts[index]})
	return result

## The engine's own objective flag, read only to cross-check the wait.
static func _engine_objective(sim: RefCounted) -> Variant:
	var inner: Variant = sim.get("_inner")
	var engine: Variant = inner if inner is RefCounted else sim
	for field: String in ["_objective_done", "_objective"]:
		var value: Variant = engine.get(field)
		if value is bool: return value
	return null

func _follow(key: String, sim: RefCounted, frames: Array, prior: Dictionary, label: String) -> void:
	var wait := MemoryWait.new()
	var prior_end := MemoryWait.prior_ticks(prior)
	wait.begin("b", prior_end)
	var seen := {}
	var agreed := true
	var started := -1
	var ended_at_memory := true
	var started_usec := Time.get_ticks_usec()
	for frame: Dictionary in frames:
		var state: Dictionary = sim.step(frame)
		var was := wait.waiting()
		var sounds := ChapterSoundMap.cues(key, state, seen)
		wait.step_silently(state, sounds)
		var own: Variant = _engine_objective(sim)
		if own is bool and own != MemoryWait.objective_done(state): agreed = false
		if wait.waiting() and not was:
			started = int(state.tick)
		if was and not wait.waiting() and not (bool(state.complete) and int(state.tick) == prior_end): ended_at_memory = false
	var per_tick := float(Time.get_ticks_usec() - started_usec) / maxf(1.0, float(frames.size()))
	skip_cost[key] = maxf(float(skip_cost.get(key, 0.0)), per_tick)
	_check(agreed, "The wait reads the same objective as the engine: " + label)
	if started >= 0:
		waits_seen[key] = int(waits_seen.get(key, 0)) + 1
		_check(started < prior_end, "A wait starts before the memory ends: " + label)
		_check(ended_at_memory, "A wait ends exactly when the memory ends: " + label)

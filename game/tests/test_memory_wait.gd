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
const LighthouseCatalog = preload("res://core/lighthouse/stage_catalog.gd")
const PlantAnimation = preload("res://presentation/plant_animation.gd")
const Joystick = preload("res://presentation/joystick.gd")
const FastForwardBadge = preload("res://presentation/fast_forward_badge.gd")
const SafeArea = preload("res://presentation/safe_area.gd")

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
	## Whether wait hints are hushed under the fast-forward mark, as last told.
	var hints_hushed := false
	func present(state: Dictionary, _immediate: bool = false) -> void: presented.append(state)
	func hush_wait_hints(hushed: bool) -> void: hints_hushed = hushed

class ControlsStub extends CanvasLayer:
	var held := false
	var waits: Array = []
	var stick := Control.new()
	func update_state(_title: String, _remaining: float, _state: Dictionary, _live: bool) -> void: pass
	func show_memory_wait(text: String, ratio: float, _skipping: bool = false) -> void: waits.append([text, ratio])
	func hide_memory_wait() -> void: pass
	func fast_forward_held() -> bool: return held
	func dim_stick(_dim: bool) -> void: pass
	func show_tries(_tries: int) -> void: pass

## The chapter screen with its save and turn check left out.
class Preview extends "res://relay_preview.gd":
	var finishes := 0
	## The tick of every draft save, in order.
	var drafts: Array = []
	var cards: Array = []
	## The pause and save-problem cards' actions, by id.
	var actions: Dictionary = {}
	var fail_saves := false
	func _persist_draft(after_retry: String = "play", _periodic: bool = false) -> bool:
		drafts.append(int(sim.snapshot().tick))
		if fail_saves: _show_save_problem("The disk is full.", after_retry)
		return not fail_saves
	## True runs the screen's own finish (a room test); otherwise it only stops.
	var real_finish := false
	func _finish() -> void:
		finishes += 1
		if real_finish: super._finish()
		else: running = false
	# The pause card without the chapter's own UI.
	func _card(_title: String, _body: String) -> VBoxContainer:
		running = false
		var card := VBoxContainer.new()
		cards.append(card)
		return card
	func _action_button(action_id: String, callback: Callable) -> Button:
		var button := Button.new()
		button.name = action_id
		actions[action_id] = callback
		return button
	func _add_safety_action(_card: VBoxContainer) -> void: pass
	func _add_redo_action(_card: VBoxContainer) -> void: pass

## The solo Lighthouse screen with its save and finish left out.
class LighthouseScreen extends "res://lighthouse_preview.gd":
	var finishes := 0
	var saves: Array = []
	var fail_saves := false
	func _save_draft(_after_retry: String = "play") -> bool:
		saves.append(int(sim.tick))
		if fail_saves:
			mode = "save_error"
			running = false
		return not fail_saves
	func _finish() -> void:
		finishes += 1
		running = false
	func _show_final_moment() -> void:
		finishes += 1
		running = false

class RoomStub extends RefCounted:
	var coordinator: RefCounted
	func busy() -> bool: return false
	func mutations_enabled() -> bool: return true
	func turn_tries_supported() -> bool: return false

class JourneyStub extends RefCounted:
	var sends := 0
	func snapshot() -> Dictionary: return {}
	func pending() -> Dictionary: return {}
	func stage_id() -> String: return ""
	func role() -> String: return "a"
	func checkpoint() -> Dictionary: return {}
	func prior_recording() -> Dictionary: return {}
	func commit(_recording: Dictionary, _tries: int = 0, _face: String = "") -> bool:
		sends += 1
		return true
	func accept_recording(_recording: Dictionary) -> bool:
		sends += 1
		return true

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
				_test_auto_skip_resumed_draft, _test_auto_skip_pause, _test_auto_skip_not_sent, _test_auto_skip_only_live,
				_test_world_doze_and_replay.bind(false), _test_world_doze_and_replay.bind(true),
				_test_lighthouse_world.bind(false), _test_lighthouse_world.bind(true), _test_hud_strip]:
			_timed(part)
	_timed(_test_every_chapter)
	_timed(_test_seed_held)
	_timed(_test_bloom_waits_for_ring)
	_timed(_test_auto_skip_save_fails)
	_timed(_test_lighthouse_auto_skip)
	await _test_skip_budget_per_frame()
	for reduced: bool in [false, true]:
		var started := Time.get_ticks_msec()
		await _test_fast_forward_badge(reduced)
		print("TIME _test_fast_forward_badge %d ms" % (Time.get_ticks_msec() - started))
	await _test_badge_safe_area()
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
	first_wait.auto_skip = true
	_check(not first_wait.auto_skip_due(), "Always skip waits has nothing to skip in a first turn")
	for value: Variant in [null, "true", 1, {}]:
		_check(not MemoryWait.skip_waits({"skip_waits": value}), "A saved %s reads as off" % str(value))
	_check(not MemoryWait.skip_waits({}) and MemoryWait.skip_waits({"skip_waits": true}), "Always skip waits is on only when saved on")

## A still player at normal speed, Hold to fast-forward and Skip to end all
## leave the same simulation and the same recording, byte for byte.
func _test_identity() -> void:
	var still := _receiver()
	for input: Dictionary in to_ring: still.step(input)
	while not still.finished: still.step(STILL)
	var expected: Dictionary = still.export_recording()
	_check(bool(still.complete), "At normal speed the stage completes when the memory ends")
	for way: String in ["normal", "fast_forward", "skip", "auto", "fast_forward_slow_phone", "skip_slow_phone", "auto_slow_phone"]:
		var auto := way.begins_with("auto")
		var run := _preview_to_ring(auto)
		var preview: Preview = run.preview
		var controls: ControlsStub = run.controls
		# A huge budget pins the speed checks; a slow phone (1 usec) still
		# reaches the very same end, only over more frames.
		var slow := way.ends_with("_slow_phone")
		preview.memory_wait.step_budget_usec = 1 if slow else 1 << 40
		preview.memory_wait.skip_budget_usec = 1 if slow else 1 << 40
		var drafts_before := preview.drafts.size()
		if slow:
			controls.held = way.begins_with("fast_forward")
			if way.begins_with("skip"): preview._skip_memory_wait()
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
			if not auto: preview._skip_memory_wait()
			var skip_ticks := 0
			while preview.running and skip_ticks < 10000:
				preview._physics_process(1.0 / 30.0)
				skip_ticks += 1
			_check(skip_ticks <= 2, "With frame time to spare, Skip reaches the end at once: " + way)
		if way.contains("skip") or auto:
			_check(preview.drafts.size() > drafts_before and preview.drafts[drafts_before] == to_ring.size(), "The draft is saved at the press, before the skip steps on: " + way)
		_check(preview.finishes == 1, "The turn ends once: " + way)
		_check(preview.sim.state_hash() == still.state_hash(), "The final state is byte-identical: " + way)
		_check(Canonical.same(preview.sim.export_recording(), expected) and JSON.stringify(preview.sim.export_recording()) == JSON.stringify(expected), "The recording is byte-identical: " + way)
		_free_preview(run)

func _preview_to_ring(auto_skip: bool = false, preview: Preview = null) -> Dictionary:
	if preview == null: preview = Preview.new()
	preview.memory_wait.step_budget_usec = 1 << 40
	preview.memory_wait.skip_budget_usec = 1 << 40
	var controls := ControlsStub.new()
	var sound := CueLog.new()
	var world := WorldStub.new()
	preview.chapter_key = KEY
	preview.chapter = Registry.descriptor(KEY)
	preview.definition = Registry.definition(KEY)
	preview.checkpoint = Registry.initial_checkpoint(KEY).duplicate()
	preview.checkpoint["stage_index"] = 0
	preview.settings = {"sound": true, "haptics": false, "reduced_motion": false, "skip_waits": auto_skip}
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
	for card: Node in run.preview.cards: card.free()
	for part: String in ["stick", "overlay", "hud", "hint_label", "action_button", "finish_button"]:
		var node: Variant = run.preview.get(part)
		if is_instance_valid(node): node.free()
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
	for way: String in ["normal", "fast_forward", "skip", "auto"]:
		var run := _preview_to_ring(way == "auto")
		var preview: Preview = run.preview
		var sound: CueLog = run.sound
		_check(_count(sound.played, "bell_rung") == 0, "The bell is silent at the press: " + way)
		if way == "normal":
			while preview.running: preview.advance_input(STILL)
		elif way == "fast_forward":
			run.controls.held = true
			while preview.running: preview._physics_process(1.0 / 30.0)
		else:
			if way == "skip": preview._skip_memory_wait()
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
	_check(not controls.fast_forward_badge.active(), "No fast-forward mark while the wait plays at normal speed")
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
	_check(controls.fast_forward_badge.active(), "Holding Fast-forward shows the fast-forward mark")
	touch.pressed = false
	button._gui_input(touch)
	_check(not controls.fast_forward_held(), "Lifting the finger lets go")
	controls.show_memory_wait("Waiting for Sam", 0.3)
	_check(not controls.fast_forward_badge.active(), "Letting go of Fast-forward lets the mark go")
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

## The seed chapters: a seed planted or placed while the friend's memory still
## plays stays in the dozing spirit's hands, its cue silent, until the memory
## ends; after the wake the seed goes in (the planting beat for a planted one)
## and its cue sounds once, at the pitch it had at the press. Each fixture turn
## of the seed chapters that waits is replayed in its real world, and each
## fixture turn is also made to wait by letting its memory linger.
func _test_seed_held() -> void:
	var goals_seen: Dictionary = {}
	for key: String in [Registry.RELAY, Registry.FIRST_STEPS]:
		for name: String in ReplayGolden.CHAINS[key]:
			for pair: Dictionary in _fixture_pairs(key, ReplayGolden.CHAINS[key][name]):
				var label := "%s %s %s" % [key, name, pair.b.stage_id]
				var lingering := _lingering_pair(key, pair)
				for turn: Dictionary in [pair, lingering]:
					if turn.is_empty(): continue
					var goal := _seed_wait(key, turn, label + (" lingering" if turn == lingering else ""))
					if not goal.is_empty(): goals_seen[goal] = int(goals_seen.get(goal, 0)) + 1
	print("Seed waits replayed by goal: ", goals_seen)
	_check(goals_seen.has("planted") and goals_seen.has("socket"), "A planted seed and a seed placed in the relay are both seen held through a wait")

## The same pair with the memory lingering LINGER_TICKS longer and the second
## turn standing still to the new end, or {} if that is not a valid turn.
func _lingering_pair(key: String, pair: Dictionary) -> Dictionary:
	var level := Registry.definition(key)
	var engine: Script = Registry.simulation_script(key)
	var a: RefCounted = engine.new()
	a.catch_assistance = bool(pair.a.get("catch_assistance", true))
	if not Registry.reset_simulation(a, key, level, str(pair.a.stage_id), pair.at, {}, "a", pair.a): return {}
	for input: Dictionary in engine.expand_recording_inputs(pair.a): a.step(input)
	for _tick in range(LINGER_TICKS):
		if a.finished: break
		a.step(STILL)
	if not a.can_commit(): return {}
	var first_turn: Dictionary = a.export_recording()
	var b: RefCounted = engine.new()
	b.catch_assistance = bool(pair.b.get("catch_assistance", true))
	if not Registry.reset_simulation(b, key, level, str(pair.b.stage_id), pair.at, first_turn, "b"): return {}
	var frames: Array = engine.expand_recording_inputs(pair.b)
	var index := 0
	while not b.finished and index < 20000:
		b.step(frames[index] if index < frames.size() else STILL)
		index += 1
	if not bool(b.complete): return {}
	return {"a": first_turn, "b": b.export_recording(), "at": pair.at}

const NO_SOUNDS := {"cues": [], "sources": []}

## Replays one second turn in its real world through MemoryWait. Returns the
## seed's status after the goal ("planted", "socket"), or "" if it never waited.
func _seed_wait(key: String, pair: Dictionary, label: String) -> String:
	var level := Registry.definition(key)
	var engine: Script = Registry.simulation_script(key)
	var make := func() -> RefCounted:
		var sim: RefCounted = engine.new()
		sim.catch_assistance = bool(pair.b.get("catch_assistance", true))
		Registry.reset_simulation(sim, key, level, str(pair.b.stage_id), pair.at, pair.a, "b", pair.b)
		return sim
	var frames: Array = engine.expand_recording_inputs(pair.b)
	var prior_end := MemoryWait.prior_ticks(pair.a)
	var probe := MemoryWait.new()
	probe.begin("b", prior_end)
	var probe_sim: RefCounted = make.call()
	for input: Dictionary in frames: probe.step_silently(probe_sim.step(input), NO_SOUNDS)
	# Only a seed goal (not First Steps' loft) keeps the seed in hand.
	if not probe.waited or str(probe_sim.snapshot().seed.status) not in ["planted", "socket"]: return ""
	# Nothing held: the cues as they sounded before waits held seeds.
	var plain := CueLog.new()
	plain.begin_turn(key, str(pair.b.stage_id))
	var plain_seen := {}
	var reference: RefCounted = make.call()
	for input: Dictionary in frames:
		var state: Dictionary = reference.step(input)
		var sounds := ChapterSoundMap.cues(key, state, plain_seen)
		plain.consume_turn_events(sounds.cues, sounds.sources, false)
	var stage: Dictionary = {}
	for item: Dictionary in level.stages: if item.id == pair.b.stage_id: stage = item
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1560, 720)
	root.add_child(viewport)
	var world: Node3D = Registry.world_script(key).new()
	viewport.add_child(world)
	world.load_level(level)
	world.show_stage(stage)
	if world.has_method("present_history"): world.present_history(pair.at)
	var sound := CueLog.new()
	viewport.add_child(sound)
	sound.begin_turn(key, str(pair.b.stage_id))
	var wait := MemoryWait.new()
	wait.world = world
	wait.soundscape = sound
	wait.begin("b", prior_end)
	var sim: RefCounted = make.call()
	var seen := {}
	wait.show(sim.snapshot(), true)
	var waited_ticks := 0
	var carried := true
	var dozed := false
	var planted_early := false
	var cue_early := false
	## Seed cues heard before the press (the memory may open the garden).
	var before_wait := 0
	var goal := ""
	var live := ""
	for input: Dictionary in frames:
		var state: Dictionary = sim.step(input)
		live = str(state.active_slot)
		wait.step(state, ChapterSoundMap.cues(key, state, seen), false)
		world._process(1.0 / 30.0)
		wait.advance(1.0 / 30.0)
		goal = str(state.seed.status)
		if wait.waiting():
			waited_ticks += 1
			var actor: Node3D = world.actors.get(live)
			carried = carried and actor != null and world.seed.visible and str(world.get("_seed_holder")) == live and bool(actor.carrying_seed)
			if carried: carried = world.seed.position.distance_to(actor.position + actor.carry_anchor_position()) < 0.05
			dozed = dozed or (actor != null and actor.pose() == SpiritIdle.DOZE)
			planted_early = planted_early or not PlantAnimation.running(world.terrain).is_empty()
			cue_early = cue_early or _seed_cues(sound.played) > before_wait
		else: before_wait = _seed_cues(sound.played)
	_check(waited_ticks > 0 and goal in ["planted", "socket"], "The seed goal is reached before the memory ends: " + label)
	_check(carried, "The waiting spirit keeps carrying the seed: " + label)
	_check(dozed, "The spirit dozes with the seed: " + label)
	_check(not planted_early, "No planting beat during the wait: " + label)
	_check(not cue_early, "The seed's cue is silent during the wait: " + label)
	_check(wait.ring_pending() and world.seed.visible, "At the arrival the spirit wakes still holding the seed: " + label)
	for _frame in range(40):
		world._process(FRAME)
		wait.advance(FRAME)
	_check(not wait.ring_pending() and wait.rings_released == 1, "After the wake the seed goes in: " + label)
	if goal == "planted":
		_check(not PlantAnimation.running(world.terrain).is_empty() and not world.seed.visible, "The planting beat plays after the wake: " + label)
	else:
		_check(world.seed.visible and str(world.get("_seed_holder")).is_empty(), "The seed sits in the relay after the wake: " + label)
	var same := true
	for cue: String in Soundscape.CLIPS:
		if _count(sound.played, cue) != _count(plain.played, cue): same = false
	_check(same, "Every cue sounds as often as with nothing held: " + label)
	for cue: String in ["island_bloomed", "garden_opened"]:
		_check(_first(sound.played, cue).get("step") == _first(plain.played, cue).get("step"), "A held seed cue keeps its pitch (%s): %s" % [cue, label])
	plain.free()
	viewport.free()
	return goal

static func _seed_cues(played: Array) -> int:
	return _count(played, "island_bloomed") + _count(played, "garden_opened")

## The review waits for the goal's ring, so a planting beat that starts at the
## ring plays whole before the review card covers it.
func _test_bloom_waits_for_ring() -> void:
	_check(PlantAnimation.DURATION <= Preview.COMPLETION_DURATION, "The planting beat fits in the completion hold")
	var run := _preview_to_ring()
	var preview: Preview = run.preview
	while preview.running: preview.advance_input(STILL)
	_check(preview.memory_wait.ring_pending(), "The friend has arrived and the ring waits for the wake")
	preview.mode = "bloom"
	_check(not preview.completion_counting(), "The completion hold does not count before the ring")
	var elapsed := 0.0
	while preview.memory_wait.ring_pending() and elapsed < 2.0:
		preview.memory_wait.advance(FRAME)
		elapsed += FRAME
	_check(preview.completion_counting(), "The completion hold counts from the ring")
	preview.mode = "ready"
	_free_preview(run)

## The recording a still player makes, waiting the memory out at normal speed.
func _still_recording() -> Dictionary:
	var still := _receiver()
	for input: Dictionary in to_ring: still.step(input)
	while not still.finished: still.step(STILL)
	return {"recording": still.export_recording(), "hash": still.state_hash()}

func _same_as_still(preview: Preview, expected: Dictionary, label: String) -> void:
	_check(preview.sim.state_hash() == expected.hash, "The final state is byte-identical: " + label)
	_check(JSON.stringify(preview.sim.export_recording()) == JSON.stringify(expected.recording), "The recording is byte-identical: " + label)

## Always skip waits on a draft resumed in the middle of the wait (the
## screen's _resume_draft steps it silently, then plays on): it skips again.
func _test_auto_skip_resumed_draft() -> void:
	var expected := _still_recording()
	var run := _preview_to_ring(true)
	var preview: Preview = run.preview
	preview.memory_wait.auto_skip = false
	for _tick in range(40): preview.advance_input(STILL)
	var draft: Dictionary = preview.sim.export_recording()
	_free_preview(run)
	var resumed := Preview.new()
	var controls := ControlsStub.new()
	var sound := CueLog.new()
	var world := WorldStub.new()
	resumed.memory_wait.skip_budget_usec = 1 << 40
	resumed.chapter_key = KEY
	resumed.chapter = Registry.descriptor(KEY)
	resumed.definition = Registry.definition(KEY)
	resumed.checkpoint = Registry.initial_checkpoint(KEY).duplicate()
	resumed.checkpoint["stage_index"] = 0
	resumed.settings = {"sound": true, "haptics": false, "reduced_motion": false, "skip_waits": true}
	resumed.controls = controls
	resumed.soundscape = sound
	resumed.world = world
	resumed.sim = _receiver()
	resumed.role = "b"
	sound.begin_turn(KEY, STAGE)
	resumed._begin_sound_turn()
	resumed._begin_memory_wait("b", first)
	# What the screen's _fast_forward does with a saved draft.
	for input: Dictionary in Simulation.expand_recording_inputs(draft):
		var state: Dictionary = resumed.sim.step(input)
		resumed.memory_wait.step_silently(state, resumed._turn_sounds(state))
	resumed.mode = "play"
	resumed.running = true
	_check(resumed.memory_wait.waiting() and resumed.memory_wait.auto_skip_due(), "A draft resumed mid-wait is due a skip")
	var ticks := 0
	while resumed.running and ticks < 10000:
		resumed._physics_process(1.0 / 30.0)
		ticks += 1
	_check(ticks <= 2 and resumed.finishes == 1, "The resumed draft skips straight to the end")
	_check(resumed.drafts == [int(draft.duration_ticks)], "The resumed skip saves the draft once, where it resumed")
	_same_as_still(resumed, expected, "resumed draft, auto")
	for _frame in range(60): resumed.memory_wait.advance(FRAME)
	_check(_count(sound.played, "bell_rung") == 1, "The resumed skip rings once")
	_free_preview({"preview": resumed, "controls": controls, "sound": sound, "world": world})

## Pause (the app goes to the background) in the middle of an automatic skip:
## the draft is saved where the skip got to, nothing steps while paused, and
## Resume finishes the same skip with the same recording and the same bell.
func _test_auto_skip_pause() -> void:
	var expected := _still_recording()
	var run := _preview_to_ring(true)
	var preview: Preview = run.preview
	var before: int = preview.drafts.size()
	preview.stick = Joystick.new()
	preview.overlay = Control.new()
	preview.hud = Control.new()
	# A slow phone: one tick per physics tick.
	preview.memory_wait.skip_budget_usec = 1
	preview._physics_process(1.0 / 30.0)
	_check(preview.memory_wait.skipping and preview.drafts.slice(before) == [to_ring.size()], "The skip starts by itself on the next physics tick, after a draft save at the press")
	for _tick in range(5): preview._physics_process(1.0 / 30.0)
	var at := int(preview.sim.snapshot().tick)
	_check(at > to_ring.size() and at < int(first.duration_ticks), "The skip is under way")
	preview._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(preview.mode == "paused" and not preview.running and preview.drafts[-1] == at, "Backgrounding pauses the skip and saves the draft where it got to")
	for _tick in range(10): preview._physics_process(1.0 / 30.0)
	_check(int(preview.sim.snapshot().tick) == at, "Nothing steps while paused")
	preview._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	preview._start_play()
	_check(preview.memory_wait.skipping and not preview.memory_wait.auto_skip_due(), "Resume carries on with the same skip")
	preview.memory_wait.skip_budget_usec = 1 << 40
	var ticks := 0
	while preview.running and ticks < 10000:
		preview._physics_process(1.0 / 30.0)
		ticks += 1
	_check(preview.finishes == 1 and preview.drafts.size() == before + 2, "The resumed skip ends the turn once, with no further skip-start save")
	_same_as_still(preview, expected, "paused auto skip")
	for _frame in range(60): preview.memory_wait.advance(FRAME)
	_check(_count(run.sound.played, "bell_rung") == 1, "The paused skip still rings once")
	_free_preview(run)

## A friend's room: the automatic skip reaches the friend's arrival and the
## completion bloom with the real finish, and nothing sends the turn.
func _test_auto_skip_not_sent() -> void:
	var expected := _still_recording()
	var preview := Preview.new()
	preview.real_finish = true
	var journey := JourneyStub.new()
	var room := RoomStub.new()
	room.coordinator = journey
	preview.journey = journey
	preview.online_session = room
	preview.hint_label = Label.new()
	preview.stick = Joystick.new()
	preview.action_button = Button.new()
	preview.finish_button = Button.new()
	var run := _preview_to_ring(true, preview)
	var ticks := 0
	while preview.running and ticks < 10000:
		preview._physics_process(1.0 / 30.0)
		ticks += 1
	_check(preview.finishes == 1 and preview.mode == "bloom", "The skipped room turn reaches the completion bloom")
	_check(JSON.stringify(preview.review) == JSON.stringify(expected.recording), "The turn kept for review is the still player's, byte for byte")
	for _frame in range(60): preview.memory_wait.advance(FRAME)
	_check(journey.sends == 0, "Nothing sends the turn: the player's Save on the review card does")
	preview.mode = "ready"
	_free_preview(run)

## Replays and anything but live play never skip by themselves: the screen's
## own Skip refuses them, as it refuses a tap.
func _test_auto_skip_only_live() -> void:
	var run := _preview_to_ring(true)
	var preview: Preview = run.preview
	for mode: String in ["replay", "paused", "bloom"]:
		preview.mode = mode
		preview._fast_forward_wait()
		_check(not preview.memory_wait.skipping, "No automatic skip in " + mode)
	preview.mode = "play"
	preview.backgrounded = true
	preview._fast_forward_wait()
	_check(not preview.memory_wait.skipping, "No automatic skip while backgrounded")
	preview.backgrounded = false
	var off := _preview_to_ring(false)
	off.preview._fast_forward_wait()
	_check(not off.preview.memory_wait.skipping and off.preview.memory_wait.waiting(), "With the setting off the wait plays as before")
	_free_preview(off)
	preview.mode = "ready"
	_free_preview(run)

## The skip's budget is per rendered frame: a physics tick catching up in a
## frame that has spent it steps once, and the next frame gets it back.
func _test_skip_budget_per_frame() -> void:
	var run := _preview_to_ring()
	var preview: Preview = run.preview
	var wait: RefCounted = preview.memory_wait
	wait.skipping = true
	wait.skip_budget_usec = 3000
	var ticks := func() -> int: return int(preview.sim.snapshot().tick)
	var shown := func() -> int: return run.world.presented.size()
	await process_frame
	var start: int = ticks.call()
	wait.skip_tick(preview.sim, preview._turn_sounds, preview.advance_input)
	var first: int = ticks.call() - start
	var shown_first: int = shown.call()
	start = ticks.call()
	wait.skip_tick(preview.sim, preview._turn_sounds, preview.advance_input)
	_check(first > 1 and ticks.call() - start == 1, "A tick catching up in a spent frame steps once (%d, then %d)" % [first, ticks.call() - start])
	_check(shown.call() == shown_first, "and does not show the world a second time that frame")
	await process_frame
	start = ticks.call()
	wait.skip_tick(preview.sim, preview._turn_sounds, preview.advance_input)
	_check(ticks.call() - start > 1 and shown.call() == shown_first + 1, "The next frame gets the whole budget back")
	wait.skipping = false
	preview.mode = "ready"
	_free_preview(run)

## A draft that cannot be saved as the skip starts: the save problem card
## shows, no skip starts and nothing steps; Retry saves and the skip goes on.
func _test_auto_skip_save_fails() -> void:
	var expected := _still_recording()
	var run := _preview_to_ring(true)
	var preview: Preview = run.preview
	preview.overlay = Control.new()
	preview.hud = Control.new()
	preview.fail_saves = true
	var at := int(preview.sim.snapshot().tick)
	preview._physics_process(1.0 / 30.0)
	_check(preview.mode == "save_error" and not preview.running and not preview.memory_wait.skipping, "A failed save at the skip's start shows the save problem and starts no skip")
	for _tick in range(5): preview._physics_process(1.0 / 30.0)
	_check(int(preview.sim.snapshot().tick) == at and preview.actions.has("retry_save"), "Nothing steps behind the save problem, and it offers Retry")
	preview.fail_saves = false
	preview.actions["retry_save"].call()
	_check(preview.mode == "play" and preview.running, "Retry saves and plays on")
	var ticks := 0
	while preview.running and ticks < 10000:
		preview._physics_process(1.0 / 30.0)
		ticks += 1
	_check(preview.finishes == 1 and ticks <= 2, "Then the skip starts by itself and reaches the end")
	_same_as_still(preview, expected, "skip after a failed save")
	_free_preview(run)

## The solo Lighthouse screen (lighthouse_preview.gd): its own Skip is pressed
## by Always skip waits after its draft save, refused when that save fails,
## and leaves the same turn as a still player at normal speed.
func _test_lighthouse_auto_skip() -> void:
	var six := Golden.fixture(ReplayGolden.LIGHTHOUSE_FIXTURE)
	var tried := 0
	for index in range(six.pairs.size() - 1):
		var pair: Dictionary = six.pairs[index]
		if int(pair.b.duration_ticks) != int(pair.a.duration_ticks): continue
		var prefix: Array = six.pairs.slice(0, index)
		var frames: Array = Light.expand_recording_inputs(pair.b)
		var probe := Light.new()
		probe.reset("b", pair.a, prefix, int(pair.b.simulation_version))
		var press := -1
		for tick in range(frames.size()):
			if MemoryWait.objective_done(probe.step(frames[tick])):
				press = tick + 1
				break
		if press < 0 or press >= int(pair.a.duration_ticks) - 2: continue
		var still := Light.new()
		still.reset("b", pair.a, prefix, int(pair.b.simulation_version))
		for tick in range(press): still.step(frames[tick])
		while not still.finished: still.step(STILL)
		for failing: bool in [true, false]:
			var label := " (Lighthouse %d%s)" % [index, ", failed save" if failing else ""]
			var screen := LighthouseScreen.new()
			var controls := ControlsStub.new()
			var sound := CueLog.new()
			var world := WorldStub.new()
			screen.controls = controls
			screen.soundscape = sound
			screen.world = world
			screen.settings = {"sound": true, "reduced_motion": false, "skip_waits": true}
			screen.sim = Light.new()
			screen.sim.reset("b", pair.a, prefix, int(pair.b.simulation_version))
			screen.stage = LighthouseCatalog.definition(str(pair.b.stage_id))
			screen.checkpoint = Light.checkpoint_from_pairs(prefix).checkpoint if not prefix.is_empty() else {"stage_index": 0}
			screen.role = "b"
			screen.mode = "play"
			screen.running = true
			screen._begin_sound_turn()
			screen._begin_memory_wait("b", pair.a)
			for tick in range(press): screen.advance_input(frames[tick])
			_check(screen.memory_wait.waiting() and screen.memory_wait.auto_skip_due(), "The Lighthouse wait is due a skip" + label)
			var before: int = screen.saves.size()
			screen.fail_saves = failing
			screen.memory_wait.skip_budget_usec = 1 << 40
			var ticks := 0
			while screen.running and ticks < 10000:
				screen._physics_process(1.0 / 30.0)
				ticks += 1
			if failing:
				_check(screen.mode == "save_error" and not screen.memory_wait.skipping and int(screen.sim.tick) == press, "A failed save refuses the Lighthouse skip" + label)
			else:
				_check(screen.saves.slice(before) == [press] and screen.finishes == 1 and ticks <= 2, "The Lighthouse skip saves at the press and reaches the end%s (saves %s, press %d, ticks %d)" % [label, str(screen.saves.slice(before)), press, ticks])
				_check(screen.sim.state_hash() == still.state_hash() and JSON.stringify(screen.sim.export_recording()) == JSON.stringify(still.export_recording()), "The Lighthouse turn is byte-identical to a still player" + label)
				for _frame in range(60): screen.memory_wait.advance(FRAME)
				_check(screen.memory_wait.rings_released == 1, "The Lighthouse ring is released once" + label)
			controls.stick.free()
			for part: Node in [controls, sound, world, screen]: part.free()
		tried += 1
		break
	_check(tried == 1, "A solo Lighthouse fixture turn waits for its memory")
## The fast-forward mark in the real chapter controls: it fades in as the
## skip starts, never takes a touch, breathes only without Reduce motion, and
## lets go as the friend arrives, before the ring.
func _test_fast_forward_badge(reduced: bool) -> void:
	var label := " (Reduce motion)" if reduced else ""
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1560, 720)
	root.add_child(viewport)
	var controls := ChapterControls.new()
	controls.settings = {"reduced_motion": reduced}
	viewport.add_child(controls)
	var run := _preview_to_ring(true)
	var preview: Preview = run.preview
	preview.controls = controls
	var badge: Control = controls.fast_forward_badge
	_check(not badge.visible and not badge.active(), "No fast-forward mark before the skip" + label)
	# A slow phone: one tick per physics tick, so the skip lasts a while.
	preview.memory_wait.skip_budget_usec = 1
	preview._physics_process(1.0 / 30.0)
	_check(badge.active() and badge.visible, "The mark shows as the skip starts" + label)
	_check(run.world.hints_hushed, "Wait hints step aside while the mark shows" + label)
	var ignored := badge.mouse_filter == Control.MOUSE_FILTER_IGNORE
	for child: Node in badge.find_children("*", "Control", true, false): ignored = ignored and (child as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE
	_check(ignored, "The mark never takes a touch" + label)
	# Rendered frames go by while the skip is under way (it steps only on
	# physics ticks, which this test drives by hand).
	var swell := 1.0
	var until := Time.get_ticks_msec() + int((FastForwardBadge.FADE_IN + FastForwardBadge.PULSE) * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
		swell = maxf(swell, badge.scale.x)
	var steps := 0
	_check(is_equal_approx(badge.modulate.a, 1.0) and badge.active(), "The mark has faded in while the skip runs" + label)
	if reduced: _check(is_equal_approx(swell, 1.0), "Reduce motion: the mark holds still")
	else: _check(swell > 1.02, "The mark breathes gently")
	var stayed := true
	while preview.running and steps < 20000:
		preview._physics_process(1.0 / 30.0)
		if preview.memory_wait.waiting(): stayed = stayed and badge.active()
		steps += 1
	_check(stayed, "The mark stays for the whole skip" + label)
	_check(not badge.active() and preview.memory_wait.ring_pending(), "The mark lets go as the friend arrives, before the ring" + label)
	_check(not run.world.hints_hushed, "and wait hints may show again" + label)
	await create_timer(FastForwardBadge.FADE_OUT + 0.25).timeout
	_check(not badge.visible and is_zero_approx(badge.modulate.a) and badge.scale == Vector2.ONE, "Then it has faded out" + label)
	preview.controls = run.controls
	_free_preview(run)
	viewport.free()

## A landscape phone with its camera hole on either side: the mark stays
## inside the safe area, where the chapter controls' content root is inset.
func _test_badge_safe_area() -> void:
	# A phone-shaped window with the project's stretch, as test_cutout_full_bleed sets it.
	var original := {"size": root.size, "content_scale_size": root.content_scale_size, "content_scale_mode": root.content_scale_mode, "content_scale_aspect": root.content_scale_aspect}
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size = Vector2i(1600, 738)
	await process_frame
	var controls := ChapterControls.new()
	root.add_child(controls)
	await process_frame
	var visible := root.get_visible_rect()
	var native := root.get_screen_transform() * visible
	for side: String in ["left", "right"]:
		var inset := 180.0
		SafeArea.simulate(Rect2(native.position + Vector2(inset if side == "left" else 0.0, 0.0), native.size - Vector2(inset, 0.0)))
		root.size_changed.emit()
		controls.show_memory_wait("Waiting for Sam", 0.5, true)
		await process_frame
		await process_frame
		var safe := SafeArea.rect(root)
		var badge: Control = controls.fast_forward_badge
		_check(safe.size.x < visible.size.x and safe.encloses(badge.get_global_rect()), "The fast-forward mark sits inside the safe area with a %s cutout (%s in %s)" % [side, str(badge.get_global_rect()), str(safe)])
		controls.hide_memory_wait()
	SafeArea.simulate(Rect2())
	controls.free()
	for property: String in original: root.set(property, original[property])
	await process_frame

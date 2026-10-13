extends SceneTree
## Save turn on a solo chapter replays the finished turn once. The journey
## checks it from its own proven checkpoint, keeps a successful result for the
## Save that follows, and builds the next checkpoint from that same check.
## Every verdict, snapshot and checkpoint must equal what the public
## verify_recording / derive_checkpoint produce, and the saved journal must
## load back through the full chain check unchanged.
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Preview = preload("res://relay_preview.gd")
const RelaySimulation = preload("res://core/v2/simulation_v2.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Reaper = preload("res://services/worker_reaper.gd")

class CountingJourney extends "res://services/relay_journey.gd":
	var replays := 0
	func _verify_on_checkpoint(recording: Dictionary) -> Dictionary:
		replays += 1
		return super(recording)

var checks := 0
var failures := 0
var directory := ""
## Which family dispatch each covered chapter used (raw static or _proof).
var modes := {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = "user://turn-save-checks-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	var covered := 0
	# One chapter per simulation family, each with every stage in fixtures.
	for spec: Dictionary in [
		{"chapter": Registry.FIRST_STEPS, "folder": "first_steps", "rules": 0},
		{"chapter": Registry.RELAY, "folder": "v2", "rules": 2, "names": ["relay", "garden"]},
		{"chapter": Registry.WISHING_WELL, "folder": "cooperative", "rules": 0},
		{"chapter": Registry.TURN_OF_THE_TIDE, "folder": "journey", "rules": 0},
	]:
		if not Registry.keys().has(str(spec.chapter)): continue
		if _chapter(spec): covered += 1
	_check(covered >= 3, "At least three simulation families are covered (%d)" % covered)
	_check(modes.has("raw") and modes.has("proof"), "Both the static and the proof-engine checks are exercised: " + str(modes.keys()))
	await _visible_wait()
	await _prefetch_scene()
	print("TURN SAVE CHECKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _chapter(spec: Dictionary) -> bool:
	var chapter := str(spec.chapter)
	var level := Registry.definition(chapter)
	var family: Script = Registry.simulation_script(chapter)
	var path := directory + "/" + chapter.validate_filename() + ".json"
	var journey := CountingJourney.new(path, null, chapter)
	journey.load_data()
	if int(spec.rules) > 0: journey._state.simulation_version = int(spec.rules)
	modes["raw" if journey._has_static("_verify_raw") else ("proof" if journey._has_static("_proof") else "public")] = true
	var names: Array = spec.get("names", level.stages.map(func(stage: Dictionary) -> String: return str(stage.id)))
	for index in range(names.size()):
		for role: String in ["a", "b"]:
			var recording := _fixture(str(spec.folder) + "/" + str(names[index]) + "-" + role)
			if recording.is_empty():
				_check(false, "%s: fixture %s-%s exists" % [chapter, names[index], role])
				return false
			var start := journey.checkpoint()
			var prior := journey.prior_recording()
			var label := "%s %s/%s" % [chapter, names[index], role]
			var public: Dictionary = family.verify_recording(level, recording, start, prior)
			var trusted: Dictionary = journey._verify_on_checkpoint(recording)
			_check(public.get("valid", false) and trusted.get("valid", false) and Canonical.same(public.snapshot, trusted.snapshot), label + ": the check from the proven checkpoint equals the public check")
			if role == "b":
				var derived: Dictionary = family.derive_checkpoint(level, start, prior, recording)
				var built: Dictionary = journey._next_checkpoint(prior, recording, trusted)
				_check(derived.get("valid", false) and built.get("valid", false) and Canonical.same(derived.checkpoint, built.checkpoint), label + ": the next checkpoint equals derive_checkpoint")
			# A tampered turn fails and is never kept.
			var tampered := recording.duplicate(true)
			tampered.final_state_hash = "0".repeat(64)
			var kept: int = journey._verified_turns.size()
			var before := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
			_check(not journey.verify_turn(tampered).get("valid", true) and journey._verified_turns.size() == kept, label + ": a tampered turn fails and is not remembered")
			_check(not journey.accept_recording(tampered) and (FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()) == before, label + ": a tampered turn is never saved")
			# The real flow: review, then Save turn, replays the turn once.
			journey.replays = 0
			var reviewed: Dictionary = journey.verify_turn(recording)
			# While a first turn's review is up, the turn after it is set up on
			# a worker from the same inputs a fresh setup reads.
			var job: Dictionary = journey.next_turn_job(recording) if role == "a" else {}
			var worker: Thread = null
			if not job.is_empty():
				worker = Thread.new()
				_check(worker.start(Callable(Journey, "build_live").bind(job)) == OK, label + ": the next turn starts setting up on a worker")
			_check(role == "a" or journey.next_turn_job(recording).is_empty(), label + ": only a first turn prefetches the turn after it")
			var saved: bool = journey.accept_recording(recording)
			_check(reviewed.get("valid", false) and Canonical.same(reviewed.snapshot, public.snapshot), label + ": the review check is the public verdict")
			_check(saved and journey.replays == 1, label + ": review and Save turn replay the turn once (%d)" % journey.replays)
			if worker != null and worker.is_started():
				_prefetched_equals_direct(journey, job, worker.wait_to_finish(), family, _fixture(str(spec.folder) + "/" + str(names[index]) + "-b"), label)
			var full: Dictionary = journey._validate_state(journey._state)
			_check(full.get("valid", false) and Canonical.same(full.checkpoint, journey._checkpoint), label + ": the saved state passes the full chain check with the same checkpoint")
			var reopened := Journey.new(path, null, chapter)
			reopened.load_data()
			_check(not reopened.read_only and Canonical.same(reopened._state, journey._state) and Canonical.same(reopened.checkpoint(), journey.checkpoint()), label + ": the journal loads back through the full check unchanged")
	_check(journey.chapter_complete(), chapter + ": every stage was saved")
	return true

## The turn a worker set up must be the turn this thread sets up: same state,
## snapshot and inputs, and B's whole turn played on each ends identically.
## A job for other inputs is refused.
func _prefetched_equals_direct(journey: RefCounted, job: Dictionary, built: Dictionary, family: Script, second: Dictionary, label: String) -> void:
	var wrong := job.duplicate(true)
	wrong.prior = {}
	_check(journey.adopt_live_simulation(wrong, built) == null, label + ": a prefetch built from other inputs is refused")
	var adopted: RefCounted = journey.adopt_live_simulation(job, built)
	_check(adopted != null and journey.is_live_simulation(adopted), label + ": the prefetched next turn is adopted as the live turn")
	var direct: RefCounted = journey.create_live_simulation(false)
	if adopted == null or direct == null:
		_check(false, label + ": both next-turn setups exist")
		return
	_check(adopted.state_hash() == direct.state_hash() and Canonical.same(adopted.snapshot(), direct.snapshot()) and Canonical.same(_inputs_of(adopted), _inputs_of(direct)), label + ": the next turn set up on a worker equals the one set up here")
	if second.is_empty(): return
	for input: Dictionary in family.expand_recording_inputs(second):
		adopted.step(input)
		direct.step(input)
	var mine: Dictionary = adopted.export_recording()
	_check(adopted.state_hash() == direct.state_hash() and Canonical.same(mine, direct.export_recording()) and Canonical.same(adopted.snapshot(), direct.snapshot()), label + ": B's turn played on each ends identically")

static func _inputs_of(simulation: RefCounted) -> Dictionary:
	var stage: Variant = simulation.get("stage")
	return {"role": simulation.get("role"), "stage": stage.get("id", "") if stage is Dictionary else "", "checkpoint": simulation.get("_checkpoint"), "prior": simulation.get("_prior"), "rules": simulation.get("simulation_version"), "tick": simulation.get("tick")}

## On the real chapter screen with frames running: when the journey's last
## check or setup was slow, finishing a turn and Save turn first draw a card
## saying the saved progress is being checked, then continue by themselves;
## quick work goes straight on.
func _visible_wait() -> void:
	var path := directory + "/scene.json"
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var app := Preview.new()
	app.journey = Journey.new(path)
	app.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	viewport.add_child(app)
	app.set_physics_process(false)
	await process_frame
	app._begin()
	for input: Dictionary in RelaySimulation.expand_recording_inputs(_fixture("v2/relay-a")): app.advance_input(input)
	# As if the last replay-backed work here had taken a second.
	app.journey._last_setup_usec = 1000000
	app._finish()
	_check(app.mode == "turn_wait" and _shows(app.overlay, PlayerCopy.LIGHTHOUSE_PREVIEW_DA74C3A728FC), "A slow check first shows that saved progress is being checked")
	await _until(app, "review")
	_check(app.mode == "review" and _button(app.overlay, "Save turn") != null, "The review follows by itself once the card was drawn")
	_check(str(app._prefetch_job.get("role", "")) == "b" and Canonical.same(app._prefetch_job.get("prior"), app.review), "The review of a first turn starts setting up the turn after it on a worker")
	await _until_prefetched(app)
	var prefetched: RefCounted = app._prefetch_built.get("simulation")
	app.journey._last_setup_usec = 1000000
	_button(app.overlay, "Save turn").pressed.emit()
	_check(app.mode == "ready" and prefetched != null and app.sim == prefetched and app.journey.is_live_simulation(app.sim) and app.role == "b", "Save turn goes straight to the next turn the worker set up, with no wait card")
	_check(app._prefetch_thread == null and app._prefetch_job.is_empty(), "The used prefetch is released")
	# Quick work never shows the card.
	app.journey._last_setup_usec = 0
	app.journey._last_check_usec = 0
	var ready_sim: RefCounted = app.sim
	app._begin()
	_check(app.mode == "play" and app.sim == ready_sim and app.journey.is_live_simulation(app.sim), "Start turn plays the simulation the ready card set up instead of setting it up again")
	for input: Dictionary in RelaySimulation.expand_recording_inputs(_fixture("v2/relay-b")): app.advance_input(input)
	app._finish()
	if app.mode == "bloom": app._process(Preview.COMPLETION_DURATION)
	_check(app.mode == "review", "Quick checks go straight to the review")
	# Saving the chapter's last turn shows the finished scene from the screen's
	# own simulation; a reopened chapter rebuilds the same scene from the chain.
	_button(app.overlay, "Save turn").pressed.emit()
	await _until(app, "checkpoint")
	for name: String in ["garden-a", "garden-b"]:
		app._show_ready()
		# A simulation that has moved since the ready card is never reused.
		var shown_sim: RefCounted = app.sim
		if name == "garden-b": app.sim.step(RelaySimulation.expand_recording_inputs(_fixture("v2/garden-b"))[0])
		app._begin()
		_check(app.mode == "play" and app.sim.tick == 0 and app.journey.is_live_simulation(app.sim) and (app.sim == shown_sim) == (name == "garden-a"), "Start turn after the ready card: " + name)
		for input: Dictionary in RelaySimulation.expand_recording_inputs(_fixture("v2/" + name)): app.advance_input(input)
		app._finish()
		if app.mode == "bloom": app._process(Preview.COMPLETION_DURATION)
		await _until(app, "review")
		if name == "garden-a":
			# Without a prefetch, Save turn falls back to setting the next turn
			# up here, behind the wait card when that was slow last time.
			app._drop_prefetch()
			app.journey._last_setup_usec = 1000000
		_button(app.overlay, "Save turn").pressed.emit()
		if name == "garden-a":
			_check(app.mode == "turn_wait" and app.journey.role() == "b", "Without a prefetch, Save turn writes the turn at once, then shows the wait before setting up the next turn")
		await _until(app, "ready" if name == "garden-a" else "complete")
		if name == "garden-a":
			_check(app.mode == "ready" and app.role == "b" and app.sim != null and app.sim.role == "b" and app.journey.is_live_simulation(app.sim), "The next turn is ready by itself after the wait")
	_check(app.mode == "complete" and app.journey.chapter_complete(), "Saving the last turn completes the chapter")
	var shown: Dictionary = app.sim.snapshot()
	var reopened := Preview.new()
	reopened.journey = Journey.new(path)
	reopened.settings = app.settings.duplicate()
	viewport.add_child(reopened)
	reopened.set_process(false)
	reopened.set_physics_process(false)
	await process_frame
	_check(reopened.mode == "complete" and Canonical.same(reopened.sim.snapshot(), shown), "The finished scene after Save turn equals the scene rebuilt from the saved chain")
	viewport.queue_free()
	await process_frame

## A next turn still being set up when Save turn is tapped finishes behind the
## wait card and is then used; leaving the screen while one is being set up
## does not wait for it, and the shared reaper joins it once it ends.
func _prefetch_scene() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var app := Preview.new()
	app.journey = Journey.new(directory + "/prefetch-scene.json")
	app.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	viewport.add_child(app)
	app.set_physics_process(false)
	await process_frame
	await _play_to_review(app, "v2/relay-a")
	var gate := Semaphore.new()
	var job: Dictionary = app._prefetch_job.duplicate(true)
	var held := _hold_prefetch(app, job, gate)
	app.journey._last_setup_usec = 0
	app.journey._last_check_usec = 0
	_button(app.overlay, "Save turn").pressed.emit()
	_check(app.mode == "turn_wait" and app.journey.role() == "b", "Save turn while the next turn is still being set up shows the wait card, even when setup was quick before")
	for frame in range(5): await process_frame
	_check(app.mode == "turn_wait" and held.is_alive(), "The card stays up while the worker finishes; nothing runs on this thread")
	gate.post()
	await _until(app, "ready", 20000)
	_check(app.mode == "ready" and app.role == "b" and app.journey.is_live_simulation(app.sim) and app.sim.tick == 0 and not held.is_started(), "Once the worker ends, its next turn is joined and used")
	# Leave while the next turn is being set up.
	app._begin()
	for input: Dictionary in RelaySimulation.expand_recording_inputs(_fixture("v2/relay-b")): app.advance_input(input)
	app._finish()
	if app.mode == "bloom": app._process(Preview.COMPLETION_DURATION)
	await _until(app, "review")
	_button(app.overlay, "Save turn").pressed.emit()
	await _until(app, "checkpoint")
	app._show_ready()
	await _play_to_review(app, "v2/garden-a")
	gate = Semaphore.new()
	held = _hold_prefetch(app, app._prefetch_job.duplicate(true), gate)
	var started := Time.get_ticks_usec()
	viewport.remove_child(app)
	app.free()
	var leave_ms := (Time.get_ticks_usec() - started) / 1000.0
	_check(held.is_started() and Reaper.holds(held), "Leaving mid-setup does not wait for the worker (%.1f ms); the reaper holds it" % leave_ms)
	gate.post()
	# Swapping in the held setup also handed the screen's own earlier setup to
	# the reaper; under load either may still be replaying. Wait (bounded, by
	# the clock) until the reaper has joined every worker it was given.
	var deadline := Time.get_ticks_msec() + 60000
	while (held.is_started() or Reaper.pending_count() > 0) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not held.is_started(), "The reaper joins the left worker once it ends")
	_check(Reaper.pending_count() == 0, "The reaper ends holding no worker")
	viewport.queue_free()
	await process_frame

func _play_to_review(app: Node, recording: String) -> void:
	app._begin()
	for input: Dictionary in RelaySimulation.expand_recording_inputs(_fixture(recording)): app.advance_input(input)
	app._finish()
	if app.mode == "bloom": app._process(Preview.COMPLETION_DURATION)
	await _until(app, "review")
	_check(app.mode == "review" and str(app._prefetch_job.get("role", "")) == "b", recording + ": the review starts the next turn's prefetch")

## Swaps the screen's prefetch for one that waits on gate before building the
## same job, so a test controls when it ends.
func _hold_prefetch(app: Node, job: Dictionary, gate: Semaphore) -> Thread:
	app._drop_prefetch()
	var thread := Thread.new()
	thread.start(Callable(get_script(), "_gated_build").bind(gate, job))
	app._prefetch_thread = thread
	app._prefetch_job = job
	return thread

static func _gated_build(gate: Semaphore, job: Dictionary) -> Dictionary:
	gate.wait()
	return Journey.build_live(job)

func _until_prefetched(app: Node) -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while app._prefetch_thread != null and Time.get_ticks_msec() < deadline:
		await process_frame

## At least 30 frames, longer when a worker's end is awaited (msec).
func _until(app: Node, wanted: String, msec: int = 0) -> void:
	var deadline := Time.get_ticks_msec() + msec
	var frame := 0
	while frame < 30 or Time.get_ticks_msec() < deadline:
		if app.mode == wanted: return
		frame += 1
		await process_frame

func _shows(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text and (node as Label).is_visible_in_tree(): return true
	for child: Node in node.get_children():
		if _shows(child, text): return true
	return false

func _button(node: Node, text: String) -> Button:
	for button: Node in node.find_children("*", "Button", true, false):
		if (button as Button).text == text and not (button as Button).disabled: return button
	return null

func _fixture(name: String) -> Dictionary:
	var path := "res://tests/fixtures/" + name + ".json"
	if not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)

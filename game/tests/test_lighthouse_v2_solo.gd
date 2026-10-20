extends SceneTree
## sleeping-lighthouse@2 solo, on the shared chapter screen: the journal is
## proven stage by stage and loaded on a worker, the proof memo survives a
## restart, the HUD counts six stages, and the last stage ends on the lit
## beacon before the shared completion. Recordings are the C2 chain fixture.
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Proofs = preload("res://services/journey_proofs.gd")
const Warmup = preload("res://services/journey_proof_warmup.gd")
const RoomProof = preload("res://core/lighthouse/room_proof.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Frozen = preload("res://services/frozen_simulation.gd")
const KEY := Registry.LIGHTHOUSE_V2
var checks := 0
var failures := 0
var chain: Dictionary
var path := ""

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	chain = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/v2-chain.json"))
	path = str(Registry.descriptor(KEY).local_path)
	_check(path == "user://sleeping-lighthouse-journey-v2.json", "The chapter keeps its own solo save")
	Proofs.directory = "user://lighthouse-v2-solo-proofs-" + Crypto.new().generate_random_bytes(6).hex_encode()
	_journal()
	_memo_restart()
	_warmup_sources()
	await _worker_draft()
	await _screen_ready()
	await _final_moment()
	await _playthrough()
	await _leave_while_loading()
	_cleanup()
	print("LIGHTHOUSE V2 SOLO: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Saves the first `pairs` stages and, optionally, the next A turn.
func _save(pairs: int, with_a: bool) -> RefCounted:
	_remove_save()
	var journey := Journey.new(path, null, KEY)
	journey.load_data()
	var ok := not journey.read_only
	for index in range(pairs):
		ok = ok and journey.accept_recording(chain.pairs[index].a) and journey.accept_recording(chain.pairs[index].b)
	if with_a: ok = ok and journey.accept_recording(chain.pairs[pairs].a)
	_check(ok, "A solo journal saves %d stages%s" % [pairs, " and an A turn" if with_a else ""])
	return journey

func _journal() -> void:
	var journey := _save(6, false)
	_check(journey.chapter_complete() and journey.pairs().size() == 6, "All six stages complete the solo chapter")
	_check(Canonical.same(journey.checkpoint(), chain.checkpoints[6]), "...at the chain's final checkpoint")
	var cold := Journey.new(path, null, KEY)
	cold.load_data()
	_check(not cold.read_only and cold.chapter_complete() and cold.pairs().size() == 6, "A cold load restores the complete journey")

func _memo_restart() -> void:
	var memo := Proofs.directory.path_join(Proofs.MEMO_FILE)
	# Rooms and replays verify whole checkpoints (the solo journal keeps its own
	# per-save proof); one full check remembers every nested checkpoint.
	RoomProof.clear_memo()
	_check(Registry.simulation_script(KEY).verify_checkpoint(Registry.definition(KEY), chain.checkpoints[6]).valid and RoomProof.Memo.pair_replays >= 6, "A first full check replays all six stages")
	Proofs.save_memo(KEY)
	_check(FileAccess.file_exists(memo) and RoomProof.memo_size() > 0, "Verified Lighthouse checkpoints are kept on disk")
	RoomProof.clear_memo()
	Proofs._memo_sizes.clear()
	Proofs.prepare_memo(KEY)
	var kept := RoomProof.memo_size()
	_check(kept > 0, "A restart reads them back (%d)" % kept)
	var before: int = RoomProof.Memo.pair_replays
	_check(Registry.simulation_script(KEY).verify_checkpoint(Registry.definition(KEY), chain.checkpoints[6]).valid and RoomProof.Memo.pair_replays == before, "The final checkpoint then verifies without replaying a stage")
	Proofs.prepare_memo(Registry.TURN_OF_THE_TIDE)
	_check(RoomProof.memo_size() == kept, "Other chapters leave the Lighthouse memo alone")

func _warmup_sources() -> void:
	var found := false
	for source: Dictionary in Warmup.default_sources(): found = found or (source.chapter == KEY and source.path == path)
	_check(found, "The Home warm-up proves the Lighthouse solo save ahead of an open")

## The periodic draft save exports a still copy of the live engine on a
## worker; the Lighthouse facade's copy carries its engine too.
func _worker_draft() -> void:
	var journey := _save(2, false)
	var sim: RefCounted = journey.create_live_simulation()
	_check(sim != null, "A live stage-3 turn is set up")
	if sim == null: return
	var inputs: Array = Registry.simulation_script(KEY).expand_recording_inputs(chain.pairs[2].a)
	for index in range(mini(30, inputs.size())): sim.step(inputs[index])
	var frozen: RefCounted = Frozen.of(sim)
	var live: Dictionary = sim.export_recording()
	_check(not live.is_empty() and Canonical.same(frozen.export_recording(), live), "A still copy exports exactly the live turn")
	frozen.step(inputs[30])
	_check(Canonical.same(sim.export_recording(), live), "Stepping the copy leaves the live turn untouched")
	_check(journey.save_live_draft(sim, true), "A periodic draft save starts on a worker")
	var deadline := Time.get_ticks_msec() + 20000
	while journey._draft_writer != null and journey._draft_writer.is_alive() and Time.get_ticks_msec() < deadline: await process_frame
	_check(journey.finish_live_draft_save() and journey.last_error.is_empty(), "...and is written: " + journey.last_error)
	var cold := Journey.new(path, null, KEY)
	cold.load_data()
	_check(Canonical.same(cold.draft(), live), "The saved draft is the turn so far")

func _open() -> Node:
	var scene: Node = load(Registry.solo_scene(KEY)).instantiate()
	scene.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "photo_prompts": false}
	root.add_child(scene)
	return scene

func _wait_mode(scene: Node, modes: Array, seconds: float = 30.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while scene.mode not in modes and Time.get_ticks_msec() < deadline: await process_frame
	return scene.mode in modes

func _screen_ready() -> void:
	_save(2, false)
	var scene := _open()
	_check(scene.mode == "loading" and scene._journal_loader != null, "The six-stage journal loads on a worker behind a card")
	_check(await _wait_mode(scene, ["ready"]), "The ready card follows the load")
	_check(scene.journey.pairs().size() == 2 and scene.journey.stage_id() == chain.definition.stages[2].id, "The loaded journal stands at stage 3")
	scene._begin()
	_check(scene.mode == "play" and scene.chapter_label.text.contains("3 / 6"), "The HUD counts six stages: " + scene.chapter_label.text)
	_check(scene.sim.catch_assistance == false, "Lighthouse turns record no catch assistance")
	for input: Dictionary in Registry.simulation_script(KEY).expand_recording_inputs(chain.pairs[2].a):
		if scene.mode != "play": break
		scene.advance_input(input)
	if scene.mode == "play": scene._finish()
	_check(scene.mode in ["review", "turn_wait"], "A played stage-3 turn reaches review")
	_check(Canonical.same(scene.review, chain.pairs[2].a), "...with the fixture's exact record")
	scene.queue_free()
	await process_frame

func _final_moment() -> void:
	_save(5, true)
	var scene := _open()
	_check(await _wait_mode(scene, ["ready"]), "The last stage opens")
	scene._begin()
	_check(scene.role == "b" and scene.chapter_label.text.contains("6 / 6"), "The last B turn is stage 6 of 6")
	for input: Dictionary in Registry.simulation_script(KEY).expand_recording_inputs(chain.pairs[5].b):
		if scene.mode != "play": break
		scene.advance_input(input)
	_check(scene.mode == "moment" and scene.sim.snapshot().get("beacon", {}).get("lit", false), "The lit beacon holds the screen")
	_check(scene.finish_button.visible and not scene.finish_button.disabled and not scene.running, "...until the player continues")
	_check(not scene.journey.draft().is_empty(), "The finished turn is already saved as a draft")
	scene._finish()
	_check(scene.mode == "bloom", "Continuing plays the shared completion")
	scene.queue_free()
	await process_frame

## All twelve turns played through the screen's own controls, Save turn
## after each review, from an empty journal to the shared completion.
func _playthrough() -> void:
	_remove_save()
	var scene := _open()
	_check(await _wait_mode(scene, ["ready"]), "An empty journal opens")
	var played := 0
	for index in range(6):
		for role: String in ["a", "b"]:
			if scene.mode != "ready": break
			scene._begin()
			for input: Dictionary in Registry.simulation_script(KEY).expand_recording_inputs(chain.pairs[index][role]):
				if scene.mode != "play": break
				scene.advance_input(input)
			if scene.mode == "moment": scene._finish()
			if scene.mode == "play": scene._finish()
			await _wait_mode(scene, ["review", "bloom"], 10.0)
			if scene.mode == "bloom":
				scene.completion_remaining = 0.0
				await _wait_mode(scene, ["review"], 10.0)
			if scene.mode != "review" or not Canonical.same(scene.review, chain.pairs[index][role]):
				push_error("Turn %d%s left the fixture: mode=%s error=%s reason=%s" % [index + 1, role, scene.mode, str(scene.sim.get("error")), str(scene.sim.snapshot().get("commit_reason", ""))])
				break
			await scene._accept()
			await _wait_mode(scene, ["ready", "checkpoint", "complete"], 10.0)
			if scene.mode == "checkpoint": scene._show_ready()
			played += 1
	_check(played == 12 and scene.journey.chapter_complete() and scene.mode == "complete", "Twelve turns through the screen complete the chapter (%d, %s)" % [played, scene.mode])
	scene.queue_free()
	await process_frame

func _leave_while_loading() -> void:
	_save(3, false)
	var scene := _open()
	_check(scene.mode == "loading", "A reopened journal loads again")
	scene._leave()
	_check(scene.mode == "loading" and scene._leave_after_load and not scene._leaving, "Back during the load waits for the worker")
	# Freeing the screen joins the worker rather than leaking it.
	scene.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(scene), "The screen closes with its worker joined")

func _remove_save() -> void:
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _cleanup() -> void:
	_remove_save()
	var directory := DirAccess.open(Proofs.directory)
	if directory != null:
		for name: String in directory.get_files(): directory.remove(name)
	DirAccess.remove_absolute(Proofs.directory)

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

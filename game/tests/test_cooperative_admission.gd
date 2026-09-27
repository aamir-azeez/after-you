extends SceneTree
const Preview = preload("res://cooperative_preview.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Simulation = preload("res://core/cooperative/simulation.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Integration = preload("res://tests/test_cooperative_integration.gd")
const AccessTests = preload("res://tests/test_chapter_access.gd")
var checks := 0
var failures := 0
var directory := "user://cooperative-admission-" + Crypto.new().generate_random_bytes(8).hex_encode()

class TrackedJournal extends Journey:
	var loads := 0
	func _init(path: String, storage: RefCounted, chapter: String) -> void: super(path, storage, chapter)
	func load_data() -> void:
		loads += 1
		super.load_data()

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(directory)
	await _free_entry()
	await _paid_preservation(Registry.ROLLING_HOME)
	await _paid_preservation(Registry.HOUSE)
	await _paid_preservation(Registry.CONSERVATORY)
	await _paid_preservation(Registry.LONG_WAY_HOME)
	for filename: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	print("COOPERATIVE ADMISSION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _free_entry() -> void:
	var journal := TrackedJournal.new(directory.path_join("free.json"), null, Registry.HIGH_AND_LOW)
	var screen := Preview.new()
	screen.chapter_key = Registry.HIGH_AND_LOW
	screen.journey = journal
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true}
	root.add_child(screen)
	screen.set_physics_process(false)
	_check(screen._prepared and screen.admission == null and journal.loads == 1, "The free chapter opens through its normal journal without a purchase gate")
	screen._begin()
	_check(screen.running and screen.sim.get_script() == Simulation, "Free chapter entry starts the actual physical simulation")
	screen.advance_input({"move_x": 1.0})
	_check(screen.sim.tick == 1, "The free controller advances real input")
	root.remove_child(screen)
	screen.queue_free()
	await process_frame

func _paid_preservation(key: String) -> void:
	var stage: String = Registry.definition(key).stages[0].id
	var path := directory.path_join(stage + ".json")
	var folder := "journey" if Registry.is_journey(key) else "cooperative"
	var a: Dictionary = _fixture(stage + "-a",folder)
	var b: Dictionary = _fixture(stage + "-b",folder)
	if a.is_empty() or b.is_empty(): return
	var seed := Journey.new(path, null, key)
	seed.load_data()
	_check(seed.accept_recording(a), "The preserved journal contains a real accepted source")
	var live: RefCounted = seed.create_live_simulation()
	var inputs := Simulation.expand_recording_inputs(b)
	for frame: Dictionary in inputs.slice(0, 20): live.step(frame)
	_check(seed.save_live_draft(live), "The preserved journal contains a real receiver rehearsal")
	var before := _hashes(path)
	var disk := Integration.Disk.new(path)
	var journal := TrackedJournal.new(path, disk, key)
	var store := AccessTests.Store.new()
	store._configuration = {"purchase_mode": "google_play", "entitlement_id": "full_journey_play"}
	var screen: Node = load(Registry.solo_scene(key)).instantiate()
	screen.chapter_key = key
	screen.journey = journal
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true}
	screen.purchase_service_factory = func(): return store
	root.add_child(screen)
	screen.set_physics_process(false)
	_check(not screen._prepared and journal.loads == 0 and screen.mode == "access", "Paid direct scene admission waits before loading the retained journal")
	store.answer(store.requests[-1], false)
	screen._begin()
	screen._resume_draft()
	screen._start_play()
	screen._start_replay(a, Registry.initial_checkpoint(key), {})
	screen.advance_input({"move_x": 1.0})
	_check(journal.loads == 0 and not screen.running and _hashes(path) == before, "Denied Begin, Resume, replay and direct input preserve unloaded save bytes")
	screen.admission.check_access()
	store.answer(store.requests[-1], true)
	_check(screen._prepared and journal.loads == 1 and _hashes(path) == before, "Matched buyer admission loads the old chapter once without rewriting it")
	screen.world.set_process(false)
	screen._resume_draft()
	_check(screen.running and screen.sim.tick == 20, "Explicit Resume reconstructs the actual saved receiver interval")
	_check(screen.sim.get_script() == Registry.simulation_script(key) and screen.world.get_script() == Registry.world_script(key), "Registered paid scenes use their exact engine and world for real resumed input")
	for frame: Dictionary in inputs.slice(20, 25): screen.advance_input(frame)
	store.revoke()
	_check(not screen.running and screen.mode == "access" and screen.sim.tick == 25 and journal.draft().duration_ticks == 25, "Revocation saves the latest real interval and holds gameplay")
	before = _hashes(path)
	screen._start_play()
	screen.advance_input(inputs[25])
	await screen._accept()
	_check(screen.sim.tick == 25 and _hashes(path) == before and Canonical.same(journal.prior_recording(), a), "Stale input, Continue and Save cannot bypass revoked access or alter source proof")
	screen.admission.check_access()
	store.answer(store.requests[-1], true)
	_check(not screen.running and journal.draft().duration_ticks == 25, "Restored admission preserves the saved interval and waits for explicit Resume")
	screen._resume_draft()
	screen.advance_input(inputs[25])
	disk.reject = true
	store.revoke()
	_check(not screen.running and screen._admission_save_failed and screen.sim.tick == 26 and _hashes(path) == before, "Disk failure during revocation retains the unsaved live interval without changing durable bytes")
	screen.admission.check_access()
	store.answer(store.requests[-1], true)
	_check(screen.mode == "save_error" and not screen.running and screen.sim.tick == 26, "Restored access preserves the disk-error recovery instead of resetting the rehearsal")
	disk.reject = false
	_check(screen._persist_draft() and journal.draft().duration_ticks == 26, "Retrying storage saves the preserved interval exactly")
	screen._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	screen._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	var requests := store.requests.size()
	screen._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(store.requests.size() == requests and not screen.running, "Foreground events coalesce into one access check while preserving pause")
	store.answer(store.requests[-1], true)
	_check(not screen.running and journal.loads == 1, "Warm access verification does not reload the chapter or autoplay")
	before = _hashes(path)
	screen._start_replay(a,Registry.initial_checkpoint(key),{})
	_check(screen.mode == "replay" and screen.running,"The registered paid scene admits a verified source replay after access returns")
	if Registry.is_journey(key):
		var presentation := Registry.stage_presentation(key,Registry.definition(key).stages[0])
		_check(screen.controls.chapter_label.text.begins_with(presentation.title) and screen.controls.hint_label.text == presentation.hint_a,"Replay shows the actual source stage and accepted role hint while a receiver draft is retained")
	for _tick in range(int(a.duration_ticks)): screen._physics_process(1.0/30.0)
	_check(Canonical.same(screen.sim.export_recording(),a) and _hashes(path) == before,"Actual scene replay reproduces native bytes without replacing the saved receiver draft")
	root.remove_child(screen)
	screen.queue_free()
	await process_frame

func _fixture(name: String, folder: String = "cooperative") -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + folder + "/" + name + ".json"))
	_check(value is Dictionary, "The admission test uses native-generated evidence")
	return value if value is Dictionary else {}

func _hashes(path: String) -> Dictionary:
	var result := {}
	for suffix: String in ["", ".backup", ".tmp"]:
		result[suffix] = FileAccess.get_sha256(path + suffix) if FileAccess.file_exists(path + suffix) else "absent"
	return result

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

extends SceneTree

const Preview = preload("res://lighthouse_preview.gd")
const Purchases = preload("res://services/purchases.gd")
const Journal = preload("res://services/lighthouse_journey.gd")
const Simulation = preload("res://core/lighthouse/borrowed_light.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0
var path := "user://test-lighthouse-admission-%d.json" % Time.get_ticks_usec()

class Store extends Purchases:
	var requests: Array[String] = []
	func _connect_native() -> bool: return true
	func refresh_customer_info() -> String:
		var id := "check-%d" % requests.size()
		requests.append(id)
		return id
	func answer(id: String, active: bool) -> void:
		customer_info = {"schema_version": 1, "entitlements": {"full_journey": {"active": active}}}
		customer_info_changed.emit(customer_info)
		completed.emit(id, "get_customer_info", customer_info)
	func deny(id: String) -> void:
		failed.emit(id, "get_customer_info", "provider_unavailable", "", false)
	func revoke() -> void:
		customer_info = {"schema_version": 1, "entitlements": {}}
		customer_info_changed.emit(customer_info)

class TrackedJournal extends Journal:
	var loads := 0
	func _init(save_path: String) -> void: super(save_path)
	func load_data() -> void:
		loads += 1
		super.load_data()

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/first-two-v3.json"))
	var seed := Journal.new(path)
	seed.load_data()
	_check(seed.accept_recording(fixture.pairs[0].a), "The preserved save contains an independently verified accepted A")
	var live: RefCounted = seed.create_live_simulation()
	var b_inputs: Array = Simulation.expand_recording_inputs(fixture.pairs[0].b)
	for i in range(20): live.step(b_inputs[i])
	_check(seed.save_live_draft(live), "The preserved save contains a real twenty-tick B rehearsal")
	var original := _hashes()
	var tracked := TrackedJournal.new(path)
	var store := Store.new()
	var screen := Preview.new()
	screen.journey = tracked
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true}
	screen.purchase_service_factory = func(): return store
	root.add_child(screen)
	screen.set_physics_process(false)
	screen.world.set_process(false)
	screen.backgrounded = false
	_check(screen.mode == "access_check" and tracked.loads == 0 and not screen._journal_started, "Actual scene admission waits for SDK information before any journal load")
	_check(store.requests.size() == 1, "The scene asks the already configured store for customer information once")
	store.answer(store.requests[-1], false)
	_check(screen.mode == "access_hold" and tracked.loads == 0, "A nonbuyer cannot load even an existing accepted chapter and draft")
	_check(_button(screen.controls.overlay, "Check purchase again") != null and _button(screen.controls.overlay, "Back") != null, "Denied admission has explicit retry and Back")
	screen._begin()
	screen._resume_draft()
	screen._start_replay(fixture.pairs[0].b, fixture.pairs[0].a, [])
	screen._show_collection()
	_check(screen.sim == null and not screen.running and tracked.loads == 0, "Direct record, resume, replay and completed-collection calls cannot bypass denied admission")
	_check(_hashes() == original, "Denied entry preserves exact primary, backup and temporary save bytes")
	screen._check_access()
	var expired: String = store.requests[-1]
	screen._access_deadline = 0
	screen._process(0.0)
	_check(screen.mode == "access_hold" and screen._access_request.is_empty(), "A missing callback has a bounded access hold")
	store.answer(expired, true)
	_check(not screen._access_granted and tracked.loads == 0, "A late timed-out SDK success cannot grant access")
	screen._check_access()
	store.answer(store.requests[-1], true)
	var deadline := Time.get_ticks_msec() + 30000
	while screen.mode == "loading" and Time.get_ticks_msec() < deadline: await process_frame
	_check(screen.mode == "ready" and tracked.loads == 1 and screen.journey == tracked, "An exact active SDK result admits the real asynchronous journal once")
	if screen.mode != "ready":
		root.remove_child(screen)
		screen.queue_free()
		await process_frame
		_finish()
		return
	_check(_hashes() == original and screen.role == "b", "Admitted load preserves exact old bytes and accepted physical-role context")
	_check(Canonical.same(screen.journey.prior_recording(), fixture.pairs[0].a), "Admission does not rewrite immutable source recording proof")
	screen._resume_draft()
	_check(screen.running and screen.sim.tick == 20, "Explicit resume restores the actual saved tick")
	for i in range(20, 25): screen.advance_input(b_inputs[i])
	store.revoke()
	_check(screen.mode == "access_hold" and not screen.running and screen.sim.tick == 25, "Explicit entitlement loss pauses the current rehearsal without advancing it")
	_check(int(screen.journey.draft().duration_ticks) == 25, "Revocation persists the actual latest interval before holding access")
	var paused := _hashes()
	screen._start_play()
	screen._accept()
	screen.advance_input(b_inputs[25])
	_check(not screen.running and screen.sim.tick == 25 and _hashes() == paused, "Stale continue, Save and input cannot bypass a revoked entitlement")
	screen._check_access()
	store.deny(store.requests[-1])
	_check(screen.mode == "access_hold" and not screen._access_granted and _hashes() == paused, "Provider failure remains retryable and cannot erase or unlock the saved rehearsal")
	screen._check_access()
	store.answer(store.requests[-1], true)
	_check(screen.mode == "paused" and not screen.running and screen.sim.tick == 25, "Restored entitlement returns a paused rehearsal without autoplay")
	screen._start_play()
	screen._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	var count: int = store.requests.size()
	screen._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	screen._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(store.requests.size() == count + 1 and not screen.running, "Resume rechecks once; paired focus events coalesce and do not restart recording")
	store.answer(store.requests[-1], true)
	_check(screen.mode == "paused" and tracked.loads == 1, "Warm access verification does not reload the journal or lose the current interval")
	screen._start_replay(fixture.pairs[0].b, fixture.pairs[0].a, [])
	for i in range(10): screen._physics_process(1.0 / 30.0)
	var cursor: int = screen.replay_cursor
	var replay_bytes := _hashes()
	screen._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	screen._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	store.answer(store.requests[-1], true)
	_check(screen.mode == "paused" and screen.replay_cursor == cursor and not screen.running, "A replay's exact cursor survives the resume access check")
	screen._continue_replay()
	_check(screen.mode == "replay" and screen.running and screen.replay_cursor == cursor and _hashes() == replay_bytes, "Only explicit Continue resumes the same read-only replay")
	root.remove_child(screen)
	# The node remains alive until queued deletion; cleared request ownership must
	# already make its pending completion harmless after leaving the scene tree.
	screen._access_completed("old-request", "get_customer_info", {"schema_version": 1, "entitlements": {}})
	screen.queue_free()
	await process_frame
	_finish()

func _hashes() -> Dictionary:
	var result := {}
	for suffix: String in ["", ".backup", ".tmp"]:
		result[suffix] = FileAccess.get_sha256(path + suffix) if FileAccess.file_exists(path + suffix) else "absent"
	return result

func _button(node: Node, label: String) -> Button:
	if node is Button and node.text == label: return node
	for child: Node in node.get_children():
		var found := _button(child, label)
		if found != null: return found
	return null

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _finish() -> void:
	for suffix: String in ["", ".backup", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("LIGHTHOUSE ADMISSION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

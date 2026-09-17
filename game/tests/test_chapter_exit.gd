extends "res://tests/test_relay_online.gd"
## Exercise real scene exit, retained session and durable coordinator requests.
## Only HTTP and storage are the same controlled doubles as the online suite.
const Registry = preload("res://services/chapter_registry.gd")

func _run() -> void:
	for key: String in Registry.keys():
		_load_chapter(key)
		await _leave_during_read(key)
		await _leave_during_submission(key, false)
		await _leave_during_submission(key, true)
	for path: String in cleanup_paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(path + suffix)
	await create_timer(0.2).timeout
	print("After You chapter exit: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _load_chapter(key: String) -> void:
	level = Registry.definition(key)
	var names := ["relay-a", "relay-b", "garden-a", "garden-b", "initial-checkpoint", "relay-checkpoint", "final-checkpoint"]
	var files := names if key == Registry.RELAY else ["a-little-lift-a", "a-little-lift-b", "a-place-to-grow-a", "a-place-to-grow-b", "initial-checkpoint", "lift-checkpoint", "final-checkpoint"]
	var folder := "v2" if key == Registry.RELAY else "first_steps"
	for index: int in names.size():
		fixtures[names[index]] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + folder + "/" + files[index] + ".json"))

func _snapshot(api: FakeApi, owner: String) -> Dictionary:
	var value := super._snapshot(api, owner)
	value.level_id = level.id
	value.level_version = level.version
	return value

func _open_case(key: String) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var app := Main.new()
	var path := "user://chapter-exit-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	cleanup_paths.append(path)
	app.saves = Save.new(path)
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.api.queue_free()
	var api := _api()
	root.remove_child(api)
	app.add_child(api)
	app.api = api
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.identity_data = {"player_id": HOST, "device_token": api.device_token}
	app.saves.data.settings.sound = false
	app.saves.data.settings.haptics = false
	app.saves.data.settings.reduced_motion = true
	app.selected_online_chapter = key
	var store := MemoryStore.new()
	var session := Session.new(api, app._relay_identity, store)
	app.relay_session = session
	api.exists = true
	api.joined = true
	api.revision = 1
	_check(await session.open_room(ROOM), "Authenticated room read accepts the native chapter fixtures: " + key)
	session.capabilities = {"mutations_enabled": true}
	app._enter_online_relay()
	var preview: Node = app.relay_child
	preview.set_process(false)
	preview.set_physics_process(false)
	await process_frame
	_check(preview.chapter_key == key and preview.mode == "ready", "Real parent opens the requested chapter: " + key)
	return {"viewport": viewport, "app": app, "api": api, "session": session, "store": store, "preview": preview}

func _leave_during_read(key: String) -> void:
	var scene := await _open_case(key)
	var preview: Node = scene.preview
	var session: RefCounted = scene.session
	var api: FakeApi = scene.api
	var before := Canonical.digest(scene.store.values)
	var calls := api.calls.size()
	api.hold_next = true
	preview.online_refresh_queued = true
	preview._service_online_refresh()
	_check(api.busy and session.busy() and api.calls.size() == calls + 1 and api.calls.back().method == HTTPClient.METHOD_GET, "Automatic refresh is truly awaiting a single GET before Back: " + key)
	var button: Button = _button_named(preview, "Back to the journey")
	_check(button != null and not button.disabled, "The actual Back button is available during refresh: " + key)
	if button != null: button.pressed.emit()
	_check(scene.app.relay_child == null and scene.app.mode == "relay_rooms" and scene.app.ui.visible, "One Back tap immediately returns to the parent while GET is pending: " + key)
	_check(session.busy() and scene.app.relay_session == session and Canonical.digest(scene.store.values) == before, "Back retains the API owner and leaves saved room bytes unchanged: " + key)
	# Let the old implementation finish too, so the negative run has no leaked
	# request or scene after its failed immediate-exit assertion.
	if scene.app.relay_child != null: scene.app._leave_online_relay()
	var retired: WeakRef = weakref(preview)
	await process_frame
	api.release.emit()
	await process_frame
	_check(retired.get_ref() == null and scene.app.relay_child == null and scene.app.mode == "relay_rooms", "Late refresh cannot restore the departed chapter or overlay: " + key)
	_check(not session.busy() and api.calls.size() == calls + 1 and Canonical.digest(scene.store.values) == before, "The retained GET drains with no POST or unnecessary save: " + key)
	scene.viewport.queue_free()
	await process_frame

func _leave_during_submission(key: String, lose_reply: bool) -> void:
	var scene := await _open_case(key)
	var preview: Node = scene.preview
	var session: RefCounted = scene.session
	var api: FakeApi = scene.api
	preview._begin()
	for input: Dictionary in Registry.simulation_script(key).expand_recording_inputs(fixtures["relay-a"]):
		preview.advance_input(input)
	preview._finish()
	_check(preview.mode == "review" and not session.coordinator.draft().is_empty(), "Actual controls produce a saved, uncommitted review: " + key)
	var solo_before := Canonical.digest(scene.app.saves.data)
	api.hold_next = true
	api.drop_next = lose_reply
	preview._accept()
	var pending: Dictionary = session.coordinator.pending()
	var before := Canonical.digest(scene.store.values)
	_check(api.busy and not pending.is_empty() and api.calls.back().method == HTTPClient.METHOD_POST, "Submission is durably journaled before the held POST: " + key)
	var reopened := Session.Coordinator.new(session.transport, scene.store.load_scope, scene.store.save_scope, scene.app._relay_identity)
	_check(reopened.bind_room(ROOM) and Canonical.same(reopened.pending(), pending), "A fresh coordinator can recover the exact request before any reply: " + key)
	preview._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(scene.app.relay_child == null and scene.app.mode == "relay_rooms", "Android Back leaves while the saved contribution awaits acknowledgement: " + key)
	_check(Canonical.digest(scene.store.values) == before and Canonical.same(session.coordinator.pending(), pending), "Leaving does not erase or rewrite the pending contribution: " + key)
	if scene.app.relay_child != null: scene.app._leave_online_relay()
	var retired: WeakRef = weakref(preview)
	await process_frame
	api.release.emit()
	await process_frame
	_check(retired.get_ref() == null and scene.app.mode == "relay_rooms" and scene.app.relay_child == null and not session.busy(), "Late submission response cannot reopen its review or photo card: " + key)
	_check(api.receipts.size() == 1 and _post_count(api) == 1, "The original contribution was submitted exactly once: " + key)
	if lose_reply:
		_check(Canonical.same(session.coordinator.pending().get("body", {}), pending.body), "A lost acknowledgement retains the identical request and idempotency key: " + key)
		_check(await session.coordinator.reconcile() and session.coordinator.pending().is_empty(), "Explicit receipt checking recovers the acknowledgement after exit: " + key)
	else:
		_check(session.coordinator.pending().is_empty() and session.coordinator.last_receipt().recording_hash == fixtures["relay-a"].recording_hash, "A validated acknowledgement persists after the presentation is gone: " + key)
	_check(_post_count(api) == 1 and Canonical.digest(scene.app.saves.data) == solo_before, "Receipt recovery never resubmits or changes the solo journey: " + key)
	scene.app._enter_online_relay()
	_check(scene.app.relay_child != null and scene.app.relay_child.mode == "online_waiting", "Reopening shows the confirmed next-player state: " + key)
	scene.app._leave_online_relay()
	scene.viewport.queue_free()
	await process_frame

func _post_count(api: FakeApi) -> int:
	var count := 0
	for request: Dictionary in api.calls:
		if request.method == HTTPClient.METHOD_POST: count += 1
	return count

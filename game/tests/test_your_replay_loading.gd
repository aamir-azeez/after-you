extends "res://tests/test_shared_replays.gd"

func _run() -> void:
	root.size=Vector2i(960,540)
	var saved := {"a":_fixture("","first-light-a"),"b":_fixture("","first-light-b"),"draft":{}}
	var storage := Save.new("user://your-replay-loading-%d.json" % Time.get_ticks_usec())
	storage.data.settings.sound=false
	storage.data.settings.haptics=false
	storage.data.settings.reduced_motion=true
	_check(storage.save_attempt("first-light",saved,true),"Seed the real completed First Light replay")
	var app := Main.new()
	app.saves=storage
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.world.set_process(false)
	app.api.queue_free()
	var api := Api.new()
	app.add_child(api)
	app.api=api
	app.application_backgrounded=false
	app._show_collection()
	var original := Canonical.digest(storage.data)
	var bytes := _save_hashes(storage.path)
	var live: RefCounted=app.sim
	var state: Dictionary=live.snapshot()
	var row := _button(app.overlay,str(app.levels[0].title))
	_check(row != null,"The actual collection exposes the saved First Light replay")
	if row != null: row.pressed.emit()
	_check(app.mode == "collection_loading" and not app.running and app.overlay.visible,"Selecting a saved replay immediately shows loading without starting playback")
	_check(is_instance_valid(app._collection_replay_loading_bar) and app._collection_replay_loading_bar.is_visible_in_tree(),"The loading card contains a visible replay progress bar")
	_check(app.sim == live and Canonical.same(live.snapshot(),state),"Starting a worker leaves the live simulation unchanged")
	var progress: RefCounted=app._collection_replay_job.get("progress")
	await _drain(app)
	_check(app.mode == "preview" and app.running and app.collection_preview and app.sim != live and app.sim.tick == 0,"The joined worker adopts a prepared simulation at tick zero")
	_check(Canonical.same(app.review_recording,saved.b) and app.replay_frames.size() == int(saved.b.duration_ticks) and app.replay_index == 0,"Playback adopts exactly the selected recording and its prepared input frames")
	if progress != null:
		var counted: Dictionary=progress.snapshot()
		var expected := 2*int(saved.a.duration_ticks)+int(saved.b.duration_ticks)+2
		_check(counted.total == expected and counted.checked == expected and counted.phase == "ready","Progress counts both A verifications, the B verification, and preparation completion")
	_check(Canonical.same(live.snapshot(),state),"Worker preparation never mutates the previous simulation")
	app._show_collection()
	live=app.sim
	var bad: Dictionary=saved.b.duplicate(true)
	bad.final_state_hash="0".repeat(64)
	app._preview(bad,true)
	await _drain(app)
	_check(app.mode == "collection" and not app.running and app.sim == live,"An invalid final proof returns to the collection without adopting a simulation")
	_check(_contains_text(app.overlay,Main.PlayerCopy.MAIN_CD2F00E32FC5),"Failed verification displays its replay error in the collection")
	_check(Canonical.digest(storage.data) == original and _save_hashes(storage.path) == bytes,"Valid and invalid loads preserve every save generation byte")
	app._preview(saved.b,true)
	var cancelled: RefCounted=app._collection_replay_job.get("progress")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(app.mode == "collection" and cancelled != null and cancelled.cancelled(),"Android Back immediately returns and cancels pending replay work")
	await _drain(app)
	_check(app.mode == "collection" and not app.running and app.sim == live,"A retired worker can never open its replay after Back")
	app._preview(saved.b,true)
	var retired: RefCounted=app._collection_replay_job.get("progress")
	var back := _button(app.overlay,"Back to Your replays")
	_check(back != null,"The loading screen offers a visible Back action")
	if back != null: back.pressed.emit()
	app._preview(saved.a,true)
	await _drain(app)
	_check(retired != null and retired.cancelled() and app.mode == "preview" and app.role == "a" and Canonical.same(app.review_recording,saved.a),"Immediate reentry adopts only the newest request after retiring the old worker")
	_check(app.sim.tick == 0 and Canonical.digest(storage.data) == original and _save_hashes(storage.path) == bytes and api.calls.is_empty(),"Reentry preserves saves and never requests network data")
	app._show_collection()
	app._preview(saved.b,true)
	var exiting: RefCounted=app._collection_replay_job.get("progress")
	root.remove_child(app)
	_check(app._collection_replay_worker == null and exiting != null and exiting.cancelled(),"Leaving the scene cancels and joins its worker")
	app.queue_free()
	await process_frame
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(storage.path+suffix): DirAccess.remove_absolute(storage.path+suffix)
	print("YOUR REPLAY LOADING: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _drain(app: Node) -> void:
	var deadline := Time.get_ticks_msec()+10000
	while (app._collection_replay_worker != null or not app._collection_replay_job.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame
		app._service_collection_replay()
	_check(app._collection_replay_worker == null and app._collection_replay_job.is_empty(),"Replay worker drains within the bounded load window")

func _save_hashes(path: String) -> Dictionary:
	var result := {}
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix): result[suffix]=FileAccess.get_sha256(path+suffix)
	return result

func _contains_text(node: Node, fragment: String) -> bool:
	if node is Label and fragment in node.text: return true
	for child: Node in node.get_children():
		if _contains_text(child,fragment): return true
	return false

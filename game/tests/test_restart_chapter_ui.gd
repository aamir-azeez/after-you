extends "res://tests/test_relay_preview.gd"

const Storage = preload("res://services/local_save.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Archive = preload("res://services/attempt_archive.gd")

func _run() -> void:
	root.size = Vector2i(1280,720)
	await _retained_ready()
	await _retained_review()
	await _retained_draft_and_empty()
	await _completed_archive_replay()
	await _first_steps_prior()
	await _fresh_and_online()
	_cleanup()
	await process_frame
	await create_timer(0.15).timeout
	print("RESTART CHAPTER UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _seed_retained(key: String, first: Dictionary, draft: Dictionary, version: int) -> Dictionary:
	var path := _new_path("retained-restart")
	var definition := Registry.definition(key)
	var state := {"schema_version":definition.schema_version,"simulation_version":version,"level_id":definition.id,"level_version":definition.version,"definition_hash":Canonical.digest(definition),"pairs":[],"a":first.duplicate(true),"draft":draft.duplicate(true)}
	var storage := Storage.new(path)
	_check(storage.update_values({"relay":state}), "Retained fixture is written through normal durable local storage")
	var app := Preview.new()
	app.chapter_key = key
	app.journey = Journey.new(path,null,key)
	app.settings = {"sound":false,"haptics":false,"reduced_motion":true,"assistance":true}
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	_check(app.mode == "ready" and not app.journey.read_only, "Real preview natively validates retained journal before showing ready")
	return {"app":app,"path":path,"state":state}

func _retained_ready() -> void:
	var case := _seed_retained(Registry.RELAY,_fixture("relay-a"),{},2)
	var app: Node3D = case.app
	var bytes := _save_bytes(case.path)
	await _tap(app,"Restart chapter")
	_check(app.mode == "confirm_restart_chapter" and Canonical.same(bytes,_save_bytes(case.path)), "Actual Restart tap asks before touching retained A")
	var stale: Callable = _find_button(app.overlay,"Restart chapter").get_signal_connection_list("pressed")[0].callable
	await _tap(app,"Cancel")
	_check(app.mode == "ready" and Canonical.same(bytes,_save_bytes(case.path)) and app.journey.archived_attempts().is_empty(), "Cancel preserves every active generation and creates no archive")
	stale.call()
	_check(Canonical.same(bytes,_save_bytes(case.path)) and app.sim.simulation_version == 2, "Retired modal cannot restart the recovered old native turn")
	await _tap(app,"Restart chapter")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(app.mode == "ready" and Canonical.same(bytes,_save_bytes(case.path)), "Android Back uses the same guarded Cancel")
	await _tap(app,"Restart chapter")
	await _tap(app,"Restart chapter")
	_check(app.mode == "ready" and app.role == "a" and app.sim.simulation_version == 8 and app.journey.prior_recording().is_empty(), "Explicit confirmation begins new8 only after the old journal is archived")
	_check(Canonical.same(Archive.load_attempt(case.path,"relay",Canonical.digest(case.state),Journey.MAX_SAVE_BYTES),case.state), "The full exact accepted old A remains in its content-addressed archive")
	_check(_find_button(app.overlay,"Restart chapter") == null, "Fresh8 ready gains no additional Restart action")
	_check(app.journey.archived_attempts().is_empty() and _find_button(app.overlay,"Replays") == null, "The preserved accepted A is excluded from replay metadata and has no empty replay action")
	app.queue_free()
	await _settle()

func _retained_review() -> void:
	var draft := _fixture("relay-b")
	var case := _seed_retained(Registry.RELAY,_fixture("relay-a"),draft,2)
	var app: Node3D = case.app
	app._resume_draft()
	if app.mode == "bloom": app._process(Preview.COMPLETION_DURATION)
	_check(app.mode == "review" and app.sim.complete, "Actual old completed rehearsal reaches review")
	var bytes := _save_bytes(case.path)
	var frame: Dictionary = app.sim.snapshot()
	var review: Dictionary = app.review.duplicate(true)
	await _tap(app,"Restart chapter")
	await _tap(app,"Cancel")
	_check(app.mode == "review" and app.review == review and app.sim.snapshot() == frame and Canonical.same(bytes,_save_bytes(case.path)), "Review Cancel preserves the completed frame and exact saved draft")
	await _tap(app,"Restart chapter")
	var previous_generation: int = app.online_request_generation
	app.online_request_generation += 1
	await _tap(app,"Restart chapter")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(app.mode == "confirm_restart_chapter" and Canonical.same(bytes,_save_bytes(case.path)), "Stale generation can neither restart nor revive review through native Back")
	app.online_request_generation = previous_generation
	await _tap(app,"Restart chapter")
	_check(app.mode == "ready" and app.sim.simulation_version == 8 and Canonical.same(Archive.load_attempt(case.path,"relay",Canonical.digest(case.state),Journey.MAX_SAVE_BYTES),case.state), "Explicit review restart preserves old A and B draft together")
	_check(app.journey.archived_attempts().is_empty() and _find_button(app.overlay,"Replays") == null, "Preserved A and draft remain outside replay metadata and collection rows")
	app.queue_free()
	await _settle()

func _first_steps_prior() -> void:
	var first: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first_steps/cumulative-lift-a.json"))
	var case := _seed_retained(Registry.FIRST_STEPS,first,{},4)
	var app: Node3D = case.app
	_check(app.sim.simulation_version == 5, "First Steps old accepted A still pins its receiver to5")
	await _tap(app,"Restart chapter")
	await _tap(app,"Restart chapter")
	_check(app.mode == "ready" and app.sim.simulation_version == 8 and app.journey.simulation_version() == 4, "First Steps restart uses fresh8 without rewriting its authored envelope convention")
	_check(_find_button(app.overlay,"Restart chapter") == null, "Authored First Steps envelope4 alone does not show a stale-rules action")
	_check(Canonical.same(Archive.load_attempt(case.path,"relay",Canonical.digest(case.state),Journey.MAX_SAVE_BYTES),case.state), "First Steps prior remains exact in the archive")
	app.queue_free()
	await _settle()

func _retained_draft_and_empty() -> void:
	for draft: Dictionary in [_fixture("relay-a"), {}]:
		var case := _seed_retained(Registry.RELAY,{},draft,2)
		var app: Node3D = case.app
		_check(app.sim.simulation_version == 2, "Loading old draft or empty metadata never silently upgrades it")
		await _tap(app,"Restart chapter")
		await _tap(app,"Restart chapter")
		_check(app.mode == "ready" and app.sim.simulation_version == 8 and Canonical.same(Archive.load_attempt(case.path,"relay",Canonical.digest(case.state),Journey.MAX_SAVE_BYTES),case.state), "Explicit restart archives the entire old draft or empty envelope before fresh8")
		_check(app.journey.archived_attempts().is_empty() and _find_button(app.overlay,"Replays") == null, "Old draft or empty metadata is preserved but is not presented as a replay")
		app.queue_free()
		await _settle()

func _completed_archive_replay() -> void:
	var case := _seed_retained(Registry.RELAY,_fixture("relay-a"),{},2)
	var app: Node3D = case.app
	for name: String in ["relay-b","garden-a","garden-b"]:
		_check(app.journey.accept_recording(_fixture(name)), "Completed archive uses accepted native contribution: " + name)
	_check(app.journey.chapter_complete(), "Both native pairs complete the retained chapter")
	_check(Archive.save(case.path,"relay",case.state,Journey.MAX_SAVE_BYTES,Journey.MAX_ARCHIVED_ATTEMPTS).is_empty(), "The same collection also retains its earlier accepted-A recovery archive")
	var partial_path: String = case.path + ".attempt-" + Canonical.digest(case.state) + ".json"
	var partial_bytes := FileAccess.get_file_as_bytes(partial_path)
	app._show_ready()
	await _tap(app,"Retry")
	await _tap(app,"%s · 1 / %d" % [app.definition.title,app.definition.stages.size()])
	await _tap(app,"Retry")
	_check(app.mode == "ready" and app.journey.archived_attempts().size() == 1 and not partial_bytes.is_empty() and FileAccess.get_file_as_bytes(partial_path) == partial_bytes, "Whole-chapter retry lists only the completed replay while retaining the exact partial archive file")
	var before := _save_bytes(case.path)
	await _tap(app,"Replays")
	_check(app.mode == "replay_collection", "A completed archive keeps the visible Replays entry")
	var partial_label := "%s · 0 / %d" % [Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(partial_path)).replace("T"," "),app.definition.stages.size()]
	_check(_find_button(app.overlay,partial_label) == null, "Collection omits the preserved zero-stage recovery file")
	var completed: Dictionary = app.journey.archived_attempts()[0] if not app.journey.archived_attempts().is_empty() else {}
	_check(not completed.is_empty(), "Completed archive metadata remains listed by the unchanged service")
	if not completed.is_empty():
		await _tap(app,"%s · %d / %d" % [Time.get_datetime_string_from_unix_time(int(completed.modified)).replace("T"," "),completed.stage_count,app.definition.stages.size()])
		_check(app.mode == "replay" and app.sim.simulation_version == 2, "Actual archived row starts the exact old-rules replay")
		var ticks := 0
		while app.mode in ["replay","bloom"] and ticks < 1250:
			if app.mode == "bloom": app._process(Preview.COMPLETION_DURATION)
			else: app._physics_process(1.0/30.0)
			ticks += 1
		_check(app.mode == "ready" and ticks > 0 and ticks < 1250, "The completed old archive replays both native pairs and returns to the new chapter")
	_check(Canonical.same(before,_save_bytes(case.path)) and FileAccess.get_file_as_bytes(partial_path) == partial_bytes and Canonical.same(Archive.load_attempt(case.path,"relay",Canonical.digest(case.state),Journey.MAX_SAVE_BYTES),case.state), "Replay leaves the new journal and exact partial recovery archive unchanged")
	app.queue_free()
	await _settle()

func _fresh_and_online() -> void:
	var case := _seed_retained(Registry.RELAY,{}, {},8)
	var app: Node3D = case.app
	_check(_find_button(app.overlay,"Restart chapter") == null, "Empty current8 ready has no Restart action")
	app.queue_free()
	await _settle()
	case = _seed_retained(Registry.RELAY,_fixture("relay-a"),{},2)
	app = case.app
	var bytes := _save_bytes(case.path)
	# A non-null online owner must short-circuit before any local service call.
	app.online_session = RefCounted.new()
	app._confirm_restart_chapter()
	_check(app.mode == "ready" and Canonical.same(bytes,_save_bytes(case.path)), "The local Restart handler cannot replace an online-pinned chapter")
	app.online_session = null
	app.queue_free()
	await _settle()

func _tap(app: Node3D, text: String) -> void:
	await _settle()
	var button := _find_button(app.overlay,text)
	_check(button != null and not button.disabled,"Rendered chapter action is reachable: "+text)
	if button == null or button.disabled: return
	_check(app.ui.get_global_rect().encloses(button.get_global_rect()),"Chapter action stays within the scaled safe viewport: "+text)
	var point := button.get_global_rect().get_center()
	for down: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position=point
		event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed=down
		root.push_input(event,true)
	await _settle()

func _settle() -> void:
	await process_frame
	await process_frame

func _cleanup() -> void:
	for path: String in paths:
		var directory := DirAccess.open(path.get_base_dir())
		if directory == null: continue
		for name: String in directory.get_files():
			if name == path.get_file() or name.begins_with(path.get_file()+"."):
				DirAccess.remove_absolute(path.get_base_dir().path_join(name))

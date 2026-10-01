extends SceneTree

const Main = preload("res://main.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Storage = preload("res://services/local_save.gd")
const Levels = preload("res://core/levels.gd")
const Simulation = preload("res://core/simulation.gd")
const TurnState = preload("res://services/turn_state.gd")
const FakeApi = preload("res://tests/fake_rooms_api.gd")
const ChapterPreview = preload("res://relay_preview.gd")
const ChapterJourney = preload("res://services/relay_journey.gd")
const ChapterRegistry = preload("res://services/chapter_registry.gd")
const Retained = preload("res://tests/retained_chapter_fixture.gd")

class SaveProbe:
	extends "res://services/local_save.gd"
	var read_mode: Callable
	var completed_save_modes: Array=[]
	func update_values(changes: Dictionary, erase_keys: Array=[]) -> bool:
		var draft: Dictionary=changes.get("room_draft",{}).get("attempt",{}).get("draft",{})
		for value: Dictionary in changes.get("attempts",{}).values():
			if value.get("draft",{}).get("completed",false):
				draft=value.draft
		if draft.get("completed",false) and read_mode.is_valid():
			completed_save_modes.append(read_mode.call())
		return super.update_values(changes,erase_keys)

var checks := 0
var failures := 0
var app: Node
var api: Node
var path := ""
var first: Dictionary
var second: Dictionary
var frames: Array

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	path="user://completion-test-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	first=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-a.json"))
	second=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-b.json"))
	frames=Simulation.expand_recording_inputs(second)
	app=Main.new()
	app.saves=SaveProbe.new(path)
	app.saves.data.settings.sound=false
	app.saves.data.settings.haptics=false
	app.saves.flush()
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.world.set_process(false)
	api=FakeApi.new()
	app.add_child(api)
	app.api=api
	app.saves.read_mode=func(): return app.mode
	await process_frame
	_test_live_completion()
	_test_background()
	_test_explicit_review()
	_test_cancelled_countdown()
	await _test_collection()
	_test_noncompletion()
	_test_failed_save()
	_test_online_draft()
	_test_reduced_motion()
	await _test_chapter_replays()
	app.saves.read_mode=Callable()
	app.soundscape.set_backgrounded(true)
	app.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix):
			DirAccess.remove_absolute(path+suffix)
	print("AFTER YOU COMPLETION MOMENT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func _prepare() -> void:
	app.application_backgrounded=false
	app.foreground_refresh_queued=false
	app.foreground_refresh_running=false
	app.submission_in_flight=false
	app.saves.read_only=false
	app.saves.last_error=""
	app.level_index=0
	app.current_level=Levels.get_level(0)
	app.attempt={"a":first.duplicate(true),"b":{},"draft":{}}
	app.role="b"
	app.room_play=false
	app.active_room={}
	app.saves.update_values({"attempts":{},"completed":{},"replays":{},"room":{}},["room_draft","pending_turn"])
	app.saves.completed_save_modes.clear()
	api.calls.clear()
	app._prepare_turn()

func _feed(frame: Dictionary) -> void:
	var right: Vector3=app.world.camera.global_basis.x
	var forward: Vector3=app.world.camera.global_basis.z
	right=Vector3(right.x,0,right.z).normalized()
	forward=Vector3(forward.x,0,forward.z).normalized()
	var movement := Vector3(frame.move_x,0,frame.move_z)
	app.stick.value=Vector2(movement.dot(right),movement.dot(forward))
	app.action_pressed=frame.interact
	app._physics_process(1.0/30.0)

func _finish_live() -> void:
	app._begin_turn()
	for frame: Dictionary in frames:
		_feed(frame)

func _finish_preview() -> void:
	app._preview(second)
	for _i: int in range(frames.size()+1):
		app._physics_process(1.0/30.0)

func _finish_collection_preview() -> bool:
	app._preview(second,true)
	var deadline := Time.get_ticks_msec()+10000
	# Processing is disabled in this fixture; join and adopt the loaded replay
	# without advancing the completion timer or unrelated app services.
	while (app._collection_replay_worker != null or not app._collection_replay_job.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame
		app._service_collection_replay()
	var ready: bool=app._collection_replay_worker == null and app._collection_replay_job.is_empty() and app.mode == "preview" and app.running and app.collection_preview and app.sim.tick == 0
	_check(ready,"Saved replay preparation finishes within the bounded load window before playback")
	if not ready:
		app._cancel_collection_replay()
		return false
	for _i: int in range(frames.size()+1):
		app._physics_process(1.0/30.0)
	return true

func _test_live_completion() -> void:
	_prepare()
	_finish_live()
	_check(app.mode=="completion" and app.sim.complete and app.world.bloomed,"Main control path reaches an unobstructed bloom mode")
	_check(not app.running and not app.overlay.visible and app.overlay_shade==null,"Completion stops simulation and removes the review card and shade")
	_check(not app.stick.visible and not app.interact_button.visible and not app.finish_button.visible and app.stick.value==Vector2.ZERO and not app.action_pressed,"Completion releases and hides gameplay inputs")
	var stored := Storage.new(path)
	stored.load_data()
	_check(TurnState.same_recording(stored.attempt("first-light").draft,app.review_recording) and stored.attempt("first-light").draft.completed,"Completed recording is already durable before the presentation delay")
	_check(TurnState.review(app.current_level,stored.attempt("first-light").draft,stored.attempt("first-light")).valid,"Reloaded completed draft still passes authoritative replay verification")
	_check(app.saves.completed_save_modes==["play"],"Final draft is persisted once while still in the live recording state")
	_check(stored.attempt("first-light").a==first and stored.attempt("first-light").b.is_empty() and stored.data.completed.is_empty() and stored.data.replays.is_empty(),"Bloom neither changes the earlier turn nor commits the second turn")
	var tick: int=app.sim.tick
	var state: String=app.sim.state_hash()
	var generation: int=app.saves.data.generation
	app.stick.value=Vector2.ONE
	app.action_pressed=true
	app._physics_process(20.0)
	app._commit_turn()
	_check(app.sim.tick==tick and app.sim.state_hash()==state and app.saves.data.generation==generation,"Late inputs and a direct commit request cannot advance or commit the bloom mode")
	app._process(0.7)
	_check(app.mode=="completion" and not app.overlay.visible,"The first fraction of the bloom remains visible without review")
	app._process(Main.COMPLETION_MOMENT_SECONDS)
	_check(app.mode=="review" and app.completion_time_left==0.0 and app.overlay.visible,"Elapsed presentation time opens review and clears the timer")
	_check(_button(app.overlay,"Save turn")!=null and app.saves.data.completed.is_empty(),"The completed island still requires the player's explicit Save turn action")
	_check(_has_text(app.overlay,PlayerCopy.MAIN_32A4E00F108C),"An unsaved completion still explains the available Save turn action")
	var count: int=app.overlay.get_child_count()
	app._process(20.0)
	_check(app.overlay.get_child_count()==count and app.saves.data.generation==generation,"Expired countdown does not reopen review or repeatedly save")

func _test_background() -> void:
	_prepare()
	_finish_live()
	app._process(0.3)
	var remaining: float=app.completion_time_left
	var generation: int=app.saves.data.generation
	var state: String=app.sim.state_hash()
	app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	app._process(30.0)
	app._physics_process(30.0)
	_check(app.mode=="completion" and app.completion_time_left==remaining and app.sim.state_hash()==state,"Background holds both the completion countdown and simulation")
	_check(app.saves.data.generation==generation and api.calls.is_empty(),"Background retains the already saved draft without another save or network request")
	app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	app._process(0.2)
	_check(app.mode=="completion" and app.completion_time_left<remaining and app.foreground_refresh_queued and api.calls.is_empty(),"Resume continues the visible moment and defers room refresh until a safe menu")
	app._process(Main.COMPLETION_MOMENT_SECONDS)
	_check(app.mode=="review" and api.calls.is_empty() and app.saves.data.completed.is_empty(),"Returning from background reaches review without submitting the turn")

func _test_explicit_review() -> void:
	for action: String in ["pause","escape","android_back"]:
		_prepare()
		_finish_preview()
		if action=="pause":
			var pause := _button(app.hud,"Pause")
			_check(pause!=null and pause.visible,"HUD keeps a reachable Pause action during completion")
			if pause!=null:
				pause.pressed.emit()
		elif action=="escape":
			var key := InputEventKey.new()
			key.pressed=true
			key.physical_keycode=KEY_ESCAPE
			app._unhandled_key_input(key)
		else:
			app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		_check(app.mode=="review" and app.completion_time_left==0.0 and not app.running,"Explicit "+action+" skips directly to review instead of Home or paused rehearsal")
		_check(api.calls.is_empty() and app.saves.data.completed.is_empty(),"Explicit "+action+" does not commit a turn")

func _test_cancelled_countdown() -> void:
	_prepare()
	_finish_preview()
	app._show_home()
	app._process(20.0)
	_check(app.mode=="home" and app.completion_time_left==0.0,"Leaving for Home cancels the pending review")
	_prepare()
	_finish_preview()
	app._prepare_turn()
	app._process(20.0)
	_check(app.mode=="ready" and app.completion_time_left==0.0 and app.sim.tick==0,"A new rehearsal is not replaced by the preceding completion's review")
	_finish_preview()
	app._preview(second)
	app._process(20.0)
	_check(app.mode=="preview" and app.completion_time_left==0.0 and app.running and app.sim.tick==0,"A new replay cancels the old countdown without advancing its simulation")

func _test_collection() -> void:
	_prepare()
	var collection := {"a":first.duplicate(true),"b":second.duplicate(true),"draft":{}}
	app.saves.save_attempt("first-light",collection,true)
	app.attempt=collection.duplicate(true)
	var before: String=FileAccess.get_file_as_string(path)
	if not await _finish_collection_preview(): return
	_check(app.mode=="completion" and app.collection_preview,"Saved combined replay also exposes the bloom before its collection card")
	app._process(Main.COMPLETION_MOMENT_SECONDS)
	_check(app.mode=="collection" and _button(app.overlay,"Save turn")==null,"Collection review contains no action to recommit the old recording")
	_check(_has_text(app.overlay,PlayerCopy.SHARED_REPLAY_VIEW_8432676D063D) and not _has_text(app.overlay,PlayerCopy.MAIN_32A4E00F108C),"An earned replay describes already-saved contributions without promising an unavailable Save action")
	_check(_button(app.overlay,"Replay")!=null and _button(app.overlay,"Back")!=null and _button(app.overlay,"Retry")==null,"Earned replay completion retains its read-only Replay and Back actions")
	app._commit_turn()
	if not await _finish_collection_preview(): return
	app._pause()
	_check(app.mode=="collection" and FileAccess.get_file_as_string(path)==before and api.calls.is_empty(),"Repeated collection playback and explicit skipping remain read-only")

func _test_noncompletion() -> void:
	_prepare()
	app.role="a"
	app.attempt={"a":{},"b":{},"draft":{}}
	app._preview(first)
	for _i: int in range(int(first.duration_ticks)+1):
		app._physics_process(1.0/30.0)
	_check(app.mode=="review" and app.completion_time_left==0.0 and not app.sim.complete,"First-player handoff review does not wait for an island bloom")
	_prepare()
	app._begin_turn()
	for _i: int in range(601):
		app._physics_process(1.0/30.0)
	_check(app.mode=="review" and app.completion_time_left==0.0 and not app.sim.complete,"Missed handoff reaches retry review immediately")
	_prepare()
	app._resume_draft(second)
	_check(app.mode=="review" and app.completion_time_left==0.0,"Restoring an already finished local draft opens review directly")

func _test_failed_save() -> void:
	_prepare()
	app._begin_turn()
	for frame: Dictionary in frames.slice(0,frames.size()-1):
		_feed(frame)
	var before := FileAccess.get_file_as_string(path)
	app.saves.read_only=true
	app.saves.last_error="Injected final draft write failure"
	_feed(frames.back())
	_check(app.sim.complete and app.mode=="review" and app.completion_time_left==0.0,"A failed final save bypasses the delay and opens review immediately")
	_check(app.review_recording.completed and not app.review_recording.actions.is_empty() and _button(app.overlay,"Save turn")!=null,"Failed persistence retains the full in-memory recording for retry")
	_check(app.toast_label.visible and app.toast_label.text=="Injected final draft write failure","Final save failure is visible to the player")
	_check(FileAccess.get_file_as_string(path)==before and app.saves.data.completed.is_empty(),"Failed final write preserves the previous durable draft without marking completion")
	app.saves.read_only=false

func _test_online_draft() -> void:
	_prepare()
	app.room_play=true
	app.active_room={"room_id":"synthetic-room","revision":2}
	_finish_live()
	var saved := Storage.new(path)
	saved.load_data()
	var draft: Dictionary=saved.data.get("room_draft",{})
	_check(app.mode=="completion" and draft.get("room_id")=="synthetic-room" and draft.get("revision")==2 and TurnState.same_recording(draft.get("attempt",{}).get("draft",{}),app.review_recording),"Online completion first saves a draft tied to the current room revision")
	_check(not saved.data.has("pending_turn") and api.calls.is_empty(),"Watching the bloom does not create an uncertain submission or send a request")
	app._process(Main.COMPLETION_MOMENT_SECONDS)
	_check(_button(app.overlay,"Save turn")!=null and api.calls.is_empty(),"Online completion stops at the explicit Save turn action")

func _test_reduced_motion() -> void:
	_prepare()
	app.saves.data.settings.reduced_motion=true
	app._apply_settings()
	_finish_preview()
	var flower: Node3D=app.world.flowers[0]
	var rotation := flower.rotation
	var camera_transform: Transform3D=app.world.camera.transform
	app.world._process(0.5)
	app._process(0.5)
	_check(app.world.reduced_motion and flower.rotation==rotation and app.world.camera.transform==camera_transform,"Completion respects reduced motion without introducing flower sway or a new camera movement")
	_check(flower.scale.x>0.001 and app.mode=="completion" and not app.overlay.visible,"Existing bloom presentation can advance while simulation and review remain held")
	app._process(Main.COMPLETION_MOMENT_SECONDS)
	_check(app.mode=="review" and app.saves.data.settings.reduced_motion,"Reduced motion still reaches the same explicit review flow")

func _test_chapter_replays() -> void:
	for key: String in [ChapterRegistry.FIRST_STEPS, ChapterRegistry.HIGH_AND_LOW, ChapterRegistry.ROLLING_HOME]:
		var journal_path := "user://completion-chapter-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
		_check(Retained.seed(journal_path,key),"Completed replay fixture uses a real retained journal envelope")
		var journal := ChapterJourney.new(journal_path, null, key)
		journal.load_data()
		var definition := ChapterRegistry.definition(key)
		var folder := "first_steps" if key == ChapterRegistry.FIRST_STEPS else "cooperative"
		for stage: Dictionary in definition.stages:
			for role: String in ["a", "b"]:
				var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + folder + "/" + stage.id + "-" + role + ".json"))
				_check(journal.accept_recording(record), "A native verified pair prepares the saved completion replay: " + key)
		var before := FileAccess.get_sha256(journal_path)
		var preview := ChapterPreview.new()
		preview.chapter_key = key
		preview.journey = journal
		preview.settings = {"sound": false, "haptics": false, "reduced_motion": false}
		root.add_child(preview)
		preview.set_process(false)
		preview.set_physics_process(false)
		preview.world.set_process(false)
		preview.replay_pair_index = 1
		preview._play_collection_pair()
		for _frame in range(preview.replay_frames.size() + 1): preview._physics_process(1.0 / 30.0)
		_check(preview.sim.snapshot().get("complete", false) and preview.mode == "bloom" and not preview.overlay.visible, "The actual terminal collection replay keeps its completed world visible: " + key)
		if key == ChapterRegistry.ROLLING_HOME:
			for input: String in ["escape", "android_back"]:
				var remaining: float = preview.completion_remaining
				if input == "escape":
					var event := InputEventKey.new()
					event.pressed = true
					event.physical_keycode = KEY_ESCAPE
					preview._unhandled_key_input(event)
				else: preview._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
				preview._process(20.0)
				_check(preview.mode == "paused" and not preview.running and preview.completion_remaining == remaining, "Completion " + input + " pauses the held moment without leaving or consuming time")
				var resume := _button(preview.overlay, "Resume")
				_check(resume != null, "Paused celebration exposes its actual Resume control")
				if resume != null: resume.pressed.emit()
				_check(preview.mode == "bloom" and not preview.running and not preview.overlay.visible, "Resume restores the same completed world without replaying inputs")
		var finished_tick: int = preview.sim.tick
		var finished_hash: String = preview.sim.state_hash()
		preview._physics_process(10.0)
		preview._process(2.5)
		_check(preview.mode == "bloom" and not preview.overlay.visible and preview.sim.tick == finished_tick and preview.sim.state_hash() == finished_hash, "The replay holds its final state through the bloom without advancing simulation: " + key)
		_check(FileAccess.get_sha256(journal_path) == before, "The presentation delay never resaves accepted recordings: " + key)
		preview._process(ChapterPreview.COMPLETION_DURATION)
		_check(preview.mode == "complete" and not preview.running and FileAccess.get_sha256(journal_path) == before, "After the finite celebration, collection navigation resumes without rewriting progress: " + key)
		preview.queue_free()
		await process_frame
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(journal_path + suffix): DirAccess.remove_absolute(journal_path + suffix)

func _button(node: Node, label: String) -> Button:
	if node is Button and node.text==label:
		return node
	for child: Node in node.get_children():
		var found := _button(child,label)
		if found!=null:
			return found
	return null

func _has_text(node: Node, text: String) -> bool:
	if node is Label and node.text==text:
		return true
	for child: Node in node.get_children():
		if _has_text(child,text): return true
	return false

func _check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL: "+message)

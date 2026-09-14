extends Node3D
## Offline rehearsal for the authored Lighthouse. Accepted input remains immutable.

const Catalog = preload("res://core/lighthouse/stage_catalog.gd")
const Simulation = preload("res://core/lighthouse/borrowed_light.gd")
const Journey = preload("res://services/lighthouse_journey.gd")
const World = preload("res://presentation/lighthouse_world.gd")
const Controls = preload("res://presentation/chapter_controls.gd")
const LocalSave = preload("res://services/local_save.gd")
const Soundscape = preload("res://services/soundscape.gd")

var journey: RefCounted = Journey.new()
var sim: RefCounted
var world: Node3D
var controls: CanvasLayer
var soundscape: Node
var settings: Dictionary = {}
var checkpoint: Dictionary = {}
var history: Array = []
var prior: Dictionary = {}
var role := "a"
var stage: Dictionary = {}
var running := false
var backgrounded := false
var mode := "ready"
var action_pressed := false
var review: Dictionary = {}
var replay_frames: Array = []
var replay_cursor := 0
var collection_index := -1
var moment_replay := false

func _ready() -> void:
	if settings.is_empty():
		var saved := LocalSave.new()
		saved.load_data()
		settings = saved.data.settings.duplicate(true)
	journey.load_data()
	soundscape = Soundscape.new()
	soundscape.configure(settings)
	add_child(soundscape)
	world = World.new()
	add_child(world)
	world.reduced_motion = bool(settings.get("reduced_motion", false))
	controls = Controls.new()
	controls.settings = settings.duplicate(true)
	add_child(controls)
	controls.pause_requested.connect(_pause)
	controls.action_requested.connect(func(): action_pressed = true)
	controls.finish_requested.connect(_finish)
	get_tree().auto_accept_quit = false
	_show_ready()

func _card(title: String, text: String) -> VBoxContainer:
	running = false
	action_pressed = false
	return controls.card(title, text)

func _show_ready() -> void:
	mode = "ready"
	collection_index = -1
	if journey.read_only:
		_show_error(journey.last_error)
		return
	if journey.chapter_complete() or journey.stage_id().is_empty():
		_show_collection()
		return
	history = journey.pairs()
	checkpoint = journey.checkpoint()
	prior = journey.prior_recording()
	role = journey.role()
	stage = Catalog.definition(journey.stage_id())
	if not _reset_live(): return
	_present_start()
	var stories := {
		"borrowed-light": "The lighthouse went quiet. Someone left a little light behind.",
		"missing-piece": "Your first path remains. Across the water, an empty cradle waits for its missing lens.",
		"two-promises": "One light reached the shore. Two promises can wake the path beyond it.",
		"after-the-first-bell": "The keeper crossed this water in two small steps. Leave a path, a place to rest, and a way onward.",
		"what-carried-you": "The light that brought you here does not have to stay behind. Leave it where your friend can find it.",
		"a-welcome-left-on": "The keeper did not leave the light on for a ship. They left it on for someone coming home. One last promise, kept together."
	}
	var story: String = stories.get(str(stage.stage_id), "Every path remembers the two of you. Let the light reach a little farther.")
	var card := _card("%d / %d  ·  %s" % [int(checkpoint.stage_index) + 1, Journey.TOTAL_STAGES, stage.title], story + "\n\n" + str(stage["hint_" + role]) + "\n\nSolo chapter preview · saved on this device. Play both contributions at your own pace.")
	if not journey.draft().is_empty():
		card.add_child(controls.button("Resume rehearsal", _resume_draft))
	card.add_child(controls.button("Record this turn", _begin))
	if role == "b":
		card.add_child(controls.button("Re-record the earlier contribution", func(): _confirm_checkpoint(int(journey.checkpoint().stage_index))))
	if not history.is_empty():
		card.add_child(controls.button("Watch the saved stages", _watch_collection))
	card.add_child(controls.button("Back to the journey", _leave))

func _reset_live() -> bool:
	sim = journey.create_live_simulation()
	if sim == null:
		_show_error(journey.last_error)
		return false
	return true

func _present_start() -> void:
	world.load_level(stage)
	world.present_history(checkpoint)
	world.present(sim.snapshot(), true)

func _begin() -> void:
	if not _reset_live(): return
	review = {}
	collection_index = -1
	_present_start()
	_start_play()

func _start_play() -> void:
	mode = "play"
	controls.show_play()
	running = true
	_update_hud(sim.snapshot())

func _resume_draft() -> void:
	var draft: Dictionary = journey.draft()
	if journey.read_only:
		_show_error(journey.last_error)
		return
	if draft.is_empty() or not _reset_live(): return
	for input: Dictionary in Simulation.expand_recording_inputs(draft):
		sim.step(input)
	_present_start()
	if sim.finished:
		review = draft
		_show_review()
	else:
		_start_play()

func _physics_process(_delta: float) -> void:
	if not running or backgrounded: return
	var input: Dictionary
	if mode == "replay":
		if replay_cursor >= replay_frames.size():
			_replay_ended()
			return
		input = replay_frames[replay_cursor]
		replay_cursor += 1
	else:
		var move: Vector2 = controls.stick.value
		var keyboard := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
		if keyboard.length() > 0: move = keyboard.limit_length()
		var right: Vector3 = world.camera.global_basis.x
		var forward: Vector3 = world.camera.global_basis.z
		var direction := (Vector3(right.x, 0, right.z).normalized() * move.x + Vector3(forward.x, 0, forward.z).normalized() * move.y).limit_length()
		input = {"move_x": direction.x, "move_z": direction.z, "interact": action_pressed}
		action_pressed = false
	advance_input(input)

func advance_input(input: Dictionary) -> void:
	# Real touch input and controlled input-driven tests share this one path.
	if not running or backgrounded or mode not in ["play", "replay"]: return
	var state: Dictionary = sim.step(input)
	if not str(sim.error).is_empty():
		_show_error(str(sim.error))
		return
	var sounds: Array = []
	for event: String in state.get("events", []):
		if event == "bridge_open": sounds.append("bridge_opened")
		elif event == "stage_complete": sounds.append("island_bloomed")
	soundscape.consume_events(sounds, mode == "play")
	world.present(state)
	_update_hud(state)
	if mode == "play" and int(state.tick) % 30 == 0 and not _save_draft(): return
	if state.finished:
		if state.get("beacon", {}).get("lit", false): _show_final_moment()
		elif mode == "replay": _replay_ended()
		else: _finish()

func _update_hud(state: Dictionary) -> void:
	var display := state.duplicate(true)
	var signals: Dictionary = state.get("receiver_goal", {}).get("signals", {})
	if not signals.is_empty():
		var lit := 0
		for value: Variant in signals.values():
			if value == true: lit += 1
		display.progress_message = "Beams together: %d / %d" % [lit, signals.size()]
	if state.has("sequence"):
		var sequence: Dictionary = state.sequence
		var phase := str(sequence.get("phase", "off"))
		if str(state.get("role", "")) == "a":
			var required: Array = sequence.get("required_ticks", [])
			if sequence.get("broken", false):
				display.progress_message = "The sequence went dark · rehearse again"
			elif phase == "off":
				display.progress_message = "First path → Rest Rock → second path"
			elif required.size() == 2:
				var elapsed := int(sequence.get(phase + "_ticks", 0))
				var target := int(required[0 if phase == "first" else 1])
				var next := "Keep the path lit" if elapsed < target else "Choose the second path" if phase == "first" else "Ready to finish" if state.get("can_commit", false) else "Sequence incomplete · rehearse again"
				display.progress_message = "%s path · %.1f / %.1f s\n%s" % [phase.capitalize(), float(elapsed) / Simulation.TICK_RATE, float(target) / Simulation.TICK_RATE, next]
		else:
			var reached := int(state.get("route_progress", {}).get("step", 0))
			var first_open := phase == "first"
			var second_open := phase == "second"
			var first_hint := "Follow the first light" if first_open else "Wait for the first light" if phase == "off" else "First path missed · rehearse this turn"
			var rest_hint := "Rest Rock reached · take the second path" if second_open else "Rest Rock is safe · wait for the second light"
			var milestones := [first_hint, "Cross to Rest Rock", rest_hint, "Cross to the tower", "Tower reached · ring the bell"]
			display.progress_message = milestones[clampi(reached, 0, milestones.size() - 1)]
	if state.has("handoff"):
		var handoff: Dictionary = state.handoff
		var local_role := str(state.get("role", ""))
		var prop: Dictionary = state.get("props", {}).get(handoff.get("prop_id", ""), {})
		if handoff.get("authority", "") == "source":
			display.progress_message = "Bring the lens to Rest Rock" if local_role == "a" else "Your partner still holds the lens"
		elif handoff.get("authority", "") == "offered":
			if local_role == "a":
				display.progress_message = "Lens left at Rest Rock · ready to finish" if state.get("can_commit", false) else "Leave the lens earlier · rehearse again"
			else:
				display.progress_message = "The lens is waiting for you on Rest Rock"
		elif prop.get("status", "") == "fitted":
			display.progress_message = "The same light, in its new home"
		else:
			display.progress_message = "Carry the lens to the tower projector"
	if state.has("beacon"):
		var beacon: Dictionary = state.beacon
		if beacon.get("lit", false):
			display.progress_message = "A welcome, left on."
		elif str(state.get("role", "")) == "a":
			if state.get("can_commit", false):
				display.progress_message = "Your light is held · ready to finish"
			else:
				display.progress_message = "Upper light · contribution not ready"
				display.message = str(state.get("commit_reason", stage.hint_a))
		else:
			var lit := 0
			for value: Variant in beacon.get("signals", {}).values():
				if value == true: lit += 1
			var next := "Step onto the two-mark crest" if beacon.get("ready", false) else "Align the second light beside your partner's memory"
			if state.get("context_action", {}).get("id", "") == "light_beacon" and state.context_action.get("enabled", false): next = "Leave the light on"
			display.progress_message = "Two lights: %d / 2\n%s" % [lit, next]
	controls.update_state("THE SLEEPING LIGHTHOUSE\n%d / %d  ·  %s" % [int(checkpoint.stage_index) + 1, Journey.TOTAL_STAGES, "Replay" if mode == "replay" else stage.title], float(Simulation.MAX_TICKS - int(state.tick)) / Simulation.TICK_RATE, display, mode == "play")

func _save_draft(after_retry: String = "play") -> bool:
	if sim.tick == 0: return true
	if journey.save_live_draft(sim): return true
	_show_save_problem(journey.last_error, after_retry)
	return false

func _finish() -> void:
	if mode == "moment":
		_continue_final_moment()
		return
	if mode != "play": return
	review = sim.export_recording()
	if not _save_draft("review"): return
	_show_review()

func _show_final_moment() -> void:
	moment_replay = mode == "replay"
	if not moment_replay:
		review = sim.export_recording()
		if not _save_draft("review"): return
	mode = "moment"
	running = false
	action_pressed = false
	controls.show_moment("Back to your chapter" if moment_replay and collection_index >= 0 else "Back to review" if moment_replay else "Review this turn")

func _continue_final_moment() -> void:
	if moment_replay: _replay_ended()
	else: _show_review()

func _show_review() -> void:
	mode = "review"
	var verified: Dictionary = Simulation.verify_recording(review, prior, history)
	var can_save: bool = bool(verified.get("valid", false)) and bool(verified.get("snapshot", {}).get("can_commit", false))
	var text := "Watch your moment, then keep it. You can rehearse again without changing an earlier checkpoint."
	if not can_save:
		text += "\n\n" + str(verified.get("snapshot", {}).get("commit_reason", verified.get("error", "Complete this contribution before saving it.")))
	var card := _card("A little light to leave behind.", text)
	card.add_child(controls.button("Preview this turn", _preview_turn))
	var accept: Button = controls.button("Save this contribution", _accept)
	accept.disabled = not can_save
	card.add_child(accept)
	card.add_child(controls.button("Rehearse this turn again", _begin))
	card.add_child(controls.button("Leave and keep the draft", _leave))

func _accept() -> void:
	if mode not in ["review", "save_error"]: return
	if not journey.accept_recording(review):
		_show_save_problem(journey.last_error, "commit")
		return
	if role == "a":
		_show_ready()
		return
	mode = "checkpoint"
	var card := _card("This place remembers.", "Both contributions are safely kept. Your next rehearsal begins where these spirits stopped.\n\nYou can close the app here and return later.")
	card.add_child(controls.button("Continue from this checkpoint", _show_ready))
	card.add_child(controls.button("Watch your saved stages", _watch_collection))
	card.add_child(controls.button("Revisit a checkpoint", _choose_checkpoint))
	card.add_child(controls.button("Back to the journey", _leave))

func _preview_turn() -> void:
	_start_replay(review, prior, history)

func _start_replay(recording: Dictionary, source: Dictionary, prefix: Array) -> void:
	sim = Simulation.new()
	if not sim.reset(str(recording.role), source, prefix):
		_show_error(str(sim.error))
		return
	var checked: Dictionary = Simulation.verify_recording(recording, source, prefix)
	if not checked.valid:
		_show_error(str(checked.error))
		return
	checkpoint = Simulation.checkpoint_from_pairs(prefix).checkpoint
	stage = Catalog.definition(str(recording.stage_id))
	_present_start()
	mode = "replay"
	replay_frames = Simulation.expand_recording_inputs(recording)
	replay_cursor = 0
	controls.show_play()
	_update_hud(sim.snapshot())
	running = true

func _replay_ended() -> void:
	running = false
	if collection_index >= 0:
		collection_index += 1
		if collection_index < journey.pairs().size(): _play_collection_pair()
		else: _show_ready()
	else:
		_show_review()

func _watch_collection() -> void:
	collection_index = 0
	_play_collection_pair()

func _play_collection_pair() -> void:
	var pairs: Array = journey.pairs()
	if collection_index < 0 or collection_index >= pairs.size():
		_show_error("That saved stage is not available. Its recordings have been kept.")
		return
	var pair: Dictionary = pairs[collection_index]
	_start_replay(pair.b, pair.a, pairs.slice(0, collection_index))

func _show_collection() -> void:
	var pairs: Array = journey.pairs()
	if not pairs.is_empty():
		var last: Dictionary = pairs[-1]
		var prefix: Array = pairs.slice(0, pairs.size() - 1)
		sim = Simulation.new()
		if not sim.resume_recording(last.b, last.a, prefix):
			_show_error(str(sim.error))
			return
		checkpoint = Simulation.checkpoint_from_pairs(prefix).checkpoint
		stage = Catalog.definition(str(last.b.stage_id))
		_present_start()
	mode = "collection"
	var finished: bool = journey.chapter_complete()
	var card := _card("The lighthouse remembers you." if finished else "Your light is safely kept.", "You can revisit every contribution together." if finished else "%d of %d stages are saved. Revisit those memories, then return to the next checkpoint." % [pairs.size(), Journey.TOTAL_STAGES])
	if not pairs.is_empty(): card.add_child(controls.button("Watch the saved chapter", _watch_collection))
	if not pairs.is_empty(): card.add_child(controls.button("Revisit a checkpoint", _choose_checkpoint))
	card.add_child(controls.button("Back to the journey", _leave))

func _choose_checkpoint() -> void:
	mode = "choose_checkpoint"
	var card := _card("Where shall we begin again?", "Your current attempt will be preserved before you re-record a checkpoint.")
	for index in range(journey.pairs().size()):
		var definition: Dictionary = Catalog.definition(Catalog.STAGE_IDS[index])
		card.add_child(controls.button("%d  ·  %s" % [index + 1, definition.title], func(): _confirm_checkpoint(index)))
	card.add_child(controls.button("Keep the current journey", _show_ready))

func _confirm_checkpoint(index: int) -> void:
	mode = "confirm_checkpoint"
	var card := _card("Leave a different path?", "Stages before this checkpoint stay as they are. This contribution and its later turns will be kept in an earlier attempt on this device, then this checkpoint starts again.")
	card.add_child(controls.button("Start a new attempt here", func():
		if journey.fork_from_stage(index):
			_show_ready()
		else:
			mode = "fork_error"
			var problem := _card("Your current journey is kept.", journey.last_error)
			problem.add_child(controls.button("Keep the current journey", _show_ready))
	))
	card.add_child(controls.button("Keep the current journey", _show_ready))

func _pause() -> void:
	if mode == "moment":
		_continue_final_moment()
		return
	if not running: return
	var previous := mode
	if previous == "play" and not _save_draft(): return
	mode = "paused"
	var card := _card("Take your time.", "Your checkpoint and rehearsal stay on this device.")
	if previous == "play":
		card.add_child(controls.button("Continue recording", _start_play))
		card.add_child(controls.button("Restart this turn", _begin))
	else:
		card.add_child(controls.button("Continue replay", func(): mode = "replay"; controls.show_play(); running = true))
	card.add_child(controls.button("Back to the journey", _leave))

func _show_error(text: String) -> void:
	mode = "error"
	var card := _card("Your saved journey is kept.", text)
	card.add_child(controls.button("Back to the journey", _leave))

func _show_save_problem(text: String, after_retry: String) -> void:
	mode = "save_error"
	var card := _card("This moment is still here.", text + "\n\nThe latest interval is still on this screen. Retry saving before leaving to keep it.")
	card.add_child(controls.button("Retry saving", func():
		if after_retry == "commit": _accept()
		elif _save_draft(after_retry):
			if after_retry == "review" or sim.finished:
				review = sim.export_recording()
				_show_review()
			else: _start_play()
	))
	card.add_child(controls.button("Leave without the unsaved interval", _leave))

func _leave() -> void:
	get_tree().change_scene_to_file("res://main.tscn")

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE and mode == "play": action_pressed = true
		elif event.physical_keycode == KEY_ESCAPE:
			_pause() if running or mode == "moment" else _leave()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		backgrounded = true
		if is_instance_valid(soundscape): soundscape.set_backgrounded(true)
		if is_instance_valid(controls) and running: _pause()
	elif what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]:
		backgrounded = false
		if is_instance_valid(soundscape): soundscape.set_backgrounded(false)
	elif what in [NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_WM_CLOSE_REQUEST]:
		if is_instance_valid(controls):
			_pause() if running or mode == "moment" else _leave()

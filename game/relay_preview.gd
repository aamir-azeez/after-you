extends Node3D
const PlayerCopy = preload("res://presentation/player_copy.gd")
## The same chapter presentation can use local practice or a retained online owner.
signal closed

const Registry = preload("res://services/chapter_registry.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Simulation = preload("res://core/v2/simulation_v2.gd")
const Journey = preload("res://services/relay_journey.gd")
const World = preload("res://presentation/relay_world.gd")
const Controls = preload("res://presentation/chapter_controls.gd")
const RefreshClock = preload("res://services/refresh_schedule.gd")
const Joystick = preload("res://presentation/joystick.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const LegacySave = preload("res://services/local_save.gd")
const Soundscape = preload("res://services/soundscape.gd")
const ReactionPhotos = preload("res://presentation/reaction_photo_flow.gd")
const ReactionStrip = preload("res://presentation/reaction_photo_strip.gd")
const SafetyScreen = preload("res://presentation/safety_screen.gd")
const PresenceBadge = preload("res://presentation/friend_presence_badge.gd")
const CREAM := Color("eceddb")
const MINT := Color("a6d9c4")
const MUTED := Color("afc7bd")

@export var chapter_key := Registry.RELAY
var chapter: Dictionary = {}
var _simulation: Script = Simulation
var journey: RefCounted = Journey.new()
var online_session: RefCounted
var friend_presence: Node
var presence_hud: Label
var _safety_screen: CanvasLayer
var _safety_photos: Array = []
var online_refresh_queued := false
var online_request_generation := 0
var reaction_photos_enabled := ReactionPhotos.FEATURE_ENABLED
var reaction_photos: Node
var reaction_strip: Control
var clipboard_copy: Callable = _copy_with_display_server
var definition: Dictionary = Catalog.relay_isles()
var sim: RefCounted = Simulation.new()
var world: Node3D
var soundscape: Node
var controls: CanvasLayer
var ui: Control
var refresh_schedule := RefreshClock.new()
var online_sync_status: Label
var online_last_checked_ms := -1
var hud: Control
var overlay: Control
var stick: Control
var action_button: Button
var finish_button: Button
var timer_label: Label
var chapter_label: Label
var hint_label: Label
var review: Dictionary = {}
var replay_frames: Array = []
var replay_cursor := 0
var replay_pair_index := -1
var running := false
var mode := "ready"
var action_pressed := false
var stage: Dictionary = {}
var checkpoint: Dictionary = {}
var prior: Dictionary = {}
var role := "a"
var settings: Dictionary = {}
var save_photo_prompt_preference: Callable
var turn_notification_status: Callable
var enable_turn_notifications: Callable
var notification_hint: Label
var notification_offer: Button
var completion_remaining := 0.0
var backgrounded := false
var _leaving := false
var title_font: Font
var modal_shade: ColorRect


func _ready() -> void:
	if settings.is_empty():
		var old_save := LegacySave.new()
		old_save.load_data()
		settings = old_save.data.settings.duplicate(true)
	if online_session != null:
		journey = online_session.coordinator
		chapter_key = journey.chapter_key()
	chapter = Registry.descriptor(chapter_key)
	if chapter.is_empty():
		_build_ui()
		_show_error(PlayerCopy.RELAY_PREVIEW_7D6EECC5B2C3)
		return
	definition = Registry.definition(chapter_key)
	_simulation = Registry.simulation_script(chapter_key)
	sim = _simulation.new()
	if online_session == null:
		if journey == null or journey.chapter_key() != chapter_key:
			journey = Journey.new("", null, chapter_key)
		journey.load_data()
	soundscape = Soundscape.new()
	soundscape.configure(settings)
	add_child(soundscape)
	world = Registry.world_script(chapter_key).new()
	add_child(world)
	world.footstep.connect(func():
		if running and mode in ["play", "replay"]: soundscape.play_footstep())
	world.reduced_motion = bool(settings.get("reduced_motion", false))
	world.load_level(definition)
	_build_ui()
	world.configure_camera_exploration(_camera_exploration_active, _camera_exploration_allowed)
	world.camera_exploration.frame_applied.connect(_position_replay_photos)
	if online_session != null and reaction_photos_enabled:
		reaction_photos = ReactionPhotos.new()
		reaction_photos.configure(self, online_session)
		reaction_photos.prompts_enabled = _photo_prompts_enabled
		reaction_photos.save_prompt_preference = _save_photo_prompts
		add_child(reaction_photos)
		reaction_strip = ReactionStrip.new()
		reaction_strip.configure(online_session)
		reaction_strip.report_requested.connect(_report_partner_photo)
		reaction_strip.edit_requested.connect(_edit_replay_photo)
		hud.add_child(reaction_strip)
		reaction_strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_resize)
	_resize()
	get_tree().auto_accept_quit = false
	_show_ready()


func _build_ui() -> void:
	controls=Controls.new()
	controls.settings=settings.duplicate(true)
	add_child(controls)
	ui=controls.ui
	hud=controls.hud
	overlay=controls.overlay
	stick=controls.stick
	action_button=controls.action_button
	finish_button=controls.finish_button
	timer_label=controls.timer_label
	chapter_label=controls.chapter_label
	hint_label=controls.hint_label
	title_font=controls.title_font
	controls.pause_requested.connect(_pause)
	controls.action_requested.connect(_request_action)
	controls.finish_requested.connect(_finish)
	if is_instance_valid(friend_presence) and online_session != null:
		presence_hud = _presence_badge()
		hud.add_child(presence_hud)
		presence_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		presence_hud.offset_left = -270
		presence_hud.offset_right = -36
		presence_hud.offset_top = 88
		presence_hud.offset_bottom = 112
		presence_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _photo_prompts_enabled() -> bool:
	return bool(settings.get("photo_prompts", true))

func _save_photo_prompts(enabled: bool) -> bool:
	if not save_photo_prompt_preference.is_valid() or save_photo_prompt_preference.call(enabled) != true:
		return false
	settings.photo_prompts = enabled
	return true


func _anchor_rect(control: Control, preset: int, rect: Rect2) -> void:
	# Set offsets, not absolute positions, after the control has a parent.
	control.set_anchors_and_offsets_preset(preset)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y


func _resize() -> void:
	if is_instance_valid(controls): controls._resize()


func _resize_shade() -> void:
	if is_instance_valid(controls): controls._resize_shade()


func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(16)
	style.set_border_width_all(1)
	style.border_color = Color("54766a")
	return style


func _label(text: String, size: int = 20) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _action_button(action_id: String, callback: Callable) -> Button:
	return controls.button_for(action_id, callback)


func _button(text: String, callback: Callable, primary: bool=true) -> Button:
	return controls.button(text,callback,primary)


func _card(title: String, body: String) -> VBoxContainer:
	if is_instance_valid(reaction_strip) and mode == "replay": _safety_photos = reaction_strip.report_targets()
	running=false
	action_pressed=false
	var card: VBoxContainer=controls.card(title,body)
	if is_instance_valid(friend_presence) and online_session != null: card.add_child(_presence_badge())
	modal_shade=controls.modal_shade
	return card

func _presence_badge() -> Label:
	var badge := PresenceBadge.new()
	badge.configure(friend_presence, "v2", str(journey.snapshot().get("room_id", "")))
	return badge


func _show_ready() -> void:
	_clear_reaction_view()
	mode = "ready"
	replay_pair_index = -1
	if journey.read_only:
		_show_error(journey.last_error)
		return
	if online_session != null and not journey.pending().is_empty():
		_show_online_waiting()
		return
	if journey.chapter_complete():
		_show_completed()
		return
	if online_session != null and not journey.my_turn():
		_show_online_waiting()
		return
	checkpoint = journey.checkpoint()
	prior = journey.prior_recording()
	role = journey.role()
	for item: Dictionary in definition.stages:
		if str(item.id) == journey.stage_id():
			stage = item
	if not _reset_live():
		return
	world.show_stage(stage)
	world.present(sim.snapshot(), true)
	var second_stage := int(checkpoint.stage_index) == 1
	var body := PlayerCopy.RELAY_PREVIEW_2B224F3B19B0 if not second_stage else PlayerCopy.RELAY_PREVIEW_5BED71BD3E00
	if chapter_key == Registry.FIRST_STEPS:
		body = PlayerCopy.RELAY_PREVIEW_9A01DAC077E3 if not second_stage else PlayerCopy.RELAY_PREVIEW_4238BDD23E08
	body += PlayerCopy.from_canonical(str(stage["hint_" + role])) + (PlayerCopy.RELAY_PREVIEW_441E8D9C7D61 if online_session != null else PlayerCopy.RELAY_PREVIEW_DC436BB6F967)
	if online_session != null and not online_session.invitation_code().is_empty():
		body += "\n\nInvitation: " + online_session.invitation_code()
	var card := _card("%d / 2  ·  %s" % [int(checkpoint.stage_index) + 1, "Leave a path" if role == "a" else "Follow the recording"], body)
	_add_invitation_copy(card)
	if not journey.draft().is_empty():
		card.add_child(_action_button("resume", _resume_draft))
	card.add_child(_action_button("record", _begin))
	if online_session != null:
		card.add_child(_action_button("refresh", _online_refresh))
	_add_recent_photo_action(card)
	card.add_child(_action_button("back", _leave))


func _show_online_waiting() -> void:
	mode = "online_waiting"
	var room: Dictionary = journey.snapshot()
	var pending: Dictionary = journey.pending()
	if not room.is_empty() and room.stage_index < 2:
		var display_sim: RefCounted = _simulation.new()
		var first: Dictionary = room.recording_a if room.recording_a is Dictionary else {}
		if display_sim.reset(definition,room.stage_id,room.checkpoint,first,room.active_role):
			world.show_stage(_simulation.stage_by_id(definition,room.stage_id))
			world.present(display_sim.snapshot(),true)
	var message := PlayerCopy.RELAY_PREVIEW_06FE980C1040
	if not pending.is_empty():
		message = PlayerCopy.RELAY_PREVIEW_53416F9C53E3
	elif room.is_empty():
		message = PlayerCopy.RELAY_PREVIEW_17179ABFBE5C
	if not journey.last_error.is_empty():
		message += "\n\n" + journey.last_error
	if not online_session.mutations_enabled():
		message += PlayerCopy.RELAY_PREVIEW_F8EBEB9FEF49
	if not online_session.invitation_code().is_empty():
		message += "\n\nInvitation: " + online_session.invitation_code()
	var card := _card(PlayerCopy.RELAY_PREVIEW_F429902DFA23, message)
	_add_invitation_copy(card)
	card.add_child(_action_button("check_saved" if not pending.is_empty() else "refresh", _online_refresh))
	_add_online_sync_status(card)
	if pending.is_empty(): _add_notification_offer(card)
	if not pending.is_empty() and pending.get("held", false):
		card.add_child(_button(PlayerCopy.RELAY_PREVIEW_D4FF2D8D4CDF, func():
			if journey.archive_held_submission():
				_online_refresh()
			else:
				_show_online_waiting()))
	if not _pairs().is_empty():
		card.add_child(_action_button("replays", func(): replay_pair_index = 0; _play_collection_pair()))
	_add_recent_photo_action(card)
	card.add_child(_action_button("back", _leave))


func _add_recent_photo_action(card: VBoxContainer) -> void:
	_add_safety_action(card)
	if not is_instance_valid(reaction_photos) or not journey.pending().is_empty():
		return
	var receipt: Dictionary = journey.last_receipt()
	if receipt.get("operation") != "turns":
		return
	# Keep a receipt-backed way back to an unfinished optional photo even before
	# the partner completes this stage and its combined replay becomes available.
	card.add_child(_button("Photo for your last contribution", func(): reaction_photos.offer(receipt, _show_ready)))

func _add_invitation_copy(card: VBoxContainer) -> void:
	if online_session == null or online_session.invitation_code().is_empty():
		return
	var status := _label("",17)
	status.name = "RelayCopyStatus"
	card.add_child(_button("Copy invitation code",func(): _copy_invitation(status)))
	card.add_child(status)

func _copy_invitation(status: Label) -> void:
	var code: String = online_session.invitation_code() if online_session != null else ""
	if code.is_empty() or not clipboard_copy.is_valid() or clipboard_copy.call(code) != true:
		status.text = PlayerCopy.RELAY_PREVIEW_6D5192F38DBE
		return
	status.text = PlayerCopy.RELAY_PREVIEW_87AB91E6F763

static func _copy_with_display_server(code: String) -> bool:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		return false
	DisplayServer.clipboard_set(code)
	return DisplayServer.clipboard_get() == code


func _online_refresh() -> void:
	if online_session == null or online_session.busy() or running:
		return
	var now := Time.get_ticks_msec()
	refresh_schedule.bind(_online_refresh_context(), now)
	refresh_schedule.request_now(now)
	var ticket := refresh_schedule.begin_if_due(now, not backgrounded, online_session.busy())
	if ticket.is_empty():
		_update_online_sync_status(now)
		return
	mode = "online_request"
	online_request_generation += 1
	var generation := online_request_generation
	_card(PlayerCopy.RELAY_PREVIEW_E274B279C9CF, PlayerCopy.RELAY_PREVIEW_AE8554BD7C76)
	# The active room is already bound. Do not download every room and the
	# capability catalogue before checking this one contribution.
	var reconciling: bool = not journey.pending().is_empty()
	if reconciling:
		await journey.reconcile()
	else:
		await journey.refresh()
	var result: Dictionary = {} if reconciling else journey.last_refresh_result()
	refresh_schedule.complete(ticket, Time.get_ticks_msec(), journey.last_error.is_empty(), int(result.get("retry_after_ms", 0)), bool(result.get("terminal", false)))
	if is_inside_tree() and generation == online_request_generation:
		online_last_checked_ms = Time.get_ticks_msec() if journey.last_error.is_empty() else online_last_checked_ms
		_show_ready()

func _online_refresh_context() -> String:
	return str(journey.get_instance_id()) + ":" + str(online_session.last_room())

func _add_online_sync_status(card: VBoxContainer) -> void:
	online_sync_status = _label(PlayerCopy.RELAY_PREVIEW_7A4E91C6BB33, 16)
	online_sync_status.name = "RoomSyncStatus"
	card.add_child(online_sync_status)
	_update_online_sync_status(Time.get_ticks_msec())

func _update_online_sync_status(now: int) -> void:
	if not is_instance_valid(online_sync_status): return
	if refresh_schedule.stopped() and journey.last_refresh_result().get("terminal", false):
		online_sync_status.text = PlayerCopy.RELAY_PREVIEW_9D001B9A783F
	elif refresh_schedule.busy():
		online_sync_status.text = PlayerCopy.RELAY_PREVIEW_8E35E137EA15
	elif not journey.last_error.is_empty():
		online_sync_status.text = PlayerCopy.RELAY_PREVIEW_EF61644814DA % maxi(1, ceili(float(refresh_schedule.next_due_ms() - now) / 1000.0))
	elif online_last_checked_ms >= 0:
		online_sync_status.text = PlayerCopy.RELAY_PREVIEW_F85672E29DEB
	else:
		online_sync_status.text = PlayerCopy.RELAY_PREVIEW_AE39B1E4A9F7

func _service_online_refresh() -> void:
	if online_session==null or backgrounded or running or not is_inside_tree(): return
	if mode not in ["ready","online_waiting","complete"] or is_instance_valid(_safety_screen): return
	if is_instance_valid(reaction_photos) and reaction_photos.active: return
	var now := Time.get_ticks_msec()
	var context := _online_refresh_context()
	refresh_schedule.bind(context,now)
	_update_online_sync_status(now)
	if online_refresh_queued:
		refresh_schedule.request_now(now)
		online_refresh_queued=false
	elif mode=="ready":
		# Poll while waiting for a friend, rather than competing with Begin.
		return
	var ticket: Dictionary=refresh_schedule.begin_if_due(now,true,online_session.busy())
	if ticket.is_empty(): return
	var generation := online_request_generation
	var before: Dictionary=journey.snapshot()
	# Deliberately GET-only: reconcile() may retry a POST. A timer must never
	# resend an uncertain gameplay contribution or optional photo request.
	var succeeded: bool=await journey.refresh()
	if succeeded: online_last_checked_ms = Time.get_ticks_msec()
	var refresh_result: Dictionary=journey.last_refresh_result()
	refresh_schedule.complete(ticket,Time.get_ticks_msec(),succeeded,int(refresh_result.get("retry_after_ms",0)),bool(refresh_result.get("terminal",false)))
	if not is_inside_tree() or generation!=online_request_generation: return
	if backgrounded or running or mode not in ["ready","online_waiting","complete"]: return
	if succeeded and before!=journey.snapshot(): _show_ready()


func identity_invalidated() -> void:
	online_request_generation += 1
	_clear_reaction_view()
	if is_instance_valid(reaction_photos):
		reaction_photos.invalidate()
	running = false
	if is_instance_valid(ui):
		_show_error(PlayerCopy.RELAY_PREVIEW_34409DD3D3AA)


func _pairs() -> Array:
	return online_session.chapter_pairs() if online_session != null else journey.pairs()


func _begin() -> void:
	if not _reset_live():
		return
	review = {}
	replay_pair_index = -1
	world.present(sim.snapshot(), true)
	_start_play()


func _reset_live() -> bool:
	var live: RefCounted = journey.create_live_simulation()
	if live == null:
		_show_error(journey.last_error)
		return false
	sim = live
	sim.catch_assistance = bool(settings.get("assistance", true))
	return true


func _start_play() -> void:
	mode = "play"
	overlay.visible = false
	hud.visible = true
	running = true
	_update_hud(sim.snapshot())


func _resume_draft() -> void:
	var draft: Dictionary = journey.draft()
	if not _reset_live():
		return
	sim.catch_assistance = bool(draft.get("catch_assistance", true))
	for input: Dictionary in _simulation.expand_recording_inputs(draft):
		sim.step(input)
	world.present(sim.snapshot(), true)
	if sim.finished:
		review = draft
		_show_review()
	else:
		_start_play()


func _physics_process(_delta: float) -> void:
	if not running or backgrounded:
		return
	var input: Dictionary
	if mode == "replay":
		if replay_cursor >= replay_frames.size():
			_replay_ended()
			return
		input = replay_frames[replay_cursor]
		replay_cursor += 1
	else:
		var move: Vector2 = stick.value
		var keyboard := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
		if keyboard.length() > 0:
			move = keyboard.limit_length()
		var right: Vector3 = world.camera.global_basis.x
		var forward: Vector3 = world.camera.global_basis.z
		var direction := (Vector3(right.x, 0, right.z).normalized() * move.x + Vector3(forward.x, 0, forward.z).normalized() * move.y).limit_length()
		input = {"move_x": direction.x, "move_z": direction.z, "interact": action_pressed}
		action_pressed = false
	advance_input(input)


func advance_input(input: Dictionary) -> void:
	# Both touch/keyboard input and input-driven QA use this single tick path.
	var state: Dictionary = sim.step(input)
	var sounds: Array = []
	for event: String in state.get("events", []):
		if event.begins_with("bridge_opened:"):
			sounds.append("bridge_opened")
		elif event == "relay_filled":
			sounds.append("garden_opened")
		elif event == "garden_bloomed":
			sounds.append("island_bloomed")
		else:
			sounds.append(event)
	soundscape.consume_events(sounds, mode == "play")
	world.present(state)
	_update_hud(state)
	if mode == "play" and int(state.tick) % 30 == 0 and not _persist_draft():
		return
	if state.finished:
		if mode == "replay":
			_replay_ended()
		else:
			_finish()


func _update_hud(state: Dictionary) -> void:
	var title := "%s · %d / 2 · %s" % [chapter.title, int(checkpoint.stage_index)+1,"Replay" if mode=="replay" else "Your first turn" if role=="a" else "Alongside a ghost"]
	controls.update_state(title,(600-int(state.tick))/30.0,state,mode=="play")

func _request_action() -> void:
	if running and not backgrounded and mode=="play" and sim.context_action().get("enabled",false):
		action_pressed=true


func _persist_draft(after_retry: String = "play") -> bool:
	if sim.tick == 0:
		return true
	if journey.save_live_draft(sim):
		return true
	_show_save_problem(journey.last_error, after_retry)
	return false


func _finish() -> void:
	review = sim.export_recording()
	if review.is_empty():
		_show_ready()
		return
	if not _persist_draft("review"):
		return
	running = false
	if sim.snapshot().get("complete", false):
		mode = "bloom"
		completion_remaining = 1.6
		hint_label.text = PlayerCopy.RELAY_PREVIEW_AFC92040F3DB
		stick.release()
		stick.visible = false
		action_button.visible = false
		finish_button.visible = false
	else:
		_show_review()


func _show_review() -> void:
	mode = "review"
	var verified: Dictionary = _simulation.verify_recording(definition, review, checkpoint, prior)
	var can_save := bool(verified.get("valid", false)) and bool(verified.get("snapshot", {}).get("can_commit", false))
	var explanation := PlayerCopy.RELAY_PREVIEW_B9074234FC11
	if not can_save:
		explanation += "\n\n" + PlayerCopy.from_canonical(str(verified.get("snapshot", {}).get("commit_reason", verified.get("error", PlayerCopy.RELAY_PREVIEW_9DDEE52F0B85))))
	var card := _card(PlayerCopy.RELAY_PREVIEW_93772D9A4DA5, explanation)
	card.add_child(_action_button("preview", _preview_turn))
	var save := _action_button("save", _accept)
	save.disabled = not can_save or (online_session != null and (not online_session.mutations_enabled() or online_session.busy()))
	card.add_child(save)
	if online_session != null and not online_session.mutations_enabled():
		card.add_child(_label(PlayerCopy.RELAY_PREVIEW_FAF7DFD92132,17))
	card.add_child(_action_button("retry", _begin))
	card.add_child(_action_button("leave_draft", _leave))


func _accept() -> void:
	if online_session != null:
		if online_session.busy() or not online_session.mutations_enabled() or not journey.pending().is_empty():
			_show_online_waiting()
			return
		mode = "online_request"
		online_request_generation += 1
		var generation := online_request_generation
		_card("Saving your contribution…", PlayerCopy.RELAY_PREVIEW_D30D1660A268)
		var accepted: bool = await journey.commit(review)
		if not is_inside_tree() or generation != online_request_generation:
			return
		if not accepted:
			_show_online_waiting()
			return
		if is_instance_valid(reaction_photos):
			# Only a validated server acknowledgement reaches this optional card.
			# Native Use and even a failed photo request never recommit the turn.
			reaction_photos.offer(journey.last_receipt(), _after_accept, true)
			return
	elif not journey.accept_recording(review):
		_show_save_problem(journey.last_error, "commit")
		return
	_after_accept()


func _after_accept() -> void:
	if role == "b" and not journey.chapter_complete():
		mode = "checkpoint"
		var card := _card(chapter.checkpoint_title, chapter.checkpoint_text)
		card.add_child(_action_button("continue", _show_ready))
		card.add_child(_action_button("back", _leave))
	else:
		_show_ready()


func _preview_turn() -> void:
	_start_replay(review, checkpoint, prior)


func _start_replay(recording: Dictionary, start: Dictionary, source: Dictionary) -> void:
	_clear_reaction_view()
	if not sim.reset(definition, str(recording.stage_id), start, source, str(recording.role)):
		_show_error(sim.error)
		return
	sim.catch_assistance = bool(recording.get("catch_assistance", true))
	checkpoint = start
	for item: Dictionary in definition.stages:
		if str(item.id) == str(recording.stage_id):
			world.show_stage(item)
	mode = "replay"
	replay_frames = _simulation.expand_recording_inputs(recording)
	replay_cursor = 0
	overlay.visible = false
	hud.visible = true
	world.present(sim.snapshot(), true)
	_update_hud(sim.snapshot())
	running = true


func _replay_ended() -> void:
	running = false
	if replay_pair_index >= 0:
		replay_pair_index += 1
		if replay_pair_index < _pairs().size():
			_play_collection_pair()
		else:
			_show_ready() if online_session != null and not journey.chapter_complete() else _show_completed()
	else:
		_show_review()


func _play_collection_pair() -> void:
	var pairs: Array = _pairs()
	if replay_pair_index < 0 or replay_pair_index >= pairs.size():
		_show_error(PlayerCopy.RELAY_PREVIEW_3DB2A54BEB93)
		return
	var start: Dictionary = Registry.initial_checkpoint(chapter_key)
	for index in range(replay_pair_index):
		var derived: Dictionary = _simulation.derive_checkpoint(definition, start, pairs[index].a, pairs[index].b)
		if not derived.get("valid", false):
			_show_error(str(derived.get("error", PlayerCopy.RELAY_PREVIEW_ED3A094D0041)))
			return
		start = derived.checkpoint
	var pair: Dictionary = pairs[replay_pair_index]
	_start_replay(pair.b, start, pair.a)
	_load_replay_photos()


func _load_replay_photos() -> void:
	if not is_instance_valid(reaction_strip) or mode != "replay":
		return
	var pairs: Array = _pairs()
	if replay_pair_index >= 0 and replay_pair_index < pairs.size():
		reaction_strip.show_turns(online_session.replay_photo_turns(replay_pair_index, pairs[replay_pair_index]))


func _position_replay_photos() -> void:
	if not is_instance_valid(reaction_strip):
		return
	if mode != "replay" or backgrounded or not is_instance_valid(world) or not is_instance_valid(controls):
		reaction_strip.hide()
		return
	reaction_strip.show()
	var to_local := reaction_strip.get_global_transform_with_canvas().affine_inverse()
	var exclusions: Array[Rect2] = []
	for control: Control in [stick, action_button, finish_button, timer_label, chapter_label, hint_label, controls.pause_button, controls.objective_panel, controls.turn_progress, presence_hud]:
		if is_instance_valid(control) and control.is_visible_in_tree():
			var transform := to_local * control.get_global_transform_with_canvas()
			exclusions.append(transform * Rect2(Vector2.ZERO, control.size))
	reaction_strip.position_over_spirits(world.camera, world.actors, Rect2(Vector2.ZERO, reaction_strip.size), exclusions)


func _edit_replay_photo(reference: Dictionary) -> void:
	if replay_pair_index < 0 or mode not in ["replay", "paused"] or not is_instance_valid(reaction_photos):
		return
	_clear_reaction_view()
	# _card pauses presentation only. This replay engine is never saved as draft.
	reaction_photos.open_owned(reference, _resume_replay)

func _resume_replay() -> void:
	mode = "replay"
	overlay.visible = false
	hud.visible = true
	running = true
	_load_replay_photos()

func _add_replay_photo_action(card: VBoxContainer) -> void:
	if online_session == null or not is_instance_valid(reaction_photos): return
	var pairs: Array = _pairs()
	if replay_pair_index < 0 or replay_pair_index >= pairs.size(): return
	for reference: Dictionary in online_session.replay_photo_turns(replay_pair_index, pairs[replay_pair_index]):
		if reference.get("own", false):
			card.add_child(_button("Add or edit your photo", func(): _edit_replay_photo(reference)))


func _clear_reaction_view() -> void:
	if is_instance_valid(reaction_strip):
		reaction_strip.clear()


func _show_completed() -> void:
	_clear_reaction_view()
	# A reopened chapter has no live simulation yet. Rebuild its final scene from
	# the verified recording chain before presenting the completion card.
	var pairs: Array = _pairs()
	if not pairs.is_empty():
		var start: Dictionary = Registry.initial_checkpoint(chapter_key)
		for pair: Dictionary in pairs:
			if not sim.reset(definition, str(pair.b.stage_id), start, pair.a, "b"):
				_show_error(sim.error)
				return
			sim.catch_assistance = bool(pair.b.catch_assistance)
			for input: Dictionary in _simulation.expand_recording_inputs(pair.b):
				sim.step(input)
			var derived: Dictionary = _simulation.derive_checkpoint(definition, start, pair.a, pair.b)
			if not derived.get("valid", false):
				_show_error(str(derived.get("error", PlayerCopy.RELAY_PREVIEW_DA6BA2478FE5)))
				return
			start = derived.checkpoint
		world.show_stage(definition.stages[-1])
		world.present(sim.snapshot(), true)
	mode = "complete"
	var card := _card(PlayerCopy.RELAY_PREVIEW_8D42D9E99BAF, str(chapter.completion_text) + "\n\n" + (PlayerCopy.RELAY_PREVIEW_FF18C2378950 if online_session != null else PlayerCopy.RELAY_PREVIEW_7DECA1CF83C7))
	card.add_child(_action_button("replays", func(): replay_pair_index = 0; _play_collection_pair()))
	_add_recent_photo_action(card)
	_add_safety_action(card)
	card.add_child(_action_button("back", _leave))


func _pause() -> void:
	if mode == "play" and not _persist_draft():
		return
	var previous := mode
	if is_instance_valid(reaction_strip): _safety_photos = reaction_strip.report_targets()
	mode = "paused"
	var card := _card("Take your time.", PlayerCopy.RELAY_PREVIEW_50922961D853)
	if previous == "play":
		card.add_child(_action_button("resume", _start_play))
		card.add_child(_action_button("retry", _begin))
	elif previous == "replay":
		card.add_child(_action_button("resume", _resume_replay))
		_add_replay_photo_action(card)
	else:
		card.add_child(_action_button("continue", _show_ready))
	_add_safety_action(card)
	card.add_child(_action_button("back", _leave))


func _show_error(message: String) -> void:
	mode = "error"
	var card := _card(PlayerCopy.LIGHTHOUSE_PREVIEW_CE5202BED332, message)
	card.add_child(_action_button("back", _leave))


func _show_save_problem(message: String, after_retry: String) -> void:
	# Keep the live simulation/draft in memory. A transient full disk or I/O
	# failure is recoverable here without discarding the latest contribution.
	mode = "save_error"
	var card := _card(PlayerCopy.LIGHTHOUSE_PREVIEW_DC7EDE5D9A53, message + PlayerCopy.RELAY_PREVIEW_761D2317CF80)
	card.add_child(_action_button("retry_save", func():
		if after_retry == "commit":
			_accept()
		elif _persist_draft(after_retry):
			if after_retry == "review" or sim.finished:
				review = sim.export_recording()
				_show_review()
			else:
				_start_play()
	))
	card.add_child(_action_button("leave_unsaved", _leave))


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	running = false
	action_pressed = false
	mode = "leaving"
	online_request_generation += 1
	if is_instance_valid(stick): stick.release()
	if online_session != null:
		# The parent retains the session, including any durable pending request.
		# Leaving the presentation must not wait for a room/photo GET or discard
		# a contribution whose acknowledgement is still in flight.
		if is_instance_valid(reaction_photos):
			reaction_photos.invalidate()
		_clear_reaction_view()
		closed.emit()
	else:
		get_tree().change_scene_to_file("res://main.tscn")


func _exit_tree() -> void:
	if is_instance_valid(_safety_screen): _safety_screen.client.invalidate()
	_clear_reaction_view()
	if is_instance_valid(reaction_photos):
		reaction_photos.invalidate()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE and mode == "play":
			_request_action()
		elif event.physical_keycode == KEY_ESCAPE:
			_pause() if running else _leave()


func _process(delta: float) -> void:
	_service_online_refresh()
	_position_replay_photos()
	if mode == "bloom" and not backgrounded:
		completion_remaining -= delta
		if completion_remaining <= 0:
			_show_review()


func _notification(what: int) -> void:
	if is_instance_valid(_safety_screen) and what in [NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_WM_CLOSE_REQUEST]: return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		backgrounded = true
		if is_instance_valid(soundscape):
			soundscape.set_backgrounded(true)
		if is_instance_valid(stick) and running:
			_pause()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		var was_backgrounded := backgrounded
		backgrounded = false
		if online_session != null and was_backgrounded:
			online_refresh_queued = true
		if is_instance_valid(soundscape):
			soundscape.set_backgrounded(false)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_instance_valid(stick):
			_pause() if running else _leave()


func _add_notification_offer(card: VBoxContainer) -> void:
	if not turn_notification_status.is_valid() or not enable_turn_notifications.is_valid(): return
	notification_hint = _label("", 16)
	notification_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(notification_hint)
	notification_offer = _button(PlayerCopy.MAIN_C4B947AAAE59, func(): enable_turn_notifications.call(); update_notification_offer())
	card.add_child(notification_offer)
	update_notification_offer()

func update_notification_offer() -> void:
	if not turn_notification_status.is_valid(): return
	var state: Dictionary = turn_notification_status.call()
	if is_instance_valid(notification_hint): notification_hint.text = str(state.get("message", ""))
	if is_instance_valid(notification_offer):
		notification_offer.visible = not state.get("registered", false)
		notification_offer.disabled = state.get("busy", false)

func notification_room_hint(room_id: String) -> void:
	if online_session != null and online_session.last_room() == room_id:
		online_refresh_queued = true

func notification_deferred(message: String) -> void:
	# A small note on the existing pause/wait card never replaces its controls,
	# recording cursor, photo selection or saved rehearsal.
	if running or not is_instance_valid(controls) or not is_instance_valid(controls.modal_stack): return
	if controls.modal_stack.has_node("NotificationDeferredHint"): return
	var note := _label(message, 16)
	note.name = "NotificationDeferredHint"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.modal_stack.add_child(note)

func _add_safety_action(card: VBoxContainer) -> void:
	if card.has_meta("safety_action_added"): return
	if online_session != null and online_session.has_method("safety_context") and not online_session.safety_context().is_empty():
		card.set_meta("safety_action_added", true)
		card.add_child(_button("Report or block player", _open_safety))

func _report_partner_photo(reference: Dictionary) -> void:
	_safety_photos = [reference.photo.duplicate(true)]
	_open_safety()

func _open_safety() -> void:
	if online_session == null or is_instance_valid(_safety_screen): return
	if mode == "play" and not _persist_draft(): return
	var context: Dictionary = online_session.safety_context()
	if context.is_empty(): return
	context["photos"] = _safety_photos.duplicate(true)
	running = false
	mode = "safety"
	_clear_reaction_view()
	controls.visible = false
	_safety_screen = SafetyScreen.new(online_session.safety_client(), context, _close_safety, _blocked_safety)
	add_child(_safety_screen)

func _close_safety() -> void:
	_safety_screen = null
	controls.visible = true
	_show_ready()

func _blocked_safety() -> void:
	_safety_screen = null
	running = false
	_clear_reaction_view()
	if is_instance_valid(reaction_photos): reaction_photos.invalidate()
	closed.emit()

func _camera_exploration_active() -> bool:
	return not backgrounded and mode in ["play", "replay", "bloom"] and controls.visible and not controls.overlay.visible

func _camera_exploration_allowed(point: Vector2) -> bool:
	return not world.CameraExploration.ui_blocks(controls, point)

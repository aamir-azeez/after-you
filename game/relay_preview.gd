extends Node3D
## The same chapter presentation can use local practice or a retained online owner.
signal closed

const Catalog = preload("res://core/v2/stage_catalog.gd")
const Simulation = preload("res://core/v2/simulation_v2.gd")
const Journey = preload("res://services/relay_journey.gd")
const World = preload("res://presentation/relay_world.gd")
const Joystick = preload("res://presentation/joystick.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const LegacySave = preload("res://services/local_save.gd")
const Soundscape = preload("res://services/soundscape.gd")
const CREAM := Color("eceddb")
const MINT := Color("a6d9c4")
const MUTED := Color("afc7bd")

var journey: RefCounted = Journey.new()
var online_session: RefCounted
var online_refresh_queued := false
var online_request_generation := 0
var clipboard_copy: Callable = _copy_with_display_server
var definition: Dictionary = Catalog.relay_isles()
var sim := Simulation.new()
var world: Node3D
var soundscape: Node
var ui: Control
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
var completion_remaining := 0.0
var backgrounded := false
var title_font: Font
var modal_shade: ColorRect


func _ready() -> void:
	if settings.is_empty():
		var old_save := LegacySave.new()
		old_save.load_data()
		settings = old_save.data.settings.duplicate(true)
	if online_session == null:
		journey.load_data()
	else:
		journey = online_session.coordinator
	soundscape = Soundscape.new()
	soundscape.configure(settings)
	add_child(soundscape)
	world = World.new()
	add_child(world)
	world.reduced_motion = bool(settings.get("reduced_motion", false))
	world.load_level(definition)
	_build_ui()
	get_viewport().size_changed.connect(_resize)
	_resize()
	get_tree().auto_accept_quit = false
	_show_ready()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	var theme := Theme.new()
	var body := FontVariation.new()
	body.base_font = preload("res://assets/fonts/nunito.ttf")
	body.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	theme.default_font = body
	var heading := FontVariation.new()
	heading.base_font = preload("res://assets/fonts/fredoka.ttf")
	heading.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	title_font = heading
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", CREAM)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var color := Color("254b45") if state == "normal" else Color("426b5e")
		if state == "disabled":
			color = Color("203e38")
		theme.set_stylebox(state, "Button", _style(color))
		theme.set_color("font_" + state + "_color", "Button", CREAM)
	theme.set_color("font_color", "Button", CREAM)
	ui.theme = theme
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	chapter_label = _label("THE RELAY ISLES", 26)
	chapter_label.add_theme_font_override("font", title_font)
	chapter_label.position = Vector2(28, 20)
	hud.add_child(chapter_label)
	timer_label = _label("20.0", 25)
	timer_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	timer_label.position = Vector2(-28, 24)
	hud.add_child(timer_label)
	var pause := _button("Pause", _pause)
	pause.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause.position = Vector2(-135, 20)
	pause.size = Vector2(110, 50)
	hud.add_child(pause)
	hint_label = _label("", 21)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position = Vector2(-340, -94)
	hint_label.size = Vector2(680, 78)
	hud.add_child(hint_label)
	stick = Joystick.new()
	stick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stick.position = Vector2(28, -198)
	stick.size = Vector2(152, 152)
	hud.add_child(stick)
	action_button = _button("Throw seed", func(): action_pressed = true)
	action_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	action_button.position = Vector2(-240, -178)
	action_button.size = Vector2(210, 64)
	hud.add_child(action_button)
	finish_button = _button("Finish recording", _finish)
	finish_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	finish_button.position = Vector2(-240, -100)
	finish_button.size = Vector2(210, 54)
	hud.add_child(finish_button)
	if settings.get("left_handed", false):
		_anchor_rect(stick, Control.PRESET_BOTTOM_RIGHT, Rect2(-180, -198, 152, 152))
		_anchor_rect(action_button, Control.PRESET_BOTTOM_LEFT, Rect2(28, -178, 210, 64))
		_anchor_rect(finish_button, Control.PRESET_BOTTOM_LEFT, Rect2(28, -100, 210, 54))
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(overlay)


func _anchor_rect(control: Control, preset: int, rect: Rect2) -> void:
	# Set offsets, not absolute positions, after the control has a parent.
	control.set_anchors_and_offsets_preset(preset)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y


func _resize() -> void:
	if not is_instance_valid(ui):
		return
	var viewport := get_viewport().get_visible_rect()
	var safe := viewport
	if OS.has_feature("android"):
		safe = SafeArea.viewport_rect(Rect2(DisplayServer.get_display_safe_area()), get_viewport().get_screen_transform(), viewport)
	ui.offset_left = safe.position.x - viewport.position.x
	ui.offset_top = safe.position.y - viewport.position.y
	ui.offset_right = safe.end.x - viewport.end.x
	ui.offset_bottom = safe.end.y - viewport.end.y
	_resize_shade()


func _resize_shade() -> void:
	# Controls respect display cutouts; the dimming backdrop covers the whole
	# world, including those insets. Otherwise a bright side strip remains.
	if not is_instance_valid(modal_shade):
		return
	modal_shade.offset_left = -ui.offset_left
	modal_shade.offset_top = -ui.offset_top
	modal_shade.offset_right = -ui.offset_right
	modal_shade.offset_bottom = -ui.offset_bottom


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


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 50
	button.pressed.connect(callback)
	return button


func _card(title: String, body: String) -> VBoxContainer:
	running = false
	action_pressed = false
	stick.release()
	hud.visible = false
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	overlay.visible = true
	modal_shade = ColorRect.new()
	modal_shade.color = Color(0.025, 0.10, 0.10, 0.73)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(modal_shade)
	_resize_shade()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 610
	panel.add_theme_stylebox_override("panel", _style(Color("163c36")))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for edge: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	margin.add_child(stack)
	var heading_label := _label(title, 32)
	heading_label.add_theme_font_override("font", title_font)
	stack.add_child(heading_label)
	var paragraph := _label(body, 20)
	paragraph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	paragraph.custom_minimum_size.x = 566
	paragraph.add_theme_color_override("font_color", MUTED)
	stack.add_child(paragraph)
	return stack


func _show_ready() -> void:
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
	var body := "Three islands. Two keepers. One seed that remembers the way.\n\n" if not second_stage else "The relay kept your seed safe. Now the receiver leads, and the other keeper follows both bridges.\n\n"
	body += str(stage["hint_" + role]) + ("\n\nYour friend returns later. Rehearsals stay on this device until you save a contribution to the room." if online_session != null else "\n\nSolo chapter preview · progress is saved on this device.")
	if online_session != null and not online_session.invitation_code().is_empty():
		body += "\n\nInvitation: " + online_session.invitation_code()
	var card := _card("%d / 2  ·  %s" % [int(checkpoint.stage_index) + 1, "Leave a path" if role == "a" else "Follow the recording"], body)
	_add_invitation_copy(card)
	if not journey.draft().is_empty():
		card.add_child(_button("Resume rehearsal", _resume_draft))
	card.add_child(_button("Record this turn", _begin))
	if online_session != null:
		card.add_child(_button("Refresh room", _online_refresh))
	card.add_child(_button("Back to the journey", _leave))


func _show_online_waiting() -> void:
	mode = "online_waiting"
	var room: Dictionary = journey.snapshot()
	var pending: Dictionary = journey.pending()
	if not room.is_empty() and room.stage_index < 2:
		var display_sim := Simulation.new()
		var first: Dictionary = room.recording_a if room.recording_a is Dictionary else {}
		if display_sim.reset(definition,room.stage_id,room.checkpoint,first,room.active_role):
			world.show_stage(Simulation.stage_by_id(definition,room.stage_id))
			world.present(display_sim.snapshot(),true)
	var message := "Your friend has the next contribution. Return whenever you are ready."
	if not pending.is_empty():
		message = "Your exact contribution is saved on this device. Check its receipt before recording another turn."
	elif room.is_empty():
		message = "The room could not be loaded. Your local rehearsal is kept."
	if not journey.last_error.is_empty():
		message += "\n\n" + journey.last_error
	if not online_session.mutations_enabled():
		message += "\n\nNew submissions are currently paused; existing receipts can still be checked."
	if not online_session.invitation_code().is_empty():
		message += "\n\nInvitation: " + online_session.invitation_code()
	var card := _card("A shared place, at your own pace.", message)
	_add_invitation_copy(card)
	card.add_child(_button("Check saved submission" if not pending.is_empty() else "Refresh room", _online_refresh))
	if not pending.is_empty() and pending.get("held", false):
		card.add_child(_button("Keep rejected turn in held rehearsals", func():
			if journey.archive_held_submission():
				_online_refresh()
			else:
				_show_online_waiting()))
	if not _pairs().is_empty():
		card.add_child(_button("Watch completed stages", func(): replay_pair_index = 0; _play_collection_pair()))
	card.add_child(_button("Back to rooms", _leave))

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
		status.text = "Could not copy. Use the invitation shown above, or refresh the room."
		return
	status.text = "Invitation code copied. Send it to your friend."

static func _copy_with_display_server(code: String) -> bool:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		return false
	DisplayServer.clipboard_set(code)
	return DisplayServer.clipboard_get() == code


func _online_refresh() -> void:
	if online_session == null or online_session.busy() or running:
		return
	mode = "online_request"
	online_request_generation += 1
	var generation := online_request_generation
	_card("Checking your shared place…", "Your saved contribution stays safe while its receipt is checked.")
	await online_session.load_lobby()
	if not is_inside_tree() or generation != online_request_generation:
		return
	if not journey.pending().is_empty():
		await journey.reconcile()
	else:
		await journey.refresh()
	if is_inside_tree() and generation == online_request_generation:
		_show_ready()


func identity_invalidated() -> void:
	online_request_generation += 1
	running = false
	if is_instance_valid(ui):
		_show_error("Your identity changed. Return to the account screen before reopening this room. Saved requests stay with their original identity.")


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
	for input: Dictionary in Simulation.expand_recording_inputs(draft):
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
	chapter_label.text = "THE RELAY ISLES\n%d / 2  ·  %s" % [int(checkpoint.stage_index) + 1, "Replay" if mode == "replay" else ("Leave a path" if role == "a" else "Follow your ghost")]
	timer_label.text = "%.1f" % ((600 - int(state.tick)) / 30.0)
	hint_label.text = str(state.get("message", ""))
	var context: Dictionary = state.get("context_action", {})
	action_button.text = str(context.get("label", "Interact"))
	action_button.disabled = not bool(context.get("enabled", false))
	finish_button.disabled = not bool(state.get("can_commit", false))
	stick.visible = mode == "play"
	action_button.visible = mode == "play"
	finish_button.visible = mode == "play"


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
		stick.release()
		stick.visible = false
		action_button.visible = false
		finish_button.visible = false
	else:
		_show_review()


func _show_review() -> void:
	mode = "review"
	var verified: Dictionary = Simulation.verify_recording(definition, review, checkpoint, prior)
	var can_save := bool(verified.get("valid", false)) and bool(verified.get("snapshot", {}).get("can_commit", false))
	var explanation := "Preview your recording before saving it. Your last checkpoint stays safe if you try again."
	if not can_save:
		explanation += "\n\n" + str(verified.get("snapshot", {}).get("commit_reason", verified.get("error", "Try this turn again to complete your contribution.")))
	var card := _card("A moment, ready to keep.", explanation)
	card.add_child(_button("Preview this turn", _preview_turn))
	var save := _button("Save this contribution", _accept)
	save.disabled = not can_save or (online_session != null and (not online_session.mutations_enabled() or online_session.busy()))
	card.add_child(save)
	if online_session != null and not online_session.mutations_enabled():
		card.add_child(_label("Online submissions are paused. Your rehearsal stays here.",17))
	card.add_child(_button("Try this turn again", _begin))
	card.add_child(_button("Leave and keep the draft", _leave))


func _accept() -> void:
	if online_session != null:
		if online_session.busy() or not online_session.mutations_enabled() or not journey.pending().is_empty():
			_show_online_waiting()
			return
		mode = "online_request"
		online_request_generation += 1
		var generation := online_request_generation
		_card("Saving your contribution…", "The request is kept on this device before it is sent. Your friend can return after the room confirms it.")
		var accepted: bool = await journey.commit(review)
		if not is_inside_tree() or generation != online_request_generation:
			return
		if not accepted:
			_show_online_waiting()
			return
	elif not journey.accept_recording(review):
		_show_save_problem(journey.last_error, "commit")
		return
	if role == "b" and not journey.chapter_complete():
		mode = "checkpoint"
		var card := _card("A little light, safely kept.", "The relay remembers your seed and the first bridge stays open. You can leave here and return later.\n\nNext: swap spirits and carry the light to the far island.")
		card.add_child(_button("Continue from the relay", _show_ready))
		card.add_child(_button("Back to the journey", _leave))
	else:
		_show_ready()


func _preview_turn() -> void:
	_start_replay(review, checkpoint, prior)


func _start_replay(recording: Dictionary, start: Dictionary, source: Dictionary) -> void:
	if not sim.reset(definition, str(recording.stage_id), start, source, str(recording.role)):
		_show_error(sim.error)
		return
	sim.catch_assistance = bool(recording.get("catch_assistance", true))
	checkpoint = start
	for item: Dictionary in definition.stages:
		if str(item.id) == str(recording.stage_id):
			world.show_stage(item)
	mode = "replay"
	replay_frames = Simulation.expand_recording_inputs(recording)
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
		_show_error("That saved stage is unavailable. Your recordings are kept.")
		return
	var start: Dictionary = Catalog.initial_checkpoint(definition)
	for index in range(replay_pair_index):
		var derived: Dictionary = Simulation.derive_checkpoint(definition, start, pairs[index].a, pairs[index].b)
		if not derived.get("valid", false):
			_show_error(str(derived.get("error", "The earlier stage could not be replayed.")))
			return
		start = derived.checkpoint
	var pair: Dictionary = pairs[replay_pair_index]
	_start_replay(pair.b, start, pair.a)


func _show_completed() -> void:
	# A reopened chapter has no live simulation yet. Rebuild its final scene from
	# the verified recording chain before presenting the completion card.
	var pairs: Array = _pairs()
	if not pairs.is_empty():
		var start: Dictionary = Catalog.initial_checkpoint(definition)
		for pair: Dictionary in pairs:
			if not sim.reset(definition, str(pair.b.stage_id), start, pair.a, "b"):
				_show_error(sim.error)
				return
			sim.catch_assistance = bool(pair.b.catch_assistance)
			for input: Dictionary in Simulation.expand_recording_inputs(pair.b):
				sim.step(input)
			var derived: Dictionary = Simulation.derive_checkpoint(definition, start, pair.a, pair.b)
			if not derived.get("valid", false):
				_show_error(str(derived.get("error", "The chapter could not be replayed.")))
				return
			start = derived.checkpoint
		world.show_stage(definition.stages[-1])
		world.present(sim.snapshot(), true)
	mode = "complete"
	var card := _card("You left a path. I carried it on.", "Three islands are awake. Your two saved stages can now play together as one memory.\n\n" + ("Your shared chapter is confirmed in the room." if online_session != null else "This solo preview is the beginning of the larger journey."))
	card.add_child(_button("Watch the whole chapter", func(): replay_pair_index = 0; _play_collection_pair()))
	card.add_child(_button("Back to the journey", _leave))


func _pause() -> void:
	if mode == "play" and not _persist_draft():
		return
	var previous := mode
	mode = "paused"
	var card := _card("Take your time.", "Your saved checkpoint and rehearsal stay on this device.")
	if previous == "play":
		card.add_child(_button("Continue recording", _start_play))
		card.add_child(_button("Restart this turn", _begin))
	elif previous == "replay":
		card.add_child(_button("Continue replay", func(): mode = "replay"; overlay.visible = false; hud.visible = true; running = true))
	else:
		card.add_child(_button("Continue", _show_ready))
	card.add_child(_button("Back to the journey", _leave))


func _show_error(message: String) -> void:
	mode = "error"
	var card := _card("Your saved journey is kept.", message)
	card.add_child(_button("Back to the journey", _leave))


func _show_save_problem(message: String, after_retry: String) -> void:
	# Keep the live simulation/draft in memory. A transient full disk or I/O
	# failure is recoverable here without discarding the latest contribution.
	mode = "save_error"
	var card := _card("This moment is still here.", message + "\n\nThe latest recording is kept on this screen. Retry saving before leaving to keep it.")
	card.add_child(_button("Retry saving", func():
		if after_retry == "commit":
			_accept()
		elif _persist_draft(after_retry):
			if after_retry == "review" or sim.finished:
				review = sim.export_recording()
				_show_review()
			else:
				_start_play()
	))
	card.add_child(_button("Leave without the unsaved interval", _leave))


func _leave() -> void:
	if online_session != null:
		if online_session.busy():
			return
		online_request_generation += 1
		closed.emit()
	else:
		get_tree().change_scene_to_file("res://main.tscn")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE and mode == "play":
			action_pressed = true
		elif event.physical_keycode == KEY_ESCAPE:
			_pause() if running else _leave()


func _process(delta: float) -> void:
	if online_refresh_queued and online_session != null and not backgrounded and mode in ["ready", "online_waiting", "complete"] and not online_session.busy():
		online_refresh_queued = false
		_online_refresh()
	if mode == "bloom" and not backgrounded:
		completion_remaining -= delta
		if completion_remaining <= 0:
			_show_review()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		backgrounded = true
		if is_instance_valid(soundscape):
			soundscape.set_backgrounded(true)
		if is_instance_valid(stick) and running:
			_pause()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		backgrounded = false
		if online_session != null:
			online_refresh_queued = true
		if is_instance_valid(soundscape):
			soundscape.set_backgrounded(false)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_instance_valid(stick):
			_pause() if running else _leave()

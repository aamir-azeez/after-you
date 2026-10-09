extends Node3D
const PlayerCopy = preload("res://presentation/player_copy.gd")
## The same chapter presentation can use local practice or a retained online owner.
signal closed

const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Simulation = preload("res://core/v2/simulation_v2.gd")
const Journey = preload("res://services/relay_journey.gd")
const World = preload("res://presentation/relay_world.gd")
const Controls = preload("res://presentation/chapter_controls.gd")
const RefreshClock = preload("res://services/refresh_schedule.gd")
const Joystick = preload("res://presentation/joystick.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const LegacySave = preload("res://services/local_save.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const Soundscape = preload("res://services/soundscape.gd")
const ReactionPhotos = preload("res://presentation/reaction_photo_flow.gd")
const ReactionStrip = preload("res://presentation/reaction_photo_strip.gd")
const SafetyScreen = preload("res://presentation/safety_screen.gd")
const RedoClient = preload("res://services/redo_client.gd")
const RedoScreen = preload("res://presentation/redo_screen.gd")
const PresenceBadge = preload("res://presentation/friend_presence_badge.gd")
const StoryCamera = preload("res://presentation/story_camera.gd")
const RoomReadyPanel = preload("res://presentation/room_ready_panel.gd")
const COPY_ICON = preload("res://assets/ui/social/copy.svg")
const SHARE_ICON = preload("res://assets/ui/social/share-network.svg")
const REFRESH_ICON = preload("res://assets/ui/social/arrows-clockwise.svg")
const USERS_ICON = preload("res://assets/ui/social/users.svg")
const CREAM := Color("eceddb")
const MINT := Color("a6d9c4")
const MUTED := Color("afc7bd")
const COMPLETION_DURATION := 3.0
const SOLO_REPLAY_CONTEXT_PATH := "user://solo-replay-playback.json"
const SOLO_REPLAY_CONTEXT_MAX_BYTES := 2097152

@export var chapter_key := Registry.RELAY
var chapter: Dictionary = {}
var _simulation: Script = Simulation
var journey: RefCounted = Journey.new()
var online_session: RefCounted
var friend_presence: Node
var presence_hud: Label
var _safety_screen: CanvasLayer
var _redo_screen: CanvasLayer
var _safety_photos: Array = []
var online_refresh_queued := false
var online_request_generation := 0
var _suspended_manual_refresh: Dictionary = {}
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
var _replay_context: Dictionary = {}
var _continue_replay_context := false
var replay_pair_index := -1
var _replay_collection: Array = []
var _solo_replay_only := false
var _solo_replay_context_error := false
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
var share_current_room: Callable
var _sharing_room := false
var _room_ready_panel: Control
var _room_camera: Dictionary = {}
var _ready_turn_buttons: Array[Button] = []
var notification_hint: Label
var notification_offer: Button
var completion_remaining := 0.0
var _completion_is_replay := false
var backgrounded := false
var _retry_cancel: Callable
var _leaving := false
var title_font: Font
var modal_shade: ColorRect
var story_flow: Node
var story_chapter_index := -1
var campaign_card_state: Callable
var campaign_card_action: Callable
var campaign_control_refresh: Callable
var campaign_refresh_ready: Callable
var campaign_redo_client: Callable
var _story_hold := -1
var _story_overlay_was_visible := false
var _story_badges: Array[Dictionary] = []
var _story_context_lost := false
var _story_last_release := -1
var _campaign_actions: VBoxContainer
var _story_camera := StoryCamera.new()


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
	var injected := consume_solo_replay_context(SOLO_REPLAY_CONTEXT_PATH, chapter_key, definition, _simulation)
	if injected.get("status") == "error":
		_solo_replay_context_error = true
	elif injected.get("status") == "consumed":
		_solo_replay_only = true
		_replay_collection = injected.context.accepted_pairs.duplicate(true)
		replay_pair_index = int(injected.context.selected_stage_index)
	if online_session == null and not _solo_replay_only and not _solo_replay_context_error:
		if journey == null or journey.chapter_key() != chapter_key:
			journey = Journey.new("", null, chapter_key)
		journey.load_data()
	soundscape = Soundscape.new()
	soundscape.configure(settings)
	add_child(soundscape)
	world = Registry.world_script(chapter_key).new()
	add_child(world)
	GraphicsPolicy.apply(world, settings)
	world.footstep.connect(func():
		if running and mode in ["play", "replay"]: soundscape.play_footstep())
	world.reunion.connect(func():
		if running and mode in ["play", "replay"]: soundscape.play_reunion())
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
	if _solo_replay_context_error:
		_show_error(PlayerCopy.RELAY_PREVIEW_3DB2A54BEB93)
	elif _solo_replay_only:
		_play_collection_pair()
	else:
		_show_ready()


static func consume_solo_replay_context(path: String, expected_chapter: String, level: Dictionary, simulation_script: Script) -> Dictionary:
	if not FileAccess.file_exists(path): return {"status": "none"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"status": "error"}
	if file.get_length() < 1 or file.get_length() > SOLO_REPLAY_CONTEXT_MAX_BYTES:
		file.close()
		return {"status": "error"}
	var raw := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(raw) != OK or not parser.data is Dictionary: return {"status": "error"}
	var context: Dictionary = parser.data
	if context.get("schema_version") != 1 or context.get("chapter_key") != expected_chapter:
		return {"status": "error"}
	var stage_index: Variant = context.get("selected_stage_index")
	var pairs: Variant = context.get("accepted_pairs")
	var visibility_key: Variant = context.get("visibility_key")
	if not (stage_index is int or stage_index is float) or not is_finite(float(stage_index)) or float(stage_index) != floor(float(stage_index)):
		return {"status": "error"}
	if not visibility_key is String or str(visibility_key).is_empty() or str(visibility_key).length() > 512:
		return {"status": "error"}
	if not pairs is Array or pairs.size() != int(stage_index) + 1 or pairs.size() > level.get("stages", []).size() or pairs.is_empty():
		return {"status": "error"}
	var checkpoint: Dictionary = Registry.initial_checkpoint(expected_chapter)
	if checkpoint.is_empty(): return {"status": "error"}
	for index in range(pairs.size()):
		var pair: Variant = pairs[index]
		if not pair is Dictionary or pair.size() != 2 or not pair.get("a") is Dictionary or not pair.get("b") is Dictionary:
			return {"status": "error"}
		var expected_stage := str(level.stages[index].get("id", level.stages[index].get("stage_id", "")))
		if expected_stage.is_empty() or pair.a.get("role") != "a" or pair.b.get("role") != "b" or pair.a.get("stage_id") != expected_stage or pair.b.get("stage_id") != expected_stage:
			return {"status": "error"}
		var derived: Dictionary = simulation_script.derive_checkpoint(level, checkpoint, pair.a, pair.b)
		if not derived.get("valid", false) or not derived.get("checkpoint") is Dictionary:
			return {"status": "error"}
		checkpoint = derived.checkpoint
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if remove_error != OK: return {"status": "error"}
	return {"status": "consumed", "context": context.duplicate(true)}


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
	if not is_inside_tree(): return
	if is_instance_valid(controls): controls._resize()
	if is_instance_valid(_room_ready_panel) and mode == "ready":
		if ui.size.x < 880 or _room_ready_panel.short_layout != (ui.size.y < 640): _show_ready.call_deferred()
		else: _frame_ready_world.call_deferred()


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
	_restore_ready_world()
	_room_ready_panel = null
	_campaign_actions = null
	_ready_turn_buttons.clear()
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
	_restore_ready_world()
	if _story_context_lost:
		_show_error(PlayerCopy.RELAY_PREVIEW_17179ABFBE5C)
		return
	_clear_reaction_view()
	_replay_collection = []
	if _campaign_recovery_only():
		if not journey.read_only and journey.chapter_complete() and journey.pending().is_empty(): _show_completed()
		else: _show_campaign_recovery()
		return
	mode = "ready"
	replay_pair_index = -1
	if journey.read_only:
		_show_error(journey.last_error)
		return
	if online_session != null and not journey.pending().is_empty():
		_show_online_waiting()
		return
	if _ordinary_redo_available():
		var redo: RefCounted = online_session.redo_client()
		if not redo.busy: redo.bind_room("relay",journey.snapshot())
		if redo.pending().get("action") == "accept":
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
	world.present(sim.snapshot(), true)
	var second_stage := int(checkpoint.stage_index) == 1
	var body := PlayerCopy.RELAY_PREVIEW_2B224F3B19B0 if not second_stage else PlayerCopy.RELAY_PREVIEW_5BED71BD3E00
	if chapter_key == Registry.FIRST_STEPS:
		body = PlayerCopy.RELAY_PREVIEW_9A01DAC077E3 if not second_stage else PlayerCopy.RELAY_PREVIEW_4238BDD23E08
	elif Registry.is_cooperative(chapter_key):
		body = ""
	body += PlayerCopy.from_canonical(str(Registry.stage_presentation(chapter_key,stage)["hint_" + role])) + (PlayerCopy.RELAY_PREVIEW_441E8D9C7D61 if online_session != null else PlayerCopy.RELAY_PREVIEW_DC436BB6F967)
	if online_session != null and not online_session.invitation_code().is_empty():
		body += "\n\nInvitation: " + online_session.invitation_code()
	var title := "%d / 2  ·  %s" % [int(checkpoint.stage_index) + 1, "Leave a path" if role == "a" else "Follow the recording"]
	var compact: bool = online_session != null and not journey.campaign_scoped() and not is_instance_valid(story_flow) and ui.size.x >= 880
	var card := _ordinary_room_card(title,body) if compact else _card(title,body)
	_add_invitation_copy(card)
	if compact:
		card.add_child(HSeparator.new())
	if not journey.draft().is_empty():
		var resume := _action_button("resume", _resume_draft)
		_ready_turn_buttons.append(resume)
		card.add_child(resume)
	var record := _action_button("record", _begin)
	if compact: record.custom_minimum_size.y = 54 if _room_ready_panel.short_layout else 64
	_ready_turn_buttons.append(record)
	card.add_child(record)
	if online_session != null:
		var refresh := _action_button("refresh", _online_refresh)
		if compact:
			_room_icon_button(refresh,REFRESH_ICON,"Refresh",true)
			_room_ready_panel.header.add_child(refresh)
		else: card.add_child(refresh)
	elif not journey.archived_attempts().is_empty():
		card.add_child(_action_button("replays", _show_local_replays))
	_add_local_restart(card)
	_add_redo_action(card)
	_add_recent_photo_action(card)
	_add_campaign_card_actions(card)
	if not compact: card.add_child(_action_button("back", _leave))
	_offer_story_arrival()

func _ordinary_room_card(title: String, body: String) -> VBoxContainer:
	_card("", "")
	# The ordinary card's deferred width constraints must not own this layout.
	controls.modal_scroll = null
	controls.modal_stack = null
	for child: Node in overlay.get_children():
		if child == controls.modal_shade: continue
		overlay.remove_child(child)
		child.queue_free()
	controls.modal_shade.color = Color(0.025,0.10,0.10,0.26)
	_room_ready_panel = RoomReadyPanel.new()
	overlay.add_child(_room_ready_panel)
	var hint := PlayerCopy.from_canonical(str(Registry.stage_presentation(chapter_key,stage)["hint_"+role]))
	var card: VBoxContainer = _room_ready_panel.build(str(chapter.title),title,hint,title_font,_leave,func():
		mode = "room_details"
		var details := _card(str(chapter.title),body)
		details.add_child(_action_button("back",_show_ready)))
	if is_instance_valid(friend_presence) and online_session != null: card.add_child(_presence_badge())
	_room_ready_panel.scene_space.resized.connect(_frame_ready_world.call_deferred)
	var camera: Camera3D = world.camera
	_room_camera = {"transform":camera.transform,"size":camera.size,"keep_aspect":camera.keep_aspect,"h_offset":camera.h_offset,"v_offset":camera.v_offset}
	world.set_process(false)
	_frame_ready_world.call_deferred()
	return card

func _frame_ready_world() -> void:
	if _room_camera.is_empty() or not is_instance_valid(_room_ready_panel) or mode != "ready" or _story_hold >= 0: return
	var target: Rect2 = _room_ready_panel.scene_space.get_global_rect()
	if target.size.x < 80 or target.size.y < 60: return
	var camera: Camera3D = world.camera
	camera.transform = _room_camera.transform
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.h_offset = _room_camera.h_offset
	camera.v_offset = _room_camera.v_offset
	var viewport := get_viewport().get_visible_rect()
	camera.size = float(_room_camera.size) * maxf(viewport.size.x / target.size.x * 0.82,viewport.size.y / target.size.y * 0.66)
	var shift := viewport.get_center() - target.get_center()
	var units: float = camera.size / viewport.size.y
	camera.global_position += camera.global_basis.x * shift.x * units - camera.global_basis.y * shift.y * units

func _restore_ready_world() -> void:
	if _room_camera.is_empty(): return
	if is_instance_valid(world) and is_instance_valid(world.camera):
		var camera: Camera3D = world.camera
		camera.transform = _room_camera.transform
		camera.size = _room_camera.size
		camera.keep_aspect = _room_camera.keep_aspect
		camera.h_offset = _room_camera.h_offset
		camera.v_offset = _room_camera.v_offset
	_room_camera.clear()

func _room_icon_button(button: Button, texture: Texture2D, accessible: String, icon_only: bool = false) -> void:
	button.icon = texture
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if icon_only else HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("icon_max_width",28)
	button.add_theme_color_override("icon_normal_color",CREAM)
	button.add_theme_color_override("icon_hover_color",Color("193d39"))
	button.tooltip_text = accessible
	button.accessibility_name = accessible
	if icon_only:
		button.text = ""
		button.custom_minimum_size = Vector2(48,48)
		button.size_flags_horizontal = Control.SIZE_SHRINK_END


func _show_online_waiting() -> void:
	mode = "online_waiting"
	var room: Dictionary = journey.snapshot()
	var pending: Dictionary = journey.pending()
	if not room.is_empty() and room.stage_index < 2:
		var display_sim: RefCounted = _simulation.new()
		var first: Dictionary = room.recording_a if room.recording_a is Dictionary else {}
		if display_sim.reset(definition,room.stage_id,room.checkpoint,first,room.active_role):
			_present_stage_history(_simulation.stage_by_id(definition,room.stage_id),room.checkpoint)
			var display: Dictionary = display_sim.snapshot()
			# The verified room identifies the viewer; the simulation still owns
			# the active player. This hint belongs only to this waiting preview.
			if room.get("player_slot") in ["p0", "p1"]: display["viewer_slot"] = room.player_slot
			world.present(display,true)
	var message := PlayerCopy.RELAY_PREVIEW_06FE980C1040
	if not pending.is_empty():
		message = PlayerCopy.SHARED_TURN_HELD_HINT if pending.get("held", false) else PlayerCopy.RELAY_PREVIEW_53416F9C53E3
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
	_add_redo_action(card)
	_add_recent_photo_action(card)
	_add_campaign_card_actions(card)
	card.add_child(_action_button("back", _leave))
	_offer_story_arrival()


func story_boundary_ready(allow_completed: bool = false) -> bool:
	if campaign_redo_client.is_valid():
		var client: RefCounted = campaign_redo_client.call()
		if client != null and client.held(): return false
	if _campaign_recovery_only() and not (allow_completed and journey.chapter_complete() and journey.pending().is_empty()): return false
	if online_session == null or backgrounded or running or _leaving or _story_context_lost: return false
	if (mode not in ["ready", "online_waiting"] and not (allow_completed and mode == "complete")) or journey.read_only or journey.busy(): return false
	if online_session.busy() or online_session.photo_request_busy() or not journey.pending().is_empty(): return false
	if (journey.chapter_complete() and not allow_completed) or is_instance_valid(_safety_screen): return false
	if is_instance_valid(reaction_photos) and reaction_photos.active: return false
	return not journey.snapshot().is_empty()

func hold_story(generation: int, allow_completed: bool = false) -> bool:
	if _story_hold >= 0 or not story_boundary_ready(allow_completed): return false
	if not _story_camera.begin(world,generation): return false
	_story_hold = generation
	_story_last_release = -1
	_story_overlay_was_visible = is_instance_valid(overlay) and overlay.visible
	if is_instance_valid(overlay): overlay.hide()
	for actor: Node in world.actors.values():
		for badge: Node in actor.get_children():
			# Every shipped spirit's direct Label3D child is its turn-role badge.
			# Lighthouse-derived worlds predate the replay metadata tag.
			if badge is Label3D:
				_story_badges.append({"reference":weakref(badge),"visible":badge.visible})
				badge.hide()
	action_pressed = false
	if is_instance_valid(stick): stick.release()
	return true

func frame_story_camera(generation: int, panel_rect: Rect2, safe_rect: Rect2 = Rect2()) -> bool:
	return generation == _story_hold and not _story_context_lost and _story_camera.frame(generation,panel_rect,mode == "complete",safe_rect)

func release_story(generation: int) -> void:
	if _story_hold != generation: return
	_story_camera.restore(generation)
	_story_hold = -1
	if not _story_context_lost and is_instance_valid(overlay):
		overlay.visible = _story_overlay_was_visible
	_story_overlay_was_visible = false
	for saved: Dictionary in _story_badges:
		var badge: Variant = saved.reference.get_ref()
		if is_instance_valid(badge): badge.visible = saved.visible
	_story_badges.clear()
	_story_last_release = generation
	if campaign_card_state.is_valid(): _refresh_released_campaign_card.call_deferred(generation)

func _refresh_released_campaign_card(generation: int) -> void:
	if generation != _story_last_release or _story_hold >= 0 or _story_context_lost or _leaving or not is_inside_tree() or not campaign_card_state.is_valid(): return
	# Only action widgets change: replaying a completed/ready world here would
	# overwrite the exact camera and exploration state restored above.
	refresh_campaign_actions()

func story_context_changed() -> void:
	_story_last_release = -1
	if _story_hold >= 0: _story_camera.restore(_story_hold)
	_story_context_lost = true
	online_request_generation += 1
	running = false
	action_pressed = false
	_show_error(PlayerCopy.RELAY_PREVIEW_17179ABFBE5C)

func _offer_story_arrival() -> void:
	if is_instance_valid(story_flow): story_flow.present_arrival(self, story_chapter_index)


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

func _ordinary_redo_available() -> bool:
	if online_session == null or journey == null or is_instance_valid(story_flow): return false
	return not journey.has_method("campaign_scoped") or not journey.campaign_scoped()

func _add_redo_action(card: VBoxContainer) -> void:
	if not _ordinary_redo_available() or not journey.pending().is_empty(): return
	var client: RefCounted = online_session.redo_client()
	if not client.busy: client.bind_room("relay",journey.snapshot())
	if not online_session.mutations_enabled() and client.pending().is_empty(): return
	var room: Dictionary = journey.snapshot()
	if RedoClient.source_for("relay",room).is_empty() and client.pending().is_empty(): return
	var label := "Redo requested" if client.can_accept() else "Ask for redo" if journey.my_turn() else "Turn requests"
	card.add_child(_button(label,_open_redo))

func _open_redo() -> void:
	if not _ordinary_redo_available() or online_session.busy() or running or backgrounded or _story_hold >= 0 or _story_context_lost or is_instance_valid(_redo_screen): return
	if mode not in ["ready", "online_waiting", "paused", "review"]: return
	var client: RefCounted = online_session.redo_client()
	if not client.bind_room("relay",journey.snapshot()): return
	var previous_mode := mode
	mode = "redo_requests"
	ui.visible = false
	_redo_screen = RedoScreen.new()
	_redo_screen.client = client
	_redo_screen.allow_mutations = online_session.mutations_enabled()
	_redo_screen.closed.connect(func():
		var accepted: bool = _redo_screen.accepted or client.accepted
		_redo_screen = null
		if _leaving or not is_inside_tree(): return
		ui.visible = true
		if accepted:
			# Reconcile the accepted fork before exposing any saved recording
			# controls. The old dependent draft stays durable until that succeeds.
			if not backgrounded and not online_session.busy(): _online_refresh()
			else:
				mode = "online_waiting"
				_show_online_waiting()
				online_refresh_queued = true
		elif previous_mode == "paused":
			_restore_paused_draft()
		elif previous_mode == "review":
			if client.pending().get("action") == "accept": _show_online_waiting()
			else: _show_review()
		else:
			_show_ready()
			if not backgrounded and not online_session.busy(): _online_refresh()
			else: online_refresh_queued = true)
	add_child(_redo_screen)

func _restore_paused_draft() -> void:
	if not _reset_live(true): return
	var draft: Dictionary = journey.draft()
	sim.catch_assistance = bool(draft.get("catch_assistance", true))
	for input: Dictionary in _simulation.expand_recording_inputs(draft):
		sim.step(input)
	world.present(sim.snapshot(), true)
	running = false
	mode = "paused"
	var card := _card("Take your time.", PlayerCopy.RELAY_PREVIEW_50922961D853)
	card.add_child(_action_button("resume", _start_play))
	card.add_child(_action_button("retry", _begin))
	_add_safety_action(card)
	_add_redo_action(card)
	card.add_child(_action_button("back", _leave))

func _refresh_redo() -> bool:
	if campaign_redo_client.is_valid() and not backgrounded and _story_hold < 0 and not _story_context_lost and journey.pending().is_empty():
		var campaign_client: RefCounted = campaign_redo_client.call()
		if campaign_client == null or campaign_client.busy or campaign_client.held() or not campaign_client.available(): return false
		var before: Dictionary = campaign_client.view()
		# The existing refresh cycle already verified parent and child. Add only
		# the advisory read on that cadence, never a separate timer.
		await campaign_client.refresh(false)
		return before != campaign_client.view()
	if not _ordinary_redo_available() or backgrounded or _story_hold >= 0 or _story_context_lost or not journey.pending().is_empty(): return false
	var client: RefCounted = online_session.redo_client()
	if client.busy: return false
	var before: Dictionary = client.view()
	var room: Dictionary = journey.snapshot()
	if RedoClient.source_for("relay",room).is_empty() and client.pending().is_empty(): return false
	if not client.bind_room("relay",room): return false
	await client.refresh()
	return before != client.view()

func _add_campaign_redo_action(card: VBoxContainer) -> void:
	if not campaign_redo_client.is_valid() or journey == null or not journey.pending().is_empty(): return
	var client: RefCounted = campaign_redo_client.call()
	if client == null or not client.available(): return
	var source := RedoClient.source_for("relay",journey.snapshot())
	if source.is_empty() and not client.held(): return
	var label := "Turn requests"
	if client.held(): label = "Recover turn request"
	elif client.can_accept(): label = "Redo requested"
	elif not source.is_empty() and source.second_player_id == client._context().get("owner"): label = "Request redo"
	card.add_child(_button(label,_open_campaign_redo))

func _open_campaign_redo() -> void:
	# Review is intentionally allowed only here, not at Story dialogue/Continue boundaries.
	if not campaign_redo_client.is_valid() or online_session == null or online_session.busy() or running or backgrounded or _leaving or _story_hold >= 0 or _story_context_lost or is_instance_valid(_redo_screen): return
	if not journey.pending().is_empty(): return
	var client: RefCounted = campaign_redo_client.call()
	if client == null or client.busy or not client.available(): return
	# A completed card can still own an unsettled receipt or obsolete intent.
	# Its visible recovery action must not grant new consent on completed play.
	if mode not in ["ready","online_waiting","review","campaign_recovery"] and not (mode == "complete" and journey.chapter_complete() and client.held()): return
	var previous_mode := mode
	var previous_room: Dictionary = journey.snapshot()
	var saved_journey: RefCounted = journey
	var generation := online_request_generation
	var context: Dictionary = client._context()
	mode = "redo_requests"
	ui.visible = false
	_redo_screen = RedoScreen.new()
	_redo_screen.client = client
	_redo_screen.allow_mutations = online_session.mutations_enabled()
	_redo_screen.closed.connect(func():
		_redo_screen = null
		if _leaving or not is_inside_tree() or generation != online_request_generation or journey != saved_journey or client._context() != context: return
		ui.visible = true
		if client.held() or client.busy: _show_campaign_recovery()
		elif previous_mode == "review" and journey.snapshot() == previous_room: _show_review()
		else: _show_ready())
	add_child(_redo_screen)

func _add_invitation_copy(card: VBoxContainer) -> void:
	if online_session == null or online_session.invitation_code().is_empty():
		return
	var compact := is_instance_valid(_room_ready_panel) and mode == "ready"
	var short_layout: bool = compact and _room_ready_panel.short_layout
	var friend_status := _label("Waiting for friend" if journey.snapshot().get("guest_id") == null else "Friend joined",(26 if short_layout else 30) if compact else 20)
	friend_status.name = "RoomFriendStatus"
	friend_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if compact: friend_status.add_theme_font_override("font",title_font)
	if compact:
		var status_row := HBoxContainer.new()
		status_row.add_theme_constant_override("separation",12 if short_layout else 16)
		card.add_child(status_row)
		var people := TextureRect.new()
		people.texture = USERS_ICON
		people.custom_minimum_size = Vector2(40,40) if short_layout else Vector2(48,48)
		people.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		people.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		people.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		people.self_modulate = CREAM
		status_row.add_child(people)
		friend_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		friend_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		status_row.add_child(friend_status)
	else: card.add_child(friend_status)
	var status := _label("",17)
	status.name = "RelayCopyStatus"
	status.visible = false
	status.minimum_size_changed.connect(func(): status.visible = not status.text.is_empty())
	var copy := _button("Copy invitation code",func(): _copy_invitation(status),false)
	if compact:
		card.add_child(_label("Invitation code",17))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",8)
		card.add_child(row)
		var code := LineEdit.new()
		code.text = online_session.invitation_code()
		code.editable = false
		code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code.custom_minimum_size.y = 50 if short_layout else 64
		code.add_theme_font_size_override("font_size",18 if short_layout else 20)
		code.add_theme_color_override("font_uneditable_color",CREAM)
		code.tooltip_text = "Invitation code"
		row.add_child(code)
		_room_icon_button(copy,COPY_ICON,"Copy invitation code",true)
		copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(copy)
	else: card.add_child(copy)
	card.add_child(status)
	if share_current_room.is_valid() and not journey.campaign_scoped() and not journey.campaign_recovery_only():
		var shared := _label("All friends",17)
		if compact: shared.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var share := _button("Share current room",func(): _share_room_from_card(card, shared),false)
		share.name = "ShareCurrentRoom"
		if compact: _room_icon_button(share,SHARE_ICON,"Share current room")
		share.disabled = _sharing_room or online_session.busy()
		card.add_child(share)
		if compact:
			preload("res://presentation/control_theme.gd").inset_button(share)
			share.custom_minimum_size.y = 54 if short_layout else 64
		card.add_child(shared)

func _share_room_from_card(card: VBoxContainer, status: Label) -> void:
	if _sharing_room or backgrounded or running or _leaving or _story_hold >= 0 or _story_context_lost or online_session == null or online_session.busy() or not share_current_room.is_valid() or not is_instance_valid(card) or not card.is_inside_tree(): return
	var target := {"api_version": 2, "room_id": journey.snapshot().get("room_id", "")}
	var source: RefCounted = journey
	var button: Button = card.get_node("ShareCurrentRoom")
	button.disabled = true
	_sharing_room = true
	var result: Dictionary = await share_current_room.call(target)
	_sharing_room = false
	if not is_inside_tree() or backgrounded or running or _leaving or source != journey or target.room_id != journey.snapshot().get("room_id") or not is_instance_valid(card) or not card.is_inside_tree() or result.get("ignored", false): return
	button.disabled = false
	status.text = str(result.get("message", "Friends unavailable"))

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
	if online_session == null or online_session.busy() or running or _story_hold >= 0 or _story_context_lost or not _campaign_refresh_ready():
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
	_suspended_manual_refresh.clear()
	_card(PlayerCopy.RELAY_PREVIEW_E274B279C9CF, PlayerCopy.RELAY_PREVIEW_AE8554BD7C76)
	var source: RefCounted = journey
	var context := _online_refresh_context()
	var saved_pending: Dictionary = journey.pending()
	var reconciling: bool = not saved_pending.is_empty()
	var control: Dictionary = await _refresh_campaign_control()
	if not control.current or not _online_refresh_is_current(generation,source,context,["online_request"]):
		refresh_schedule.complete(ticket,Time.get_ticks_msec(),false)
		_remember_suspended_manual_refresh(generation,source,context)
		return
	if not control.okay or saved_pending != journey.pending():
		refresh_schedule.complete(ticket,Time.get_ticks_msec(),false)
		_show_ready()
		return
	# The explicit action keeps the exact saved direction captured before the
	# control GET. It does not infer a new contribution or Continue request.
	if reconciling:
		await journey.reconcile()
	else:
		await journey.refresh()
	var result: Dictionary = {} if reconciling else journey.last_refresh_result()
	if journey.last_error.is_empty(): await _refresh_redo()
	refresh_schedule.complete(ticket, Time.get_ticks_msec(), journey.last_error.is_empty(), int(result.get("retry_after_ms", 0)), bool(result.get("terminal", false)))
	if _online_refresh_is_current(generation,source,context,["online_request"]):
		online_last_checked_ms = Time.get_ticks_msec() if journey.last_error.is_empty() else online_last_checked_ms
		_show_ready()
	else:
		_remember_suspended_manual_refresh(generation,source,context)

func _remember_suspended_manual_refresh(generation: int, source: RefCounted, context: String) -> void:
	if backgrounded and is_inside_tree() and mode == "online_request" and generation == online_request_generation and journey == source and online_session != null and context == _online_refresh_context() and not _leaving and not _story_context_lost:
		_suspended_manual_refresh = {"generation":generation,"context":context}

func _refresh_campaign_control() -> Dictionary:
	if not campaign_control_refresh.is_valid(): return {"current":true,"okay":true,"changed":false}
	var result: Variant = await campaign_control_refresh.call()
	if not result is Dictionary or not result.get("current") is bool or not result.get("okay") is bool or not result.get("changed") is bool:
		return {"current":false,"okay":false,"changed":false}
	return result

func _campaign_refresh_ready() -> bool:
	return not campaign_refresh_ready.is_valid() or campaign_refresh_ready.call() == true

func _online_refresh_is_current(generation: int, source: RefCounted, context: String, allowed_modes: Array) -> bool:
	return is_inside_tree() and generation == online_request_generation and journey == source and online_session != null and context == _online_refresh_context() and not backgrounded and not running and not _leaving and _story_hold < 0 and not _story_context_lost and mode in allowed_modes and not is_instance_valid(_safety_screen) and not (is_instance_valid(reaction_photos) and reaction_photos.active) and not online_session.photo_request_busy()

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
	if online_session==null or backgrounded or running or _sharing_room or _story_hold >= 0 or _story_context_lost or not is_inside_tree() or not _campaign_refresh_ready(): return
	# A manual read may finish while backgrounded. Rebuild its stable card only
	# after foreground returns, then leave all retry traffic on the GET-only path.
	if not _suspended_manual_refresh.is_empty():
		if online_session.busy() or journey.busy() or refresh_schedule.busy(): return
		var saved := _suspended_manual_refresh
		_suspended_manual_refresh = {}
		if saved.generation == online_request_generation and saved.context == _online_refresh_context() and mode == "online_request":
			_show_ready()
			online_refresh_queued = true
	if mode not in ["ready","online_waiting","complete"] or is_instance_valid(_safety_screen): return
	if is_instance_valid(reaction_photos) and reaction_photos.active: return
	var now := Time.get_ticks_msec()
	var context := _online_refresh_context()
	refresh_schedule.bind(context,now)
	_update_online_sync_status(now)
	if online_refresh_queued:
		refresh_schedule.request_now(now)
		online_refresh_queued=false
	elif mode=="ready" and journey.snapshot().get("guest_id") != null:
		# The existing GET scheduler observes a friend's arrival before Begin.
		# Once joined, ready cards and active play do not keep polling.
		return
	var ticket: Dictionary=refresh_schedule.begin_if_due(now,true,online_session.busy())
	if ticket.is_empty(): return
	var generation := online_request_generation
	var source: RefCounted = journey
	var saved_pending: Dictionary = journey.pending()
	var before: Dictionary=journey.snapshot()
	var before_my_turn: bool = journey.my_turn()
	refresh_campaign_actions()
	var control: Dictionary = await _refresh_campaign_control()
	if not control.current or not _online_refresh_is_current(generation,source,context,["ready","online_waiting","complete"]):
		refresh_schedule.complete(ticket,Time.get_ticks_msec(),false)
		return
	if not control.okay or saved_pending != journey.pending():
		refresh_schedule.complete(ticket,Time.get_ticks_msec(),false)
		if control.changed: _show_ready()
		else: refresh_campaign_actions()
		return
	# Deliberately GET-only: reconcile() may retry a POST. A timer must never
	# resend an uncertain gameplay contribution or optional photo request.
	var succeeded: bool=await journey.refresh()
	var redo_changed := await _refresh_redo() if succeeded else false
	if succeeded: online_last_checked_ms = Time.get_ticks_msec()
	var refresh_result: Dictionary=journey.last_refresh_result()
	refresh_schedule.complete(ticket,Time.get_ticks_msec(),succeeded,int(refresh_result.get("retry_after_ms",0)),bool(refresh_result.get("terminal",false)))
	if not _online_refresh_is_current(generation,source,context,["ready","online_waiting","complete"]): return
	if control.changed or before_my_turn != journey.my_turn() or succeeded and (before!=journey.snapshot() or redo_changed): _show_ready()
	else: refresh_campaign_actions()


func identity_invalidated() -> void:
	if is_instance_valid(story_flow): story_flow.invalidate()
	online_request_generation += 1
	if is_instance_valid(_redo_screen):
		_redo_screen.invalidate()
		_redo_screen = null
		ui.visible = true
	_clear_reaction_view()
	if is_instance_valid(reaction_photos):
		reaction_photos.invalidate()
	running = false
	if is_instance_valid(ui):
		_show_error(PlayerCopy.RELAY_PREVIEW_34409DD3D3AA)


func _pairs() -> Array:
	if online_session == null and not _replay_collection.is_empty(): return _replay_collection.duplicate(true)
	return online_session.chapter_pairs() if online_session != null else journey.pairs()


func _begin() -> void:
	if _campaign_recovery_only(): return
	if _story_hold >= 0 or _story_context_lost: return
	if online_session != null and online_session.busy(): return
	if not _reset_live():
		return
	review = {}
	replay_pair_index = -1
	world.present(sim.snapshot(), true)
	_start_play()


func _reset_live(resume_draft: bool = false) -> bool:
	if _ordinary_redo_available() and online_session.redo_client().pending().get("action") == "accept":
		_show_online_waiting()
		return false
	var live: RefCounted = journey.create_live_simulation(resume_draft)
	if live == null:
		_show_error(journey.last_error)
		return false
	sim = live
	sim.catch_assistance = bool(settings.get("assistance", true))
	_present_stage_history(_simulation.stage_by_id(definition,journey.stage_id()),journey.checkpoint())
	return true

func _present_stage_history(authored: Dictionary, verified_checkpoint: Dictionary) -> void:
	world.show_stage(authored)
	if world.has_method("present_history"): world.present_history(verified_checkpoint)


func _start_play() -> void:
	if _campaign_recovery_only(): return
	if _story_hold >= 0 or _story_context_lost: return
	_restore_ready_world()
	mode = "play"
	overlay.visible = false
	hud.visible = true
	running = true
	_update_hud(sim.snapshot())


func _resume_draft() -> void:
	if _campaign_recovery_only(): return
	if _story_hold >= 0 or _story_context_lost: return
	if online_session != null and online_session.busy(): return
	var draft: Dictionary = journey.draft()
	if not _reset_live(true):
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
		if not _replay_ready(): return
		if replay_cursor >= replay_frames.size():
			_finish_replay_playback()
			return
		input = replay_frames[replay_cursor]
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
	if _story_hold >= 0 or _story_context_lost: return
	if mode == "replay":
		if not _replay_ready() or replay_cursor >= replay_frames.size(): return
		input = replay_frames[replay_cursor]
	elif _campaign_recovery_only(): return
	# Both touch/keyboard input and input-driven QA use this single tick path.
	var state: Dictionary = sim.step(input)
	if mode == "replay": replay_cursor += 1
	var sounds: Array = []
	for event: String in state.get("events", []):
		if event.begins_with("bridge_opened:"):
			sounds.append("bridge_opened")
		elif event == "relay_filled":
			sounds.append("garden_opened")
		elif event == "garden_bloomed":
			sounds.append("island_bloomed")
		elif Registry.is_cooperative(chapter_key) and event == "stage_complete":
			sounds.append("island_bloomed")
		elif Registry.is_cooperative(chapter_key) and event == "lever":
			sounds.append("seed_landed")
		elif Registry.is_cooperative(chapter_key) and event == "handoff_claim":
			sounds.append("seed_caught")
		else:
			sounds.append(event)
	soundscape.consume_events(sounds, mode == "play")
	world.present(state)
	_update_hud(state)
	if mode == "play" and int(state.tick) % 30 == 0 and not _persist_draft("play", true):
		return
	if state.finished:
		if mode == "replay":
			_finish_replay_playback()
		else:
			_finish()


func _update_hud(state: Dictionary) -> void:
	var title := "%s · %d / 2 · %s" % [chapter.title, int(checkpoint.stage_index)+1,"Replay" if mode=="replay" else "Your first turn" if role=="a" else "Alongside a ghost"]
	var display := state
	if Registry.is_journey(chapter_key):
		var presentation := Registry.stage_presentation(chapter_key,definition.stages[int(checkpoint.stage_index)])
		var displayed_role := str(state.get("role",role))
		title = "%s · %d / 2 · %s" % [presentation.title,int(checkpoint.stage_index)+1,"Replay" if mode=="replay" else "Your first turn" if role=="a" else "Alongside a ghost"]
		display = state.duplicate()
		display.message = presentation["hint_"+displayed_role]
	if mode == "play" and Registry.is_cooperative(chapter_key) and role == "a" and state.get("can_commit",false):
		display = state.duplicate()
		display.message = PlayerCopy.MAIN_1AAC5BE95E22
	controls.update_state(title,(int(state.get("duration_ticks", 600))-int(state.tick))/30.0,display,mode=="play")

func _request_action() -> void:
	if running and not backgrounded and mode=="play" and sim.context_action().get("enabled",false):
		action_pressed=true


func _persist_draft(after_retry: String = "play", periodic: bool = false) -> bool:
	if sim.tick == 0:
		return true
	var saved: bool = journey.save_live_draft(sim, periodic) if online_session != null else journey.save_live_draft(sim)
	if saved:
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
		_begin_completion(false)
	else:
		_show_review()

func _begin_completion(from_replay: bool) -> void:
	running = false
	mode = "bloom"
	_completion_is_replay = from_replay
	completion_remaining = COMPLETION_DURATION
	hint_label.text = PlayerCopy.RELAY_PREVIEW_AFC92040F3DB
	stick.release()
	stick.visible = false
	action_button.visible = false
	finish_button.visible = false

func _finish_replay_playback() -> void:
	if sim.snapshot().get("complete", false): _begin_completion(true)
	else: _replay_ended()

func _resume_completion() -> void:
	if _completion_is_replay and not _replay_ready(): return
	mode = "bloom"
	running = false
	overlay.visible = false
	hud.visible = true


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
	card.add_child(_action_button("retry", _retry_review))
	_add_redo_action(card)
	if not can_save and role == "b": _add_campaign_redo_action(card)
	_add_local_restart(card)
	card.add_child(_action_button("leave_draft", _leave))


func _retry_review() -> void:
	if mode != "review" or backgrounded: return
	var verified: Dictionary = _simulation.verify_recording(definition, review, checkpoint, prior)
	if not verified.get("valid",false) or not verified.get("snapshot",{}).get("complete",false):
		_begin()
		return
	var recording := review.duplicate(true)
	var start := checkpoint.duplicate(true)
	var first := prior.duplicate(true)
	var saved_journey: RefCounted = journey
	var source_stage: String = journey.stage_id()
	var source_role: String = journey.role()
	var generation := online_request_generation
	mode = "confirm_retry"
	var card := _card(PlayerCopy.LIGHTHOUSE_PREVIEW_E1352BA6D9BA, "")
	var card_reference: WeakRef = weakref(card)
	var current := func() -> bool:
		var current_card: Variant = card_reference.get_ref()
		return is_instance_valid(current_card) and current_card.is_inside_tree() and mode == "confirm_retry" and not backgrounded and online_request_generation == generation and journey == saved_journey and review == recording and checkpoint == start and prior == first and journey.stage_id() == source_stage and journey.role() == source_role and journey.checkpoint() == start
	card.add_child(_action_button("retry",func():
		if current.call(): _begin()))
	_retry_cancel = func():
		if current.call(): _show_review()
	card.add_child(_action_button("cancel",_retry_cancel))


func _local_restart_available() -> bool:
	return online_session == null and journey != null and not journey.read_only and not journey.chapter_complete() and journey.restart_upgrades_rules()

func _add_local_restart(card: VBoxContainer) -> void:
	if _local_restart_available():
		card.add_child(_button("Restart chapter", _confirm_restart_chapter))

func _confirm_restart_chapter() -> void:
	if mode not in ["ready", "review"] or backgrounded or running or not _local_restart_available(): return
	var previous_mode := mode
	var saved_journey: RefCounted = journey
	var saved_sim: RefCounted = sim
	var saved_hash: String = sim.state_hash()
	var saved_checkpoint: Dictionary = journey.checkpoint()
	var saved_pairs: Array = journey.pairs()
	var saved_prior: Dictionary = journey.prior_recording()
	var saved_draft: Dictionary = journey.draft()
	var saved_review := review.duplicate(true)
	var key := chapter_key
	var generation := online_request_generation
	if journey.read_only: return
	mode = "confirm_restart_chapter"
	var card := _card("Restart chapter?", "")
	var card_reference: WeakRef = weakref(card)
	var current := func() -> bool:
		var current_card: Variant = card_reference.get_ref()
		return is_instance_valid(current_card) and current_card.is_inside_tree() and mode == "confirm_restart_chapter" and not backgrounded and not running and online_session == null and online_request_generation == generation and chapter_key == key and journey == saved_journey and sim == saved_sim and sim.state_hash() == saved_hash and review == saved_review and _local_restart_available() and journey.checkpoint() == saved_checkpoint and journey.pairs() == saved_pairs and journey.prior_recording() == saved_prior and journey.draft() == saved_draft and not journey.read_only
	card.add_child(_button("Restart chapter", func():
		if not current.call(): return
		if journey.fork_from_stage(0): _show_ready()
		else: _show_error(journey.last_error)))
	_retry_cancel = func():
		if not current.call(): return
		if previous_mode == "review": _show_review()
		else: _show_ready()
	card.add_child(_action_button("cancel", _retry_cancel))


func _accept() -> void:
	if _campaign_recovery_only(): return
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
	if _story_hold >= 0 or _story_context_lost or backgrounded or _leaving: return
	if _continue_replay_context:
		if not _replay_ready(): return
	else:
		_replay_context = {}
	if online_session != null and not _continue_replay_context:
		if online_session.coordinator != journey or not journey.has_method("playback_context"):
			_retire_replay()
			return
		_replay_context = journey.playback_context()
		if _replay_context.is_empty():
			_retire_replay()
			return
	_clear_reaction_view()
	if not Registry.reset_simulation(sim, chapter_key, definition, str(recording.stage_id), start, source, str(recording.role), recording):
		_show_error(sim.error)
		return
	sim.catch_assistance = bool(recording.get("catch_assistance", true))
	checkpoint = start
	for item: Dictionary in definition.stages:
		if str(item.id) == str(recording.stage_id):
			_present_stage_history(item,start)
	mode = "replay"
	completion_remaining = 0.0
	_completion_is_replay = false
	replay_frames = _simulation.expand_recording_inputs(recording)
	replay_cursor = 0
	overlay.visible = false
	hud.visible = true
	world.present(sim.snapshot(), true)
	_update_hud(sim.snapshot())
	running = true


func _replay_ready() -> bool:
	if _story_hold >= 0 or backgrounded or _leaving or _story_context_lost or not is_inside_tree(): return false
	if online_session == null: return true
	if online_session.coordinator == journey and not _replay_context.is_empty() and Canonical.same(_replay_context,journey.playback_context()): return true
	_retire_replay()
	return false

func _retire_replay() -> void:
	_replay_context = {}
	if is_instance_valid(world): world.set_process(false)
	if is_instance_valid(soundscape): soundscape.stop_reunion()
	story_context_changed()

func _replay_ended() -> void:
	running = false
	if replay_pair_index >= 0:
		replay_pair_index += 1
		if replay_pair_index < _pairs().size():
			_play_collection_pair(true)
		elif _solo_replay_only:
			_leave()
		else:
			_show_ready()
	else:
		_show_review()


func _play_collection_pair(continue_collection: bool = false) -> void:
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
	# Keep the existing subclass admission hook and its three-argument API.
	# The continuation flag spans only this synchronous call.
	_continue_replay_context = continue_collection
	_start_replay(pair.b, start, pair.a)
	_continue_replay_context = false
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
	if not _replay_ready(): return
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
		_present_stage_history(definition.stages[-1],start)
		world.present(sim.snapshot(), true)
	mode = "complete"
	var card := _card(PlayerCopy.RELAY_PREVIEW_8D42D9E99BAF, str(chapter.completion_text) + "\n\n" + (PlayerCopy.RELAY_PREVIEW_FF18C2378950 if online_session != null else PlayerCopy.RELAY_PREVIEW_7DECA1CF83C7))
	if online_session == null:
		card.add_child(_action_button("replays", _show_local_replays))
		card.add_child(_action_button("retry", _choose_local_checkpoint))
	else:
		card.add_child(_action_button("replays", func(): replay_pair_index = 0; _play_collection_pair()))
		if not is_instance_valid(story_flow): card.add_child(_button("New room", _create_another_room))
	_add_campaign_card_actions(card)
	_add_redo_action(card)
	_add_recent_photo_action(card)
	_add_safety_action(card)
	card.add_child(_action_button("back", _leave))
	_offer_story_arrival()

func _choose_local_checkpoint() -> void:
	if online_session != null: return
	mode = "choose_checkpoint"
	var card := _card(PlayerCopy.LIGHTHOUSE_PREVIEW_F87CE3CA6999, PlayerCopy.LIGHTHOUSE_PREVIEW_8C7F45D78BE8)
	for index in range(journey.pairs().size()):
		card.add_child(_button("%s · %d / %d" % [definition.title, index + 1, definition.stages.size()], func(): _confirm_local_checkpoint(index)))
	card.add_child(_action_button("back", _show_ready))

func _confirm_local_checkpoint(index: int) -> void:
	if online_session != null: return
	mode = "confirm_checkpoint"
	var card := _card(PlayerCopy.LIGHTHOUSE_PREVIEW_E1352BA6D9BA, PlayerCopy.LIGHTHOUSE_PREVIEW_64EA954F32D2)
	card.add_child(_action_button("retry", func():
		if journey.fork_from_stage(index): _show_ready()
		else: _show_error(journey.last_error)))
	card.add_child(_action_button("cancel", _show_ready))

func _show_local_replays() -> void:
	if online_session != null: return
	var archives: Array = journey.archived_attempts()
	if archives.is_empty():
		_watch_local_pairs(journey.pairs())
		return
	mode = "replay_collection"
	var card := _card("Replays", PlayerCopy.LIGHTHOUSE_PREVIEW_E569853CE1C8)
	if not journey.pairs().is_empty():
		card.add_child(_button("Replays · %d / %d" % [journey.pairs().size(), definition.stages.size()], func(): _watch_local_pairs(journey.pairs())))
	for attempt: Dictionary in archives:
		var date := Time.get_datetime_string_from_unix_time(int(attempt.modified)).replace("T", " ")
		card.add_child(_button("%s · %d / %d" % [date, attempt.stage_count, definition.stages.size()], func():
			var saved: Array = journey.archived_pairs(str(attempt.id))
			if saved.is_empty(): _show_error(journey.last_error)
			else: _watch_local_pairs(saved)))
	card.add_child(_action_button("back", _show_ready))

func _watch_local_pairs(pairs: Array) -> void:
	_replay_collection = pairs.duplicate(true)
	replay_pair_index = 0
	_play_collection_pair()

func _create_another_room() -> void:
	if online_session == null or mode != "complete": return
	mode = "creating_room"
	_card("New room", PlayerCopy.RELAY_PREVIEW_AE8554BD7C76)
	var room_id: String = await online_session.create_room(chapter_key)
	if not is_inside_tree(): return
	if room_id.is_empty():
		_show_error(online_session.last_error)
		return
	journey = online_session.coordinator
	_show_ready()


func _pause() -> void:
	if mode == "play" and not _persist_draft():
		return
	var previous := mode
	if is_instance_valid(reaction_strip): _safety_photos = reaction_strip.report_targets()
	mode = "paused"
	soundscape.stop_reunion()
	var card := _card("Take your time.", PlayerCopy.RELAY_PREVIEW_50922961D853)
	if previous == "play":
		card.add_child(_action_button("resume", _start_play))
		card.add_child(_action_button("retry", _begin))
	elif previous == "replay":
		card.add_child(_action_button("resume", _resume_replay))
		_add_replay_photo_action(card)
	elif previous == "bloom":
		card.add_child(_action_button("resume", _resume_completion))
	else:
		card.add_child(_action_button("continue", _show_ready))
	_add_safety_action(card)
	if previous == "play": _add_redo_action(card)
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
	card.add_child(_action_button("leave_unsaved", func(): _leave(true)))


func _leave(allow_unsaved: bool = false) -> void:
	if _story_hold >= 0: return
	if _leaving:
		return
	if online_session != null and journey != null:
		var durable: bool = journey.finish_live_draft_save()
		if not allow_unsaved and (not durable or mode == "save_error"):
			_show_save_problem(journey.last_error, "play")
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
	_restore_ready_world()
	if online_session != null and journey != null: journey.finish_live_draft_save()
	if _story_hold >= 0: _story_camera.restore(_story_hold)
	if is_instance_valid(story_flow): story_flow.retire_child(self)
	if is_instance_valid(_safety_screen): _safety_screen.client.invalidate()
	_clear_reaction_view()
	if is_instance_valid(reaction_photos):
		reaction_photos.invalidate()


func _unhandled_key_input(event: InputEvent) -> void:
	if _story_hold >= 0: return
	if is_instance_valid(_redo_screen): return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE and mode == "play":
			_request_action()
		elif event.physical_keycode == KEY_ESCAPE:
			if mode in ["confirm_retry", "confirm_restart_chapter"]:
				if _retry_cancel.is_valid(): _retry_cancel.call()
			else: _pause() if running or mode == "bloom" else _leave()


func _process(delta: float) -> void:
	if online_session != null and journey != null and not journey.poll_live_draft_save():
		_show_save_problem(journey.last_error, "play")
		return
	if (mode == "replay" or (mode == "bloom" and _completion_is_replay)) and not _replay_ready():
		if is_instance_valid(world): world.set_process(false)
		return
	if is_instance_valid(world): world.set_process(_story_hold < 0 and not backgrounded and mode in ["play", "replay", "bloom"])
	_service_online_refresh()
	if mode == "ready":
		for button: Button in _ready_turn_buttons:
			if is_instance_valid(button): button.disabled = online_session != null and online_session.busy()
	_position_replay_photos()
	if mode == "bloom" and not backgrounded:
		completion_remaining -= delta
		if completion_remaining <= 0:
			if _completion_is_replay: _replay_ended()
			else: _show_review()


func _notification(what: int) -> void:
	if is_instance_valid(_redo_screen) and what in [NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_WM_CLOSE_REQUEST]: return
	if is_instance_valid(_safety_screen) and what in [NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_WM_CLOSE_REQUEST]: return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		backgrounded = true
		if is_instance_valid(story_flow): story_flow.set_backgrounded(true)
		if is_instance_valid(soundscape):
			soundscape.set_backgrounded(true)
		if is_instance_valid(stick) and (running or mode == "bloom"):
			_pause()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		var was_backgrounded := backgrounded
		backgrounded = false
		if is_instance_valid(story_flow): story_flow.set_backgrounded(false)
		if online_session != null and was_backgrounded:
			online_refresh_queued = true
			if _story_hold < 0 and not _story_context_lost and not _leaving and mode in ["ready","online_waiting","complete"]:
				refresh_campaign_actions()
		if is_instance_valid(soundscape):
			soundscape.set_backgrounded(false)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _story_hold >= 0:
			if is_instance_valid(story_flow): story_flow.skip_from_system_back(self)
			return
		if is_instance_valid(stick):
			if mode in ["confirm_retry", "confirm_restart_chapter"]:
				if _retry_cancel.is_valid(): _retry_cancel.call()
			else: _pause() if running or mode == "bloom" else _leave()


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


func _campaign_recovery_only() -> bool:
	return online_session != null and journey != null and journey.has_method("campaign_recovery_only") and journey.campaign_recovery_only()

func _add_campaign_card_actions(card: VBoxContainer) -> void:
	if not campaign_card_state.is_valid() or not campaign_card_action.is_valid(): return
	_campaign_actions = VBoxContainer.new()
	_campaign_actions.add_theme_constant_override("separation",12)
	card.add_child(_campaign_actions)
	refresh_campaign_actions()

func refresh_campaign_actions() -> void:
	if not is_instance_valid(_campaign_actions) or not _campaign_actions.is_inside_tree() or not campaign_card_state.is_valid() or not campaign_card_action.is_valid(): return
	for old: Node in _campaign_actions.get_children():
		_campaign_actions.remove_child(old)
		old.queue_free()
	var state: Variant = campaign_card_state.call()
	if not state is Dictionary: return
	if not str(state.get("message","")).is_empty(): _campaign_actions.add_child(_label(str(state.message),18))
	for item: Dictionary in state.get("actions",[]):
		var button := _button(str(item.label),func(): campaign_card_action.call(str(item.action)))
		button.disabled = not item.get("enabled",false)
		button.mouse_filter = Control.MOUSE_FILTER_PASS
		_campaign_actions.add_child(button)
	_add_campaign_redo_action(_campaign_actions)
	# One poll owns both the campaign and room reads, even between their awaits.
	if refresh_schedule.busy():
		for button: Node in _campaign_actions.get_children():
			if button is BaseButton: button.disabled = true

func _show_campaign_recovery() -> void:
	running = false
	action_pressed = false
	mode = "campaign_recovery"
	var card := _card("Saved chapter",PlayerCopy.RELAY_PREVIEW_53416F9C53E3)
	_add_campaign_card_actions(card)
	card.add_child(_action_button("back",_leave))

func refresh_campaign_card() -> void:
	if _story_hold >= 0 or _story_context_lost or running or _leaving: return
	if journey.chapter_complete() and journey.pending().is_empty(): _show_completed()
	elif _campaign_recovery_only(): _show_campaign_recovery()
	else: _show_ready()

func show_story_history(entries: Array, open_entry: Callable) -> void:
	if not story_boundary_ready(true) or not open_entry.is_valid(): return
	mode = "story_history"
	var card := _card("History","")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480,220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for entry: Dictionary in entries:
		var row := _button("%d · %s" % [int(entry.index)+1,"Arrival" if entry.phase == "arrival" else "Completion"],func(): open_entry.call(int(entry.index),str(entry.phase)),false)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		list.add_child(row)
	card.add_child(_action_button("back",refresh_campaign_card))

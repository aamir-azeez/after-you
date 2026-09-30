extends Node3D
const PlayerCopy = preload("res://presentation/player_copy.gd")
## An immutable, read-only view. This scene has no gameplay journal or commit API.
signal closed
const Collection = preload("res://services/shared_replay_collection.gd")
const Registry = preload("res://services/chapter_registry.gd")
const LegacySimulation = preload("res://core/simulation.gd")
const Levels = preload("res://core/levels.gd")
const LegacyWorld = preload("res://presentation/island_world.gd")
const Controls = preload("res://presentation/chapter_controls.gd")
const Strip = preload("res://presentation/reaction_photo_strip.gd")
const Session = preload("res://services/relay_online_session.gd")
const SafetyScreen = preload("res://presentation/safety_screen.gd")
const Safety = preload("res://services/safety_client.gd")
const Soundscape = preload("res://services/soundscape.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const LoadProgress = preload("res://services/replay_load_progress.gd")
const LoadingBar = preload("res://presentation/replay_loading_bar.gd")
const COMPLETION_DURATION := 3.0
var entry: Dictionary = {}
var sequence: Array = []
var _part_index := 0
var _validation_worker: Thread
var _validation_progress := LoadProgress.new()
var _loading_bar: VBoxContainer
var settings: Dictionary = {}
var identity: Callable
var api: Node
var context_factory: RefCounted
var controls: CanvasLayer
var world: Node3D
var sim: RefCounted
var strip: Control
var soundscape: Node
var mode := "ready"
var running := false
var backgrounded := false
var cursor := 0
var _frames: Array = []
var _display_title := ""
var _binding: Dictionary = {}
var _photos: RefCounted
var _tick_time := 0.0
var _safety_screen: CanvasLayer
var _safety_photos: Array = []
var blocked_exit := false
var completion_remaining := 0.0
var _paused_completion := false

class ReadSession extends Session:
	var photo_targets: Array = []
	var photo_context_factory: RefCounted
	var local_replay_only := true
	func local_photo_key(_room: String, _turn: String, _hash_value: String) -> String: return ""
	func create_photo_controller(local_io: Callable, factory: RefCounted = null) -> RefCounted:
		var supplied: RefCounted = factory if factory != null else photo_context_factory
		if supplied == null: supplied = auxiliary_context_factory()
		var result: RefCounted
		if supplied == null: result = super.create_photo_controller(local_io)
		# The base session now supplies factories even for ordinary rooms. Wrap
		# every one before its request can bypass this scene's transport override.
		else: result = super.create_photo_controller(local_io, ReadFactory.new(self, supplied))
		result.local_replay_only = local_replay_only
		return result
	func transport(request: Dictionary) -> Dictionary:
		if request.get("method") == HTTPClient.METHOD_GET: return await super.transport(request)
		if not _ready() or request.get("owner_player_id") != _owner or request.get("identity_epoch") != _epoch:
			return {"ok": false, "status": 401, "code": "identity_changed"}
		if not _delivery_ack(request): return {"ok": false, "status": 403, "code": "read_only_replay"}
		# The photo controller calls this only after a verified durable local write.
		# A delivery receipt changes neither a photo nor a gameplay contribution.
		return await _call(request.method, request.path, request.body)
	func _delivery_ack(request: Dictionary) -> bool:
		var body: Variant = request.get("body")
		if request.get("method") != HTTPClient.METHOD_POST or not body is Dictionary or body.size() != 3 or not Collection.Coordinator._range(body.get("photo_revision"), 1, 1000000) or not Collection._hash(body.get("sha256")):
			return false
		for target: Dictionary in photo_targets:
			if request.get("path") == "/v2/rooms/" + str(target.room_id) + "/photos/" + str(target.turn_id) + "/ack" and body.get("recording_hash") == target.recording_hash: return true
		return false

class ReadTarget extends RefCounted:
	var _factory: RefCounted
	var _context: RefCounted
	func _init(factory: RefCounted, context: RefCounted) -> void:
		_factory = factory
		_context = context
	func current() -> bool:
		return _factory.current() and _context != null and _context.has_method("current") and _context.current()
	func request(value: Dictionary) -> Dictionary:
		var session: RefCounted = _factory.session()
		if not current() or session == null or not _context.has_method("request"): return _held()
		if value.get("method") != HTTPClient.METHOD_GET and not session._delivery_ack(value): return _held()
		# Strong context/factory locals survive view closure during transport.
		var context := _context
		var response: Dictionary = await context.request(value)
		return response if current() else _held()
	func _held() -> Dictionary:
		return {"ok": false, "ignored": true, "status": 403, "code": "read_only_replay"}

class ReadFactory extends RefCounted:
	var _source: RefCounted
	var _session: WeakRef
	var _generation := -1
	var _identity: Dictionary = {}
	func _init(session: RefCounted, source: RefCounted) -> void:
		_source = source
		_session = weakref(session)
		if session._ready():
			_generation = int(session._generation)
			_identity = session.photo_identity()
	func session() -> RefCounted: return _session.get_ref()
	func current() -> bool:
		var value: RefCounted = session()
		return value != null and _generation >= 0 and value._generation == _generation and value.photo_identity() == _identity and _source != null and _source.has_method("current") and _source.current()
	func for_room(room_id: String, purpose: String) -> RefCounted:
		if not current() or purpose != "photo" or not _source.has_method("for_room"): return null
		var context: Variant = _source.for_room(room_id, purpose)
		return ReadTarget.new(self, context) if context is RefCounted else null

func _ready() -> void:
	_binding = identity.call() if identity.is_valid() else {}
	controls = Controls.new()
	controls.settings = settings.duplicate(true)
	add_child(controls)
	controls.pause_requested.connect(_pause)
	controls.finish_requested.connect(_pause)
	if sequence.is_empty(): sequence = [entry]
	if not _current() or sequence.size() > 2:
		_show_error(PlayerCopy.SHARED_REPLAY_VIEW_1F82C26A6714)
		return
	sequence = sequence.duplicate(true)
	mode = "loading"
	var card: VBoxContainer = controls.card("Shared replay", "")
	_loading_bar=LoadingBar.new()
	_loading_bar.reduced_motion=bool(settings.get("reduced_motion",false))
	card.add_child(_loading_bar)
	_loading_bar.update_progress(_validation_progress.snapshot())
	card.add_child(controls.button_for("back", _leave))
	_validation_worker = Thread.new()
	if _validation_worker.start(Callable(get_script(), "valid_sequence").bind(sequence, str(_binding.player_id), _validation_progress)) != OK:
		_validation_worker = null
		_show_error(PlayerCopy.SHARED_REPLAY_VIEW_1F82C26A6714)

func _prepare_replay() -> void:
	entry = sequence[0]
	_display_title = str(Collection.summary(entry).title)
	world = Registry.world_script(entry.room.chapter_key).new() if entry.room.family == "chapter" else LegacyWorld.new()
	world.reduced_motion = bool(settings.get("reduced_motion", false))
	add_child(world)
	GraphicsPolicy.apply(world, settings)
	var definition: Dictionary = Registry.definition(entry.room.chapter_key) if entry.room.family == "chapter" else Levels.get_level(entry.pair.level_id)
	world.load_level(definition)
	world.configure_camera_exploration(_camera_exploration_active, _camera_exploration_allowed)
	world.camera_exploration.frame_applied.connect(_position_replay_photos)
	soundscape = Soundscape.new()
	soundscape.configure(settings)
	add_child(soundscape)
	world.footstep.connect(func(): if running: soundscape.play_footstep())
	if entry.room.family == "chapter":
		_photos = ReadSession.new(api, identity)
		_photos.photo_context_factory = context_factory
		_photos.photo_targets = Collection._verified_photo_turns(entry, _binding.player_id)
		strip = Strip.new()
		strip.configure(_photos)
		strip.report_requested.connect(_report_photo)
		controls.hud.add_child(strip)
		strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_start()

func _current() -> bool:
	return identity.is_valid() and _binding.get("ready", false) and identity.call() == _binding

static func valid_sequence(values: Array, owner: String, progress: RefCounted = null) -> bool:
	if values.is_empty() or values.size() > 2: return false
	if progress != null: progress.set_total(values.size()+1)
	for value: Variant in values:
		if not Collection.verify_entry(value, owner): return false
		if progress != null: progress.advance()
	if values.size() == 1:
		if progress != null: progress.advance()
		return true
	var first: Dictionary = values[0]
	var last: Dictionary = values[1]
	var valid: bool = first.room.family == "chapter" and first.room == last.room and first.pair.stage_index == 0 and last.pair.stage_index == 1 and first.pair.branch <= last.pair.branch and Collection.Canonical.same(first.pair.checkpoint, Registry.previous_checkpoint(last.room.chapter_key, last.pair.checkpoint))
	if valid and progress != null: progress.advance()
	return valid

func _start() -> void:
	_part_index = 0
	_start_part()

func _start_part() -> void:
	if not _current(): identity_invalidated(); return
	entry = sequence[_part_index]
	_display_title = str(Collection.summary(entry).title)
	if _photos != null: _photos.photo_targets = Collection._verified_photo_turns(entry, _binding.player_id)
	completion_remaining = 0.0
	_paused_completion = false
	var pair: Dictionary = entry.pair
	if entry.room.family == "chapter":
		var engine: Script = Registry.simulation_script(entry.room.chapter_key)
		sim = engine.new()
		var definition := Registry.definition(entry.room.chapter_key)
		if not Registry.reset_simulation(sim, entry.room.chapter_key, definition, str(pair.b.stage_id), Registry.previous_checkpoint(entry.room.chapter_key, pair.checkpoint), pair.a, "b", pair.b):
			_show_error(sim.error); return
		world.show_stage(definition.stages[int(pair.stage_index)])
		_frames = engine.expand_recording_inputs(pair.b)
	else:
		sim = LegacySimulation.new()
		if not sim.reset(Levels.get_level(pair.level_id), pair.a, "b"):
			_show_error(sim.error); return
		_frames = LegacySimulation.expand_recording_inputs(pair.b)
	sim.catch_assistance = bool(pair.b.get("catch_assistance", true))
	cursor = 0
	_tick_time = 0.0
	world.present(sim.snapshot(), true)
	_resume()

func _resume() -> void:
	if not _current(): identity_invalidated(); return
	mode = "bloom" if _paused_completion else "replay"
	running = not _paused_completion
	controls.show_play()
	_update_hud()
	if is_instance_valid(strip): strip.show_turns(_photos.photo_targets)

func _physics_process(delta: float) -> void:
	if not running or backgrounded or not _current(): return
	_tick_time += delta
	while _tick_time >= 1.0 / 30.0 and running:
		_tick_time -= 1.0 / 30.0
		if cursor >= _frames.size(): _finished(); break
		var snapshot: Dictionary = sim.step(_frames[cursor])
		cursor += 1
		world.present(snapshot)
		_update_hud(snapshot)
		if cursor >= _frames.size(): _finished()

func _update_hud(snapshot: Dictionary = {}) -> void:
	var state: Dictionary = (sim.snapshot() if snapshot.is_empty() else snapshot).duplicate()
	state.context_action = {"label": "Replay", "enabled": false}
	state.message = PlayerCopy.SHARED_REPLAY_VIEW_C46191B0894B
	controls.update_state("SHARED REPLAY\n" + _display_title, float(_frames.size() - cursor) / 30.0, state, false)
	controls.stick.hide()
	controls.action_button.hide()
	controls.finish_button.hide()

func _pause() -> void:
	if not running and mode != "bloom": return
	_paused_completion = mode == "bloom"
	running = false
	mode = "paused"
	if is_instance_valid(strip):
		_safety_photos = strip.report_targets()
		strip.clear()
	var card: VBoxContainer = controls.card(PlayerCopy.SHARED_REPLAY_VIEW_91F0B52CD01E, PlayerCopy.SHARED_REPLAY_VIEW_6EE4245DCD7F)
	card.add_child(controls.button_for("resume", _resume))
	card.add_child(controls.button_for("replay", _start))
	card.add_child(controls.button("Report or block player", _open_safety))
	card.add_child(controls.button_for("back", _leave))

func _finished() -> void:
	running = false
	if sim.snapshot().get("complete", false):
		mode = "bloom"
		completion_remaining = COMPLETION_DURATION
	else:
		_show_finished()

func _show_finished() -> void:
	if _part_index + 1 < sequence.size():
		_part_index += 1
		_start_part()
		return
	running = false
	mode = "complete"
	if is_instance_valid(strip): strip.clear()
	var card: VBoxContainer = controls.card(PlayerCopy.SHARED_REPLAY_VIEW_DA1E512354C7, PlayerCopy.SHARED_REPLAY_VIEW_8432676D063D)
	card.add_child(controls.button_for("replay", _start))
	card.add_child(controls.button("Report or block player", _open_safety))
	card.add_child(controls.button_for("back", _leave))

func _process(delta: float) -> void:
	if is_instance_valid(world): world.set_process(not backgrounded and mode in ["replay", "bloom"])
	if not _current():
		if mode != "error": identity_invalidated()
		return
	if mode == "loading" and _validation_worker != null:
		if is_instance_valid(_loading_bar): _loading_bar.update_progress(_validation_progress.snapshot())
		if _validation_worker.is_alive(): return
		var valid: bool = _validation_worker.wait_to_finish()
		_validation_worker = null
		if not valid:
			_show_error(PlayerCopy.SHARED_REPLAY_VIEW_1F82C26A6714)
			return
		mode="preparing"
		if is_instance_valid(_loading_bar): _loading_bar.update_progress({"phase":"preparing"})
		return
	if mode == "preparing":
		_prepare_replay()
	_position_replay_photos()
	if mode == "bloom" and not backgrounded:
		completion_remaining = maxf(0.0, completion_remaining - delta)
		if completion_remaining == 0.0: _show_finished()

func _position_replay_photos() -> void:
	if not is_instance_valid(strip): return
	if not running or backgrounded: strip.hide(); return
	strip.show()
	var inverse: Transform2D = strip.get_global_transform_with_canvas().affine_inverse()
	var exclusions: Array[Rect2] = []
	for item: Control in [controls.timer_label, controls.chapter_label, controls.hint_label, controls.pause_button, controls.objective_panel, controls.turn_progress]:
		if item.is_visible_in_tree(): exclusions.append(inverse * item.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, item.size))
	strip.position_over_spirits(world.camera, world.actors, Rect2(Vector2.ZERO, strip.size), exclusions)

func identity_invalidated() -> void:
	running = false
	if _photos != null: _photos.invalidate_identity()
	if is_instance_valid(strip): strip.clear()
	_show_error(PlayerCopy.SHARED_REPLAY_VIEW_FBCF70672D83)

func _show_error(message: String) -> void:
	running = false
	mode = "error"
	var card: VBoxContainer = controls.card(PlayerCopy.SHARED_REPLAY_VIEW_B81950FA86BB, message)
	card.add_child(controls.button_for("back", _leave))

func _leave() -> void:
	running = false
	if is_instance_valid(strip): strip.clear()
	if _photos != null: _photos.invalidate_identity()
	closed.emit()

func _exit_tree() -> void:
	if _validation_worker != null and _validation_worker.is_started():
		_validation_worker.wait_to_finish()
		_validation_worker = null
	if is_instance_valid(_safety_screen): _safety_screen.client.invalidate()
	if is_instance_valid(strip): strip.clear()
	if _photos != null: _photos.invalidate_identity()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		# Closing emits synchronously and may reveal Main's return menu before
		# this same event reaches it. Consume the viewer's action first.
		get_viewport().set_input_as_handled()
		_pause() if running or mode == "bloom" else _leave()

func _notification(what: int) -> void:
	if is_instance_valid(_safety_screen) and what in [NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_WM_CLOSE_REQUEST]: return
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		backgrounded = true
		if running or mode == "bloom": _pause()
		if is_instance_valid(soundscape): soundscape.set_backgrounded(true)
	elif what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]:
		backgrounded = false
		if is_instance_valid(soundscape): soundscape.set_backgrounded(false)
	elif what in [NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_WM_CLOSE_REQUEST]:
		_pause() if running or mode == "bloom" else _leave()

func _report_photo(reference: Dictionary) -> void:
	_safety_photos = [reference.photo.duplicate(true)]
	_open_safety()

func _open_safety() -> void:
	if not _current() or is_instance_valid(_safety_screen): return
	var peer: String = entry.room.guest_id if entry.room.host_id == _binding.player_id else entry.room.host_id
	var room := {"room_family": "relay" if entry.room.family == "chapter" else "legacy", "room_id": entry.room.room_id, "peer_id": peer, "photos": _safety_photos.duplicate(true)}
	running = false
	mode = "safety"
	if is_instance_valid(strip): strip.clear()
	controls.visible = false
	_safety_screen = SafetyScreen.new(Safety.new(api, identity, null, Callable(), context_factory), room, _close_safety, func(): blocked_exit = true; _leave())
	add_child(_safety_screen)

func _close_safety() -> void:
	_safety_screen = null
	controls.visible = true
	running = true
	_pause()

func _camera_exploration_active() -> bool:
	return not backgrounded and mode in ["replay", "bloom", "complete"] and controls.visible and not controls.overlay.visible

func _camera_exploration_allowed(point: Vector2) -> bool:
	return not world.CameraExploration.ui_blocks(controls, point)

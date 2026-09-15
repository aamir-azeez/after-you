extends Node3D
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
const Soundscape = preload("res://services/soundscape.gd")
var entry: Dictionary = {}
var settings: Dictionary = {}
var identity: Callable
var api: Node
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
var _binding: Dictionary = {}
var _photos: RefCounted
var _tick_time := 0.0

class ReadSession extends Session:
	var photo_targets: Array = []
	func local_photo_key(_room: String, _turn: String, _hash_value: String) -> String: return ""
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

func _ready() -> void:
	_binding = identity.call() if identity.is_valid() else {}
	controls = Controls.new()
	controls.settings = settings.duplicate(true)
	add_child(controls)
	controls.pause_requested.connect(_pause)
	controls.finish_requested.connect(_pause)
	if not _current() or not Collection.verify_entry(entry, str(_binding.get("player_id", ""))):
		_show_error("This shared memory could not be verified. Your saved recordings were kept.")
		return
	entry = entry.duplicate(true)
	world = Registry.world_script(entry.room.chapter_key).new() if entry.room.family == "chapter" else LegacyWorld.new()
	world.reduced_motion = bool(settings.get("reduced_motion", false))
	add_child(world)
	var definition: Dictionary = Registry.definition(entry.room.chapter_key) if entry.room.family == "chapter" else Levels.get_level(entry.pair.level_id)
	world.load_level(definition)
	soundscape = Soundscape.new()
	soundscape.configure(settings)
	add_child(soundscape)
	world.footstep.connect(func(): if running: soundscape.play_footstep())
	if entry.room.family == "chapter":
		_photos = ReadSession.new(api, identity)
		_photos.photo_targets = Collection.photo_turns(entry, _binding.player_id)
		strip = Strip.new()
		strip.configure(_photos)
		controls.hud.add_child(strip)
		strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_start()

func _current() -> bool:
	return identity.is_valid() and _binding.get("ready", false) and identity.call() == _binding

func _start() -> void:
	if not _current(): identity_invalidated(); return
	var pair: Dictionary = entry.pair
	if entry.room.family == "chapter":
		var engine: Script = Registry.simulation_script(entry.room.chapter_key)
		sim = engine.new()
		var definition := Registry.definition(entry.room.chapter_key)
		if not sim.reset(definition, str(pair.b.stage_id), Registry.previous_checkpoint(entry.room.chapter_key, pair.checkpoint), pair.a, "b"):
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
	mode = "replay"
	running = true
	controls.show_play()
	_update_hud()
	if is_instance_valid(strip): strip.show_turns(Collection.photo_turns(entry, _binding.player_id))

func _physics_process(delta: float) -> void:
	if not running or backgrounded or not _current(): return
	_tick_time += delta
	while _tick_time >= 1.0 / 30.0 and running:
		_tick_time -= 1.0 / 30.0
		if cursor >= _frames.size(): _finished(); break
		sim.step(_frames[cursor])
		cursor += 1
		world.present(sim.snapshot())
		_update_hud()
		if cursor >= _frames.size(): _finished()

func _update_hud() -> void:
	var state: Dictionary = sim.snapshot().duplicate(true)
	state.context_action = {"label": "Replay", "enabled": false}
	state.message = "Two contributions, kept together."
	controls.update_state("SHARED REPLAY\n" + str(Collection.summary(entry).title), float(_frames.size() - cursor) / 30.0, state, false)
	controls.stick.hide()
	controls.action_button.hide()
	controls.finish_button.hide()

func _pause() -> void:
	if not running: return
	running = false
	mode = "paused"
	if is_instance_valid(strip): strip.clear()
	var card: VBoxContainer = controls.card("A moment to keep", "This is a shared replay. Watching it never changes either contribution.")
	card.add_child(controls.button("Continue replay", _resume))
	card.add_child(controls.button("Watch from the beginning", _start))
	card.add_child(controls.button("Back to shared replays", _leave))

func _finished() -> void:
	running = false
	mode = "complete"
	if is_instance_valid(strip): strip.clear()
	var card: VBoxContainer = controls.card("You made this together.", "Both contributions are saved as they were recorded.")
	card.add_child(controls.button("Watch again", _start))
	card.add_child(controls.button("Back to shared replays", _leave))

func _process(_delta: float) -> void:
	if not _current():
		if mode != "error": identity_invalidated()
		return
	if not is_instance_valid(strip): return
	if not running or backgrounded: strip.hide(); return
	strip.show()
	var inverse: Transform2D = strip.get_global_transform_with_canvas().affine_inverse()
	var exclusions: Array[Rect2] = []
	for item: Control in [controls.timer_label, controls.chapter_label, controls.hint_label, controls.pause_button, controls.progress_label, controls.turn_progress]:
		if item.is_visible_in_tree(): exclusions.append(inverse * item.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, item.size))
	strip.position_over_spirits(world.camera, world.actors, Rect2(Vector2.ZERO, strip.size), exclusions)

func identity_invalidated() -> void:
	running = false
	if _photos != null: _photos.invalidate_identity()
	if is_instance_valid(strip): strip.clear()
	_show_error("Your account changed. Return to shared replays before opening this memory again.")

func _show_error(message: String) -> void:
	running = false
	mode = "error"
	var card: VBoxContainer = controls.card("Your saved replay is kept", message)
	card.add_child(controls.button("Back to shared replays", _leave))

func _leave() -> void:
	running = false
	if is_instance_valid(strip): strip.clear()
	if _photos != null: _photos.invalidate_identity()
	closed.emit()

func _exit_tree() -> void:
	if is_instance_valid(strip): strip.clear()
	if _photos != null: _photos.invalidate_identity()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		_pause() if running else _leave()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		backgrounded = true
		if running: _pause()
		if is_instance_valid(soundscape): soundscape.set_backgrounded(true)
	elif what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]:
		backgrounded = false
		if is_instance_valid(soundscape): soundscape.set_backgrounded(false)
	elif what in [NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_WM_CLOSE_REQUEST]:
		_pause() if running else _leave()

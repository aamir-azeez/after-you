extends Node
## Still pips: one shared offscreen renderer draws a pip at rest (the same
## studio as the live preview, kit/pip_stage.gd) into a texture, and keeps the
## newest CACHE_SIZE of them, so a list of pips never gives a row a live view
## of its own. kit/pip_avatar.gd asks here in still mode.
##
## - request() answers at once from the cache, or queues the pip and calls
##   back when it is drawn. Requests for a pip already queued wait on the same
##   render: ten matching pips cost one.
## - It draws at most one pip a frame (one finishes and the next starts in the
##   same frame), and skips a queued pip nobody waits for
##   any more (a row scrolled away and freed).
## - The renderer is a node made under the root on the first request; with
##   nothing left to draw for IDLE_SECONDS it frees itself and its viewport.
##   The cached textures stay for the session; their release is registered
##   with kit/session_release.gd.
## - Without a GPU (headless runs) a drawn pip is a blank texture of its size,
##   so every caller still gets an answer.
const Stage = preload("res://presentation/kit/pip_stage.gd")
const Outfit = preload("res://services/outfit.gd")
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const SCRIPT_PATH := "res://presentation/kit/pip_snapshots.gd"
const NODE_NAME := "PipSnapshots"

const CACHE_SIZE := 64
const IDLE_SECONDS := 2.0
## A render with no frame drawn after this many frames is asked for again,
## or, with no GPU, taken as a blank.
const DRAW_WAIT_FRAMES := 3

## Drawn textures by key, oldest first.
static var _cache: Dictionary = {}
## Queued keys in order, each one's pip, and who waits for it.
static var _queue: Array[String] = []
static var _specs: Dictionary = {}
static var _waiters: Dictionary = {}
static var _node: WeakRef
## Pips drawn this session (tests count it).
static var renders := 0
## Tests may draw with this instead of the GPU: func(spec: Dictionary) -> Texture2D.
static var draw_with: Callable

var _view: SubViewport
var _camera: Camera3D
var _pip: Node3D
## The key being drawn, frames waited, and whether a frame has drawn it.
var _drawing := ""
var _waited := 0
var _drawn := false
var _idle := 0.0
var _headless := DisplayServer.get_name() == "headless"

## The cache key for a pip: colour, outfit, pixel size and facing.
static func key(color: Color, outfit: Dictionary, size: Vector2i, yaw: float) -> String:
	return "%s|%s|%dx%d|%.4f" % [color.to_html(), Outfit.digest(outfit), size.x, size.y, yaw]

## The pip's texture now if it is drawn, else null, and `done(key, texture)`
## is called once it is.
static func request(color: Color, outfit: Dictionary, size: Vector2i, yaw: float, done: Callable) -> Texture2D:
	var id := key(color, outfit, size, yaw)
	var found: Texture2D = _cache.get(id)
	if found != null:
		# Most recently used goes last.
		_cache.erase(id)
		_cache[id] = found
		return found
	if not _waiters.has(id):
		_waiters[id] = []
		_specs[id] = {"key": id, "color": color, "outfit": outfit.duplicate(), "size": size, "yaw": yaw}
		_queue.append(id)
	_waiters[id].append(done)
	_renderer()
	return null

## How many textures are kept, and whether a pip waits to be drawn (tests).
static func cached_count() -> int:
	return _cache.size()

static func pending() -> int:
	return _queue.size()

## The renderer node, or null while none runs (tests).
static func renderer() -> Node:
	return _node.get_ref() if _node != null else null

## Lets go of every texture (SessionRelease calls it at shutdown; tests too).
static func release_cached() -> void:
	_cache.clear()
	_queue.clear()
	_specs.clear()
	_waiters.clear()

static func _renderer() -> void:
	var running: Node = renderer()
	if is_instance_valid(running) and not running.is_queued_for_deletion(): return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null: return
	var made: Node = load(SCRIPT_PATH).new()
	made.name = NODE_NAME
	made.process_mode = Node.PROCESS_MODE_ALWAYS
	# The root may be busy adding or removing the screen that asked.
	tree.root.add_child.call_deferred(made)
	_node = weakref(made)

func _process(delta: float) -> void:
	if not _drawing.is_empty():
		_waited += 1
		if not _drawn and _waited < DRAW_WAIT_FRAMES: return
		if not _drawn and not _headless:
			# A frame the system skipped: draw it again rather than keep a blank.
			_waited = 0
			_view.render_target_update_mode = SubViewport.UPDATE_ONCE
			return
		_finish()
	var next := _next()
	if next.is_empty():
		_idle += delta
		if _idle >= IDLE_SECONDS: queue_free()
		return
	_idle = 0.0
	_start(_specs[next])

## The next queued key someone still waits for ("" when none).
func _next() -> String:
	while not _queue.is_empty():
		var id: String = _queue.pop_front()
		var live: Array = (_waiters.get(id, []) as Array).filter(func(done: Callable) -> bool: return done.is_valid())
		if not live.is_empty():
			_waiters[id] = live
			return id
		_waiters.erase(id)
		_specs.erase(id)
	return ""

func _start(spec: Dictionary) -> void:
	renders += 1
	_drawing = spec.key
	if draw_with.is_valid():
		_store(spec.key, draw_with.call(spec))
		return
	_build()
	var size: Vector2i = spec.size
	_view.size = size
	if is_instance_valid(_pip): _pip.free()
	_pip = Stage.pip(spec.color, spec.outfit)
	_pip.facing_target = spec.yaw
	_pip.facing.rotation.y = spec.yaw
	_view.add_child(_pip)
	Stage.frame(_camera, spec.outfit)
	_pip.advance_motion(Vector3.ZERO, 0.001, false)
	_waited = 0
	_drawn = false
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE

func _build() -> void:
	if is_instance_valid(_view): return
	_view = SubViewport.new()
	_view.name = "PipSnapshotView"
	_view.own_world_3d = true
	_view.transparent_bg = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_view)
	# The studio's pip is replaced for each render; a placeholder holds its place.
	_pip = Node3D.new()
	_camera = Stage.build(_view, _pip, {})
	RenderingServer.frame_post_draw.connect(_on_drawn)

func _on_drawn() -> void:
	if not _drawing.is_empty(): _drawn = true

func _finish() -> void:
	var image: Image = _view.get_texture().get_image() if is_instance_valid(_view) and not _headless else null
	var size: Vector2i = _specs[_drawing].size
	if image == null or image.is_empty(): image = Image.create(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGBA8)
	_store(_drawing, ImageTexture.create_from_image(image))

func _store(id: String, texture: Texture2D) -> void:
	_drawing = ""
	_cache[id] = texture
	while _cache.size() > CACHE_SIZE: _cache.erase(_cache.keys()[0])
	SessionRelease.on_exit(Callable(load(SCRIPT_PATH), "release_cached"))
	var waiting: Array = _waiters.get(id, [])
	_waiters.erase(id)
	_specs.erase(id)
	for done: Callable in waiting:
		if done.is_valid(): done.call(id, texture)

func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_drawn): RenderingServer.frame_post_draw.disconnect(_on_drawn)
	# Taken away mid render (the tree is closing): its pip goes back in line,
	# so a later renderer draws it for whoever still waits.
	if not _drawing.is_empty():
		_queue.push_front(_drawing)
		_drawing = ""

extends Node
## Loads the chapter pictures picker cards show on the loader's threads and
## keeps them while Main is up, so opening the Chapters page never decodes a
## 1280x720 picture in a frame.
##
## - A card asks through fill(): a picture already kept is set at once, so the
##   card draws filled; any other is loaded off the main thread, one at a time,
##   and fades in on the card when it arrives. The card's frame keeps its size
##   meanwhile, so nothing moves.
## - While Home is idle (idle()), the pictures warm_paths() names are loaded
##   ahead, so the page opens filled even right after a chapter.
## - Main owns it, so its pictures go with Main when a chapter opens, and it
##   lets them go while a world plays inside Main (playing(): an online
##   chapter, a shared replay): none is held while a chapter plays, and no
##   static var holds a texture. It keeps only pictures cards asked for or
##   warm_paths() named, one per picker card (about 3.7 MB each), as the open
##   page itself held them.
## - With no shelf in the tree (tests, tools), fill() loads at once, as before.
const GROUP := "chapter_thumbnail_shelf"
const IDLE_SECONDS := 0.5
const FADE_SECONDS := 0.15
const PATH_META := "thumbnail_path"

## True while the player is at Home with nothing opening; set by the owner.
var idle: Callable
## True while no load may start (a chapter opening, the app in the
## background); set by the owner.
var paused: Callable
## True while a world plays inside the owner; the shelf lets its pictures go
## and starts none. Set by the owner.
var playing: Callable
## The pictures the Chapters page shows, in its order; set by the owner.
var warm_paths: Callable
var idle_seconds := IDLE_SECONDS
var fade_seconds := FADE_SECONDS

## Path to Texture2D for every picture loaded so far.
var _kept: Dictionary = {}
## Paths cards wait for, then paths warmed ahead, in order.
var _wanted: Array[String] = []
var _ahead: Array[String] = []
## The one path on the loader's threads, or "".
var _loading := ""
## Path to the instance ids of the pictures waiting for it.
var _waiting: Dictionary = {}
var _idle_for := 0.0
var _warmed := false

func _init() -> void:
	name = "ChapterThumbnailShelf"
	add_to_group(GROUP)

## Shows the picture at path in rect once rect is in a tree: at once when that
## tree's shelf keeps it, else when the shelf has loaded it. With no shelf in
## the tree, loads it at once, as cards did before.
static func fill(rect: TextureRect, path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path): return
	rect.set_meta(PATH_META, path)
	if rect.is_inside_tree(): _fill_in_tree(rect, path)
	else: rect.tree_entered.connect(func(): _fill_in_tree(rect, path), CONNECT_ONE_SHOT)

static func _fill_in_tree(rect: TextureRect, path: String) -> void:
	if not is_instance_valid(rect) or rect.texture != null: return
	var shelf := rect.get_tree().get_first_node_in_group(GROUP)
	if shelf == null: rect.texture = load(path) as Texture2D
	else: shelf.want(rect, path)

## Sets rect's picture now when kept, else loads it first and fades it in.
func want(rect: TextureRect, path: String) -> void:
	if _kept.has(path):
		rect.texture = _kept[path]
		return
	if not _waiting.has(path): _waiting[path] = []
	_waiting[path].append(rect.get_instance_id())
	if path != _loading and not path in _wanted: _wanted.append(path)
	_ahead.erase(path)
	set_process(true)

## Whether the picture at path is kept.
func keeps(path: String) -> bool:
	return _kept.has(path)

## True while a card waits for a picture or one loads.
func busy() -> bool:
	return not _loading.is_empty() or not _wanted.is_empty()

func _process(delta: float) -> void:
	if not _loading.is_empty():
		_poll()
		# The next one starts in the same frame its predecessor arrives.
		if not _loading.is_empty(): return
	if playing.is_valid() and playing.call():
		if _warmed or not _kept.is_empty(): release()
		return
	if paused.is_valid() and paused.call():
		_idle_for = 0.0
		return
	if not _warmed and _wanted.is_empty():
		_idle_for = _idle_for + delta if idle.is_valid() and idle.call() else 0.0
		if _idle_for >= idle_seconds: _warm()
	if not _wanted.is_empty(): _start(_wanted.pop_front())
	elif not _ahead.is_empty(): _start(_ahead.pop_front())
	# Holding pictures, it keeps watching playing(); holding none, it rests.
	elif _warmed and _kept.is_empty(): set_process(false)

## Lets every kept picture go and stops warming; the next idle Home warms
## again. Cards still waiting keep their place in line.
func release() -> void:
	_kept.clear()
	_ahead.clear()
	_warmed = false
	_idle_for = 0.0

func _warm() -> void:
	_warmed = true
	if not warm_paths.is_valid(): return
	for path: String in warm_paths.call():
		if not path.is_empty() and not _kept.has(path) and path != _loading and not path in _wanted and not path in _ahead: _ahead.append(path)

func _start(path: String) -> void:
	if _kept.has(path):
		_arrive(path, _kept[path])
	elif not ResourceLoader.exists(path):
		_arrive(path, null)
	elif ResourceLoader.has_cached(path):
		# Already in memory elsewhere: taking it costs nothing.
		_arrive(path, load(path) as Texture2D)
	elif ResourceLoader.load_threaded_request(path) == OK:
		_loading = path
	else:
		_arrive(path, load(path) as Texture2D)

func _poll() -> void:
	var status := ResourceLoader.load_threaded_get_status(_loading)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return
	var path := _loading
	_loading = ""
	var texture: Texture2D = null
	if status != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE: texture = ResourceLoader.load_threaded_get(path) as Texture2D
	_arrive(path, texture)

func _arrive(path: String, texture: Texture2D) -> void:
	if texture != null: _kept[path] = texture
	for id: int in _waiting.get(path, []):
		var rect := instance_from_id(id) as TextureRect
		if not is_instance_valid(rect) or rect.texture != null or str(rect.get_meta(PATH_META, "")) != path: continue
		rect.texture = texture
		if texture == null or not rect.is_inside_tree(): continue
		rect.modulate.a = 0.0
		rect.create_tween().tween_property(rect, "modulate:a", 1.0, fade_seconds)
	_waiting.erase(path)

func _exit_tree() -> void:
	# Each request is collected once, so the loader lets its picture go. A load
	# still running finishes here: at most the rest of one picture's decode.
	if not _loading.is_empty(): ResourceLoader.load_threaded_get(_loading)
	_loading = ""
	_wanted.clear()
	_ahead.clear()
	_waiting.clear()

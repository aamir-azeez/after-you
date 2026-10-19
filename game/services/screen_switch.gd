extends Node
## Changes the screen (the tree's current scene) without the old screen's
## teardown holding the frame of the change.
##
## The engine's change removes the old screen from the tree at once and frees
## it whole at the end of that frame, together with the new screen's _ready:
## freeing Home's tree took about 6 ms of a chapter's opening frame on a
## desktop, and a chapter's about 12 ms of the frame back to Home. Here the
## change itself is the engine's, so the old screen leaves the tree exactly as
## before (its _exit_tree, tree_exiting and tree_exited run in the same place),
## and the new screen enters at the end of the frame as before. Only the old
## screen's nodes, already out of the tree, are handed to this node and freed
## a slice of each later frame, children before their parents, from the frame
## after the new screen has entered. Nothing out of the tree processes, draws
## or takes input meanwhile; the old screen's plain service nodes (neither
## drawn nor holding drawn nodes) are freed at the end of the frame as before,
## so none of them still answers a shared signal or timer.
##
## Home's scene is kept loaded for the session, so going back to Home never
## loads and compiles main.tscn again in the frame of the tap.
const NODE_NAME := "ScreenSwitch"
const SCRIPT_PATH := "res://services/screen_switch.gd"
const HOME_SCENE := "res://main.tscn"
## The wall time each frame spends freeing an old screen's nodes.
const FREE_SLICE_USEC := 2000

static var _home: PackedScene
## A switch node made while the root was busy waits for its deferred add.
static var _pending: WeakRef

## Nodes still to free, deepest last.
var _queue: Array = []
## Freeing waits for the new screen: armed once the tree says the scene has
## changed (after its _ready), and only from a later frame. A change made from
## input runs before the frame counter moves on, so the counter alone could
## not tell the change's frame apart.
var _armed := true
var _armed_frame := -1
## The frame of the last hand-over: a change the tree never reports still
## frees from a few frames on.
var _handed_frame := -1
const ARM_FRAMES := 3

## The engine's change_scene_to_packed; on success the old screen's nodes are
## freed over the next frames instead of at the end of this one.
static func to_packed(tree: SceneTree, packed: PackedScene) -> Error:
	var previous := tree.current_scene
	# Leaving Home keeps its scene, still loaded now, for the way back.
	if is_instance_valid(previous) and previous.scene_file_path == HOME_SCENE: home_scene()
	var result := tree.change_scene_to_packed(packed)
	if result == OK: release(previous)
	return result

## change_scene_to_file through to_packed. A scene that does not load is left
## to the engine's own call, which reports it as before.
static func to_file(tree: SceneTree, path: String) -> Error:
	var packed := home_scene() if path == HOME_SCENE else load(path) as PackedScene
	if packed == null: return tree.change_scene_to_file(path)
	return to_packed(tree, packed)

## Back to Home.
static func to_home(tree: SceneTree) -> Error:
	return to_file(tree, HOME_SCENE)

## Home's scene, loaded once a session.
static func home_scene() -> PackedScene:
	if _home == null: _home = load(HOME_SCENE) as PackedScene
	return _home

## Takes the nodes of a screen that has left the tree and frees them over the
## next frames. The screen itself is left as it is: the engine frees it at the
## end of this frame, with nothing under it by then.
static func release(screen: Node) -> void:
	if not is_instance_valid(screen) or screen.is_inside_tree() or screen.get_child_count() == 0: return
	var holder: Node = _instance()
	if holder == null: return
	for child: Node in screen.get_children():
		screen.remove_child(child)
		if _draws(child): holder._queue.append(child)
		else: child.queue_free()
	holder._armed = false
	holder._handed_frame = Engine.get_process_frames()
	var tree := Engine.get_main_loop() as SceneTree
	if not tree.scene_changed.is_connected(holder._arm): tree.scene_changed.connect(holder._arm, CONNECT_ONE_SHOT)
	holder.set_process(true)

## Whether node is drawn or holds drawn nodes: those are the bulk of a
## screen, freed over frames. Anything else is a small service node.
static func _draws(node: Node) -> bool:
	if node is Node3D or node is CanvasItem or node is CanvasLayer: return true
	for child: Node in node.get_children():
		if _draws(child): return true
	return false

## Nodes of old screens not freed yet.
static func pending_count() -> int:
	var holder: Node = _instance(false)
	return 0 if holder == null else holder._queue.size()

## Frees everything still waiting, at once.
static func flush() -> void:
	var holder: Node = _instance(false)
	if holder != null: holder._free_some(0)

static func _instance(create: bool = true) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null: return null
	var found := tree.root.get_node_or_null(NODE_NAME)
	if found != null and not found.is_queued_for_deletion(): return found
	if _pending != null:
		var waiting: Node = _pending.get_ref()
		if is_instance_valid(waiting) and not waiting.is_queued_for_deletion(): return waiting
	if not create: return null
	var holder: Node = load(SCRIPT_PATH).new()
	holder.name = NODE_NAME
	holder.process_mode = Node.PROCESS_MODE_ALWAYS
	holder.set_process(false)
	# The root is busy removing the scene that hands its nodes over.
	tree.root.add_child.call_deferred(holder)
	_pending = weakref(holder)
	return holder

func _ready() -> void:
	set_process(not _queue.is_empty())

func _arm() -> void:
	_armed = true
	_armed_frame = Engine.get_process_frames()

func _process(_delta: float) -> void:
	# Never in the frame of the change itself, which has the new screen's
	# _ready still to run.
	var frame := Engine.get_process_frames()
	if not _armed and frame > _handed_frame + ARM_FRAMES: _arm()
	if not _armed or frame == _armed_frame: return
	_free_some(FREE_SLICE_USEC)

## Frees nodes, children first, for up to budget_usec (all of them for 0).
func _free_some(budget_usec: int) -> void:
	var start := Time.get_ticks_usec()
	while not _queue.is_empty():
		var held: Variant = _queue.back()
		if not is_instance_valid(held):
			_queue.pop_back()
			continue
		var node := held as Node
		var count := node.get_child_count()
		if count > 0:
			_queue.append(node.get_child(count - 1))
			continue
		_queue.pop_back()
		node.free()
		if budget_usec > 0 and Time.get_ticks_usec() - start >= budget_usec: break
	if _queue.is_empty(): set_process(false)

func _notification(what: int) -> void:
	# At quit nothing waits for later frames.
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE: _free_some(0)

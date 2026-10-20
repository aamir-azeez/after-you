extends Node
## Lets go of session caches that hold GPU resources before the engine stops.
##
## A static var keeps its value until its script is freed, which happens after
## the renderer has shut down: a kept ArrayMesh freed then reads a server that
## is gone, and the process ends with 0xC0000005 although every check passed.
## A cache that keeps meshes registers its release here; this node lives under
## the root and calls every release when it leaves the tree, which the tree
## does for its whole root before the servers stop.
const NODE_NAME := "SessionRelease"
const SCRIPT_PATH := "res://presentation/kit/session_release.gd"

## Release callables, each registered once (a static function of a holder).
static var _releases: Array[Callable] = []
## A node made while the root was busy waits for its deferred add.
static var _pending: WeakRef

## Registers release to run when the tree shuts down. Safe to call often.
static func on_exit(release: Callable) -> void:
	if not release.is_valid(): return
	if not _releases.has(release): _releases.append(release)
	_instance()

## Runs every registered release now (the node does this at shutdown).
static func release_all() -> void:
	for release: Callable in _releases:
		if release.is_valid(): release.call()

static func _instance() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null: return null
	var found := tree.root.get_node_or_null(NODE_NAME)
	if found != null and not found.is_queued_for_deletion(): return found
	if _pending != null:
		var waiting: Node = _pending.get_ref()
		if is_instance_valid(waiting) and not waiting.is_queued_for_deletion(): return waiting
	var node: Node = load(SCRIPT_PATH).new()
	node.name = NODE_NAME
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	# The root may be busy adding or removing the scene that keeps a mesh.
	tree.root.add_child.call_deferred(node)
	_pending = weakref(node)
	return node

func _notification(what: int) -> void:
	# Leaving the tree only happens at shutdown.
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		release_all()

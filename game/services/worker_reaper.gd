extends Node
## Joins background threads whose owner has gone, without holding a frame.
##
## Rule for every worker in this project: always join a worker before its
## owner is freed; never join through a self method in a RefCounted
## PREDELETE; read your own fields instead. The chapter rules themselves are
## safe to run on a worker while the main thread runs the same chapter.
##
## An owner that leaves while its worker still runs asks the worker to stop
## (when it can), then hands the Thread here. This node joins each one once it
## has finished, and joins whatever is left when it leaves the tree itself, so
## no worker outlives the scripts it runs. It lives under the root, so a scene
## change never frees it.
const NODE_NAME := "WorkerReaper"
const SCRIPT_PATH := "res://services/worker_reaper.gd"

var _threads: Array[Thread] = []
## A reaper made while the root was busy waits for its deferred add; later
## hand-overs in that frame find it here.
static var _pending: WeakRef

## Takes ownership of a started thread and joins it once it ends. Without a
## scene tree to live in, joins it at once.
static func adopt(thread: Thread) -> void:
	if thread == null or not thread.is_started(): return
	var reaper: Variant = _instance()
	if reaper == null:
		thread.wait_to_finish()
		return
	reaper._threads.append(thread)
	reaper.set_process(true)

## Threads handed over and not joined yet.
static func pending_count() -> int:
	var reaper: Variant = _instance(false)
	return 0 if reaper == null else reaper._threads.size()

static func _instance(create: bool = true) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null: return null
	var found := tree.root.get_node_or_null(NODE_NAME)
	if found != null and not found.is_queued_for_deletion(): return found
	if _pending != null:
		var waiting: Node = _pending.get_ref()
		if is_instance_valid(waiting) and not waiting.is_queued_for_deletion(): return waiting
	if not create: return null
	var reaper: Node = load(SCRIPT_PATH).new()
	reaper.name = NODE_NAME
	reaper.process_mode = Node.PROCESS_MODE_ALWAYS
	# The root may be busy removing the scene that hands a thread over.
	tree.root.add_child.call_deferred(reaper)
	_pending = weakref(reaper)
	return reaper

func _process(_delta: float) -> void:
	var index := _threads.size() - 1
	while index >= 0:
		var thread: Thread = _threads[index]
		if not thread.is_alive():
			thread.wait_to_finish()
			_threads.remove_at(index)
		index -= 1
	if _threads.is_empty(): set_process(false)

func _notification(what: int) -> void:
	# Leaving the tree only happens at shutdown; blocking is acceptable there.
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		for thread: Thread in _threads:
			if thread.is_started(): thread.wait_to_finish()
		_threads.clear()

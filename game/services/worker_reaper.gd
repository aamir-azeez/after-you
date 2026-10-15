extends Node
## Joins background threads whose owner has gone, without holding a frame.
##
## Every worker in this project is started one of two ways:
## - Awaited work (start it, wait for its result): `await run(work)`. The
##   reaper owns the thread from its start, so a caller dropped mid-job (its
##   owner freed, the app quitting) never destroys it while it runs. Never
##   keep such a Thread in a local and await it by hand.
## - A worker held in a field and polled: call ensure() before starting it,
##   join it with wait_to_finish() once it has ended, and hand it to adopt()
##   if the owner leaves first (asking it to stop when it can). Never join
##   through a self method in a RefCounted PREDELETE; read your own fields.
## The chapter rules themselves are safe to run on a worker while the main
## thread runs the same chapter.
##
## This node joins each handed-over thread once it has finished, and joins
## whatever is left when it leaves the tree itself, so no worker outlives the
## scripts it runs. It lives under the root, so a scene change never frees it.
const NODE_NAME := "WorkerReaper"
const SCRIPT_PATH := "res://services/worker_reaper.gd"

var _threads: Array[Thread] = []
## A reaper made while the root was busy waits for its deferred add; later
## hand-overs in that frame find it here.
static var _pending: WeakRef

## Owners call this when they start a worker, so the reaper is already in the
## tree by the time one might be handed over. At quit the tree tears down
## without running deferred calls; a reaper made only then would never be
## added or freed, and its threads never joined.
static func ensure() -> void:
	_instance()

## Takes ownership of a started thread and joins it once it ends. With no
## reaper set up by ensure(), joins it at once instead, as owners did before.
static func adopt(thread: Thread) -> void:
	if thread == null or not thread.is_started(): return
	var reaper: Variant = _instance(false)
	if reaper == null:
		thread.wait_to_finish()
		return
	reaper._threads.append(thread)
	reaper.set_process(true)

## Runs work on a worker the reaper owns from its start, and returns work's
## result once it ends, waiting a frame at a time. Await it. work must be safe
## on a worker (a static function and private copies). Whatever happens to the
## caller meanwhile (its owner freed, its coroutine dropped, the app quitting),
## the worker is joined by the reaper, never destroyed while it runs; a thread
## kept only in a waiting coroutine was destroyed mid-job (a crash at exit).
## With no tree, or no thread to start, it returns null without running work,
## unless here_if_unavailable asks to run it on this thread instead.
static func run(work: Callable, here_if_unavailable: bool = false) -> Variant:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or _instance() == null: return work.call() if here_if_unavailable else null
	var result := Result.new()
	var thread := Thread.new()
	if thread.start(Callable(load(SCRIPT_PATH), "_run_into").bind(work, result)) != OK: return work.call() if here_if_unavailable else null
	adopt(thread)
	while thread.is_alive(): await tree.process_frame
	return result.value()

## What a run's worker returned, read once it has ended.
class Result extends RefCounted:
	var _mutex := Mutex.new()
	var _value: Variant = null
	func store(value: Variant) -> void:
		_mutex.lock()
		_value = value
		_mutex.unlock()
	func value() -> Variant:
		_mutex.lock()
		var held: Variant = _value
		_mutex.unlock()
		return held

static func _run_into(work: Callable, result: Result) -> void:
	result.store(work.call())

## Threads handed over and not joined yet.
static func pending_count() -> int:
	var reaper: Variant = _instance(false)
	return 0 if reaper == null else reaper._threads.size()

## True while this thread is handed over and not joined yet.
static func holds(thread: Thread) -> bool:
	var reaper: Variant = _instance(false)
	return reaper != null and reaper._threads.has(thread)

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

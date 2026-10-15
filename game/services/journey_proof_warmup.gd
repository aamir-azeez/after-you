extends Node
## Proves saved solo journeys ahead of time, on one worker, while the player
## is idle at Home, so that opening such a chapter later finds its proof
## remembered (journey_proofs.gd) instead of replaying its turns.
##
## - Starts once Home has been idle for IDLE_SECONDS; nothing runs on the main
##   thread but the start and the join.
## - Asks the worker to stop, between stages, when the app goes to the
##   background or the owner calls stop() (a chapter is opening). Work it
##   already finished stays remembered; an open replays only what is left.
## - Joins its worker once it ends. Leaving the tree hands a running worker
##   to the shared reaper (worker_reaper.gd), never waits for it.
## - Never writes a journal and never reports an error: a save it cannot prove
##   is checked in full when it is opened, exactly as before.
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Proofs = preload("res://services/journey_proofs.gd")
const Reaper = preload("res://services/worker_reaper.gd")
const IDLE_SECONDS := 2.0
const MAX_SAVE_BYTES := 1048576

## Shared with the worker: a stop request, and what it has done.
class Run extends "res://services/stop_request.gd":
	var _results: Array = []
	func record(result: String) -> void:
		_mutex.lock()
		_results.append(result)
		_mutex.unlock()
	func results() -> Array:
		_mutex.lock()
		var copy := _results.duplicate()
		_mutex.unlock()
		return copy

## True while Home is shown and idle; set by the owner.
var idle: Callable
var _idle_for := 0.0
var _thread: Thread
var _run: Run
var _finished := false
var _backgrounded := false
## Overridable for tests: [{chapter, path}] of the saves to prove.
var sources: Array = []
## What the last finished run did, one entry per saved generation.
var last_results: Array = []


func _ready() -> void:
	if sources.is_empty(): sources = default_sources()

## Every solo chapter whose rules can be proved stage by stage.
static func default_sources() -> Array:
	var result: Array = []
	for chapter: String in Registry.keys():
		if not Proofs._runtime_family(Registry.simulation_script(chapter)): continue
		var path := str(Registry.descriptor(chapter).get("local_path", ""))
		if not path.is_empty(): result.append({"chapter": chapter, "path": path})
	return result

## True while a worker runs.
func running() -> bool:
	return _thread != null

## Asks a running worker to stop after its current stage. It is joined when
## it ends; a later idle Home starts again for what is left.
func stop() -> void:
	_idle_for = 0.0
	if _run != null: _run.stop()

## Starts the worker now. False when one already runs or this run is done.
func start() -> bool:
	if _thread != null or _finished or _backgrounded: return false
	_run = Run.new()
	# Joined by _process once it ends, or by the reaper after a leave.
	Reaper.ensure()
	var thread := Thread.new()
	# A static function and private copies: no node crosses to the worker.
	if thread.start(Callable(get_script(), "_work").bind(sources.duplicate(true), _run)) != OK:
		_run = null
		return false
	_thread = thread
	return true

func _process(delta: float) -> void:
	if _thread != null:
		if not _thread.is_alive():
			_thread.wait_to_finish()
			_thread = null
			last_results = _run.results()
			# A run that was asked to stop is resumed by a later idle Home.
			_finished = not _run.stopped()
			_run = null
		return
	if _finished or _backgrounded or not idle.is_valid() or not idle.call():
		_idle_for = 0.0
		return
	_idle_for += delta
	if _idle_for >= IDLE_SECONDS: start()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_backgrounded = true
		stop()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_backgrounded = false

func _exit_tree() -> void:
	# Never wait here: the worker stops after its stage and the reaper joins it.
	if _thread != null:
		_run.stop()
		Reaper.adopt(_thread)
		_thread = null
		_run = null


## The worker. Reads each saved generation itself and proves it with a
## private validator; only remembered proofs are shared.
static func _work(saves: Array, run: Run) -> void:
	var cancelled := Callable(run, "stopped")
	for source: Dictionary in saves:
		var chapter := str(source.chapter)
		var path := str(source.path)
		var validator: RefCounted = null
		for suffix: String in ["", ".tmp", ".backup"]:
			if run.stopped(): return
			var state: Variant = _read(path + suffix)
			if state == null: continue
			if validator == null: validator = Journey.new(path, null, chapter)
			run.record("%s%s: %s" % [chapter, suffix, Proofs.warm(validator, state, cancelled)])

static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return null
	if file.get_length() < 1 or file.get_length() > MAX_SAVE_BYTES:
		file.close()
		return null
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary: return null
	var relay: Variant = json.data.get("relay")
	return relay if relay is Dictionary else null

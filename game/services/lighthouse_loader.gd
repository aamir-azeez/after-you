class_name LighthouseLoader
extends RefCounted
## Main-thread owner for one replay-verifying journal load: the solo
## Lighthouse journal (@1), or a registry chapter's RelayJourney with more than
## two stages (@2 in the shared chapter screen). One loader per screen. After start succeeds the caller
## must stop reading/writing the journal until take_result or finish joins it.
## Cancellation discards the result; it never interrupts verification or rolls
## back normal LocalSave recovery. No SceneTree callback or network work runs.

const Journey = preload("res://services/lighthouse_journey.gd")
const RelayJourney = preload("res://services/relay_journey.gd")

var _thread: Thread
var _journal: RefCounted
var _cancelled := false
## What the optional preparation step returned (see start), once joined.
var prepared: Variant = null


## `prepare`, when given, runs on the same worker before the load (a
## worker-safe static Callable with no node); its result is `prepared`.
func start(journal: RefCounted, prepare: Callable = Callable()) -> Error:
	if not Thread.is_main_thread():
		return ERR_UNAUTHORIZED
	if busy():
		return ERR_BUSY
	if journal == null or not (journal is Journey or journal is RelayJourney):
		return ERR_INVALID_PARAMETER
	_journal = journal
	_cancelled = false
	prepared = null
	# Joined by take_result or finish, or in PREDELETE from its own fields
	# (never through a self method there).
	_thread = Thread.new()
	# Bind only the RefCounted journal: no loader reference cycle and no Node.
	# Godot's default thread-safety checks remain enabled.
	var result := _thread.start(journal.load_data) if not prepare.is_valid() else _thread.start(Callable(get_script(), "_prepare_then_load").bind(journal, prepare))
	if result != OK:
		_thread = null
		_journal = null
		return result
	return OK


static func _prepare_then_load(journal: RefCounted, prepare: Callable) -> Variant:
	var result: Variant = prepare.call()
	journal.load_data()
	return result


func busy() -> bool:
	return _thread != null and _thread.is_started()


func ready() -> bool:
	return busy() and not _thread.is_alive()


func cancel() -> void:
	# Main-thread state only; the worker never consults this flag.
	if busy():
		_cancelled = true


func take_result() -> RefCounted:
	if not ready():
		return null
	prepared = _thread.wait_to_finish()
	var result: RefCounted = null if _cancelled else _journal
	_thread = null
	_journal = null
	_cancelled = false
	return result


func finish() -> void:
	# Exit cleanup may block until bounded verification finishes. Normal Back
	# cancels, keeps polling ready, and joins before leaving the owning UI.
	_cancelled = true
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	_journal = null
	_cancelled = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# A RefCounted's reference count is already zero here. Calling another
		# method on self is rejected by GDScript even though this notification's
		# fields are still valid, so join directly instead of calling finish().
		if _thread != null and _thread.is_started():
			_thread.wait_to_finish()
		_thread = null
		_journal = null

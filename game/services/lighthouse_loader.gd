class_name LighthouseLoader
extends RefCounted
## Main-thread owner for one replay-verifying journal load.
## One loader may be active per Lighthouse UI. After start succeeds the caller
## must stop reading/writing the journal until take_result or finish joins it.
## Cancellation discards the result; it never interrupts verification or rolls
## back normal LocalSave recovery. No SceneTree callback or network work runs.

const Journey = preload("res://services/lighthouse_journey.gd")

var _thread: Thread
var _journal: RefCounted
var _cancelled := false


func start(journal: RefCounted) -> Error:
	if not Thread.is_main_thread():
		return ERR_UNAUTHORIZED
	if busy():
		return ERR_BUSY
	if journal == null or not journal is Journey:
		return ERR_INVALID_PARAMETER
	_journal = journal
	_cancelled = false
	_thread = Thread.new()
	# Bind only the RefCounted journal: no loader reference cycle and no Node.
	# Godot's default thread-safety checks remain enabled.
	var result := _thread.start(journal.load_data)
	if result != OK:
		_thread = null
		_journal = null
		return result
	return OK


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
	_thread.wait_to_finish()
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

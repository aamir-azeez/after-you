extends RefCounted
## The app's one request slot, as a queue. Requests run one at a time in the
## order they were asked for, exactly as on the wire before; a caller that asks
## while another request is out waits its turn instead of being refused.
##
## - Each entry may carry `still`, the caller's own check of its screen or
##   state. When the entry reaches the front and `still` no longer holds, it
##   is skipped and its caller gets a "request_cancelled" result.
## - A read (`coalesce` key, given by RoomsApi to GETs) that matches one still
##   waiting joins it: both callers get the one reply, so a slow network never
##   builds a backlog of polls. It is skipped only when every caller's check fails.
## - At most MAX_WAITING entries wait; one more is refused with
##   "request_queue_full".
## - A failed or timed out request ends its turn like any other, so it never
##   blocks the ones behind it. If the owner of the work is freed mid-request
##   (the app quits), the callers behind it are never resumed, as before.
##
## Callers never look at this queue to decide anything; RoomsApi owns it.

const MAX_WAITING := 16
const CANCELLED := "request_cancelled"
const FULL := "request_queue_full"

class Entry extends RefCounted:
	signal finished
	var work: Callable
	var refused: Callable
	var key := ""
	var checks: Array[Callable] = []
	var done := false
	var result: Dictionary = {}

	## True while any caller still wants this entry. A caller with no check
	## always does; one whose check's owner was freed no longer does.
	func wanted() -> bool:
		for check: Callable in checks:
			if check.is_null(): return true
			if check.is_valid() and check.call(): return true
		return false

	func finish(value: Dictionary) -> void:
		done = true
		result = value
		finished.emit()

var _waiting: Array[Entry] = []
var _running: Entry = null
var _pumping := false

## Runs `work` (a coroutine returning the reply Dictionary) in its turn and
## returns its reply. `refused` builds the reply for a skipped or refused entry
## from its code ("request_cancelled" or "request_queue_full").
func run(work: Callable, refused: Callable, still: Callable = Callable(), coalesce: String = "") -> Dictionary:
	if not coalesce.is_empty():
		for waiting: Entry in _waiting:
			if waiting.key != coalesce: continue
			waiting.checks.append(still)
			return await _result_of(waiting)
	if _waiting.size() >= MAX_WAITING: return refused.call(FULL)
	var entry := Entry.new()
	entry.work = work
	entry.key = coalesce
	entry.checks.append(still)
	entry.refused = refused
	_waiting.append(entry)
	_pump()
	return await _result_of(entry)

## True while a request is out or waiting. For tests and diagnostics only.
func busy() -> bool:
	return _running != null or not _waiting.is_empty()

func waiting_count() -> int:
	return _waiting.size()

func _result_of(entry: Entry) -> Dictionary:
	# The pump may finish an entry before its caller awaits (a skipped entry at the front).
	if not entry.done: await entry.finished
	return entry.result.duplicate(true)

func _pump() -> void:
	if _pumping: return
	_pumping = true
	while not _waiting.is_empty():
		var entry: Entry = _waiting.pop_front()
		if not entry.wanted():
			entry.finish(entry.refused.call(CANCELLED))
			continue
		_running = entry
		var value: Variant = await entry.work.call()
		_running = null
		entry.finish(value if value is Dictionary else entry.refused.call("connection_interrupted"))
	_pumping = false

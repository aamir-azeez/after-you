class_name RefreshSchedule
extends RefCounted
## Pure foreground polling clock. Controllers own all requests and UI changes.
## Supply a monotonic clock and an identity/epoch/resource context key. A token
## never authorizes a POST or application of data to an unsafe screen.

const ROOM_INTERVAL_MS := 3000
const LOBBY_INTERVAL_MS := 10000
const FAILURE_DELAYS_MS := [5000, 15000, 30000]

var _context := ""
var _generation := 0
var _serial := 0
var _interval := ROOM_INTERVAL_MS
var _due := 0
var _cooldown_until := 0
var _last_now := 0
var _failure_count := 0
var _terminal := false
var _active: Dictionary = {}


func bind(context_key: String, now_ms: int, interval_ms: int = ROOM_INTERVAL_MS) -> void:
	var now := _now(now_ms)
	var interval := maxi(1, interval_ms)
	if context_key == _context and interval == _interval:
		return
	_context = context_key
	_interval = interval
	_generation += 1
	_failure_count = 0
	_terminal = false
	_due = now + _interval
	# An old request still occupies the transport. Its exact completion releases
	# the slot, but cannot schedule or validate data for this new context.
	# Provider Retry-After also survives switching rooms on the same scheduler.


func request_now(now_ms: int) -> bool:
	var now := _now(now_ms)
	if _context.is_empty() or _terminal:
		return false
	# Multiple manual/resume signals for the currently running read are served
	# by that one read. A changed context may queue a read behind the old one.
	if not _active.is_empty() and _active.generation == _generation:
		return false
	_due = mini(_due, now)
	return true


func begin_if_due(now_ms: int, eligible: bool, transport_busy: bool) -> Dictionary:
	var now := _now(now_ms)
	if not eligible or transport_busy or busy() or stopped() or now < next_due_ms():
		return {}
	_serial += 1
	_active = {"serial": _serial, "generation": _generation}
	return _active.duplicate()


func complete(token: Dictionary, now_ms: int, success: bool, retry_after_ms: int = 0, terminal: bool = false) -> bool:
	var now := _now(now_ms)
	if _active.is_empty() or token != _active:
		return false
	var current: bool = int(_active.generation) == _generation and not _context.is_empty()
	_active = {}
	_cooldown_until = maxi(_cooldown_until, now + maxi(0, retry_after_ms))
	if not current:
		return false
	_terminal = terminal
	if success:
		_failure_count = 0
		_due = now + _interval
	else:
		_failure_count = mini(_failure_count + 1, FAILURE_DELAYS_MS.size())
		_due = now + int(FAILURE_DELAYS_MS[_failure_count - 1])
	return true


func busy() -> bool:
	return not _active.is_empty()


func stopped() -> bool:
	return _context.is_empty() or _terminal


func next_due_ms() -> int:
	return maxi(_due, _cooldown_until)


func _now(value: int) -> int:
	# A caller clock regression cannot pull a scheduled request into the past.
	_last_now = maxi(_last_now, maxi(0, value))
	return _last_now

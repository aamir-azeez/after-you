extends Node
## The one capabilities read the app keeps for Home and its menu screens: what
## the server has on for this player (the Wardrobe, the store, Pollen, Fruits,
## Duels) reaches the shared stores through it, so every button that waits on
## the server reads the same answer.
##
## It reads once the signed-in player is known (identity_ready), and again when
## the app comes back to the front, at most once every RESUME_GAP_MS while the
## last read worked, so a server switch reaches a phone without a restart. A
## read that fails goes again on RETRY_MS (2, 5, 15, 30 seconds, then every
## minute), only while the app is in front. While the phone reads as offline
## (services/connectivity.gd) its own retries wait: the probe asks the server
## then, and the phone coming back online reads at once.
##
## Before the first answer of a run everything shows as if it works (pending);
## a tap then waits for the read out (until_read, at most TAP_WAIT_MS). The
## greying itself stays services/connectivity.gd's (presentation/offline_hold.gd).
##
## Main sets `read` (() -> Variant, awaited: true answered, false failed, null
## not now, as while the room session is busy) and `may_read` (() -> bool: the
## screen up lets a read run). Tests set `clock` (() -> ms) and call tick().
const Connectivity = preload("res://services/connectivity.gd")

signal changed

## Waits after a failed read, the last repeating.
const RETRY_MS := [2000, 5000, 15000, 30000, 60000]
## A read not wanted now (busy, another screen) is asked for again after this.
const NOT_NOW_MS := 2000
## Coming back to the front reads again once the last good read is this old.
const RESUME_GAP_MS := 300000
## How long a tap waits for a read out before it goes on without one.
const TAP_WAIT_MS := 4000

var read: Callable
var may_read: Callable
var clock: Callable
var _reading := false
var _ready_to_read := false
var _last_ok_ms := -1
var _failures := 0
## When the next read is due (ms), or -1 for none.
var _due_ms := -1
var _foreground := true
## The player the reads are for (identity_ready).
var _player := ""

func _ready() -> void:
	var state: RefCounted = Connectivity.shared()
	if not state.changed.is_connected(_on_connectivity): state.changed.connect(_on_connectivity)
	_update()

func _exit_tree() -> void:
	var state: RefCounted = Connectivity.shared()
	if state.changed.is_connected(_on_connectivity): state.changed.disconnect(_on_connectivity)

## Whether a read answered in this run.
func known() -> bool:
	return _last_ok_ms >= 0

## Before the first answer of this run, while one can still come: buttons show as if they work.
func pending() -> bool:
	return not known() and _ready_to_read

## Reads failed in a row.
func failures() -> int:
	return _failures

func reading() -> bool:
	return _reading

## The signed-in player is known: a read now, once per player (`key` names them).
func identity_ready(key: String) -> void:
	if _ready_to_read and key == _player: return
	_player = key
	_ready_to_read = true
	_last_ok_ms = -1
	_failures = 0
	_ask(_now())

## A tap before the first answer: waits for the read out (one starts if none
## is), at most TAP_WAIT_MS. True once the server has answered in this run.
func until_read() -> bool:
	if known() or not _ready_to_read: return known()
	if not _reading: await read_now()
	var tree := get_tree()
	var started := _now()
	while _reading and tree != null and _now() - started < TAP_WAIT_MS: await tree.process_frame
	return known()

## One read now, unless one is out already.
func read_now() -> void:
	if _reading or not read.is_valid() or not _ready_to_read: return
	_due_ms = -1
	_reading = true
	_update()
	var answer: Variant = await read.call()
	_reading = false
	if answer == null:
		_ask(_now() + NOT_NOW_MS)
		return
	if bool(answer):
		_failures = 0
		_last_ok_ms = _now()
	else:
		_failures += 1
		_ask(_now() + int(RETRY_MS[mini(_failures - 1, RETRY_MS.size() - 1)]))
	_update()
	changed.emit()

func _ask(at_ms: int) -> void:
	if not _ready_to_read: return
	_due_ms = at_ms if _due_ms < 0 else mini(_due_ms, at_ms)
	_update()

func _on_connectivity(online: bool) -> void:
	# Back online: a read that failed, or never ran, goes now.
	if online and _ready_to_read and not known(): _ask(_now())

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_foreground = false
		_update()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_foreground = true
		resumed()

## Back in front: a read once the last good one is old enough, or at once after a failure.
func resumed() -> void:
	_foreground = true
	if not _ready_to_read: return
	if not known() or _now() - _last_ok_ms >= RESUME_GAP_MS: _ask(_now())
	_update()

func _update() -> void:
	set_process(_foreground and _due_ms >= 0 and not _reading)

func _process(_delta: float) -> void:
	tick()

## Runs a read that is due while the app is in front, online and on a screen that lets it.
func tick() -> void:
	if _reading or _due_ms < 0 or not _foreground or _now() < _due_ms: return
	if not Connectivity.shared().online() and _failures > 0: return
	if may_read.is_valid() and not bool(may_read.call()): return
	read_now()

func _now() -> int:
	return int(clock.call()) if clock.is_valid() else Time.get_ticks_msec()

extends RefCounted
## Whether this phone reaches the server: the one online/offline answer every
## screen asks before it offers something that needs the server.
##
## It learns only from traffic the app already makes, never from a polling loop:
## - every answer of Main's RoomsApi (note_response): an HTTP status of any kind
##   means the server was reached; a request that could not connect, resolve,
##   finish its TLS handshake or got no answer before its timeout did not;
## - the live socket opening (note_reached, LiveConnection.health_changed);
## - AppStatus's own check, and the probe (services/connectivity_probe.gd),
##   which asks only while this says offline and the app is in front.
##
## States: unknown (the launch, before any answer), online and offline. Unknown
## reads as online, so the first tap after launch always registers. Going
## offline is debounced: it takes OFFLINE_AFTER failures in a row with no
## answer between them, so one dropped request never greys anything. Coming back
## is immediate: the first answer of any kind, or the live socket opening.
## `changed` fires only when online() flips.
##
## Tests and captures install their own (use_shared) or force a state (force).
signal changed(online: bool)

enum State { UNKNOWN, ONLINE, OFFLINE }

## Failures in a row before the phone reads as offline.
const OFFLINE_AFTER := 2
## Engine results that mean the server was never reached (HTTPRequest.Result).
const UNREACHED := [HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CONNECTION_ERROR,
	HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR, HTTPRequest.RESULT_TIMEOUT]

static var _shared: RefCounted = null

var state := State.UNKNOWN
var _failures := 0
## () -> void: asks the server once (services/connectivity_probe.gd sets it while Main is up).
var probe: Callable

static func shared() -> RefCounted:
	if _shared == null: _shared = load("res://services/connectivity.gd").new()
	return _shared

## Installs one as the shared one (tests, captures), or clears it with null.
static func use_shared(value: RefCounted) -> void:
	_shared = value

## False only once requests have kept failing to reach the server.
func online() -> bool:
	return state != State.OFFLINE

## One HTTP exchange as HTTPRequest reports it ([result, status, headers, body]).
## [] (a request that could not start, or a test transport) says nothing.
func note_response(response: Array) -> void:
	if response.size() < 2: return
	if int(response[0]) == HTTPRequest.RESULT_SUCCESS and int(response[1]) > 0: note_reached()
	elif int(response[0]) in UNREACHED: note_unreached()

## The server answered (any status) or the live socket opened.
func note_reached() -> void:
	_failures = 0
	_move_to(State.ONLINE)

## A request did not reach the server.
func note_unreached() -> void:
	_failures += 1
	if _failures >= OFFLINE_AFTER: _move_to(State.OFFLINE)

## Asks the server now while offline (a tap on something greyed, the app back
## in front). The answer arrives through note_response.
func check_now() -> void:
	if not online() and probe.is_valid(): probe.call()

## Tests and captures: a state as if the server had answered (true) or not (false).
func force(value: bool) -> void:
	_failures = 0 if value else OFFLINE_AFTER
	_move_to(State.ONLINE if value else State.OFFLINE)

func _move_to(next: State) -> void:
	var was := online()
	state = next
	if online() != was: changed.emit(online())

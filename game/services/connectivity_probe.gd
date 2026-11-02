extends Node
## Finds out when the phone reaches the server again, so what was greyed
## offline comes back on its own (services/connectivity.gd).
##
## It runs only while the phone reads as offline and the app is in front: no
## frame work at all otherwise, so nothing polls while online, idle in solo
## play with a connection, or in the background. While it runs it asks
## GET /v1/app-status (public, no identity, no Durable Object) on its own
## HTTPRequest, never through RoomsApi's one request slot, on RefreshSchedule's
## failure pace (5, 15, then every 30 seconds). A tap on something greyed and
## the app coming back to the front ask at once (probe_now). The first answer of
## any kind reads as online and it stops.
const Connectivity = preload("res://services/connectivity.gd")
const RefreshScheduleScript = preload("res://services/refresh_schedule.gd")
const AppStatus = preload("res://services/app_status.gd")
const TIMEOUT_SECONDS := 6.0
## The first ask after going offline.
const FIRST_MS := 5000

var base_url := ""
## Whether base_url may be used (RoomsApi.configured()); without it nothing is asked.
var configured := false
## Tests: transport(url) -> [result, status, headers, body]; clock() -> ms.
var transport: Callable
var clock: Callable
var _schedule: RefCounted = RefreshScheduleScript.new()
var _round := 0
var _foreground := true

func _ready() -> void:
	var state: RefCounted = Connectivity.shared()
	state.probe = probe_now
	if not state.changed.is_connected(_on_changed): state.changed.connect(_on_changed)
	_on_changed(state.online())

func _exit_tree() -> void:
	var state: RefCounted = Connectivity.shared()
	if state.changed.is_connected(_on_changed): state.changed.disconnect(_on_changed)
	if state.probe == probe_now: state.probe = Callable()

## Whether frames run now: only while offline, in front and able to ask.
func active() -> bool:
	return is_processing()

## Asks on the next frame (a tap on something greyed, the app back in front).
func probe_now() -> void:
	if Connectivity.shared().online() or not configured: return
	_schedule.request_now(_now())
	_update()

func _on_changed(online: bool) -> void:
	if not online:
		_round += 1
		_schedule.bind("offline-%d" % _round, _now(), FIRST_MS)
	_update()

func _update() -> void:
	set_process(configured and _foreground and not Connectivity.shared().online())

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_foreground = false
		_update()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_foreground = true
		probe_now()
		_update()

func _process(_delta: float) -> void:
	var token: Dictionary = _schedule.begin_if_due(_now(), true, false)
	if token.is_empty(): return
	var response: Array = await _send(base_url.trim_suffix("/") + AppStatus.PATH)
	if not is_inside_tree(): return
	Connectivity.shared().note_response(response)
	_schedule.complete(token, _now(), Connectivity.shared().online())
	_update()

func _send(url: String) -> Array:
	if transport.is_valid(): return await transport.call(url)
	var request := HTTPRequest.new()
	request.timeout = TIMEOUT_SECONDS
	request.body_size_limit = AppStatus.BODY_LIMIT
	add_child(request)
	if request.request(url, PackedStringArray(), HTTPClient.METHOD_GET) != OK:
		request.queue_free()
		return []
	var response: Array = await request.request_completed
	request.queue_free()
	return response

func _now() -> int:
	return int(clock.call()) if clock.is_valid() else Time.get_ticks_msec()

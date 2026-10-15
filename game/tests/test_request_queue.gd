extends SceneTree
## services/request_queue.gd and RoomsApi on top of it: one request at a time in
## the order asked, polls that share a turn, entries skipped when their caller
## moved on, a bounded wait list, and no deadlock when a request fails.
const RequestQueue = preload("res://services/request_queue.gd")
const RoomsApi = preload("res://services/rooms_api.gd")

## Work that finishes only when released, so a test decides when each reply lands.
class Held extends RefCounted:
	signal released
	var name := ""
	var log: Array
	var reply: Variant
	func _init(value: String, into: Array, answer: Variant = null) -> void:
		name = value
		log = into
		reply = answer if answer != null else {"ok": true, "name": value}
	func work() -> Variant:
		log.append("start " + name)
		await released
		log.append("end " + name)
		return reply

## A caller object whose check outlives it.
class Owner extends Object:
	func wants() -> bool: return true

## A RoomsApi whose exchange waits for the test, like the online harness device.
class Api extends RoomsApi:
	signal answer
	var sent: Array = []
	func _ready() -> void: base_url = "https://queue.test"
	func _send(method: int, path: String, headers: PackedStringArray, _body: String) -> Array:
		sent.append({"method": method, "path": path, "headers": headers})
		await answer
		return [HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"path": path}).to_utf8_buffer()]

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)

static func refused(code: String) -> Dictionary: return {"ok": false, "code": code}

func _run() -> void:
	await _order()
	await _coalesce()
	await _cancel()
	await _failures()
	await _full()
	await _rooms_api()
	print("REQUEST QUEUE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Collects a run's reply once it lands.
func _start(queue: RequestQueue, work: Callable, into: Dictionary, name: String, still: Callable = Callable(), key: String = "") -> void:
	into[name] = await queue.run(work, refused, still, key)

func _order() -> void:
	var queue := RequestQueue.new()
	var log: Array = []
	var replies := {}
	var a := Held.new("a", log)
	var b := Held.new("b", log)
	var c := Held.new("c", log)
	_start(queue, a.work, replies, "a")
	_start(queue, b.work, replies, "b")
	_start(queue, c.work, replies, "c")
	_check(log == ["start a"], "Only the first request goes out while it is out: %s" % [log])
	a.released.emit()
	_check(log == ["start a", "end a", "start b"], "The second starts right after the first lands, never alongside: %s" % [log])
	b.released.emit()
	c.released.emit()
	_check(log == ["start a", "end a", "start b", "end b", "start c", "end c"], "Requests run in the order asked: %s" % [log])
	_check(replies.get("a", {}).get("name") == "a" and replies.get("c", {}).get("name") == "c", "Each caller gets its own reply")
	_check(not queue.busy(), "The queue is idle once every request landed")

func _coalesce() -> void:
	var queue := RequestQueue.new()
	var log: Array = []
	var replies := {}
	var first := Held.new("first", log)
	var poll := Held.new("poll", log)
	var again := Held.new("again", log)
	_start(queue, first.work, replies, "first")
	_start(queue, poll.work, replies, "poll", Callable(), "GET /v1/room-inbox")
	_start(queue, again.work, replies, "again", Callable(), "GET /v1/room-inbox")
	_check(queue.waiting_count() == 1, "A second identical poll joins the one already waiting instead of queueing")
	first.released.emit()
	poll.released.emit()
	_check(log.count("start poll") == 1 and not log.has("start again"), "The shared poll goes out once: %s" % [log])
	_check(replies.get("poll", {}).get("name") == "poll" and replies.get("again", {}).get("name") == "poll", "Both callers get that one reply")
	replies.poll.name = "changed"
	_check(replies.again.name == "poll", "Each caller gets its own copy of the shared reply")
	# A poll that is already out is not joined: a later one may see newer data.
	log.clear()
	var out := Held.new("out", log)
	var later := Held.new("later", log)
	_start(queue, out.work, replies, "out", Callable(), "GET /v2/rooms/x")
	_start(queue, later.work, replies, "later", Callable(), "GET /v2/rooms/x")
	out.released.emit()
	later.released.emit()
	_check(log == ["start out", "end out", "start later", "end later"], "A poll asked while the same one is out runs after it: %s" % [log])
	# A shared poll still runs while any of its callers wants it.
	log.clear()
	var hold := Held.new("hold", log)
	var shared := Held.new("shared", log)
	var stale := [false]
	_start(queue, hold.work, replies, "hold")
	_start(queue, shared.work, replies, "shared", func() -> bool: return not stale[0], "GET /v1/friends")
	_start(queue, Held.new("unused", log).work, replies, "kept", Callable(), "GET /v1/friends")
	stale[0] = true
	hold.released.emit()
	shared.released.emit()
	_check(log.has("start shared") and replies.get("kept", {}).get("name") == "shared", "A shared poll runs while one caller still wants it")

func _cancel() -> void:
	var queue := RequestQueue.new()
	var log: Array = []
	var replies := {}
	var a := Held.new("a", log)
	var b := Held.new("b", log)
	var c := Held.new("c", log)
	var moved_on := [false]
	_start(queue, a.work, replies, "a")
	_start(queue, b.work, replies, "b", func() -> bool: return not moved_on[0])
	_start(queue, c.work, replies, "c")
	moved_on[0] = true
	a.released.emit()
	_check(not log.has("start b") and replies.get("b", {}).get("code") == RequestQueue.CANCELLED, "A request whose caller moved on is skipped when its turn comes")
	_check(log.back() == "start c", "The request behind a skipped one goes out at once")
	c.released.emit()
	# Every caller of a shared poll moved on: it is skipped too.
	log.clear()
	var hold := Held.new("hold", log)
	_start(queue, hold.work, replies, "hold")
	_start(queue, Held.new("poll", log).work, replies, "p1", func() -> bool: return false, "GET /v1/social/inbox")
	_start(queue, Held.new("poll2", log).work, replies, "p2", func() -> bool: return false, "GET /v1/social/inbox")
	hold.released.emit()
	_check(not log.has("start poll") and replies.get("p1", {}).get("code") == RequestQueue.CANCELLED and replies.get("p2", {}).get("code") == RequestQueue.CANCELLED, "A shared poll nobody wants any more never goes out")
	_check(not queue.busy(), "Nothing is left waiting")
	# A caller freed while its request waited no longer wants it.
	log.clear()
	var lead := Held.new("lead", log)
	var owner := Owner.new()
	_start(queue, lead.work, replies, "lead")
	_start(queue, Held.new("orphan", log).work, replies, "orphan", owner.wants)
	owner.free()
	lead.released.emit()
	_check(not log.has("start orphan") and replies.get("orphan", {}).get("code") == RequestQueue.CANCELLED, "A request whose caller was freed is skipped")

func _failures() -> void:
	var queue := RequestQueue.new()
	var log: Array = []
	var replies := {}
	var timed_out := Held.new("timeout", log, {"ok": false, "status": 0, "code": "connection_interrupted"})
	var broken := Held.new("broken", log, "not a reply")
	var next := Held.new("next", log)
	_start(queue, timed_out.work, replies, "timeout")
	_start(queue, broken.work, replies, "broken")
	_start(queue, next.work, replies, "next")
	timed_out.released.emit()
	_check(replies.get("timeout", {}).get("ok") == false and log.back() == "start broken", "A request that times out ends its turn and the next one goes")
	broken.released.emit()
	_check(replies.get("broken", {}).get("code") == "connection_interrupted", "Work that returns no reply reads as an interrupted connection")
	_check(log.back() == "start next", "Nothing deadlocks behind a failed request")
	next.released.emit()
	_check(replies.get("next", {}).get("ok") == true and not queue.busy(), "The queue drains after failures")

func _full() -> void:
	var queue := RequestQueue.new()
	var log: Array = []
	var replies := {}
	var helds: Array = []
	for index in range(RequestQueue.MAX_WAITING + 2):
		var held := Held.new(str(index), log)
		helds.append(held)
		_start(queue, held.work, replies, str(index))
	var last := str(RequestQueue.MAX_WAITING + 1)
	_check(replies.get(last, {}).get("code") == RequestQueue.FULL, "One more than the waiting limit is refused at once")
	_check(queue.waiting_count() == RequestQueue.MAX_WAITING, "The wait list stays bounded")
	for held: Held in helds: held.released.emit()
	_check(not queue.busy(), "Every waiting request still runs")

func _rooms_api() -> void:
	var api := Api.new()
	api.player_id = "player-one"
	api.device_token = "token-one"
	root.add_child(api)
	var replies := {}
	var ask := func(name: String, method: int, path: String) -> void: replies[name] = await api.request_json(method, path, {"schema_version": 1})
	ask.call("poll", HTTPClient.METHOD_GET, "/v1/room-inbox")
	ask.call("tap", HTTPClient.METHOD_POST, "/v1/invitations/resolve")
	_check(api.sent.size() == 1 and api.sent[0].path == "/v1/room-inbox", "A tap during a poll waits for it instead of being refused")
	api.answer.emit()
	_check(api.sent.size() == 2 and api.sent[1].path == "/v1/invitations/resolve", "The tap goes out right after the poll lands")
	api.answer.emit()
	_check(replies.get("poll", {}).get("ok") == true and replies.get("tap", {}).get("ok") == true, "Both get their replies")
	# Two writes never share a turn.
	ask.call("w1", HTTPClient.METHOD_POST, "/v2/rooms/r/turns")
	ask.call("w2", HTTPClient.METHOD_POST, "/v2/rooms/r/turns")
	ask.call("w3", HTTPClient.METHOD_POST, "/v2/rooms/r/turns")
	api.answer.emit()
	api.answer.emit()
	api.answer.emit()
	_check(api.sent.size() == 5, "Identical writes each go out once, in order")
	# A request asked under one identity never goes out under another.
	api.sent.clear()
	ask.call("before", HTTPClient.METHOD_GET, "/v1/friends")
	ask.call("stale", HTTPClient.METHOD_POST, "/v1/rooms")
	api.player_id = "player-two"
	api.device_token = "token-two"
	api.answer.emit()
	_check(api.sent.size() == 1 and replies.get("stale", {}).get("code") == RequestQueue.CANCELLED, "A request asked before an identity change is skipped")
	_check(api.sent[0].headers.has("Authorization: Bearer token-one"), "Credentials are the ones read when the request was asked")
	# A caller's own check skips its request.
	api.sent.clear()
	var open := [true]
	ask.call("busy", HTTPClient.METHOD_GET, "/v1/entitlement")
	var stale_reply := {}
	var asked := func() -> void: stale_reply.merge(await api.request_json(HTTPClient.METHOD_GET, "/v1/rooms", {}, func() -> bool: return open[0]))
	asked.call()
	open[0] = false
	api.answer.emit()
	_check(api.sent.size() == 1 and stale_reply.get("cancelled") == true, "A request whose screen closed while it waited never goes out")
	api.queue_free()
	await process_frame

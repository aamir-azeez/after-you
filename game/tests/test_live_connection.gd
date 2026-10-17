extends SceneTree
## services/live_connection.gd against a fake socket and a fake API: the
## capability gate, the handshake (credentials in headers only), hints and
## their limits, keepalive and silence, the reconnect backoff and its reset,
## the server's identity-revoked close, and background and identity changes.
const Live = preload("res://services/live_connection.gd")
const OWNER := "aaaaaaaaaaaaaaaaaaaaaa"
const ROOM := "rrrrrrrrrrrrrrrrrrrrrr"
var failures := 0
var checks := 0
var now := 1000

class FakeSocket:
	extends RefCounted
	var state := WebSocketPeer.STATE_CONNECTING
	var inbound: Array[PackedByteArray] = []
	var sent: Array[String] = []
	var close_code := -1
	var closed_here := false
	var url := ""
	var headers := PackedStringArray()
	func poll() -> void: pass
	func get_ready_state() -> int: return state
	func get_available_packet_count() -> int: return inbound.size()
	func get_packet() -> PackedByteArray: return inbound.pop_front()
	func send_text(text: String) -> int:
		sent.append(text)
		return OK
	func close(_code: int = 1000, _reason: String = "") -> void:
		closed_here = true
		state = WebSocketPeer.STATE_CLOSED
	func get_close_code() -> int: return close_code
	func push(text: String) -> void: inbound.append(text.to_utf8_buffer())

class FakeApi:
	extends Node
	var paths: Array[String] = []
	var answer: Dictionary = {"ok": true, "data": {"api_version": 2}}
	func configured() -> bool: return true
	func request_json(_method: int, path: String, _body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		paths.append(path)
		return JSON.parse_string(JSON.stringify(answer))

var sockets: Array[FakeSocket] = []
## What Main's capability source and screen check report (lambdas capture locals by value).
var held: Dictionary = {}
var up := false
var events: Array = []
var live: Node
var api: FakeApi

func _initialize() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func identity(token: String = "device-credential", epoch: int = 1) -> Dictionary:
	return {"ready": true, "player_id": OWNER, "device_token": token, "base_url": "https://example.test", "epoch": epoch}

func factory(url: String, headers: PackedStringArray) -> Object:
	var socket := FakeSocket.new()
	socket.url = url
	socket.headers = headers
	sockets.append(socket)
	return socket

func step(advance: int = 0) -> void:
	now += advance
	live.service()
	await process_frame

func last() -> FakeSocket: return sockets.back() if not sockets.is_empty() else null

func missed() -> int: return events.filter(func(item: Array) -> bool: return item[0] == "missed").size()

func _run() -> void:
	api = FakeApi.new()
	root.add_child(api)
	live = Live.new()
	live.api = api
	live.socket_factory = factory
	live.clock_ms = func() -> int: return now
	live.jitter_ms = func(_limit: int) -> int: return 0
	root.add_child(live)
	live.set_process(false)
	live.room_changed.connect(func(room: String, seq: int) -> void: events.append(["room", room, seq]))
	live.friends_changed.connect(func(early: bool) -> void: events.append(["friends", early]))
	live.missed_hints.connect(func(since: int) -> void: events.append(["missed", since]))
	live.health_changed.connect(func(healthy: bool) -> void: events.append(["health", healthy]))
	await _capability_gate()
	await _handshake_and_hints()
	await _keepalive_and_silence()
	await _backoff()
	await _revoked_and_lifecycle()
	live.queue_free()
	await _wanted_and_held()
	api.queue_free()
	await process_frame
	print("LIVE CONNECTION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _capability_gate() -> void:
	await step()
	check(api.paths.is_empty(), "No identity, no request")
	live.set_identity(identity())
	await step()
	check(api.paths == ["/v2/capabilities"], "The capability is read once for an identity")
	await step(); await step(100000)
	check(sockets.is_empty() and api.paths.size() == 1, "A server that does not offer live_version never sees a socket, nor a second read soon")
	check(live.poll_interval_ms(3000) == 3000, "Without a socket the poll keeps its own pace")
	live.set_foreground(false)
	live.set_foreground(true)
	await step(Live.RECHECK_MS)
	check(api.paths.size() == 2, "A no is asked again after a while, on return to the app")
	api.answer = {"ok": true, "data": {"api_version": 2, "live_version": 2}}
	live.set_foreground(false); live.set_foreground(true)
	await step(Live.RECHECK_MS)
	await step()
	check(sockets.is_empty(), "An unknown live version is not used")

func _handshake_and_hints() -> void:
	api.answer = {"ok": true, "data": {"api_version": 2, "live_version": 1.0}}
	live.set_identity(identity("device-credential", 2))
	await step()
	await step()
	check(sockets.size() == 1, "An offered live version opens one socket")
	var socket := last()
	check(socket.url == "wss://example.test/v1/live", "The socket goes to the live path over TLS")
	check(not socket.url.contains("device-credential") and socket.headers.has("Authorization: Bearer device-credential") and socket.headers.has("X-Player-Id: " + OWNER), "Credentials go in headers, never the URL")
	check(not live.healthy(), "A connecting socket is not healthy yet")
	socket.state = WebSocketPeer.STATE_OPEN
	events.clear()
	await step()
	check(live.healthy() and live.poll_interval_ms(3000) == Live.SAFETY_POLL_MS, "An open socket slows the poll to its safety interval")
	check(events == [["health", true]], "A first open asks for no catch-up read: the screen's own open read covers it")
	events.clear()
	socket.push(JSON.stringify({"type": "room_changed", "room": ROOM, "seq": 7}))
	socket.push(JSON.stringify({"type": "friends_changed"}))
	socket.push(JSON.stringify({"type": "room_changed", "room": "short", "seq": 1}))
	socket.push(JSON.stringify({"type": "room_changed", "room": ROOM, "seq": -1}))
	socket.push(JSON.stringify({"type": "something_else"}))
	socket.push("not json")
	socket.push(JSON.stringify({"type": "friends_changed", "pad": "x".repeat(Live.MAX_MESSAGE_BYTES)}))
	await step()
	check(events == [["room", ROOM, 7], ["friends", true]], "Valid hints are passed on; malformed, unknown and oversized ones are dropped")

func _keepalive_and_silence() -> void:
	var socket := last()
	await step(Live.PING_MS)
	check(socket.sent == ["ping"], "A ping goes out every PING_MS")
	socket.push("pong")
	await step(Live.SILENCE_MS - 1)
	check(live.healthy() and not socket.closed_here, "A pong keeps the socket alive")
	events.clear()
	await step(Live.SILENCE_MS)
	check(socket.closed_here and not live.healthy(), "Silence for SILENCE_MS closes the socket (network switch or sleep)")
	check(events == [["health", false]], "Losing the socket tells pollers to return to their own pace")
	check(live.poll_interval_ms(3000) == 3000, "Polling is today's again while the socket is down")
	await step(Live.BACKOFF_MS[0] - 1)
	check(sockets.size() == 1, "No reconnect before the first backoff")
	await step(1)
	check(sockets.size() == 2, "The first reconnect comes after the first backoff")

func _backoff() -> void:
	# The server is gone (a deploy): each attempt closes before it opens.
	var reads := api.paths.size()
	var socket := last()
	socket.state = WebSocketPeer.STATE_CLOSED
	await step()
	var waited: Array[int] = []
	for attempt in 3:
		var before := sockets.size()
		var started := now
		while sockets.size() == before and now - started < 400000: await step(500)
		waited.append(now - started)
		last().state = WebSocketPeer.STATE_CLOSED
		await step()
	check(waited[0] >= Live.BACKOFF_MS[1] and waited[1] >= Live.BACKOFF_MS[2] and waited[1] > waited[0], "Delays grow after each failed attempt: %s" % [waited])
	check(api.paths.size() > reads, "Handshakes that never open make the app ask for the capability again")
	# A socket that stays up resets the delays.
	var before := sockets.size()
	while sockets.size() == before: await step(1000)
	socket = last()
	socket.state = WebSocketPeer.STATE_OPEN
	await step()
	for ping in 2:
		socket.push("pong")
		await step(Live.PING_MS)
	check(live.healthy(), "The socket is open")
	socket.close_code = 1001
	socket.state = WebSocketPeer.STATE_CLOSED
	await step()
	before = sockets.size()
	await step(Live.BACKOFF_MS[0])
	check(sockets.size() == before + 1, "After a socket stayed open a while, a server deploy reconnects after the first delay again")

func _revoked_and_lifecycle() -> void:
	var socket := last()
	socket.state = WebSocketPeer.STATE_OPEN
	await step()
	socket.close_code = Live.REVOKED
	socket.state = WebSocketPeer.STATE_CLOSED
	await step()
	var count := sockets.size()
	await step(Live.BACKOFF_MS.back() * 2)
	check(sockets.size() == count, "A revoked identity is not retried")
	live.set_foreground(false)
	live.set_foreground(true)
	await step()
	check(sockets.size() == count + 1, "Coming back to the app tries again")
	socket = last()
	socket.state = WebSocketPeer.STATE_OPEN
	await step()
	live.set_foreground(false)
	check(socket.closed_here and not live.healthy(), "The background closes the socket")
	await step(Live.BACKOFF_MS.back())
	check(sockets.size() == count + 1, "Nothing connects in the background")
	live.set_foreground(true)
	await step()
	socket = last()
	socket.state = WebSocketPeer.STATE_OPEN
	await step()
	var reads := api.paths.size()
	live.set_identity(identity("recovered-credential", 3))
	check(socket.closed_here and not live.healthy(), "A new identity closes the old socket at once")
	await step()
	check(api.paths.size() == reads + 1, "A new identity reads the capability again")
	await step()
	check(last().headers.has("Authorization: Bearer recovered-credential"), "The new socket carries the new credential")
	live.set_identity({})
	check(last().closed_here, "No identity, no socket")

## Main's own sources: nothing starts until an online screen is up; a held
## capability answer is used without a read; with none held, the app's own read
## comes after a short grace; a held "no" is asked again by the app's own read
## after a while; and handshakes that keep failing are followed by its own read
## too, never the held answer that may be stale.
func _wanted_and_held() -> void:
	var paths := api.paths.size()
	live = Live.new()
	live.api = api
	live.socket_factory = factory
	live.clock_ms = func() -> int: return now
	live.jitter_ms = func(_limit: int) -> int: return 0
	live.capabilities = func() -> Dictionary: return held
	live.wanted = func() -> bool: return up
	root.add_child(live)
	live.set_process(false)
	live.friends_changed.connect(func(early: bool) -> void: events.append(["friends", early]))
	live.missed_hints.connect(func(since: int) -> void: events.append(["missed", since]))
	live.set_identity(identity("held-credential", 9))
	var count := sockets.size()
	await step(); await step(Live.CAPABILITY_GRACE_MS * 3)
	check(sockets.size() == count and api.paths.size() == paths, "Nothing is read or opened before an online screen is up")
	up = true
	await step()
	await step(Live.CAPABILITY_GRACE_MS - 1)
	check(api.paths.size() == paths, "The app's own read waits for the capability answer the screen loads")
	held = {"api_version": 2, "live_version": 1.0}
	await step()
	check(sockets.size() == count + 1 and api.paths.size() == paths, "A held answer opens the socket with no extra read")
	last().state = WebSocketPeer.STATE_OPEN
	await step()
	check(live.healthy(), "Open")
	events.clear()
	last().push(JSON.stringify({"type": "friend_requests_changed"}))
	await step()
	check(events == [["friends", false]], "A request that arrived or was cancelled is a hint with no early read")
	# A server deploy drops the socket: the reopen asks every screen for one read.
	events.clear()
	last().close_code = 1001
	last().state = WebSocketPeer.STATE_CLOSED
	await step()
	await step(Live.BACKOFF_MS[0])
	last().state = WebSocketPeer.STATE_OPEN
	await step()
	check(live.healthy() and missed() == 1, "A reopen after a drop asks for one catch-up read")
	# Leaving the online screens closes the socket after a grace, and misses nothing.
	up = false
	await step()
	await step(Live.WANTED_GRACE_MS - 1)
	check(live.healthy(), "An open socket stays open for a moment after the screens close")
	await step(1)
	check(not live.healthy() and last().closed_here, "It closes WANTED_GRACE_MS after the last online screen, so none stays open in solo play")
	up = true
	events.clear()
	var reopened_from := sockets.size()
	await step()
	check(sockets.size() == reopened_from + 1, "An online screen opens it again")
	last().state = WebSocketPeer.STATE_OPEN
	await step()
	check(live.healthy() and missed() == 0, "Reopening for a screen asks for no catch-up read")
	# A focus change keeps the socket; only a pause closes it.
	live.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await step()
	check(live.healthy() and not last().closed_here, "A focus change keeps the socket open")
	# A pause closes it; hints sent meanwhile are lost, so the reopen after resume asks for one catch-up read from the pause on.
	events.clear()
	var paused_at := now
	live.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(not live.healthy() and last().closed_here, "A pause closes the socket")
	await step(5000)
	live.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await step()
	last().state = WebSocketPeer.STATE_OPEN
	await step()
	check(live.healthy() and events.filter(func(item: Array) -> bool: return item[0] == "missed") == [["missed", paused_at]], "A resume reopens with exactly one catch-up read, from the pause (%s)" % [events])
	last().state = WebSocketPeer.STATE_CLOSING
	await step()
	check(not live.healthy(), "A closing socket is not healthy")
	await step(Live.CONNECT_TIMEOUT_MS)
	check(last().closed_here, "A close the network never finishes is given up")
	# A rollback: every handshake now fails; the held answer still says yes.
	up = true
	api.answer = {"ok": true, "data": {"api_version": 2}}
	var reads := api.paths.size()
	for attempt in Live.MAX_FAILED_OPENS + 1:
		var before := sockets.size()
		var started := now
		while sockets.size() == before and api.paths.size() == reads and now - started < 700000: await step(1000)
		if api.paths.size() > reads: break
		last().state = WebSocketPeer.STATE_CLOSED
		await step()
	check(api.paths.size() == reads + 1, "Failed handshakes are followed by the app's own read, not the stale held answer")
	var after_no := sockets.size()
	await step(Live.BACKOFF_MS.back() * 3)
	check(sockets.size() == after_no, "And the server's no keeps it closed")
	reads = api.paths.size()
	# A held no from before a flag was switched on is asked again later.
	held = {"api_version": 2}
	live.set_identity(identity("held-credential", 10))
	await step()
	check(api.paths.size() == reads and sockets.size() == after_no, "A held no is used without a read")
	api.answer = {"ok": true, "data": {"api_version": 2, "live_version": 1}}
	await step(Live.RECHECK_MS)
	await step()
	check(api.paths.size() == reads + 1 and sockets.size() == after_no + 1, "After a while the app asks itself and opens despite the old held no")
	live.queue_free()

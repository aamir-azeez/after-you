extends Node
## One live socket per phone to its own server object, open while the app is
## in front, an identity exists and an online screen is up (closed WANTED_GRACE_MS
## after the last one goes, so none stays open in solo play). The server sends hints; each subscriber
## answers a hint with one ordinary read through the request queue, so no data
## and no access decision ever comes over the socket. A missed hint is caught
## by the subscriber's slower safety poll.
##
## - It connects only when GET /v2/capabilities (asked with X-AfterYou-Live: 1)
##   answers live_version 1, so a server without the feature sees nothing new.
##   An answer the app already holds (`capabilities`) is used first; its own
##   read waits CAPABILITY_GRACE_MS for one, and runs only while `wanted` (an
##   online screen is up). A "no" is asked again after RECHECK_MS, and
##   handshakes that keep failing (a rollback drops every socket and refuses
##   new ones) are followed by its own read, never the held answer.
## - Credentials go in the handshake headers, never the URL, and are not kept
##   on the socket object.
## - A dropped socket reconnects with growing, jittered delays; the delays
##   reset only once a socket has stayed open a while. The server closing with
##   4401 (identity revoked) stops it until the identity changes or the app
##   comes back to the front.
## - `missed_hints(since_ms)` is the one rule for catch-up reads: it fires when a
##   socket reopens after one that was open while wanted went away, by itself (a
##   deploy, a network switch, silence) or with the app paused. `since_ms` is when
##   hints started being missed, so a screen whose own resume read began after it
##   (RefreshSchedule.hint) reads no second time. A first open, closing for solo
##   play or an identity change sends nothing.
## - Keepalive: engine protocol pings every HEARTBEAT_S keep the path open at no
##   cost to the server; Godot reports no pongs, so a rare text "ping"
##   (answered by the server without waking it) is the liveness check.
## - `poll_interval_ms(base)` is the shared delay: a poller asks it for its
##   interval, and gets the slow safety poll while the socket is healthy.
const Presence = preload("res://services/friend_presence.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const ClientIdentity = preload("res://services/client_identity.gd")

signal room_changed(room_id: String, seq: int)
## `early`: the server opened an early friends list read for it (a shared room
## changed, a request was accepted). A request that arrived or was cancelled is not early.
signal friends_changed(early: bool)
## The socket reopened after one that was open dropped or was paused: hints sent
## since `since_ms` are lost, so each screen reads once unless a read it began
## after `since_ms` already covers them.
signal missed_hints(since_ms: int)
signal health_changed(healthy: bool)

const PATH := "/v1/live"
const VERSION := 1
const CAPABILITY_HEADER := "X-AfterYou-Live: 1"
## A poller's interval while the socket is healthy (its safety poll).
const SAFETY_POLL_MS := 60000
## Engine protocol pings, free on the server, keep idle proxies and NATs from closing the socket.
const HEARTBEAT_S := 30.0
## The text ping that proves the socket still reaches the server (billed as a fraction of a request).
const PING_MS := 240000
## No pong or hint for this long means the socket is gone (a network switch, a sleeping radio).
const SILENCE_MS := 300000
const CONNECT_TIMEOUT_MS := 15000
const BACKOFF_MS: Array[int] = [1000, 2000, 5000, 15000, 30000, 60000, 300000]
const JITTER_MS := 1000
## A socket open this long resets the backoff.
const STABLE_MS := 60000
## Handshakes in a row that never opened before the capability is read again.
const MAX_FAILED_OPENS := 3
## A server "no" is asked again after this long, on the next try.
const RECHECK_MS := 600000
## How long an online screen may be up before this asks the capability itself.
const CAPABILITY_GRACE_MS := 3000
## An open socket closes this long after the last online screen goes.
const WANTED_GRACE_MS := 30000
const MAX_MESSAGE_BYTES := 512
const REVOKED := 4401

var api: Node
## func() -> Dictionary: the capability answer the app already holds, or {}.
var capabilities: Callable
## func() -> bool: whether a screen that reads on hints is up.
var wanted: Callable
## func(url: String, headers: PackedStringArray) -> Object with poll(),
## get_ready_state(), get_available_packet_count(), get_packet(), send_text(),
## close() and get_close_code(), already connecting; null when it cannot start.
var socket_factory: Callable = _open_socket
var clock_ms: Callable = Time.get_ticks_msec
var jitter_ms: Callable = func(limit: int) -> int: return randi() % maxi(1, limit)

var _identity: Dictionary = {}
var _key := ""
var _foreground := true
var _generation := 0
## -1 not asked, 0 not offered, 1 offered (for _key).
var _advertised := -1
var _checked_at := -1
var _checking := false
var _socket: Object = null
var _connect_started := 0
var _opened_at := -1
var _last_inbound := 0
var _next_ping := 0
var _next_attempt := 0
var _failures := 0
var _failed_opens := 0
var _stopped := false
var _healthy := false
var _wanted_since := -1
var _unwanted_since := -1
## When an open, wanted socket dropped or was paused (-1: nothing missed); the next open sends missed_hints.
var _missed_since := -1
## The held answer proved wrong (handshakes failed) or old (a "no" being asked
## again): the next answer comes from this service's own read.
var _own_read := false
var _closing_since := -1

func _process(_delta: float) -> void:
	service()

## The identity in the FriendPresence shape ({ready, player_id, device_token, base_url, epoch}).
func set_identity(value: Dictionary) -> void:
	var key := Presence.identity_key(value)
	if key == _key: return
	_drop_socket()
	_generation += 1
	_key = key
	_identity = value.duplicate(true) if not key.is_empty() else {}
	_advertised = -1
	_checked_at = -1
	_own_read = false
	_failures = 0
	_failed_opens = 0
	_next_attempt = 0
	_stopped = false
	_missed_since = -1

## A pause closes the socket; hints sent while paused are lost, so the reopen
## after resume asks each screen for one catch-up read (merged with a screen's own
## resume read). A pending reconnect delay still holds on resume.
func set_foreground(value: bool) -> void:
	if _foreground == value: return
	_foreground = value
	_generation += 1
	if not value:
		if _opened_at >= 0 and (not wanted.is_valid() or wanted.call()): _note_missed(_now())
		_drop_socket()
		return
	_stopped = false

## True while a socket is open and heard from recently.
func healthy() -> bool:
	return _healthy

## The interval a poller with this base interval uses now.
func poll_interval_ms(base_ms: int) -> int:
	return maxi(base_ms, SAFETY_POLL_MS) if _healthy else base_ms

func service() -> void:
	var now := _now()
	if _socket != null:
		_close_when_unwanted(now)
		if _socket != null: _service_socket(now)
		return
	if _key.is_empty() or not _foreground or _stopped or _checking or now < _next_attempt: return
	if not is_instance_valid(api) or not api.configured(): return
	if wanted.is_valid() and not wanted.call():
		_wanted_since = -1
		return
	if _wanted_since < 0: _wanted_since = now
	# A "no" is asked again after a while, by this service's own read.
	if _advertised == 0 and _checked_at >= 0 and now - _checked_at >= RECHECK_MS:
		_advertised = -1
		_own_read = true
	if _advertised == -1 and not _own_read:
		var held := _held_capability()
		if held >= 0:
			_advertised = held
			_checked_at = now
	if _advertised == -1:
		if capabilities.is_valid() and not _own_read and now - _wanted_since < CAPABILITY_GRACE_MS: return
		_check_capability()
		return
	if _advertised == 1: _connect(now)

## live_version from a capability answer the app already holds: 1 offered,
## 0 not, -1 none held.
func _held_capability() -> int:
	if not capabilities.is_valid(): return -1
	var data: Variant = capabilities.call()
	if not data is Dictionary or data.get("api_version") == null: return -1
	return 1 if RoomsApi.json_int(data.get("live_version")) == VERSION else 0

func _check_capability() -> void:
	_checking = true
	var generation := _generation
	var response: Dictionary = await api.request_json(HTTPClient.METHOD_GET, "/v2/capabilities")
	# A newer identity or a trip to the background already let go of this read.
	if generation != _generation: return
	_checking = false
	var now := _now()
	if not response.get("ok", false):
		_backoff(now)
		return
	var data: Variant = response.get("data")
	_advertised = 1 if data is Dictionary and RoomsApi.json_int(data.get("live_version")) == VERSION else 0
	_checked_at = now
	_own_read = false

func _connect(now: int) -> void:
	var base := str(_identity.get("base_url", "")).trim_suffix("/")
	var url := ("wss://" + base.substr(8)) if base.begins_with("https://") else ("ws://" + base.substr(7)) if base.begins_with("http://") else ""
	if url.is_empty(): return
	var headers := PackedStringArray(["Authorization: Bearer " + str(_identity.device_token), "X-Player-Id: " + str(_identity.player_id)])
	var client := ClientIdentity.header_line()
	if not client.is_empty(): headers.append(client)
	_socket = socket_factory.call(url + PATH, headers)
	_connect_started = now
	_opened_at = -1
	if _socket == null: _after_close(now, -1, false)

## No online screen for WANTED_GRACE_MS: the socket closes, and nothing is missed.
func _close_when_unwanted(now: int) -> void:
	if not wanted.is_valid() or wanted.call():
		_unwanted_since = -1
		return
	if _unwanted_since < 0: _unwanted_since = now
	if now - _unwanted_since < WANTED_GRACE_MS: return
	_unwanted_since = -1
	_missed_since = -1
	_drop_socket()

func _service_socket(now: int) -> void:
	_socket.poll()
	match int(_socket.get_ready_state()):
		WebSocketPeer.STATE_CONNECTING:
			if now - _connect_started >= CONNECT_TIMEOUT_MS: _close_and_retry(now)
		WebSocketPeer.STATE_OPEN:
			if _opened_at < 0:
				_opened_at = now
				_last_inbound = now
				_next_ping = now + PING_MS
				_failed_opens = 0
				_own_read = false
				_set_healthy(true)
				if _missed_since >= 0:
					var since := _missed_since
					_missed_since = -1
					missed_hints.emit(since)
			if _socket == null: return
			while _socket != null and _socket.get_available_packet_count() > 0:
				var packet: PackedByteArray = _socket.get_packet()
				_last_inbound = now
				_handle(packet)
			if _socket == null: return
			if _failures > 0 and now - _opened_at >= STABLE_MS: _failures = 0
			if now - _last_inbound >= SILENCE_MS:
				_close_and_retry(now)
			elif now >= _next_ping:
				_next_ping = now + PING_MS
				_socket.send_text("ping")
		WebSocketPeer.STATE_CLOSING:
			# A close handshake the network never finishes is a dropped socket.
			_set_healthy(false)
			if _closing_since < 0: _closing_since = now
			elif now - _closing_since >= CONNECT_TIMEOUT_MS: _close_and_retry(now)
		WebSocketPeer.STATE_CLOSED:
			var code := int(_socket.get_close_code())
			var opened := _opened_at >= 0
			_socket = null
			_after_close(now, code, opened)

## A hint names a room or says friends changed; nothing else is trusted from it.
func _handle(packet: PackedByteArray) -> void:
	if packet.size() > MAX_MESSAGE_BYTES: return
	var text := packet.get_string_from_utf8()
	if text == "pong": return
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary: return
	var value: Dictionary = parser.data
	match value.get("type"):
		"room_changed":
			var seq := RoomsApi.json_int(value.get("seq"))
			if Presence.valid_id(value.get("room")) and seq >= 0: room_changed.emit(str(value.room), seq)
		"friends_changed":
			friends_changed.emit(true)
		"friend_requests_changed":
			friends_changed.emit(false)

## Keeps the earliest moment: a drop while an earlier one is still owed changes nothing.
func _note_missed(now: int) -> void:
	if _missed_since < 0: _missed_since = now

func _close_and_retry(now: int) -> void:
	var opened := _opened_at >= 0
	_close_socket()
	_after_close(now, -1, opened)

func _after_close(now: int, code: int, opened: bool) -> void:
	_opened_at = -1
	if opened: _note_missed(now)
	_closing_since = -1
	_set_healthy(false)
	if code == REVOKED:
		_stopped = true
		return
	if not opened:
		_failed_opens += 1
		# A server rolled back or switched off: ask the capability again first,
		# with this service's own read (the answer the app holds may be the stale one).
		if _failed_opens >= MAX_FAILED_OPENS:
			_failed_opens = 0
			_advertised = -1
			_own_read = true
	_backoff(now)

func _backoff(now: int) -> void:
	var delay: int = BACKOFF_MS[mini(_failures, BACKOFF_MS.size() - 1)]
	_failures += 1
	_next_attempt = now + delay + int(jitter_ms.call(JITTER_MS))

func _drop_socket() -> void:
	_close_socket()
	_opened_at = -1
	_closing_since = -1
	_checking = false
	_set_healthy(false)

func _close_socket() -> void:
	if _socket != null:
		var socket := _socket
		_socket = null
		socket.close()

func _set_healthy(value: bool) -> void:
	if _healthy == value: return
	_healthy = value
	health_changed.emit(value)

func _now() -> int:
	return int(clock_ms.call())

func _notification(what: int) -> void:
	# Pause only: a focus change (a notification shade, a dialog) keeps the socket.
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]:
		set_foreground(false)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		set_foreground(true)

func _exit_tree() -> void:
	_generation += 1
	_drop_socket()
	_identity.clear()
	_key = ""

static func _open_socket(url: String, headers: PackedStringArray) -> Object:
	var peer := WebSocketPeer.new()
	peer.handshake_headers = headers
	peer.inbound_buffer_size = 4096
	peer.outbound_buffer_size = 4096
	peer.max_queued_packets = 32
	peer.heartbeat_interval = HEARTBEAT_S
	return peer if peer.connect_to_url(url) == OK else null

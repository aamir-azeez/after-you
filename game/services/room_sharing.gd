extends Node
## Sharing a hosted room with all friends, and the one hosting alert a shared
## room owes. The server refuses a hosting alert for a room that is not shared,
## so a room that still owes its alert sends it once its share is confirmed, and
## a failed alert retries quietly a few times. The owed record and its
## publication id live in the room event client, so a restart keeps the alert
## and a retry never sends it twice.
##
## The relay lobby, the open room, the legacy room page and Friends drive it; it
## draws nothing. Main hosts it as an internal child, so a quiet retry ends with
## Main, and passes in what it reads. share reads the Friends client once, when
## it starts; view and each retry read it again:
## - friends(create) -> the Friends client, made on first use when create is set
## - events() -> the room event client
## - identity() -> the relay identity ({"ready": ...})
## - owner() -> the identity a retry belongs to
## - allowed(target) -> whether that room is open here and hosted by this player
## - route_context() and route_current(context) -> whether the player moved on
## - changed(target) -> the open room redraws its share controls
const FriendsClient = preload("res://services/friends_client.gd")
const FriendRoomEventsClient = preload("res://services/friend_room_events_client.gd")
## Share replies that mean the room can no longer be shared: its alert is dropped.
const ROOM_GONE_CODES := ["room_not_found", "friend_room_unavailable", "friend_not_joinable", "room_full"]

## A failed hosting alert for a shared room retries quietly after these delays.
var retry_delays_s: Array[float] = [5.0, 20.0, 60.0]
## True while a share change is in flight.
var busy := false
var _retrying := ""
var _friends: Callable
var _events: Callable
var _identity: Callable
var _owner: Callable
var _allowed: Callable
var _route_context: Callable
var _route_current: Callable
var _changed: Callable

func _init(friends := Callable(), events := Callable(), identity := Callable(), owner := Callable(), allowed := Callable(), route_context := Callable(), route_current := Callable(), changed := Callable()) -> void:
	_friends = friends
	_events = events
	_identity = identity
	_owner = owner
	_allowed = allowed
	_route_context = route_context
	_route_current = route_current
	_changed = changed

## Shares the hosted room with all friends, or stops sharing it. A room that
## still owes its hosting alert sends it here, once, right after the share is
## confirmed.
func share(target: Dictionary, shared: bool = true) -> Dictionary:
	if busy or not _allowed.call(target): return {"ok": false, "message": "Room unavailable"}
	var client: RefCounted = _friends.call(true)
	var context: Dictionary = _route_context.call()
	busy = true
	_changed.call(target)
	var okay := false
	var attempted := false
	if await _client_idle(context, client) and _allowed.call(target):
		attempted = true
		okay = await client.share_room(target if shared else null)
	if okay and shared and _route_current.call(context) and _allowed.call(target): await send_owed_alert(target)
	elif attempted and not okay and shared and client.last_code in ROOM_GONE_CODES: _events.call().forget(target)
	busy = false
	if not _route_current.call(context) or not _allowed.call(target): return {"ok": false, "ignored": true}
	_changed.call(target)
	var error: String = client.last_error if not client.last_error.is_empty() else "Friends unavailable"
	if not okay: return {"ok": false, "message": error}
	return {"ok": true, "message": "Shared with friends" if shared else ""}

## Whether the room is the one shared with friends, and whether a change is in flight.
func view(target: Dictionary) -> Dictionary:
	var client: RefCounted = _friends.call(false)
	var shared: Variant = client.shared_room() if client != null else null
	return {"shared": FriendsClient.same_room(shared, target), "busy": busy}

## Sends the one alert a shared room still owes, from any place that shared it.
func send_owed_alert(room: Dictionary) -> void:
	if not _identity.call().ready or not _events.call().owes(room): return
	if not await _publish(room): _retry(room)

## Whether a failed alert is waiting to retry.
func retrying() -> bool:
	return not _retrying.is_empty()

## The Friends client sends one of its own requests at a time; wait briefly for one in flight.
func _client_idle(context: Dictionary, client: RefCounted) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while client.busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not _route_current.call(context): return false
	return not client.busy and _route_current.call(context)

func _publish(room: Dictionary) -> bool:
	if not _identity.call().ready or not FriendRoomEventsClient.valid_room(room): return false
	var events: FriendRoomEventsClient = _events.call()
	# A delivery failure never undoes the room or its share. The client keeps
	# the publication id after a failure, so a later retry cannot alert twice.
	var deadline := Time.get_ticks_msec() + 5000
	while events.busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not _identity.call().ready: return false
	if events.busy: return false
	var result: Dictionary = await events.publish(room)
	return result.get("ok", false)

## A few quiet retries with backoff, only while the room is still shared and
## still owes its alert; the saved id keeps every retry at one alert.
func _retry(room: Dictionary) -> void:
	var key := _key(room)
	if _retrying == key: return
	_retrying = key
	var identity: String = _owner.call()
	for delay: float in retry_delays_s:
		await get_tree().create_timer(delay).timeout
		if identity != _owner.call() or not _identity.call().ready or not _events.call().owes(room): break
		var client: RefCounted = _friends.call(false)
		if client == null or not FriendsClient.same_room(client.shared_room(), room): break
		if await _publish(room): break
	if _retrying == key: _retrying = ""

static func _key(room: Dictionary) -> String:
	return "%d:%s" % [int(room.get("api_version", 0)), str(room.get("room_id", ""))]

extends RefCounted
## Adding a room partner as a friend: whether a room screen offers it, and the
## request itself. The request is the ordinary friend request
## (friends_client.add_friend with the partner's player id from the room
## membership), so it reaches the partner exactly like one sent from Friends:
## the same route, the same live friend event and the same "View" pop-up, and
## they can accept or ignore it.
##
## Nothing here reads the network to decide: who is already a friend comes
## from the friends list this phone kept (friend_roster.gd), and a blocked or
## reported partner from this phone's safety record (safety_store.gd).
const FriendRoster = preload("res://services/friend_roster.gd")
const SafetyStore = preload("res://services/safety_store.gd")
const Presence = preload("res://services/friend_presence.gd")

## What a room screen shows for a partner: nothing, "Add friend", or "Request sent".
const HIDDEN := ""
const ADDABLE := "addable"
const REQUESTED := "requested"

## () -> {server, owner} of the signed-in player, or {}.
var scope: Callable
## (create: bool) -> the friends client (services/friends_client.gd), or null.
var friends: Callable
var roster: RefCounted
var safety: RefCounted

func _init(scope_source: Callable, friends_source: Callable, roster_store: RefCounted = null, safety_store: RefCounted = null) -> void:
	scope = scope_source
	friends = friends_source
	roster = roster_store if roster_store != null else FriendRoster.shared()
	safety = safety_store if safety_store != null else SafetyStore.new()

## HIDDEN for a friend, a pending request either way, a blocked or reported
## partner, or no partner; REQUESTED once this player sent one; else ADDABLE.
## `family` and `room` name the room ("relay" or "legacy" and its id).
func state(peer: String, family: String = "", room: String = "") -> String:
	var current: Dictionary = scope.call() if scope.is_valid() else {}
	if current.is_empty() or not Presence.valid_id(peer) or peer == current.owner: return HIDDEN
	if not family.is_empty():
		# One read of the safety record: a blocked partner or room, or a report
		# about this room waiting to be sent.
		var record: Dictionary = safety.read(str(current.owner))
		if not record.get("ok", false) or SafetyStore.suppressed_rooms.has(str(current.owner) + ":" + family + ":" + room): return HIDDEN
		var kept: Dictionary = record.value
		if kept.blocked_rooms.has(family + ":" + room) or peer in kept.blocked_players or kept.pending.get("room_id") == room: return HIDDEN
	match roster.status(str(current.server), str(current.owner), peer):
		"outgoing": return REQUESTED
		"accepted", "incoming": return HIDDEN
	return ADDABLE

## Sends the friend request. True when the server took it.
func send(peer: String) -> bool:
	if state(peer) != ADDABLE: return false
	var client: RefCounted = friends.call(true) if friends.is_valid() else null
	if client == null: return false
	return await client.add_friend(peer)

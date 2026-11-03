extends RefCounted
## The partner's name in a public duel's room, for every room surface (the
## room's own strip and waiting card, Your rooms, Replays). Such a room names
## its partner by a stand-in id that is no player (backend v2 room masking), so
## the friend resolver (services/friend_nicknames.gd) would only ever say "a
## friend" there. Here the partner is who the duel says: your party partner or
## a friend by their own name, a stranger by the name they chose to show, else
## "A player". Any other room answers "", and its surface names its friend as
## before. No request, no id ever shown.
const DuelsClient = preload("res://services/duels_client.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

## "" for a room that is not a public duel's. `friend_name(id)` names a partner this phone knows by id.
static func public_partner(room_id: String, friend_name: Callable = Callable()) -> String:
	var seat := DuelsClient.room_partner(room_id)
	if seat.is_empty(): return ""
	var friend := str(seat.get("friend", ""))
	if not friend.is_empty() and friend_name.is_valid():
		var named := str(friend_name.call(friend))
		if not named.is_empty(): return named
	var label := str(seat.get("label", ""))
	return label if not label.is_empty() else PlayerCopy.PUBLIC_A_PLAYER

## Whether a room's partner presence may show: never in a public duel's room, whose partner may be someone you don't know.
static func presence_shown(room_id: String) -> bool:
	return not DuelsClient.public_room(room_id)

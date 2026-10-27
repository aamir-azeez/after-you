extends RefCounted
## What each slot's pip wears in a room's world: {"p0": look, "p1": look}, for
## IslandWorld.wear_slots(). Cosmetics are strictly per player, so each slot
## wears its own player's look and nothing is shared:
## - live(): the viewer's slot wears their own look (services/own_look.gd) and
##   the partner's slot the look their partner wore when this phone last heard
##   (services/turn_looks.gd members). A recording that plays in the turn (the
##   partner's first turn, played back while the viewer answers it) dresses
##   its slot in that turn's own look.
## - replay(): every slot in its recording's own look, whatever either player
##   wears now. A turn this phone never heard a look for plays in the default.
## Rooms name the viewer's slot in `player_slot` (p0 hosts, p1 joined).
const OwnLook = preload("res://services/own_look.gd")
const TurnLooks = preload("res://services/turn_looks.gd")
const SLOTS: Array[String] = ["p0", "p1"]

static func live(room: Dictionary, recordings: Array = [], looks: RefCounted = null) -> Dictionary:
	var store: RefCounted = looks if looks != null else TurnLooks.shared()
	var mine := str(room.get("player_slot", ""))
	if not mine in SLOTS: return replay(recordings, store)
	var partner_slot := "p1" if mine == "p0" else "p0"
	var partner: Variant = room.get("guest_id") if mine == "p0" else room.get("host_id")
	var result := {mine: OwnLook.outfit(), partner_slot: store.member(str(partner)) if partner is String else {}}
	result.merge(replay(recordings, store), true)
	return result

static func replay(recordings: Array, looks: RefCounted = null) -> Dictionary:
	var store: RefCounted = looks if looks != null else TurnLooks.shared()
	var result := {}
	for recording: Variant in recordings:
		if not recording is Dictionary: continue
		var slot := str(recording.get("player_slot", ""))
		var recording_hash := str(recording.get("recording_hash", ""))
		if slot in SLOTS and TurnLooks.valid_hash(recording_hash): result[slot] = store.look(recording_hash)
	return result

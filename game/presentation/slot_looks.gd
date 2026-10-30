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
##   A turn this phone holds unsent (`unsent`: the Watch preview of a turn not
##   saved yet) is the viewer's own, played just now, so it wears their look
##   until this phone keeps the look it was accepted in.
## - solo(): both pips are the player's own, so both wear their look now,
##   live and in replays alike (solo turns keep no looks of their own).
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

static func solo() -> Dictionary:
	var own := OwnLook.outfit()
	var result := {}
	for slot: String in SLOTS: result[slot] = own.duplicate()
	return result

static func replay(recordings: Array, looks: RefCounted = null, unsent: Array = []) -> Dictionary:
	var store: RefCounted = looks if looks != null else TurnLooks.shared()
	var result := {}
	for recording: Variant in recordings:
		if not recording is Dictionary: continue
		var slot := str(recording.get("player_slot", ""))
		var recording_hash := str(recording.get("recording_hash", ""))
		if not slot in SLOTS or not TurnLooks.valid_hash(recording_hash): continue
		result[slot] = OwnLook.outfit() if recording_hash in unsent and not store.has(recording_hash) else store.look(recording_hash)
	return result

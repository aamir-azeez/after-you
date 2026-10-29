extends RefCounted
## Reactions made during a run: the faces a player taps while playing, each at
## a tick of the turn's own step count. Presentation only: a track lives beside
## its recording (services/run_reaction_store.gd keeps it by recording hash) and
## is never part of the recording, its hash, a checkpoint, a draft or a replay's
## bytes, so a turn plays and verifies the same with or without one. The server
## takes the same shape with a turn (backend src/v2/run-reactions.ts).
##
## A track is an Array of {"tick": int, "id": face}, ticks strictly rising, ids
## from services/reaction_catalog.gd. This object records one turn's track and
## its limits; Cursor plays a recorded one back.
const Catalog = preload("res://services/reaction_catalog.gd")
const Typed = preload("res://services/typed_values.gd")
const TICK_RATE := 30
## Three seconds between reactions, counted in the turn's own ticks.
const COOLDOWN_TICKS := 90
const MAX_PER_TURN := 20
## How long a spirit holds the face and its bubble shows.
const FACE_SECONDS := 2.0
const BUBBLE_SECONDS := 1.6
## A recorded reaction is shown on its own tick. One the playback reaches more
## than this many ticks late (the ticks a Skip to end or a resumed draft stepped
## silently) is passed over, so nothing bursts out afterwards.
const LATE_TICKS := 6

var entries: Array = []

## Whether a reaction may be made on `tick`: under the cap, and the cooldown since the last one has run.
func can_react(tick: int) -> bool:
	return entries.size() < MAX_PER_TURN and (entries.is_empty() or tick >= int(entries[-1].tick) + COOLDOWN_TICKS)

func full() -> bool:
	return entries.size() >= MAX_PER_TURN

## How much of the cooldown is still ahead on `tick`, 1 to 0.
func cooldown(tick: int) -> float:
	if entries.is_empty() or full(): return 0.0
	return clampf(float(int(entries[-1].tick) + COOLDOWN_TICKS - tick) / float(COOLDOWN_TICKS), 0.0, 1.0)

## Records `face` on `tick`. Returns its index in the track (its ordinal), or -1 when refused.
func add(tick: int, face: String) -> int:
	if not Catalog.is_face(face) or tick < 0 or not can_react(tick): return -1
	entries.append({"tick": tick, "id": face})
	return entries.size() - 1

## A copy of the track, as it is sent and kept.
func track() -> Array:
	return entries.duplicate(true)

## A track read from a server reply or a file, or [] when anything in it is out
## of shape (the whole track is refused, as the server refuses it).
## `duration_ticks` >= 0 also bounds the last tick by the recording's length.
## `received`: the track came from the server, so a well-formed face this build
## does not know plays as Catalog.FALLBACK_FACE instead of refusing the track.
static func parse(value: Variant, duration_ticks: int = -1, received: bool = false) -> Array:
	if not value is Array or value.is_empty() or value.size() > MAX_PER_TURN: return []
	var parsed: Array = []
	var previous := -1
	for item: Variant in value:
		if not item is Dictionary or item.size() != 2 or not Typed.whole_number(item.get("tick")): return []
		var face: String = Catalog.shown_face(item.get("id")) if received else str(item.get("id")) if Catalog.is_face(item.get("id")) else ""
		if face.is_empty(): return []
		var tick := int(item.tick)
		if tick <= previous: return []
		previous = tick
		parsed.append({"tick": tick, "id": face})
	if duration_ticks >= 0 and previous > duration_ticks: return []
	return parsed


## Plays a recorded track back as its turn is stepped: due(tick) on each shown
## tick gives the reactions that fall on it, by their index in the track.
class Cursor extends RefCounted:
	var entries: Array = []
	var _next := 0
	func _init(track: Array) -> void:
		entries = track
	## The indexes of the reactions due on `tick`, oldest first. Any passed more
	## than LATE_TICKS ago are dropped without showing.
	func due(tick: int) -> Array[int]:
		var found: Array[int] = []
		while _next < entries.size() and int(entries[_next].tick) <= tick:
			if tick - int(entries[_next].tick) <= LATE_TICKS: found.append(_next)
			_next += 1
		return found

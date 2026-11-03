extends RefCounted
## The race ghost's data (race-picker boards 4A and 5C): in a ghost race against
## a board run, each turn plays that run's matching turn as a see-through pip
## beside the player (presentation/race_ghost_view.gd draws it).
##
## - Which run: the ghost race played in the room (services/duels_client.gd
##   ghost_race, from this session's duel reads; one lobby read when a duel
##   room has none), whose `ghost` names the board run's entry_id and
##   replay_hash (backend duels/model.ts Ghost). The developers' Our run has
##   no ghost yet: its recordings don't ship.
## - The replay: fetched once from the board (services/leaderboard_client.gd
##   replay_blob) and kept still encoded and hash-checked in the shared blob
##   format, beside a friend duel's other run (services/duel_their_run.gd, by
##   the race's duel_id, so account erasure clears it with the rest). Decoded
##   on a worker. release_ended() drops the copy once its race has ended.
## - The track: services/race_ghost_track.gd, on a worker, once per stage and
##   role, kept in memory for the race being played only.
## - Who and how: the raced player's look from the race (`ghost.looks`, slot
##   order) and their name from the board this phone last read, else "" (the
##   view writes "Recorded run").
##
## Requests: at most one replay read per race (usually answered from the
## server's cache, no Durable Object request), and one board read kept a
## minute for the name. Nothing per frame or per tick.
const DuelsClient = preload("res://services/duels_client.gd")
const LeaderboardClient = preload("res://services/leaderboard_client.gd")
const TheirRun = preload("res://services/duel_their_run.gd")
const Track = preload("res://services/race_ghost_track.gd")
const Reaper = preload("res://services/worker_reaper.gd")
const Outfit = preload("res://services/outfit.gd")

## Erasure (owner, 2026-11-03): true keeps playing the raced run from this
## phone's copy until the race ends, even after the board stops serving it (an
## account erased, or the run left the top 10; the board answers both the same
## way). false drops the ghost from the next turn on once the board stops
## serving it: each turn asks the board again (one read, usually cached).
const KEEP_COPY_UNTIL_RACE_ENDS := true

var _api: Node
var _owner := ""
## The race whose parts and tracks are in memory, its parts, and its tracks by "stage|role".
var _duel_id := ""
var _parts: Array = []
var _tracks: Dictionary = {}
## Duel rooms this session already read the lobby for, so a room with no ghost race asks once.
var _asked_rooms: Dictionary = {}

static var _shared: RefCounted

static func shared(api: Node, owner: String) -> RefCounted:
	if _shared == null or _shared._api != api or _shared._owner != owner: _shared = load("res://services/race_ghost.gd").new(api, owner)
	return _shared

func _init(api: Node, owner: String) -> void:
	_api = api
	_owner = owner

## The ghost for this turn: {slot, points, duration_ticks, look, name} or {}.
## `room_id`: the duel room being played; `duel_room`: whether the room says it is one.
func turn(room_id: String, duel_room: bool, chapter_key: String, stage_index: int, role: String) -> Dictionary:
	var race := await _race(room_id, duel_room)
	var ghost: Variant = race.get("ghost")
	if not ghost is Dictionary or ghost.source != "board" or ghost.get("replay_hash") == null or ghost.get("entry_id") == null: return {}
	if not race.status in ["running", "challenged"]: return {}
	var parts := await _parts_of(race, chapter_key)
	if stage_index < 0 or stage_index >= parts.size(): return {}
	var key := "%d|%s" % [stage_index, role]
	if not _tracks.has(key):
		var built: Variant = await Reaper.run(Callable(Track, "build").bind(chapter_key, parts[stage_index].pair, role), true)
		if race.duel_id != _duel_id: return {}
		_tracks[key] = built if built is Dictionary else {}
	var track: Dictionary = _tracks[key]
	if track.is_empty(): return {}
	var index := 1 if str(track.slot) == "p1" else 0
	var shown := track.duplicate()
	shown["look"] = Outfit.from(ghost.looks[index]) if ghost.get("looks") is Array and ghost.looks.size() > index else {}
	shown["name"] = await _name(race, index)
	return shown

## Keeps the raced run's replay as soon as a race starts, so a run that leaves
## the top 10 before the first turn still plays (no decode; a failure retries at the turn).
func prefetch(race: Dictionary) -> void:
	var ghost: Variant = race.get("ghost")
	if not KEEP_COPY_UNTIL_RACE_ENDS or not ghost is Dictionary or ghost.get("replay_hash") == null or ghost.get("entry_id") == null: return
	if not TheirRun.kept_run(_owner, str(race.duel_id)).get("digest", "") == ghost.replay_hash: await _fetch(race)

## Lets go of the copy and tracks of every ghost race in `lobby` that has ended.
func release_ended(lobby: Dictionary) -> void:
	for view: Dictionary in lobby.get("duels", []):
		if view.kind != "ghost" or view.status in ["running", "challenged"]: continue
		TheirRun.forget(_owner, str(view.duel_id))
		if view.duel_id == _duel_id: _forget_memory()

func _race(room_id: String, duel_room: bool) -> Dictionary:
	var client: RefCounted = DuelsClient.shared(_api, _owner)
	var race: Dictionary = client.ghost_race(room_id)
	if race.is_empty() and duel_room and not _asked_rooms.has(room_id):
		_asked_rooms[room_id] = true
		var answer: Dictionary = await client.lobby()
		if answer.get("ok", false):
			release_ended(answer.lobby)
			race = client.ghost_race(room_id)
	return race

## The race's decoded parts, from this phone's copy or fetched once.
func _parts_of(race: Dictionary, chapter_key: String) -> Array:
	var duel_id := str(race.duel_id)
	if duel_id != _duel_id:
		_forget_memory()
		_duel_id = duel_id
	var kept: Dictionary = TheirRun.kept_run(_owner, duel_id) if KEEP_COPY_UNTIL_RACE_ENDS else {}
	if kept.get("digest", "") != race.ghost.replay_hash:
		kept = await _fetch(race)
	elif not _parts.is_empty(): return _parts
	if kept.is_empty():
		# The board no longer serves it: with the copy dropped on erasure, no ghost from here on.
		if not KEEP_COPY_UNTIL_RACE_ENDS: _forget_memory()
		return []
	if not _parts.is_empty(): return _parts
	var parts: Variant = await Reaper.run(Callable(TheirRun, "parts").bind(kept, chapter_key), true)
	if duel_id != _duel_id: return []
	if not parts is Array or parts.is_empty():
		TheirRun.forget(_owner, duel_id)
		return []
	_parts = parts
	return _parts

func _fetch(race: Dictionary) -> Dictionary:
	var answer: Dictionary = await LeaderboardClient.shared(_api, _owner).replay_blob(str(race.board), str(race.ghost.entry_id), str(race.ghost.replay_hash))
	if not answer.get("ok", false): return {}
	if KEEP_COPY_UNTIL_RACE_ENDS: TheirRun.keep(_owner, str(race.duel_id), answer.blob)
	return answer.blob

## The raced player's name as the board shows it now, or "" (names hidden, or the run no longer listed).
func _name(race: Dictionary, index: int) -> String:
	var answer: Dictionary = await LeaderboardClient.shared(_api, _owner).board(str(race.board))
	if not answer.get("ok", false): return ""
	for row: Dictionary in answer.view.get("top", []):
		if row.entry_id == race.ghost.entry_id and row.get("names") is Array and row.names.size() > index: return str(row.names[index])
	return ""

func _forget_memory() -> void:
	_duel_id = ""
	_parts = []
	_tracks = {}

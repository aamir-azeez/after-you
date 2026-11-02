extends RefCounted
## What a duel hint (services/live_connection.gd duels_changed) asks of the
## Duels lobby (presentation/duels/duels_flow.gd), and the duels waiting for a
## read of their own. Pure: no nodes, no requests, no clock.
##
## A hint naming a duel the kept lobby shows, newer than its copy there, reads
## only that duel (2 Durable Object requests: sign-in and its board), which
## services/duels_client.gd puts into the kept lobby. A hint that changes the
## list itself reads the whole lobby (3 requests plus one per chapter holding a
## duel), spaced by the flow: the party (no duel named), a duel the lobby lacks
## (a new challenge or ghost race), and a duel read that came back ended or
## failed. When the duels waiting would cost more read one by one than the
## lobby once, the lobby reads instead.
const NONE := ""
const DUEL := "duel"
const LOBBY := "lobby"
## Requests of a lobby read beyond one per chapter (backend duels/routes.ts lobby:
## sign-in, own party row, partner's party row), and of one duel's read.
const LOBBY_BASE_REQUESTS := 3
const DUEL_REQUESTS := 2

## duel_id -> the newest change time a hint named for it.
var _waiting: Dictionary = {}

## What a hint for `duel_id` (empty: the party or the list) changed at `at_ms` asks, given the kept `lobby`.
static func route(lobby: Dictionary, duel_id: String, at_ms: int) -> String:
	if duel_id.is_empty(): return LOBBY
	var view := _find(lobby, duel_id)
	if view.is_empty(): return LOBBY
	return NONE if int(view.updated_ms) >= at_ms else DUEL

## Keeps a duel waiting for its own read; repeats keep the newest time.
func note(duel_id: String, at_ms: int) -> void:
	_waiting[duel_id] = maxi(at_ms, int(_waiting.get(duel_id, at_ms)))

func waiting() -> int:
	return _waiting.size()

func clear() -> void:
	_waiting.clear()

## Whether reading the waiting duels one by one would cost more than one lobby read of `lobby`.
func cheaper_as_lobby(lobby: Dictionary) -> bool:
	return _waiting.size() * DUEL_REQUESTS > lobby_requests(lobby)

## Durable Object requests one lobby read costs for `lobby`: the base and one per chapter board holding a duel.
static func lobby_requests(lobby: Dictionary) -> int:
	var boards := {}
	for view: Dictionary in lobby.get("duels", []): boards[view.board] = true
	return LOBBY_BASE_REQUESTS + boards.size()

## The next waiting duel still worth a read: its kept copy from `lobby`, or {}
## when none is left. A duel the lobby now holds at least as new as its hint,
## or no longer shows, goes without a read.
func next(lobby: Dictionary) -> Dictionary:
	while not _waiting.is_empty():
		var duel_id: String = _waiting.keys()[0]
		var at := int(_waiting[duel_id])
		_waiting.erase(duel_id)
		if route(lobby, duel_id, at) == DUEL: return _find(lobby, duel_id)
	return {}

## Whether a duel's read changes the lobby's list beyond its own tile: it
## ended (no longer waiting or running) where the kept copy `before` had not.
static func ended(before: Dictionary, after: Dictionary) -> bool:
	var open := ["challenged", "running"]
	return str(before.get("status", "")) in open and not str(after.get("status", "")) in open

static func _find(lobby: Dictionary, duel_id: String) -> Dictionary:
	for view: Dictionary in lobby.get("duels", []):
		if view.duel_id == duel_id: return view
	return {}

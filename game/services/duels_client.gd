extends RefCounted
## The duel requests (backend src/duels/routes.ts) through the app's one
## request queue (services/rooms_api.gd request_json), and what this phone
## keeps of them:
## - lobby(): GET /v1/duels, the party, its invites and every duel this player
##   is in. Kept in memory for the pages, and two small facts are saved
##   (atomic_file, user://duels.json, per player): which rooms are duel rooms,
##   for the Duel tag in Your rooms, and which won duels already rang their
##   bell (bell_due, mark_rung), so each win rings once, after a restart too,
##   as a leaderboard celebration shows once. A duel's clear needs nothing
##   kept: its room is an ordinary room, which the chapter chain already counts.
## - ghosts(): GET /v1/duels/ghosts, kept for GHOSTS_KEEP_MS.
## - duel(): one duel with what it paid this player.
## - the party, challenge and duel actions. Challenges and ghost races carry an
##   idempotency key made once per tap, so a retry answers the duel it made.
## Every answer is checked before it is used; one this build cannot read is a
## failure, never a partial page.
## - looks: while the server has looks on, each side carries what its members
##   wear (`looks`, in `members` order), a board ghost its row's, and the lobby
##   the partner's (`party.partner_look`). Kept as sent ({} for anything that is
##   not a Dictionary); the pages clean them (services/outfit.gd) as they draw,
##   so only offered items ever show. A server without them reads as the default.
## - public duels (services/public_duels_client.gd): a public duel is a friend
##   duel whose seats fill from the list. Its view carries `public` and each side
##   `seats` ({open, you, label}); members hold ids only for this player and the
##   players this phone already knows, so a stranger is a seat, never an id. Its
##   room is kept as kind "public" (public_room()), which room screens read to
##   offer no friend request, nickname or photo on the stand-in partner. The
##   lobby's `public` part says whether this player and the partner have the
##   switch on and how many duels count toward the limit. A detail read of a
##   public duel carries `held`: the duel extra held for this player.
## - hints_sent(): whether the latest lobby or duel read said duel changes also
##   come over the live socket (duel_hints_version), so the screens may read at
##   their backup pace. A server rolled back to one without hints says nothing,
##   and the next read brings the old pace back.
const Typed = preload("res://services/typed_values.gd")
const AtomicFile = preload("res://services/atomic_file.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const TheirRun = preload("res://services/duel_their_run.gd")
const Reaper = preload("res://services/worker_reaper.gd")
const PREFIX := "/v1/duels"
const SAVE_PATH := "user://duels.json"
const GHOSTS_KEEP_MS := 60_000
const MAX_DUELS := 64
const STATUSES := ["challenged", "running", "decided", "declined", "withdrawn", "expired", "pair_gone", "unfinished"]
const CHECKS := ["none", "waiting", "passed", "failed", "error"]
const OUTCOMES := ["won", "lost", "draw", "none"]
## The duel limits when no lobby was read yet: the server's own (backend duels/rules.ts
## MAX_FRIEND_DUELS_PER_PAIR, MAX_GHOST_RACES_PER_PAIR), which every lobby read reports.
const FRIEND_LIMIT := 10
const GHOST_LIMIT := 3

var _api: Node
var _owner: String
var _path := SAVE_PATH
var _lobby: Dictionary = {}
var _ghosts: Dictionary = {}
var _ghosts_at := -GHOSTS_KEEP_MS
var _hints := false
## {rooms: {room_id: kind}, rung: {duel_id: true} oldest first} for this player.
var _saved: Dictionary = {}
## The ghost races this session read, by the room each is played in (room_id -> the newest view), for the race ghost (services/race_ghost.gd).
var _ghost_rooms: Dictionary = {}

static var _shared: RefCounted

## One client per signed-in player, so the pages, Home and Your rooms share it.
static func shared(api: Node, owner: String) -> RefCounted:
	if _shared == null or _shared._api != api or _shared._owner != owner: _shared = load("res://services/duels_client.gd").new(api, owner)
	return _shared

func _init(api: Node, owner: String, path: String = SAVE_PATH) -> void:
	_api = api
	_owner = owner
	_path = path
	_saved = _read_saved()

## {ok, lobby} or {ok: false, code}.
func lobby() -> Dictionary:
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_GET, PREFIX)
	if not response.get("ok", false): return {"ok": false, "code": str(response.get("code", ""))}
	_note_hints(response.get("data"))
	var checked := valid_lobby(response.get("data"))
	if checked.is_empty(): return {"ok": false, "code": "invalid_duels"}
	return {"ok": true, "lobby": _take(checked)}

## The last lobby read, or {}.
func last_lobby() -> Dictionary:
	return _lobby

## How many duels of `kind` ("friend" or "ghost") a pair may have going, as the last lobby read said.
func limit(kind: String) -> int:
	return int(_lobby.get("limits", {}).get(kind, GHOST_LIMIT if kind == "ghost" else FRIEND_LIMIT))

## Whether the pair already has as many ghost races going as it may (limit("ghost")),
## counted as the server counts them (backend duels/routes.ts openFor): open races
## of the current pair whose own side has not finished. From the last lobby read
## (no request), so the race picker greys its rows before a tap.
func ghost_races_full() -> bool:
	return ghost_races_going(_lobby) >= limit("ghost")

static func ghost_races_going(lobby: Dictionary) -> int:
	var partner: Variant = lobby.get("party", {}).get("partner")
	var going := 0
	for view: Dictionary in lobby.get("duels", []):
		if view.kind != "ghost" or not view.status in ["challenged", "running"]: continue
		var own: Variant = view.sides[view.mine]
		if own is Dictionary and not own.finished and (partner == null or partner in own.members): going += 1
	return going

## {ok, boards: [{board, developer, top}]}, kept a minute.
func ghosts(fresh: bool = false) -> Dictionary:
	if not fresh and not _ghosts.is_empty() and Time.get_ticks_msec() - _ghosts_at < GHOSTS_KEEP_MS: return {"ok": true, "boards": _ghosts.boards}
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_GET, PREFIX + "/ghosts")
	if not response.get("ok", false): return {"ok": false, "code": str(response.get("code", ""))}
	var data: Variant = response.get("data")
	if not data is Dictionary or not data.get("boards") is Array: return {"ok": false, "code": "invalid_duels"}
	var boards: Array = []
	for item: Variant in data.boards:
		if not item is Dictionary or not _board(item.get("board")) or not item.get("top") is Array: return {"ok": false, "code": "invalid_duels"}
		var developer: Variant = item.get("developer")
		var top: Array = []
		for row: Variant in item.top:
			if not row is Dictionary or not _entry(row.get("entry_id")) or not Typed.whole_number(row.get("ticks")) or not Typed.whole_number(row.get("rank")): return {"ok": false, "code": "invalid_duels"}
			top.append({"entry_id": row.entry_id, "ticks": int(row.ticks), "rank": int(row.rank), "names": row.get("names") if row.get("names") is Array else null})
		boards.append({"board": item.board, "developer": int(developer) if Typed.whole_number(developer) else -1, "top": top})
	_ghosts = {"boards": boards}
	_ghosts_at = Time.get_ticks_msec()
	return {"ok": true, "boards": boards}

## {ok, duel, pay, win_bonus} for one duel. `win_bonus`: a friend duel's, or on a ghost race the
## server's `ghost_bonus`, its first win over Our run on the board.
func duel(board: String, duel_id: String) -> Dictionary:
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_GET, "%s/%s/%s" % [PREFIX, board, duel_id])
	if response.get("ok", false): _note_hints(response.get("data"))
	return _duel_answer(response, true)

## Whether the latest lobby or duel read said duel changes come as live hints.
func hints_sent() -> bool:
	return _hints

func _note_hints(data: Variant) -> void:
	_hints = data is Dictionary and Typed.equal(data.get("duel_hints_version"), 1)

func invite(friend: String) -> Dictionary: return await _party("invite", {"friend": friend})
func accept_party(from: String) -> Dictionary: return await _party("accept", {"from": from})
func dismiss_party(from: String) -> Dictionary: return await _party("dismiss", {"from": from})
func cancel_invite() -> Dictionary: return await _party("cancel", {})
func leave_party() -> Dictionary: return await _party("leave", {})

## A challenge to `friend`'s pair on `board`. `key` is made once per tap (new_key()).
func challenge(friend: String, board: String, key: String) -> Dictionary:
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_POST, PREFIX + "/challenge", {"schema_version": 1, "idempotency_key": key, "friend": friend, "board": board})
	return _duel_answer(response)

## A ghost race on `board` against a board run (`entry_id`) or the developers' time ("developer").
func race_ghost(board: String, source: String, entry_id: Variant, key: String) -> Dictionary:
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_POST, PREFIX + "/ghost", {"schema_version": 1, "idempotency_key": key, "board": board, "source": source, "entry_id": entry_id})
	return _duel_answer(response)

## accept, decline, leave or sync on one duel.
func act(board: String, duel_id: String, action: String) -> Dictionary:
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_POST, "%s/%s/%s/%s" % [PREFIX, board, duel_id, action], {"schema_version": 1})
	return _duel_answer(response)

## {ok, parts} for the other pair's run in friend duel `view`, in chapter `chapter_key`,
## or {ok: false, code}. The phone's own copy plays first; otherwise the server's
## is fetched, kept here, and only then acknowledged, so the server lets its copy
## go only once this phone has one (services/duel_their_run.gd).
func their_run(view: Dictionary, chapter_key: String) -> Dictionary:
	var duel_id := str(view.get("duel_id", ""))
	var board := str(view.get("board", ""))
	var kept := TheirRun.kept_run(_owner, duel_id)
	if kept.is_empty():
		var response: Dictionary = await _api.request_json(HTTPClient.METHOD_GET, "%s/%s/%s/their-run" % [PREFIX, board, duel_id])
		if not response.get("ok", false): return {"ok": false, "code": str(response.get("code", ""))}
		kept = TheirRun.valid(response.get("data"), duel_id, board)
		if kept.is_empty(): return {"ok": false, "code": "invalid_replay"}
		var parts := await _their_parts(kept, chapter_key)
		if parts.is_empty(): return {"ok": false, "code": "invalid_replay"}
		# Acknowledged only once kept on disk.
		if TheirRun.keep(_owner, duel_id, kept): _confirm_their_run(board, duel_id, kept)
		return {"ok": true, "parts": parts}
	var held := await _their_parts(kept, chapter_key)
	if held.is_empty():
		# A copy that no longer decodes is dropped, and the next tap fetches the run again.
		TheirRun.forget(_owner, duel_id)
		return {"ok": false, "code": "invalid_replay"}
	# An acknowledgement that was lost goes again; one the server took is never sent twice.
	if not kept.acked: _confirm_their_run(board, duel_id, kept)
	return {"ok": true, "parts": held}

## Tells the server this phone keeps the run, and notes that it heard back.
func _confirm_their_run(board: String, duel_id: String, kept: Dictionary) -> void:
	if not await _ack_their_run(board, duel_id, kept.digest): return
	var done := kept.duplicate()
	done["acked"] = true
	TheirRun.keep(_owner, duel_id, done)

func _their_parts(kept: Dictionary, chapter_key: String) -> Array:
	var parts: Variant = await Reaper.run(Callable(TheirRun, "parts").bind(kept, chapter_key), true)
	return parts if parts is Array else []

func _ack_their_run(board: String, duel_id: String, digest: String) -> bool:
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_POST, "%s/%s/%s/their-run/ack" % [PREFIX, board, duel_id], {"schema_version": 1, "digest": digest})
	return bool(response.get("ok", false))

static func new_key() -> String:
	return RoomsApi.new_key()

## The ghost race played in `room_id` as this session last read it, or {} (no request).
func ghost_race(room_id: String) -> Dictionary:
	return _ghost_rooms.get(room_id, {})

## "friend", "ghost", "public" or "" for a room this phone knows as a duel room.
func room_kind(room_id: String) -> String:
	return str(_saved.get("rooms", {}).get(room_id, ""))

## The player's Public duels switch as the server last said (a lobby read or the switch's own
## answer), kept in this file so Settings shows it before any read this launch.
func public_on() -> bool:
	return _saved.get("public_on", false) == true

func note_public(on: bool) -> void:
	if public_on() == on or _owner.is_empty(): return
	_saved["public_on"] = on
	_save()

## Whether a won duel's result has not rung its bell on this phone yet.
func bell_due(view: Dictionary) -> bool:
	var result: Variant = view.get("result")
	return result is Dictionary and result.get("outcome") == "won" and _entry(view.get("duel_id")) and not _saved.rung.has(view.duel_id)

## The duel's bell rang: it never rings again for this player.
func mark_rung(duel_id: String) -> void:
	if _owner.is_empty() or not _entry(duel_id) or _saved.rung.has(duel_id): return
	_saved.rung[duel_id] = true
	while _saved.rung.size() > MAX_DUELS * 2: _saved.rung.erase(_saved.rung.keys()[0])
	_save()

func _party(action: String, body: Dictionary) -> Dictionary:
	var sent := body.duplicate()
	sent["schema_version"] = 1
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_POST, "%s/party/%s" % [PREFIX, action], sent)
	if not response.get("ok", false): return {"ok": false, "code": str(response.get("code", ""))}
	_note_hints(response.get("data"))
	var checked := valid_lobby(response.get("data"))
	if checked.is_empty(): return {"ok": false, "code": "invalid_duels"}
	return {"ok": true, "lobby": _take(checked)}

## A duel answer from another duel route (services/public_duels_client.gd), checked and kept like this client's own.
func duel_answer(response: Dictionary, detail: bool = false) -> Dictionary:
	return _duel_answer(response, detail)

## Whether `room_id` is a public duel's room as the signed-in player's client knows it
## (services/partner_friends.gd, the photo card): its partner is a stand-in, never a friend.
static func public_room(room_id: String) -> bool:
	return _shared != null and not room_id.is_empty() and _shared.room_kind(room_id) == "public"

func _duel_answer(response: Dictionary, detail: bool = false) -> Dictionary:
	if not response.get("ok", false): return {"ok": false, "code": str(response.get("code", "")), "status": int(response.get("status", 0))}
	var data: Variant = response.get("data")
	var view := valid_view(data.get("duel") if data is Dictionary else null)
	if view.is_empty(): return {"ok": false, "code": "invalid_duels"}
	_remember([view])
	_keep_in_lobby(view)
	var answer := {"ok": true, "duel": view}
	if detail:
		answer["pay"] = _pay(data.get("pay"))
		answer["win_bonus"] = _bonus(data.get("ghost_bonus" if view.kind == "ghost" else "win_bonus"))
		answer["held"] = _held(data.get("held")) if view.has("public") else {}
	return answer

## Puts a duel's newer copy into the kept lobby, so the lobby under a page
## shows what an action answered (a duel just left) before the next read.
func _keep_in_lobby(view: Dictionary) -> void:
	var duels: Array = _lobby.get("duels", [])
	for index in range(duels.size()):
		if duels[index].duel_id != view.duel_id: continue
		if _older(view, duels[index]): return
		var kept := _lobby.duplicate()
		kept.duels = duels.duplicate()
		kept.duels[index] = view
		_lobby = kept
		return

## Keeps a lobby the server answered (a read or a party action). A read that
## went out before an action (Leave) answers with older copies of its duels:
## the newer copies kept here stay. Duels the server dropped stay dropped.
func _take(checked: Dictionary) -> Dictionary:
	var held: Dictionary = {}
	for view: Dictionary in _lobby.get("duels", []): held[view.duel_id] = view
	for index in range(checked.duels.size()):
		var fresh: Dictionary = checked.duels[index]
		if held.has(fresh.duel_id) and _older(fresh, held[fresh.duel_id]): checked.duels[index] = held[fresh.duel_id]
	_lobby = checked
	_remember(checked.duels)
	if checked.has("public"): note_public(bool(checked.public.on))
	return checked

## Whether `view` is an older copy of the same duel than `than`.
static func _older(view: Dictionary, than: Dictionary) -> bool:
	return int(view.updated_ms) < int(than.updated_ms)

## Notes duel rooms, and saves only when they changed.
func _remember(views: Array) -> void:
	if _owner.is_empty(): return
	var rooms: Dictionary = _saved.get("rooms", {}).duplicate()
	for view: Dictionary in views:
		var own: Dictionary = view.sides[view.mine]
		if own.get("room_id") is String and not str(own.room_id).is_empty():
			rooms[own.room_id] = "public" if view.has("public") else view.kind
			if view.kind == "ghost" and not (_ghost_rooms.has(own.room_id) and _older(view, _ghost_rooms[own.room_id])): _ghost_rooms[own.room_id] = view
	if rooms == _saved.get("rooms", {}): return
	while rooms.size() > MAX_DUELS * 2: rooms.erase(rooms.keys()[0])
	_saved.rooms = rooms
	_save()

## This player's part of the file, beside the other players' parts.
func _save() -> void:
	if _owner.is_empty(): return
	var all := _read_all(_path)
	all[_owner] = {"rooms": _saved.rooms, "rung": _saved.rung.keys(), "public_on": public_on()}
	AtomicFile.write_text(_path, JSON.stringify(all))

## Forgets a player's part of the file (account deletion); other players' parts stay.
## False when the file, or a damaged copy of it kept aside, could not be changed (services/deleted_identity_stores.gd tries again).
static func clear_owner(owner: String, path: String = SAVE_PATH) -> bool:
	# A client still holding the player (a request awaiting its answer) must never write them back.
	if _shared != null and _shared._owner == owner:
		_shared._owner = ""
		_shared = null
	var all := _read_all(path)
	all.erase(owner)
	# Written even when nothing changed: a damaged file read as empty, and the
	# copy of it kept aside (AtomicFile.read_json), hold every player's part here.
	var saved := AtomicFile.write_text(path, JSON.stringify(all))
	return AtomicFile.remove_unreadable(path) and saved

## Every player's part of the file, or {} when no copy of it reads.
static func _read_all(path: String) -> Dictionary:
	var parsed: Variant = AtomicFile.read_json(path, func(value: Variant) -> bool: return value is Dictionary)
	return parsed if parsed is Dictionary else {}

func _read_saved() -> Dictionary:
	var mine: Variant = _read_all(_path).get(_owner)
	var rooms := {}
	var rung := {}
	if not mine is Dictionary: return {"rooms": rooms, "rung": rung, "public_on": false}
	if mine.get("rooms") is Dictionary:
		for room_id: Variant in mine.rooms:
			if Typed.valid_id(room_id) and mine.rooms[room_id] in ["friend", "ghost", "public"]: rooms[room_id] = mine.rooms[room_id]
	if mine.get("rung") is Array:
		for duel_id: Variant in (mine.rung as Array).slice(maxi((mine.rung as Array).size() - MAX_DUELS * 2, 0)):
			if _entry(duel_id): rung[duel_id] = true
	return {"rooms": rooms, "rung": rung, "public_on": mine.get("public_on") == true}

## A lobby as the server sent it, or {} when it is not one this build reads.
static func valid_lobby(value: Variant) -> Dictionary:
	if not value is Dictionary or not Typed.equal(value.get("schema_version"), 1) or not value.get("party") is Dictionary or not value.get("duels") is Array: return {}
	var party: Dictionary = value.party
	var partner: Variant = party.get("partner")
	var out: Variant = party.get("invite_out")
	if (partner != null and not _id(partner)) or (out != null and not _id(out)) or not party.get("intact") is bool or not party.get("invites_in") is Array: return {}
	for from: Variant in party.invites_in:
		if not _id(from): return {}
	var duels: Array = []
	for item: Variant in value.duels:
		var view := valid_view(item)
		if view.is_empty(): return {}
		duels.append(view)
	if duels.size() > MAX_DUELS: return {}
	var limits: Variant = value.get("limits")
	var kept := {"party": {"partner": partner, "intact": party.intact, "invites_in": party.invites_in.duplicate(), "invite_out": out, "partner_look": _look(party.get("partner_look"))}, "duels": duels,
		"limits": {"friend": _limit(limits, "friend", FRIEND_LIMIT), "ghost": _limit(limits, "ghost", GHOST_LIMIT)}}
	var public := _public_part(value.get("public"))
	if not public.is_empty(): kept["public"] = public
	return kept

## The lobby's public duels part ({version 1, on, show_name, partner_on, paused, running}), or {} without one.
static func _public_part(value: Variant) -> Dictionary:
	if not value is Dictionary or not Typed.equal(value.get("version"), 1) or not value.get("on") is bool or not value.get("show_name") is bool or not value.get("paused") is bool or not Typed.whole_number(value.get("running")): return {}
	var partner: Variant = value.get("partner_on")
	return {"on": value.on, "show_name": value.show_name, "partner_on": partner if partner is bool else null, "paused": value.paused, "running": int(value.running)}

static func _limit(limits: Variant, kind: String, fallback: int) -> int:
	var value: Variant = limits.get(kind) if limits is Dictionary else null
	return int(value) if Typed.whole_number(value) and int(value) > 0 else fallback

## One duel as the server sent it (backend duels/model.ts DuelView), or {}.
static func valid_view(value: Variant) -> Dictionary:
	if not value is Dictionary or not Typed.equal(value.get("schema_version"), 1) or not _entry(value.get("duel_id")) or not _board(value.get("board")): return {}
	if not value.get("kind") in ["friend", "ghost"] or not value.get("status") in STATUSES or not Typed.whole_number(value.get("steps")) or not value.get("sides") is Array or value.sides.size() != 2: return {}
	var mine: Variant = value.get("mine")
	if not Typed.equal(mine, 0) and not Typed.equal(mine, 1): return {}
	var sides: Array = []
	for index in range(2):
		var side: Variant = value.sides[index]
		if side == null and index == 1 and value.kind == "ghost":
			sides.append(null)
			continue
		var checked := _side(side)
		if checked.is_empty(): return {}
		sides.append(checked)
	var ghost: Variant = value.get("ghost")
	var kept_ghost: Variant = null
	if value.kind == "ghost":
		if not ghost is Dictionary or not Typed.whole_number(ghost.get("ticks")) or not ghost.get("source") in ["board", "developer"]: return {}
		# A board run's entry_id and replay_hash (backend model.ts Ghost) let the race ghost play it; a server before them sends none.
		var hash: Variant = ghost.get("replay_hash")
		kept_ghost = {"source": ghost.source, "ticks": int(ghost.ticks), "rank": int(ghost.rank) if Typed.whole_number(ghost.get("rank")) else 0, "names": ghost.get("names") if ghost.get("names") is Array else null, "looks": _looks(ghost.get("looks")),
			"entry_id": ghost.entry_id if _entry(ghost.get("entry_id")) else null, "replay_hash": hash if hash is String and hash.length() == 64 and hash.is_valid_hex_number() and hash == hash.to_lower() else null}
	var result: Variant = value.get("result")
	var kept_result: Variant = null
	if result != null:
		if not result is Dictionary or not result.get("outcome") in OUTCOMES or not result.get("reason") is String: return {}
		kept_result = {"outcome": result.outcome, "reason": result.reason, "margin_ticks": int(result.margin_ticks) if Typed.whole_number(result.get("margin_ticks")) else -1}
	var kept := {"duel_id": value.duel_id, "chapter": value.board, "board": value.board, "kind": value.kind, "status": value.status, "steps": int(value.steps),
		"mine": int(mine), "sides": sides, "ghost": kept_ghost, "result": kept_result, "eligible": value.get("eligible") == true,
		"created_ms": int(value.get("created_ms", 0)), "updated_ms": int(value.get("updated_ms", 0))}
	# A public duel: its list times, and every side's seats (a friend duel has none).
	var public: Variant = value.get("public")
	if public != null:
		if value.kind != "friend" or not public is Dictionary or not Typed.whole_number(public.get("posted_ms")) or not Typed.whole_number(public.get("open_until_ms")) or not Typed.whole_number(public.get("seats_open")): return {}
		if sides.any(func(side: Variant) -> bool: return not side is Dictionary or not side.has("seats")): return {}
		kept["public"] = {"posted_ms": int(public.posted_ms), "open_until_ms": int(public.open_until_ms), "seats_open": int(public.seats_open)}
	return kept

static func _side(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("members") is Array or value.members.size() != 2 or not value.get("you") is bool: return {}
	for member: Variant in value.members:
		if member != null and not _id(member): return {}
	if not Typed.whole_number(value.get("steps")) or not Typed.whole_number(value.get("ticks")) or not value.get("finished") is bool or not value.get("left") is bool or not value.get("check") in CHECKS: return {}
	var turn: Variant = value.get("turn")
	var side := {"members": value.members.duplicate(), "you": value.you, "steps": int(value.steps), "ticks": int(value.ticks),
		"turn": int(turn) if Typed.whole_number(turn) and int(turn) < 2 else -1, "finished": value.finished, "left": value.left, "check": value.check, "looks": _looks(value.get("looks"))}
	# A public duel's seats: open, this player's own, and a stranger's label ("" when they show no name).
	if value.has("seats"):
		var seats: Variant = value.seats
		if not seats is Array or seats.size() != 2: return {}
		var kept_seats: Array = []
		for seat: Variant in seats:
			if not seat is Dictionary or not seat.get("open") is bool or not seat.get("you") is bool: return {}
			var label: Variant = seat.get("label")
			if label != null and (not label is String or label.length() > 40): return {}
			kept_seats.append({"open": seat.open, "you": seat.you, "label": "" if label == null or seat.open else str(label)})
		side["seats"] = kept_seats
	if value.you:
		var room: Variant = value.get("room_id")
		var invite: Variant = value.get("invite_code")
		side["room_id"] = room if Typed.valid_id(room) else ""
		side["invite_code"] = invite if invite is String else ""
		side["hosting"] = value.get("hosting") == true
	return side

## Two looks in member order, as sent; {} for each one missing or not a Dictionary.
static func _looks(value: Variant) -> Array:
	var sent: Array = value if value is Array else []
	return [_look(sent[0] if sent.size() > 0 else null), _look(sent[1] if sent.size() > 1 else null)]

static func _look(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate() if value is Dictionary else {}

static func _pay(value: Variant) -> Dictionary:
	if not value is Dictionary: return {}
	var pay := {}
	for field: String in ["turns", "plain", "blooms", "duel", "duel_percent", "boost", "boost_percent", "total"]:
		if not Typed.whole_number(value.get(field)): return {}
		pay[field] = int(value[field])
	# A public duel's held duel extra, which the total leaves out until the duel pays it.
	if value.has("held"):
		if not Typed.whole_number(value.held): return {}
		pay["held"] = int(value.held)
	return pay

## A public duel's held duel extra for this player: {amount, state running|paid|forfeit, reason}, or {}.
static func _held(value: Variant) -> Dictionary:
	if not value is Dictionary or not Typed.whole_number(value.get("amount")) or not value.get("state") in ["running", "paid", "forfeit"]: return {}
	var reason: Variant = value.get("reason", "")
	return {"amount": int(value.amount), "state": value.state, "reason": str(reason) if reason is String else ""}

static func _bonus(value: Variant) -> Dictionary:
	if not value is Dictionary or not Typed.whole_number(value.get("amount")) or not value.get("counted") is bool: return {}
	return {"amount": int(value.amount), "counted": value.counted, "reason": str(value.get("reason", ""))}

static func _id(value: Variant) -> bool:
	return Typed.valid_id(value)

## Whether `value` names a duel's room as a create sends it (backend duels/routes.ts parseDuelAsk): {duel_id, board}.
static func valid_room_ask(value: Variant) -> bool:
	return value is Dictionary and value.size() == 2 and _entry(value.get("duel_id")) and _board(value.get("board"))

static func _entry(value: Variant) -> bool:
	return value is String and value.length() == 32 and value.is_valid_hex_number()

static func _board(value: Variant) -> bool:
	return value is String and value.contains("@") and value.length() <= 56

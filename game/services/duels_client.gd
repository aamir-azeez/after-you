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

var _api: Node
var _owner: String
var _path := SAVE_PATH
var _lobby: Dictionary = {}
var _ghosts: Dictionary = {}
var _ghosts_at := -GHOSTS_KEEP_MS
var _hints := false
## {rooms: {room_id: kind}, rung: {duel_id: true} oldest first} for this player.
var _saved: Dictionary = {}

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

## "friend", "ghost" or "" for a room this phone knows as a duel room.
func room_kind(room_id: String) -> String:
	return str(_saved.get("rooms", {}).get(room_id, ""))

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
		if own.get("room_id") is String and not str(own.room_id).is_empty(): rooms[own.room_id] = view.kind
	if rooms == _saved.get("rooms", {}): return
	while rooms.size() > MAX_DUELS * 2: rooms.erase(rooms.keys()[0])
	_saved.rooms = rooms
	_save()

## This player's part of the file, beside the other players' parts.
func _save() -> void:
	if _owner.is_empty(): return
	var all := _read_all(_path)
	all[_owner] = {"rooms": _saved.rooms, "rung": _saved.rung.keys()}
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
	if not mine is Dictionary: return {"rooms": rooms, "rung": rung}
	if mine.get("rooms") is Dictionary:
		for room_id: Variant in mine.rooms:
			if Typed.valid_id(room_id) and mine.rooms[room_id] in ["friend", "ghost"]: rooms[room_id] = mine.rooms[room_id]
	if mine.get("rung") is Array:
		for duel_id: Variant in (mine.rung as Array).slice(maxi((mine.rung as Array).size() - MAX_DUELS * 2, 0)):
			if _entry(duel_id): rung[duel_id] = true
	return {"rooms": rooms, "rung": rung}

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
	return {"party": {"partner": partner, "intact": party.intact, "invites_in": party.invites_in.duplicate(), "invite_out": out, "partner_look": _look(party.get("partner_look"))}, "duels": duels,
		"limits": {"friend": int(limits.get("friend", 3)), "ghost": int(limits.get("ghost", 3))} if limits is Dictionary else {"friend": 3, "ghost": 3}}

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
		kept_ghost = {"source": ghost.source, "ticks": int(ghost.ticks), "rank": int(ghost.rank) if Typed.whole_number(ghost.get("rank")) else 0, "names": ghost.get("names") if ghost.get("names") is Array else null, "looks": _looks(ghost.get("looks"))}
	var result: Variant = value.get("result")
	var kept_result: Variant = null
	if result != null:
		if not result is Dictionary or not result.get("outcome") in OUTCOMES or not result.get("reason") is String: return {}
		kept_result = {"outcome": result.outcome, "reason": result.reason, "margin_ticks": int(result.margin_ticks) if Typed.whole_number(result.get("margin_ticks")) else -1}
	return {"duel_id": value.duel_id, "chapter": value.board, "board": value.board, "kind": value.kind, "status": value.status, "steps": int(value.steps),
		"mine": int(mine), "sides": sides, "ghost": kept_ghost, "result": kept_result, "eligible": value.get("eligible") == true,
		"created_ms": int(value.get("created_ms", 0)), "updated_ms": int(value.get("updated_ms", 0))}

static func _side(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("members") is Array or value.members.size() != 2 or not value.get("you") is bool: return {}
	for member: Variant in value.members:
		if member != null and not _id(member): return {}
	if not Typed.whole_number(value.get("steps")) or not Typed.whole_number(value.get("ticks")) or not value.get("finished") is bool or not value.get("left") is bool or not value.get("check") in CHECKS: return {}
	var turn: Variant = value.get("turn")
	var side := {"members": value.members.duplicate(), "you": value.you, "steps": int(value.steps), "ticks": int(value.ticks),
		"turn": int(turn) if Typed.whole_number(turn) and int(turn) < 2 else -1, "finished": value.finished, "left": value.left, "check": value.check, "looks": _looks(value.get("looks"))}
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
	return pay

static func _bonus(value: Variant) -> Dictionary:
	if not value is Dictionary or not Typed.whole_number(value.get("amount")) or not value.get("counted") is bool: return {}
	return {"amount": int(value.amount), "counted": value.counted, "reason": str(value.get("reason", ""))}

static func _id(value: Variant) -> bool:
	return Typed.valid_id(value)

static func _entry(value: Variant) -> bool:
	return value is String and value.length() == 32 and value.is_valid_hex_number()

static func _board(value: Variant) -> bool:
	return value is String and value.contains("@") and value.length() <= 56

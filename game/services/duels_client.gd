extends RefCounted
## The duel requests (backend src/duels/routes.ts) through the app's one
## request queue (services/rooms_api.gd request_json), and what this phone
## keeps of them:
## - lobby(): GET /v1/duels, the party, its invites and every duel this player
##   is in. Kept in memory for the pages, and two small facts are saved
##   (atomic_file, user://duels.json, per player): which rooms are duel rooms,
##   for the Duel tag in Your rooms. A duel's clear needs nothing kept: its
##   room is an ordinary room, which the chapter chain already counts.
## - ghosts(): GET /v1/duels/ghosts, kept for GHOSTS_KEEP_MS.
## - duel(): one duel with what it paid this player.
## - the party, challenge and duel actions. Challenges and ghost races carry an
##   idempotency key made once per tap, so a retry answers the duel it made.
## Every answer is checked before it is used; one this build cannot read is a
## failure, never a partial page.
const Typed = preload("res://services/typed_values.gd")
const AtomicFile = preload("res://services/atomic_file.gd")
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
## {rooms: {room_id: kind}} for this player.
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
	var checked := valid_lobby(response.get("data"))
	if checked.is_empty(): return {"ok": false, "code": "invalid_duels"}
	_lobby = checked
	_remember(checked.duels)
	return {"ok": true, "lobby": checked}

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

## {ok, duel, pay, win_bonus} for one duel.
func duel(board: String, duel_id: String) -> Dictionary:
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_GET, "%s/%s/%s" % [PREFIX, board, duel_id])
	return _duel_answer(response, true)

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

static func new_key() -> String:
	return Crypto.new().generate_random_bytes(18).hex_encode()

## "friend", "ghost" or "" for a room this phone knows as a duel room.
func room_kind(room_id: String) -> String:
	return str(_saved.get("rooms", {}).get(room_id, ""))

func _party(action: String, body: Dictionary) -> Dictionary:
	var sent := body.duplicate()
	sent["schema_version"] = 1
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_POST, "%s/party/%s" % [PREFIX, action], sent)
	if not response.get("ok", false): return {"ok": false, "code": str(response.get("code", ""))}
	var checked := valid_lobby(response.get("data"))
	if checked.is_empty(): return {"ok": false, "code": "invalid_duels"}
	_lobby = checked
	_remember(checked.duels)
	return {"ok": true, "lobby": checked}

func _duel_answer(response: Dictionary, detail: bool = false) -> Dictionary:
	if not response.get("ok", false): return {"ok": false, "code": str(response.get("code", ""))}
	var data: Variant = response.get("data")
	var view := valid_view(data.get("duel") if data is Dictionary else null)
	if view.is_empty(): return {"ok": false, "code": "invalid_duels"}
	_remember([view])
	var answer := {"ok": true, "duel": view}
	if detail:
		answer["pay"] = _pay(data.get("pay"))
		answer["win_bonus"] = _bonus(data.get("win_bonus"))
	return answer

## Notes duel rooms, and saves only when they changed.
func _remember(views: Array) -> void:
	if _owner.is_empty(): return
	var rooms: Dictionary = _saved.get("rooms", {}).duplicate()
	for view: Dictionary in views:
		var own: Dictionary = view.sides[view.mine]
		if own.get("room_id") is String and not str(own.room_id).is_empty(): rooms[own.room_id] = view.kind
	if rooms == _saved.get("rooms", {}): return
	while rooms.size() > MAX_DUELS * 2: rooms.erase(rooms.keys()[0])
	_saved = {"rooms": rooms}
	var text := AtomicFile.read_text(_path)
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	var all: Dictionary = parsed if parsed is Dictionary else {}
	all[_owner] = _saved
	AtomicFile.write_text(_path, JSON.stringify(all))

func _read_saved() -> Dictionary:
	var text := AtomicFile.read_text(_path)
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	var mine: Variant = parsed.get(_owner) if parsed is Dictionary else null
	if not mine is Dictionary or not mine.get("rooms") is Dictionary: return {"rooms": {}}
	var rooms := {}
	for room_id: Variant in mine.rooms:
		if room_id is String and room_id.length() == 22 and mine.rooms[room_id] in ["friend", "ghost"]: rooms[room_id] = mine.rooms[room_id]
	return {"rooms": rooms}

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
	return {"party": {"partner": partner, "intact": party.intact, "invites_in": party.invites_in.duplicate(), "invite_out": out}, "duels": duels,
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
		kept_ghost = {"source": ghost.source, "ticks": int(ghost.ticks), "rank": int(ghost.rank) if Typed.whole_number(ghost.get("rank")) else 0, "names": ghost.get("names") if ghost.get("names") is Array else null}
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
	var side := {"members": value.members.duplicate(), "you": value.you, "steps": int(value.steps), "ticks": int(value.ticks), "assisted": value.get("assisted") == true,
		"turn": int(turn) if Typed.whole_number(turn) and int(turn) < 2 else -1, "finished": value.finished, "left": value.left, "check": value.check}
	if value.you:
		var room: Variant = value.get("room_id")
		var invite: Variant = value.get("invite_code")
		side["room_id"] = room if room is String and room.length() == 22 else ""
		side["invite_code"] = invite if invite is String else ""
		side["hosting"] = value.get("hosting") == true
	return side

static func _pay(value: Variant) -> Dictionary:
	if not value is Dictionary: return {}
	var pay := {}
	for field: String in ["turns", "plain", "blooms", "duel", "boost", "boost_percent", "total"]:
		if not Typed.whole_number(value.get(field)): return {}
		pay[field] = int(value[field])
	return pay

static func _bonus(value: Variant) -> Dictionary:
	if not value is Dictionary or not Typed.whole_number(value.get("amount")) or not value.get("counted") is bool: return {}
	return {"amount": int(value.amount), "counted": value.counted, "reason": str(value.get("reason", ""))}

static func _id(value: Variant) -> bool:
	return value is String and value.length() == 22

static func _entry(value: Variant) -> bool:
	return value is String and value.length() == 32 and value.is_valid_hex_number()

static func _board(value: Variant) -> bool:
	return value is String and value.contains("@") and value.length() <= 56

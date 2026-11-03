extends RefCounted
## Public duels' own requests (backend src/duels public routes), through the
## app's one request queue (services/rooms_api.gd request_json). A posted or
## joined duel comes back as an ordinary duel view, read and kept through the
## duels client (services/duels_client.gd duel_answer), so the lobby, Your
## rooms' Duel tag and the duel pages see it like any other.
## - list(): one page of open public duels, read when the list opens or is
##   pulled down, never on a timer. Rows carry no player ids: a stranger is a
##   seat with a label (their shown name, or null).
## - post() and join(): each with the idempotency key of the attempt, made once
##   and sent again on a retry (the caller keeps it), so a lost answer never
##   posts or seats twice. A spot someone took first answers `spot_taken` with
##   the row as it is now (or null once the duel is gone).
## - set_on(): the player's Public duels switch.
## - block(), report(), befriend(): a stranger is named by seat only; the
##   server finds the player, so no id ever reaches this phone.
## Every answer is checked before it is used; one this build cannot read is a
## failure, never a partial page.
const Typed = preload("res://services/typed_values.gd")
const PREFIX := "/v1/duels/public"
## Rows on one page, as the server sends them.
const PAGE_ROWS := 20
const SORTS := ["newest", "almost_full"]
const REASONS := ["sexual_content", "child_safety", "harassment", "hate", "privacy", "other"]

var _api: Node
## The duels client the duel views go through (services/duels_client.gd).
var duels: RefCounted

func _init(api: Node, duels_client: RefCounted) -> void:
	_api = api
	duels = duels_client

## {ok, rows, next} for one page: `scope` "all" or a board key, `sort` newest or
## almost_full, `page` from 0. `next`: the next page, or -1 at the end.
func list(scope: String, sort: String, page: int = 0) -> Dictionary:
	if not (scope == "all" or _board(scope)) or not sort in SORTS or page < 0: return {"ok": false, "code": "invalid_public_list"}
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_GET, "%s/list/%s/%s/%d" % [PREFIX, scope, sort, page])
	if not response.get("ok", false): return _failure(response)
	var checked := valid_list(response.get("data"))
	if checked.is_empty(): return {"ok": false, "code": "invalid_public_list"}
	checked["ok"] = true
	return checked

## Posts a public duel on `board`, alone or with the party.
func post(board: String, joining: String, key: String) -> Dictionary:
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_POST, PREFIX, {"schema_version": 1, "idempotency_key": key, "board": board, "as": joining})
	return _duel(response)

## Takes `seat` (or the server's pick with -1) in duel `duel_id`, alone or with the party.
func join(board: String, duel_id: String, joining: String, seat: int, key: String) -> Dictionary:
	var body := {"schema_version": 1, "idempotency_key": key, "as": joining, "seat": seat if seat >= 0 else null}
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_POST, "%s/%s/%s/join" % [PREFIX, board, duel_id], body)
	var answer := _duel(response)
	if not answer.ok and answer.code == "spot_taken": answer["row"] = _taken_row(response.get("data"))
	return answer

## Sets the player's Public duels switch: {ok, on, show_name, paused}.
func set_on(on: bool) -> Dictionary:
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_PUT, PREFIX + "/me", {"schema_version": 1, "on": on})
	if not response.get("ok", false): return _failure(response)
	var data: Variant = response.get("data")
	if not data is Dictionary or not data.get("on") is bool or not data.get("show_name") is bool or not data.get("paused") is bool: return {"ok": false, "code": "invalid_public_duels"}
	return {"ok": true, "on": data.on, "show_name": data.show_name, "paused": data.paused}

## Blocks the player in `seat`: {ok, left} (blocking your own partner leaves the duel).
func block(board: String, duel_id: String, seat: int) -> Dictionary:
	var response := await _seat_action(board, duel_id, "block", {"seat": seat})
	if not response.get("ok", false): return _failure(response)
	var data: Variant = response.get("data")
	if not data is Dictionary or not Typed.equal(data.get("blocked"), true) or not data.get("left") is bool: return {"ok": false, "code": "invalid_public_duels"}
	return {"ok": true, "left": data.left}

## Reports the player in `seat` for one of the six reasons, with the key of this report (kept across its retries).
func report(board: String, duel_id: String, seat: int, reason: String, key: String) -> Dictionary:
	if not reason in REASONS: return {"ok": false, "code": "invalid_safety_target"}
	var response := await _seat_action(board, duel_id, "report", {"seat": seat, "reason": reason, "idempotency_key": key})
	if not response.get("ok", false): return _failure(response)
	var data: Variant = response.get("data")
	if not data is Dictionary or not Typed.equal(data.get("received"), true): return {"ok": false, "code": "invalid_public_duels"}
	return {"ok": true}

## Sends the player in `seat` an ordinary friend request, once the duel is over.
func befriend(board: String, duel_id: String, seat: int) -> Dictionary:
	var response := await _seat_action(board, duel_id, "friend", {"seat": seat})
	if not response.get("ok", false): return _failure(response)
	var data: Variant = response.get("data")
	if not data is Dictionary or not Typed.equal(data.get("sent"), true): return {"ok": false, "code": "invalid_public_duels"}
	return {"ok": true}

func _seat_action(board: String, duel_id: String, action: String, fields: Dictionary) -> Dictionary:
	if not _board(board) or not _entry(duel_id) or not Typed.whole_number(fields.get("seat")) or int(fields.seat) < 0 or int(fields.seat) > 3: return {"ok": false, "code": "invalid_public_duels"}
	var body := fields.duplicate()
	body["schema_version"] = 1
	return await _api.request_json(HTTPClient.METHOD_POST, "%s/%s/%s/%s" % [PREFIX, board, duel_id, action], body)

func _duel(response: Dictionary) -> Dictionary:
	return duels.duel_answer(response)

static func _failure(response: Dictionary) -> Dictionary:
	return {"ok": false, "code": str(response.get("code", "")), "status": int(response.get("status", 0))}

## The row a `spot_taken` refusal carries, as checked, or {} (the duel is gone or closed).
static func _taken_row(data: Variant) -> Dictionary:
	if not data is Dictionary: return {}
	var error: Variant = data.get("error")
	var row: Variant = data.get("row") if data.has("row") else error.get("row") if error is Dictionary else null
	return valid_row(row)

## A list page as the server sent it: {page, next, rows}, or {}.
static func valid_list(value: Variant) -> Dictionary:
	if not value is Dictionary or not Typed.equal(value.get("schema_version"), 1) or not Typed.whole_number(value.get("page")) or not value.get("rows") is Array or value.rows.size() > PAGE_ROWS: return {}
	var next: Variant = value.get("next")
	if next != null and not Typed.whole_number(next): return {}
	var rows: Array = []
	for item: Variant in value.rows:
		var row := valid_row(item)
		if row.is_empty(): return {}
		rows.append(row)
	return {"page": int(value.page), "next": int(next) if next != null else -1, "rows": rows}

## One list row, or {}. Seats keep only what the row draws: open, a label and a look.
static func valid_row(value: Variant) -> Dictionary:
	if not value is Dictionary or not _entry(value.get("duel_id")) or not _board(value.get("board")) or not Typed.whole_number(value.get("posted_ms")) or not Typed.whole_number(value.get("open_until_ms")) or not Typed.whole_number(value.get("steps")): return {}
	if not value.get("sides") is Array or value.sides.size() != 2: return {}
	var sides: Array = []
	for side: Variant in value.sides:
		if not side is Dictionary or not Typed.whole_number(side.get("steps")) or not side.get("seats") is Array or side.seats.size() != 2: return {}
		var seats: Array = []
		for seat: Variant in side.seats:
			var kept := valid_seat(seat)
			if kept.is_empty(): return {}
			seats.append(kept)
		sides.append({"steps": int(side.steps), "seats": seats})
	return {"duel_id": value.duel_id, "board": value.board, "chapter": value.board, "posted_ms": int(value.posted_ms), "open_until_ms": int(value.open_until_ms),
		"steps": int(value.steps), "mine": value.get("mine") == true, "sides": sides}

## One seat: {open, label (String, "" for none), you, look}, or {}.
static func valid_seat(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("open") is bool: return {}
	var label: Variant = value.get("label")
	if label != null and (not label is String or label.length() > 40): return {}
	return {"open": value.open, "label": "" if label == null or value.open else str(label), "you": value.get("you") == true, "look": (value.look as Dictionary).duplicate() if value.get("look") is Dictionary and not value.open else {}}

static func _entry(value: Variant) -> bool:
	return value is String and value.length() == 32 and value.is_valid_hex_number()

static func _board(value: Variant) -> bool:
	return value is String and value.contains("@") and value.length() <= 56 and not value.contains("/")

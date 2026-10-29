extends RefCounted
## The leaderboard requests (backend src/leaderboards/routes.ts) through the
## app's one request queue (services/rooms_api.gd request_json):
## - board(): GET /v1/leaderboards/<board>, the board anyone sees. Kept here for
##   VIEW_KEEP_MS, so moving between chapters asks the server once each. Every
##   board read from the server goes to services/leaderboard_placings.gd,
##   which notes this player's runs it confirms in the top 10.
## - the name choice ("Show my name on leaderboards", off by default): kept on
##   the phone and sent with PUT /v1/leaderboards/me. A choice the server has
##   not taken yet stays pending and goes again on the next sync(). With
##   nothing pending, sync() reads the server's once per install (so a
##   reinstall shows it right) and otherwise asks nothing.
## - report(): POST .../entries/<entry>/report.
## - replay(): GET .../replay/<entry>, a top 10 run's replay for the viewer
##   (services/leaderboard_replay.gd), checked on a worker. Never kept: each
##   Watch asks once, and the server answers from its cache.
const Typed = preload("res://services/typed_values.gd")
const AtomicFile = preload("res://services/atomic_file.gd")
const LeaderboardReplay = preload("res://services/leaderboard_replay.gd")
const Reaper = preload("res://services/worker_reaper.gd")
const Placings = preload("res://services/leaderboard_placings.gd")
const PREFIX := "/v1/leaderboards/"
const ME := "/v1/leaderboards/me"
const VIEW_KEEP_MS := 60_000
const CHOICE_PATH := "user://leaderboard-name.json"
const MAX_ROWS := 10
const MAX_CHECKING := 64

var _api: Node
var _owner: String
var _choice_path := CHOICE_PATH
var _views: Dictionary = {}
## {show, pending, synced} for this player.
var _choice: Dictionary = {}

static var _shared: RefCounted

## One client per signed-in player, so Settings and the board screen share the choice and the kept boards.
static func shared(api: Node, owner: String) -> RefCounted:
	if _shared == null or _shared._api != api or _shared._owner != owner: _shared = load("res://services/leaderboard_client.gd").new(api, owner)
	return _shared

func _init(api: Node, owner: String, choice_path: String = CHOICE_PATH) -> void:
	_api = api
	_owner = owner
	_choice_path = choice_path
	_choice = _read_choice()

## {ok, view} or {ok: false, code}. A view is checked before it is used.
func board(key: String, fresh: bool = false) -> Dictionary:
	var kept: Dictionary = _views.get(key, {})
	if not fresh and not kept.is_empty() and Time.get_ticks_msec() - int(kept.at) < VIEW_KEEP_MS: return {"ok": true, "view": kept.view}
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_GET, PREFIX + key)
	if not response.get("ok", false): return {"ok": false, "code": str(response.get("code", ""))}
	var view := valid_view(response.get("data"), key)
	if view.is_empty(): return {"ok": false, "code": "invalid_board"}
	_views[key] = {"at": Time.get_ticks_msec(), "view": view}
	Placings.shared().learn(_owner, key, view)
	return {"ok": true, "view": view}

## The board this client last read from the server, however old, or {} (no request).
func kept_view(key: String) -> Dictionary:
	return (_views.get(key, {}) as Dictionary).get("view", {})

## Whether this player chose to show their name (the phone's copy).
func show_name() -> bool:
	return bool(_choice.get("show", false))

## Saves the choice on the phone at once and sends it; true when kept.
func set_show_name(show: bool) -> bool:
	_choice = {"show": show, "pending": true, "synced": bool(_choice.get("synced", false))}
	var kept := _write_choice()
	sync()
	return kept

## Sends a pending choice, or reads the server's when this install never has.
func sync() -> void:
	if _owner.is_empty(): return
	var sending: Dictionary = _choice.duplicate()
	var response: Dictionary
	if sending.get("pending", false): response = await _api.request_json(HTTPClient.METHOD_PUT, ME, {"schema_version": 1, "show_name": bool(sending.show)})
	elif not sending.get("synced", false): response = await _api.request_json(HTTPClient.METHOD_GET, ME)
	else: return
	var data: Variant = response.get("data")
	if not response.get("ok", false) or not data is Dictionary or not data.get("show_name") is bool: return
	# A newer choice made while this one was out stays pending.
	if _choice.get("pending", false) and _choice.show != sending.get("show"): return
	_choice = {"show": data.show_name, "pending": false, "synced": true}
	_write_choice()

## {ok} for a report of a ranked run.
func report(key: String, entry_id: String) -> Dictionary:
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_POST, "%s%s/entries/%s/report" % [PREFIX, key, entry_id], {"schema_version": 1})
	return {"ok": bool(response.get("ok", false)), "code": str(response.get("code", ""))}

## {ok, parts} for the run `row` (a row of board `key`, with a replay_hash) of
## chapter `chapter_key`: the viewer's parts, decoded and hash-checked, or {ok: false, code}.
func replay(key: String, chapter_key: String, row: Dictionary) -> Dictionary:
	if not _hash(row.get("replay_hash")) or not _entry(row.get("entry_id")): return {"ok": false, "code": "no_replay"}
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_GET, "%s%s/replay/%s" % [PREFIX, key, row.entry_id])
	if not response.get("ok", false): return {"ok": false, "code": str(response.get("code", ""))}
	var work := Callable(LeaderboardReplay, "parts").bind(response.get("data"), key, str(row.entry_id), str(row.replay_hash), chapter_key)
	var parts: Variant = await Reaper.run(work, true)
	if not parts is Array or parts.is_empty(): return {"ok": false, "code": "invalid_replay"}
	return {"ok": true, "parts": parts}

## The board as the server sent it, or {} when it is not one this build reads.
static func valid_view(value: Variant, key: String) -> Dictionary:
	if not value is Dictionary or not Typed.equal(value.get("schema_version"), 1) or not Typed.equal(value.get("board"), key) or not value.get("top") is Array or not value.get("checking") is Array: return {}
	if value.top.size() > MAX_ROWS or value.checking.size() > MAX_CHECKING: return {}
	var top: Array = []
	for row: Variant in value.top:
		if not row is Dictionary or not Typed.whole_number(row.get("rank")) or not Typed.whole_number(row.get("ticks")) or not _entry(row.get("entry_id")) or not row.get("gold_leaf") is bool: return {}
		var names: Variant = row.get("names")
		if names != null and (not names is Array or names.size() != 2 or not names[0] is String or not names[1] is String): return {}
		# A server before replays sends no replay_hash: the row has no Watch.
		var replay_hash: Variant = row.get("replay_hash")
		if replay_hash != null and not _hash(replay_hash): return {}
		top.append({"rank": int(row.rank), "entry_id": row.entry_id, "ticks": int(row.ticks), "names": names, "gold_leaf": row.gold_leaf, "finished_on": str(row.get("finished_on", "")), "replay_hash": replay_hash})
	var checking: Array = []
	for id: Variant in value.checking:
		if not _entry(id): return {}
		checking.append(id)
	return {"board": key, "top": top, "checking": checking}

static func _entry(value: Variant) -> bool:
	return value is String and value.length() == 32 and value.is_valid_hex_number()

static func _hash(value: Variant) -> bool:
	return value is String and value.length() == 64 and value.is_valid_hex_number() and value == value.to_lower()

func _read_choice() -> Dictionary:
	var text := AtomicFile.read_text(_choice_path)
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if parsed is Dictionary and parsed.get(_owner) is Dictionary and parsed[_owner].get("show") is bool and parsed[_owner].get("pending") is bool:
		return {"show": parsed[_owner].show, "pending": parsed[_owner].pending, "synced": parsed[_owner].get("synced", false) == true}
	return {"show": false, "pending": false, "synced": false}

func _write_choice() -> bool:
	if _owner.is_empty(): return false
	var text := AtomicFile.read_text(_choice_path)
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	var all: Dictionary = parsed if parsed is Dictionary else {}
	all[_owner] = _choice.duplicate()
	return AtomicFile.write_text(_choice_path, JSON.stringify(all))

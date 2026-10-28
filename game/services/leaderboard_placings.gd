extends RefCounted
## This player's runs that a board confirmed in its top 10, for the
## celebration (presentation/leaderboard_celebration.gd), and which of them
## this phone has celebrated.
##
## - learn() reads every board the app reads (services/leaderboard_client.gd
##   board(), a refresh included). A placing is a row of the board's top 10
##   whose entry is one of this phone's own runs (services/leaderboard_runs.gd)
##   and that is not waiting for its check: only ranked rows are in `top`, and
##   a run still in `checking` is never news. A placing waiting to be shown
##   follows the newest read of its board (its rank may move) and goes when
##   that board no longer lists it (pushed out, or struck).
## - next() is the oldest placing waiting; mark_shown() records it by its
##   entry id when its celebration opens, so each placing shows once, after a
##   restart too. Runs never change their entry id, so a run that later moves
##   up is not celebrated again.
##
## Kept per player in one small file written whole with AtomicFile. Every
## value read back is checked; a file that cannot be read reads as empty.
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const Runs = preload("res://services/leaderboard_runs.gd")

const PATH := "user://leaderboard-placings.json"
const VERSION := 1
const TOP_PLACES := 10
const MAX_PENDING := 16
const MAX_SHOWN := 256
## The celebration tiers by place (presentation/leaderboard_celebration.gd TIERS).
const FIRST := "first"
const SECOND := "second"
const THIRD := "third"
const TOP_TEN := "top_ten"

static var _shared: RefCounted = null

var path := PATH
## owner -> {"shown": {entry_id: true} oldest first, "pending": [placing]}.
var _players: Dictionary = {}

static func shared() -> RefCounted:
	if _shared == null: _shared = load("res://services/leaderboard_placings.gd").new()
	return _shared

## Installs a store as the shared one (tests), or clears it with null.
static func use_shared(store: RefCounted) -> void:
	_shared = store

func _init(storage_path: String = PATH) -> void:
	path = storage_path
	_load()

## The celebration tier for a place: first, second, third, top_ten, or "".
static func tier(rank: int) -> String:
	match rank:
		1: return FIRST
		2: return SECOND
		3: return THIRD
	return TOP_TEN if rank >= 4 and rank <= TOP_PLACES else ""

## Reads a checked board view (leaderboard_client.gd valid_view) of `board`;
## true when something waiting changed.
func learn(owner: String, board: String, view: Dictionary) -> bool:
	if owner.is_empty() or board.is_empty() or not view.get("top") is Array: return false
	var mine: Dictionary = {}
	for run: Dictionary in Runs.on_board(owner, board):
		if not run.assisted: mine[run.entry_id] = run
	var checking: Array = view.get("checking", [])
	var player: Dictionary = _players.get(owner, {"shown": {}, "pending": []})
	var pending: Array = player.pending
	var listed: Dictionary = {}
	var changed := false
	for row: Dictionary in view.top:
		listed[row.entry_id] = true
		if not mine.has(row.entry_id) or row.entry_id in checking or player.shown.has(row.entry_id) or tier(int(row.rank)).is_empty(): continue
		var placing := {"entry_id": row.entry_id, "board": board, "rank": int(row.rank), "ticks": int(row.ticks), "names": row.get("names"), "gold_leaf": bool(row.get("gold_leaf", false)), "partner": str(mine[row.entry_id].get("partner", ""))}
		var at := _find(pending, row.entry_id)
		if at < 0: pending.append(placing)
		elif pending[at] == placing: continue
		else: pending[at] = placing
		changed = true
	var kept: Array = pending.filter(func(item: Dictionary) -> bool: return item.board != board or listed.has(item.entry_id))
	changed = changed or kept.size() != pending.size()
	if not changed: return false
	player.pending = kept.slice(maxi(kept.size() - MAX_PENDING, 0))
	_players[owner] = player
	_save()
	return true

## Whether a placing waits for its celebration (cheap enough for every frame).
func has_pending(owner: String) -> bool:
	return not ((_players.get(owner, {}) as Dictionary).get("pending", []) as Array).is_empty()

## The oldest placing waiting for its celebration ({} when none):
## {entry_id, board, rank, ticks, names (two names or null), gold_leaf, partner}.
func next(owner: String) -> Dictionary:
	var pending: Array = (_players.get(owner, {}) as Dictionary).get("pending", [])
	return (pending[0] as Dictionary).duplicate(true) if not pending.is_empty() else {}

## Whether this placing's celebration was shown on this phone.
func was_shown(owner: String, entry_id: String) -> bool:
	return (_players.get(owner, {}) as Dictionary).get("shown", {}).has(entry_id)

## The placing's celebration opened: it never shows again.
func mark_shown(owner: String, entry_id: String) -> void:
	if owner.is_empty() or not _entry(entry_id) or was_shown(owner, entry_id): return
	var player: Dictionary = _players.get(owner, {"shown": {}, "pending": []})
	player.pending = (player.pending as Array).filter(func(item: Dictionary) -> bool: return item.entry_id != entry_id)
	player.shown[entry_id] = true
	while player.shown.size() > MAX_SHOWN: player.shown.erase(player.shown.keys()[0])
	_players[owner] = player
	_save()

static func _find(pending: Array, entry_id: String) -> int:
	for index in range(pending.size()):
		if pending[index].entry_id == entry_id: return index
	return -1

static func _entry(value: Variant) -> bool:
	return value is String and value.length() == 32 and value.is_valid_hex_number()

static func _placing(value: Variant) -> bool:
	if not value is Dictionary or not _entry(value.get("entry_id")) or not value.get("board") is String or str(value.board).is_empty(): return false
	if not Typed.whole_number(value.get("rank")) or tier(int(value.rank)).is_empty() or not Typed.whole_number(value.get("ticks")) or int(value.ticks) < 0: return false
	var names: Variant = value.get("names")
	if names != null and (not names is Array or names.size() != 2 or not names[0] is String or not names[1] is String): return false
	return value.get("gold_leaf") is bool and value.get("partner") is String

func _load() -> void:
	_players = {}
	var text := AtomicFile.read_text(path)
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not parsed is Dictionary or not Typed.equal(parsed.get("version"), VERSION) or not parsed.get("players") is Dictionary: return
	for owner: Variant in parsed.players:
		var value: Variant = parsed.players[owner]
		if not owner is String or not value is Dictionary or not value.get("shown") is Array or not value.get("pending") is Array: continue
		var shown: Dictionary = {}
		for id: Variant in value.shown:
			if _entry(id): shown[id] = true
		var pending: Array = []
		for item: Variant in value.pending:
			if _placing(item) and not shown.has(item.entry_id) and _find(pending, item.entry_id) < 0:
				pending.append({"entry_id": item.entry_id, "board": item.board, "rank": int(item.rank), "ticks": int(item.ticks), "names": item.names, "gold_leaf": item.gold_leaf, "partner": item.partner})
		_players[owner] = {"shown": shown, "pending": pending.slice(maxi(pending.size() - MAX_PENDING, 0))}

func _save() -> bool:
	var players: Dictionary = {}
	for owner: String in _players:
		players[owner] = {"shown": (_players[owner].shown as Dictionary).keys(), "pending": _players[owner].pending}
	return AtomicFile.write_text(path, JSON.stringify({"version": VERSION, "players": players}))

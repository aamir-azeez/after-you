extends RefCounted
## What platform board posting keeps on this phone, in its own small file beside
## platform-games-v1.json (which holds links and must stay small):
## - judged: each run's verdict (platform_boards.gd GO, WAIT, NEVER) by its board entry id, the
##   newest MAX_JUDGED kept. Entry ids are hashes of a room; no player id is kept here.
## - posted: the best time (hundredths) posted on each board, per platform account
##   ("<kind>:<player_key>", the one-way key the provider gives), so a time goes up once per new
##   best and a new account, or a new phone, posts its bests again.
## Losing the file costs at most one repeated post per board (the platforms keep each player's
## best anyway) and verdicts worked out again on the next board reads. Written whole with
## services/atomic_file.gd, only when something changed.
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const Policy = preload("res://services/platform_games/platform_boards.gd")

const PATH := "user://platform-boards-v1.json"
const MAX_JUDGED := 512
const MAX_ACCOUNTS := 8
const MAX_BOARDS := 64
const ENTRY := "^[a-f0-9]{32}$"
const ACCOUNT := "^(play_games|game_center):[a-f0-9]{64}$"

var path := PATH
var judged: Dictionary = {}
var posted: Dictionary = {}

func _init(file_path: String = PATH) -> void:
	path = file_path
	_load()

## The account key for `kind` and the provider's one-way `player_key`.
static func account(kind: String, player_key: String) -> String:
	return "%s:%s" % [kind, player_key]

## board -> hundredths this account posted.
func posted_for(account_key: String) -> Dictionary:
	return (posted.get(account_key, {}) as Dictionary).duplicate()

## Keeps the verdicts of one pass. Verdicts of runs not in it stay (another player of this phone,
## or a run the pass did not see); the oldest go past MAX_JUDGED. True when written or unchanged.
func keep_verdicts(verdicts: Dictionary) -> bool:
	var changed := false
	for id: String in verdicts:
		if judged.get(id) == verdicts[id]: continue
		judged.erase(id)
		judged[id] = verdicts[id]
		changed = true
	if not changed: return true
	while judged.size() > MAX_JUDGED: judged.erase(judged.keys()[0])
	return _save()

func remember_posted(account_key: String, board: String, hundredths: int) -> bool:
	var mine: Dictionary = posted.get(account_key, {})
	if mine.get(board) == hundredths: return true
	mine[board] = hundredths
	posted.erase(account_key)
	posted[account_key] = mine
	while posted.size() > MAX_ACCOUNTS: posted.erase(posted.keys()[0])
	return _save()

func _save() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"schema_version": 1, "judged": judged, "posted": posted}))

## Reads what passes the shapes above; anything else is left out, never trusted.
func _load() -> void:
	judged = {}
	posted = {}
	var parsed: Variant = AtomicFile.read_json(path, func(value: Variant) -> bool:
		return value is Dictionary and Typed.equal(value.get("schema_version"), 1) and value.get("judged") is Dictionary and value.get("posted") is Dictionary)
	if not parsed is Dictionary: return
	var entry := RegEx.create_from_string(ENTRY)
	for id: Variant in parsed.judged:
		if id is String and entry.search(id) != null and parsed.judged[id] in Policy.VERDICTS: judged[id] = parsed.judged[id]
	while judged.size() > MAX_JUDGED: judged.erase(judged.keys()[0])
	var account_shape := RegEx.create_from_string(ACCOUNT)
	for key: Variant in parsed.posted:
		var boards: Variant = parsed.posted[key]
		if not key is String or account_shape.search(key) == null or not boards is Dictionary or boards.size() > MAX_BOARDS: continue
		var kept: Dictionary = {}
		for board: Variant in boards:
			if board is String and board.length() <= 64 and Typed.whole_number(boards[board]) and int(boards[board]) > 0: kept[board] = int(boards[board])
		posted[key] = kept
	while posted.size() > MAX_ACCOUNTS: posted.erase(posted.keys()[0])

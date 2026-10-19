extends RefCounted
## Display names: the rules a name follows on this phone, the anonymous name
## made from a player id, this player's own choice, and the names friends and
## room partners chose (from the friends list and room replies).
##
## The server is the authority on names. This phone pre-checks length and
## characters so the field can say what is wrong at once, keeps what the server
## last confirmed, and treats every name it receives as untrusted text: a name
## that breaks the rules is ignored, and screens show names only in plain
## Labels, cut with short().
##
## Everything is kept per server and player (a scope), in one small file. One
## shared instance (shared()) backs every screen; tests make their own with a
## path of their choosing and may install it with use_shared().
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")

const PATH := "user://display_names.json"
const WORDS_PATH := "res://content/anonymous_names.json"
const VERSION := 1
## The request header that asks the server for names (friends list, rooms,
## capabilities).
const HEADER := "X-AfterYou-Display-Names: 1"
const MAX_LENGTH := 18
## Other players' names kept per scope; the oldest room names go first.
const MAX_NAMES := 200
## typed: a name the player typed; anonymous: no name, friends see the
## generated one; platform: the Play Games or Game Center name, copied once.
const CHOICES := ["typed", "anonymous", "platform"]
## Punctuation a name may hold besides letters, digits, marks and spaces.
const PUNCTUATION := ".'-_!?’"
## Where an own choice stands: "" (never chosen), pending (not yet confirmed by
## the server), synced, or refused (the server said no; code says why).
const PENDING := "pending"
const SYNCED := "synced"
const REFUSED := "refused"

static var _shared: RefCounted = null
static var _words: PackedStringArray = PackedStringArray()

var path := PATH
var _scopes: Dictionary = {}

static func shared() -> RefCounted:
	if _shared == null: _shared = load("res://services/display_names.gd").new()
	return _shared

## Installs a store as the shared one (tests), or clears it with null.
static func use_shared(store: RefCounted) -> void:
	_shared = store

func _init(storage_path: String = PATH) -> void:
	path = storage_path
	_load()

# --- Rules ---------------------------------------------------------------

## Spaces trimmed and runs of whitespace made one space. The server also
## normalises the text (NFC); what it sends back is what is kept.
static func clean(text: String) -> String:
	var joined := text
	for space: String in [char(9), char(10), char(13), char(0xa0), char(0x3000)]: joined = joined.replace(space, " ")
	joined = joined.strip_edges()
	while joined.contains("  "): joined = joined.replace("  ", " ")
	return joined

## What is wrong with a name this phone can tell: "" when nothing, "length"
## (empty or over MAX_LENGTH) or "characters". Letters of every script pass;
## the server refuses the rest (symbols, emoji, the block list).
static func problem(text: String) -> String:
	var name := clean(text)
	if name.is_empty() or name.length() > MAX_LENGTH: return "length"
	for i in range(name.length()):
		if hidden_character(name.unicode_at(i)) or symbol_character(name.unicode_at(i)): return "characters"
	return ""

## Control, format, separator and private-use code points: never shown.
static func hidden_character(code: int) -> bool:
	if code < 32 or (code >= 127 and code < 160): return true
	if code == 0x00ad or code == 0x061c or code == 0x180e or code == 0xfeff: return true
	if (code >= 0x200b and code <= 0x200f) or (code >= 0x2028 and code <= 0x202e) or (code >= 0x2060 and code <= 0x206f): return true
	if (code >= 0xfe00 and code <= 0xfe0f) or (code >= 0xfff0 and code <= 0xfffb): return true
	if (code >= 0xe000 and code <= 0xf8ff) or code >= 0xf0000 or (code >= 0xe0000 and code <= 0xe0fff): return true
	return code >= 0xd800 and code <= 0xdfff

## ASCII symbols outside PUNCTUATION and the common emoji and symbol blocks.
static func symbol_character(code: int) -> bool:
	if code < 128:
		var character := char(code)
		return not (character == " " or (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or PUNCTUATION.contains(character))
	if code == 0x2019: return false
	if (code >= 0x2190 and code <= 0x2bff) or (code >= 0x1f000 and code <= 0x1faff) or (code >= 0x2000 and code <= 0x206f): return true
	return code in [0xa9, 0xae, 0xd7, 0xf7, 0xb0, 0xa7, 0xb6, 0xa6, 0xac, 0xb1]

## A name another player sent: a string the rules allow, unchanged by clean().
static func valid_remote(value: Variant) -> bool:
	return value is String and value == clean(value) and problem(value).is_empty()

## A name cut to fit a line: at most `limit` characters, ending in "…".
static func short(name: String, limit: int = MAX_LENGTH) -> String:
	if name.length() <= limit: return name
	return name.left(maxi(1, limit - 1)).strip_edges() + "…"

## The anonymous name for a player id, made from the game's own words and a
## number ("Kite 41"). Every phone makes the same one from the public id, so
## nothing is stored or sent. "" for a value that is not a player id.
static func anonymous_name(player_id: String) -> String:
	if not RegEx.create_from_string("^[A-Za-z0-9_-]{22}$").search(player_id): return ""
	var words := _anonymous_words()
	if words.is_empty(): return ""
	var digest := player_id.sha256_buffer()
	var word := words[((digest[0] << 8) | digest[1]) % words.size()]
	return "%s %d" % [word, 10 + ((digest[2] << 8) | digest[3]) % 90]

static func _anonymous_words() -> PackedStringArray:
	if _words.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(WORDS_PATH))
		if parsed is Dictionary and parsed.get("words") is Array:
			for word: Variant in parsed.words:
				if word is String and not word.is_empty() and word.length() <= 12: _words.append(word)
	return _words

# --- Scopes ----------------------------------------------------------------

static func scope_key(server: String, owner: String) -> String:
	return server.strip_edges().trim_suffix("/") + "|" + owner

func _scope(server: String, owner: String, create: bool = false) -> Dictionary:
	if owner.is_empty() or server.strip_edges().is_empty(): return {}
	var key := scope_key(server, owner)
	if not _scopes.has(key):
		if not create: return {}
		_scopes[key] = {"enabled": false, "own": _blank_own(), "names": {}}
	return _scopes[key]

static func _blank_own() -> Dictionary:
	return {"choice": "", "name": "", "revision": 0, "state": "", "code": "", "asked": false}

## Whether the server shows names to this player (the friends list or the
## capabilities said so last time). Prompts and anonymous names wait for it.
func enabled(server: String, owner: String) -> bool:
	return bool(_scope(server, owner).get("enabled", false))

func set_enabled(server: String, owner: String, on: bool) -> void:
	var scope := _scope(server, owner, on)
	if scope.is_empty() or bool(scope.enabled) == on: return
	scope.enabled = on
	# Names the server stops showing are not kept.
	if not on: scope.names = {}
	_save()

# --- This player's own name ---------------------------------------------

func own(server: String, owner: String) -> Dictionary:
	var scope := _scope(server, owner)
	return (scope.own as Dictionary).duplicate() if not scope.is_empty() else _blank_own()

## The name friends see for this player now: the confirmed or pending name, or
## the anonymous one.
func own_shown(server: String, owner: String) -> String:
	var mine := own(server, owner)
	if mine.choice in ["typed", "platform"] and not str(mine.name).is_empty() and mine.state != REFUSED: return str(mine.name)
	return anonymous_name(owner)

## Records a new choice, waiting to be sent. Returns the record, or {} for a
## choice or name the rules refuse.
func choose(server: String, owner: String, choice: String, name: String = "") -> Dictionary:
	if choice not in CHOICES: return {}
	var cleaned := "" if choice == "anonymous" else clean(name)
	if choice != "anonymous" and not problem(cleaned).is_empty(): return {}
	var scope := _scope(server, owner, true)
	if scope.is_empty(): return {}
	var mine: Dictionary = scope.own
	# Revisions are milliseconds since 1970, always rising on this phone, so a
	# reinstalled phone still sends a newer one than the server holds.
	mine.revision = maxi(int(mine.revision) + 1, int(Time.get_unix_time_from_system() * 1000.0))
	mine.choice = choice
	mine.name = cleaned
	mine.state = PENDING
	mine.code = ""
	mine.asked = true
	_save()
	return mine.duplicate()

## The server's answer to the send of `revision`. A newer choice made while it
## was out is kept as it is. ok answers carry the server's name (or null).
func settle(server: String, owner: String, revision: int, answer: Dictionary) -> void:
	var scope := _scope(server, owner)
	if scope.is_empty() or int(scope.own.revision) != revision: return
	var mine: Dictionary = scope.own
	if answer.get("ok", false):
		var name: Variant = answer.get("display_name")
		if name is String and valid_remote(name): mine.name = name
		elif name == null and mine.choice != "anonymous":
			# The server holds no name although one was sent: an operator cleared
			# it, or a newer anonymous choice won. This phone follows the server.
			mine.choice = "anonymous"
			mine.name = ""
		mine.state = SYNCED
		mine.code = ""
	else:
		mine.state = REFUSED
		mine.code = str(answer.get("code", ""))
	_save()

## The own name the friends list reported. A phone with nothing waiting to send
## follows it, so a new phone shows the name it had and a cleared name clears.
func adopt(server: String, owner: String, name: Variant) -> void:
	var scope := _scope(server, owner, true)
	if scope.is_empty(): return
	var mine: Dictionary = scope.own
	if mine.state == PENDING: return
	var named: bool = mine.choice in ["typed", "platform"]
	if name is String and valid_remote(name):
		if mine.state == SYNCED and named and mine.name == name: return
		if not named: mine.choice = "typed"
		mine.name = name
	elif name == null:
		# A phone that never chose stays unasked; an anonymous one is already right.
		if mine.choice == "" or (mine.state == SYNCED and mine.choice == "anonymous"): return
		mine.choice = "anonymous"
		mine.name = ""
	else:
		return
	mine.state = SYNCED
	mine.code = ""
	mine.asked = true
	_save()

## The first-run prompt was shown (once per player).
func mark_asked(server: String, owner: String) -> void:
	var scope := _scope(server, owner, true)
	if scope.is_empty() or bool(scope.own.asked): return
	scope.own.asked = true
	_save()

# --- Other players' names -----------------------------------------------

## The name a friend or room partner chose, or "".
func chosen(server: String, owner: String, player: String) -> String:
	var entry: Variant = _scope(server, owner).get("names", {}).get(player)
	return str(entry.name) if entry is Dictionary else ""

## The name to show for another player when this phone has no nickname for
## them: their chosen name, or their anonymous name while names are on, else "".
func shown(server: String, owner: String, player: String) -> String:
	var name := chosen(server, owner, player)
	if not name.is_empty(): return name
	return anonymous_name(player) if enabled(server, owner) else ""

## A friends list page: names on when it carries the own name key, and its
## friends' names replace the ones an earlier page gave.
func take_friends_page(server: String, owner: String, page: Dictionary) -> void:
	var on := page.has("display_name")
	set_enabled(server, owner, on)
	if not on: return
	var scope := _scope(server, owner, true)
	var names: Dictionary = scope.names
	for player: String in names.keys():
		if names[player].get("from") == "friend": names.erase(player)
	for row: Variant in page.get("friends", []):
		if not row is Dictionary or not row.get("player_id") is String: continue
		var name: Variant = row.get("display_name")
		if name is String and valid_remote(name): names[row.player_id] = {"name": name, "from": "friend", "at": _now()}
	adopt(server, owner, page.get("display_name"))
	_save()

## A room partner's name from a room reply or the room list. null (anonymous)
## forgets what was kept.
func note_partner(server: String, owner: String, player: String, name: Variant) -> void:
	if player.is_empty() or player == owner: return
	var scope := _scope(server, owner, true)
	if scope.is_empty(): return
	scope.enabled = true
	var names: Dictionary = scope.names
	var before: Variant = names.get(player)
	if name is String and valid_remote(name):
		if before is Dictionary and before.name == name: return
		names[player] = {"name": name, "from": before.get("from", "room") if before is Dictionary else "room", "at": _now()}
		_trim(names)
	elif name == null:
		if before == null: return
		names.erase(player)
	else:
		return
	_save()

static func _trim(names: Dictionary) -> void:
	if names.size() <= MAX_NAMES: return
	var rooms := names.keys().filter(func(player: String) -> bool: return names[player].get("from") == "room")
	rooms.sort_custom(func(a: String, b: String) -> bool: return int(names[a].at) < int(names[b].at))
	for player: String in rooms.slice(0, names.size() - MAX_NAMES): names.erase(player)

## Forgets everything kept for a player (account deletion, a new identity).
func clear_owner(owner: String) -> void:
	var changed := false
	for key: String in _scopes.keys():
		if key.get_slice("|", 1) == owner:
			_scopes.erase(key)
			changed = true
	if changed: _save()

static func _now() -> int:
	return int(Time.get_unix_time_from_system())

# --- File ---------------------------------------------------------------

func _load() -> void:
	_scopes = {}
	var parsed: Variant = JSON.parse_string(AtomicFile.read_text(path, func(text: String) -> bool: return JSON.parse_string(text) is Dictionary))
	if not parsed is Dictionary or not Typed.equal(parsed.get("schema_version"), VERSION) or not parsed.get("scopes") is Dictionary: return
	for key: Variant in parsed.scopes:
		var value: Variant = parsed.scopes[key]
		if not key is String or not key.contains("|") or not value is Dictionary: continue
		var scope := {"enabled": value.get("enabled") == true, "own": _blank_own(), "names": {}}
		var mine: Variant = value.get("own")
		if mine is Dictionary and mine.get("choice", "") in CHOICES + [""] and mine.get("state", "") in ["", PENDING, SYNCED, REFUSED]:
			var name: Variant = mine.get("name", "")
			if name is String and (name.is_empty() or valid_remote(name)):
				scope.own = {"choice": mine.choice, "name": name, "revision": Typed.as_int(mine.get("revision"), 0), "state": mine.state,
					"code": str(mine.get("code", "")).left(40), "asked": mine.get("asked") == true}
		var names: Variant = value.get("names")
		if names is Dictionary:
			for player: Variant in names:
				var entry: Variant = names[player]
				if player is String and entry is Dictionary and valid_remote(entry.get("name")) and entry.get("from") in ["friend", "room"]:
					scope.names[player] = {"name": entry.name, "from": entry.from, "at": Typed.as_int(entry.get("at"), 0)}
		_scopes[key] = scope

func _save() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"schema_version": VERSION, "scopes": _scopes}))

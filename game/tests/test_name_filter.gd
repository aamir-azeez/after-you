extends SceneTree
## The word filter for display names and nicknames (services/name_filter.gd):
## - the shared list loads, and its entries are lowercase a to z or digits;
## - every entry is refused plain and disguised (case, spacing, dots, doubled
##   letters, accents, digit swaps, lookalike letters, wide and bold letters);
## - the shared vectors (also run by backend/test/name-filter.test.ts): names
##   refused, names passed, and the plain fold each side must produce;
## - every anonymous name passes;
## - display names: the phone's check says "display_name_refused", names from
##   others are ignored, and a kept own name the list came to refuse stays;
## - nicknames: a refused one is not saved, and one saved before is kept in the
##   file but not shown;
## - odd input: empty, past the limit, marks and hidden characters alone, and
##   hidden characters inside a word.
const NameFilter = preload("res://services/name_filter.gd")
const DisplayNames = preload("res://services/display_names.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

const VECTORS := "res://tests/fixtures/display_names/name_filter_vectors.json"
# Synthetic ids only.
const SERVER := "https://names.example.test"
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const MAYA := "bbbbbbbbbbbbbbbbbbbbbb"

var checks := 0
var failures := 0
var _paths: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_list()
	_entries()
	_vectors()
	_anonymous()
	_display_names()
	_nicknames()
	_odd_input()
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU NAME FILTER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _list() -> void:
	var substrings := NameFilter.entries("substrings")
	var words := NameFilter.entries("words")
	_check(substrings.size() > 50 and words.size() > 150, "The shared list loads: %d substrings, %d words" % [substrings.size(), words.size()])
	var pattern := RegEx.create_from_string("^[a-z0-9]+$")
	var seen := {}
	for entry: String in substrings + words:
		_check(pattern.search(entry) != null, "An entry is lowercase a to z or digits: " + entry)
		_check(not seen.has(entry), "An entry is listed once: " + entry)
		seen[entry] = true
	_check(NameFilter.run_pattern("nigger") == "n+i+g{2,}e+r+" and NameFilter.run_pattern("kkk") == "k{3,}" and NameFilter.run_pattern("1488") == "1+4+8{2,}", "A run of a letter matches that many or more")

func _entries() -> void:
	var missed := PackedStringArray()
	for entry: String in NameFilter.entries("substrings") + NameFilter.entries("words"):
		for name: String in _disguises(entry):
			if not NameFilter.blocked(name): missed.append(name.c_escape())
	_check(missed.is_empty(), "Every entry is refused plain and disguised; missed: " + ", ".join(missed))

## Ways a player might write an entry. The server's suite makes the same ones.
func _disguises(entry: String) -> PackedStringArray:
	var look := {}
	var lookalikes: Dictionary = _json("res://content/display_name_blocklist.json").folding.lookalikes
	for from: String in lookalikes:
		var to := str(lookalikes[from])
		if to.length() == 1 and not look.has(to): look[to] = from
	var spaced := PackedStringArray()
	var doubled := ""
	var accented := ""
	var wide := ""
	var bold := ""
	for c: String in entry:
		spaced.append(c)
		doubled += c + c
		accented += c + (char(0x301) if "aeiouy".contains(c) else "")
		var code := c.unicode_at(0)
		if code >= 97 and code <= 122:
			wide += char(0xff41 + code - 97)
			bold += char(0x1d400 + code - 97)
		else:
			wide += char(0xff10 + code - 48)
			bold += char(0x1d7ce + code - 48)
	return PackedStringArray([
		entry,
		entry.to_upper(),
		entry.left(1).to_upper() + entry.substr(1),
		" ".join(spaced),
		".".join(spaced),
		"-".join(spaced),
		doubled,
		accented,
		# Swaps are read only in a run that holds a letter, so the first letter stays.
		entry.left(1) + _mapped(entry.substr(1), {"o": "0", "i": "1", "e": "3", "a": "4", "s": "5", "t": "7", "b": "8", "g": "9"}),
		# The alternate swaps are never read at the end of a run, so the last letter stays.
		_mapped(entry.left(-1), {"o": "0", "l": "1", "e": "3", "a": "4", "s": "$"}) + entry.right(1),
		_mapped(entry, look),
		wide,
		bold,
		"Big " + entry,
		entry + "_99",
	])

func _vectors() -> void:
	var vectors: Dictionary = _json(VECTORS)
	_check(not vectors.is_empty(), "The shared vectors load")
	for name: String in vectors.get("blocked", []):
		_check(NameFilter.blocked(name), "Refused: " + name.c_escape())
	for name: String in vectors.get("allowed", []):
		_check(not NameFilter.blocked(name), "Passed: " + name)
		_check(DisplayNames.problem(name).is_empty(), "and the phone's check takes it: " + name)
	for fold: Dictionary in vectors.get("folds", []):
		_check(NameFilter.fold(str(fold.input)) == str(fold.plain), "Folds like the server: %s to %s, not %s" % [str(fold.input).c_escape(), fold.plain, NameFilter.fold(str(fold.input))])

func _anonymous() -> void:
	var missed := PackedStringArray()
	for word: String in _json(DisplayNames.WORDS_PATH).words:
		if NameFilter.blocked(word): missed.append(word)
		for n in range(10, 100):
			if NameFilter.blocked("%s %d" % [word, n]): missed.append("%s %d" % [word, n])
	_check(missed.is_empty(), "Every anonymous name passes; refused: " + ", ".join(missed))

func _display_names() -> void:
	_check(DisplayNames.problem("Pussy") == "display_name_refused" and DisplayNames.problem("  p u s s y ") == "display_name_refused", "The phone's check refuses a listed word")
	_check(PlayerCopy.DISPLAY_NAME_ERRORS.has("display_name_refused"), "and has words for it")
	_check(DisplayNames.problem("a".repeat(19)) == "length" and DisplayNames.problem("Fuck<") == "characters", "Length and characters are still said first")
	_check(not DisplayNames.valid_remote("Big Cock") and DisplayNames.valid_remote("Hancock"), "A listed name from the server is ignored, an innocent one is kept")
	var path := _path("display")
	var store := DisplayNames.new(path)
	_check(store.choose(SERVER, ME, "typed", "Slut").is_empty(), "A listed name is never chosen")
	# A name the server confirmed before the list grew: kept, not wiped.
	var file := {"schema_version": 1, "scopes": {DisplayNames.scope_key(SERVER, ME): {"enabled": true,
		"own": {"choice": "typed", "name": "Twat", "revision": 5, "state": "synced", "code": "", "asked": true, "confirmed": "Twat"},
		"names": {MAYA: {"name": "Wanker", "from": "friend", "at": 1}}}}}
	_write(path, file)
	store = DisplayNames.new(path)
	_check(store.own(SERVER, ME).name == "Twat" and store.own(SERVER, ME).confirmed == "Twat", "A kept own name the list came to refuse stays")
	_check(store.chosen(SERVER, ME, MAYA).is_empty(), "A kept friend's name the list refuses is not shown")
	store.take_friends_page(SERVER, ME, {"display_name": null, "friends": []})
	_check(store.own(SERVER, ME).choice == "anonymous" and store.own_shown(SERVER, ME) == DisplayNames.anonymous_name(ME), "The friends list's null makes this phone anonymous")

func _nicknames() -> void:
	var path := _path("nicknames")
	var nicknames := FriendNicknames.new(path)
	_check(not nicknames.set_nickname(SERVER, ME, MAYA, "Dumbass") and nicknames.nickname(SERVER, ME, MAYA).is_empty(), "A listed nickname is not saved")
	_check(FriendNicknames.refused(" Dumbass ") and not FriendNicknames.refused("Cassidy"), "The Friends screen can tell why")
	_check(nicknames.set_nickname(SERVER, ME, MAYA, "Cassidy") and nicknames.nickname(SERVER, ME, MAYA) == "Cassidy", "An innocent nickname is saved")
	_check(nicknames.set_nickname(SERVER, ME, MAYA, ""), "Clearing a nickname still works")
	_write(path, {"schema_version": 1, "entries": [{"server": SERVER, "owner": ME, "friend": MAYA, "nickname": "Bitch"}]})
	nicknames = FriendNicknames.new(path)
	_check(nicknames.nickname(SERVER, ME, MAYA).is_empty(), "A kept nickname the list came to refuse is not shown")
	_check(FileAccess.get_file_as_string(path).contains("Bitch"), "but it stays in the file")

func _odd_input() -> void:
	_check(not NameFilter.blocked("") and NameFilter.fold("").is_empty(), "An empty name is fine")
	_check(not NameFilter.blocked("a".repeat(NameFilter.MAX_INPUT)) and NameFilter.blocked("a".repeat(NameFilter.MAX_INPUT + 1)), "Input past the limit is refused unread")
	_check(not NameFilter.blocked(char(0x301) + char(0x200f) + char(0x202e) + char(0xffff)), "Marks and hidden characters alone are fine")
	for hidden: int in [0x200b, 0x200c, 0x200d, 0x200e, 0x200f, 0x2060, 0x202e, 0xfeff, 0xad, 0x301, 0x34f]:
		_check(NameFilter.blocked("pu" + char(hidden) + "ssy") and NameFilter.blocked("ni" + char(hidden) + "gger"), "A hidden character gets no word through: %x" % hidden)
	var swap_key := RegEx.create_from_string("^[0-9@$!]$")
	var folding: Dictionary = _json("res://content/display_name_blocklist.json").folding
	for key: String in folding.swaps.keys() + folding.alternate_swaps.keys():
		_check(swap_key.search(key) != null, "A swap key is a digit or @ $ !: " + key)

func _mapped(text: String, table: Dictionary) -> String:
	var out := ""
	for c: String in text: out += str(table.get(c, c))
	return out

func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func _path(label: String) -> String:
	var path := "user://test-name-filter-%s-%s.json" % [label, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

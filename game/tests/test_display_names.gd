extends SceneTree
## Display names on this phone (services/display_names.gd and its neighbours):
## - the rules: trimming, length 1 to 18, hidden and symbol characters, the
##   shared ellipsis cut, and names from others treated as untrusted;
## - the anonymous name made from a player id (the game's words and a number);
## - the player's own choice: kept, sent once with a rising revision, the
##   server's answer, a newer choice made while one is out, a refusal, and a
##   new phone following the name the friends list reports;
## - other players' names: a friends page replaces the friends' names, a room
##   reply adds or forgets a partner's, names go when the server stops showing
##   them, and the file survives a restart while bad entries are dropped;
## - the one resolver: a nickname, then the chosen name, then the anonymous
##   name while names are on, then the fallback;
## - the friends list's optional name keys, which never refuse a page;
## - rooms_api asks for names and takes the partner's name out of a room reply;
## - the room list keeps a partner's name; the roster and the room partner
##   friend request (state from what the phone keeps, the ordinary request).
const DisplayNames = preload("res://services/display_names.gd")
const Client = preload("res://services/display_name_client.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const FriendsClient = preload("res://services/friends_client.gd")
const FriendRoster = preload("res://services/friend_roster.gd")
const PartnerFriends = preload("res://services/partner_friends.gd")
const SafetyStore = preload("res://services/safety_store.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const RoomInbox = preload("res://services/room_inbox_client.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

# Synthetic ids only.
const SERVER := "https://names.example.test"
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const MAYA := "bbbbbbbbbbbbbbbbbbbbbb"
const SAM := "cccccccccccccccccccccc"
const RANDO := "dddddddddddddddddddddd"
const REQUEST := "eeeeeeeeeeeeeeeeeeeeee"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"

var checks := 0
var failures := 0
var _paths: Array[String] = []

class Api extends Node:
	var base_url := "https://names.example.test"
	var player_id := "aaaaaaaaaaaaaaaaaaaaaa"
	var device_token := "synthetic-token"

class FakeFriends extends RefCounted:
	var sent: Array = []
	var answer := true
	func add_friend(code: String) -> bool:
		sent.append(code)
		return answer

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_rules()
	_anonymous()
	_own()
	_others()
	_reload()
	_resolver()
	_friends_page()
	_rooms_api()
	_inbox()
	await _client()
	await _partners()
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	DisplayNames.use_shared(null)
	FriendRoster.use_shared(null)
	print("AFTER YOU DISPLAY NAMES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _path(label: String) -> String:
	var path := "user://test-display-names-%s-%s.json" % [label, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

func _store() -> RefCounted:
	return DisplayNames.new(_path("store"))

func _rules() -> void:
	_check(DisplayNames.clean("  Maya   Rose  ") == "Maya Rose", "Spaces are trimmed and runs of them made one")
	_check(DisplayNames.clean("Maya\tRose") == "Maya Rose", "A tab counts as a space")
	_check(DisplayNames.problem("") == "length" and DisplayNames.problem("   ") == "length", "An empty name is refused")
	_check(DisplayNames.problem("a".repeat(18)).is_empty() and DisplayNames.problem("a".repeat(19)) == "length", "18 characters pass and 19 do not")
	_check(DisplayNames.problem("Zoë").is_empty() and DisplayNames.problem("Мария").is_empty() and DisplayNames.problem("さくら").is_empty(), "Letters of every script pass")
	_check(DisplayNames.problem("O'Neil-Smith_2!").is_empty() and DisplayNames.problem("Robin’s pip?").is_empty(), "Digits and the allowed punctuation pass")
	for bad: String in ["Ma" + char(0x200b) + "ya", "Maya" + char(0x202e) + "evil", char(0x2066) + "x", "Maya" + char(0xfeff), "Be" + char(7) + "ll"]:
		_check(DisplayNames.problem(bad) == "characters", "A hidden character is refused: " + bad.c_escape())
	for bad: String in ["<b>Maya</b>", "[color=red]x", "Maya" + char(0x1f600), "a{b}", "50%", "#1", "Maya" + char(0x2665)]:
		_check(DisplayNames.problem(bad) == "characters", "Symbols and markup are refused: " + bad)
	_check(DisplayNames.valid_remote("Maya") and not DisplayNames.valid_remote(" Maya") and not DisplayNames.valid_remote("x".repeat(19)) and not DisplayNames.valid_remote(null) and not DisplayNames.valid_remote(4), "A name from the server must already follow the rules")
	_check(DisplayNames.short("Robin") == "Robin" and DisplayNames.short("a".repeat(20)) == "a".repeat(17) + "…" and DisplayNames.short("abcdef", 4) == "abc…", "The shared cut ends in an ellipsis within the limit")

func _anonymous() -> void:
	var first := DisplayNames.anonymous_name(ME)
	_check(first == DisplayNames.anonymous_name(ME), "The anonymous name is the same every time for one id")
	var pattern := RegEx.create_from_string("^[A-Z][a-z]+ [1-9][0-9]$")
	_check(pattern.search(first) != null, "It is a word and a two-digit number: " + first)
	_check(DisplayNames.problem(first).is_empty(), "and it follows the name rules")
	var seen := {}
	for i in range(40): seen[DisplayNames.anonymous_name(("p%d" % i).sha256_text().left(22))] = true
	_check(seen.size() >= 30, "Different ids mostly get different names: %d of 40" % seen.size())
	_check(DisplayNames.anonymous_name("not an id").is_empty() and DisplayNames.anonymous_name("friend-" + ME).is_empty(), "Only a player id gets one")

func _own() -> void:
	var store := _store()
	_check(store.own(SERVER, ME).choice == "" and not store.own(SERVER, ME).asked, "A new player has not chosen and was not asked")
	_check(store.own_shown(SERVER, ME) == DisplayNames.anonymous_name(ME), "Until then others see the anonymous name")
	_check(store.choose(SERVER, ME, "typed", "  x".repeat(10)).is_empty(), "A name the rules refuse is not kept")
	_check(store.choose(SERVER, ME, "nickname", "Robin").is_empty(), "An unknown choice is not kept")
	var first: Dictionary = store.choose(SERVER, ME, "typed", "  Robin ")
	_check(first.name == "Robin" and first.state == DisplayNames.PENDING and first.asked, "A typed name is kept, cleaned, waiting to be sent")
	_check(int(first.revision) > 1_600_000_000_000, "Its revision is a time in milliseconds, so a reinstall still sends a newer one")
	var second: Dictionary = store.choose(SERVER, ME, "typed", "Robin B")
	_check(int(second.revision) > int(first.revision), "Each choice has a higher revision")
	store.settle(SERVER, ME, int(first.revision), {"ok": true, "display_name": "Robin"})
	_check(store.own(SERVER, ME).name == "Robin B" and store.own(SERVER, ME).state == DisplayNames.PENDING, "A late answer for an older choice changes nothing")
	store.settle(SERVER, ME, int(second.revision), {"ok": true, "display_name": "Robin B"})
	_check(store.own(SERVER, ME).state == DisplayNames.SYNCED and store.own_shown(SERVER, ME) == "Robin B", "The server's answer confirms it")
	var refused: Dictionary = store.choose(SERVER, ME, "typed", "Badname")
	store.settle(SERVER, ME, int(refused.revision), {"ok": false, "code": "display_name_refused"})
	_check(store.own(SERVER, ME).state == DisplayNames.REFUSED and store.own(SERVER, ME).code == "display_name_refused", "A refusal is kept with its reason")
	_check(store.own_shown(SERVER, ME) == DisplayNames.anonymous_name(ME), "A refused name is never shown as the name others see")
	store.adopt(SERVER, ME, "Robin B")
	_check(store.own(SERVER, ME).state == DisplayNames.SYNCED and store.own(SERVER, ME).name == "Robin B", "The next friends list says what the server holds")
	var anonymous: Dictionary = store.choose(SERVER, ME, "anonymous", "ignored")
	_check(anonymous.name == "" and anonymous.choice == "anonymous", "Anonymous keeps no name")
	store.adopt(SERVER, ME, "Old name")
	_check(store.own(SERVER, ME).choice == "anonymous", "A choice waiting to be sent is never overwritten by the list")
	store.settle(SERVER, ME, int(anonymous.revision), {"ok": true, "display_name": null})
	_check(store.own(SERVER, ME).state == DisplayNames.SYNCED and store.own_shown(SERVER, ME) == DisplayNames.anonymous_name(ME), "Confirmed anonymous")
	var cleared := _store()
	var typed: Dictionary = cleared.choose(SERVER, ME, "typed", "Robin")
	cleared.settle(SERVER, ME, int(typed.revision), {"ok": true, "display_name": "Robin"})
	cleared.adopt(SERVER, ME, null)
	_check(cleared.own(SERVER, ME).choice == "anonymous", "A name the server cleared (an operator) clears here too")
	var fresh := _store()
	fresh.adopt(SERVER, ME, null)
	_check(fresh.own(SERVER, ME).choice == "" and not fresh.own(SERVER, ME).asked, "A phone that never chose stays unasked when the server holds no name")
	fresh.adopt(SERVER, ME, "Robin")
	_check(fresh.own(SERVER, ME).choice == "typed" and fresh.own(SERVER, ME).name == "Robin" and fresh.own(SERVER, ME).asked, "A new phone takes the name the account already has, and is not asked")
	var marked := _store()
	marked.mark_asked(SERVER, ME)
	_check(marked.own(SERVER, ME).asked and marked.own(SERVER, ME).choice == "", "Not now marks the prompt as asked without a choice")

func _others() -> void:
	var store := _store()
	_check(store.shown(SERVER, ME, MAYA) == "", "With names off, nothing is shown for others")
	store.take_friends_page(SERVER, ME, {"display_name": null, "friends": [{"player_id": MAYA, "display_name": "Maya"}, {"player_id": SAM, "display_name": null}, {"player_id": RANDO, "display_name": "<evil>"}]})
	_check(store.enabled(SERVER, ME), "A page with the own name key turns names on")
	_check(store.chosen(SERVER, ME, MAYA) == "Maya" and store.chosen(SERVER, ME, SAM) == "" and store.chosen(SERVER, ME, RANDO) == "", "A friend's name is kept; none and a broken one are not")
	_check(store.shown(SERVER, ME, SAM) == DisplayNames.anonymous_name(SAM), "A friend with no name shows their anonymous name")
	store.note_partner(SERVER, ME, RANDO, "Kit")
	_check(store.chosen(SERVER, ME, RANDO) == "Kit", "A room partner's name from a room reply is kept")
	store.take_friends_page(SERVER, ME, {"display_name": null, "friends": [{"player_id": SAM, "display_name": "Sam"}]})
	_check(store.chosen(SERVER, ME, MAYA) == "" and store.chosen(SERVER, ME, SAM) == "Sam", "A new page replaces the friends' names (a friend who left loses theirs)")
	_check(store.chosen(SERVER, ME, RANDO) == "Kit", "A room partner's name stays")
	store.note_partner(SERVER, ME, RANDO, null)
	_check(store.chosen(SERVER, ME, RANDO) == "", "A partner who went anonymous is forgotten")
	store.note_partner(SERVER, ME, RANDO, "x".repeat(40))
	store.note_partner(SERVER, ME, ME, "Me")
	_check(store.chosen(SERVER, ME, RANDO) == "" and store.chosen(SERVER, ME, ME) == "", "A broken name and the player's own id are ignored")
	for i in range(DisplayNames.MAX_NAMES + 5): store.note_partner(SERVER, ME, ("partner%d" % i).sha256_text().left(22), "P%d" % i)
	var kept := 0
	for i in range(DisplayNames.MAX_NAMES + 5): kept += int(not store.chosen(SERVER, ME, ("partner%d" % i).sha256_text().left(22)).is_empty())
	_check(kept <= DisplayNames.MAX_NAMES and store.chosen(SERVER, ME, SAM) == "Sam", "Partner names are capped and friends' names stay: %d" % kept)
	store.take_friends_page(SERVER, ME, {"friends": [{"player_id": SAM}]})
	_check(not store.enabled(SERVER, ME) and store.chosen(SERVER, ME, SAM) == "" and store.shown(SERVER, ME, SAM) == "", "A page without names turns them off and forgets every name")
	_check(store.chosen("https://other.example.test", ME, SAM) == "", "Another server is another scope")

func _reload() -> void:
	var path := _path("reload")
	var store: RefCounted = DisplayNames.new(path)
	store.take_friends_page(SERVER, ME, {"display_name": "Robin", "friends": [{"player_id": MAYA, "display_name": "Maya"}]})
	var again: RefCounted = DisplayNames.new(path)
	_check(again.enabled(SERVER, ME) and again.chosen(SERVER, ME, MAYA) == "Maya" and again.own(SERVER, ME).name == "Robin", "Names and the own choice survive a restart")
	again.clear_owner(ME)
	_check(not DisplayNames.new(path).enabled(SERVER, ME), "Clearing a player (account deletion) forgets everything kept for them")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version": 1, "scopes": {SERVER + "|" + ME: {"enabled": true, "own": {"choice": "typed", "name": "<b>x</b>", "state": "synced"}, "names": {MAYA: {"name": "Maya", "from": "friend", "at": 1}, SAM: {"name": char(0x202e) + "x", "from": "friend"}, RANDO: {"name": "Kit", "from": "elsewhere"}}}}}))
	file.close()
	var damaged: RefCounted = DisplayNames.new(path)
	_check(damaged.chosen(SERVER, ME, MAYA) == "Maya" and damaged.chosen(SERVER, ME, SAM) == "" and damaged.chosen(SERVER, ME, RANDO) == "" and damaged.own(SERVER, ME).choice == "", "A damaged file keeps only entries that follow the rules")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	_check(not DisplayNames.new(path).enabled(SERVER, ME), "An unreadable file reads as nothing kept")

func _resolver() -> void:
	var store := _store()
	DisplayNames.use_shared(store)
	var nicknames: RefCounted = FriendNicknames.new(_path("nicknames"))
	_check(nicknames.display_name(SERVER, ME, MAYA) == FriendNicknames.FALLBACK, "Names off: the old fallback")
	store.take_friends_page(SERVER, ME, {"display_name": null, "friends": [{"player_id": MAYA, "display_name": "Maya"}]})
	_check(nicknames.display_name(SERVER, ME, MAYA) == "Maya", "The resolver shows the name a friend chose")
	_check(nicknames.display_name(SERVER, ME, SAM) == DisplayNames.anonymous_name(SAM), "and the anonymous name of anyone without one")
	nicknames.set_nickname(SERVER, ME, MAYA, "Sunny")
	_check(nicknames.display_name(SERVER, ME, MAYA) == "Sunny", "A nickname this phone set wins over any chosen name")
	nicknames.set_nickname(SERVER, ME, MAYA, "")
	_check(nicknames.display_name(SERVER, ME, MAYA) == "Maya", "Clearing the nickname brings the chosen name back")
	DisplayNames.use_shared(null)

func _friends_page() -> void:
	var base := {"schema_version": 1, "friend_code": ME, "refresh_after_seconds": 30, "shared_room": null, "friends": [
		{"player_id": MAYA, "request_id": REQUEST, "status": "accepted", "online": false, "expires_after_seconds": 0, "join_available": false}]}
	_check(FriendsClient.valid_page(base, ME), "A page without names is valid as before")
	var named := base.duplicate(true)
	named["display_name"] = "Robin"
	named.friends[0]["display_name"] = "Maya"
	_check(FriendsClient.valid_page(named, ME), "A page with the own name and a friend's name is valid")
	named.friends[0]["display_name"] = "<b>not allowed</b>"
	_check(FriendsClient.valid_page(named, ME), "A name the rules refuse never refuses the page")
	named.friends[0]["display_name"] = 7
	_check(not FriendsClient.valid_page(named, ME), "A name that is not text does")
	named.friends[0]["display_name"] = "x".repeat(65)
	_check(not FriendsClient.valid_page(named, ME), "and so does a very long one")
	named.friends[0]["display_name"] = null
	named["extra"] = 1
	_check(not FriendsClient.valid_page(named, ME), "An unknown key is still refused")

func _rooms_api() -> void:
	var friends := RoomsApi.capability_headers(HTTPClient.METHOD_GET, "/v1/friends")
	_check(DisplayNames.HEADER in friends, "The friends list asks for names")
	for path: String in ["/v2/capabilities", "/v1/room-inbox", "/v2/rooms/" + ROOM]:
		_check(DisplayNames.HEADER in RoomsApi.capability_headers(HTTPClient.METHOD_GET, path), "So does " + path)
	_check(DisplayNames.HEADER in RoomsApi.capability_headers(HTTPClient.METHOD_POST, "/v2/rooms/" + ROOM + "/turns"), "So does a turn")
	_check(not DisplayNames.HEADER in RoomsApi.capability_headers(HTTPClient.METHOD_GET, "/v1/social/inbox"), "Other routes do not")
	var api := RoomsApi.new()
	var body := JSON.stringify({"schema_version": 1, "room": {"room_id": ROOM}, "partner_name": "Maya"}).to_utf8_buffer()
	var result: Dictionary = api._result([HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), body], HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM)
	_check(result.get("partner_name") == "Maya" and not result.data.has("partner_name"), "The partner's name leaves the room reply, so the room kept is unchanged")
	api.free()

func _inbox() -> void:
	var store := _store()
	DisplayNames.use_shared(store)
	var api := Api.new()
	root.add_child(api)
	var inbox: RefCounted = RoomInbox.new(api, func() -> Dictionary: return {"ready": true, "player_id": ME, "epoch": 1})
	var entry := {"room_id": ROOM, "family": "relay", "api_version": 2, "chapter": {"id": "relay", "version": 1}, "membership": {"host_id": ME, "guest_id": RANDO, "you_are_host": true},
		"status": "your_turn", "revision": 3, "remote_activity_sequence": 0, "activity_at": null, "partner_name": "Kit"}
	_check(RoomInbox.valid_server_room(entry), "A room list entry with the partner's name is valid")
	var long := entry.duplicate(true)
	long.partner_name = "x".repeat(70)
	_check(not RoomInbox.valid_server_room(long), "A very long one is not")
	var none := entry.duplicate(true)
	none.partner_name = null
	_check(RoomInbox.valid_server_room(none), "No name (null) is valid")
	inbox._normalize_room(entry)
	_check(store.chosen(SERVER.replace("names.", "names."), ME, RANDO) == "Kit" or store.chosen(api.base_url, ME, RANDO) == "Kit", "The room list keeps the partner's name")
	inbox._normalize_room(none)
	_check(store.chosen(api.base_url, ME, RANDO) == "", "and forgets it when they have none")
	api.queue_free()
	DisplayNames.use_shared(null)

func _client() -> void:
	var store := _store()
	var api := Api.new()
	root.add_child(api)
	var sent: Array = []
	var replies: Array = []
	var transport := func(method: int, path: String, body: Dictionary) -> Dictionary:
		sent.append({"method": method, "path": path, "body": body.duplicate(true)})
		await process_frame
		return replies.pop_front() if not replies.is_empty() else {"ok": false, "code": "connection_interrupted"}
	var identity := func() -> Dictionary: return {"ready": true, "player_id": ME, "epoch": 1}
	var client: RefCounted = Client.new(api, identity, transport, store)
	_check((await client.send(10)).get("done") == true and sent.is_empty(), "Nothing waiting: nothing is sent")
	var mine: Dictionary = store.choose(api.base_url, ME, "typed", "Robin")
	replies.append({"ok": true, "data": {"schema_version": 1, "display_name": "Robin", "revision": mine.revision}})
	var answer: Dictionary = await client.send(2000)
	_check(answer.done and answer.ok and sent.size() == 1, "Save sends the choice once and waits for the answer")
	_check(sent[0].method == HTTPClient.METHOD_PUT and sent[0].path == "/v1/profile/name" and sent[0].body == {"schema_version": 1, "display_name": "Robin", "revision": int(mine.revision)}, "The body is the contract's")
	_check(store.own(api.base_url, ME).state == DisplayNames.SYNCED, "and the answer is kept")
	mine = store.choose(api.base_url, ME, "anonymous")
	replies.append({"ok": false, "code": "connection_interrupted"})
	answer = await client.send(2000)
	_check(not answer.done and store.own(api.base_url, ME).state == DisplayNames.PENDING and sent[1].body.display_name == null, "Anonymous sends null; a network failure keeps it waiting")
	replies.append({"ok": true, "data": {"schema_version": 1, "display_name": null, "revision": mine.revision}})
	client.flush()
	for i in range(4): await process_frame
	_check(sent.size() == 3 and store.own(api.base_url, ME).state == DisplayNames.SYNCED, "A flush after a friends read sends what waited")
	mine = store.choose(api.base_url, ME, "typed", "Badname")
	replies.append({"ok": false, "code": "display_name_refused"})
	var heard: Array = []
	client.settled.connect(func(value: Dictionary) -> void: heard.append(value))
	answer = await client.send(2000)
	_check(answer.done and not answer.ok and answer.code == "display_name_refused" and store.own(api.base_url, ME).state == DisplayNames.REFUSED, "A refusal comes back to the card with its reason")
	_check(heard.size() == 1 and heard[0].code == "display_name_refused", "and is said once")
	mine = store.choose(api.base_url, ME, "typed", "Slow")
	replies.append({"ok": false, "code": "display_names_disabled"})
	answer = await client.send(0)
	_check(not answer.done, "Save with no time to wait closes and leaves it waiting")
	for i in range(4): await process_frame
	_check(store.own(api.base_url, ME).state == DisplayNames.PENDING, "A server pause (503) keeps it waiting, not refused")
	# A newer choice made while one is out goes as soon as that one returns.
	store.choose(api.base_url, ME, "typed", "First")
	var newer_sent := sent.size()
	replies.append({"ok": false, "code": "connection_interrupted"})
	client.flush()
	var newest: Dictionary = store.choose(api.base_url, ME, "typed", "Second")
	replies.append({"ok": true, "data": {"schema_version": 1, "display_name": "Second", "revision": newest.revision}})
	for i in range(8): await process_frame
	_check(sent.size() == newer_sent + 2 and sent.back().body.display_name == "Second" and store.own(api.base_url, ME).state == DisplayNames.SYNCED, "The newer choice is sent after the one that was out")
	api.queue_free()

func _partners() -> void:
	var roster: RefCounted = FriendRoster.new(_path("roster"))
	var safety: RefCounted = SafetyStore.new("user://test-display-names-safety-" + Crypto.new().generate_random_bytes(4).hex_encode())
	var friends := FakeFriends.new()
	var scope := func() -> Dictionary: return {"server": SERVER, "owner": ME}
	var partners: RefCounted = PartnerFriends.new(scope, func(_create: bool) -> RefCounted: return friends, roster, safety)
	_check(partners.state(RANDO, "relay", ROOM) == PartnerFriends.ADDABLE, "A partner who is not a friend can be added")
	_check(partners.state(ME, "relay", ROOM) == PartnerFriends.HIDDEN and partners.state("", "relay", ROOM) == PartnerFriends.HIDDEN, "Never yourself or no one")
	roster.take_page(SERVER, ME, {"friends": [{"player_id": MAYA, "status": "accepted"}, {"player_id": SAM, "status": "incoming"}]})
	_check(partners.state(MAYA, "relay", ROOM) == PartnerFriends.HIDDEN, "A friend is not offered")
	_check(partners.state(SAM, "relay", ROOM) == PartnerFriends.HIDDEN, "Nor someone whose request waits for this player")
	_check(await partners.send(RANDO) and friends.sent == [RANDO], "Add friend sends the ordinary request with the partner's id")
	roster.note_request(SERVER, ME, RANDO)
	_check(partners.state(RANDO, "relay", ROOM) == PartnerFriends.REQUESTED, "then shows Request sent")
	_check(not await partners.send(RANDO) and friends.sent.size() == 1, "and never sends twice")
	var blocked := SafetyStore.empty(ME)
	var other := "ffffffffffffffffffffff"
	blocked.blocked_players = [other]
	blocked.blocked_rooms = {"relay:" + ROOM: other}
	var read: Dictionary = safety.read(ME)
	_check(read.ok and safety.write(ME, blocked, read.value), "A blocked partner is recorded")
	_check(partners.state(other, "relay", ROOM) == PartnerFriends.HIDDEN, "A blocked partner is not offered")
	var reported := SafetyStore.empty(ME)
	reported.pending = {"schema_version": 1, "idempotency_key": "k".repeat(20), "room_family": "relay", "room_id": "QQQQQQQQQQQQQQQQQQQQQQ", "reason": "harassment", "photo": null}
	read = safety.read(ME)
	_check(read.ok and safety.write(ME, reported, read.value), "A report is recorded")
	_check(partners.state("gggggggggggggggggggggg", "relay", "QQQQQQQQQQQQQQQQQQQQQQ") == PartnerFriends.HIDDEN, "A partner in a room being reported is not offered")
	safety.erase(ME)
	_check(PlayerCopy.ROOM_ADD_FRIEND == "Add friend" and PlayerCopy.ROOM_FRIEND_REQUESTED == "Request sent", "The owner's labels")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

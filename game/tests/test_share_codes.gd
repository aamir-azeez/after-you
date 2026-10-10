extends SceneTree
## Typed share codes and invite links: pure formatting and parsing.
const ShareCodes = preload("res://services/share_codes.gd")
const InviteShare = preload("res://services/invite_share.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const FRIEND_ID := "Ab9_-xxxxxxxxxxxxxxxxZ"
const ROOM_CODE := "0123456789ABCDEF0123"
var checks := 0
var failures := 0

func _initialize() -> void:
	_check(FRIEND_ID.length() == 22 and ROOM_CODE.length() == 20, "Fixtures use the server ID shapes")
	_formatting()
	_friend_input()
	_room_input()
	_links()
	_messages()
	print("SHARE CODES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _ok(result: Dictionary, type: String, id: String, message: String) -> void:
	_check(result.get("ok") == true and result.get("type") == type and result.get("id") == id, message + " -> " + JSON.stringify(result))

func _fails(result: Dictionary, error: String, type: String, message: String) -> void:
	_check(result.get("ok") == false and result.get("error") == error and result.get("type") == type and not result.has("id"), message + " -> " + JSON.stringify(result))

func _formatting() -> void:
	_check(ShareCodes.format(ShareCodes.FRIEND, FRIEND_ID) == "friend-" + FRIEND_ID, "Friend codes are friend-<id>")
	_check(ShareCodes.format(ShareCodes.ROOM, ROOM_CODE) == "room-" + ROOM_CODE, "Room codes are room-<code>")
	for bad: Variant in [null, "", FRIEND_ID.substr(1), FRIEND_ID + "x", "friend-" + FRIEND_ID, FRIEND_ID.replace("Z", "="), 42]:
		_check(ShareCodes.format(ShareCodes.FRIEND, bad).is_empty(), "Only a canonical friend ID formats: " + str(bad))
	for bad: Variant in [ROOM_CODE.to_lower(), ROOM_CODE.substr(1), "0123-4567-89AB-CDEF-0123", "room-" + ROOM_CODE, ROOM_CODE.replace("0", "G")]:
		_check(ShareCodes.format(ShareCodes.ROOM, bad).is_empty(), "Only a canonical room code formats: " + str(bad))
	_check(ShareCodes.format("party", FRIEND_ID).is_empty(), "Unknown types never format")
	_check(ShareCodes.display(ShareCodes.ROOM, ROOM_CODE) == "room-" + ROOM_CODE and ShareCodes.display(ShareCodes.FRIEND, "ABCD1234") == "ABCD1234", "Display falls back to the raw value when it is not canonical")
	_check(ShareCodes.link(ShareCodes.FRIEND, FRIEND_ID) == "https://aamirazeez.com/after-you/link#friend-" + FRIEND_ID, "Invite links carry the code in the fragment")
	_check(ShareCodes.link(ShareCodes.ROOM, ROOM_CODE).is_empty() and ShareCodes.link(ShareCodes.FRIEND, "bad").is_empty(), "Rooms and invalid IDs have no link")
	for type: String in ShareCodes.TYPES:
		var id := FRIEND_ID if type == ShareCodes.FRIEND else ROOM_CODE
		_ok(ShareCodes.parse(ShareCodes.format(type, id), type), type, id, "Every type round-trips through format and parse")

func _friend_input() -> void:
	var friend := ShareCodes.FRIEND
	_ok(ShareCodes.parse("friend-" + FRIEND_ID, friend), friend, FRIEND_ID, "Prefixed friend code")
	_ok(ShareCodes.parse(FRIEND_ID, friend), friend, FRIEND_ID, "Legacy bare friend ID")
	_ok(ShareCodes.parse("  \tfriend-" + FRIEND_ID + " \n", friend), friend, FRIEND_ID, "Surrounding whitespace is ignored")
	_ok(ShareCodes.parse("Friend-" + FRIEND_ID, friend), friend, FRIEND_ID, "Keyboard capitalisation of the prefix is accepted")
	_ok(ShareCodes.parse("FRIEND-" + FRIEND_ID, friend), friend, FRIEND_ID, "The type prefix is case-insensitive")
	_ok(ShareCodes.parse(ShareCodes.link(friend, FRIEND_ID), friend), friend, FRIEND_ID, "A pasted invite link adds the friend")
	var lowered := ShareCodes.parse("friend-" + FRIEND_ID.to_lower(), friend)
	_check(lowered.ok and lowered.id == FRIEND_ID.to_lower() and lowered.id != FRIEND_ID, "Friend IDs stay case-sensitive")
	# A legacy ID that happens to start like a prefix still parses as the bare ID.
	var lookalike := "room-abcdefghijklmnopq"
	_ok(ShareCodes.parse(lookalike, friend), friend, lookalike, "A 22-character legacy ID beginning with room- is still a friend ID")
	var friend_lookalike := "friend-abcdefghijklmno"
	_ok(ShareCodes.parse(friend_lookalike, friend), friend, friend_lookalike, "A 22-character legacy ID beginning with friend- is still a friend ID")
	_fails(ShareCodes.parse("room-" + ROOM_CODE, friend), "wrong_type", ShareCodes.ROOM, "A room code in Add friend is the wrong type")
	_fails(ShareCodes.parse(ROOM_CODE, friend), "wrong_type", ShareCodes.ROOM, "A legacy room code in Add friend is the wrong type")
	_fails(ShareCodes.parse("room-" + ROOM_CODE.to_lower(), friend), "wrong_type", ShareCodes.ROOM, "Any room code form is recognised")
	for bad: Variant in ["", "   ", "friend-", "friend-" + FRIEND_ID.substr(1), "friend-" + FRIEND_ID + "x", "friend " + FRIEND_ID, "friend-" + FRIEND_ID.substr(0, 10) + " " + FRIEND_ID.substr(10), "friend-" + FRIEND_ID.replace("Z", "+"), "friend-" + FRIEND_ID.replace("Z", "é"), "party-" + FRIEND_ID, "x".repeat(300), null, 7]:
		_check(not ShareCodes.parse(bad, friend).ok, "Invalid friend input is rejected: " + str(bad))
	_fails(ShareCodes.parse("friend-" + FRIEND_ID.substr(1), friend), "invalid", friend, "A malformed prefixed code reports its detected type")
	_check(not ShareCodes.parse("friend-" + FRIEND_ID, "party").ok, "An unknown expected type never accepts input")

func _room_input() -> void:
	var room := ShareCodes.ROOM
	_ok(ShareCodes.parse("room-" + ROOM_CODE, room), room, ROOM_CODE, "Prefixed room code")
	_ok(ShareCodes.parse(ROOM_CODE, room), room, ROOM_CODE, "Legacy room code")
	_ok(ShareCodes.parse(ROOM_CODE.to_lower(), room), room, ROOM_CODE, "Legacy lower case is uppercased")
	_ok(ShareCodes.parse("Room-" + ROOM_CODE.to_lower(), room), room, ROOM_CODE, "Prefix removed before uppercasing")
	_ok(ShareCodes.parse("ROOM-0123-4567 89ab-CDEF-0123", room), room, ROOM_CODE, "Prefix removed before spaces and grouping hyphens are stripped")
	_ok(ShareCodes.parse(" 0123 4567-89AB CDEF-0123 ", room), room, ROOM_CODE, "Legacy grouped input keeps working")
	_fails(ShareCodes.parse("friend-" + FRIEND_ID, room), "wrong_type", ShareCodes.FRIEND, "A friend code in Join is the wrong type")
	_fails(ShareCodes.parse(FRIEND_ID, room), "wrong_type", ShareCodes.FRIEND, "A legacy friend ID in Join is the wrong type")
	_fails(ShareCodes.parse(ShareCodes.link(ShareCodes.FRIEND, FRIEND_ID), room), "wrong_type", ShareCodes.FRIEND, "An invite link in Join is the wrong type")
	for bad: Variant in ["room-", "room-" + ROOM_CODE.substr(1), "room-" + ROOM_CODE + "0", "room-" + ROOM_CODE.replace("0", "G"), "roomx" + ROOM_CODE, "room_" + ROOM_CODE, "ROOM" + ROOM_CODE, "invite-" + ROOM_CODE, "https://aamirazeez.com/after-you/link#room-" + ROOM_CODE]:
		_check(not ShareCodes.parse(bad, room).ok, "Invalid room input is rejected: " + str(bad))

func _links() -> void:
	var base := "https://aamirazeez.com/after-you/link"
	for good: String in [base + "#friend-" + FRIEND_ID, base + "?c=friend-" + FRIEND_ID, base + "/#friend-" + FRIEND_ID, base + "/?c=friend-" + FRIEND_ID, "HTTPS://AamirAzeez.com/after-you/link#friend-" + FRIEND_ID]:
		_ok(ShareCodes.parse_link(good), ShareCodes.FRIEND, FRIEND_ID, "Accepted invite link form: " + good)
	for bad: Variant in [null, "", "invalid", "http://aamirazeez.com/after-you/link#friend-" + FRIEND_ID, "https://www.aamirazeez.com/after-you/link#friend-" + FRIEND_ID, "https://aamirazeez.com.evil.test/after-you/link#friend-" + FRIEND_ID, "https://user@aamirazeez.com/after-you/link#friend-" + FRIEND_ID, "https://aamirazeez.com:443/after-you/link#friend-" + FRIEND_ID, "https://aamirazeez.com/after-you#friend-" + FRIEND_ID, "https://aamirazeez.com/after-you/#friend-" + FRIEND_ID, "https://aamirazeez.com/after-you/linked#friend-" + FRIEND_ID, "https://aamirazeez.com/after-you/link/x#friend-" + FRIEND_ID, "https://aamirazeez.com/After-You/link#friend-" + FRIEND_ID, base + "#" + FRIEND_ID, base + "#Friend-" + FRIEND_ID, base + "#room-" + ROOM_CODE, base + "#friend-" + FRIEND_ID.substr(1), base + "#friend-" + FRIEND_ID + "x", base + "?c=friend-" + FRIEND_ID + "#friend-" + FRIEND_ID, base + "?c=friend-" + FRIEND_ID + "&x=1", base + "?x=1&c=friend-" + FRIEND_ID, base + "?code=friend-" + FRIEND_ID, base + "#friend-" + FRIEND_ID + "\n", " " + base + "#friend-" + FRIEND_ID, base + "#friend-" + FRIEND_ID.replace("Z", "%"), base + "#friend-" + "x".repeat(300)]:
		_check(not ShareCodes.parse_link(bad).ok, "Rejected invite link: " + str(bad).c_escape())

func _messages() -> void:
	_check(ShareCodes.error_message(ShareCodes.parse("room-" + ROOM_CODE, ShareCodes.FRIEND), "fallback") == PlayerCopy.SHARE_CODE_ROOM_NOT_FRIEND, "A room code in Add friend gets a clear message")
	_check(ShareCodes.error_message(ShareCodes.parse("friend-" + FRIEND_ID, ShareCodes.ROOM), "fallback") == PlayerCopy.SHARE_CODE_FRIEND_NOT_ROOM, "A friend code in Join gets a clear message")
	_check(ShareCodes.error_message(ShareCodes.parse("nonsense", ShareCodes.ROOM), "fallback") == "fallback", "Other invalid input keeps the caller's existing message")
	var text := InviteShare.message(FRIEND_ID)
	_check(text.contains(ShareCodes.link(ShareCodes.FRIEND, FRIEND_ID)) and text.contains("friend-" + FRIEND_ID) and text == PlayerCopy.INVITE_SHARE_MESSAGE % [ShareCodes.link(ShareCodes.FRIEND, FRIEND_ID), "friend-" + FRIEND_ID], "Shared text carries the invite link plus the typed code")
	_check(InviteShare.message("bad").is_empty(), "No share text without a valid friend ID")
	var sent: Array = []
	var copied: Array = []
	var sheet_ok := func(value: String) -> bool:
		sent.append(value)
		return true
	var sheet_missing := func(value: String) -> bool:
		sent.append(value)
		return false
	var copy := func(value: String) -> void:
		copied.append(value)
	_check(InviteShare.share(FRIEND_ID, sheet_ok, copy), "Share accepts a valid ID")
	_check(sent == [text] and copied.is_empty(), "A share sheet receives the message once without a clipboard write")
	sent.clear()
	_check(InviteShare.share(FRIEND_ID, sheet_missing, copy), "Share without a share sheet still succeeds")
	_check(sent == [text] and copied == ["friend-" + FRIEND_ID], "Without a share sheet the typed code is copied once")
	sent.clear()
	copied.clear()
	_check(not InviteShare.share("bad", sheet_ok, copy) and sent.is_empty() and copied.is_empty(), "An invalid ID shares and copies nothing")

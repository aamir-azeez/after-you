extends "res://tests/test_online_scenarios.gd"
## A hosted room is named by its own chapter everywhere the host and their
## friends look. The report (0.6.0): a host chose a chapter, went to Friends and
## found First Steps there. Every rebuilt hub fell back to its first chapter,
## First Steps, so Host after a visit to Friends hosted First Steps; and the
## Friends room card never named a shared room that was not the current one.
const Registry = preload("res://services/chapter_registry.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
const RoomInboxClient = preload("res://services/room_inbox_client.gd")
const FIRST_STEPS := "first-steps@1"
const RELAY_TITLE := "The Relay Isles"
const FIRST_TITLE := "First Steps"

func scenarios() -> Array[Callable]:
	return [_one_resolver, _choice_survives_friends, _shared_room_named, _friend_side]

func suite_name() -> String:
	return "Hosted chapter"

## Both phones' server offers First Steps beside the Relay Isles, as live does.
func _begin_two_chapters(name: String) -> void:
	await _begin(name)
	h.server.chapters.assign([h.RELAY, FIRST_STEPS])

func _texts(device: Node) -> Array[String]:
	return device.visible_texts()

func _friends_open(device: Node) -> bool:
	return device.running() and is_instance_valid(device.app.friends_screen) and device.app.mode == "friends"

func _hub_choice(device: Node) -> String:
	return device.hub().selected_key() if device.hub() != null else ""

func _hero(device: Node) -> String:
	return device.hub()._hero_title.text if device.hub() != null else ""

func _shared_line(device: Node) -> String:
	var line: Label = device.app.friends_screen.find_child("SharedRoomLine", true, false) if _friends_open(device) else null
	return line.text if line != null and line.is_visible_in_tree() else ""

## One resolver names every room: each chapter's own id and version give its
## own title, and nothing unknown borrows the first chapter's name.
func _one_resolver() -> void:
	h.scenario = "one resolver"
	for key: String in Registry.keys():
		var known := Registry.descriptor(key)
		h.check(RoomChapterTitle.key(known.level_id, known.level_version) == key, "%s round-trips through its level id and version" % key)
		h.check(RoomChapterTitle.title(key) == str(known.title), "%s is named by its own title" % key)
		h.check(RoomChapterTitle.for_room({"level_id": known.level_id, "level_version": float(known.level_version)}) == str(known.title), "%s is named from a room's JSON level fields" % key)
	for unknown: Variant in [{}, {"level_id": "the-orchard", "level_version": 1}, {"level_id": "first-steps", "level_version": 9}, {"level_id": 0, "level_version": 1}, {"level_id": "first-steps"}]:
		h.check(RoomChapterTitle.for_room(unknown) == RoomChapterTitle.UNKNOWN, "an unknown room is a neutral saved chapter, never First Steps: %s" % [unknown])
	h.check(RoomChapterTitle.title("", "Current room") == "Current room", "an empty key keeps the caller's neutral label")
	h.check(RoomChapterTitle.legacy_title("first-light") == "First Light" and RoomChapterTitle.title("legacy-first-light") == "First Light", "an earlier island is named by its level id")
	h.check(RoomChapterTitle.legacy_title(0) == RoomChapterTitle.UNKNOWN and RoomChapterTitle.legacy_title(1.0, "Island") == "Island", "a numeric legacy id is not clamped to the first island")
	var inbox := RoomInboxClient.new(null, Callable())
	var shown: Dictionary = inbox._normalize_room({"room_id": "r", "family": "relay", "api_version": 2, "chapter": {"id": "the-wishing-well", "version": 1}, "membership": {}})
	h.check(shown.chapter_key == "the-wishing-well@1" and shown.chapter_title == "The Wishing Well", "the hub names an inbox room by its chapter id and version: %s" % [shown])
	shown = inbox._normalize_room({"room_id": "r", "family": "relay", "api_version": 2, "chapter": {"id": "the-orchard", "version": 1}, "membership": {}})
	h.check(shown.chapter_title == "The Orchard", "a chapter this build lacks keeps a name from its own id")

## The reported order: choose a chapter, look at Friends, come back and host.
## The hub kept First Steps after each rebuild, so the room was First Steps.
func _choice_survives_friends() -> void:
	await _begin_two_chapters("choice survives a visit to Friends")
	await h.step("host opens the hub", func(): h.open_hub(host))
	h.check(_hub_choice(host) == FIRST_STEPS, "a fresh hub starts on First Steps")
	await h.step("host chooses the Relay Isles", func(): host.hub()._choose_chapter(h.RELAY))
	await h.step("host opens the Friends tab", func(): host.hub()._select_tab("Friends"))
	h.check(_friends_open(host), "the Friends tab opens Friends")
	await h.step("host goes back to the hub", func(): h.back(host))
	h.check(_hub_choice(host) == h.RELAY and _hero(host) == RELAY_TITLE, "back from Friends the hub still offers the Relay Isles (saw %s, '%s')" % [_hub_choice(host), _hero(host)])
	await h.step("host opens Friends again", func(): host.hub()._select_tab("Friends"))
	await h.step("host taps Host a room on Friends", func(): h.press(host, "Host a room"))
	h.check(_hub_choice(host) == h.RELAY, "Friends' Host a room returns to the Relay Isles (saw %s)" % _hub_choice(host))
	await h.step("host sets Invitation only and back again", func(): host.hub()._set_visibility("Invitation only"))
	await h.step("host opens Friends a third time", func(): host.hub()._select_tab("Friends"))
	await h.step("host goes back", func(): h.back(host))
	h.check(host.hub() != null and host.hub()._visibility == "invitation_only", "the hub keeps Invitation only too")
	await h.step("host sets Friends", func(): host.hub()._set_visibility("Friends"))
	await h.step("host hosts", func(): h.press(host, "HostRoom"))
	var room: String = h.current_room(host)
	h.check(not room.is_empty() and h.server.room_chapter(room) == h.RELAY, "the room the host made is the Relay Isles (server has %s)" % h.server.room_chapter(room))
	await h.step("host goes back", func(): h.back(host))
	h.check(_hub_choice(host) == h.RELAY and _hero(host) == RELAY_TITLE, "after hosting the hub still offers the Relay Isles, not First Steps")
	await h.step("host opens the Friends tab", func(): host.hub()._select_tab("Friends"))
	var texts := _texts(host)
	print("      host Friends: %s" % " | ".join(texts))
	h.check(RELAY_TITLE in texts and FIRST_TITLE not in texts, "the host's Friends shows the Relay Isles and no First Steps")
	h.check("Shared with friends" in texts and _shared_line(host).is_empty(), "the current room is the shared one, so no second line names it")
	await h.step("host leaves Friends", func(): h.back(host))
	await h.finish()

## The host shares one room and then plays in another chapter's room. The
## Friends card shows the room just played (First Steps) with Stop sharing
## under it, so it read as sharing First Steps; the shared room is now named.
func _shared_room_named() -> void:
	await _begin_two_chapters("shared room named by its chapter")
	await h.step("guest opens the hub", func(): h.open_hub(guest))
	await h.step("guest chooses First Steps", func(): guest.hub()._choose_chapter(FIRST_STEPS))
	await h.step("guest sets Invitation only", func(): guest.hub()._set_visibility("Invitation only"))
	await h.step("guest hosts First Steps", func(): h.press(guest, "HostRoom"))
	var first: String = h.current_room(guest)
	var code: String = h.invitation(guest)
	h.check(h.server.room_chapter(first) == FIRST_STEPS, "the guest's room is First Steps")
	await h.step("host opens the hub", func(): h.open_hub(host))
	await h.step("host hosts the Relay Isles for friends", func(): h.host_room(host))
	var shared: String = h.current_room(host)
	h.check(FriendsClientShape.same(h.server.players[host.player_id].get("shared_room"), shared), "the Relay room is shared with friends")
	await h.step("host goes back", func(): h.back(host))
	await h.step("host joins the guest's First Steps room", func(): h.join_room(host, code))
	h.check(h.current_room(host) == first, "the host is in the First Steps room")
	await h.step("host goes back", func(): h.back(host))
	await h.step("host opens the Friends tab", func(): host.hub()._select_tab("Friends"))
	var texts := _texts(host)
	print("      host Friends: %s" % " | ".join(texts))
	h.check(FIRST_TITLE in texts and "Stop sharing room" in texts, "the card shows the room just played, First Steps, with Stop sharing")
	h.check(_shared_line(host) == "Shared with friends · " + RELAY_TITLE, "the shared room is named by its own chapter (saw '%s')" % _shared_line(host))
	await h.step("host leaves Friends", func(): h.back(host))
	await h.step("guest goes back", func(): h.back(guest))
	await h.finish()

## A friend of the host sees the host's room as Join, never under another
## chapter's name. The friends list and hosting alert carry no chapter today
## (backend/src/friends-routes.ts:81-82, notifications.ts:5), so nothing names it.
func _friend_side() -> void:
	await _begin_two_chapters("what the host's friend sees")
	h.server.befriend(host.player_id, guest.player_id)
	await h.step("host opens the hub", func(): h.open_hub(host))
	await h.step("host hosts the Relay Isles for friends", func(): h.host_room(host))
	await h.step("guest opens the hub", func(): h.open_hub(guest))
	await h.step("guest opens the Friends tab", func(): guest.hub()._select_tab("Friends"))
	var texts := _texts(guest)
	print("      friend's Friends: %s" % " | ".join(texts))
	h.check(guest.button("Join") != null, "the friend can join the host's shared room")
	for key: String in Registry.keys():
		if key != h.RELAY: h.check(str(Registry.descriptor(key).title) not in texts, "the friend's Friends never names a chapter the room is not (%s)" % key)
	await h.step("guest leaves Friends", func(): h.back(guest))
	await h.finish()

## FriendsClient.same_room without a running client.
class FriendsClientShape:
	static func same(shared: Variant, room_id: String) -> bool:
		return shared is Dictionary and shared.get("room_id") == room_id and int(shared.get("api_version", 0)) == 2

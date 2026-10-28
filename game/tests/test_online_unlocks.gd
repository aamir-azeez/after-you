extends "res://tests/test_online_scenarios.gd"
## Chapter unlocks on two phones (services/chapter_unlocks.gd): a veteran
## invites a brand new player. A room for a chapter the new player has not
## reached is refused with a line that says what to ask for, holds nothing,
## and the two start together at First Steps.
const Unlocks = preload("res://services/chapter_unlocks.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const FIRST_STEPS := "first-steps@1"

func scenarios() -> Array[Callable]:
	return [_newcomer_and_veteran]

func suite_name() -> String:
	return "Online unlocks"

func _newcomer_and_veteran() -> void:
	await _begin("a new player and a veteran")
	h.server.chapters.assign([h.RELAY, FIRST_STEPS])
	# The guest is a new player: Main's own progress, with nothing finished.
	guest.app.real = true
	await h.step("host opens the hub", func(): h.open_hub(host))
	await h.step("guest opens the hub", func(): h.open_hub(guest))
	h.check(guest.hub() != null and guest.hub().selected_key() == FIRST_STEPS and not str(guest.hub().chapters[1].get("unlock_reason", "")).is_empty(), "the new player's hub offers First Steps and locks the Relay Isles")
	await h.step("host hosts the Relay Isles", func(): h.host_room(host))
	var relay_room: String = h.current_room(host)
	var relay_code: String = h.invitation(host)
	h.check(not relay_room.is_empty() and relay_code.begins_with("room-"), "the veteran hosts the Relay Isles")
	await h.step("guest tries the Relay Isles room", func(): h.join_room(guest, relay_code), [guest])
	var refusal := PlayerCopy.CHAPTER_JOIN_NOT_REACHED % Unlocks.title(FIRST_STEPS)
	h.check(h.current_room(guest).is_empty() and guest.hub() != null and guest.hub()._message == refusal, "the new player is refused and told to ask for First Steps (saw '%s')" % (guest.hub()._message if guest.hub() != null else ""))
	h.check(guest.app.relay_session == null or guest.app.relay_session.pending_lobby().is_empty(), "the refused join is not kept as a request to retry")
	h.check(guest.hub() != null and not guest.hub()._held_panel.visible, "the hub holds no other room behind it")
	h.check(h.current_room(host) == relay_room, "the veteran stays in their room")
	await h.step("host goes back", func(): h.back(host))
	await h.step("host hosts First Steps", _host_first_steps)
	var first_room: String = h.current_room(host)
	h.check(not first_room.is_empty() and first_room != relay_room, "the veteran hosts First Steps")
	await h.step("guest joins First Steps", func(): h.join_room(guest, h.invitation(host)))
	h.check(h.current_room(guest) == first_room, "the new player and the veteran play First Steps together")
	await h.finish()

func _host_first_steps() -> void:
	host.hub()._choose_chapter(FIRST_STEPS)
	h.press(host, "HostRoom")

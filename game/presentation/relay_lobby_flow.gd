extends Node
## The chapter (v2) room lobby: checking the chapter rooms before a room opens,
## the short progress card while a room is checked, created, joined or opened,
## the create, join, retry and open steps themselves, sharing a Friends room as
## soon as it exists, and joining by a chapter room code.
##
## Main hosts it as a child and keeps the room session (relay_session), the room
## screen (relay_child) and the step that swaps Main's screen for it
## (_enter_online_relay, which a finished step calls), and the way back to the
## hub (_return_to_room_hub, _settle_room_flow). The flow keeps the lobby's
## private staleness token (_menu_generation): a step that waited checks it,
## open_lobby() tells its caller whether its lobby is still current, and Main's
## return to the hub or an identity change cancels pending steps through
## cancel(). It reads Main only through this host contract (read at call time,
## so Main or a test can swap a service):
## - services: api, saves, relay_session, ensure_relay_session, room_sharing,
##   _friend_events
## - identity: _relay_identity, _ensure_identity
## - screen: mode, running, ui, application_backgrounded, store_view_generation,
##   lifecycle_generation, _online_gated, _toast
## - room flow: room_hub_flow (select_chapter, host_visibility),
##   legacy_room_flow (navigation_ready), _relay_available,
##   _prepare_ordinary_navigation, _friends_route_context,
##   _friends_route_current, _settle_room_flow, _return_to_room_hub,
##   _enter_online_relay
## - card kit: _card, _label, _paragraph, _back_button
## RoomHubFlow and FriendsFlow call open_lobby(), lobby_action() and join_room().
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ChapterRegistry = preload("res://services/chapter_registry.gd")
const CREAM := Color("eceddb")
## Main's mode while the progress card is up.
const MODE_LOBBY := "relay_rooms"

var host: Node
## Bumped by each lobby step and by cancel(); a step that waited stops when it moved.
var _menu_generation := 0

func _init(main: Node = null) -> void:
	host = main

## Pending lobby steps stop: the player went back to the hub or the identity changed.
func cancel() -> void:
	_menu_generation += 1

## Checks the chapter rooms and shows the progress card. True when this call's
## lobby is still the current one, so its caller may take the next step.
func open_lobby(chapter: String = "") -> bool:
	var start := _menu_generation
	await _check_rooms(chapter)
	return _menu_generation == start + 1 and host.mode == MODE_LOBBY and host.relay_session != null

func _check_rooms(chapter: String) -> void:
	if host._online_gated(): return
	if not chapter.is_empty():
		if ChapterRegistry.descriptor(chapter).is_empty():
			host._toast(PlayerCopy.MAIN_ED8E80825350)
			host._settle_room_flow()
			return
		host.room_hub_flow.select_chapter(chapter)
	var view: int = host.store_view_generation
	var lifecycle: int = host.lifecycle_generation
	if not host._relay_available() or not await host._ensure_identity() or view != host.store_view_generation or lifecycle != host.lifecycle_generation or host.application_backgrounded or not await host._prepare_ordinary_navigation():
		host._settle_room_flow()
		return
	host.ensure_relay_session()
	host.running = false
	_menu_generation += 1
	var generation := _menu_generation
	draw_progress(PlayerCopy.MAIN_07713E9CC81E)
	var context: Dictionary = host._friends_route_context()
	var loaded: bool = await host.relay_session.load_lobby()
	if generation != _menu_generation or not host._friends_route_current(context):
		return
	# The caller continues from this progress card; a failed check returns to the hub.
	if not loaded: host._return_to_room_hub(host.relay_session.last_error)

## The short wait while a room is checked, created, joined or opened. Back,
## Escape and Android Back return to the hub, as the old lobby's Back did.
func draw_progress(message: String) -> void:
	host.mode = MODE_LOBBY
	var card: VBoxContainer = host._card(minf(700.0,maxf(280.0,host.ui.size.x-48.0)))
	card.name = "RoomProgress"
	card.add_child(host._label("Play with a friend",34,CREAM,true))
	card.add_child(host._paragraph(message,minf(640.0,maxf(240.0,host.ui.size.x-88.0))))
	var back: Button = host._back_button("Back",host._return_to_room_hub,false)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.custom_minimum_size.x = 128
	card.add_child(back)

func lobby_action(action: String, value: String = "") -> void:
	if host.relay_session == null or host.relay_session.busy() or not host._relay_available() or not host._relay_identity().ready or not host.legacy_room_flow.navigation_ready() or not await host._prepare_ordinary_navigation():
		host._settle_room_flow()
		return
	_menu_generation += 1
	var generation := _menu_generation
	draw_progress(PlayerCopy.MAIN_6734074E99D4)
	var context: Dictionary = host._friends_route_context()
	# After a cold start the hub opens rooms before anything read the service's
	# chapters, and a room opened without them cannot save a turn.
	if host.relay_session.capabilities.is_empty():
		var loaded: bool = await host.relay_session.load_lobby()
		if generation != _menu_generation or not host._friends_route_current(context): return
		if not loaded:
			host._return_to_room_hub(host.relay_session.last_error)
			return
		# The list can drop the last room's proof. Checking it again here lets
		# this same tap go on, or releases a last room that is gone.
		var checked: bool = await host._prepare_ordinary_navigation()
		if generation != _menu_generation or not host._friends_route_current(context): return
		if not checked:
			host._settle_room_flow()
			return
	var room_id := ""
	match action:
		"create": room_id = await host.relay_session.create_room(value)
		"join": room_id = await host.relay_session.join_room(value)
		"retry": room_id = await host.relay_session.retry_lobby()
		"open":
			await host.relay_session.open_room(value)
			if host.relay_session.coordinator != null and host.relay_session.coordinator.snapshot().get("room_id", "") == value:
				room_id = value
	if generation != _menu_generation or not host._friends_route_current(context):
		return
	if room_id.is_empty():
		host._return_to_room_hub(host.relay_session.last_error)
		return
	var hosted := {"api_version":2,"room_id":room_id}
	var sharing: bool = bool(host.saves.data.settings.get("share_online_status", true))
	var hosting: bool = host.relay_session.coordinator != null and host.relay_session.coordinator.snapshot().get("host_id") == host.api.player_id
	if action in ["create", "retry"] and hosting and host.room_hub_flow.host_visibility == "friends" and sharing:
		# A Friends room is shared as soon as it exists and sends one hosting
		# alert. The alert is saved as owed first, so a restart keeps it.
		host._friend_events().owe(hosted)
		host.room_sharing.share.call_deferred(hosted)
	elif action == "open" and sharing and host._friend_events().owes(hosted):
		# Reopened before its alert went out (e.g. after a restart): finish it.
		host.room_sharing.share.call_deferred(hosted)
	host._enter_online_relay()

func join_room(code: String) -> void:
	if code.strip_edges().is_empty() or not host._relay_available() or not await host._ensure_identity():
		return
	if not host.legacy_room_flow.navigation_ready(): return
	# Both protocols use twenty hex characters, so the visible room-type choice
	# is authoritative. Never probe two mutating join endpoints with one code.
	if not await open_lobby():
		return
	await lobby_action("join",code)

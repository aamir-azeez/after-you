extends Node
## Friends (presentation/friends_screen.gd) and its glue: it builds the screen
## for the room this phone is in, and routes the screen's Leave, Host a room,
## Return to the current room and Join a friend's room.
##
## Main hosts it as a child and keeps the entry checks (_show_friends, which the
## room hub awaits inside its tap gate), the Friends and room event clients,
## friend_share_target, the room flows and room sharing. The flow keeps the
## screen and where its Back leads. It asks Main to navigate through the signals
## below, and reads Main only through this host contract (read at call time, so
## Main or a test can swap a service):
## - services: api, saves, relay_session, friend_nicknames, turn_notifications,
##   room_sharing, live_connection, _friends_client, _friend_events
## - identity: _relay_identity, _tester_context
## - screen: mode, running, ui, application_backgrounded, lifecycle_generation,
##   _sync_presence
## - room flow: active_room, friend_share_target, _friends_to_rooms,
##   legacy_room_flow (open_room, join_room), relay_lobby_flow (open_lobby,
##   lobby_action)
## - pop-up: notification_flow (friends_notice), which shows the screen's lines
## - names: display_name_flow (chip, flush, maybe_ask), for the header chip and
##   the first-run name prompt
## - node: add_child (the Friends layer stays Main's child)
## - leaderboards: ensure_relay_session, relay_session (capabilities), api
##   (player_id), _paid_content_hidden and saves (Reduce motion), for the page
##   opened over Friends; and for a run's replay,
##   presentation/shared_replay_launch.gd's host contract
## Main asks is_open() and drives the screen through close(), hosting_hint(),
## refresh() and confirm_invite_link(). refresh() calls the screen's private
## _refresh, as Main's alert routing did.
const FriendsScreen = preload("res://presentation/friends_screen.gd")
const LeaderboardScreen = preload("res://presentation/leaderboard_screen.gd")
const SharedReplayLaunch = preload("res://presentation/shared_replay_launch.gd")
const LeaderboardClient = preload("res://services/leaderboard_client.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
const Typed = preload("res://services/typed_values.gd")
## Main's mode while Friends is up.
const MODE_FRIENDS := "friends"

signal home_requested
signal rooms_requested
## Friends drew its hosting list.
signal hosting_view_ready(events: Array)

var host: Node
var screen: CanvasLayer
## A leaderboard run's replay this flow opened (_watch_replay), while it plays.
var _replay: Node3D
## Back from Friends goes Home when Friends opened from Home, else to the hub.
var _return_home := false

func _init(main: Node = null) -> void:
	host = main

## Builds Friends once Main's entry checks have passed and the hub has gone.
func open(from_home: bool) -> void:
	_return_home = from_home
	var client: RefCounted = host._friends_client(true)
	var events: RefCounted = host._friend_events()
	var shareable := {}
	var current := _current_room()
	var title := ""
	if current.get("api_version") == 2:
		var room: Dictionary = host.relay_session.coordinator.snapshot()
		title = RoomChapterTitle.for_room(room,"Current room")
		if room.get("host_id") == host.api.player_id: shareable = current.duplicate(true)
	elif current.get("api_version") == 1:
		title = RoomChapterTitle.legacy_title(host.active_room.get("level_id"),"Current room")
		if Typed.equal(host.active_room.get("host_id"), host.api.player_id): shareable = current.duplicate(true)
	host.running = false
	host.mode = MODE_FRIENDS
	host._sync_presence()
	host.ui.visible = false
	screen = FriendsScreen.new()
	screen.client = client
	screen.event_client = events
	screen.nickname_store = host.friend_nicknames
	screen.name_chip = host.display_name_flow.chip
	if not client.page_read.is_connected(_page_read): client.page_read.connect(_page_read)
	screen.notification_transport = host.turn_notifications
	screen.live = host.live_connection
	screen.hosting_view_ready.connect(hosting_view_ready.emit)
	screen.room_shared.connect(host.room_sharing.send_owed_alert)
	screen.notice.connect(host.notification_flow.friends_notice)
	screen.shareable_room = shareable
	screen.room_title = title
	screen.shared_room_title = _shared_room_title
	if not current.is_empty():
		var snapshot: Dictionary = host.relay_session.coordinator.snapshot() if current.get("api_version") == 2 else host.active_room
		screen.room_status = "Waiting for friend" if snapshot.get("guest_id") == null else "Friend joined"
	screen.openable_room = not current.is_empty()
	screen.closed.connect(_leave)
	screen.host_requested.connect(_host)
	screen.open_requested.connect(_return_to_room)
	screen.join_requested.connect(_join)
	screen.leaderboards_requested.connect(_open_leaderboards)
	host.add_child(screen)
	_offer_leaderboards(screen)

## Shows Friends' Leaderboards button once the server's capabilities say they
## are open, reading them first when this session has not yet.
func _offer_leaderboards(page: CanvasLayer) -> void:
	host.ensure_relay_session()
	var session: RefCounted = host.relay_session
	if session.capabilities.is_empty(): await session.load_capabilities()
	if not is_instance_valid(page) or page != screen: return
	page.show_leaderboards(session.leaderboards_supported())
	# The name choice as the server keeps it, so Settings shows it right after a reinstall.
	if session.leaderboards_supported(): LeaderboardClient.shared(host.api, str(host.api.player_id)).sync()

## Leaderboards, over Friends.
func _open_leaderboards() -> void:
	open_leaderboards("")

## Leaderboards over Friends, open on `chapter_key` ("" for the first chapter):
## Friends' button, or a celebration's View board from Home.
func open_leaderboards(chapter_key: String) -> void:
	if not is_open() or host.application_backgrounded: return
	var board := LeaderboardScreen.new()
	board.chapter_key = chapter_key
	board.reduced_motion = bool(host.saves.data.settings.get("reduced_motion", false))
	board.duels_on = host.relay_session != null and host.relay_session.duels_supported()
	board.client = LeaderboardClient.shared(host.api, str(host.api.player_id))
	board.player_id = str(host.api.player_id)
	board.chapter_filter = func(key: String) -> bool: return not (host._paid_content_hidden() and bool(Registry.descriptor(key).get("premium", false)))
	board.notice.connect(host.notification_flow.friends_notice)
	board.watch_requested.connect(func(parts: Array, chapter_key: String) -> void: _watch_replay(board, parts, chapter_key))
	screen.open_overlay(board)

## A leaderboard run's replay in the shared replay viewer, full screen as Replays
## plays one (presentation/shared_replay_launch.gd). Friends and the board hide
## meanwhile; leaving shows them again, and closing Friends closes it too.
func _watch_replay(board: CanvasLayer, parts: Array, chapter_key: String) -> void:
	if not is_open() or host.application_backgrounded or is_instance_valid(host.shared_replay_child) or parts.is_empty():
		board.replay_closed()
		return
	_replay = SharedReplayLaunch.make(host, parts)
	_replay.leaderboard_chapter = chapter_key
	_replay.closed.connect(func() -> void: _leave_replay(board))
	screen.visible = false
	SharedReplayLaunch.show(host, _replay)

func _leave_replay(board: CanvasLayer) -> void:
	if not is_instance_valid(_replay) or host.shared_replay_child != _replay: return
	_replay = null
	SharedReplayLaunch.close(host)
	if is_open(): screen.visible = true
	if is_instance_valid(board): board.replay_closed()

## A friends list read while Friends is up: display names may have just come
## on (the chip appears and the first-run prompt opens once), and a name
## waiting to be sent goes.
func _page_read() -> void:
	host.display_name_flow.flush()
	if not is_open(): return
	screen.show_name_chip()
	host.display_name_flow.maybe_ask(screen.page_root())

## Whether Friends is up.
func is_open() -> bool:
	return is_instance_valid(screen)

## Closes Friends for a screen Main shows instead. Main sets its mode first, so
## the screen's close does not navigate.
func close() -> void:
	if not is_instance_valid(screen): return
	# A run's replay opened from Friends goes with it (an account change, a room opening).
	if is_instance_valid(_replay) and host.shared_replay_child == _replay:
		_replay = null
		SharedReplayLaunch.close(host)
	var friends := screen
	screen = null
	friends.close()

## A hosting alert arrived while Friends is up: it reads its inbox now.
func hosting_hint() -> void:
	screen.hosting_hint()

## Reads the open Friends list again.
func refresh() -> void:
	await screen._refresh()

## An invite link names a friend: Friends asks before it sends the request.
func confirm_invite_link(friend: String) -> void:
	screen.confirm_invite_link(friend)

## The chapter of a room shared with friends, from that room's own record on
## this phone; "" when the phone does not have it.
func _shared_room_title(room: Dictionary) -> String:
	var room_id := str(room.get("room_id",""))
	if room.get("api_version") == 2 and host.relay_session != null:
		return RoomChapterTitle.title(host.relay_session.room_chapter(room_id),"")
	if room.get("api_version") == 1:
		for saved: Variant in [host.active_room,host.saves.data.get("room",{})]:
			if saved is Dictionary and Typed.equal(saved.get("room_id"), room_id): return RoomChapterTitle.legacy_title(saved.get("level_id"),"")
	return ""

## The room Friends offers to return to: friend_share_target, while this player
## is still in it on this phone.
func _current_room() -> Dictionary:
	if not host._relay_identity().ready: return {}
	var room := {}
	var target: Dictionary = host.friend_share_target
	if target.get("api_version") == 2 and host.relay_session != null and host.relay_session.coordinator != null:
		room = host.relay_session.coordinator.snapshot()
	elif target.get("api_version") == 1:
		room = host.active_room
	if room.get("room_id") != target.get("room_id") or host.api.player_id not in [room.get("host_id"),room.get("guest_id")]: return {}
	return target.duplicate(true)

func _host() -> void:
	if host.mode != MODE_FRIENDS or host.application_backgrounded or not host._relay_identity().ready: return
	host._friends_to_rooms()
	rooms_requested.emit()

func _return_to_room() -> void:
	if host.mode != MODE_FRIENDS or host.application_backgrounded: return
	var target := _current_room()
	if target.is_empty(): return
	host._friends_to_rooms()
	if target.api_version == 2: host.relay_lobby_flow.lobby_action("open",target.room_id)
	else: host.legacy_room_flow.open_room(target.room_id)

func _leave() -> void:
	screen = null
	if host.mode == MODE_FRIENDS:
		host.ui.visible = true
		if _return_home: home_requested.emit()
		else: rooms_requested.emit()

func _join(descriptor: Dictionary) -> void:
	if host.mode != MODE_FRIENDS or host.application_backgrounded or not host._relay_identity().ready: return
	# The screen closes after emitting. Set the destination first so its close
	# callback cannot replace a successful room join with the rooms menu.
	host._friends_to_rooms()
	if descriptor.get("api_version") == 2:
		var room_id := str(descriptor.get("room_id",""))
		if host.relay_session != null and (room_id in host.relay_session.room_ids() or (host.relay_session.coordinator != null and host.relay_session.coordinator.snapshot().get("room_id") == room_id)):
			host.relay_lobby_flow.lobby_action("open",room_id)
		else:
			var identity: String = host._tester_context()
			# The lobby's own check carries the join over a pause and resume.
			var current: bool = await host.relay_lobby_flow.open_lobby()
			if not current or host.application_backgrounded or identity != host._tester_context(): return
			if room_id in host.relay_session.room_ids(): host.relay_lobby_flow.lobby_action("open",room_id)
			else: host.relay_lobby_flow.lobby_action("join",str(descriptor.get("invite_code","")))
	elif descriptor.get("api_version") == 1:
		var room_id := str(descriptor.get("room_id",""))
		var saved: Dictionary = host.saves.data.get("room",{})
		if Typed.equal(saved.get("room_id"), room_id) and host.api.player_id in [saved.get("host_id"),saved.get("guest_id")]: host.legacy_room_flow.open_room(room_id)
		else: host.legacy_room_flow.join_room(str(descriptor.get("invite_code","")))

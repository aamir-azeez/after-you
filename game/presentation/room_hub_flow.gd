extends Node
## Play with a friend: the room hub (presentation/room_hub_screen.gd) and its
## glue. It opens and rebuilds the hub, lists Your rooms from the room inbox,
## this session's rooms and saved replays, removes and retries rooms, and routes
## the hub's Open, Host, Join and Friends taps, and Home's Play with your friend,
## through one busy-tap gate.
##
## Main hosts it as a child and keeps the room session, Friends and the relay
## lobby; the legacy room is LegacyRoomFlow's. The flow keeps the hub's own state: the screen, its
## inbox, and the chapter and visibility last chosen. It asks Main to navigate
## through the signals below, and reads Main only through this host contract
## (read at call time, so Main or a test can swap a service):
## - services: api, relay_session, shared_replays, tester_access, live_connection (read once, in _ready)
## - identity and access: _relay_identity, _ensure_identity, _tester_context,
##   _tester_checks_enabled, _load_cached_tester, _hosting_lock_reason,
##   _paid_content_hidden, _online_gated, _friend_display_name, _chapter_marks,
##   _chapter_unlocks
## Main's chapter unlocks read known_rooms(), from the same room list client
## the hub draws (rooms_client()).
## - screen: mode, running, ui, overlay, store_view_generation, lifecycle_generation,
##   application_backgrounded, _toast
## - room flow: active_room, _relay_available,
##   _return_to_room_hub, _settle_room_flow, _online_flow_idle,
##   _room_session_idle, _prepare_ordinary_navigation, _friends_route_context,
##   _friends_route_current, _show_friends, forget_removed_room,
##   legacy_room_flow (open_room, join_room), relay_lobby_flow (open_lobby,
##   lobby_action, join_room)
## - card kit: _card, _label, _paragraph, _list_button, _back_button
## - names and friends: display_name_flow (maybe_ask, the first-run name prompt),
##   partner_friends (Add friend on a finished room's menu)
## - node: add_child (the hub layer stays Main's child)
## Main asks is_open() and drives the hub through go_back(), redraw_chapters()
## and refresh(). It calls release() when another screen replaces the hub, and
## drop() when Friends takes over or the identity changes. After a block it
## calls hide_room() so the hub's saved list never shows the blocked room.
## RelayLobbyFlow calls select_chapter() when a chapter's rooms are checked.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const BusyTapGate = preload("res://presentation/busy_tap_gate.gd")
const ChapterPicker = preload("res://presentation/chapter_picker.gd")
const LegacyRoomFlow = preload("res://presentation/legacy_room_flow.gd")
const RelayLobbyFlow = preload("res://presentation/relay_lobby_flow.gd")
const RoomHubScreen = preload("res://presentation/room_hub_screen.gd")
const ChapterRegistry = preload("res://services/chapter_registry.gd")
const ChapterUnlocks = preload("res://services/chapter_unlocks.gd")
const ChapterThumbnailCatalog = preload("res://services/chapter_thumbnail_catalog.gd")
const RoomInboxClient = preload("res://services/room_inbox_client.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const RoomLeaveSupport = preload("res://services/room_leave_support.gd")
const ShareCodes = preload("res://services/share_codes.gd")
const SharedReplays = preload("res://services/shared_replay_collection.gd")
const Purchases = preload("res://services/purchases.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const PartnerFriends = preload("res://services/partner_friends.gd")
const Typed = preload("res://services/typed_values.gd")
const CREAM := Color("eceddb")
## Main's mode while the hub (or its no-service card) is up.
const MODE_ROOMS := "rooms"
const RefreshClock = preload("res://services/refresh_schedule.gd")
## The hub has no timer of its own: its hint-driven reads never come due by time.
const LIVE_ONLY_INTERVAL_MS := 86400000

signal home_requested
signal journey_requested
signal hosting_locked_requested(chapter_key: String)
signal tester_access_requested
signal shared_replay_requested(room_id: String)

var host: Node
## The chapter last chosen or hosted in Play with a friend. Every rebuilt hub
## starts from it, so leaving for Friends or a room keeps the choice; First
## Steps is only the default before the first choice.
var selected_chapter := ChapterRegistry.FIRST_STEPS
var host_visibility := "friends"
## The host panel's Hard chip as last chosen (services/hard_mode.gd).
var host_hard := false
var screen: CanvasLayer
var inbox: RefCounted
## The hub's taps (Continue, Open, Host, Join, Friends) go through one busy-tap
## gate (presentation/busy_tap_gate.gd): a tap made while earlier work its flow
## would refuse during is still running waits, with the tapped control saying
## so; a later tap replaces it; it runs only while this hub is still up.
## Requests themselves wait their turn in the API's request queue.
var _gate: BusyTapGate
var _tap_room := ""
## Whether the server offers Leave room, read only once the list shows a
## confirmed finished room. A failed leave forgets it.
var leave_support := RoomLeaveSupport.new()

## The room list client the hub and the chapter unlocks share (rooms_client()),
## and the API it was made for.
var _client: RefCounted
var _client_api: Node

## Hint-driven reads of the open hub's rooms (services/refresh_schedule.gd):
## one at a time, one more for hints that arrive while a read is out.
var _live_reads := RefreshClock.new()

func _init(main: Node = null) -> void:
	host = main

## A room changed (a turn, a join, a close), or the socket came back after
## dropping (LiveConnection.missed_hints): the open hub reads its rooms once.
func _ready() -> void:
	var live: Node = host.get("live_connection") if host != null else null
	if not is_instance_valid(live): return
	live.room_changed.connect(func(_room: String, _seq: int) -> void: _live_hint())
	live.missed_hints.connect(_live_caught_up)

func _live_hint() -> void:
	if is_open(): _live_reads.hint(Time.get_ticks_msec())

## Hints were missed since `since_ms` (the socket dropped, or the app was paused): one catch-up read.
func _live_caught_up(since_ms: int) -> void:
	if is_open(): _live_reads.hint(Time.get_ticks_msec(), since_ms)

func _process(_delta: float) -> void:
	if not is_open():
		_live_reads.bind("", 0)
		return
	var now := Time.get_ticks_msec()
	_live_reads.bind(str(screen.get_instance_id()), now, LIVE_ONLY_INTERVAL_MS)
	var ticket: Dictionary = _live_reads.begin_if_due(now, host.mode == MODE_ROOMS and not screen.refreshing(), false)
	if ticket.is_empty(): return
	var hub := screen
	await refresh_when_idle(hub)
	_live_reads.complete(ticket, Time.get_ticks_msec(), true)

func show_rooms() -> void:
	if host._online_gated(): return
	if not host.api.configured():
		host.running=false
		host.mode=MODE_ROOMS
		var frame: VBoxContainer = host._card(700)
		frame.add_child(host._label(PlayerCopy.MAIN_3A4A78824AC3,34,CREAM,true))
		frame.add_child(host._paragraph(PlayerCopy.MAIN_C372E9DBD93A))
		frame.add_child(host._list_button("Practice on your own",func(): journey_requested.emit()))
		frame.add_child(host._back_button("Back",func(): home_requested.emit(),false))
		return
	if is_instance_valid(screen): return
	var view: int = host.store_view_generation
	var lifecycle: int = host.lifecycle_generation
	if not host._relay_available() or not await host._ensure_identity(): return
	if view != host.store_view_generation or lifecycle != host.lifecycle_generation or host.application_backgrounded: return
	# A note from the check stays on the hub's own notice.
	var report := {"text": ""}
	if not await host._prepare_ordinary_navigation(func(text: String) -> void: report.text = text):
		if not report.text.is_empty(): host._toast(report.text)
		return
	open_hub(report.text)

## Home's Play with your friend (`source` is its button). The room session can
## still be busy with work that outlives its screen, such as a finished room's
## replay save after Watch replay or after that room's play; show_rooms cannot
## check the last room until it ends. The tap waits for it in the busy-tap gate,
## the button reading "Opening…", then opens the hub; a wait that runs out says why.
func open_from_home(source: Control) -> void:
	if _gate == null or _gate.area() != host.overlay: _gate = BusyTapGate.new(host.overlay)
	await _gate.tap(source, PlayerCopy.HUB_OPENING,
		func() -> bool: return host.relay_session == null or not host.relay_session.busy(),
		show_rooms,
		func() -> bool: return host.mode == "home",
		func() -> void: host._toast(PlayerCopy.ROOMS_API_DA75E6F7A674))
	# The first time with names on, the name prompt opens over the room list.
	if is_instance_valid(screen): host.display_name_flow.maybe_ask(screen.page_root(), true)

## Builds the hub without the entry checks of show_rooms; every room flow
## returns here. A notice, such as why a room could not be opened, shows above
## the room list.
func open_hub(notice: String = "", refresh: bool = true) -> void:
	if is_instance_valid(screen):
		screen.show_notice(notice)
		return
	host.running=false
	host.mode=MODE_ROOMS
	host.ui.visible=false
	inbox = rooms_client()
	screen = RoomHubScreen.new()
	screen.client = inbox
	screen.restore_choice(selected_chapter,host_visibility)
	screen.set_chapters(together_chapters())
	screen.completion_marks = host._chapter_marks()
	screen.display_name = _member_name
	screen.partner_friend = _partner_friend
	screen.add_friend_requested.connect(_add_partner_friend)
	screen.thumbnail_for = func(key: String) -> String: return ChapterThumbnailCatalog.path(key)
	screen.closed.connect(close)
	screen.friends_requested.connect(_open_friends)
	screen.chapter_picked.connect(func(key: String): selected_chapter = key)
	screen.visibility_picked.connect(func(value: String): host_visibility = value)
	screen.hard_picked.connect(func(on: bool): host_hard = on)
	screen.room_open_requested.connect(_open_room)
	screen.cards_redrawn.connect(_follow_tap)
	screen.host_requested.connect(_host_room)
	screen.tester_code_requested.connect(_open_tester_code)
	screen.join_code_requested.connect(_join)
	screen.retry_requested.connect(_retry)
	screen.room_remove_requested.connect(_remove_room)
	screen.room_show_requested.connect(_show_room)
	screen.set_held_request(_held_room_request())
	screen.set_leave_finished(_leave_offered())
	host.add_child(screen)
	screen.show_notice(notice)
	_offer_hard(screen)
	_refresh_together_locks(screen)
	if refresh: refresh_when_idle(screen)

## The chapter a hosted or checked room is for becomes the hub's choice.
func select_chapter(chapter_key: String) -> void:
	selected_chapter = chapter_key

## Whether the hub is up.
func is_open() -> bool:
	return is_instance_valid(screen)

## Android Back or Escape while the hub is up: the hub's own Back.
func go_back() -> void:
	screen.go_back()

## Draws the chapter cards again, for a change in hosting access.
func redraw_chapters() -> void:
	screen.set_chapters(together_chapters())

## Reads the open hub's rooms again once earlier requests are done.
func refresh() -> void:
	await refresh_when_idle(screen)

## The hub is a layer above the overlay; any other screen replaces it, or the
## hub would cover that screen and take its taps.
func release() -> void:
	if not is_instance_valid(screen): return
	screen.queue_free()
	screen = null
	inbox = null
	host.ui.visible = true

## Frees the hub and leaves Main's ui as it is: Friends draws its own layer, and
## an identity change settles the screens itself.
func drop() -> void:
	if is_instance_valid(screen):
		screen.queue_free()
		screen = null
		inbox = null

## The hub gives way to the screen a tap leads to. Opening a room passes
## keep_inbox and leaves the inbox set, as it always has.
func _leave(keep_inbox: bool = false) -> void:
	if is_instance_valid(screen): screen.queue_free()
	screen = null
	if not keep_inbox: inbox = null
	host.ui.visible = true

## Takes a room off this device's saved hub list, as Remove from list does,
## whether or not the hub is up. New activity in the room brings it back.
func hide_room(version: int, room_id: String) -> void:
	var client: RefCounted = inbox if inbox != null else rooms_client()
	for room: Dictionary in client.view().rooms:
		if int(room.get("api_version",0)) == version and str(room.get("room_id","")) == room_id: client.hide(room)

## The hub can open before the saved tester code is read; once it is, the
## hosting locks are drawn again so a tester never keeps a stale lock.
## The host panel's Hard chip: shown only once the server says it hosts hard
## rooms, as the relay session or the hub's own capabilities read
## (services/room_leave_support.gd) last heard.
func _offer_hard(hub: Node) -> void:
	if not is_instance_valid(hub): return
	var session: RefCounted = host.relay_session
	var hosted: bool = (session != null and session.hard_mode_supported()) or leave_support.hard_offered(host._tester_context())
	hub.set_hard(hosted, host.hard_states(hosted), host_hard)

func _refresh_together_locks(hub: Node) -> void:
	if not host._tester_checks_enabled() or (is_instance_valid(host.tester_access) and host.tester_access.cache_checked_context == host._tester_context()): return
	await host._load_cached_tester()
	if is_instance_valid(hub) and hub == screen and host.mode == MODE_ROOMS: hub.set_chapters(together_chapters())

func refresh_when_idle(hub: CanvasLayer) -> void:
	# The hub's read takes its turn after a room save or replay delivery still
	# out, and keeps its saved list meanwhile.
	if not is_instance_valid(hub) or hub != screen: return
	await hub.refresh()
	if is_instance_valid(hub) and hub == screen: hub.set_held_request(_held_room_request())
	# One capabilities read per identity: for Leave room on a finished room,
	# and for the Hard chip.
	var identity: String = host._tester_context()
	if not _lists_finished_room() and leave_support.known(identity): return
	await leave_support.read(host.api, identity, func() -> bool: return identity == host._tester_context())
	if is_instance_valid(hub) and hub == screen:
		hub.set_leave_finished(_leave_offered())
		_offer_hard(hub)

## Only a list with a confirmed finished server room needs to know about Leave room.
func _lists_finished_room() -> bool:
	if inbox == null: return false
	for room: Dictionary in inbox.view().get("rooms",[]):
		if room.get("status") == "completed" and int(room.get("api_version",0)) in [1,2] and inbox.confirmed(room): return true
	return false

func _leave_offered() -> bool:
	return leave_support.offered(host._tester_context())

## After the hub's confirm step: "close" ends a room still in play for both
## members (DELETE), "leave" drops a room the other member closed,
## "leave_finished" leaves a finished room (the server erases this player's
## photos and reactions there and the friend keeps the room), and "hide" takes
## a finished room off this device's list without a request. The other
## member's inbox then shows a closed room as closed.
func _remove_room(room: Dictionary, action: String) -> void:
	var version := int(room.get("api_version",0))
	var room_id := str(room.get("room_id",""))
	if host.mode != MODE_ROOMS or not is_instance_valid(screen) or inbox == null or not host._relay_identity().ready or room_id.is_empty(): return
	var hub := screen
	var client: RefCounted = inbox
	if action == "hide":
		client.hide(room)
		hub.show_notice("")
		return
	if version not in [1,2]: return
	var identity: String = host._tester_context()
	var path := "/v%d/rooms/%s" % [version,room_id]
	hub.set_removing(true)
	var response: Dictionary
	if action == "close":
		response = await host.api.request_json(HTTPClient.METHOD_DELETE,path)
		# Already closed by the other member: the room is gone, so only the link remains.
		if not response.get("ok",false) and str(response.get("code","")) == "room_not_found" and identity == host._tester_context():
			response = await host.api.request_json(HTTPClient.METHOD_POST,path+"/leave",{"schema_version":1})
	elif action == "leave_finished":
		response = await host.api.request_json(HTTPClient.METHOD_POST,path+"/leave",{"schema_version":1,"leave_finished":true})
		if not response.get("ok",false):
			leave_support.forget()
			response["error"] = PlayerCopy.ROOM_LEAVE_IN_PLAY if str(response.get("code","")) == "room_not_closed" else PlayerCopy.ROOM_LEAVE_FAILED if int(response.get("status",0)) == 0 else PlayerCopy.ROOM_LEAVE_UNAVAILABLE
	else:
		response = await host.api.request_json(HTTPClient.METHOD_POST,path+"/leave",{"schema_version":1})
	# The server has acted even if the player has moved on; keep this device in step.
	if response.get("ok",false) and identity == host._tester_context():
		client.forget(version,room_id)
		host.forget_removed_room(version,room_id)
	if not is_instance_valid(hub) or hub != screen: return
	hub.set_removing(false)
	if response.get("ok",false): hub.show_notice("")
	else:
		hub.show_notice(str(response.get("error",PlayerCopy.ROOMS_API_1C556A121773)))
		refresh_when_idle(hub)

## Show again on a hidden room: it returns to the list on this device.
func _show_room(room: Dictionary) -> void:
	if host.mode != MODE_ROOMS or not is_instance_valid(screen) or inbox == null: return
	inbox.show_again(room)
	screen.show_notice("")

## A create or join request saved before its reply arrived, or a room with an
## unfinished redo request. Either blocks other rooms until it is retried.
func _held_room_request() -> String:
	if host.relay_session == null: return ""
	if not host.relay_session.pending_lobby().is_empty(): return "lobby"
	return "redo" if not host.relay_session.pending_redo_room().is_empty() else ""

func _retry(kind: String) -> void:
	if host.mode != MODE_ROOMS or host.relay_session == null or not host._relay_identity().ready: return
	var pending_redo: String = host.relay_session.pending_redo_room()
	_leave()
	# A retry needs the service's chapters, which a fresh start has not read yet.
	if not await host.relay_lobby_flow.open_lobby(): return
	if kind == "lobby": await host.relay_lobby_flow.lobby_action("retry")
	elif not pending_redo.is_empty(): await host.relay_lobby_flow.lobby_action("open",pending_redo)
	else: host._return_to_room_hub()

## The room list client: one for the flow, kept while the API in use is the
## same, so the hub and the chapter unlocks read one saved list and never
## parse it again per draw. It binds to the identity in use on each read.
func rooms_client() -> RefCounted:
	if _client == null or _client_api != host.api:
		_client = RoomInboxClient.new(host.api,host._relay_identity)
		_client.local = _local_history
		# Saved replays name rooms the server can no longer read; the hub
		# loads them, the chapter unlocks read only what is loaded.
		_client.finished = func() -> Array: return _saved_replay_rooms(is_open())
		_client_api = host.api
	return _client

## Every room this phone knows, as chapter keys, for the chapter unlocks
## (services/chapter_unlocks.gd): {"chapters": every room's, "finished":
## rooms finished on the server's word (the room list's own "completed") or
## the online session's (its last turn played)}. A room known from a saved
## replay counts as known only: that list holds waiting rooms and rooms in
## play too, and the hub's list names a placeholder row from it.
func known_rooms() -> Dictionary:
	var client := rooms_client()
	var chapters: Array = []
	var finished: Array = []
	for room: Dictionary in client.view().get("rooms", []): chapters.append(str(room.get("chapter_key", "")))
	for room: Dictionary in client.listed():
		if room.get("status") == "completed" and not RoomInboxClient.unresolved(room): finished.append(str(room.chapter_key))
	for room: Dictionary in _local_history():
		chapters.append(str(room.chapter_key))
		if room.status == "completed": finished.append(str(room.chapter_key))
	for room: Dictionary in _saved_replay_rooms(false): chapters.append(str(room.chapter_key))
	return {"chapters": chapters, "finished": finished}

## Chapter picker entries for Play with a friend. The hub lists offered chapters
## and hosts through hosting_key; once the server's chapters are known, a
## chapter it cannot create at any version is tagged unavailable online.
## Locks follow hosting access, which a Test Store purchase alone does not give.
## A build that sells nothing lists only the free chapters to host; joining a
## friend's room by code is unchanged. A chapter the chain has not reached
## (services/chapter_unlocks.gd) is locked with its reason ("unlock_reason"),
## ahead of any hosting lock: it cannot be chosen until it opens.
func together_chapters() -> Array[Dictionary]:
	var reason: String = host._hosting_lock_reason()
	var free_only: bool = host._paid_content_hidden()
	var known: bool = host.relay_session != null and not host.relay_session.capabilities.is_empty()
	var unlocks: Dictionary = host._chapter_unlocks()
	var result: Array[Dictionary] = []
	for offered: String in ChapterRegistry.offered_keys():
		var item := ChapterPicker.entry(offered)
		if free_only and item.premium: continue
		var tag := ""
		if known and not host.relay_session.supports_creation(ChapterRegistry.hosting_key(offered,host.relay_session.supports_creation)): tag = " · unavailable online"
		item.locked = item.premium and not reason.is_empty()
		item.tag = tag
		if not ChapterUnlocks.lock_entry(item, unlocks) and item.locked:
			item.lock_reason = reason
			# Owned through the Test Store: the card says the code is what is missing.
			if reason == Purchases.HOSTING_NEEDS_TESTER_CODE: item.note = PlayerCopy.HOSTING_NEEDS_TESTER_CODE
		result.append(item)
	return result

func _local_history() -> Array:
	# Hosted and joined rooms the player already reached this session, mapped
	# into the inbox room shape so the hub lists them even while the inbox
	# endpoint is unavailable. Turn state is unknown without the inbox, so a
	# live room is shown as openable without claiming it is the player's turn.
	var rooms: Array = []
	if host.relay_session == null or not host._relay_identity().ready: return rooms
	var me := str(host.api.player_id)
	for summary: Dictionary in host.relay_session.room_summaries():
		var role := str(summary.get("active_role",""))
		rooms.append({
			"api_version": 2,
			"room_id": str(summary.get("room_id","")),
			"chapter_key": _history_chapter(summary),
			"chapter_title": str(summary.get("title","Saved chapter")),
			"member_ids": [me],
			"status": "completed" if role == "complete" else "waiting_for_their_turn",
			"revision": 0,
			"remote_activity_sequence": 0,
			"activity_at": 0,
			"family": "relay",
		})
	return rooms

## Rooms whose replay this phone saved, in the inbox room shape. Once both
## players save a finished room's replay the server keeps only a compact record,
## so this names such a room when the inbox cannot. `make` makes the saved
## replays' collection when Main has none yet.
func _saved_replay_rooms(make: bool = true) -> Array:
	var rooms: Array = []
	if not host._relay_identity().ready: return rooms
	if host.shared_replays == null and not make: return rooms
	if host.shared_replays == null: host.shared_replays = SharedReplays.new(host.api,host._relay_identity)
	for room: Dictionary in host.shared_replays.rooms():
		if room.get("family") != "chapter": continue
		var members: Array[String] = []
		for member: Variant in [room.get("host_id"),room.get("guest_id")]:
			if member is String: members.append(member)
		rooms.append({
			"api_version": 2,
			"room_id": str(room.get("room_id","")),
			"chapter_key": str(room.get("chapter_key","")),
			"chapter_title": str(room.get("title","")),
			"member_ids": members,
			"status": "completed",
			"revision": 0,
			"remote_activity_sequence": 0,
			"activity_at": 0,
			"family": "relay",
		})
	return rooms

func _history_chapter(summary: Dictionary) -> String:
	# Two versions of a chapter share a title, so match the room's own key.
	var key: String = host.relay_session.room_chapter(str(summary.get("room_id","")))
	return key if not key.is_empty() else "unknown"

## A Your rooms card's member line: the friend's name opens the line, and the
## player is left out.
## Whether a finished room's menu offers to add its partner as a friend
## (services/partner_friends.gd, Main's partner_friends): {"state", "partner"}.
func _partner_friend(room: Dictionary) -> Dictionary:
	var partner := ""
	for member: Variant in room.get("member_ids", []):
		if str(member) != str(host.api.player_id): partner = str(member)
	var family := str(room.get("family", ""))
	return {"state": host.partner_friends.state(partner, family if family in ["legacy", "relay"] else "", str(room.get("room_id", ""))), "partner": partner}

## Add friend from a finished room's menu: the ordinary friend request.
func _add_partner_friend(room: Dictionary, partner: String) -> void:
	if _partner_friend(room).get("state") != PartnerFriends.ADDABLE: return
	var line := PlayerCopy.add_friend_sent(host._friend_display_name(partner))
	host._toast(line if await host.partner_friends.send(partner) else PlayerCopy.ROOM_ADD_FRIEND_FAILED)

func _member_name(member: String) -> String:
	if member == str(host.api.player_id): return ""
	return FriendNicknames.sentence_start(host._friend_display_name(member))

func close() -> void:
	_leave()
	home_requested.emit()

func _open_friends(source: Control = null) -> void:
	if host.mode != MODE_ROOMS: return
	# The hub stays up until Friends opens (_show_friends drops it then), so
	# a refused open reports its reason on the hub.
	await _tap(source, PlayerCopy.HUB_OPENING, host._online_flow_idle, PlayerCopy.HUB_FRIENDS_WAIT_EXPIRED, host._show_friends.bind(message))

func _tap(source: Control, label: String, ready: Callable, expired: String, run: Callable, room_id: String = "") -> void:
	_tap_room = room_id
	var hub := screen
	if not is_instance_valid(hub):
		await run.call() # No hub: nothing on screen to label or wait for.
		return
	# A new tap clears the last one's reason.
	hub.show_notice("")
	if _gate == null or _gate.area() != hub: _gate = BusyTapGate.new(hub)
	await _gate.tap(source, label, ready, run,
		func() -> bool: return host.mode == MODE_ROOMS and is_instance_valid(hub) and hub == screen,
		func() -> void: message(expired))

## A refresh that rebuilt the room cards while a room's tap waits: the new card's button carries its label.
func _follow_tap() -> void:
	if _gate != null and _gate.waiting() and not _tap_room.is_empty() and is_instance_valid(screen):
		_gate.follow(screen.room_action(_tap_room))

## A reason the hub tap stopped, on the hub when it is up, or on Home's toast
## after the room flow settles back to the hub.
func message(text: String) -> void:
	if host.mode == MODE_ROOMS and is_instance_valid(screen):
		screen.show_notice(text)
		return
	if not text.is_empty(): host._toast(text)
	host._settle_room_flow()

func _open_room(room: Dictionary, source: Control = null) -> void:
	if host.mode != MODE_ROOMS or not host._relay_identity().ready: return
	var version := int(room.get("api_version",0))
	var room_id := str(room.get("room_id",""))
	if room_id.is_empty(): return
	# Watch replay on a finished room opens the Together page at once; it handles
	# a save still in progress itself. A room in play waits for its flow.
	var waits_for: Callable = Callable() if room.get("status") == "completed" else host._room_session_idle if version == 2 else host._online_flow_idle
	await _tap(source, PlayerCopy.HUB_OPENING_ROOM, waits_for, PlayerCopy.MAIN_8184DEB41266, _open_room_now.bind(room), room_id)

func _open_room_now(room: Dictionary) -> void:
	var version := int(room.get("api_version",0))
	var room_id := str(room.get("room_id",""))
	var client: RefCounted = inbox
	_leave(true)
	if room.get("status") == "completed":
		# Completed rooms open their exact shared replay, which also counts as
		# seeing the room's latest activity.
		if client != null: client.confirm_room_rendered(version,room_id)
		shared_replay_requested.emit(room_id)
		return
	if version == 2:
		await host.relay_lobby_flow.lobby_action("open",room_id)
		if host.mode == "relay_online" and host.relay_session != null and host.relay_session.coordinator != null and host.relay_session.coordinator.snapshot().get("room_id") == room_id:
			if client != null: client.confirm_room_rendered(2,room_id)
	elif version == 1:
		await host.legacy_room_flow.open_room(room_id)
		if host.mode == LegacyRoomFlow.MODE_ROOM and Typed.equal(host.active_room.get("room_id"), room_id):
			if client != null: client.confirm_room_rendered(1,room_id)
		else: host._settle_room_flow()
	else:
		host._return_to_room_hub("This room can't be opened on this version of After You.")

func _host_room(chapter_key: String, visibility: String, source: Control = null) -> void:
	if host.mode != MODE_ROOMS or not host._relay_identity().ready: return
	var unlocks: Dictionary = host._chapter_unlocks()
	if not ChapterUnlocks.reached(chapter_key, unlocks):
		message(ChapterUnlocks.reason(chapter_key, unlocks))
		return
	var reason: String = host._hosting_lock_reason()
	if ChapterRegistry.descriptor(chapter_key).get("premium",false) and not reason.is_empty():
		if reason == Purchases.HOSTING_NEEDS_TESTER_CODE:
			_open_tester_code()
			return
		# Hosting a paid island needs the Full Journey; show how to unlock it
		# before entering the lobby. Never auto-create a room afterwards.
		_leave()
		hosting_locked_requested.emit(chapter_key)
		return
	selected_chapter = chapter_key
	host_visibility = visibility
	var hard: bool = is_instance_valid(screen) and screen.hard_selected()
	await _tap(source, PlayerCopy.HUB_OPENING_ROOM, host._room_session_idle, PlayerCopy.MAIN_8184DEB41266, _host_room_now.bind(chapter_key, hard))

func _host_room_now(chapter_key: String, hard: bool = false) -> void:
	_leave()
	await host.relay_lobby_flow.open_lobby(chapter_key)
	if host.mode != RelayLobbyFlow.MODE_LOBBY or host.relay_session == null: return
	var host_key := ChapterRegistry.hosting_key(ChapterRegistry.offered_key(chapter_key),host.relay_session.supports_creation)
	if host.relay_session.supports_creation(host_key):
		await host.relay_lobby_flow.lobby_action("create",host_key,hard)
	else:
		host._return_to_room_hub(host.relay_session.last_error if not host.relay_session.last_error.is_empty() else PlayerCopy.MAIN_73FEF220EAF1)

## A chapter the player owns through the Test Store waits only for a tester
## code to host, so its card and the host button go straight to that screen.
func _open_tester_code() -> void:
	if host.mode != MODE_ROOMS: return
	_leave()
	tester_access_requested.emit()

func _join(code: String, source: Control = null) -> void:
	if host.mode != MODE_ROOMS or not host._relay_identity().ready: return
	# Accept room-<code> and legacy input; a friend code gets a clear local error.
	var parsed := ShareCodes.parse(code,ShareCodes.ROOM)
	if not parsed.ok:
		message(ShareCodes.error_message(parsed,PlayerCopy.ROOMS_API_57B8AA801916))
		return
	await _tap(source, PlayerCopy.HUB_JOINING, host._room_session_idle, PlayerCopy.HUB_JOIN_WAIT_EXPIRED, _join_code.bind(str(parsed.id)))

func _join_code(code: String) -> void:
	# A refusal reports its reason on the hub.
	if not await host._prepare_ordinary_navigation(message) or host.mode != MODE_ROOMS: return
	var context: Dictionary = host._friends_route_context()
	var response: Dictionary = await host.api.request_json(HTTPClient.METHOD_POST,"/v1/invitations/resolve",{"invite_code":code},host._friends_route_current.bind(context))
	if not host._friends_route_current(context): return
	if not response.get("ok",false):
		if int(response.get("status",0)) in [0,404,405,501]:
			# The resolver is not deployed yet. Fall back to the existing modern
			# join; the visible invitation field remains a single mutating call.
			_leave()
			await host.relay_lobby_flow.join_room(code)
			host._settle_room_flow()
			return
		message(str(response.get("error","Invitation unavailable")))
		return
	var data: Variant = response.get("data")
	if not data is Dictionary or data.size() != 3 or not Typed.equal(data.get("schema_version"), 1) or data.get("family") not in ["legacy","relay"] or RoomsApi.json_int(data.get("api_version")) not in [1,2]:
		message("Invitation unavailable")
		return
	_leave()
	if data.api_version == 2:
		await host.relay_lobby_flow.join_room(code)
	else:
		await host.legacy_room_flow.join_room(code)
	# A join that stopped short (refused, or not allowed now) brings the hub
	# back with its reason; one that opened a room leaves it be.
	host._settle_room_flow()

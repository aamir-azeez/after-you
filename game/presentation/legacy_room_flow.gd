extends Node
## The earlier-island (v1) room page and its glue: opening a room (create, join,
## open, refresh, and taking the server's answer), drawing the page and its Share
## button, the legacy redo request (its client, the once-per-scope restore of
## its journal, the navigation gate built on it, the request pop-up and the Redo
## requests screen), and the page's Play your turn gate, Start a new attempt and
## Next island.
##
## Main hosts it as a child and keeps the room state other screens share:
## active_room, the room write lock (submission_in_flight, _one_room_write), play
## (room_play and the turn set-up in _start_room_turn, _watch_room_replay),
## reactions, safety, friend_share_target and the foreground refresh. The flow
## keeps the redo client and the Redo requests screen. It asks Main to navigate
## through the signals below, and reads Main only through this host contract
## (read at call time, so Main or a test can swap a service):
## - services: api, saves, relay_session, room_sharing, friend_presence,
##   foreground_schedule, turn_flow, notification_flow, ensure_relay_session
## - identity: _relay_identity, _tester_context, _ensure_identity
## - screen: mode, running, ui, overlay, application_backgrounded,
##   store_view_generation, lifecycle_generation, queue_foreground_refresh,
##   supersede_foreground_refresh, _sync_presence, _toast
## - room state: active_room, friend_share_target, room_play (the reaction
##   buttons set it), submission_in_flight, _one_room_write
## - room rules: _relay_available, _prepare_ordinary_navigation,
##   _friends_route_context, _friends_route_current, _foreground_room_context,
##   _current_room_share_allowed, _notice_room_reactions,
##   _add_room_reaction_summary, _react
## - entry points: _start_room_turn, _watch_room_replay, _room_safety, _show_friends
## - card kit: _card, _label, _paragraph, _button, _list_button, _scroll_list
## - node: add_child (the Redo requests screen stays Main's child), is_inside_tree
## Main gates online taps on navigation_ready(), asks redo_open(), calls
## close_redo() on Escape and invalidate_identity() when the identity changes.
## The foreground refresh calls navigation_ready(), redraw_when_free() and
## refresh_redo().
const PlayerCopy = preload("res://presentation/player_copy.gd")
const TurnState = preload("res://services/turn_state.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const LocalSave = preload("res://services/local_save.gd")
const ShareCodes = preload("res://services/share_codes.gd")
const RedoClient = preload("res://services/redo_client.gd")
const RedoScreen = preload("res://presentation/redo_screen.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const PresenceBadge = preload("res://presentation/friend_presence_badge.gd")
const TouchInput = preload("res://presentation/touch_input.gd")
const Simulation = preload("res://core/simulation.gd")
const Levels = preload("res://core/levels.gd")
const CREAM := Color("eceddb")
const REDO_REQUEST_BODY := "Your friend requested to redo your turn. Check the request to accept or reject it."
## Main's mode on the room page.
const MODE_ROOM := "room"
## Main's mode while the Redo requests screen is up.
const MODE_REDO := "redo_requests"

signal rooms_requested
signal home_requested

var host: Node
var legacy_redo: RefCounted
var legacy_redo_restore_scope := ""
var legacy_redo_restore_ok := true
var redo_screen: CanvasLayer
var _redo_request_modal: Control
var _announced_redo_requests: Dictionary = {}

func _init(main: Node = null) -> void:
	host = main

func create_room() -> void:
	var navigation: Dictionary = host._friends_route_context()
	if not host._relay_available() or not await host._ensure_identity(): return
	if navigation.view != host.store_view_generation or navigation.lifecycle != host.lifecycle_generation or host.application_backgrounded: return
	if not navigation_ready(): return
	if not await host._prepare_ordinary_navigation(): return
	if not host.relay_session.can_leave_for_legacy():
		host._toast(host.relay_session.last_error)
		return
	var context: Dictionary = host._friends_route_context()
	var response: Dictionary=await host.api.request_json(HTTPClient.METHOD_POST,"/v1/rooms",{"idempotency_key":RoomsApi.new_key(),"simulation_version":Simulation.COMFORT_SIMULATION_VERSION})
	if not host._friends_route_current(context): return
	accept_room(response)

func join_room(code: String) -> void:
	var navigation: Dictionary = host._friends_route_context()
	if code.strip_edges().is_empty() or not host._relay_available() or not await host._ensure_identity():
		return
	if navigation.view != host.store_view_generation or navigation.lifecycle != host.lifecycle_generation or host.application_backgrounded: return
	if not navigation_ready(): return
	if not await host._prepare_ordinary_navigation(): return
	host.ensure_relay_session()
	if not host.relay_session.can_leave_for_legacy():
		host._toast(host.relay_session.last_error)
		return
	var parsed := ShareCodes.parse(code,ShareCodes.ROOM)
	if not parsed.ok:
		host._toast(ShareCodes.error_message(parsed,PlayerCopy.ROOMS_API_57B8AA801916))
		return
	var context: Dictionary = host._friends_route_context()
	var response: Dictionary = await host.api.request_json(HTTPClient.METHOD_POST,"/v1/rooms/join",{"invite_code":parsed.id,"simulation_version":Simulation.COMFORT_SIMULATION_VERSION})
	if host._friends_route_current(context): accept_room(response)

## Opens a legacy room this player is in (Friends' Return, the hub's card).
func open_room(room_id: String) -> void:
	if not host._relay_available() or not navigation_ready(room_id): return
	if not await host._prepare_ordinary_navigation(): return
	if host.relay_session != null and not host.relay_session.can_leave_for_legacy(): return
	var context: Dictionary = host._friends_route_context()
	var response: Dictionary = await host.api.request_json(HTTPClient.METHOD_GET,"/v1/rooms/"+room_id)
	if host._friends_route_current(context): accept_room(response)

func refresh_room() -> void:
	# An explicit refresh supersedes any older automatically fetched snapshot.
	host.supersede_foreground_refresh()
	if not await host._ensure_identity():
		return
	var room_id := str(host.saves.data.get("room",{}).get("room_id",""))
	if room_id.is_empty():
		rooms_requested.emit()
		return
	restore_redo()
	if redo_client().pending().get("action") == "accept":
		host.active_room = host.saves.data.room.duplicate(true)
		show_room()
	var context: String = host._foreground_room_context(room_id)
	var response: Dictionary=await host.api.request_json(HTTPClient.METHOD_GET,"/v1/rooms/"+room_id)
	if context!=host._foreground_room_context(room_id): return
	if not response.get("ok",false) and redo_client().observe_room_failure(room_id,str(response.get("code",""))):
		rooms_requested.emit()
		host._toast(str(response.get("error",redo_client().last_error)))
		return
	host.foreground_schedule.bind(context,Time.get_ticks_msec())
	accept_room(response)

func accept_room(response: Dictionary, return_to_friends: bool = false) -> void:
	if not response.ok:
		host._toast(response.error)
		return
	# Opening the room, a write's reply or a manual read: the next poll comes soon.
	host.foreground_schedule.note_activity(Time.get_ticks_msec())
	var incoming: Variant=response.data.get("room",response.data)
	if not incoming is Dictionary or str(incoming.get("room_id","")).is_empty() or Levels.get_level(str(incoming.get("level_id",""))).is_empty():
		host._toast(PlayerCopy.MAIN_22FBAEF49772)
		return
	if not navigation_ready(str(incoming.room_id)): return
	if host.relay_session != null and not host.relay_session.can_leave_for_legacy():
		host._toast(host.relay_session.last_error)
		return
	host._notice_room_reactions(host.active_room,incoming)
	host.active_room=incoming.duplicate(true)
	if host._relay_identity().ready: host.friend_share_target = {"api_version":1,"room_id":host.active_room.room_id}
	var erased: Array=[]
	if TurnState.pending_status(host.saves.data.get("pending_turn",{}),host.active_room)=="accepted":
		erased=["pending_turn","room_draft"]
	if not host.saves.update_values({"room":host.active_room},erased):
		host._toast(host.saves.last_error)
	if return_to_friends:
		host._show_friends()
		return
	show_room()
	refresh_redo()

## A legacy room a notification named becomes the saved and shown room. False
## when the save cannot be written; nothing changes then.
func show_saved_room(room: Dictionary, refresh: bool) -> bool:
	if not host.saves.update_values({"room": room.duplicate(true)}): return false
	host.active_room = room.duplicate(true)
	host.friend_share_target = {"api_version":1,"room_id":host.active_room.room_id}
	show_room()
	if refresh: refresh_redo()
	return true

func show_room() -> void:
	host.running=false
	host.mode=MODE_ROOM
	var frame: VBoxContainer = host._card(700)
	frame.add_child(host._label(PlayerCopy.MAIN_8046BBD776CA,34,CREAM,true))
	var card: VBoxContainer = host._scroll_list(frame)
	card.get_parent().custom_minimum_size.y = clampf(host.overlay.size.y-230.0,180.0,390.0)
	if host.active_room.has("invite_code"):
		var invitation := ShareCodes.display(ShareCodes.ROOM,host.active_room.invite_code)
		card.add_child(host._paragraph("Invitation code: "+invitation))
		card.add_child(host._list_button("Copy invitation code",func(): DisplayServer.clipboard_set(invitation); host._toast("Invitation code copied."),false))
	if host._relay_identity().ready and host.active_room.get("host_id") == host.api.player_id:
		var friend_status: Label = host._label("Waiting for friend" if host.active_room.get("guest_id") == null else "Friend joined",20)
		friend_status.name = "RoomFriendStatus"
		card.add_child(friend_status)
	_add_room_share(card)
	var active_role := str(host.active_room.get("active_role","a"))
	var my_turn: bool = TurnState.my_turn(host.active_room,host.api.player_id)
	var redo: RefCounted = redo_client()
	if not redo.busy: redo.bind_room("legacy",host.active_room)
	var redo_pending: bool = redo.pending().get("action") == "accept"
	if redo_pending: my_turn = false
	var pending: Dictionary=host.saves.data.get("pending_turn",{})
	card.add_child(host._paragraph("Island %d of 8 · %s" % [int(host.active_room.get("level_index",0))+1,PlayerCopy.MAIN_1AAC5BE95E22 if my_turn else (PlayerCopy.MAIN_FAC85D5E6CA7 if active_role=="complete" else PlayerCopy.MAIN_BD6413254AB9)]))
	if is_instance_valid(host.friend_presence):
		host._sync_presence()
		var badge := PresenceBadge.new()
		badge.configure(host.friend_presence, "v1", str(host.active_room.get("room_id", "")))
		card.add_child(badge)
	if not pending.is_empty():
		card.add_child(host._paragraph(PlayerCopy.MAIN_52C04F6029F5))
		card.add_child(host._list_button("Check saved submission",host.turn_flow.reconcile_pending))
	if not my_turn and active_role != "complete" and pending.is_empty():
		host.notification_flow.add_offer(card)
	if my_turn and pending.is_empty():
		card.add_child(host._list_button("Play your turn",play_turn))
	if active_role=="complete":
		host._add_room_reaction_summary(card, host.active_room)
		card.add_child(host._list_button("Watch this island",host._watch_room_replay,false))
		if int(host.active_room.get("level_index",0))<7 and pending.is_empty() and not redo_pending:
			card.add_child(host._list_button("Next island",advance_room))
		var reactions := HBoxContainer.new()
		for reaction: String in ["Beautiful!","We did it!","Again soon"]:
			reactions.add_child(host._list_button(reaction,func(): host.room_play=true; host._react(reaction),false))
		card.add_child(reactions)
	if host.active_room.get("guest_id") != null:
		card.add_child(host._list_button("Report or block player",host._room_safety,false))
	if pending.is_empty() and not redo_pending and not LocalSave.normalize_attempt(host.active_room.get("recordings",{})).a.is_empty():
		card.add_child(host._list_button("Start a new attempt",confirm_fork,false))
	if pending.is_empty(): _add_redo_action(card)
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation",10)
	for entry: Array in [["Refresh",refresh_room],["Home",home_requested.emit]]:
		var action: Button = host._button(entry[0],entry[1],false)
		action.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		navigation.add_child(action)
	frame.add_child(navigation)

## The page's Share current room, for the host while sharing is allowed.
func _add_room_share(card: VBoxContainer) -> void:
	var target := {"api_version": 1, "room_id": host.active_room.get("room_id", "")}
	if not host._current_room_share_allowed(target): return
	var status: Label = host._label("All friends",17)
	var button: Button = host._list_button("Share current room",func(): _share_room_from_card(target, card, status),false)
	button.name = "ShareCurrentRoom"
	button.disabled = host.room_sharing.busy
	card.add_child(button)
	card.add_child(status)

func _share_room_from_card(target: Dictionary, card: VBoxContainer, status: Label) -> void:
	if not is_instance_valid(card) or not card.is_inside_tree(): return
	var button: Button = card.get_node("ShareCurrentRoom")
	button.disabled = true
	var result: Dictionary = await host.room_sharing.share(target)
	if not is_instance_valid(card) or not card.is_inside_tree() or not host._current_room_share_allowed(target) or result.get("ignored", false): return
	button.disabled = false
	status.text = str(result.get("message", "Friends unavailable"))

func redo_client() -> RefCounted:
	if legacy_redo == null: legacy_redo = RedoClient.new(host.api,host._relay_identity)
	return legacy_redo

func restore_redo() -> bool:
	var context: String = host._tester_context()
	# Cached room presentation has no authenticated redo scope until identity
	# is loaded. Network mutations separately require that identity.
	if context.is_empty(): return true
	var client := redo_client()
	var saved: Dictionary = host.saves.data.get("room",{})
	var bound_id: String = client.bound_room_id("legacy")
	if not bound_id.is_empty() and (not client.pending().is_empty() or bound_id == saved.get("room_id")):
		return true
	# Notification safety is checked every frame. Restore this journal once per
	# identity and saved room, never once per safety check.
	var scope := context + ":" + str(saved.get("room_id",""))
	if scope == legacy_redo_restore_scope: return legacy_redo_restore_ok
	legacy_redo_restore_scope = scope
	legacy_redo_restore_ok = true
	if bound_id.is_empty(): client.invalidate()
	if not str(saved.get("room_id","")).is_empty() and host.api.player_id in [saved.get("host_id"),saved.get("guest_id")]:
		legacy_redo_restore_ok = client.bind_room("legacy",saved)
	return legacy_redo_restore_ok

## Whether a room may open or an online screen may replace this one: a redo
## acceptance not yet settled holds navigation, except to the room it recovers.
## With reveal_recovery, a refusal shows that room and says why.
func navigation_ready(target_room: String = "", reveal_recovery: bool = true) -> bool:
	var restored := restore_redo()
	var client := redo_client()
	var pending: Dictionary = client.pending()
	var saved: Dictionary = host.saves.data.get("room",{})
	var recover_room := str(pending.get("source",{}).get("room_id",saved.get("room_id","")))
	# Reading the current room is safe even after a lost acceptance reply or a
	# damaged local journal. It must not strand the route back to recovery.
	if not target_room.is_empty() and target_room == recover_room: return true
	if restored and pending.is_empty(): return true
	if reveal_recovery:
		var room: Dictionary = client.bound_room("legacy")
		if room.is_empty(): room = saved
		if not room.is_empty() and host.api.player_id in [room.get("host_id"),room.get("guest_id")]:
			host.active_room = room.duplicate(true)
			show_room()
		host._toast(PlayerCopy.MAIN_8184DEB41266)
	return false

func _add_redo_action(card: VBoxContainer) -> void:
	var client: RefCounted = redo_client()
	var source := RedoClient.source_for("legacy",host.active_room)
	if source.is_empty() and client.pending().is_empty(): return
	var label := "Redo requested" if client.can_accept() else "Ask for redo" if TurnState.my_turn(host.active_room,host.api.player_id) else "Turn requests"
	if not client.pending().is_empty(): label = "Retry request"
	card.add_child(host._list_button(label,open_redo,false))
	if client.can_accept(): _announce_redo_request.call_deferred(client,str(host.active_room.get("room_id","")),open_redo)

func _announce_redo_request(client: RefCounted, room_id: String, review: Callable) -> void:
	## A friend's redo request is easy to miss as a button label, so show it once
	## per request in the shared pop-up. Not now leaves the request waiting.
	if not host.is_inside_tree() or host.running or is_instance_valid(_redo_request_modal) or not client.can_accept(): return
	var request: Variant = client.view().get("request")
	if not request is Dictionary: return
	var key := room_id + ":" + str(request.get("request_id",JSON.stringify(request)))
	if _announced_redo_requests.has(key): return
	_announced_redo_requests[key] = true
	_redo_request_modal = InGameModal.open(host.ui,"RedoRequestModal","Redo requested")
	_redo_request_modal.label(REDO_REQUEST_BODY)
	var open: Button = _redo_request_modal.add_actions("Review request",func():
		if is_instance_valid(_redo_request_modal): _redo_request_modal.close(false)
		_redo_request_modal = null
		review.call(),"Not now")
	open.grab_focus()

func open_redo() -> void:
	if not host._relay_available() or host.application_backgrounded or host.running or is_instance_valid(redo_screen): return
	var client := redo_client()
	if not client.bind_room("legacy",host.active_room): host._toast(client.last_error); return
	var context: String = host._tester_context()
	host.mode = MODE_REDO
	host.ui.visible = false
	redo_screen = RedoScreen.new()
	redo_screen.client = client
	redo_screen.closed.connect(func():
		redo_screen = null
		host.ui.visible = true
		if host._tester_context() != context or host.mode != MODE_REDO: return
		show_room()
		host.queue_foreground_refresh()
		if not host.application_backgrounded: refresh_room())
	host.add_child(redo_screen)

func refresh_redo() -> void:
	if host.mode != MODE_ROOM or host.application_backgrounded or not host.saves.data.get("pending_turn",{}).is_empty(): return
	var client := redo_client()
	if client.busy: return
	if RedoClient.source_for("legacy",host.active_room).is_empty() and client.pending().is_empty(): return
	var context: String = host._foreground_room_context(str(host.active_room.room_id))
	var before: Dictionary = client.view()
	if not client.bind_room("legacy",host.active_room): return
	await client.refresh()
	if context != host._foreground_room_context(str(host.active_room.get("room_id",""))) or host.mode != MODE_ROOM or host.application_backgrounded: return
	if before != client.view(): redraw_when_free(str(host.active_room.get("room_id","")))

## A poll's redraw of the room page waits for a tap in progress to finish, or
## the button under the finger would be freed and the tap lost.
func redraw_when_free(room_id: String) -> void:
	await TouchInput.redraw_when_released(host.overlay,func() -> bool: return host.mode==MODE_ROOM and str(host.active_room.get("room_id",""))==room_id,show_room)

## A Redo requests screen is up.
func redo_open() -> bool:
	return is_instance_valid(redo_screen)

## Escape closes the Redo requests screen, as its own controls do.
func close_redo() -> void:
	redo_screen.close()

## The identity changed: the redo journal is read again, and an open Redo
## requests screen goes. True when one was open.
func invalidate_identity() -> bool:
	legacy_redo_restore_scope = ""
	legacy_redo_restore_ok = true
	var had_redo_screen := is_instance_valid(redo_screen)
	if legacy_redo != null: legacy_redo.invalidate()
	if is_instance_valid(redo_screen):
		redo_screen.invalidate()
		redo_screen = null
		host.ui.visible = true
	return had_redo_screen

## Play your turn: the room page's checks, then Main starts the turn.
func play_turn() -> void:
	if not restore_redo():
		host._toast(PlayerCopy.MAIN_8184DEB41266)
		return
	if redo_client().pending().get("action") == "accept":
		show_room()
		return
	if not TurnState.my_turn(host.active_room,host.api.player_id) or not host.saves.data.get("pending_turn",{}).is_empty():
		show_room()
		return
	host._start_room_turn()

func confirm_fork() -> void:
	if not navigation_ready(): return
	var card: VBoxContainer = host._card()
	card.add_child(host._label(PlayerCopy.MAIN_F817D954E490,34,CREAM,true))
	card.add_child(host._paragraph(PlayerCopy.MAIN_C9DD5A234C97))
	card.add_child(host._button("Start a new attempt",fork_room))
	card.add_child(host._button("Keep this attempt",show_room,false))

func fork_room() -> void:
	if not host._relay_identity().ready or not navigation_ready(): return
	if host.submission_in_flight or not host.saves.data.get("pending_turn",{}).is_empty():
		return
	var context: String = host._foreground_room_context(str(host.active_room.room_id))
	var response: Dictionary = await host._one_room_write(host.api.request_json.bind(HTTPClient.METHOD_POST,"/v1/rooms/"+str(host.active_room.room_id)+"/fork",{"base_revision":host.active_room.revision,"idempotency_key":RoomsApi.new_key()}))
	if context == host._foreground_room_context(str(host.active_room.get("room_id",""))): accept_room(response)

func advance_room() -> void:
	if not host._relay_identity().ready or not navigation_ready(): return
	if host.submission_in_flight or not host.saves.data.get("pending_turn",{}).is_empty():
		return
	var context: String = host._foreground_room_context(str(host.active_room.room_id))
	var response: Dictionary = await host._one_room_write(host.api.request_json.bind(HTTPClient.METHOD_POST,"/v1/rooms/"+str(host.active_room.room_id)+"/advance",{"base_revision":host.active_room.revision,"idempotency_key":RoomsApi.new_key()}))
	if context == host._foreground_room_context(str(host.active_room.get("room_id",""))): accept_room(response)

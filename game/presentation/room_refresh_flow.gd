extends RefCounted
## A room screen's online reads, as the screen shows them: the manual read
## (Check saved turn, Refresh), the scheduled poll that runs from the screen's
## _process, the owed redraw, the read a manual refresh left while the phone
## was away, the live socket's hints and the sync status line
## (services/refresh_schedule.gd keeps the cadence, cooldown and retry-after).
##
## Host contract (relay_preview.gd and its subclasses; `host` = the screen):
## - reads: online_session, journey, running, backgrounded, mode,
##   _room_context_lost, _leaving, _sharing_room, _safety_screen,
##   reaction_photos, live_connection, controls;
## - shares: refresh_schedule, online_request_generation (the screen bumps it
##   on any new request; a read here bumps it too), online_refresh_queued (set
##   by the screen when the room should be read soon), online_last_checked_ms
##   and the online_sync_status label;
## - writes mode = "online_request" while a manual read shows its card;
## - calls by name, so a subclass's override answers: _show_ready(), _card(),
##   _label() and _refresh_redo().
## The screen keeps _online_refresh, _service_online_refresh,
## _online_refresh_context and poll_changed as forwarders for its room
## actions, its _process and tests.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const RefreshClock = preload("res://services/refresh_schedule.gd")
const TouchInput = preload("res://presentation/touch_input.gd")
const POLL_MODES := ["ready", "online_waiting", "complete"]

var host: Node
## A hint is waiting for its read, which runs even where the page does not poll.
var _live_read_queued := false
var _suspended_manual_refresh: Dictionary = {}
## A room read changed what the card shows but landed while the card could not
## be redrawn (the phone unfocused or away, a sheet over it). The redraw waits
## for the next service pass on this same room.
var _owed_redraw_context := ""

func _init(screen: Node) -> void:
	host = screen

## The card is being redrawn, so no redraw is owed.
func forget_owed_redraw() -> void:
	_owed_redraw_context = ""

## The manual read: the explicit action keeps the exact saved direction.
func manual() -> void:
	if host.online_session == null or host.online_session.busy() or host.running or host._room_context_lost:
		return
	var now := Time.get_ticks_msec()
	host.refresh_schedule.bind(context(), now, poll_interval_ms())
	host.refresh_schedule.request_now(now)
	var ticket: Dictionary = host.refresh_schedule.begin_if_due(now, not host.backgrounded, host.online_session.busy())
	if ticket.is_empty():
		update_sync_status(now)
		return
	host.mode = "online_request"
	host.online_request_generation += 1
	var generation: int = host.online_request_generation
	_suspended_manual_refresh.clear()
	host._card(PlayerCopy.RELAY_PREVIEW_E274B279C9CF, PlayerCopy.RELAY_PREVIEW_AE8554BD7C76)
	var source: RefCounted = host.journey
	var room_context := context()
	var reconciling: bool = not host.journey.pending().is_empty()
	if not _is_current(generation,source,room_context,["online_request"]):
		host.refresh_schedule.complete(ticket,Time.get_ticks_msec(),false)
		_remember_suspended(generation,source,room_context)
		return
	# The explicit action keeps the exact saved direction. It does not infer a
	# new contribution.
	if reconciling:
		await host.journey.reconcile()
	else:
		await host.journey.refresh()
	if not is_instance_valid(host): return
	var result: Dictionary = {} if reconciling else host.journey.last_refresh_result()
	if host.journey.last_error.is_empty(): await host._refresh_redo()
	if not is_instance_valid(host): return
	host.refresh_schedule.complete(ticket, Time.get_ticks_msec(), host.journey.last_error.is_empty(), int(result.get("retry_after_ms", 0)), bool(result.get("terminal", false)))
	if _is_current(generation,source,room_context,["online_request"]):
		host.online_last_checked_ms = Time.get_ticks_msec() if host.journey.last_error.is_empty() else host.online_last_checked_ms
		host._show_ready()
	else:
		_remember_suspended(generation,source,room_context)

func _remember_suspended(generation: int, source: RefCounted, room_context: String) -> void:
	if host.backgrounded and host.is_inside_tree() and host.mode == "online_request" and generation == host.online_request_generation and host.journey == source and host.online_session != null and room_context == context() and not host._leaving and not host._room_context_lost:
		_suspended_manual_refresh = {"generation":generation,"context":room_context}

func _is_current(generation: int, source: RefCounted, room_context: String, allowed_modes: Array) -> bool:
	return host.is_inside_tree() and generation == host.online_request_generation and host.journey == source and host.online_session != null and room_context == context() and not host.backgrounded and not host.running and not host._leaving and not host._room_context_lost and host.mode in allowed_modes and not is_instance_valid(host._safety_screen) and not (is_instance_valid(host.reaction_photos) and host.reaction_photos.active) and not host.online_session.photo_request_busy()

func poll_interval_ms() -> int:
	return host.live_connection.poll_interval_ms(RefreshClock.ROOM_INTERVAL_MS) if is_instance_valid(host.live_connection) else RefreshClock.ROOM_INTERVAL_MS

func on_live_room_changed(room_id: String, seq: int) -> void:
	if not is_instance_valid(host): return
	if host.online_session == null or room_id != host.online_session.last_room(): return
	# Reads are ordered inside the room: a hint older than the room this page holds is already shown.
	var held := int(host.journey.snapshot().get("revision", -1))
	if held >= 0 and seq < held: return
	live_hint()

func live_hint() -> void:
	if host.online_session == null or host._leaving: return
	if host.refresh_schedule.hint(Time.get_ticks_msec()): _live_read_queued = true

## Hints were missed since `since_ms`; a resume read that began after it already covers them.
func live_caught_up(since_ms: int) -> void:
	if not is_instance_valid(host): return
	if host.online_session == null or host._leaving: return
	if host.refresh_schedule.hint(Time.get_ticks_msec(), since_ms): _live_read_queued = true

func context() -> String:
	return str(host.journey.get_instance_id()) + ":" + str(host.online_session.last_room())

func add_sync_status(card: VBoxContainer, only_when_delayed: bool = false) -> void:
	host.online_sync_status = host._label(PlayerCopy.RELAY_PREVIEW_7A4E91C6BB33, 16)
	host.online_sync_status.name = "RoomSyncStatus"
	# The side panel keeps the routine cadence in Room options and shows only delays.
	if only_when_delayed: host.online_sync_status.set_meta("only_when_delayed", true)
	card.add_child(host.online_sync_status)
	update_sync_status(Time.get_ticks_msec())

func update_sync_status(now: int) -> void:
	if not is_instance_valid(host.online_sync_status): return
	var status: Label = host.online_sync_status
	var text := PlayerCopy.RELAY_PREVIEW_AE39B1E4A9F7
	var terminal: bool = host.refresh_schedule.stopped() and host.journey.last_refresh_result().get("terminal", false)
	if terminal:
		text = PlayerCopy.RELAY_PREVIEW_9D001B9A783F
	elif host.refresh_schedule.busy():
		text = PlayerCopy.RELAY_PREVIEW_8E35E137EA15
	elif not host.journey.last_error.is_empty():
		text = PlayerCopy.RELAY_PREVIEW_EF61644814DA % maxi(1, ceili(float(host.refresh_schedule.next_due_ms() - now) / 1000.0))
	elif host.online_last_checked_ms >= 0:
		text = PlayerCopy.RELAY_PREVIEW_F85672E29DEB
	status.text = text
	if status.has_meta("only_when_delayed"):
		status.visible = terminal or not host.journey.last_error.is_empty()

## The scheduled poll, once per screen frame.
func service() -> void:
	if host.online_session==null or host.backgrounded or host.running or host._sharing_room or host._room_context_lost or not host.is_inside_tree(): return
	# A manual read may finish while backgrounded. Rebuild its stable card only
	# after foreground returns, then leave all retry traffic on the GET-only path.
	if not _suspended_manual_refresh.is_empty():
		if host.online_session.busy() or host.journey.busy() or host.refresh_schedule.busy(): return
		var saved := _suspended_manual_refresh
		_suspended_manual_refresh = {}
		if saved.generation == host.online_request_generation and saved.context == context() and host.mode == "online_request":
			host._show_ready()
			host.online_refresh_queued = true
	if host.mode not in POLL_MODES or is_instance_valid(host._safety_screen): return
	if is_instance_valid(host.reaction_photos) and host.reaction_photos.active: return
	var now := Time.get_ticks_msec()
	var room_context := context()
	# A read that found a change while the card could not be redrawn: the next
	# read compares with what that one kept, so the card is redrawn now.
	if _owed_redraw_context == room_context and not host.online_session.busy() and not host.online_session.photo_request_busy() and not TouchInput.press_held(host.controls):
		host._show_ready()
		return
	host.refresh_schedule.bind(room_context,now,poll_interval_ms())
	update_sync_status(now)
	if host.online_refresh_queued:
		host.refresh_schedule.request_now(now)
		host.online_refresh_queued=false
	elif host.mode=="ready" and host.journey.snapshot().get("guest_id") != null and not _live_read_queued:
		# The existing GET scheduler observes a friend's arrival before Begin.
		# Once joined, ready cards and active play do not keep polling.
		return
	# A poll disables and redraws this card's buttons, so it never starts while
	# a finger is pressing one; it runs on the first frame after the release.
	if now >= host.refresh_schedule.next_due_ms() and TouchInput.press_held(host.controls): return
	var ticket: Dictionary=host.refresh_schedule.begin_if_due(now,true,host.online_session.busy())
	if ticket.is_empty(): return
	_live_read_queued = false
	var generation: int = host.online_request_generation
	var source: RefCounted = host.journey
	var saved_pending: Dictionary = host.journey.pending()
	var before: Dictionary=host.journey.snapshot()
	var before_my_turn: bool = host.journey.my_turn()
	if not _is_current(generation,source,room_context,POLL_MODES):
		host.refresh_schedule.complete(ticket,Time.get_ticks_msec(),false)
		return
	# A saved turn whose receipt never arrived is checked on the same schedule:
	# reconcile() first asks the server for the turn's receipt and resends the
	# identical request (same key, same bytes) only when the server says it
	# never got it, so a retry can never make a second turn. A turn the room
	# definitively refused (held) is never resent here; the player decides.
	var unconfirmed: bool = not saved_pending.is_empty() and not saved_pending.get("held", false)
	var succeeded: bool=await host.journey.reconcile() if unconfirmed else await host.journey.refresh()
	if not is_instance_valid(host): return
	var redo_changed: bool = await host._refresh_redo() if succeeded else false
	if not is_instance_valid(host): return
	if succeeded: host.online_last_checked_ms = Time.get_ticks_msec()
	var refresh_result: Dictionary=host.journey.last_refresh_result()
	# A turn whose receipt is still being checked never waits any longer.
	var changed: bool = unconfirmed or poll_changed(host.journey,before,before_my_turn,saved_pending,succeeded,redo_changed)
	host.refresh_schedule.complete(ticket,Time.get_ticks_msec(),succeeded,int(refresh_result.get("retry_after_ms",0)),bool(refresh_result.get("terminal",false)),changed)
	var shown_changed := poll_changed(host.journey,before,before_my_turn,saved_pending,succeeded,redo_changed)
	if not _is_current(generation,source,room_context,POLL_MODES):
		_owe_redraw(source,room_context,shown_changed)
		return
	# A tap that began during the read finishes on the card it started on.
	await TouchInput.until_released(host.controls)
	if not is_instance_valid(host): return
	if not host.is_inside_tree() or not _is_current(generation,source,room_context,POLL_MODES):
		_owe_redraw(source,room_context,shown_changed)
		return
	if shown_changed: host._show_ready()

func _owe_redraw(source: RefCounted, room_context: String, changed: bool) -> void:
	if changed and host.is_inside_tree() and host.mode in POLL_MODES and host.journey == source and host.online_session != null and room_context == context(): _owed_redraw_context = room_context

## True when a room poll found something the room card shows: the turn moved
## to or from this phone, the unsent turn changed, the room is gone, or the
## room or its turn requests changed. The card is redrawn then, and the next
## poll comes at the base cadence; a poll that found nothing waits longer.
static func poll_changed(source: RefCounted, before: Dictionary, before_my_turn: bool, saved_pending: Dictionary, succeeded: bool, redo_changed: bool) -> bool:
	return before_my_turn != source.my_turn() or saved_pending != source.pending() or (source.has_method("room_gone") and source.room_gone()) or succeeded and (before != source.snapshot() or redo_changed)

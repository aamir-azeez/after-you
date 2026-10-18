extends Node
## Turn and hosting notifications inside the app: the notification service's
## save, secret and identity callbacks, the notification rows of Settings >
## Friends & notifications (their values; presentation/settings_rows.gd draws
## them) and the Enable offer on room cards, alerts that arrive while the app is open, and
## opening the room or Friends that a tapped alert names. A tap from a cold start
## or a resume stays in the service's pending route until opening it is safe.
##
## Main hosts it as a child. Main creates the notification service and its native
## bridge and keeps the service (turn_notifications); this flow configures it.
## The flow reads Main through this host contract (read at call time, so Main or
## a test can swap a service):
## - services: api, saves, secrets, turn_notifications,
##   hosting_notification_preferences, relay_session
## - screens: mode, running, relay_child, toast_label
## - state: application_backgrounded, submission_in_flight, identity_loading,
##   identity_busy, identity_read_state, IdentityReadState,
##   foreground_refresh_running, relay_identity_epoch, lifecycle_generation
## - rules: _relay_identity, _token_digest, _await_secret, _parse_json,
##   _update_gate_active, _friend_display_name
## - entry points: legacy_room_flow (navigation_ready, show_saved_room),
##   ensure_relay_session, queue_foreground_refresh,
##   _show_friends, friends_flow (is_open, hosting_hint, refresh),
##   _enter_online_relay, _request_update_gate, settings_flow (is_open,
##   refresh: Settings redraws its notification rows when the service changes)
## - modes: NOTIFICATION_ROUTE_MODES (the screens a tap may leave)
## - card kit: _paragraph, _button, _toast
## It also calls two private members, as Main did: RelayOnline._room_gone and
## TurnNotifications._integer.
## Main calls service_route() every frame while the service exists.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const TurnNotifications = preload("res://services/turn_notifications.gd")
const RelayOnline = preload("res://services/relay_online_session.gd")
const ChapterRegistry = preload("res://services/chapter_registry.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const Levels = preload("res://core/levels.gd")
const Typed = preload("res://services/typed_values.gd")
var host: Node
## A tapped alert that could not open waits until this time before another try.
var route_retry_ms := 0
var _route_busy := false
var _deferred_event := ""
var _hint: Label
var _offer: Button

func _init(main: Node = null) -> void:
	host = main

## Wires the service Main created to the saves, secrets and identity it reads.
func configure_service(service: Node, native: Node) -> void:
	service.configure(host.api, native, _identity, _read_binding, _write_binding, _preference, _save_preference)
	service.configure_hosting(host.hosting_notification_preferences.read,host.hosting_notification_preferences.save)
	service.configure_requests(_request_preference, _save_request_preference)
	service.changed.connect(update_offer)
	service.foreground_hint.connect(foreground_hint)
	service.route_available.connect(func():
		if is_instance_valid(host.toast_label): host._toast(PlayerCopy.MAIN_6FE6B224FD24))

func _identity() -> Dictionary:
	return {"ready": host._relay_identity().ready, "settled": not host.identity_loading and host.identity_read_state not in [host.IdentityReadState.UNCHECKED, host.IdentityReadState.LOADING], "owner": host.api.player_id if host.api != null else "", "credential_hash": host._token_digest() if host.api != null and not host.api.device_token.is_empty() else ""}

func _preference() -> bool:
	return host.saves.data.settings.get("turn_notifications", false) == true

func _save_preference(value: bool) -> bool:
	var next: Dictionary = host.saves.data.settings.duplicate(true)
	next.turn_notifications = value
	return host.saves.update_values({"settings": next})

func _request_preference() -> bool:
	return host.saves.data.settings.get("turn_request_notifications", false) == true

func _save_request_preference(value: bool) -> bool:
	var next: Dictionary = host.saves.data.settings.duplicate(true)
	next.turn_request_notifications = value
	return host.saves.update_values({"settings": next})

func _read_binding() -> Dictionary:
	var result: Dictionary = await host._await_secret(host.secrets.get_secret("notification_binding"))
	var payload: Variant = result.get("payload")
	if not result.get("ok", false) or not payload is Dictionary: return {"ok": false}
	if Typed.equal(payload.get("found"), false) and payload.get("value") == null: return {"ok": true, "value": {}}
	if not Typed.equal(payload.get("found"), true) or not payload.get("value") is String: return {"ok": false}
	var value: Variant = host._parse_json(payload.value)
	return {"ok": value is Dictionary, "value": value}

func _write_binding(value: Dictionary) -> Dictionary:
	var result: Dictionary = await host._await_secret(host.secrets.put_secret("notification_binding", JSON.stringify(value)))
	return {"ok": result.get("ok", false) and Typed.equal(result.get("payload", {}).get("stored"), true)}

## What a room's own Enable offer shows.
func status() -> Dictionary:
	return {"enabled": host.turn_notifications.enabled(), "registered": host.turn_notifications.registered(), "busy": host.turn_notifications.busy(), "message": host.turn_notifications.status_text}

func enable() -> void:
	host.turn_notifications.set_enabled(true)
	update_offer()

## Settings > Friends & notifications reads and changes these (settings_rows.gd).
func reconcile() -> void:
	if is_instance_valid(host.turn_notifications): host.turn_notifications.queue_reconcile()

func turn_notifications_on() -> bool:
	return is_instance_valid(host.turn_notifications) and host.turn_notifications.enabled()

func set_turn_notifications(value: bool) -> bool:
	if not is_instance_valid(host.turn_notifications) or not host.turn_notifications.set_enabled(value): return false
	update_offer()
	return true

func turn_requests_on() -> bool:
	return _request_preference()

## A sub-option of turn notifications: off pauses it and keeps the choice.
func set_turn_requests(value: bool) -> bool:
	return is_instance_valid(host.turn_notifications) and host.turn_notifications.set_requests_enabled(value)

func turn_off() -> void:
	set_turn_notifications(false)

## The service's own line about where notifications stand.
func status_line() -> String:
	return str(host.turn_notifications.status_text) if is_instance_valid(host.turn_notifications) else ""

## The turn alert status line and its Enable button, on any card.
func add_offer(card: VBoxContainer) -> void:
	_hint = host._paragraph("", 480)
	_hint.name = "TurnNotificationStatus"
	card.add_child(_hint)
	_offer = host._button(PlayerCopy.MAIN_C4B947AAAE59, enable, false)
	_offer.name = "EnableTurnNotifications"
	card.add_child(_offer)
	update_offer()

func update_offer() -> void:
	if not is_instance_valid(host.turn_notifications): return
	var state := status()
	if is_instance_valid(_hint): _hint.text = state.message
	if is_instance_valid(_offer):
		_offer.visible = not state.registered
		_offer.disabled = state.busy
	if is_instance_valid(host.relay_child): host.relay_child.update_notification_offer()
	if host.settings_flow != null and host.settings_flow.is_open(): host.settings_flow.refresh()

## An alert that arrived while the app is open.
func foreground_hint(route: Dictionary) -> void:
	if not host.turn_notifications.accepts(route): return
	if route.get("kind") == "friend_room_available":
		# Android shows no banner while the app is open, so say it here. The toast
		# sits under the hidden main UI while a room is open; the room card shows it.
		var message: String = FriendNicknames.sentence_start(host._friend_display_name(str(route.host_id))) + " has a room ready"
		if host.friends_flow.is_open(): host.friends_flow.hosting_hint()
		elif is_instance_valid(host.relay_child): host.relay_child.notification_deferred(message)
		else: host._toast(message)
		return
	if route.room_family == "relay" and is_instance_valid(host.relay_child):
		host.relay_child.notification_room_hint(route.room_id)
	elif route.room_family == "legacy" and str(host.saves.data.get("room", {}).get("room_id", "")) == route.room_id:
		host.queue_foreground_refresh()
	# The ordinary refresh schedulers enforce mode, identity, busy and cooldown
	# guards. Receiving a hint never reconciles a POST or changes the open room.

## Friends drew its hosting list.
func hosting_view_ready(_events: Array) -> void:
	var route: Dictionary = host.turn_notifications.pending_route()
	# A rendered authenticated inbox also resolves revoked or expired publications.
	if route.get("kind") == "friend_room_available" and host.turn_notifications.accepts(route):
		host.turn_notifications.acknowledge_route(str(route.event_id))

## True when a tapped alert may change the screen now.
func route_safe(route: Dictionary) -> bool:
	if host.application_backgrounded or host.running or host.submission_in_flight or host.identity_loading or host.identity_busy or host.foreground_refresh_running or is_instance_valid(host.relay_child) or host.saves.read_only: return false
	if host.mode not in host.NOTIFICATION_ROUTE_MODES and not (host.mode == "friends" and route.get("kind") == "friend_room_available"): return false
	if not host._relay_identity().ready or not host.saves.data.get("pending_turn", {}).is_empty() or not host.saves.data.get("room_draft", {}).is_empty(): return false
	if not host.legacy_room_flow.navigation_ready(str(route.room_id) if route.room_family == "legacy" else "",false): return false
	if host.relay_session != null:
		if host.relay_session.busy() or not host.relay_session.can_leave_for_legacy(): return false
		if host.relay_session.coordinator != null and not host.relay_session.coordinator.draft().is_empty(): return false
	return host.turn_notifications.accepts(route)

func _route_context() -> String:
	return JSON.stringify([TurnNotifications.identity_key(_identity()), host.relay_identity_epoch, host.lifecycle_generation, host.mode])

func _route_current(route: Dictionary, context: String) -> bool:
	return context == _route_context() and route_safe(route) and host.turn_notifications.pending_route().get("event_id") == route.event_id

## Opens the pending tapped alert once it is safe, one at a time.
func service_route() -> void:
	if _route_busy or Time.get_ticks_msec() < route_retry_ms: return
	var route: Dictionary = host.turn_notifications.pending_route()
	if route.is_empty(): return
	# While this build is too old, a tap on an alert brings up the update screen
	# on Home rather than opening a room or Friends. The alert is used up once.
	if host._update_gate_active():
		host.turn_notifications.acknowledge_route(route.event_id)
		host._request_update_gate()
		return
	if not route_safe(route):
		if not host.application_backgrounded and _deferred_event != route.event_id:
			_deferred_event = route.event_id
			var message := PlayerCopy.MAIN_55E41B8A33F9
			if is_instance_valid(host.relay_child): host.relay_child.notification_deferred(message)
			else: host._toast(message)
		return
	_route_busy = true
	await _open_route(route)
	_route_busy = false

func _open_route(route: Dictionary) -> void:
	if not route_safe(route): return
	if route.get("kind") == "friend_room_available":
		route_retry_ms = Time.get_ticks_msec() + 15000
		if host.friends_flow.is_open(): await host.friends_flow.refresh()
		else: await host._show_friends()
		return
	var context := _route_context()
	var path := ("/v1/rooms/" if route.room_family == "legacy" else "/v2/rooms/") + str(route.room_id)
	var response: Dictionary = await host.api.request_json(HTTPClient.METHOD_GET, path)
	# The user may tap a newer room notification while the network is waiting.
	# Check the native selection again before applying this older response.
	await host.turn_notifications.refresh_pending_route()
	if not _route_current(route, context): return
	var room: Variant = response.get("data")
	if room is Dictionary: room = room.get("room", room)
	if not response.get("ok", false):
		route_retry_ms = Time.get_ticks_msec() + maxi(5000, int(response.get("retry_after_ms", 0)))
		if int(response.get("status", 0)) in [401, 403, 404, 410]:
			host.turn_notifications.acknowledge_route(route.event_id)
		# A room the friend closed says so; other failures keep the general note.
		host._toast(PlayerCopy.ROOMS_API_A7ACF38988EE if RelayOnline._room_gone(response) else PlayerCopy.MAIN_15214ED7911C)
		return
	if not _owned_room(room, route):
		host.turn_notifications.acknowledge_route(route.event_id)
		host._toast(PlayerCopy.MAIN_310F42091578)
		return
	if route.room_family == "legacy":
		if Levels.get_level(str(room.get("level_id", ""))).is_empty():
			host.turn_notifications.acknowledge_route(route.event_id)
			host._toast(PlayerCopy.MAIN_6DE42F59590C)
			return
		if not host.legacy_room_flow.show_saved_room(room, route.get("kind") == "redo_requested"):
			route_retry_ms = Time.get_ticks_msec() + 15000
			host._toast(PlayerCopy.MAIN_22017C43B345)
			return
	else:
		if not Typed.equal(room.get("api_version"), 2) or ChapterRegistry.resolve(room).is_empty():
			host.turn_notifications.acknowledge_route(route.event_id)
			host._toast(PlayerCopy.MAIN_F4F6AF4420A6)
			return
		host.ensure_relay_session()
		if host.relay_session.capabilities.is_empty():
			var loaded: bool = await host.relay_session.load_lobby()
			if not _route_current(route, context): return
			if not loaded:
				route_retry_ms = Time.get_ticks_msec() + 15000
				host._toast(PlayerCopy.MAIN_571E92F64ED1)
				return
		var opened: bool = await host.relay_session.open_room(route.room_id)
		await host.turn_notifications.refresh_pending_route()
		if not _route_current(route, context): return
		if not opened:
			route_retry_ms = Time.get_ticks_msec() + 15000
			host._toast(PlayerCopy.MAIN_BE8E691311EE)
			return
		host._enter_online_relay()
	host.turn_notifications.acknowledge_route(route.event_id)

func _owned_room(room: Variant, route: Dictionary) -> bool:
	return room is Dictionary and Typed.equal(room.get("room_id"), route.room_id) and host.api.player_id in [room.get("host_id"), room.get("guest_id")] and TurnNotifications._integer(room.get("revision")) and int(room.revision) >= int(route.revision)

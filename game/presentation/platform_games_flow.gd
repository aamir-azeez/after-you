extends Node
## Play Games / Game Center for Main: the Settings row's detail, the "which progress stays" choice,
## and Main's side of the PlatformGames service (presentation only; the rules live in
## services/platform_games/). No platform branch here: names and states come from the service.
##
## Host contract (read at call time): api, secrets, saves, home_keepsakes, config, mode,
## identity_read_state, IdentityReadState, identity_data, identity_loading, identity_busy,
## identity_restart_required, pending_recovery, deleted_identity_owner, _await_secret,
## _apply_settings, _toast, _tester_checks_enabled, tester_access, store_flow, settings_flow,
## account_flow (copy_recovery_details, _finish_identity_change).
##
## Restoring an identity uses the recovery code's safety: the next device token and recovery
## code are made here, kept in secure storage before the request, and the server only rotates
## to them. A lost answer is retried with the same proposal and a fresh platform proof.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const SettingsKit = preload("res://presentation/settings_kit.gd")
const TouchInput = preload("res://presentation/touch_input.gd")
const PlatformGames = preload("res://services/platform_games/platform_games.gd")
const LinkClient = preload("res://services/platform_games/platform_link_client.gd")
const Sources = preload("res://services/platform_games/cloud_save_sources.gd")
const RecoveryDetails = preload("res://services/recovery_details.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const Typed = preload("res://services/typed_values.gd")

const PENDING_SECRET := "platform_restore_pending"
const WEB_CLIENT_ID := "^[0-9]{6,20}-[a-z0-9]{8,64}\\.apps\\.googleusercontent\\.com$"

var host: Node
## Tests set this; production finds /root/PlatformGames.
var service: Node
var _account: Account
var _detail: WeakRef = weakref(null)
## The identity whose recovery details this flow saw copied: "Use the linked one" waits for it,
## so the friend code this phone leaves behind is never lost.
var _copied_player := ""
var _copy_busy := false
var _offer_modal: Control
var _offer_retry := false

func _init(main: Node = null) -> void:
	host = main

func games() -> Node:
	if service == null and host != null and host.is_inside_tree(): service = PlatformGames.shared(host.get_tree())
	return service

## Main is ready: hand the service what it needs, and count the moment as a progress point
## (Main starts again after every solo chapter).
func attach() -> void:
	var platform := games()
	if platform == null: return
	if _account == null: _account = Account.new(self)
	platform.attach(_account)
	if not platform.changed.is_connected(_on_changed): platform.changed.connect(_on_changed)
	if not platform.notice.is_connected(_on_notice): platform.notice.connect(_on_notice)
	if host.settings_flow.has_signal("closed") and not host.settings_flow.closed.is_connected(note_progress): host.settings_flow.closed.connect(note_progress)
	platform.note_progress()
	_maybe_offer()

func detach() -> void:
	var platform := games()
	if platform == null or _account == null: return
	platform.detach(_account)
	if platform.changed.is_connected(_on_changed): platform.changed.disconnect(_on_changed)
	if platform.notice.is_connected(_on_notice): platform.notice.disconnect(_on_notice)

func note_progress() -> void:
	var platform := games()
	if platform != null: platform.note_progress()

## The identity was erased: the server dropped its links; drop this phone's record too.
func forget_identity() -> void:
	var platform := games()
	if platform != null: platform.forget_identity()

func _on_notice(text: String) -> void:
	if host != null and is_instance_valid(host): host._toast(text)

func _on_changed() -> void:
	if host == null or not is_instance_valid(host): return
	host.settings_flow.refresh()
	_maybe_offer()
	var detail: Variant = _detail.get_ref()
	if detail is VBoxContainer and is_instance_valid(detail) and detail.visible:
		TouchInput.redraw_when_released(detail, func() -> bool: return is_instance_valid(detail) and detail.visible, func() -> void: _fill(detail))

# ---- Settings ------------------------------------------------------------------------------

func offered() -> bool:
	var platform := games()
	return platform != null and platform.offered()

# ---- "Use your friend code from your other phone?" ----------------------------------------

## One tap before a friend code comes to a phone that has none. Shown only at Home with no other
## pop-up open (it waits for one), once a session: closing it in any way counts as "Not now".
func _maybe_offer() -> void:
	var platform := games()
	if platform == null: return
	if not platform.offer_pending():
		# The offer went away (a friend code was made, another account signed in): no stale question.
		if is_instance_valid(_offer_modal) and platform.link_state != PlatformGames.LINK_OFFER: _offer_modal.close(false)
		return
	if is_instance_valid(_offer_modal): return
	if host.mode != "home" or _modal_open() or is_instance_valid(host.get("_chapter_opening")) or host.get("application_backgrounded") == true:
		if not _offer_retry:
			_offer_retry = true
			await host.get_tree().create_timer(1.0).timeout
			_offer_retry = false
			if is_instance_valid(host): _maybe_offer()
		return
	_offer_modal = InGameModal.open(host.ui, "PlatformRestoreModal", PlayerCopy.PLATFORM_GAMES_OFFER_TITLE)
	var accepted := [false]
	_offer_modal.add_actions(PlayerCopy.PLATFORM_GAMES_USE_IT, func() -> void:
		accepted[0] = true
		_offer_modal.close()
		platform.accept_offer(), PlayerCopy.PLATFORM_GAMES_NOT_NOW)
	_offer_modal.closed.connect(func() -> void:
		if not accepted[0]: platform.decline_offer())

func _modal_open() -> bool:
	for child: Node in host.ui.get_children():
		if child.get_script() == InGameModal and not child.is_queued_for_deletion(): return true
	return false

func label() -> String:
	var platform := games()
	return platform.display_name() if platform != null else ""

func status_line() -> String:
	var platform := games()
	return platform.status_line() if platform != null else ""

func enabled() -> bool:
	var platform := games()
	return platform != null and not platform.busy

## The row's inline detail: what can be done now, redrawn as the state changes.
func toggle_detail(detail: VBoxContainer, _row: Control) -> void:
	if detail.visible:
		_set_items(detail, [])
		return
	_detail = weakref(detail)
	_fill(detail)

func _fill(detail: VBoxContainer) -> void:
	var platform := games()
	if platform == null or not is_instance_valid(detail): return
	var items: Array = []
	if platform.busy:
		items.append(SettingsKit.detail_text(PlayerCopy.PLATFORM_GAMES_CHECKING))
	elif not platform.signed_in():
		items.append(SettingsKit.detail_text(PlayerCopy.PLATFORM_GAMES_SIGN_IN_NOTE))
		items.append(SettingsKit.detail_button(PlayerCopy.PLATFORM_GAMES_SIGN_IN, platform.sign_in_now))
	elif platform.link_state == PlatformGames.LINK_CONFLICT:
		items.append(SettingsKit.detail_text(PlayerCopy.PLATFORM_GAMES_CHOOSE_TITLE, true))
		items.append(SettingsKit.detail_text(PlayerCopy.PLATFORM_GAMES_CHOOSE_BODY))
		items.append(SettingsKit.detail_button(PlayerCopy.PLATFORM_GAMES_KEEP_THIS, platform.keep_this_phone))
		items.append(SettingsKit.detail_text(PlayerCopy.PLATFORM_GAMES_USE_LINKED_NOTE))
		items.append(SettingsKit.detail_button(PlayerCopy.PLATFORM_GAMES_COPY_RECOVERY, _copy_recovery))
		var use_linked := SettingsKit.detail_button(PlayerCopy.PLATFORM_GAMES_USE_LINKED, platform.use_linked_progress)
		use_linked.disabled = not recovery_copied()
		items.append(use_linked)
	elif platform.link_state == PlatformGames.LINK_OTHER:
		items.append(SettingsKit.detail_text(PlayerCopy.PLATFORM_GAMES_OTHER_NOTE))
		items.append(SettingsKit.detail_button(PlayerCopy.PLATFORM_GAMES_USE_HERE, platform.keep_this_phone))
	elif platform.link_state == PlatformGames.LINK_OFFER:
		items.append(SettingsKit.detail_text(PlayerCopy.PLATFORM_GAMES_OFFER_TITLE, true))
		items.append(SettingsKit.detail_button(PlayerCopy.PLATFORM_GAMES_USE_IT, platform.accept_offer))
	elif platform.linked():
		items.append(SettingsKit.detail_text(PlayerCopy.PLATFORM_GAMES_UNLINK_NOTE))
		items.append(SettingsKit.detail_button(PlayerCopy.PLATFORM_GAMES_UNLINK, platform.unlink))
	elif platform.link_state == PlatformGames.LINK_ERROR:
		items.append(SettingsKit.detail_button(PlayerCopy.PLATFORM_GAMES_TRY_AGAIN, platform.retry))
	elif platform.link_state == PlatformGames.LINK_NONE:
		# Unlinked, or nothing found earlier: link this phone's friend code, or look for one again.
		items.append(SettingsKit.detail_button(PlayerCopy.PLATFORM_GAMES_LINK if identity_state() == "ready" else PlayerCopy.PLATFORM_GAMES_TRY_AGAIN, platform.retry))
	_set_items(detail, items)

static func _set_items(detail: VBoxContainer, items: Array) -> void:
	for child: Node in detail.get_children():
		detail.remove_child(child)
		child.queue_free()
	for item: Control in items: detail.add_child(item)
	detail.visible = not items.is_empty()

func recovery_copied() -> bool:
	return host != null and not _copied_player.is_empty() and _copied_player == str(host.identity_data.get("player_id", ""))

## Copies this phone's recovery details; only a confirmed copy unlocks "Use the linked one".
func _copy_recovery() -> void:
	if _copy_busy: return
	var player := str(host.identity_data.get("player_id", ""))
	var code := str(host.identity_data.get("recovery_code", ""))
	if not RecoveryDetails.field_matches(player, RecoveryDetails.ID_PATTERN) or not RecoveryDetails.field_matches(code, RecoveryDetails.SECRET_PATTERN):
		host._toast(PlayerCopy.MAIN_A77FFD68F5E6)
		return
	_copy_busy = true
	var result: Dictionary = await host._await_secret(host.secrets.copy_recovery(player, code))
	_copy_busy = false
	if result.get("ok", false) and Typed.equal(result.get("payload", {}).get("copied"), true):
		_copied_player = player
		host._toast(PlayerCopy.MAIN_B3745871EB1C)
		_on_changed()
	else:
		host._toast(PlayerCopy.MAIN_A77FFD68F5E6)

# ---- Main's side of the service ------------------------------------------------------------

func identity_state() -> String:
	if host == null or not is_instance_valid(host): return "busy"
	if host.identity_loading or host.identity_busy or not host.pending_recovery.is_empty() or not str(host.deleted_identity_owner).is_empty() or host.identity_restart_required:
		return "busy"
	if host.identity_read_state == host.IdentityReadState.MISSING and host.api.player_id.is_empty(): return "missing"
	if host.identity_read_state == host.IdentityReadState.LOADED and not host.api.device_token.is_empty(): return "ready"
	# Loading, or an identity this phone could not read: never create or replace one here.
	return "busy" if host.identity_read_state == host.IdentityReadState.LOADING else "blocked"

## The build's public OAuth web client id, used only before this phone has an identity.
func config_web_client_id() -> String:
	var value := str(host.config.get("play_games_web_client_id", "")) if host != null else ""
	return value if RegEx.create_from_string(WEB_CLIENT_ID).search(value) != null else ""

## Moves the linked identity to this phone. restart: this phone had its own identity, so the app
## restarts into the restored one like a recovery; otherwise (no identity yet) it is adopted now.
func restore_identity(provider: String, get_credential: Callable, restart: bool) -> Dictionary:
	if host.identity_busy or host.identity_loading: return {"ok": false, "code": "busy"}
	host.identity_busy = true
	var pending := await _pending(provider)
	if pending.is_empty():
		host.identity_busy = false
		return {"ok": false, "code": "storage"}
	var credential: Dictionary = await get_credential.call()
	if not credential.get("ok", false):
		host.identity_busy = false
		return credential
	var answer: Dictionary = await LinkClient.new(host.api).restore(provider, credential.credential, pending)
	if not answer.get("ok", false):
		host.identity_busy = false
		if int(answer.get("status", 0)) in [401, 404]: await host._await_secret(host.secrets.remove_secret(PENDING_SECRET))
		return answer
	var identity := {"player_id": str(answer.player_id), "device_token": str(pending.next_device_token), "recovery_code": str(pending.next_recovery_code)}
	if restart and host._tester_checks_enabled() and is_instance_valid(host.tester_access) and not host.api.player_id.is_empty() and not host.api.device_token.is_empty():
		var removed_tester: Dictionary = await host.tester_access.erase_binding(host.api.base_url, host.api.player_id, host.api.device_token)
		if not removed_tester.get("ok", false):
			host.identity_busy = false
			return {"ok": false, "code": "storage"}
	var persisted: Dictionary = await host._await_secret(host.secrets.put_secret("player_identity", JSON.stringify(identity)))
	if not persisted.get("ok", false) or not Typed.equal(persisted.get("payload", {}).get("stored"), true):
		# The pending proposal stays: the next try sends it again and the server answers the same.
		host.identity_busy = false
		return {"ok": false, "code": "storage"}
	await host._await_secret(host.secrets.remove_secret(PENDING_SECRET))
	host.identity_data = identity
	host.identity_busy = false
	if restart:
		host.account_flow._finish_identity_change()
	else:
		host.identity_read_state = host.IdentityReadState.LOADED
		host.api.player_id = identity.player_id
		host.api.device_token = identity.device_token
		host.store_flow.configure_purchases()
		host.settings_flow.refresh()
	return {"ok": true, "player_id": identity.player_id}

## The saved proposal for this provider, or a new one saved before use. {} when storage fails.
func _pending(provider: String) -> Dictionary:
	var read: Dictionary = await host._await_secret(host.secrets.get_secret(PENDING_SECRET))
	var payload: Variant = read.get("payload")
	if read.get("ok", false) and payload is Dictionary and payload.get("found") == true and payload.get("value") is String:
		var saved: Variant = JSON.parse_string(payload.value)
		if _valid_pending(saved, provider): return saved
	var pending := {"schema_version": 1, "provider": provider, "idempotency_key": RoomsApi.new_key(),
		"next_device_token": RecoveryDetails.new_secret(), "next_recovery_code": RecoveryDetails.new_secret()}
	var stored: Dictionary = await host._await_secret(host.secrets.put_secret(PENDING_SECRET, JSON.stringify(pending)))
	return pending if stored.get("ok", false) and Typed.equal(stored.get("payload", {}).get("stored"), true) else {}

static func _valid_pending(value: Variant, provider: String) -> bool:
	return value is Dictionary and value.size() == 5 and Typed.equal(value.get("schema_version"), 1) and Typed.equal(value.get("provider"), provider) \
		and value.get("idempotency_key") is String and value.get("next_device_token") is String and value.get("next_recovery_code") is String \
		and RecoveryDetails.field_matches(value.next_device_token, RecoveryDetails.SECRET_PATTERN) and RecoveryDetails.field_matches(value.next_recovery_code, RecoveryDetails.SECRET_PATTERN) \
		and value.next_device_token != value.next_recovery_code

## The player said yes earlier and the answer was lost: a saved proposal for this provider exists.
func has_pending_restore(provider: String) -> bool:
	var read: Dictionary = await host._await_secret(host.secrets.get_secret(PENDING_SECRET))
	var payload: Variant = read.get("payload")
	if not read.get("ok", false) or not payload is Dictionary or payload.get("found") != true or not payload.get("value") is String: return false
	return _valid_pending(JSON.parse_string(payload.value), provider)

func cloud_sources() -> RefCounted:
	var platform := games()
	if platform == null or platform.state == null: return null
	return Sources.new(host, platform.state)

## What the service holds of Main: this flow, reached weakly so a freed Main is never kept alive.
class Account extends RefCounted:
	var _flow: WeakRef
	func _init(flow: Node) -> void: _flow = weakref(flow)
	func _flow_node() -> Node:
		var flow: Variant = _flow.get_ref()
		return flow if flow is Node and is_instance_valid(flow) and flow.host != null and is_instance_valid(flow.host) else null
	func api() -> Node:
		var flow := _flow_node()
		return flow.host.api if flow != null else null
	func identity_state() -> String:
		var flow := _flow_node()
		return flow.identity_state() if flow != null else "busy"
	func player_id() -> String:
		var flow := _flow_node()
		return str(flow.host.api.player_id) if flow != null else ""
	func recovery_code() -> String:
		var flow := _flow_node()
		return str(flow.host.identity_data.get("recovery_code", "")) if flow != null else ""
	func config_web_client_id() -> String:
		var flow := _flow_node()
		return flow.config_web_client_id() if flow != null else ""
	func restore_identity(provider: String, get_credential: Callable, restart: bool) -> Dictionary:
		var flow := _flow_node()
		if flow == null: return {"ok": false, "code": "busy"}
		return await flow.restore_identity(provider, get_credential, restart)
	func cloud_sources() -> RefCounted:
		var flow := _flow_node()
		return flow.cloud_sources() if flow != null else null
	func has_pending_restore(provider: String) -> bool:
		var flow := _flow_node()
		if flow == null: return false
		return await flow.has_pending_restore(provider)

extends Node
## Account & recovery: what Settings > Account & recovery shows and does
## inline (recovery details, the hosting access check, Photo transfer and
## Reports), identity recovery and online identity deletion with its device
## cleanup.
##
## Main hosts it as a child and keeps the identity itself. The flow reads and
## writes Main's identity state and services through this host contract (read
## at call time, so Main or a test can swap a service):
## - services: api, secrets, saves, purchases, tester_access, relay_session,
##   hosting_notification_preferences, friend_nicknames, config, store_flow
## - identity: IdentityReadState, identity_read_state, identity_data,
##   identity_loading, identity_busy, identity_restart_required,
##   pending_recovery, deleted_identity_owner, _ensure_identity,
##   _load_saved_identity, _invalidate_relay_identity, _await_secret,
##   _tester_checks_enabled, _play_store_enabled
## - screen: mode, running
## - settings_flow (flow to flow): showing, show_settings, detail, view_token,
##   view_current. Its rows table (presentation/settings_rows.gd) calls this
##   flow's panel_state and inline actions.
## - card kit: _card, _label, _paragraph, _button, _back_button, _toast
## - node: get_tree (frames and Close After You), add_child (the photo cleanup
##   node stays Main's child)
## Its own screens (recovery, deletion, cleanup) go back to Settings through
## settings_requested, which Main opens on Account & recovery.
## Main asks holds_back() before Android Back or Escape.
##
## Recovery codes and device tokens never reach a log or the ordinary save;
## their formats live in RecoveryDetails.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const RecoveryDetails = preload("res://services/recovery_details.gd")
const DeletedPhotos = preload("res://services/deleted_identity_photo_cleanup.gd")
const DeletedCaches = preload("res://services/deleted_identity_cache_cleanup.gd")
const DeletedAck = preload("res://services/deleted_identity_ack.gd")
const Typed = preload("res://services/typed_values.gd")
const SettingsKit = preload("res://presentation/settings_kit.gd")
const CREAM := Color("eceddb")
const MUTED := Color("9dbeb4")
## The Settings category this flow's rows live in (settings_rows.gd ACCOUNT).
const SETTINGS_CATEGORY := "account"
## Main's mode on each screen of this flow. "account" is the delete confirmation.
const MODE_ACCOUNT := "account"
const MODE_ACCOUNT_LOADING := "account_loading"
const MODE_RECOVERY_DETAILS := "recovery_details"
const MODE_RECOVERY_FORM := "recovery_form"
const MODE_RECOVERY := "recovery"
const MODE_IDENTITY_DELETING := "identity_deleting"
const MODE_ACCOUNT_CLEANUP := "account_cleanup"

signal settings_requested
signal photo_transfer_requested
signal safety_requested

var host: Node
var recovery_replace_allowed := false
var recovery_copy_busy := false
var recovery_acknowledged := false
var deletion_cleanup_busy := false
var deletion_photo_cleanup: Node
var deletion_cache_cleanup: RefCounted

func _init(main: Node = null) -> void:
	host = main

## Deletion and its device cleanup cannot be left with Back.
func holds_back() -> bool:
	return host.mode == MODE_IDENTITY_DELETING or deletion_cleanup_busy

## Which Account & recovery rows Settings shows: "cleanup" (a deleted
## identity's device cleanup is unfinished), "pending" (a recovery waits),
## "restart" (the app must reopen), "ready" (an identity), "missing" (none
## yet), "unread" (a saved one could not be read) or "offline" (no service).
func panel_state() -> String:
	if host.saves.data.has(DeletedPhotos.MARKER_KEY) or not host.deleted_identity_owner.is_empty(): return "cleanup"
	if not host.pending_recovery.is_empty(): return "pending"
	if host.identity_restart_required: return "restart"
	if not host.api.player_id.is_empty(): return "ready"
	if host.api.configured() and host.secrets.is_available():
		return "missing" if host.identity_read_state == host.IdentityReadState.MISSING else "unread"
	return "offline"

## The saved identity has not been read yet (cleanup offers to check it).
func identity_unread() -> bool:
	return host.identity_read_state not in [host.IdentityReadState.LOADED, host.IdentityReadState.MISSING] and not host.identity_loading

func _back_to_account() -> void:
	settings_requested.emit()

func create_identity() -> void:
	if await host._ensure_identity(): _back_to_account()

func open_photo_transfer() -> void:
	photo_transfer_requested.emit()

func open_safety() -> void:
	safety_requested.emit()

func retry_saved_identity() -> void:
	host._load_saved_identity()
	host.mode=MODE_ACCOUNT_LOADING
	var card: VBoxContainer = host._card()
	card.add_child(host._label(PlayerCopy.MAIN_199D5695599E,30,CREAM,true))
	card.add_child(host._back_button("Back",_back_to_account,false))
	var deadline := Time.get_ticks_msec()+10000
	while host.identity_loading and Time.get_ticks_msec()<deadline:
		await host.get_tree().process_frame
	if host.mode==MODE_ACCOUNT_LOADING:
		_back_to_account()

## The hosting access row's inline box, with Settings opened on Account &
## recovery first if it is not on show; null when that row is not shown.
func _hosting_detail() -> VBoxContainer:
	if not host.settings_flow.showing(SETTINGS_CATEGORY): host.settings_flow.show_settings(SETTINGS_CATEGORY)
	return host.settings_flow.detail("hosting_access")

static func _fill(detail: VBoxContainer, items: Array) -> void:
	for child: Node in detail.get_children():
		detail.remove_child(child)
		child.queue_free()
	for item: Control in items: detail.add_child(item)
	detail.visible = not items.is_empty()

func check_hosting_access() -> void:
	# Checking an existing purchase must not create or replace an identity.
	if host.identity_restart_required or host.identity_loading or host.identity_busy:
		host._toast(PlayerCopy.MAIN_3A0D8776E06F)
		return
	if host.api.player_id.is_empty() or host.api.device_token.is_empty():
		host._toast(PlayerCopy.MAIN_F64C9883094A)
		return
	var detail := _hosting_detail()
	if detail == null: return
	_fill(detail, [SettingsKit.detail_text(PlayerCopy.SETTINGS_HOSTING_CHECKING, true), SettingsKit.detail_text(PlayerCopy.MAIN_65352AE6EE21)])
	var view: int = host.settings_flow.view_token()
	var player_id: String=host.api.player_id
	var response: Dictionary=await host.api.request_json(HTTPClient.METHOD_GET,"/v1/entitlement")
	# A late response must not pull the player out of another screen or apply
	# the previous identity's purchase result after account recovery.
	if not host.settings_flow.view_current(view) or player_id!=host.api.player_id or host.identity_restart_required:
		return
	show_hosting_access(response)

## The server's answer, under the hosting access row.
func show_hosting_access(response: Dictionary) -> void:
	var detail := _hosting_detail()
	if detail == null: return
	var items: Array = []
	var data: Variant=response.get("data")
	var verified: bool=response.get("ok",false)==true and data is Dictionary and Typed.equal(data.get("status"), "verified") and data.get("full_journey") is bool
	var elsewhere := false
	if verified and data.full_journey:
		items.append(SettingsKit.detail_text("Full Journey confirmed",true))
		items.append(SettingsKit.detail_text(PlayerCopy.MAIN_632FFB4BA5D4))
	elif verified:
		items.append(SettingsKit.detail_text("Introductory hosting",true))
		if Typed.equal(host.config.get("purchase_mode"), "test_store"):
			items.append(SettingsKit.detail_text(PlayerCopy.MAIN_FAD34E850ED9))
			if PlatformSupport.tester_code_offered(): items.append(SettingsKit.detail_button("Tester code",host.store_flow.show_tester_access))
		elif host._play_store_enabled():
			items.append(SettingsKit.detail_text(PlayerCopy.MAIN_5DCCD071AE03))
		else:
			elsewhere = true
	else:
		items.append(SettingsKit.detail_text(PlayerCopy.MAIN_618916283742,true))
		items.append(SettingsKit.detail_text(PlayerCopy.MAIN_AA2B015D5D95))
	# Server verification describes hosting only. It never changes or clears
	# the separate RevenueCat SDK entitlement used for local solo play.
	_fill(detail, items)
	if elsewhere:
		host.store_flow.add_store_elsewhere(detail)
		for button: Button in detail.find_children("*","Button",true,false): SettingsKit.quiet_button(button)
		detail.visible = detail.get_child_count() > 0

## The recovery details row: shows the identity and its recovery code in
## place, with Copy; a second tap hides them again.
func toggle_recovery_details(detail: VBoxContainer, row: Control) -> void:
	var label := row.find_child("Label", true, false) as Label
	if detail.visible:
		_fill(detail, [])
		if label != null: label.text = PlayerCopy.SETTINGS_RECOVERY_DETAILS
		return
	var player := str(host.identity_data.get("player_id",""))
	var code := str(host.identity_data.get("recovery_code",""))
	var items: Array = [SettingsKit.detail_text(PlayerCopy.MAIN_4E6353EBBDB9,true), SettingsKit.detail_text(PlayerCopy.MAIN_B1B6CAA8087E)]
	for entry: Array in [["Identity",player],["Recovery code",code]]:
		items.append(SettingsKit.detail_text(entry[0]))
		items.append(SettingsKit.detail_field(entry[1]))
	var copy := SettingsKit.detail_button("Copy recovery details",func(): copy_recovery_details(player,code))
	copy.disabled = not _copyable(player, code)
	items.append(copy)
	_fill(detail, items)
	if label != null: label.text = PlayerCopy.SETTINGS_RECOVERY_DETAILS_HIDE

static func _copyable(player: String, code: String) -> bool:
	return RecoveryDetails.field_matches(player,RecoveryDetails.ID_PATTERN) and RecoveryDetails.field_matches(code,RecoveryDetails.SECRET_PATTERN)

## Recovery details on a screen of their own, for the recovery steps that
## happen outside Settings (a restart, a storage failure, a new identity).
func show_recovery_details() -> void:
	host.mode=MODE_RECOVERY_DETAILS
	var card: VBoxContainer = host._card(680)
	card.add_child(host._label(PlayerCopy.MAIN_4E6353EBBDB9,32,CREAM,true))
	card.add_child(host._paragraph(PlayerCopy.MAIN_B1B6CAA8087E,580))
	for entry: Array in [["Identity",str(host.identity_data.get("player_id",""))],["Recovery code",str(host.identity_data.get("recovery_code",""))]]:
		card.add_child(host._label(entry[0],18,MUTED))
		var field := LineEdit.new()
		field.text=entry[1]
		field.editable=false
		field.custom_minimum_size=Vector2(580,48)
		card.add_child(field)
	var player := str(host.identity_data.get("player_id",""))
	var code := str(host.identity_data.get("recovery_code",""))
	var copy: Button = host._button("Copy recovery details",func(): copy_recovery_details(player,code))
	copy.disabled=not _copyable(player,code)
	card.add_child(copy)
	card.add_child(host._back_button("Back",_back_to_account,false))

func copy_recovery_details(player: String, code: String) -> void:
	if recovery_copy_busy:
		return
	if host.identity_busy or (not host.pending_recovery.is_empty() and not _can_copy_acknowledged_recovery()) or player!=host.identity_data.get("player_id","") or code!=host.identity_data.get("recovery_code","") or not RecoveryDetails.field_matches(player,RecoveryDetails.ID_PATTERN) or not RecoveryDetails.field_matches(code,RecoveryDetails.SECRET_PATTERN):
		host._toast(PlayerCopy.MAIN_6F5191162022)
		return
	recovery_copy_busy=true
	var result: Dictionary=await host._await_secret(host.secrets.copy_recovery(player,code))
	recovery_copy_busy=false
	if result.get("ok",false) and Typed.equal(result.get("payload",{}).get("copied"), true):
		host._toast(PlayerCopy.MAIN_B3745871EB1C)
	else:
		host._toast(PlayerCopy.MAIN_A77FFD68F5E6)

func _can_copy_acknowledged_recovery() -> bool:
	# If secure storage fails after the server confirms rotation, the new code
	# is already current. Let the player copy it from the recovery error screen.
	var request: Dictionary=host.pending_recovery.get("request",{})
	return recovery_acknowledged and not request.is_empty() and host.identity_data.get("player_id")==request.get("player_id") and host.identity_data.get("recovery_code")==request.get("next_recovery_code") and host.identity_data.get("device_token")==request.get("next_device_token")

func show_recovery_form() -> void:
	host.mode=MODE_RECOVERY_FORM
	var card: VBoxContainer = host._card()
	card.add_child(host._label("Welcome back.",34,CREAM,true))
	card.add_child(host._paragraph(PlayerCopy.MAIN_01C351256351))
	var player := LineEdit.new()
	player.name="RecoveryIdentity"
	player.placeholder_text="Identity"
	player.custom_minimum_size.y=48
	var code := LineEdit.new()
	code.name="RecoveryCode"
	code.placeholder_text="Recovery code"
	code.secret=true
	code.custom_minimum_size.y=48
	var status: Label = host._paragraph(PlayerCopy.MAIN_41C32AF5A224)
	status.name="RecoveryImportStatus"
	card.add_child(host._button("Paste recovery details",func(): import_recovery_details(DisplayServer.clipboard_get(),player,code,status),false))
	card.add_child(player)
	card.add_child(code)
	# Also accept the system Paste action in either field. Android may flatten
	# line breaks in a LineEdit; the local parser accepts that copied format.
	for field: LineEdit in [player,code]:
		field.text_changed.connect(func(text: String):
			if not RecoveryDetails.parse(text).is_empty():
				import_recovery_details(text,player,code,status)
		)
	card.add_child(status)
	card.add_child(host._button("Recover identity",func(): recover_identity(player.text.strip_edges(),code.text.strip_edges())))
	card.add_child(host._back_button("Cancel",_back_to_account,false))

func import_recovery_details(text: String, player: LineEdit, code: LineEdit, status: Label) -> void:
	var details: Dictionary=RecoveryDetails.parse(text)
	if details.is_empty():
		status.text=PlayerCopy.MAIN_B3DD2F6125BC
		return
	player.text=details.player_id
	code.text=details.recovery_code
	player.release_focus()
	code.release_focus()
	status.text=PlayerCopy.MAIN_06D48BA3672C

func recover_identity(player: String, code: String) -> void:
	if host.identity_loading:
		host._toast(PlayerCopy.MAIN_45D3B02F91EE)
		return
	if host.identity_busy:
		return
	# Empty fields get the same note as mistyped ones, so the tap is never silent.
	if not RecoveryDetails.field_matches(player,RecoveryDetails.ID_PATTERN) or not RecoveryDetails.field_matches(code,RecoveryDetails.SECRET_PATTERN):
		host._toast(PlayerCopy.MAIN_C1B99419085A)
		return
	if not host.pending_recovery.is_empty():
		var old: Dictionary=host.pending_recovery.request
		if old.player_id==player and old.recovery_code==code:
			await resume_pending_recovery()
			return
		if not recovery_replace_allowed:
			_show_pending_recovery(PlayerCopy.MAIN_0E6D79FAEEC9)
			return
	# The next credentials are generated locally, and their full proposal must
	# be secured before the server can invalidate the previous credentials.
	recovery_acknowledged=false
	host.pending_recovery={"schema_version":1,"request":{"player_id":player,"recovery_code":code,"idempotency_key":RoomsApi.new_key(),"next_device_token":RecoveryDetails.new_secret(),"next_recovery_code":RecoveryDetails.new_secret()}}
	recovery_replace_allowed=false
	await resume_pending_recovery()

func resume_pending_recovery() -> void:
	if host.identity_loading or host.identity_busy or not RecoveryDetails.valid_pending(host.pending_recovery):
		return
	host._invalidate_relay_identity()
	host.identity_busy=true
	host.identity_restart_required=true
	host.identity_read_state=host.IdentityReadState.RECOVERY_PENDING
	host.mode=MODE_RECOVERY
	var card: VBoxContainer = host._card()
	card.add_child(host._label("Finishing your recovery…",32,CREAM,true))
	card.add_child(host._paragraph(PlayerCopy.MAIN_B49D9361392F))
	var secured: Dictionary=await host._await_secret(host.secrets.put_secret("recovery_pending",JSON.stringify(host.pending_recovery)))
	if not secured.ok or not Typed.equal(secured.get("payload",{}).get("stored"), true):
		host.identity_busy=false
		_show_pending_recovery(PlayerCopy.MAIN_189E8206D026)
		return
	var request: Dictionary=host.pending_recovery.request.duplicate(true)
	var response: Dictionary=await host.api.request_json(HTTPClient.METHOD_POST,"/v1/identity/recover",request)
	var data: Variant=response.get("data")
	if not response.get("ok",false) or not data is Dictionary or not data.get("recovered") is bool or data.recovered!=true or not Typed.equal(data.get("player_id"), request.player_id):
		host.identity_busy=false
		recovery_replace_allowed=(response.get("status")==401 and response.get("code")=="invalid_recovery") or (response.get("status")==409 and response.get("code")=="recovery_request_mismatch")
		_show_pending_recovery(PlayerCopy.MAIN_BDE96F64E602 if recovery_replace_allowed else PlayerCopy.MAIN_3A8CB7C5D89F)
		return
	recovery_acknowledged=true
	host.identity_data={"player_id":request.player_id,"device_token":request.next_device_token,"recovery_code":request.next_recovery_code}
	host.purchases.customer_info={}
	await persist_recovered_identity()

func _show_pending_recovery(message: String) -> void:
	host.mode=MODE_RECOVERY
	var card: VBoxContainer = host._card()
	card.add_child(host._label("Recovery is waiting.",32,CREAM,true))
	card.add_child(host._paragraph(message))
	card.add_child(host._button("Retry saved recovery",resume_pending_recovery))
	if recovery_replace_allowed:
		card.add_child(host._button("Use a different recovery code",show_recovery_form,false))
	card.add_child(host._back_button("Back to account",_back_to_account,false))

func persist_recovered_identity() -> void:
	# The server has acknowledged recovery. Remove only the old local binding,
	# before replacing its encrypted identity; a retry still has its exact key.
	if host._tester_checks_enabled() and is_instance_valid(host.tester_access) and not host.api.player_id.is_empty() and not host.api.device_token.is_empty():
		var removed_tester: Dictionary = await host.tester_access.erase_binding(host.api.base_url, host.api.player_id, host.api.device_token)
		if not removed_tester.get("ok", false):
			host.identity_busy = false
			_show_recovery_storage_failure()
			return
	var persisted: Dictionary=await host._await_secret(host.secrets.put_secret("player_identity",JSON.stringify(host.identity_data)))
	if not persisted.ok or not Typed.equal(persisted.get("payload",{}).get("stored"), true):
		host.identity_busy=false
		_show_recovery_storage_failure()
		return
	var removed: Dictionary=await host._await_secret(host.secrets.remove_secret("recovery_pending"))
	host.identity_busy=false
	if not removed.ok or not Typed.equal(removed.get("payload",{}).get("removed"), true):
		_show_recovery_storage_failure()
		return
	host.pending_recovery={}
	recovery_replace_allowed=false
	_finish_identity_change()

func _show_recovery_storage_failure() -> void:
	var card: VBoxContainer = host._card()
	card.add_child(host._label(PlayerCopy.MAIN_4156CE133C4E,30,CREAM,true))
	card.add_child(host._paragraph(PlayerCopy.MAIN_2B7F40AEE179))
	card.add_child(host._button("Retry secure storage",retry_identity_storage))
	card.add_child(host._button("Show new recovery details",show_recovery_details,false))

func retry_identity_storage() -> void:
	if host.identity_busy or host.identity_data.is_empty():
		return
	host.identity_busy=true
	await persist_recovered_identity()

func _finish_identity_change() -> void:
	host.identity_read_state=host.IdentityReadState.LOADED
	host.identity_restart_required=true
	host.purchases.customer_info={}
	# Recovery is not proof of a pending turn's receipt. Keep its body/key so
	# reopening the same identity can reconcile it against the shared room.
	host.saves.update_values({"room":{}})
	var card: VBoxContainer = host._card()
	card.add_child(host._label(PlayerCopy.MAIN_983DDFD98433,32,CREAM,true))
	card.add_child(host._paragraph(PlayerCopy.MAIN_C93C27D9AB17 if PlatformSupport.tester_code_offered() else PlayerCopy.MAIN_C93C27D9AB17_NO_TESTER))
	card.add_child(host._button("Show new recovery details",show_recovery_details,false))
	card.add_child(host._button("Close After You",func(): host.get_tree().quit()))

func confirm_delete_identity(message: String="") -> void:
	if host.identity_busy or deletion_cleanup_busy: return
	host.running=false
	host.mode=MODE_ACCOUNT
	var card: VBoxContainer = host._card()
	card.add_child(host._label(PlayerCopy.MAIN_4335B260B3E1,30,CREAM,true))
	card.add_child(host._paragraph(PlayerCopy.MAIN_6FD20F7D08FA))
	if not message.is_empty(): card.add_child(host._paragraph(message))
	card.add_child(host._button("Delete identity and shared rooms",delete_identity))
	card.add_child(host._back_button("Keep my identity",_back_to_account,false))

func delete_identity() -> void:
	if host.identity_busy or not await host._ensure_identity():
		return
	host._invalidate_relay_identity()
	host.identity_busy = true
	host.running=false
	host.mode=MODE_IDENTITY_DELETING
	var card: VBoxContainer = host._card()
	card.add_child(host._label("Deleting online identity…",30,CREAM,true))
	var activity := ProgressBar.new()
	activity.name="IdentityDeletionActivity"
	activity.custom_minimum_size.y=14
	activity.show_percentage=false
	activity.indeterminate=not bool(host.saves.data.settings.get("reduced_motion",false))
	card.add_child(activity)
	var response: Dictionary=await host.api.request_json(HTTPClient.METHOD_DELETE,"/v1/identity")
	if not response.ok:
		host.identity_busy = false
		confirm_delete_identity(str(response.error))
		return
	# Only this positive response authorizes local deletion. A missing profile,
	# authentication failure, or ordinary identity recovery is not confirmation.
	host.deleted_identity_owner=host.api.player_id
	host.identity_restart_required=true
	await clear_deleted_identity()
	host.identity_busy = false

func clear_deleted_identity() -> void:
	if deletion_cleanup_busy:
		return
	var owner: String = host.deleted_identity_owner
	if host.saves.data.has(DeletedPhotos.MARKER_KEY):
		owner=DeletedPhotos.marker_owner(host.saves.data[DeletedPhotos.MARKER_KEY])
	if not DeletedPhotos.valid_owner(owner) or (not host.identity_data.is_empty() and not Typed.equal(host.identity_data.get("player_id"), owner)):
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_58F37D557118)
		return
	if host.identity_loading or host.identity_read_state not in [host.IdentityReadState.LOADED,host.IdentityReadState.MISSING]:
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_143D1D0DB2C5)
		return
	if not DeletedAck.permitted(host.saves, owner):
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_6D018CBB9D68)
		return
	deletion_cleanup_busy=true
	host.identity_restart_required=true
	host.deleted_identity_owner=owner
	# Owner-only tombstone survives a restart; credentials remain in Keystore.
	# Persist it before any destructive local action, including the native cache.
	if not host.saves.update_values({DeletedPhotos.MARKER_KEY:{"schema_version":1,"owner":owner}}):
		deletion_cleanup_busy=false
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_9C9B9DFD3CC2)
		return
	_show_deleted_identity_cleanup(PlayerCopy.MAIN_88E7AC6A1F3D,false)
	if not is_instance_valid(deletion_photo_cleanup):
		deletion_photo_cleanup=DeletedPhotos.new()
		if host.relay_session != null:
			deletion_photo_cleanup.store=host.relay_session.photo_store
		host.add_child(deletion_photo_cleanup)
	var photos: Dictionary=await deletion_photo_cleanup.clear_owner(owner)
	if not photos.get("ok",false):
		deletion_cleanup_busy=false
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_7EE42FB6B934)
		return
	if deletion_cache_cleanup == null: deletion_cache_cleanup = DeletedCaches.new()
	var caches: Dictionary = deletion_cache_cleanup.erase_owner(owner)
	if not caches.get("ok", false):
		deletion_cleanup_busy=false
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_35527882CDA5)
		return
	if not host.saves.update_values({"room":{}},["pending_turn","room_draft"]):
		deletion_cleanup_busy=false
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_949AD8CB8BF2)
		return
	if host._tester_checks_enabled() and is_instance_valid(host.tester_access) and not str(host.identity_data.get("device_token", "")).is_empty():
		var tester_removed: Dictionary = await host.tester_access.erase_binding(host.api.base_url, owner, str(host.identity_data.device_token))
		if not tester_removed.get("ok", false):
			deletion_cleanup_busy=false
			_show_deleted_identity_cleanup(PlayerCopy.MAIN_B71C70F56731)
			return
	var acknowledged: Dictionary = await DeletedAck.finish(host.api, host.saves, owner)
	if not acknowledged.get("ok", false):
		deletion_cleanup_busy=false
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_BCC9D85CF2C1)
		return
	if not host.hosting_notification_preferences.clear_owner(owner,host.api.base_url):
		deletion_cleanup_busy=false
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_3820D398892A)
		return
	var result: Dictionary=await host._await_secret(host.secrets.remove_secret("player_identity"))
	var removal: Variant=result.get("payload")
	if not result.get("ok",false) or not removal is Dictionary or removal.size()!=1 or not removal.get("removed") is bool or not removal.removed:
		deletion_cleanup_busy=false
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_3820D398892A)
		return
	host.identity_data={}
	host.friend_nicknames.clear_owner(owner, host.api.base_url)
	host.identity_read_state=host.IdentityReadState.MISSING
	host.api.player_id=""
	host.api.device_token=""
	host.identity_restart_required=true
	host.purchases.customer_info={}
	if not host.saves.update_values({},[DeletedPhotos.MARKER_KEY, DeletedAck.KEY]):
		deletion_cleanup_busy=false
		_show_deleted_identity_cleanup(PlayerCopy.MAIN_32A0D82E6871)
		return
	host.deleted_identity_owner=""
	deletion_cleanup_busy=false
	var card: VBoxContainer = host._card()
	card.add_child(host._label(PlayerCopy.MAIN_5367370EB8BE,30,CREAM,true))
	card.add_child(host._paragraph(PlayerCopy.MAIN_DB7ADD49F62D))
	card.add_child(host._button("Close After You",func(): host.get_tree().quit()))

func _show_deleted_identity_cleanup(message: String, retry: bool=true) -> void:
	host.running=false
	host.mode=MODE_ACCOUNT_CLEANUP
	var card: VBoxContainer = host._card()
	card.add_child(host._label("Finish device cleanup",30,CREAM,true))
	card.add_child(host._paragraph(message))
	if retry:
		card.add_child(host._button("Retry device cleanup",clear_deleted_identity))
		if host.identity_read_state not in [host.IdentityReadState.LOADED,host.IdentityReadState.MISSING] and not host.identity_loading:
			card.add_child(host._button("Check saved identity",retry_deleted_identity_read,false))
		card.add_child(host._back_button("Back",_back_to_account,false))

func retry_deleted_identity_read() -> void:
	if deletion_cleanup_busy or host.identity_loading:
		return
	# The durable marker still blocks online use while the ordinary encrypted
	# read retries. It cannot create an identity or authorize server deletion.
	host.identity_restart_required=false
	await retry_saved_identity()

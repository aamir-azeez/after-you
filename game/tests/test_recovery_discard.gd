extends SceneTree
## A saved identity recovery that cannot finish never traps the player. The
## server refused it (lost or used code), it never left the device, or it was
## saved in a form the server never accepts: each can be stopped after one
## warning, and the device then uses its own identity or a new anonymous one.
## A request that went unanswered may already have rotated the identity, so it
## can only be retried. Every stop survives a restart.

const Storage = preload("res://services/local_save.gd")
const Main = preload("res://main.gd")
const FakeApi = preload("res://tests/fake_rooms_api.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const AccountFlow = preload("res://presentation/account_flow.gd")
const LOST_PLAYER := "RRRRRRRRRRRRRRRRRRRRRR"
const LOST_CODE := "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"
const OTHER_CODE := "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
const NEW_PLAYER := "NNNNNNNNNNNNNNNNNNNNNN"
const NEW_DEVICE := "synthetic-new-device-token"
const NEW_CODE := "synthetic-new-recovery-code"
const REFUSED := {"ok":false,"status":401,"code":"invalid_recovery","error":"refused"}
const MISMATCH := {"ok":false,"status":409,"code":"recovery_request_mismatch","error":"mismatch"}

## Secure storage whose reads answer from what was written, so a restart sees
## exactly what the previous session left behind.
class StatefulSecrets:
	extends Node
	signal completed(id: String, operation: String, payload: Dictionary)
	signal failed(id: String, operation: String, code: String)
	var values: Dictionary = {}
	var calls: Array = []
	var fail_write_names: Array = []
	var fail_remove := false
	var fail_read := false
	func is_available() -> bool:
		return true
	func get_secret(name: String) -> String:
		var id := "read-%d" % calls.size()
		calls.append({"operation":"get","name":name})
		if fail_read:
			_fail.call_deferred(id,"get")
			return id
		var payload := {"found":true,"value":values[name]} if values.has(name) else {"found":false,"value":null}
		_emit.call_deferred(id,"get",payload)
		return id
	func put_secret(name: String, value: String) -> String:
		var id := "write-%d" % calls.size()
		calls.append({"operation":"put","name":name})
		if name in fail_write_names:
			_fail.call_deferred(id,"put")
		else:
			values[name]=value
			_emit.call_deferred(id,"put",{"stored":true})
		return id
	func remove_secret(name: String) -> String:
		var id := "remove-%d" % calls.size()
		calls.append({"operation":"remove","name":name})
		if fail_remove:
			_fail.call_deferred(id,"remove")
		else:
			values.erase(name)
			_emit.call_deferred(id,"remove",{"removed":true})
		return id
	func copy_recovery(_player: String, _code: String) -> String:
		return ""
	func removed(name: String) -> bool:
		return calls.any(func(call: Dictionary) -> bool: return call.operation=="remove" and call.name==name)
	func _emit(id: String, operation: String, payload: Dictionary) -> void:
		completed.emit(id,operation,payload)
	func _fail(id: String, operation: String) -> void:
		failed.emit(id,operation,"secure_storage_unavailable")

var checks := 0
var failures := 0
var path := ""

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL: "+description)

func _run() -> void:
	path="user://recovery-discard-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	var app := Main.new()
	app.saves=Storage.new(path)
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.config["revenuecat_public_key"]=""
	var api := FakeApi.new()
	app.add_child(api)
	app.api=api
	var storage := StatefulSecrets.new()
	app.add_child(storage)
	app.secrets=storage
	storage.completed.connect(app._secret_completed)
	storage.failed.connect(app._secret_failed)
	await process_frame
	await _test_lost_code_on_fresh_install(app,api,storage)
	await _test_stop_keeps_device_identity(app,api,storage)
	await _test_unanswered_request_cannot_be_stopped(app,api,storage)
	await _test_acknowledged_recovery_cannot_be_stopped(app,api,storage)
	await _test_failed_removal_keeps_everything(app,api,storage)
	await _test_unsent_proposal(app,api,storage)
	await _test_unusable_saved_request(app,api,storage)
	await _test_failed_pending_read(app,api,storage)
	app.queue_free()
	await process_frame
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	await create_timer(0.15).timeout
	print("AFTER YOU RECOVERY DISCARD: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

## A new session: memory starts empty and only secure storage carries over.
func _restart(app: Node, api: Node, storage: StatefulSecrets, values: Dictionary, read_fails := false) -> void:
	storage.values=values.duplicate(true)
	storage.calls.clear()
	storage.fail_write_names=[]
	storage.fail_remove=false
	storage.fail_read=read_fails
	app.pending_recovery={}
	app.pending_recovery_unusable=false
	app.recovery_read_failed=false
	app.account_flow.recovery_replace_allowed=false
	app.account_flow.recovery_unsent=false
	app.account_flow.recovery_stored_refused=false
	app.account_flow.recovery_acknowledged=false
	app.account_flow.recovery_discard_busy=false
	app.identity_restart_required=false
	app.identity_busy=false
	app.identity_loading=false
	app.identity_read_state=Main.IdentityReadState.UNCHECKED
	app.identity_request=""
	app.recovery_read_request=""
	app.identity_data={}
	api.player_id=""
	api.device_token=""
	api.calls.clear()
	api.responses.clear()
	app._load_saved_identity()
	while app.identity_loading: await process_frame

static func _new_identity() -> Dictionary:
	return {"ok":true,"status":201,"data":{"player_id":NEW_PLAYER,"device_token":NEW_DEVICE,"recovery_code":NEW_CODE}}

func _identity_posts(api: Node) -> int:
	return api.calls.filter(func(call: Dictionary) -> bool: return call.path=="/v1/identity" and call.method==HTTPClient.METHOD_POST).size()

func _test_lost_code_on_fresh_install(app: Node, api: Node, storage: StatefulSecrets) -> void:
	await _restart(app,api,storage,{})
	_check(app.identity_read_state==Main.IdentityReadState.MISSING,"A fresh install has no identity yet")
	api.responses=[REFUSED]
	await app.account_flow.recover_identity(LOST_PLAYER,LOST_CODE)
	_check(storage.values.has("recovery_pending") and app.mode==AccountFlow.MODE_RECOVERY and _find_label(app.overlay,"Recovery is waiting.")!=null,"A refused recovery code leaves a saved recovery waiting")
	_check(not await app._ensure_identity() and _identity_posts(api)==0,"The waiting recovery blocks a new identity (the reported dead end)")
	_check(_find_button(app.overlay,PlayerCopy.RECOVERY_DISCARD)!=null,"The refused recovery offers Stop this recovery")

	# After a restart the refusal is not known yet: Retry asks the server again.
	var saved: Dictionary=storage.values.duplicate(true)
	await _restart(app,api,storage,saved)
	_check(app.identity_read_state==Main.IdentityReadState.RECOVERY_PENDING and not app.account_flow.can_discard_recovery(),"After a restart the saved recovery waits again and is not dropped unasked")
	app.settings_flow.show_settings("account")
	_check(_find_button(app.overlay,PlayerCopy.SETTINGS_FINISH_RECOVERY)!=null and _find_button(app.overlay,PlayerCopy.RECOVERY_DISCARD)==null,"Settings offers Finish identity recovery until the server answers")
	api.responses=[REFUSED]
	await app.account_flow.resume_pending_recovery()
	_check(api.calls.size()==1 and _find_button(app.overlay,"Use a different recovery code")!=null and _find_button(app.overlay,PlayerCopy.RECOVERY_DISCARD)!=null,"The repeated refusal offers a different code or Stop this recovery")
	app.settings_flow.show_settings("account")
	_check(_find_button(app.overlay,PlayerCopy.RECOVERY_DISCARD)!=null,"Settings also offers Stop this recovery once the server refused it")

	app.account_flow.confirm_discard_recovery()
	_check(app.mode==AccountFlow.MODE_RECOVERY_DISCARD and _find_label(app.overlay,PlayerCopy.RECOVERY_DISCARD_TITLE)!=null and _find_paragraph(app.overlay,PlayerCopy.RECOVERY_DISCARD_WARNING),"Stopping warns once that rooms and friends stay with the other identity")
	_check(storage.values.has("recovery_pending") and not app.pending_recovery.is_empty(),"The warning alone changes nothing")
	api.responses=[_new_identity()]
	await app.account_flow.discard_pending_recovery()
	_check(not storage.values.has("recovery_pending") and app.pending_recovery.is_empty() and not app.account_flow.recovery_replace_allowed,"Stopping removes the saved recovery from secure storage and memory")
	_check(_identity_posts(api)==1 and api.player_id==NEW_PLAYER and app.identity_read_state==Main.IdentityReadState.LOADED and not app.identity_restart_required,"With no identity on the device, a new anonymous identity starts right away")
	_check(JSON.parse_string(storage.values.player_identity).player_id==NEW_PLAYER and app.mode!=AccountFlow.MODE_RECOVERY_DISCARD,"The new identity is stored and Settings opens again")
	_check(not JSON.stringify(app.saves.data).contains(LOST_CODE),"The recovery code never reaches the ordinary save")

	await _restart(app,api,storage,storage.values)
	_check(app.identity_read_state==Main.IdentityReadState.LOADED and app.pending_recovery.is_empty() and api.player_id==NEW_PLAYER and not app.identity_restart_required,"After a restart the stuck card stays gone and the new identity loads")
	_check(await app._ensure_identity() and _identity_posts(api)==0,"The new identity works for online play without another request")

func _test_stop_keeps_device_identity(app: Node, api: Node, storage: StatefulSecrets) -> void:
	var own := JSON.stringify({"player_id":"own-player","device_token":"own-synthetic-device-token","recovery_code":"own-synthetic-code"})
	await _restart(app,api,storage,{"player_identity":own})
	_check(app.identity_read_state==Main.IdentityReadState.LOADED and api.player_id=="own-player","The device has its own identity")
	api.responses=[MISMATCH]
	await app.account_flow.recover_identity(LOST_PLAYER,LOST_CODE)
	_check(_find_button(app.overlay,PlayerCopy.RECOVERY_DISCARD)!=null,"A code used by a different request can be stopped too")
	app.account_flow.confirm_discard_recovery()
	await app.account_flow.discard_pending_recovery()
	_check(storage.values.player_identity==own and not storage.values.has("recovery_pending"),"Stopping never touches the device's own stored identity")
	_check(api.player_id=="own-player" and app.identity_read_state==Main.IdentityReadState.LOADED and _identity_posts(api)==0 and not app.identity_restart_required,"The device goes back to its own identity without making a new one")
	await _restart(app,api,storage,storage.values)
	_check(api.player_id=="own-player" and app.pending_recovery.is_empty(),"After a restart the device's own identity loads")

func _test_unanswered_request_cannot_be_stopped(app: Node, api: Node, storage: StatefulSecrets) -> void:
	await _restart(app,api,storage,{})
	await app.account_flow.recover_identity(LOST_PLAYER,LOST_CODE)
	_check(api.calls.size()==1 and storage.values.has("recovery_pending"),"The request went out and no answer came back")
	_check(_find_button(app.overlay,"Retry saved recovery")!=null and _find_button(app.overlay,PlayerCopy.RECOVERY_DISCARD)==null and not app.account_flow.can_discard_recovery(),"An unanswered request may hold the only new credentials, so it offers Retry and no Stop")
	var saved: String=storage.values.recovery_pending
	app.account_flow.confirm_discard_recovery()
	await app.account_flow.discard_pending_recovery()
	_check(storage.values.get("recovery_pending")==saved and not app.pending_recovery.is_empty() and not storage.removed("recovery_pending"),"A direct stop call cannot drop an unanswered request")
	app.settings_flow.show_settings("account")
	_check(_find_button(app.overlay,PlayerCopy.RECOVERY_DISCARD)==null,"Settings does not offer Stop for an unanswered request")
	await _restart(app,api,storage,storage.values)
	_check(not app.account_flow.can_discard_recovery(),"Nor after a restart, before the server answers")
	api.responses=[REFUSED]
	await app.account_flow.resume_pending_recovery()
	_check(app.account_flow.can_discard_recovery(),"Once the server refuses it, the network failure has a way out")

func _test_acknowledged_recovery_cannot_be_stopped(app: Node, api: Node, storage: StatefulSecrets) -> void:
	await _restart(app,api,storage,{})
	storage.fail_write_names=["player_identity"]
	api.responses=[{"ok":true,"data":{"player_id":LOST_PLAYER,"recovered":true}}]
	await app.account_flow.recover_identity(LOST_PLAYER,LOST_CODE)
	_check(app.account_flow.recovery_acknowledged and storage.values.has("recovery_pending"),"The server recovered the identity but the device could not store it")
	_check(not app.account_flow.can_discard_recovery() and _find_button(app.overlay,PlayerCopy.RECOVERY_DISCARD)==null and _find_button(app.overlay,"Show new recovery details")!=null,"An acknowledged recovery can never be stopped; its new details stay reachable")

func _test_failed_removal_keeps_everything(app: Node, api: Node, storage: StatefulSecrets) -> void:
	await _restart(app,api,storage,{})
	api.responses=[REFUSED]
	await app.account_flow.recover_identity(LOST_PLAYER,LOST_CODE)
	var saved: String=storage.values.recovery_pending
	storage.fail_remove=true
	app.account_flow.confirm_discard_recovery()
	await app.account_flow.discard_pending_recovery()
	_check(storage.values.get("recovery_pending")==saved and not app.pending_recovery.is_empty() and not app.identity_busy and _identity_posts(api)==0,"A failed removal keeps the saved recovery in memory and storage")
	_check(_find_paragraph(app.overlay,PlayerCopy.RECOVERY_DISCARD_FAILED) and _find_button(app.overlay,PlayerCopy.RECOVERY_DISCARD_CONFIRM)!=null and _find_button(app.overlay,"Back to account")!=null,"A failed removal says so and can be tried again")
	storage.fail_remove=false
	api.responses=[_new_identity()]
	await app.account_flow.discard_pending_recovery()
	_check(not storage.values.has("recovery_pending") and api.player_id==NEW_PLAYER,"Trying again finishes the stop")

func _test_unsent_proposal(app: Node, api: Node, storage: StatefulSecrets) -> void:
	await _restart(app,api,storage,{})
	storage.fail_write_names=["recovery_pending"]
	await app.account_flow.recover_identity(LOST_PLAYER,LOST_CODE)
	_check(api.calls.is_empty() and not storage.values.has("recovery_pending") and _find_button(app.overlay,PlayerCopy.RECOVERY_DISCARD)!=null,"A proposal that could not be stored was never sent and can be stopped")
	storage.fail_write_names=[]
	app.account_flow.confirm_discard_recovery()
	api.responses=[_new_identity()]
	await app.account_flow.discard_pending_recovery()
	_check(app.pending_recovery.is_empty() and not storage.removed("recovery_pending") and api.player_id==NEW_PLAYER,"Stopping an unsent proposal leaves storage as it was and starts a new identity")

	# A refused request still in storage under an unsent replacement goes too.
	var refused := {"schema_version":1,"request":{"player_id":LOST_PLAYER,"recovery_code":LOST_CODE,"idempotency_key":"older-request-key-0001","next_device_token":"D".repeat(43),"next_recovery_code":"E".repeat(43)}}
	await _restart(app,api,storage,{"recovery_pending":JSON.stringify(refused)})
	api.responses=[REFUSED]
	await app.account_flow.resume_pending_recovery()
	storage.fail_write_names=["recovery_pending"]
	await app.account_flow.recover_identity(LOST_PLAYER,OTHER_CODE)
	_check(api.calls.size()==1 and JSON.parse_string(storage.values.recovery_pending)==JSON.parse_string(JSON.stringify(refused)) and app.account_flow.can_discard_recovery(),"A replacement that could not be stored can be stopped")
	storage.fail_write_names=[]
	api.responses=[_new_identity()]
	await app.account_flow.discard_pending_recovery()
	_check(not storage.values.has("recovery_pending") and app.pending_recovery.is_empty() and api.player_id==NEW_PLAYER and app.identity_read_state==Main.IdentityReadState.LOADED,"Stopping removes the refused request under the unsent replacement")
	await _restart(app,api,storage,storage.values)
	_check(app.pending_recovery.is_empty() and api.player_id==NEW_PLAYER,"The refused request stays gone after a restart")

	# An unsent replacement over an unanswered request never removes that request.
	await _restart(app,api,storage,{})
	await app.account_flow.recover_identity(LOST_PLAYER,LOST_CODE)
	var unanswered: String=storage.values.recovery_pending
	await _restart(app,api,storage,storage.values)
	app.account_flow.recovery_replace_allowed=true
	storage.fail_write_names=["recovery_pending"]
	await app.account_flow.recover_identity(LOST_PLAYER,OTHER_CODE)
	storage.fail_write_names=[]
	await app.account_flow.discard_pending_recovery()
	_check(storage.values.get("recovery_pending")==unanswered and not storage.removed("recovery_pending") and app.identity_read_state==Main.IdentityReadState.RECOVERY_PENDING,"Only a refused stored request is removed; an unanswered one is found again")

func _test_unusable_saved_request(app: Node, api: Node, storage: StatefulSecrets) -> void:
	await _restart(app,api,storage,{"recovery_pending":"{ unusable saved request"})
	_check(app.identity_read_state==Main.IdentityReadState.FAILED and app.pending_recovery_unusable and not await app._ensure_identity(),"An unusable saved request blocks a new identity")
	app.settings_flow.show_settings("account")
	_check(_find_button(app.overlay,PlayerCopy.SETTINGS_CHECK_IDENTITY)!=null and _find_button(app.overlay,PlayerCopy.RECOVERY_DISCARD)!=null and _find_label(app.overlay,PlayerCopy.RECOVERY_DISCARD_UNUSABLE_NOTE)!=null,"Settings offers Stop this recovery for an unusable saved request")
	await app.account_flow.retry_saved_identity()
	_check(app.pending_recovery_unusable and storage.values.has("recovery_pending"),"Checking again finds the same unusable request")

	await _restart(app,api,storage,{"recovery_pending":"{ unusable saved request"})
	storage.fail_remove=true
	app.account_flow.confirm_discard_recovery()
	await app.account_flow.discard_pending_recovery()
	_check(storage.values.has("recovery_pending") and app.pending_recovery_unusable and _find_button(app.overlay,PlayerCopy.RECOVERY_DISCARD_CONFIRM)!=null,"A failed removal of an unusable request can be tried again")
	storage.fail_remove=false
	api.responses=[_new_identity()]
	await app.account_flow.discard_pending_recovery()
	_check(not storage.values.has("recovery_pending") and not app.pending_recovery_unusable and api.player_id==NEW_PLAYER,"Stopping removes the unusable request and starts a new identity")
	await _restart(app,api,storage,storage.values)
	_check(app.identity_read_state==Main.IdentityReadState.LOADED and not app.pending_recovery_unusable and api.player_id==NEW_PLAYER,"After a restart the unusable request stays gone")

	# A plain storage error is not an unusable request and is never removed.
	await _restart(app,api,storage,{})
	storage.fail_read=true
	app._load_saved_identity()
	while app.identity_loading: await process_frame
	_check(app.identity_read_state==Main.IdentityReadState.FAILED and not app.pending_recovery_unusable and not app.account_flow.can_discard_recovery(),"An unreadable store offers Check saved identity, not Stop")

## A saved recovery read that fails for a moment may hide an unanswered request
## holding the only new credentials: nothing may start a recovery over it.
func _test_failed_pending_read(app: Node, api: Node, storage: StatefulSecrets) -> void:
	await _restart(app,api,storage,{})
	await app.account_flow.recover_identity(LOST_PLAYER,LOST_CODE)
	var unanswered: String=storage.values.recovery_pending
	var own := JSON.stringify({"player_id":"own-player","device_token":"own-synthetic-device-token","recovery_code":"own-synthetic-code"})
	await _restart(app,api,storage,{"recovery_pending":unanswered,"player_identity":own},true)
	_check(app.identity_read_state==Main.IdentityReadState.FAILED and app.recovery_read_failed and app.pending_recovery.is_empty() and not app.account_flow.recovery_start_allowed(),"A failed saved recovery read blocks a new recovery")
	app.settings_flow.show_settings("account")
	_check(_find_button(app.overlay,PlayerCopy.SETTINGS_RECOVER)==null and _find_button(app.overlay,PlayerCopy.SETTINGS_CHECK_IDENTITY)!=null and _find_button(app.overlay,PlayerCopy.RECOVERY_DISCARD)==null,"Settings hides Recover and offers Check saved identity")
	_check(_find_label(app.overlay,PlayerCopy.UNREAD_CHECK_AGAIN)!=null and _find_label(app.overlay,PlayerCopy.MAIN_3E50EF2B7ECB)==null,"The note asks to check again without pointing to a hidden Recover row")
	storage.calls.clear()
	app.toast.text=""
	await app.account_flow.recover_identity(LOST_PLAYER,OTHER_CODE)
	_check(api.calls.is_empty() and storage.calls.is_empty() and storage.values.recovery_pending==unanswered and app.pending_recovery.is_empty() and app.toast.text==PlayerCopy.MAIN_45D3B02F91EE,"A direct recovery call cannot overwrite the unseen saved request")
	app.account_flow.confirm_discard_recovery()
	await app.account_flow.discard_pending_recovery()
	_check(storage.calls.is_empty() and storage.values.recovery_pending==unanswered and storage.values.player_identity==own,"A plain storage error never removes or replaces anything")
	storage.fail_read=false
	await app.account_flow.retry_saved_identity()
	_check(not app.recovery_read_failed and app.identity_read_state==Main.IdentityReadState.RECOVERY_PENDING and JSON.stringify(app.pending_recovery)==JSON.stringify(JSON.parse_string(unanswered)),"Checking again finds the saved request and it waits for its answer")
	app.settings_flow.show_settings("account")
	_check(_find_button(app.overlay,PlayerCopy.SETTINGS_FINISH_RECOVERY)!=null and _find_button(app.overlay,PlayerCopy.RECOVERY_DISCARD)==null,"The found request offers Finish identity recovery, not Stop")

	# With nothing saved, a later successful read brings Recover back.
	await _restart(app,api,storage,{},true)
	_check(app.recovery_read_failed and not app.account_flow.recovery_start_allowed(),"A failed read with nothing saved still blocks recovery until checked")
	storage.fail_read=false
	await app.account_flow.retry_saved_identity()
	_check(not app.recovery_read_failed and app.identity_read_state==Main.IdentityReadState.MISSING and app.account_flow.recovery_start_allowed(),"A read that finds nothing restores normal behaviour")
	app.settings_flow.show_settings("account")
	_check(_find_button(app.overlay,PlayerCopy.SETTINGS_RECOVER)!=null and _find_label(app.overlay,PlayerCopy.UNREAD_CHECK_AGAIN)==null,"Settings offers Recover again")
	api.responses=[REFUSED]
	await app.account_flow.recover_identity(LOST_PLAYER,LOST_CODE)
	_check(api.calls.size()==1 and storage.values.has("recovery_pending"),"A recovery can start again after the read succeeds")

func _find_label(node: Node, text: String) -> Label:
	if node is Label and node.text==text: return node
	for child: Node in node.get_children():
		var found := _find_label(child,text)
		if found!=null: return found
	return null

## Card paragraphs may be Labels or RichTextLabels.
func _find_paragraph(node: Node, text: String) -> bool:
	if (node is Label or node is RichTextLabel) and node.text==text: return true
	for child: Node in node.get_children():
		if _find_paragraph(child,text): return true
	return false

## A button by its text, or a Settings row by the label it reads out.
func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node.text==text or (node.text.is_empty() and node.accessibility_name==text)):
		return node
	for child: Node in node.get_children():
		var found := _find_button(child,text)
		if found!=null: return found
	return null

extends SceneTree
## The recovery code's guard on every surface that shows or copies it: the phone's
## screen lock first, the private screen while it shows, hidden again on pause, and the
## clipboard cleared after a paste import. Synthetic values only.

const Main=preload("res://main.gd")
const Storage=preload("res://services/local_save.gd")
const PlayerCopy=preload("res://presentation/player_copy.gd")
const Flow=preload("res://presentation/settings_flow.gd")

class LockProbe:
	extends Node
	signal completed(id: String, operation: String, payload: Dictionary)
	signal failed(id: String, operation: String, code: String)
	## confirm, no_lock or cancel.
	var outcome := "confirm"
	var supported := true
	var confirms := 0
	var copies: Array=[]
	var private_calls: Array=[]
	var cleared: Array=[]
	## Runs just before the screen lock answers (the player may do things meanwhile).
	var before_reply: Callable
	func is_available() -> bool: return true
	func device_check_supported() -> bool: return supported
	func confirm_device() -> String:
		confirms+=1
		var id := "confirm-"+str(confirms)
		_reply.call_deferred(id)
		return id
	func _reply(id: String) -> void:
		if before_reply.is_valid(): before_reply.call()
		match outcome:
			"confirm": completed.emit(id,"confirm_device",{"confirmed":true,"locked":true})
			"no_lock": completed.emit(id,"confirm_device",{"confirmed":true,"locked":false})
			"unavailable": failed.emit(id,"confirm_device","device_check_unavailable")
			"timeout": failed.emit(id,"confirm_device","native_request_timeout")
			_: failed.emit(id,"confirm_device","device_check_cancelled")
	func copy_recovery(player: String, code: String) -> String:
		var id := "copy-"+str(copies.size())
		copies.append([player,code])
		(func(): completed.emit(id,"copy_recovery",{"copied":true})).call_deferred()
		return id
	func set_private_screen(on: bool) -> void: private_calls.append(on)
	func clear_recovery_clip(code: String) -> void: cleared.append(code)

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)

func _settle() -> void:
	for i in 4: await process_frame

func _button(app: Node, text: String) -> Button:
	for button: Button in app.overlay.find_children("*","Button",true,false):
		if button.text==text: return button
	return null

func _fields(node: Node) -> Array:
	return node.find_children("*","LineEdit",true,false).map(func(field: LineEdit) -> String: return field.text)

func _run() -> void:
	var path := "user://recovery-lock-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1600,720)
	root.add_child(viewport)
	var app := Main.new()
	app.saves=Storage.new(path)
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	var probe := LockProbe.new()
	app.add_child(probe)
	probe.completed.connect(app._secret_completed)
	probe.failed.connect(app._secret_failed)
	app.secrets=probe
	var player := "P".repeat(22)
	var code := "R".repeat(43)
	app.identity_restart_required=false
	app.identity_loading=false
	app.api.player_id=player
	app.identity_data={"player_id":player,"recovery_code":code,"device_token":"D".repeat(43)}
	var guard: RefCounted = app.account_flow.guard

	# Settings: the row asks for the screen lock before it shows anything.
	app.settings_flow.show_settings(Flow.ACCOUNT)
	await _settle()
	var row := app.overlay.find_child("recovery_details",true,false) as Button
	var box: VBoxContainer = app.settings_flow.detail("recovery_details")
	_check(row != null and box != null,"Account & recovery shows the recovery details row")
	probe.outcome="cancel"
	row.pressed.emit()
	await _settle()
	_check(probe.confirms==1 and not box.visible and app.toast.text==PlayerCopy.RECOVERY_LOCKED,"A cancelled screen lock shows nothing and says why")
	_check(probe.private_calls.is_empty() and probe.copies.is_empty(),"Nothing was shown or copied, so the screen stays as it was")
	probe.outcome="confirm"
	row.pressed.emit()
	row.pressed.emit()
	await _settle()
	_check(probe.confirms==2,"A second tap while the screen lock is open asks nothing more")
	_check(box.visible and _fields(box)==[player,code],"The unlocked row shows the identity and code in place")
	_check(probe.private_calls==[true] and guard.private_screen(),"The private screen is on while they show")
	var copy := _button(app,"Copy recovery details")
	copy.pressed.emit()
	await _settle()
	_check(probe.confirms==2 and probe.copies==[[player,code]],"Copy right after unlocking does not ask again")

	# The app goes to the background: the row hides; the block holds until the app is back.
	app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(not box.visible and box.get_child_count()==0 and not guard.unlocked(),"Going to the background hides the details and locks them again")
	await _settle()
	_check(probe.private_calls==[true],"The private screen stays on while the app is in the background")
	app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await _settle()
	_check(probe.private_calls==[true,false],"Back in front with the details hidden, the private screen lets go")
	row.pressed.emit()
	await _settle()
	_check(probe.confirms==3 and box.visible,"After the background, showing them asks for the screen lock again")
	row.pressed.emit()
	await _settle()
	_check(not box.visible and probe.private_calls.back()==false,"Hiding them with the row lets the private screen go")

	# The screen lock pauses the app while it is open (the PIN screen on older phones).
	guard.lock()
	probe.before_reply=func():
		app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	row.pressed.emit()
	await _settle()
	probe.before_reply=Callable()
	_check(box.visible and guard.unlocked() and guard.private_screen(),"A screen lock that pauses the app still shows the details when it answers")
	row.pressed.emit()
	await _settle()
	# Settings redrawn while the prompt is open: the old row shows nothing, and the
	# next tap shows them without asking again.
	guard.lock()
	probe.before_reply=func(): app.settings_flow.show_settings(Flow.ACCOUNT)
	row.pressed.emit()
	await _settle()
	probe.before_reply=Callable()
	var redrawn := app.overlay.find_child("recovery_details",true,false) as Button
	var redrawn_box: VBoxContainer = app.settings_flow.detail("recovery_details")
	_check(redrawn != null and redrawn != row and redrawn_box != null and not redrawn_box.visible and not guard.private_screen(),"A Settings redraw during the screen lock shows nothing")
	var asked: int = probe.confirms
	redrawn.pressed.emit()
	await _settle()
	_check(probe.confirms==asked and redrawn_box.visible,"The next tap shows them without asking again")
	row=redrawn
	box=redrawn_box
	row.pressed.emit()
	await _settle()
	# A check the phone cannot show at all lets the code show (it may be the only copy of a new code).
	guard.lock()
	probe.outcome="unavailable"
	row.pressed.emit()
	await _settle()
	_check(box.visible,"A phone that cannot show its lock check still shows the details")
	row.pressed.emit()
	await _settle()
	probe.outcome="confirm"

	# A phone with no screen lock has nothing to ask.
	guard.lock()
	probe.outcome="no_lock"
	row.pressed.emit()
	await _settle()
	_check(box.visible,"A phone without a screen lock still shows the details")
	row.pressed.emit()
	await _settle()

	# The details screen outside Settings.
	app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	probe.outcome="cancel"
	var screen: String=app.mode
	await app.account_flow.show_recovery_details()
	_check(app.mode==screen and app.toast.text==PlayerCopy.RECOVERY_LOCKED,"A cancelled screen lock keeps the current screen")
	probe.outcome="confirm"
	await app.account_flow.show_recovery_details()
	await _settle()
	_check(app.mode=="recovery_details" and _fields(app.overlay)==[player,code] and guard.private_screen(),"Unlocked, the details screen shows them behind the private screen")
	app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(_fields(app.overlay)==["",""] and _button(app,PlayerCopy.SETTINGS_RECOVERY_DETAILS) != null,"Going to the background empties both fields and offers to show them again")
	app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await _settle()
	_check(not guard.private_screen(),"Back in front with empty fields, the private screen lets go")
	var count: int=probe.confirms
	_button(app,PlayerCopy.SETTINGS_RECOVERY_DETAILS).pressed.emit()
	await _settle()
	_check(probe.confirms==count+1 and _fields(app.overlay)==[player,code],"Show asks for the screen lock, then fills them again")

	# A copy whose details changed while the screen lock was open copies nothing.
	guard.lock()
	var copies: int=probe.copies.size()
	probe.before_reply=func(): app.identity_data.recovery_code="N".repeat(43)
	await app.account_flow.copy_recovery_details(player,code)
	probe.before_reply=Callable()
	_check(probe.copies.size()==copies and app.toast.text==PlayerCopy.MAIN_6F5191162022,"Details that changed during the screen lock are not copied")
	app.identity_data.recovery_code=code
	guard.lock()
	probe.outcome="cancel"
	await app.account_flow.copy_recovery_details(player,code)
	_check(probe.copies.size()==copies and app.toast.text==PlayerCopy.RECOVERY_LOCKED,"A cancelled screen lock copies nothing")
	probe.outcome="timeout"
	await app.account_flow.copy_recovery_details(player,code)
	_check(probe.copies.size()==copies and not guard.unlocked(),"A screen lock that never answers copies nothing")

	# The Play Games choice copies through the same guard.
	guard.lock()
	probe.outcome="cancel"
	await app.platform_games_flow._copy_recovery()
	_check(probe.copies.size()==copies and app.toast.text==PlayerCopy.RECOVERY_LOCKED and not app.platform_games_flow.recovery_copied(),"Play Games' copy asks for the screen lock too")
	probe.outcome="confirm"
	await app.platform_games_flow._copy_recovery()
	_check(probe.copies.size()==copies+1 and app.platform_games_flow.recovery_copied(),"and copies once it is used")

	# The recovery form: private while open, and the pasted details leave the clipboard.
	app.account_flow.show_recovery_form()
	await _settle()
	_check(guard.private_screen(),"The recovery form is behind the private screen")
	var player_field := app.overlay.find_child("RecoveryIdentity",true,false) as LineEdit
	var code_field := app.overlay.find_child("RecoveryCode",true,false) as LineEdit
	var status := app.overlay.find_child("RecoveryImportStatus",true,false) as Label
	app.account_flow.import_recovery_details("unrelated text",player_field,code_field,status)
	_check(probe.cleared.is_empty(),"Unrelated pasted text leaves the clipboard alone")
	app.account_flow.import_recovery_details("After You recovery details\nIdentity: "+player+"\nRecovery code: "+code,player_field,code_field,status)
	_check(probe.cleared==[code] and code_field.text==code,"A pasted import fills the form and clears the copied details")
	app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(code_field.text==code,"The form keeps what was pasted when the player leaves to fetch the code")
	app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)

	# Builds without the check (iOS for now, desktop) show and copy as before.
	guard.lock()
	probe.supported=false
	count=probe.confirms
	await app.account_flow.show_recovery_details()
	_check(probe.confirms==count and app.mode=="recovery_details","A build without the screen lock check shows the details directly")

	viewport.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix):
			DirAccess.remove_absolute(path+suffix)
	print("AFTER YOU RECOVERY LOCK: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

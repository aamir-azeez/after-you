extends SceneTree

const Main=preload("res://main.gd")
const Storage=preload("res://services/local_save.gd")
const Secrets=preload("res://services/secure_store.gd")

class ClipboardProbe:
	extends Node
	signal completed(id: String, operation: String, payload: Dictionary)
	signal failed(id: String, operation: String, code: String)
	var calls: Array=[]
	var outcome := "success"
	func copy_recovery(player: String, code: String) -> String:
		var id := "copy-"+str(calls.size())
		calls.append({"player_id":player,"recovery_code":code})
		_reply.call_deferred(id)
		return id
	func _reply(id: String) -> void:
		if outcome=="error":
			failed.emit(id,"copy_recovery","clipboard_unavailable")
		else:
			completed.emit(id,"copy_recovery",{"copied":outcome=="success"})

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)

func _run() -> void:
	var path := "user://recovery-copy-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,720)
	root.add_child(viewport)
	var app := Main.new()
	app.saves=Storage.new(path)
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	var native := ClipboardProbe.new()
	app.add_child(native)
	native.completed.connect(app._secret_completed)
	native.failed.connect(app._secret_failed)
	app.secrets=native
	var player := "P".repeat(22)
	var code := "R".repeat(43)
	var device_token := "D".repeat(43)
	app.identity_data={"player_id":player,"recovery_code":code,"device_token":device_token}
	for size: Vector2i in [Vector2i(1280,720),Vector2i(1560,720),Vector2i(1280,960)]:
		viewport.size=size
		app._show_recovery_details()
		await process_frame
		await process_frame
		var copy := _copy_button(app)
		_check(copy!=null and not copy.disabled,"Valid recovery details expose an enabled copy action")
		for button: Button in app.overlay.find_children("*","Button",true,false):
			_check(Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()),"Recovery action fits the screen: "+button.text)
	_check(native.calls.is_empty(),"Simply showing recovery details does not copy anything")
	var saved_before := JSON.stringify(app.saves.data)
	var identity_before := JSON.stringify(app.identity_data)
	var copy := _copy_button(app)
	copy.pressed.emit()
	copy.pressed.emit()
	await process_frame
	await process_frame
	_check(native.calls==[{"player_id":player,"recovery_code":code}],"Explicit copy sends only identity and recovery code; rapid repeat is coalesced")
	_check(not app.recovery_copy_busy and app.toast_label.text.begins_with("Recovery details copied"),"Success is shown only after the native copy receipt")
	_check(not app.toast_label.text.contains(player) and not app.toast_label.text.contains(code) and not app.toast_label.text.contains(device_token),"Copy feedback does not echo credentials")
	_check(JSON.stringify(app.saves.data)==saved_before and JSON.stringify(app.identity_data)==identity_before,"Copy does not alter identity, recovery or saved progress")
	for outcome: String in ["error","not_copied"]:
		native.outcome=outcome
		await app._copy_recovery_details(player,code)
		_check(app.toast_label.text.begins_with("Could not copy") and not app.recovery_copy_busy,"Native failure never claims clipboard success")
	var count := native.calls.size()
	app.identity_data.recovery_code="N".repeat(43)
	await app._copy_recovery_details(player,code)
	_check(native.calls.size()==count,"An old displayed recovery code cannot be copied after credential rotation")
	app.identity_data.recovery_code=code
	app.pending_recovery={"request":{"player_id":player}}
	await app._copy_recovery_details(player,code)
	_check(native.calls.size()==count,"An unresolved recovery does not copy potentially obsolete credentials")
	app.pending_recovery={}
	app.identity_data.recovery_code=""
	app._show_recovery_details()
	await process_frame
	_check(_copy_button(app).disabled,"Incomplete recovery details disable copying")
	await app._copy_recovery_details(player,"")
	_check(native.calls.size()==count,"Invalid recovery fields never reach the native clipboard")
	var legacy_store := Secrets.new()
	app.add_child(legacy_store)
	var older_plugin := Node.new()
	legacy_store.add_child(older_plugin)
	legacy_store._native=older_plugin
	var unavailable := {}
	legacy_store.failed.connect(func(id: String, operation: String, error: String): unavailable.merge({"id":id,"operation":operation,"error":error}))
	var request := legacy_store.copy_recovery(player,code)
	await process_frame
	await process_frame
	_check(unavailable.get("id")==request and unavailable.get("operation")=="copy_recovery" and unavailable.get("error")=="native_operation_unavailable","An older native plugin returns an actionable error instead of hanging")
	_check(legacy_store._pending.is_empty(),"Unsupported native copy retires its pending request")
	viewport.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix):
			DirAccess.remove_absolute(path+suffix)
	print("AFTER YOU RECOVERY COPY: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func _copy_button(app: Node) -> Button:
	for button: Button in app.overlay.find_children("*","Button",true,false):
		if button.text=="Copy recovery details":
			return button
	return null

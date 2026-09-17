extends SceneTree

const Storage=preload("res://services/local_save.gd")
const PlayerCopy=preload("res://presentation/player_copy.gd")

class RecoveryProbe:
	extends "res://main.gd"
	var submitted: Array=[]
	func _recover_identity(player: String, code: String) -> void:
		submitted.append({"player_id":player,"recovery_code":code})

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
	var path := "user://recovery-import-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,720)
	root.add_child(viewport)
	var app := RecoveryProbe.new()
	app.saves=Storage.new(path)
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	var identity := "aB_-".repeat(5)+"cD"
	var secret := "rS_-".repeat(10)+"tUv"
	var block := "After You recovery details\nIdentity: "+identity+"\nRecovery code: "+secret
	var before := JSON.stringify(app.saves.data)
	for size: Vector2i in [Vector2i(1280,720),Vector2i(1560,720),Vector2i(1280,960)]:
		viewport.size=size
		app._show_recovery_form()
		await process_frame
		await process_frame
		for control: Control in app.overlay.find_children("*","Control",true,false):
			if control is Button or control is LineEdit or control.name=="RecoveryImportStatus":
				_check(Rect2(Vector2.ZERO,Vector2(size)).encloses(control.get_global_rect()),"Recovery import control stays visible: "+control.name)
	var player: LineEdit=app.overlay.find_child("RecoveryIdentity",true,false)
	var code: LineEdit=app.overlay.find_child("RecoveryCode",true,false)
	var status: Label=app.overlay.find_child("RecoveryImportStatus",true,false)
	_check(player.text.is_empty() and code.text.is_empty() and app.submitted.is_empty(),"Opening recovery leaves both inputs empty and makes no request")
	_check(code.secret,"Imported recovery code remains masked")
	app._import_recovery_details(block,player,code,status)
	_check(player.text==identity and code.text==secret,"Import splits the complete copied block into exact fields")
	_check(app.submitted.is_empty() and status.text==PlayerCopy.MAIN_06D48BA3672C,"Import prepares fields without recovering automatically")
	_check(not status.text.contains(identity) and not status.text.contains(secret),"Import feedback never repeats recovery credentials")
	app._import_recovery_details(block+"\nIdentity: "+identity,player,code,status)
	_check(player.text==identity and code.text==secret and status.text.begins_with("Could not read"),"Ambiguous import leaves the previous valid fields intact")
	app._import_recovery_details("unrelated clipboard text",player,code,status)
	_check(player.text==identity and code.text==secret and app.submitted.is_empty(),"Unrelated clipboard content neither changes inputs nor submits")
	for target: LineEdit in [player,code]:
		player.text=""
		code.text=""
		var flattened := block.replace("\n"," ")
		target.text=flattened
		target.text_changed.emit(flattened)
		_check(player.text==identity and code.text==secret,"System Paste into either input recognizes the full flattened block")
	for target: LineEdit in [player,code]:
		player.text=""
		code.text=""
		target.insert_text_at_caret(block)
		# Exercise actual LineEdit insertion, rather than assuming how it treats
		# newlines. Emit the editing notification used by the native paste action.
		var inserted := target.text
		target.text_changed.emit(inserted)
		_check(player.text==identity and code.text==secret,"Actual LineEdit insertion into either field imports the copied multiline block")
	_check(app.submitted.is_empty(),"Pasting into either field never submits")
	for button: Button in app.overlay.find_children("*","Button",true,false):
		if button.text=="Recover identity":
			button.pressed.emit()
	_check(app.submitted==[{"player_id":identity,"recovery_code":secret}],"Only an explicit Recover action forwards the separated credentials")
	_check(JSON.stringify(app.saves.data)==before,"Preparing recovery never writes credentials to ordinary game saves")
	app._show_recovery_form()
	await process_frame
	player=app.overlay.find_child("RecoveryIdentity",true,false)
	code=app.overlay.find_child("RecoveryCode",true,false)
	_check(player.text.is_empty() and code.text.is_empty(),"Reopening recovery discards unsubmitted input")
	viewport.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix):
			DirAccess.remove_absolute(path+suffix)
	print("AFTER YOU RECOVERY IMPORT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

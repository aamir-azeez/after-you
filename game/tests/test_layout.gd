extends SceneTree

const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
class AvailableSecrets:
	extends Node
	func is_available() -> bool:
		return true
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
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,720)
	root.add_child(viewport)
	var app := Main.new()
	var path := "user://layout-test-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	app.saves=Storage.new(path)
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app._start_practice(0)
	app._close_overlay()
	app.running=false
	for size: Vector2i in [Vector2i(1280,720),Vector2i(1600,720),Vector2i(1280,960)]:
		viewport.size=size
		await process_frame
		for left in [false,true,false]:
			app.saves.data.settings.left_handed=left
			app._apply_settings()
			await process_frame
			var screen := Rect2(Vector2.ZERO,Vector2(size))
			for control: Control in [app.stick,app.interact_button,app.finish_button]:
				_check(screen.encloses(control.get_global_rect()),"%s remains fully visible at %s with left action=%s" % [control.name,size,left])
				_check(control.size.x>=44 and control.size.y>=44,"Touch targets retain usable minimum bounds")
			_check(not app.stick.get_global_rect().intersects(app.interact_button.get_global_rect()),"Movement and action controls do not overlap")
			_check(not app.interact_button.get_global_rect().intersects(app.finish_button.get_global_rect()),"Throw and finish remain separate touch targets")
			_check((app.stick.position.x>app.interact_button.position.x)==left,"Handedness moves the action and movement controls to opposite sides")
	viewport.size=Vector2i(1280,720)
	var native_available := AvailableSecrets.new()
	app.add_child(native_available)
	app.secrets=native_available
	app.api.player_id="A".repeat(22)
	app.api.device_token="B".repeat(43)
	app.api.base_url="https://example.invalid"
	app._show_account()
	await process_frame
	var account_buttons := _buttons(app.overlay)
	_check(account_buttons.size()>=6,"Native signed-in Account includes recovery, restore and hosting actions")
	for button: Button in account_buttons:
		_check(Rect2(Vector2.ZERO,Vector2(viewport.size)).encloses(button.get_global_rect()),"Account action stays on-screen: "+button.text)
	viewport.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	for suffix in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix):
			DirAccess.remove_absolute(path+suffix)
	print("AFTER YOU LAYOUT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func _buttons(node: Node) -> Array[Button]:
	var result: Array[Button]=[]
	if node is Button:
		result.append(node)
	for child in node.get_children():
		result.append_array(_buttons(child))
	return result

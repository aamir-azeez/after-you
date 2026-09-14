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
		await _test_menu_layouts(app,viewport)
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

func _test_menu_layouts(app: Node, viewport: SubViewport) -> void:
	var screen := Rect2(Vector2.ZERO,Vector2(viewport.size))
	app._start_practice(0)
	app._close_overlay()
	app.running=false
	app._toast("Your rehearsal is safely saved on this device.")
	await process_frame
	for control: Control in [app.timer_label,app.progress,app.hint_label,app.toast_label]:
		_check(screen.encloses(control.get_global_rect()),"Anchored HUD control stays visible at %s: %s" % [viewport.size,control.name])
	for button: Button in _buttons(app.hud):
		_check(screen.encloses(button.get_global_rect()),"Anchored HUD action stays visible at %s: %s" % [viewport.size,button.text])
	_check(not app.hint_label.get_global_rect().intersects(app.interact_button.get_global_rect()) and not app.hint_label.get_global_rect().intersects(app.finish_button.get_global_rect()),"Instruction text does not overlap action controls at %s" % viewport.size)
	app._show_home()
	await process_frame
	var captions := _labels(app.overlay)
	var caption: Label
	for label: Label in captions:
		_check(screen.encloses(label.get_global_rect()),"Home text remains visible at %s: %s" % [viewport.size,label.text.replace("\n"," ")])
		if label.text=="Record a moment. Leave it for someone.":
			caption=label
	_check(caption!=null and screen.encloses(caption.get_global_rect()),"Bottom-right home caption is inside the viewport at %s" % viewport.size)
	for button: Button in _buttons(app.overlay):
		_check(screen.encloses(button.get_global_rect()) and not button.get_global_rect().intersects(caption.get_global_rect()),"Home action stays visible without overlapping caption: "+button.text)
	app._show_journey()
	await process_frame
	_check_card_contents(app.overlay,screen,"Journey")
	app._show_settings()
	await process_frame
	_check_card_contents(app.overlay,screen,"Settings")
	var first: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-a.json"))
	var second: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-b.json"))
	app.room_play=false
	app.collection_preview=false
	app.attempt={"a":{},"b":{},"draft":{}}
	app.review_recording=first
	app._show_review()
	await process_frame
	_check_card_contents(app.overlay,screen,"First-turn review")
	app.attempt={"a":first,"b":{},"draft":{}}
	app.review_recording=second
	app._show_review()
	await process_frame
	_check_card_contents(app.overlay,screen,"Completed-island review")
	app._start_practice(0)
	app._close_overlay()
	app.running=false

func _check_card_contents(node: Node, screen: Rect2, context: String) -> void:
	var controls: Array[Button]=_buttons(node)
	_check(not controls.is_empty(),context+" includes reachable actions")
	for index: int in range(controls.size()):
		var control := controls[index]
		_check(screen.encloses(control.get_global_rect()),context+" action stays inside the viewport: "+control.text)
		for other: int in range(index):
			_check(not control.get_global_rect().intersects(controls[other].get_global_rect()),context+" actions do not overlap: "+control.text+" / "+controls[other].text)
	for label: Label in _labels(node):
		_check(screen.encloses(label.get_global_rect()),context+" text stays inside the viewport: "+label.text)

func _labels(node: Node) -> Array[Label]:
	var result: Array[Label]=[]
	if node is Label:
		result.append(node)
	for child: Node in node.get_children():
		result.append_array(_labels(child))
	return result

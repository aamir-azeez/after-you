extends SceneTree

const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")

class DelayedRooms:
	extends Node
	var player_id := "host"
	var device_token := "test-token"
	var busy := false
	var calls: Array=[]
	var response: Dictionary={}
	var during_request: Callable
	func configured() -> bool:
		return true
	func request_json(method: int, path: String, body: Dictionary={}, _still: Callable = Callable()) -> Dictionary:
		busy=true
		calls.append({"method":method,"path":path,"body":body.duplicate(true)})
		if during_request.is_valid():
			var callback := during_request
			during_request=Callable()
			callback.call()
		await get_tree().process_frame
		busy=false
		return response.duplicate(true)

var checks := 0
var failures := 0
var app: Node
var api: DelayedRooms
var path := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	path="user://lifecycle-test-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	app=Main.new()
	app.saves=Storage.new(path)
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	api=DelayedRooms.new()
	app.add_child(api)
	app.api=api
	await process_frame
	await _test_world_presentation()
	app.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix):
			DirAccess.remove_absolute(path+suffix)
	print("AFTER YOU LIFECYCLE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func _reset_case() -> void:
	app.application_backgrounded=false
	app.identity_loading=false
	app.identity_busy=false
	app.identity_restart_required=false
	app.mode="home"
	app.lifecycle_generation+=1
	api.player_id="host"
	api.device_token="test-token"
	api.busy=false
	api.calls=[]
	api.during_request=Callable()

func _test_world_presentation() -> void:
	_reset_case()
	var original_processing: bool = app.world.is_processing()
	var original_physics: bool = app.world.is_physics_processing()
	var original_mode: int = app.world.process_mode
	app._show_home()
	app._set_world_visible(true)
	app.world.set_process(true)
	var home_time: float = app.world.time
	await process_frame
	await process_frame
	_check(app.mode=="home" and app.world.is_visible_in_tree() and app.world.home_view and app.world.time>home_time,"Visible Home advances world animation through real process callbacks")
	for was_processing: bool in [true,false]:
		app.world.set_process(was_processing)
		app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		var paused_time: float = app.world.time
		await process_frame
		await process_frame
		_check(not app.world.is_processing() and app.world.time==paused_time,"Background stops world animation across real frames")
		_check(app.world.is_physics_processing()==original_physics and app.world.process_mode==original_mode,"Background suspension leaves world physics and descendants policy unchanged")
		app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		_check(app.world.is_processing()==was_processing,"Repeated lifecycle notifications preserve the world's original processing state")
		await process_frame
		await process_frame
		_check((app.world.time>paused_time) if was_processing else (app.world.time==paused_time),"Visible Home resumes real animation only when it was previously processing")
		app._set_world_visible(false)
		app._set_world_visible(false)
		app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		app._set_world_visible(true)
		_check(not app.world.is_processing(),"Showing a retained world while backgrounded keeps it suspended")
		var hidden_time: float = app.world.time
		await process_frame
		await process_frame
		_check(app.world.time==hidden_time,"Showing Home before foreground does not restart animation")
		app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		_check(app.world.is_processing()==was_processing,"Hide and background overlap preserves the original processing bit")
		await process_frame
		await process_frame
		_check((app.world.time>hidden_time) if was_processing else (app.world.time==hidden_time),"Returning to visible Home advances real animation only when originally enabled")
	var original_world: Node3D = app.world
	original_world.set_process(true)
	app._set_world_visible(false)
	var replacement := Node3D.new()
	root.add_child(replacement)
	replacement.set_process(false)
	app.world = replacement
	app._set_world_visible(true)
	_check(not replacement.is_processing(),"A replacement world does not inherit the old world's processing bit")
	replacement.set_process(true)
	app._set_world_visible(false)
	replacement.free()
	app._sync_world_processing()
	app.world = original_world
	app._set_world_visible(true)
	_check(not original_world.is_processing(),"A freed world's processing bit is not applied to another instance")
	app.world.set_process(original_processing)

func _check(condition: bool, description: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL: "+description)

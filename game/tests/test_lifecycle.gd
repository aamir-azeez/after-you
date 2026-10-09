extends SceneTree

const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const Levels = preload("res://core/levels.gd")

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
	func request_json(method: int, path: String, body: Dictionary={}) -> Dictionary:
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
var first: Dictionary

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	path="user://lifecycle-test-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	first=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-a.json"))
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
	await _test_visible_completion_presentation()
	await _test_resume_coalescing()
	await _test_background_rehearsal()
	await _test_unsafe_modes()
	await _test_in_flight_transitions()
	await _test_receipt_only_refresh()
	await _test_errors_and_identity()
	app.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix):
			DirAccess.remove_absolute(path+suffix)
	print("AFTER YOU LIFECYCLE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func _room(revision: int=4, id: String="room-lifecycle") -> Dictionary:
	return {"schema_version":1,"room_id":id,"revision":revision,"attempt":0,"level_id":"first-light","level_index":0,"host_id":"host","guest_id":"guest","first_player_id":"host","active_role":"a","recordings":{"a":null,"b":null}}

func _reset_case() -> void:
	app.application_backgrounded=false
	app.foreground_refresh_queued=false
	app.foreground_refresh_running=false
	app.foreground_response={}
	app.submission_in_flight=false
	app.identity_loading=false
	app.identity_busy=false
	app.identity_restart_required=false
	app.running=false
	app.mode="home"
	app.room_play=false
	app.lifecycle_generation+=1
	app.active_room=_room()
	app.saves.update_values({"room":_room()},["pending_turn","room_draft"])
	api.player_id="host"
	api.device_token="test-token"
	api.busy=false
	api.calls=[]
	api.during_request=Callable()
	api.response={"ok":true,"status":200,"data":_room(5)}

func _transition() -> void:
	app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)

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

func _test_visible_completion_presentation() -> void:
	_reset_case()
	var original_processing: bool = app.world.is_processing()
	var original_reduced_motion: bool = app.world.reduced_motion
	app.world.set_process(true)
	app.world.reduced_motion=false
	app.current_level=Levels.get_level(0)
	app.level_index=0
	app.role="b"
	app.attempt={"a":first.duplicate(true),"b":{},"draft":{}}
	var second: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-b.json"))
	app._preview(second)
	# Drive the established replay fixture to completion, then let only the
	# World's real process callbacks run. Main services and simulation stay off.
	for _frame in range(app.replay_frames.size()+1):
		app._physics_process(1.0/30.0)
	_check(app.mode=="completion" and app.world.is_visible_in_tree() and app.world.bloomed and not app.overlay.visible,"A completed replay leaves its blooming world visible")
	var completed_hash: String=app.sim.state_hash()
	var paused_time: float=app.world.time
	var paused_bloom_age: float=app.world.garden_bloom_age
	app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await process_frame
	await process_frame
	_check(app.world.time==paused_time and app.world.garden_bloom_age==paused_bloom_age,"Background holds the visible completion's animation clock and bloom across real frames")
	app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await process_frame
	await process_frame
	_check(app.world.time>paused_time and app.world.garden_bloom_age>paused_bloom_age,"Visible completion resumes its world clock and bloom through real process callbacks")
	_check(app.mode=="completion" and not app.running and app.sim.state_hash()==completed_hash and api.calls.is_empty(),"Resumed completion animation does not advance simulation or request a room")
	app.world.reduced_motion=original_reduced_motion
	app.world.set_process(original_processing)
	app._show_home()

func _test_resume_coalescing() -> void:
	_reset_case()
	app.mode="room"
	_transition()
	app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await app._service_foreground_refresh()
	await app._service_foreground_refresh()
	_check(api.calls.size()==1 and api.calls[0].method==HTTPClient.METHOD_GET,"Duplicate resume notification produces one read-only refresh")
	_check(app.active_room.revision==5 and app.mode=="room","Safe room screen receives fresh snapshot")
	_check(not app.foreground_refresh_queued and not app.foreground_refresh_running,"Successful refresh consumes its queue")

func _test_background_rehearsal() -> void:
	_reset_case()
	app.current_level=Levels.get_level(0)
	app.level_index=0
	app.role="a"
	app.attempt={"a":{},"b":{},"draft":{}}
	app._prepare_turn()
	app._begin_turn()
	for _i: int in range(12):
		app._physics_process(1.0/30.0)
	app.action_pressed=true
	var before: String=app.sim.state_hash()
	app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	var generation: int=app.saves.data.generation
	app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(app.mode=="paused" and not app.running and app.sim.state_hash()==before,"Background pauses live rehearsal without advancing its clock")
	_check(app.saves.attempt("first-light").draft.duration_ticks==12,"Background persists the exact current rehearsal")
	_check(not app.action_pressed and app.saves.data.generation==generation,"Duplicate pause clears input without repeatedly rewriting draft")
	app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await app._service_foreground_refresh()
	_check(app.mode=="paused" and not app.running and api.calls.is_empty(),"Foreground does not automatically resume or replace paused work")
	var continue_button := _find_button(app.overlay,"Resume")
	continue_button.pressed.emit()
	await app._service_foreground_refresh()
	_check(app.mode=="play" and api.calls.is_empty() and app.foreground_refresh_queued,"Refresh remains queued after player continues recording")
	app._pause()
	# Play with a friend now waits for a ready online identity, so use Home as the safe menu.
	app._show_home()
	await app._service_foreground_refresh()
	_check(api.calls.size()==1 and app.mode=="home","Returning to a safe menu drains refresh without hijacking the menu")

func _test_unsafe_modes() -> void:
	for unsafe: String in ["ready","review","preview","completion","paused","paywall","account","held"]:
		_reset_case()
		app.mode=unsafe
		_transition()
		await app._service_foreground_refresh()
		_check(api.calls.is_empty() and app.foreground_refresh_queued,"Refresh waits during "+unsafe)
	_reset_case()
	app.submission_in_flight=true
	_transition()
	await app._service_foreground_refresh()
	_check(api.calls.is_empty(),"Submission-in-flight guard holds refresh even before transport busy flag")
	app.submission_in_flight=false
	api.busy=true
	await app._service_foreground_refresh()
	_check(api.calls.is_empty(),"Existing API request is never overlapped by resume refresh")
	api.busy=false
	await app._service_foreground_refresh()
	_check(api.calls.size()==1,"Queued refresh runs once after network becomes safe")

func _test_in_flight_transitions() -> void:
	_reset_case()
	_transition()
	api.during_request=func(): app.mode="play"; app.running=true
	await app._service_foreground_refresh()
	_check(app.active_room.revision==4 and not app.foreground_response.is_empty(),"Response arriving after play begins is deferred")
	app.running=false
	app.mode="rooms"
	await app._service_foreground_refresh()
	_check(app.active_room.revision==5 and api.calls.size()==1,"Deferred response applies safely without a duplicate GET")
	_reset_case()
	_transition()
	api.during_request=func(): app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await app._service_foreground_refresh()
	_check(app.active_room.revision==4 and app.foreground_response.is_empty(),"Response from earlier foreground generation cannot apply after background")
	api.response.data=_room(8)
	app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await app._service_foreground_refresh()
	_check(api.calls.size()==2 and app.active_room.revision==8,"Next real resume obtains fresh state after discarded old response")
	_reset_case()
	_transition()
	api.during_request=func(): app.active_room=_room(12,"other-room"); app.saves.update_values({"room":app.active_room})
	await app._service_foreground_refresh()
	_check(app.active_room.room_id=="other-room" and app.saves.data.room.room_id=="other-room","Late snapshot cannot switch away from a newly selected room")
	_reset_case()
	app.active_room=_room(20)
	app.saves.update_values({"room":_room(20)})
	_transition()
	await app._service_foreground_refresh()
	_check(app.active_room.revision==20,"Older returned revision cannot roll back cached room")

func _test_receipt_only_refresh() -> void:
	_reset_case()
	var pending := {"room_id":"room-lifecycle","owner_player_id":"host","base_revision":4,"recording":first,"idempotency_key":"original-pending-key"}
	app.saves.update_values({"pending_turn":pending})
	api.response.data.recordings.a=first.duplicate(true)
	api.response.data.active_role="b"
	_transition()
	await app._service_foreground_refresh()
	_check(not app.saves.data.has("pending_turn") and api.calls.size()==1 and api.calls[0].method==HTTPClient.METHOD_GET,"Matching room receipt clears uncertainty without automatic submission")
	_reset_case()
	app.saves.update_values({"pending_turn":pending})
	_transition()
	await app._service_foreground_refresh()
	_check(app.saves.data.pending_turn.idempotency_key=="original-pending-key" and api.calls.size()==1,"Unmatched pending request remains held with exact original key")
	await app._service_foreground_refresh()
	_check(api.calls.size()==1,"Unmatched pending request causes no automatic retry loop")

func _test_errors_and_identity() -> void:
	_reset_case()
	api.response={"ok":false,"status":0,"error":"Injected loss"}
	_transition()
	await app._service_foreground_refresh()
	await app._service_foreground_refresh()
	_check(api.calls.size()==1 and app.active_room.revision==4,"Network failure preserves cache and does not create a retry storm")
	_reset_case()
	api.player_id=""
	api.device_token=""
	_transition()
	await app._service_foreground_refresh()
	_check(api.calls.is_empty() and not app.foreground_refresh_queued,"Resume does not create an identity or send anonymous room requests")
	_reset_case()
	app.identity_loading=true
	_transition()
	await app._service_foreground_refresh()
	_check(api.calls.is_empty() and app.foreground_refresh_queued,"Refresh waits for existing secure identity load")
	app.identity_loading=false
	await app._service_foreground_refresh()
	_check(api.calls.size()==1,"Loaded existing identity permits the deferred GET")

func _find_button(node: Node, label: String) -> Button:
	if node is Button and node.text==label:
		return node
	for child: Node in node.get_children():
		var found := _find_button(child,label)
		if found!=null:
			return found
	return null

func _check(condition: bool, description: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL: "+description)

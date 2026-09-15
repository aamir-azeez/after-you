extends SceneTree
const Preview = preload("res://relay_preview.gd")
const Session = preload("res://services/relay_online_session.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"

class Memory:
	extends RefCounted
	var values: Dictionary = {}
	func load_scope(scope: String) -> Dictionary:
		return {"ok":true,"found":values.has(scope),"value":values.get(scope,{}).duplicate(true)}
	func save_scope(scope: String,value: Dictionary) -> Dictionary:
		values[scope]=value.duplicate(true)
		return {"ok":true}

class Api:
	extends Node
	signal release
	var player_id := GUEST
	var device_token := "synthetic-only"
	var busy := false
	var base_url := "https://synthetic.invalid"
	var response: Callable
	var photo_gets := 0
	var photo_bodies := 0
	var non_gets := 0
	var hold_first := false
	func configured() -> bool: return true
	func request_json(method: int,path: String,_body: Dictionary={}) -> Dictionary:
		busy=true
		if method!=HTTPClient.METHOD_GET: non_gets+=1
		if "/photos/" in path:
			photo_gets+=1
			if hold_first:
				hold_first=false
				await release
		var result: Dictionary=response.call(path)
		if result.get("data",{}).get("jpeg_base64")!=null: photo_bodies+=1
		busy=false
		return result

var checks:=0
var failures:=0
var fixtures: Dictionary={}
var jpeg:=PackedByteArray()
var jpeg_hash:=""
var photo_size:=Vector2i(40,60)
var api: Api
var screen: Node
var session: RefCounted
var source_room: Dictionary
var visible_ticks:=0
var created_ticks:=0
var unsafe_ticks:=0
var summaries: Array=[]
var rejection_counts:Dictionary={}
var first_rejection:Dictionary={}

func _initialize() -> void: _run.call_deferred()
func _check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1;push_error(label)
func _ok(data: Dictionary)->Dictionary: return {"ok":true,"status":200,"data":data}
func _response(path: String)->Dictionary:
	if path=="/v2/capabilities":
		var descriptor:=Registry.descriptor(Registry.FIRST_STEPS)
		return _ok({"api_version":2,"recording_version":2,"simulation_version":2,"mutations_enabled":true,"photo_uploads_enabled":true,"validation":"structural_client_replay_required","chapters":[{"level_id":descriptor.level_id,"level_version":descriptor.level_version,"definition_hash":descriptor.definition_hash,"recording_version":4,"simulation_version":4,"premium":false}]})
	if path=="/v2/rooms": return _ok({"rooms":[source_room.duplicate(true)]})
	if path=="/v2/rooms/"+ROOM:return _ok(source_room.duplicate(true))
	if path.ends_with("/photos/t0-1-b"):
		return _ok({"photo":{"schema_version":1,"turn_id":"t0-1-b","owner_player_id":HOST,"recording_hash":fixtures.b.recording_hash,"photo_revision":1,"sha256":jpeg_hash,"width":photo_size.x,"height":photo_size.y,"byte_length":jpeg.size(),"updated_at":"2026-09-14T12:00:00Z"},"jpeg_base64":Marshalls.raw_to_base64(jpeg)})
	if "/photos/" in path:return _ok({"photo":null,"jpeg_base64":null})
	return {"ok":false,"status":404,"code":"not_found"}

func _run()->void:
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i(1280,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	for role:String in ["a","b"]:
		fixtures[role]=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first_steps/a-place-to-grow-"+role+".json"))
	var checkpoint:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first_steps/final-checkpoint.json"))
	var level:=Registry.definition(Registry.FIRST_STEPS)
	source_room={"api_version":2,"schema_version":2,"room_id":ROOM,"revision":5,"branch":0,"stage_index":2,"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),"host_id":HOST,"guest_id":GUEST,"checkpoint":checkpoint,"a_turn_id":null,"completed_pair_ids":["p0-0","p0-1"],"invite_expires_at":"2026-09-21T12:00:00Z","created_at":"2026-09-14T12:00:00Z","updated_at":"2026-09-14T12:00:00Z","active_role":"complete","first_player_id":null,"active_player_id":null,"player_slot":"p1","stage_id":"","recording_a":null,"validation":"structural_client_replay_required"}
	_make_image(Vector2i(40,60))
	api=Api.new();api.response=_response;root.add_child(api)
	var store:=Memory.new()
	session=Session.new(api,func()->Dictionary:return {"ready":true,"player_id":GUEST,"epoch":1},store)
	session.photo_store=Memory.new()
	_check(await session.load_lobby() and await session.open_room(ROOM),"Real session and coordinator replay-verify the complete First Steps room")
	if session.coordinator==null or session.coordinator.read_only:
		await _finish();return
	var preserved:=Canonical.digest(session.coordinator.snapshot())
	screen=Preview.new();screen.online_session=session
	screen.settings={"sound":false,"haptics":false,"reduced_motion":false,"left_handed":false}
	root.add_child(screen)
	await process_frame
	screen.set_physics_process(false);screen.set_process(false);screen.world.set_process(false)
	_check(screen.mode=="complete" and screen.world.get_script()==Registry.world_script(Registry.FIRST_STEPS),"Actual shared preview dispatches First StepsWorld with verified completed state")
	var refs:Array=session.replay_photo_turns(1,{"a":fixtures.a,"b":fixtures.b})
	_check(refs.size()==2 and refs[0].player_slot=="p1" and refs[1].player_slot=="p0" and not refs[1].own,"Guest sees the host final-B photo reference on exact physical p0")
	await _play_case(Vector2i(1280,720),false,false)
	await _play_case(Vector2i(1560,720),true,false)
	await _play_case(Vector2i(1280,720),false,true)
	_make_image(Vector2i(160,160))
	await _play_case(Vector2i(1560,720),true,false)
	root.size=Vector2i(1280,720)
	await process_frame
	await process_frame
	screen.controls.chapter_label.text="The Sleeping Lighthouse · After the First Bell · Replay"
	screen.hud.show()
	await process_frame
	await process_frame
	print("TITLE_LAYOUT "+JSON.stringify({"size":str(screen.controls.chapter_label.size),"minimum":str(screen.controls.chapter_label.get_minimum_size()),"lines":screen.controls.chapter_label.get_line_count()}))
	_check(screen.controls.chapter_label.get_line_count()>1,"A genuine longer chapter title still wraps")
	_check(is_equal_approx(screen.controls.chapter_label.size.y,screen.controls.chapter_label.get_minimum_size().y),"Wrapped title retains its complete minimum text height")
	screen.controls.chapter_label.text="First Steps"
	await process_frame
	await process_frame
	_check(screen.controls.chapter_label.size.y<60 and is_equal_approx(screen.controls.chapter_label.size.y,screen.controls.chapter_label.get_minimum_size().y),"A shorter title releases earlier wrapping height without clipping text")
	_check(Canonical.digest(session.coordinator.snapshot())==preserved and session.coordinator.draft().is_empty() and session.coordinator.pending().is_empty(),"Replay/photo/pause leaves verified gameplay state unchanged")
	_check(api.non_gets==0,"No gameplay or photo writes are made")
	await _finish()

func _make_image(dimensions:Vector2i)->void:
	photo_size=dimensions
	var image:=Image.create(dimensions.x,dimensions.y,false,Image.FORMAT_RGB8)
	image.fill(Color("edbd62"))
	jpeg=image.save_jpg_to_buffer()
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(jpeg);jpeg_hash=hash.finish().hex_encode()

func _play_case(size_value:Vector2i,inset:bool,delayed:bool)->void:
	root.size=size_value
	await process_frame
	if inset:
		screen.controls.ui.offset_left=40
		screen.controls.ui.offset_right=-24
	await process_frame
	visible_ticks=0;created_ticks=0;unsafe_ticks=0
	rejection_counts={};first_rejection={}
	api.hold_first=delayed
	screen.replay_pair_index=1
	screen._play_collection_pair()
	if delayed:
		_check(api.busy and screen.reaction_strip._draining,"Photo read is actually held before partner response")
		for frame in range(4):await process_frame
		api.release.emit()
	await process_frame
	_check(api.photo_bodies>0 and screen.reaction_strip._bubbles.size()==1,"Real photo controller accepts synthetic JPEG bytes and strip creates one bubble")
	var frames:int=screen.replay_frames.size()
	for index in range(frames):
		if screen.mode!="replay":break
		screen._physics_process(1.0/30.0)
		screen.world._process(1.0/30.0)
		screen._position_replay_photos()
		if screen.mode=="replay":_observe()
		if index==20:
			var cursor:int=screen.replay_cursor
			screen._pause()
			_check(not screen.running and screen.mode=="paused","Pause stops actual replay")
			var previous:int=api.photo_gets
			screen._resume_replay()
			await process_frame
			screen._position_replay_photos()
			_check(screen.running and screen.replay_cursor==cursor and api.photo_gets>=previous+2,"Continue resumes exact cursor and reloads both photo references")
		await process_frame
	_check(visible_ticks==created_ticks and visible_ticks>0,"Photo is visibly projected throughout eligible First Steps replay ticks")
	_check(unsafe_ticks==0,"Visible photo stays within its UI safe rectangle")
	summaries.append({"width":size_value.x,"inset":inset,"delayed":delayed,"square_photo":photo_size.x==photo_size.y,"input_ticks":frames,"created_ticks":created_ticks,"visible_ticks":visible_ticks,"unsafe_ticks":unsafe_ticks,"read_count":api.photo_gets,"image_response_count":api.photo_bodies})
	print("PHOTO_WORLD "+JSON.stringify(summaries[-1]))
	print("REJECTIONS "+JSON.stringify({"counts":rejection_counts,"first":first_rejection}))

func _observe()->void:
	for bubble:Control in screen.reaction_strip._bubbles:
		created_ticks+=1
		var actor:Node3D=screen.world.actors[bubble.get_meta("player_slot")]
		var local:Transform2D=screen.reaction_strip.get_global_transform_with_canvas().affine_inverse()
		var anchor:Vector2=local*screen.world.camera.unproject_position(actor.global_position+Vector3(0,actor.photo_anchor_height(),0))
		var bounds:=Rect2(anchor-Vector2(36,108),Vector2(72,104))
		var rejected:Array=[]
		if not Rect2(Vector2.ZERO,screen.reaction_strip.size).encloses(bounds):rejected.append("safe")
		var named:Dictionary={"stick":screen.stick,"action":screen.action_button,"finish":screen.finish_button,"timer":screen.timer_label,"chapter":screen.chapter_label,"hint":screen.hint_label,"pause":screen.controls.pause_button,"progress":screen.controls.progress_label,"bar":screen.controls.turn_progress}
		for key:String in named:
			var control:Control=named[key]
			var region:Rect2=(local*control.get_global_transform_with_canvas())*Rect2(Vector2.ZERO,control.size)
			if control.is_visible_in_tree() and bounds.intersects(region):
				rejected.append(key)
				if first_rejection.is_empty():first_rejection={"bubble":str(bounds),"region":str(region),"kind":key,"actor":str(actor.global_position)}
		for key:String in rejected:rejection_counts[key]=int(rejection_counts.get(key,0))+1
		if bubble.is_visible_in_tree():
			visible_ticks+=1
			if not Rect2(Vector2.ZERO,screen.reaction_strip.size).encloses(Rect2(bubble.position,bubble.size)):unsafe_ticks+=1

func _finish()->void:
	if is_instance_valid(screen):
		if is_instance_valid(screen.soundscape):screen.soundscape.set_backgrounded(true)
		screen.queue_free()
	await process_frame
	if session!=null:session.invalidate_identity()
	if is_instance_valid(api):api.response=Callable();api.queue_free()
	await process_frame
	print("First Steps photo world: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

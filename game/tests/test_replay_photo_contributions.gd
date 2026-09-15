extends SceneTree
## Exact contribution photos across a real two-stage completed replay. Synthetic
## JPEGs and transport only; session, proof verification, replay and strip are real.
const Preview = preload("res://relay_preview.gd")
const Session = preload("res://services/relay_online_session.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const WAIT_MS := 8000

class Memory:
	extends RefCounted
	var values: Dictionary = {}
	func load_scope(scope: String) -> Dictionary:
		return {"ok":true,"found":values.has(scope),"value":values.get(scope,{}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		values[scope]=value.duplicate(true)
		return {"ok":true}

class Api:
	extends Node
	signal release_read
	var player_id := GUEST
	var device_token := "synthetic-not-a-credential"
	var base_url := "https://synthetic.invalid"
	var busy := false
	var response: Callable
	var hold_turn := ""
	var held := false
	var photo_turns: Array[String] = []
	var non_gets := 0
	var collisions := 0
	func configured() -> bool: return true
	func request_json(method: int, path: String, _body: Dictionary={}) -> Dictionary:
		if busy:
			collisions+=1
			return {"ok":false,"status":0,"code":"request_busy"}
		busy=true
		if method!=HTTPClient.METHOD_GET: non_gets+=1
		# Snapshot the exact response before holding it. A later stage cannot
		# rewrite old bytes in this transport to make a stale result look current.
		var result: Dictionary=response.call(path)
		if "/photos/" in path:
			var turn:=path.get_file()
			photo_turns.append(turn)
			if turn==hold_turn:
				hold_turn=""
				held=true
				await release_read
				held=false
			else:
				await get_tree().process_frame
		busy=false
		return result

var checks := 0
var failures := 0
var records: Dictionary = {}
var photos: Dictionary = {}
var missing: Array[String] = []
var room: Dictionary = {}
var api: Api
var screen: Node
var session: RefCounted
var store: Memory
var photo_store: Memory

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func _ok(data: Dictionary) -> Dictionary:
	return {"ok":true,"status":200,"data":data}

func _response(path: String) -> Dictionary:
	if path=="/v2/capabilities":
		var chapter:=Registry.descriptor(Registry.FIRST_STEPS)
		return _ok({"api_version":2,"recording_version":2,"simulation_version":2,"mutations_enabled":true,"photo_uploads_enabled":true,"validation":"structural_client_replay_required","chapters":[{"level_id":chapter.level_id,"level_version":chapter.level_version,"definition_hash":chapter.definition_hash,"recording_version":4,"simulation_version":4,"premium":false}]})
	if path=="/v2/rooms": return _ok({"rooms":[room.duplicate(true)]})
	if path=="/v2/rooms/"+ROOM: return _ok(room.duplicate(true))
	if path.begins_with("/v2/rooms/"+ROOM+"/photos/"):
		var turn:=path.get_file()
		if turn in missing: return _ok({"photo":null,"jpeg_base64":null})
		if photos.has(turn):
			var photo: Dictionary=photos[turn]
			return _ok({"photo":{"schema_version":1,"turn_id":turn,"owner_player_id":HOST if records[turn].player_slot=="p0" else GUEST,"recording_hash":records[turn].recording_hash,"photo_revision":1,"sha256":photo.hash,"width":32,"height":32,"byte_length":photo.bytes.size(),"updated_at":"2026-09-14T12:00:00Z"},"jpeg_base64":Marshalls.raw_to_base64(photo.bytes)})
	return {"ok":false,"status":404,"code":"not_found"}

func _run() -> void:
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i(1280,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	var stages:=PackedStringArray(["a-little-lift","a-place-to-grow"])
	var colors: Array[Color]=[Color("e84b46"),Color("48bc62"),Color("447ddc"),Color("eac14c")]
	var hashes: Array[String]=[]
	for index in range(2):
		for role: String in ["a","b"]:
			var turn:="t0-%d-%s"%[index,role]
			records[turn]=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first_steps/"+stages[index]+"-"+role+".json"))
			var color: Color=colors[photos.size()]
			var image:=Image.create(32,32,false,Image.FORMAT_RGB8)
			image.fill(color)
			var bytes:=image.save_jpg_to_buffer()
			var hash:=HashingContext.new()
			hash.start(HashingContext.HASH_SHA256)
			hash.update(bytes)
			var digest:=hash.finish().hex_encode()
			hashes.append(digest)
			photos[turn]={"bytes":bytes,"hash":digest,"color":color}
	_check(hashes.size()==4 and hashes.all(func(value: String) -> bool: return hashes.count(value)==1),"Four contributions have four distinct real JPEG payloads")
	var checkpoint: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first_steps/final-checkpoint.json"))
	var level:=Registry.definition(Registry.FIRST_STEPS)
	room={"api_version":2,"schema_version":2,"room_id":ROOM,"revision":5,"branch":0,"stage_index":2,"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),"host_id":HOST,"guest_id":GUEST,"checkpoint":checkpoint,"a_turn_id":null,"completed_pair_ids":["p0-0","p0-1"],"invite_expires_at":"2026-09-21T12:00:00Z","created_at":"2026-09-14T12:00:00Z","updated_at":"2026-09-14T12:00:00Z","active_role":"complete","first_player_id":null,"active_player_id":null,"player_slot":"p1","stage_id":"","recording_a":null,"validation":"structural_client_replay_required"}
	api=Api.new()
	api.response=_response
	root.add_child(api)
	store=Memory.new()
	photo_store=Memory.new()
	session=Session.new(api,func() -> Dictionary: return {"ready":true,"player_id":GUEST,"epoch":1},store)
	session.photo_store=photo_store
	_check(await session.load_lobby() and await session.open_room(ROOM),"Real session/coordinator verify the exact completed First Steps proof")
	if session.coordinator==null or session.coordinator.read_only:
		await _finish()
		return
	var saved_before:=Canonical.digest(store.values)
	var room_before:=Canonical.digest(session.coordinator.snapshot())
	screen=Preview.new()
	screen.online_session=session
	screen.settings={"sound":false,"haptics":false,"reduced_motion":true,"left_handed":false}
	root.add_child(screen)
	screen.set_physics_process(false)
	screen.set_process(false)
	screen.world.set_process(false)
	await process_frame
	await process_frame
	_check(screen.mode=="complete" and screen.world.get_script()==Registry.world_script(Registry.FIRST_STEPS),"Real completed replay mounts the First Steps world and production photo strip")
	await _four_photos()
	await _missing_next_photo()
	await _late_previous_stage()
	_check(Canonical.digest(store.values)==saved_before and Canonical.digest(session.coordinator.snapshot())==room_before and session.coordinator.draft().is_empty() and session.coordinator.pending().is_empty(),"All replay/photo transitions leave the verified room and gameplay store unchanged")
	_check(photo_store.values.is_empty() and api.non_gets==0 and api.collisions==0,"Viewing distinct photos makes GETs only, without photo-journal writes or overlapping transport ownership")
	await _finish()

func _start() -> void:
	screen.replay_pair_index=0
	screen._play_collection_pair()

func _wait_photos(label: String) -> bool:
	var deadline:=Time.get_ticks_msec()+WAIT_MS
	while (api.busy or screen.reaction_strip._draining) and Time.get_ticks_msec()<deadline:
		await process_frame
	var ready: bool=not api.busy and not screen.reaction_strip._draining
	_check(ready,label+": bounded asynchronous reads finish")
	return ready

func _advance_to_second() -> bool:
	# Feed the immutable recorded inputs through the real replay process. Do not
	# assign a new stage index or call a fabricated completion to skip the pair.
	var steps:=0
	while screen.mode=="replay" and screen.replay_pair_index==0 and steps<602:
		screen._physics_process(1.0/30.0)
		steps+=1
	var advanced: bool=screen.mode=="replay" and screen.replay_pair_index==1
	_check(advanced and steps>0,"Actual first-pair replay advances to the second stage")
	return advanced

func _assert_bubbles(expected: Dictionary, label: String) -> void:
	var found: Dictionary={}
	for bubble: Control in screen.reaction_strip._bubbles:
		var slot: String=bubble.get_meta("player_slot")
		var reference: Dictionary=bubble.get_meta("reference")
		_check(not found.has(slot),label+": at most one current contribution image per physical spirit")
		found[slot]=reference.get("turn_id")
		if not expected.has(slot):
			_check(false,label+": no old or unrequested contribution is attached")
			continue
		var turn: String=expected[slot]
		_check(reference.turn_id==turn and reference.recording_hash==records[turn].recording_hash and reference.player_slot==records[turn].player_slot and reference.owner_player_id==(HOST if slot=="p0" else GUEST),label+": exact turn/hash/owner follows its verified physical slot")
		var views:=bubble.get_children().filter(func(node: Node) -> bool: return node is TextureRect)
		_check(views.size()==1,label+": actual strip has decoded the contribution JPEG")
		if views.size()==1:
			var pixels: Image=views[0].texture.get_image()
			var pixel:=pixels.get_pixel(pixels.get_width() >> 1,pixels.get_height() >> 1)
			var color: Color=photos[turn].color
			_check(absf(pixel.r-color.r)<0.06 and absf(pixel.g-color.g)<0.06 and absf(pixel.b-color.b)<0.06,label+": rendered texture contains this contribution's distinct pixels")
	_check(found==expected,label+": exact set of current-stage spirit photos, without a latest-avatar fallback")

func _four_photos() -> void:
	missing.clear()
	var reads_before:=api.photo_turns.size()
	_start()
	if not await _wait_photos("first stage"): return
	_assert_bubbles({"p0":"t0-0-a","p1":"t0-0-b"},"first stage")
	if not _advance_to_second(): return
	_check(screen.reaction_strip._bubbles.is_empty(),"A new stage immediately clears the previous contribution images before new GETs finish")
	if not await _wait_photos("second stage"): return
	_assert_bubbles({"p0":"t0-1-b","p1":"t0-1-a"},"role-swapped second stage")
	_check(api.photo_turns.slice(reads_before)==["t0-0-a","t0-0-b","t0-1-a","t0-1-b"],"Combined replay requests each of the four exact contribution endpoints in stage order")

func _missing_next_photo() -> void:
	missing.assign(["t0-1-b"])
	_start()
	if not await _wait_photos("prior photos before missing next"): return
	_assert_bubbles({"p0":"t0-0-a","p1":"t0-0-b"},"prior stage before missing next")
	if not _advance_to_second(): return
	if not await _wait_photos("missing next photo"): return
	_assert_bubbles({"p1":"t0-1-a"},"missing host next contribution")
	_check(screen.reaction_strip._bubbles.all(func(bubble: Control) -> bool: return bubble.get_meta("player_slot")!="p0"),"Host's earlier red photo is not reused when the next host contribution has no shared photo")
	missing.clear()

func _late_previous_stage() -> void:
	var reads_before:=api.photo_turns.size()
	api.hold_turn="t0-0-a"
	_start()
	_check(api.held and api.busy and screen.reaction_strip._bubbles.is_empty(),"A genuinely outstanding first-stage response leaves replay imagery absent, not substituted")
	if not _advance_to_second():
		if api.held: api.release_read.emit()
		await _wait_photos("failed transition cleanup")
		return
	for frame in range(3): await process_frame
	_check(screen.replay_pair_index==1 and screen.reaction_strip._bubbles.is_empty() and api.photo_turns.slice(reads_before)==["t0-0-a"],"Next stage stays image-free while the old transport owner drains; no instant-arrival claim")
	api.release_read.emit()
	if not await _wait_photos("late prior-stage response"): return
	_assert_bubbles({"p0":"t0-1-b","p1":"t0-1-a"},"after old response drains")
	_check(api.photo_turns.slice(reads_before)==["t0-0-a","t0-1-a","t0-1-b"],"Late old result is excluded and only the newest pair is subsequently fetched")

func _finish() -> void:
	if is_instance_valid(api) and api.held: api.release_read.emit()
	if is_instance_valid(screen):
		if is_instance_valid(screen.soundscape): screen.soundscape.set_backgrounded(true)
		screen.queue_free()
	await process_frame
	if session!=null: session.invalidate_identity()
	if is_instance_valid(api):
		api.response=Callable()
		api.queue_free()
	await process_frame
	print("Replay contribution photos: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

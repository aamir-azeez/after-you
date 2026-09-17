extends SceneTree

const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const State = preload("res://services/turn_state.gd")
const Levels = preload("res://core/levels.gd")
const FakeApi = preload("res://tests/fake_rooms_api.gd")
const Presence = preload("res://services/friend_presence.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var first: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-a.json"))
	var second: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-b.json"))
	_check(State.review(Levels.get_level(0),first,{}).valid and State.review(Levels.get_level(0),second,{"a":first}).valid,"Room layout uses valid deterministic handoff recordings")
	var path := "user://room-layout-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,720)
	root.add_child(viewport)
	var app := Main.new()
	app.saves=Storage.new(path)
	app.saves.data.settings.sound=false
	app.saves.flush()
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	# The real presence label must fit even before a partner response arrives.
	var presence := Presence.new()
	root.add_child(presence)
	presence.set_process(false)
	app.friend_presence = presence
	var api := FakeApi.new()
	app.add_child(api)
	app.api=api
	var waiting := {"schema_version":1,"room_id":"room-layout","revision":1,"attempt":0,"level_id":"first-light","level_index":0,"host_id":"host","guest_id":null,"first_player_id":"host","active_role":"a","invite_code":"0123456789ABCDEF0123","recordings":{"a":null,"b":null}}
	var joined: Dictionary=waiting.duplicate(true)
	joined.merge({"revision":3,"guest_id":"guest","active_role":"b","recordings":{"a":first,"b":null}},true)
	var complete: Dictionary=joined.duplicate(true)
	complete.merge({"revision":4,"active_role":"complete","recordings":{"a":first,"b":second}},true)
	var pending := {"room_id":"room-layout","owner_player_id":"guest","base_revision":3,"idempotency_key":"synthetic-pending-turn","recording":second,"rejected":false}
	var other_pending: Dictionary=pending.duplicate(true)
	other_pending.room_id="another-room"
	for size: Vector2i in [Vector2i(1280,720),Vector2i(1600,720),Vector2i(1280,960)]:
		viewport.size=size
		await process_frame
		for scenario: Dictionary in [
			{"label":"Waiting first player","player":"host","room":waiting,"pending":{}},
			{"label":"Joined second player","player":"guest","room":joined,"pending":{}},
			{"label":"Completed room","player":"host","room":complete,"pending":{}},
			{"label":"Pending submission","player":"guest","room":joined,"pending":pending},
			{"label":"Completed room with another held request","player":"guest","room":complete,"pending":other_pending},
		]:
			api.player_id=scenario.player
			app.saves.update_values({},["pending_turn"])
			if not scenario.pending.is_empty():
				app.saves.update_values({"pending_turn":scenario.pending.duplicate(true)})
			app._accept_room({"ok":true,"data":scenario.room.duplicate(true)})
			await process_frame
			_check(app.mode=="room" and app.active_room.active_role==scenario.room.active_role,scenario.label+" renders through the real saved room acceptance flow")
			_check_visible(app.overlay,Rect2(Vector2.ZERO,Vector2(size)),scenario.label)
		var held: Dictionary=pending.duplicate(true)
		held.rejected=true
		held.error="This room is no longer available to this identity. Keep the rehearsal locally; it will not be submitted again."
		app.saves.update_values({"pending_turn":held})
		app._show_held_turn(held)
		await process_frame
		_check_visible(app.overlay,Rect2(Vector2.ZERO,Vector2(size)),"Rejected held submission")
	_check(api.calls.is_empty(),"Room layout checks never send network requests or submit a recording")
	viewport.queue_free()
	presence.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix):
			DirAccess.remove_absolute(path+suffix)
	print("AFTER YOU ROOM LAYOUT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func _check_visible(node: Node, screen: Rect2, context: String) -> void:
	if node is Button or node is Label or node is PanelContainer:
		var description: String=node.text if node is Button or node is Label else "dialog panel"
		_check(screen.encloses(node.get_global_rect()),"%s at %s: %s has bounds %s" % [context,screen.size,description,node.get_global_rect()])
	for child: Node in node.get_children():
		_check_visible(child,screen,context)

func _check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)

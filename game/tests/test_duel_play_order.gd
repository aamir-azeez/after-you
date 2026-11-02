extends "res://tests/test_relay_online.gd"
## Play on a duel's page through the real Main, room lobby flow and room
## session (only the server is a stand-in): the duel's room create is kept
## and sent, the room opens for either member whatever the turn order, your
## partner's room is joined when theirs came first, and a refusal brings the
## duel's page back with its reason, never the room hub. Synthetic ids only.
const DuelsClient = preload("res://services/duels_client.gd")
const DuelPage = preload("res://presentation/duels/duel_page.gd")
const DUEL := "d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1"
const BOARD := "relay-isles@2"
const INVITE := "A1A1A1A1A1A1A1A1A1A1"

## The pair's room as the duel holds it ({} before anyone made it), and how
## the server answers the next duel room create: "" makes it, else the refusal code.
var duel_room: Dictionary = {}
var refuse_create := ""
var kind := "ghost"

func _duel_view(owner: String) -> Dictionary:
	# This player's turn comes second: the partner (GUEST) has the first.
	var side := {"members": [GUEST, HOST], "you": true, "steps": 0, "ticks": 0, "turn": 0, "finished": false, "left": false, "check": "none",
		"room_id": duel_room.get("room_id"), "invite_code": duel_room.get("invite_code"), "hosting": duel_room.get("host") == owner}
	var view := {"schema_version": 1, "duel_id": DUEL, "kind": kind, "board": BOARD, "status": "running", "steps": 4, "created_ms": 1, "accepted_ms": 1, "updated_ms": 2,
		"mine": 0, "sides": [side, null], "ghost": null, "result": null, "eligible": false}
	if kind == "ghost": view.ghost = {"source": "developer", "entry_id": null, "rank": null, "ticks": 588, "names": null}
	else: view.sides[1] = {"members": [null, null], "you": false, "steps": 0, "ticks": 0, "turn": null, "finished": false, "left": false, "check": "none"}
	return view

func _duel_server(request: Dictionary, api: FakeApi) -> Dictionary:
	var path: String = request.path
	if path == "/v2/capabilities":
		var answer := _server(request, api)
		answer.data["duels_version"] = 1
		return answer
	if path == "/v1/duels":
		return _ok({"schema_version": 1, "party": {"partner": GUEST, "intact": true, "invites_in": [], "invite_out": null}, "duels": [_duel_view(request.owner)]})
	if path.begins_with("/v1/duels/"):
		return _ok({"schema_version": 1, "duel": _duel_view(request.owner)})
	if path == "/v2/rooms" and request.method == HTTPClient.METHOD_POST and request.body.has("duel"):
		if not refuse_create.is_empty():
			if refuse_create == "duel_room_taken": duel_room = {"room_id": ROOM, "invite_code": INVITE, "host": GUEST}
			return {"ok": false, "status": 409, "code": refuse_create, "error": "Synthetic refusal " + refuse_create + "."}
		duel_room = {"room_id": ROOM, "invite_code": INVITE, "host": request.owner}
	if path.begins_with("/v1/"):
		return _ok({})
	return _server(request, api)

func _run() -> void:
	for name: String in ["relay-a","relay-b","garden-a","garden-b","initial-checkpoint","relay-checkpoint","final-checkpoint"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/"+name+".json"))
	_index_keeps_duel_create()
	for each: String in ["ghost", "friend"]:
		kind = each
		await _refused_comes_back()
		await _second_turn_makes_room()
		await _partner_first_is_joined()
	for path: String in cleanup_paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	await create_timer(1.0).timeout
	print("After You duel play order: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

## The bug the owner hit: a duel room create was never kept (its body has a
## `duel` the saved request check did not allow), so it was never sent.
func _index_keeps_duel_create() -> void:
	var identity := Identity.new()
	var session := Session.new(_api(), identity.get_value, MemoryStore.new())
	var body := {"idempotency_key": "k".repeat(36), "level_id": "relay-isles", "level_version": 2, "definition_hash": Canonical.digest(level), "duel": {"duel_id": DUEL, "board": BOARD}}
	var index := {"schema_version": 2, "owner_player_id": HOST, "room_ids": [], "standalone_ids": [], "last_room": "", "pending": {"path": "/v2/rooms", "body": body, "request_hash": Canonical.digest({"path": "/v2/rooms", "body": body})}}
	session._ready()
	_check(session._valid_index(index), "a saved duel room create is a valid pending request")
	for bad: Variant in [{"duel_id": DUEL}, {"duel_id": "x", "board": BOARD}, {"duel_id": DUEL, "board": BOARD, "extra": 1}, "duel"]:
		var wrong := body.duplicate(true)
		wrong.duel = bad
		index.pending = {"path": "/v2/rooms", "body": wrong, "request_hash": Canonical.digest({"path": "/v2/rooms", "body": wrong})}
		_check(not session._valid_index(index), "a malformed duel in a saved create is refused: %s" % [bad])
	var hard := body.duplicate(true)
	hard["mode"] = "hard"
	index.pending = {"path": "/v2/rooms", "body": hard, "request_hash": Canonical.digest({"path": "/v2/rooms", "body": hard})}
	_check(not session._valid_index(index), "a duel's room is never a hard room")

## A fresh Main on this phone (HOST), Duels open on the duel's page.
func _app() -> Array:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	root.add_child(viewport)
	var app := Main.new()
	var path := "user://duel-play-order-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	cleanup_paths.append(path)
	app.saves = Save.new(path)
	app.saves.data.settings.sound = false
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.api.queue_free()
	var api := _api()
	api.responder = _duel_server.bind(api)
	root.remove_child(api)
	app.add_child(api)
	app.api = api
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.identity_data = {"player_id":HOST,"device_token":"synthetic-device-token"}
	app.relay_session = Session.new(api,app._relay_identity,MemoryStore.new())
	await app.relay_session.load_capabilities()
	# Every chapter reached (the marks are not read in this harness).
	app.home_keepsakes.read_only = true
	app.duels_flow.open()
	await _frames(4)
	var view: Dictionary = DuelsClient.valid_view(_duel_view(HOST))
	app.duels_flow._open_duel(view)
	await _frames(4)
	api.calls.clear()
	return [app, api, view, viewport]

func _creates(api: FakeApi) -> Array:
	return api.calls.filter(func(call: Dictionary) -> bool: return call.method == HTTPClient.METHOD_POST and call.path == "/v2/rooms")

func _hub_reads(api: FakeApi) -> int:
	return api.calls.filter(func(call: Dictionary) -> bool: return call.path == "/v1/room-inbox").size()

func _done(made: Array) -> void:
	made[3].queue_free()
	await _frames(2)

## A create the server refuses: back on the duel's page with the reason.
func _refused_comes_back() -> void:
	duel_room = {}
	refuse_create = "duel_not_running"
	var made := await _app()
	var app: Main = made[0]
	var api: FakeApi = made[1]
	await app.duels_flow._play(made[2])
	await _frames(4)
	var page: Variant = app.duels_flow.screen.overlay() if app.duels_flow.is_open() else null
	_check(_creates(api).size() == 1, "%s: the duel room create is sent" % kind)
	_check(page is DuelPage and page.view.duel_id == DUEL and app.mode == "duels" and not app.room_hub_flow.is_open() and _hub_reads(api) == 0, "%s: a refused create brings back the duel's page, never the room hub (mode %s)" % [kind, app.mode])
	_check(app.toast.take_plain() == "Synthetic refusal duel_not_running.", "%s: the refusal's reason shows" % kind)
	_check(app.relay_session.pending_lobby().is_empty(), "%s: a refused create is not kept" % kind)
	refuse_create = ""
	await _done(made)

## The member whose turn is second taps Play before anyone opened the duel: their create makes the room and it opens.
func _second_turn_makes_room() -> void:
	duel_room = {}
	refuse_create = ""
	var made := await _app()
	var app: Main = made[0]
	var api: FakeApi = made[1]
	await app.duels_flow._play(made[2])
	await _frames(4)
	var creates := _creates(api)
	_check(creates.size() == 1 and creates[0].body.get("duel") == {"duel_id": DUEL, "board": BOARD}, "%s: the second-turn member's Play sends the duel's room create: %s" % [kind, creates])
	_check(is_instance_valid(app.relay_child) and not app.room_hub_flow.is_open() and _hub_reads(api) == 0 and not app.duels_flow.is_open(), "%s: the duel's room opens, not the room hub (mode %s)" % [kind, app.mode])
	await _done(made)

## Both tapped at once and the partner's create came first: this phone joins their room.
func _partner_first_is_joined() -> void:
	duel_room = {}
	refuse_create = "duel_room_taken"
	var made := await _app()
	var app: Main = made[0]
	var api: FakeApi = made[1]
	await app.duels_flow._play(made[2])
	await _frames(4)
	var joins: Array = api.calls.filter(func(call: Dictionary) -> bool: return call.path == "/v2/rooms/join")
	_check(_creates(api).size() == 1 and joins.size() == 1 and joins[0].body.invite_code == INVITE, "%s: the partner's room is joined after the create is refused as taken: %s" % [kind, api.calls.map(func(call: Dictionary) -> String: return call.path)])
	_check(not app.room_hub_flow.is_open() and _hub_reads(api) == 0 and (is_instance_valid(app.relay_child) or app.duels_flow.is_open()), "%s: joining the partner's room never shows the room hub (mode %s)" % [kind, app.mode])
	refuse_create = ""
	await _done(made)

func _frames(count: int) -> void:
	for index in range(count): await process_frame

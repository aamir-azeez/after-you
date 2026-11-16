extends RefCounted
## Explicit room controls. An uncertain acceptance retains its exact fork key.
const OpenTurns = preload("res://core/physical/open_turns.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Journal = preload("res://services/relay_online_store.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const Typed = preload("res://services/typed_values.gd")
const Registry = preload("res://services/chapter_registry.gd")
## Start over (backend redo-control.ts startOverSource): the same one-row request, naming the room's
## live checkpoint where a redo names the first turn. The asker is its second player and the friend
## who answers its first; agreeing is a fork back to the first stage. Each action is its redo
## action with this prefix.
const OVER := "over_"
const OVER_ACTIONS := ["over_request", "over_decline", "over_cancel", "over_accept"]
## Refusals that settle a request for good: the pending one is dropped, as for a changed source.
const SETTLED := ["redo_source_changed","redo_request_missing","stale_revision","room_not_found","room_deleted","player_blocked","redo_request_pending","start_over_unavailable","nothing_to_fork","room_history_full","room_member_left","wrong_redo_player"]

class DiskStore:
	extends RefCounted
	var journal := Journal.new()
	func read(scope: String) -> Dictionary:
		return journal.load_scope(scope)
	func write(scope: String, value: Dictionary) -> bool:
		return journal.save_scope(scope,value).get("ok",false)

var busy := false
var last_code := ""
var last_error := ""
var accepted := false
var restore_replay_transfer: Callable
var recover_replay_operation: Callable
var _api: Node
var _identity: Callable
var _store: RefCounted
var _binding: Dictionary = {}
var _family := ""
var _room: Dictionary = {}
var _source: Dictionary = {}
var _state: Dictionary = {}
var _view: Dictionary = {}
var _generation := 0
var _storage_ready := false
## The idempotency key of an accept made in this session and not sent yet: its
## first send needs no receipt check, since nothing can hold it yet. A key read
## back from disk is checked first, as before.
var _fresh_key := ""
## A room whose run started over since this phone last read it (take_run_reset).
var _run_reset := ""

func _init(api: Node, identity: Callable, store: RefCounted = null) -> void:
	_api = api
	_identity = identity
	_store = DiskStore.new() if store == null else store

func invalidate() -> void:
	_generation += 1
	busy = false
	_binding = {}
	_room = {}
	_source = {}
	_state = {}
	_view = {}
	accepted = false
	_storage_ready = false

func _context() -> Dictionary:
	var value: Variant = _identity.call()
	if not value is Dictionary or value.get("ready") != true or not _id(value.get("player_id")) or not is_instance_valid(_api) or _api.player_id != value.player_id or _api.device_token.is_empty(): return {}
	return {"player_id":value.player_id,"epoch":int(value.get("epoch",0)),"credential":str(_api.device_token).sha256_text(),"base_url":str(_api.base_url)}

func bind_room(family: String, room: Dictionary) -> bool:
	if busy: return _fail("request_busy")
	var context := _context()
	if context.is_empty(): return _fail("identity_changed")
	var preserve_view: bool = _storage_ready and context == _binding and _family == family and Typed.equal(_room.get("room_id"), room.get("room_id")) and Typed.same(_source,source_for(family,room))
	var previous_view := _view.duplicate(true)
	var previous_state := _state.duplicate(true)
	if context != _binding:
		invalidate()
		_binding = context
	if family != "relay" or not _id(room.get("room_id")) or context.player_id not in [room.get("host_id"),room.get("guest_id")]: return _fail("room_not_found")
	if not pending().is_empty() and (_room.get("room_id") != room.room_id or _family != family): return _fail("request_busy")
	_family = family
	_room = room.duplicate(true)
	_source = source_for(family, room)
	_view = {}
	_storage_ready = false
	accepted = false
	var loaded: Dictionary = _store.read(_scope())
	if not loaded.get("ok",false): return _fail("redo_storage_unavailable")
	var value: Variant = loaded.get("value",{})
	if not value is Dictionary or (not value.is_empty() and not _valid_state(value)): return _fail("redo_storage_unavailable")
	_state = {"schema_version":1,"owner_player_id":context.player_id,"family":family,"room_id":room.room_id,"server_hash":str(_api.base_url).sha256_text(),"pending":{}} if value.is_empty() else value.duplicate(true)
	if preserve_view and Typed.same(previous_state,_state): _view = previous_view
	_storage_ready = true
	return true

func pending() -> Dictionary: return _state.get("pending",{}).duplicate(true)
## The room whose run started over since this phone last read it, once, or "".
func take_run_reset() -> String:
	var room_id := _run_reset
	_run_reset = ""
	return room_id

## A version 2 read names the branch the room's run last began again on (run_from). A
## larger one than this phone kept means the friend agreed to start over since: the
## old run's copies go (services/room_run_reset.gd). The first read only keeps it, as
## a phone that never saw the room's run has nothing of an older one to drop.
func _note_run(view: Dictionary) -> void:
	if not view.has("run_from") or _binding.is_empty() or _room.is_empty(): return
	var scope := "relay-run-v1:" + str(_binding.player_id) + ":" + str(_room.room_id)
	var loaded: Dictionary = _store.read(scope)
	if not loaded.get("ok", false): return
	var kept: Variant = loaded.get("value", {})
	var now := int(view.run_from)
	var before := Typed.as_int(kept.get("run_from"), -1) if kept is Dictionary else -1
	if before == now: return
	if not _store.write(scope, {"schema_version": 1, "run_from": now}): return
	if before >= 0 and now > before: _run_reset = str(_room.room_id)
func bound_room(family: String) -> Dictionary:
	return _room.duplicate(true) if family == _family and _storage_ready and _same(_generation) else {}
func bound_room_id(family: String) -> String:
	return str(_room.get("room_id","")) if family == _family and _storage_ready and _same(_generation) else ""
func observe_room_failure(room_id: String, code: String) -> bool:
	# Called only for an authenticated read of this exact room, never for an
	# omitted lobby row or a generic connectivity/authentication failure.
	if busy or not _storage_ready or not _same(_generation) or _room.get("room_id")!=room_id or code not in ["room_not_found","room_deleted","player_blocked"]: return false
	_failed_reply({"code":code})
	return pending().is_empty()
func view() -> Dictionary: return _view.duplicate(true) if _same(_generation) else {}
func can_request() -> bool: return _can("second_player_id") and _view.get("request") == null and not (_view.get("start_over") is Dictionary and _view.start_over.get("status") == "pending")
func can_accept() -> bool: return _can("first_player_id") and _view.get("request") is Dictionary and _view.request.status == "pending"
func can_cancel() -> bool: return _can("second_player_id") and _view.get("request") is Dictionary and _view.request.status == "pending"
## Play my turn again (version 2 reads): the server says this player may record their saved
## first turn again now, because the friend's phone has not fetched it.
func replace_open() -> bool: return _can("first_player_id") and _view.get("replace_open") == true
## The room's start over request as the last version 2 read showed it, or {}.
func start_over() -> Dictionary:
	var request: Variant = _view.get("start_over") if _ready_view() else null
	return request.duplicate(true) if request is Dictionary else {}
## Who this player is in it: "asker", "friend" or "".
func start_over_role() -> String:
	var request := start_over()
	if request.is_empty(): return ""
	return "asker" if request.source.second_player_id == _binding.player_id else "friend" if request.source.first_player_id == _binding.player_id else ""
## This player may ask: a version 2 read showed no request on this room position yet.
func can_ask_start_over() -> bool: return _ready_view() and _view.get("schema_version") == 2 and _view.get("start_over") == null and _view.get("request") == null and not start_over_source(_room, str(_binding.get("player_id", ""))).is_empty()
func can_answer_start_over() -> bool: return start_over_role() == "friend" and start_over().status == "pending"
func can_cancel_start_over() -> bool: return start_over_role() == "asker" and start_over().status == "pending"
func request_start_over() -> bool: return await _prepare("over_request") if can_ask_start_over() else _fail("redo_unavailable")
func cancel_start_over() -> bool: return await _prepare("over_cancel") if can_cancel_start_over() else _fail("redo_unavailable")
func decline_start_over() -> bool: return await _prepare("over_decline") if can_answer_start_over() else _fail("redo_unavailable")
func accept_start_over() -> bool: return await _prepare("over_accept") if can_answer_start_over() else _fail("redo_unavailable")
## An agreement (to a redo or a start over) is still out: the room waits for it.
func accept_pending() -> bool: return pending().get("action") in ["accept", "over_accept"]
func _ready_view() -> bool: return _storage_ready and not busy and pending().is_empty() and _same(_generation) and not _room.is_empty()
func _can(role: String) -> bool:
	return _storage_ready and not busy and pending().is_empty() and _same(_generation) and not _source.is_empty() and _source.get(role) == _binding.player_id and Typed.same(_view.get("source"), _source)

func refresh() -> bool:
	if busy or not _storage_ready or not _same(_generation) or _room.is_empty(): return _fail("request_busy")
	var generation := _generation
	busy = true
	_view = {}
	var response := await _net(HTTPClient.METHOD_GET, _path()+"/redo", {}, generation)
	if not _same(generation): return false
	busy = false
	if not response.get("ok",false): return _fail(str(response.get("code","redo_unavailable")))
	if not _valid_view(response.get("data")): return _fail("redo_source_changed")
	_view = response.data.duplicate(true)
	_note_run(_view)
	last_code = ""
	last_error = ""
	return true

## The redo state a room poll carried (relay_online_session.gd take_polled_redo), in place of
## refresh()'s own read. False, and nothing kept, unless it is valid for this exact source.
func observe(value: Variant) -> bool:
	if busy or not _storage_ready or not _same(_generation) or _room.is_empty() or not _valid_view(value): return false
	_view = value.duplicate(true)
	_note_run(_view)
	return true

func request_redo() -> bool: return await _prepare("request") if can_request() else _fail("redo_unavailable")
func decline() -> bool: return await _prepare("decline") if can_accept() else _fail("redo_unavailable")
func cancel() -> bool: return await _prepare("cancel") if can_cancel() else _fail("redo_unavailable")
func accept() -> bool: return await _prepare("accept") if can_accept() else _fail("redo_unavailable")

func _prepare(action: String) -> bool:
	var over := action.begins_with(OVER)
	# A start over's source is the asker's: this player's own when asking, else the one the room holds.
	var source: Dictionary = _source if not over else start_over_source(_room, str(_binding.player_id)) if action == "over_request" else start_over().get("source", {})
	var body := {"action":action.trim_prefix(OVER),"source":source.duplicate(true)}
	var checkpoint_hash := str(_room.get("checkpoint",{}).get("checkpoint_hash",""))
	var stage_id := str(_room.get("stage_id",""))
	if action in ["accept", "over_accept"]:
		body = {"base_revision":source.revision,"idempotency_key":RoomsApi.new_key(),"redo_request_id":Canonical.digest(source)}
		body.merge({"branch":source.branch,"stage_index":0 if over else source.stage_index})
	if action == "over_accept":
		# The fork goes back to the first stage: its checkpoint and stage.
		var first := first_stage(_room)
		if first.is_empty(): return _fail("redo_unavailable")
		checkpoint_hash = first.checkpoint_hash
		stage_id = first.stage_id
	var next := _state.duplicate(true)
	next.pending = {"action":action,"body":body,"source":source.duplicate(true),"checkpoint_hash":checkpoint_hash,"stage_id":stage_id}
	if not _persist(next): return false
	_fresh_key = str(body.get("idempotency_key", "")) if action in ["accept", "over_accept"] else ""
	return await retry()

func retry(allow_mutations: bool = true) -> bool:
	if busy or not _storage_ready or not _same(_generation) or pending().is_empty(): return _fail("redo_unavailable")
	var operation := pending()
	var generation := _generation
	busy = true
	accepted = false
	var response: Dictionary = {}
	var agreeing: bool = operation.action in ["accept", "over_accept"]
	var fresh: bool = agreeing and not _fresh_key.is_empty() and str(operation.body.get("idempotency_key", "")) == _fresh_key
	_fresh_key = ""
	if agreeing and not fresh:
		response = await _net(HTTPClient.METHOD_GET, _path()+"/operations/"+str(operation.body.idempotency_key), {}, generation)
		if response.get("status") == 410 and response.get("code") == "replay_transferred" and recover_replay_operation.is_valid():
			response = await recover_replay_operation.call(str(_room.room_id), str(operation.body.idempotency_key), _transfer_receipt_valid.bind(operation))
		if not _same(generation): return false
		if not response.get("ok",false) and not (response.get("status")==404 and response.get("code")=="operation_not_found"):
			busy = false
			return _failed_reply(response)
	if not response.get("ok",false):
		if not allow_mutations:
			busy = false
			return _fail("v2_mutations_disabled")
		response = await _net(HTTPClient.METHOD_POST, _path() + ("/fork" if agreeing else "/redo"), operation.body, generation)
		if not agreeing and response.get("status") == 410 and response.get("code") == "replay_transferred" and restore_replay_transfer.is_valid():
			var restored: Dictionary = await restore_replay_transfer.call(str(_room.room_id))
			if not _same(generation): return false
			response = await _net(HTTPClient.METHOD_POST, _path()+"/redo", operation.body, generation) if restored.get("ok", false) else restored
	if not _same(generation): return false
	busy = false
	if not response.get("ok",false):
		return _failed_reply(response)
	if agreeing:
		if not _accepted_response(response.get("data"),operation): return _fail("unsupported_redo_response")
	elif operation.action.begins_with(OVER):
		# A start over's answer is that request's own state: it goes in the view's start_over.
		var data: Variant = response.get("data")
		if not valid_view(data, operation.source) or data.request == null: return _fail("redo_source_changed")
		_view["start_over"] = data.request.duplicate(true)
	else:
		if not _valid_view(response.get("data")): return _fail("redo_source_changed")
		_view = response.data.duplicate(true)
	var next := _state.duplicate(true)
	next.pending = {}
	if not _persist(next): return false
	accepted = agreeing
	if accepted: _view = {}
	last_code = ""
	last_error = ""
	return true

func _transfer_receipt_valid(receipt: Variant, operation: Dictionary) -> bool:
	return _same(_generation) and Typed.same(pending(), operation) and valid_fork_receipt(receipt, operation.source, operation.body, operation.checkpoint_hash, operation.stage_id)

func _failed_reply(response: Dictionary) -> bool:
	var code := str(response.get("code","redo_unavailable"))
	if code in SETTLED:
		var cleared := _state.duplicate(true)
		cleared.pending = {}
		if not _persist(cleared): return false
		_view = {}
	return _fail(code)

func _net(method: int, path: String, body: Dictionary, generation: int) -> Dictionary:
	if not _same(generation): return {"ok":false,"code":"request_busy"}
	var response: Dictionary = await _api.request_json(method,path,body,_same.bind(generation))
	if generation == _generation and not _same(generation): invalidate()
	return response if _same(generation) else {"ok":false,"code":"identity_changed"}
func _same(generation: int) -> bool: return generation == _generation and not _binding.is_empty() and _binding == _context()
func _path() -> String: return "/v2/rooms/" + str(_room.room_id)
func _scope() -> String: return "relay-redo-" + _family + "-v1:" + str(_binding.player_id) + ":" + str(_room.room_id)
func _persist(value: Dictionary) -> bool:
	if not _storage_ready or not _same(_generation) or not _valid_state(value) or not _store.write(_scope(),value): return _fail("redo_storage_unavailable")
	if not _same(_generation): return false
	_state = value.duplicate(true)
	return true
func _fail(code: String) -> bool:
	last_code = code
	last_error = RoomsApi.error_message(code)
	return false

func _valid_view(value: Variant) -> bool:
	return valid_view(value, _source, _room)

## A redo state: version 1 ({schema_version 1, source, request}), or version 2 (a poll or read
## with X-AfterYou-Poll-Redo: 2), which adds the room's start over request (start_over, checked
## against `room`), whether Play my turn again is open (replace_open) and the branch the
## room's run last began again on (run_from).
static func valid_view(value: Variant, source: Dictionary, room: Dictionary = {}) -> bool:
	if value is Dictionary and value.size() == 6 and Typed.equal(value.get("schema_version"), 2) and value.get("replace_open") is bool and value.has("start_over") and Typed.whole_number(value.get("run_from")) and int(value.run_from) >= 0 and int(value.run_from) < 32:
		var over: Variant = value.start_over
		if over != null and not (over is Dictionary and _valid_request(over, over.get("source")) and _valid_source(over.source) and Typed.same(over.source, start_over_source(room, str(over.source.get("second_player_id", ""))))): return false
		return valid_view({"schema_version": 1, "source": value.get("source"), "request": value.get("request")}, source)
	if not value is Dictionary or value.size()!=3 or not Typed.equal(value.get("schema_version"), 1) or not value.has("source") or not value.has("request"): return false
	if source.is_empty(): return value.source == null and value.request == null
	if not Typed.same(value.source,source): return false
	if value.request == null: return true
	return _valid_request(value.request, source)

static func _valid_request(request: Variant, source: Variant) -> bool:
	return request is Dictionary and source is Dictionary and request.size()==3 and Typed.equal(request.get("request_id"), Canonical.digest(source)) and Typed.same(request.get("source"),source) and request.get("status") in ["pending","declined","cancelled","accepted"]

func _accepted_response(value: Variant, operation: Dictionary) -> bool:
	if not value is Dictionary: return false
	var room: Variant = value.get("room")
	if not room is Dictionary or not Typed.equal(room.get("room_id"), _room.room_id) or not Typed.equal(room.get("host_id"), _room.host_id) or not Typed.equal(room.get("guest_id"), _room.guest_id) or Typed.as_int(room.get("revision"),-1)<=int(operation.source.revision): return false
	return valid_fork_receipt(value.get("receipt"),operation.source,operation.body,operation.checkpoint_hash,operation.stage_id)

static func valid_fork_receipt(receipt: Variant, source: Dictionary, body: Dictionary, checkpoint_hash: String, stage_id: String) -> bool:
	if not receipt is Dictionary or receipt.size() != 13: return false
	# Validate wire types before numeric/string equality. Malformed replies must
	# fail closed, rather than raising a Variant comparison error during recovery.
	for field: String in ["schema_version","accepted_revision","branch","stage_index"]:
		var value: Variant = receipt.get(field)
		if not (value is int or value is float) or not is_finite(float(value)) or value != floor(value) or value < 0 or value > 9007199254740991: return false
	for field: String in ["room_id","idempotency_key","request_hash","operation","stage_id","checkpoint_hash"]:
		if not receipt.get(field) is String: return false
	for field: String in ["turn_id","recording_hash","pair_id"]:
		if not receipt.has(field) or receipt[field] != null: return false
	var request: Dictionary = body.duplicate(true)
	request.operation = "fork"
	return receipt.schema_version==2 and receipt.room_id==source.room_id and receipt.operation=="fork" and receipt.idempotency_key==body.idempotency_key and receipt.request_hash==Canonical.digest(request) and receipt.accepted_revision==int(source.revision)+1 and receipt.branch==int(source.branch)+1 and receipt.stage_index==body.get("stage_index", source.stage_index) and receipt.stage_id==stage_id and receipt.checkpoint_hash==checkpoint_hash

func _valid_state(value: Dictionary) -> bool:
	return valid_journal(value,str(_binding.get("player_id","")),_family,str(_room.get("room_id","")),str(_api.base_url))

static func valid_journal(value: Dictionary, owner: String, family: String, room_id: String, base_url: String) -> bool:
	if JSON.stringify(value).length()>8192 or value.size()!=6 or not Typed.equal(value.get("schema_version"), 1) or not Typed.equal(value.get("owner_player_id"), owner) or not Typed.equal(value.get("family"), family) or not Typed.equal(value.get("room_id"), room_id) or not Typed.equal(value.get("server_hash"), base_url.sha256_text()) or not value.get("pending") is Dictionary: return false
	var operation: Dictionary = value.pending
	if operation.is_empty(): return true
	if operation.size()!=5 or operation.get("action") not in ["request","decline","cancel","accept"] + OVER_ACTIONS or not _valid_source(operation.get("source")) or operation.source.room_id!=value.room_id or owner not in [operation.source.first_player_id,operation.source.second_player_id] or not operation.get("body") is Dictionary or not operation.get("checkpoint_hash") is String or not operation.get("stage_id") is String: return false
	var body: Dictionary = operation.body
	var action := str(operation.action).trim_prefix(OVER)
	var over := str(operation.action).begins_with(OVER)
	var expected_owner: String = operation.source.first_player_id if action in ["accept","decline"] else operation.source.second_player_id
	if owner != expected_owner: return false
	if action != "accept": return body.size()==2 and Typed.equal(body.get("action"), action) and Typed.same(body.get("source"),operation.source)
	return body.size()==5 and Typed.equal(body.get("base_revision"), operation.source.revision) and Typed.equal(body.get("redo_request_id"), Canonical.digest(operation.source)) and body.get("idempotency_key") is String and body.idempotency_key.length()==36 and Typed.equal(body.get("branch"), operation.source.branch) and Typed.equal(body.get("stage_index"), 0 if over else operation.source.stage_index)

static func source_for(family: String, room: Dictionary) -> Dictionary:
	if family != "relay" or not Typed.equal(room.get("active_role"), "b") or not _id(room.get("host_id")) or not _id(room.get("guest_id")) or room.get("first_player_id") not in [room.get("host_id"),room.get("guest_id")]: return {}
	# The source names the stage's latest turn (open turns: its latest pass), who played it and who plays next.
	var view: Variant = room.get("open_turns")
	var a: Variant = view.get("newest") if view is Dictionary and view.has("newest") else OpenTurns.memory(room).prior
	if not a is Dictionary or a.is_empty(): return {}
	# Before open turns the latest is always the first turn, so the stage's second player is next.
	var next: Variant = room.get("active_player_id") if room.has("open_turns") else (room.guest_id if room.first_player_id==room.get("host_id") else room.get("host_id"))
	if next not in [room.get("host_id"), room.get("guest_id")]: return {}
	var source := {"room_id":room.get("room_id"),"revision":room.get("revision"),"branch":room.get("branch"),"stage_index":room.get("stage_index"),"a_hash":a.get("recording_hash"),"first_player_id":room.guest_id if next==room.get("host_id") else room.get("host_id"),"second_player_id":next}
	return source if _valid_source(source) else {}
## The start over source `player` would ask with on this room (backend startOverSource): a relay
## room in play with both members, something to undo, and the live checkpoint; else {}.
static func start_over_source(room: Dictionary, player: String) -> Dictionary:
	if not _id(room.get("host_id")) or not _id(room.get("guest_id")) or player not in [room.get("host_id"), room.get("guest_id")] or room.get("active_role") not in ["a", "b"] or not room.get("checkpoint") is Dictionary: return {}
	if Typed.as_int(room.get("stage_index"), -1) == 0 and room.get("a_turn_id") == null: return {}
	var source := {"room_id":room.get("room_id"),"revision":room.get("revision"),"branch":room.get("branch"),"stage_index":room.get("stage_index"),"a_hash":room.checkpoint.get("checkpoint_hash"),"first_player_id":room.guest_id if player == room.host_id else room.host_id,"second_player_id":player}
	return source if _valid_source(source) else {}

## The first stage of `room`'s chapter: its checkpoint hash and stage id, or {}.
static func first_stage(room: Dictionary) -> Dictionary:
	var chapter := Registry.resolve(room)
	if chapter.is_empty() or not room.get("checkpoint") is Dictionary: return {}
	var checkpoint: Dictionary = room.checkpoint
	# Open turns fingerprints: a flat checkpoint nests nothing; every chain starts at the chapter's first.
	if not checkpoint.has("proof") and int(checkpoint.get("stage_index", 0)) > 0: checkpoint = Registry.initial_checkpoint(chapter)
	while int(checkpoint.get("stage_index", 0)) > 0:
		checkpoint = Registry.previous_checkpoint(chapter, checkpoint)
		if checkpoint.is_empty(): return {}
	var stages: Array = Registry.definition(chapter).get("stages", [])
	return {"checkpoint_hash": str(checkpoint.get("checkpoint_hash", "")), "stage_id": str(stages[0].id)} if not stages.is_empty() else {}

static func _valid_source(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=7 or not _id(value.get("room_id")) or not _id(value.get("first_player_id")) or not _id(value.get("second_player_id")) or value.first_player_id==value.second_player_id or not value.get("a_hash") is String or value.a_hash.length()!=64: return false
	for key: String in ["revision","branch","stage_index"]:
		var number: Variant = value.get(key)
		if not (number is int or number is float) or number<0 or number>9007199254740991 or number!=floor(number): return false
	for character: String in value.a_hash:
		if character not in "0123456789abcdef": return false
	return true
static func _id(value: Variant) -> bool:
	return Typed.valid_id(value)

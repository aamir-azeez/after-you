extends RefCounted
## A server double for one open turns room that keeps turns the way the
## fingerprints wire says (claude-20261011/open-turns-fingerprints/WIRE.md):
## turn k of a stage becomes its fingerprint when turn k+1 is accepted, a
## closing turn stays full until the member who did not play it names a
## revision at or past it (a poll's X-AfterYou-Known-Room or their next turn's
## base_revision), pair rows hold fingerprints and flat checkpoints, and turn
## copies come back through want / send-back / ack (section 9). It checks what
## the server checks: base revision, a flat checkpoint linked by hash to the
## room's and naming exactly the stage's turns, and a sent-back copy hashing to
## a fingerprint it holds. Only HTTP is doubled; the phones are real coordinators.
## Turns also chain to the one before by their start and hand-off hashes and hand-off tick (backend/src/v2/open-turns.ts
## carryFits), a pass lasts at least the rest of the friend's turn, a stage's first pip is the one its checkpoint names
## (next_first_slot) and the closing checkpoint names the pip that did not close it.
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Registry = preload("res://services/chapter_registry.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
const OpenTurnStore = preload("res://services/open_turn_store.gd")
const Canonical = preload("res://core/v2/canonical.gd")

var chapter := ""
var level: Dictionary = {}
var room_id := ""
var host := ""
var guest := ""
var revision := 1
var stage_index := 0
var checkpoint: Dictionary = {}
var completed: Array = []
## The current stage's turns: [{"turn_id", "player", "revision", "hash"}].
var stage: Array = []
## Every turn row by hash: the record as held, full or its fingerprint.
var rows: Dictionary = {}
var pairs: Dictionary = {}
## The last closing turn waiting for its acknowledgement: {"hash", "revision", "reader"} or {}.
var closing: Dictionary = {}
## Turns each member asked for, and the copies sent back for them.
var wanted: Dictionary = {}
var copies: Dictionary = {}
var receipts: Dictionary = {}
var requests: Array = []
## Bytes of every full record the server held after each accepted turn (WIRE.md: only the newest and a closing turn).
var full_after_turn: Array = []

func _init(chapter_key: String, room: String, host_id: String, guest_id: String) -> void:
	chapter = chapter_key
	level = Registry.definition(chapter_key)
	room_id = room
	host = host_id
	guest = guest_id
	checkpoint = Registry.initial_checkpoint(chapter_key)

## The coordinator's transport for `player`.
func transport(request: Dictionary) -> Dictionary:
	requests.append(request.duplicate(true))
	var player := str(request.owner_player_id)
	var path := str(request.path)
	var base := "/v2/rooms/" + room_id
	var result: Dictionary
	if path == base and request.method == HTTPClient.METHOD_GET: result = _read(player, request.get("headers", PackedStringArray()))
	elif path == base + "/turns": result = _turn(player, request.body)
	elif path.begins_with(base + "/pairs/"): result = _pair(path.get_file())
	elif path == base + "/turn-copies/want": result = _want(player, request.body)
	elif path == base + "/turn-copies": result = _send_back(player, request.body)
	elif path == base + "/turn-copies/ack": result = _ack(player, request.body)
	else: result = {"ok": false, "status": 404, "code": "not_found"}
	# Real HTTP hands over JSON.
	return JSON.parse_string(JSON.stringify(result))

func _ok(data: Variant) -> Dictionary:
	return {"ok": true, "status": 200, "data": data}

func _fail(status: int, code: String) -> Dictionary:
	return {"ok": false, "status": status, "code": code}

func done() -> bool:
	return stage_index >= level.stages.size()

## The pip that plays the stage's turn 1: the checkpoint's (the host's for the first stage).
func _first_slot() -> String:
	return str(checkpoint.get("next_first_slot", "p0"))

## Whether `recording` starts from the stage's latest turn at its hand-off, as the server's carryFits checks.
func _hands_off(recording: Dictionary) -> bool:
	if stage.is_empty(): return int(recording.get("handoff_tick", -1)) == 0 and recording.get("handoff_hash") == recording.get("start_hash")
	var memory: Dictionary = rows[stage[-1].hash]
	var handoff := int(rows[stage[-2].hash].duration_ticks) - int(memory.get("handoff_tick", 0)) if stage.size() >= 2 else 0
	return recording.get("start_hash") == memory.get("handoff_hash") and int(recording.get("handoff_tick", -1)) == handoff and 		(recording.completed == true or int(recording.duration_ticks) >= int(memory.duration_ticks) - handoff)

func _member(slot: String) -> String:
	return host if slot == "p0" else guest

## The member who plays turn `turn` of the current stage.
func _player_of(turn: int) -> String:
	return _member(OpenTurns.slot(_first_slot(), turn))

func view(player: String) -> Dictionary:
	var finished := done()
	var turn := 0 if finished else stage.size() + 1
	var value := {"api_version": 2, "schema_version": 2, "room_id": room_id, "revision": revision, "branch": 0, "stage_index": stage_index,
		"level_id": level.id, "level_version": level.version, "definition_hash": Canonical.digest(level), "host_id": host, "guest_id": guest,
		"checkpoint": checkpoint.duplicate(true), "a_turn_id": stage[0].turn_id if not stage.is_empty() else null, "completed_pair_ids": completed.duplicate(),
		"invite_expires_at": "2026-12-01T12:00:00Z", "created_at": "2026-11-16T12:00:00Z", "updated_at": "2026-11-16T12:%02d:00Z" % (revision % 60),
		"active_role": "complete" if finished else ("a" if stage.is_empty() else "b"),
		"first_player_id": null if finished else _member(_first_slot()), "active_player_id": null if finished else _player_of(turn),
		"player_slot": "p0" if player == host else "p1", "stage_id": "" if finished else str(level.stages[stage_index].id),
		"recording_a": OpenTurnStore.strip(_full(stage[0].hash)) if not stage.is_empty() else null, "validation": "structural_client_replay_required",
		"simulation_version": int(level.simulation_version)}
	if player == host: value["invite_code"] = "A1".repeat(10)
	var other := guest if player == host else host
	value["open_turns"] = {"turn": turn, "cap": 0 if finished else OpenTurns.cap(level.stages[stage_index]), "must_finish": not finished and turn >= OpenTurns.cap(level.stages[stage_index]),
		"pass_bytes": 0 if finished else 262144, "turn_hashes": stage.map(func(item: Dictionary) -> String: return item.hash),
		"newest": _full(stage[-1].hash) if not stage.is_empty() else null, "closing": _full(closing.hash) if not closing.is_empty() else null,
		"wanted": wanted.get(other, []).filter(func(item: String) -> bool: return not OpenTurnStore.full(rows.get(item)) and not copies.has(item))}
	return value

## A full record the server holds (a row or a copy sent back), or the row as held.
func _full(named: String) -> Dictionary:
	if copies.has(named): return copies[named].duplicate(true)
	return rows.get(named, {}).duplicate(true)

func _stub(named: String) -> void:
	if rows.has(named): rows[named] = OpenTurnStore.strip(rows[named])

func _read(player: String, headers: PackedStringArray) -> Dictionary:
	for header: String in headers:
		if header.begins_with("X-AfterYou-Known-Room: "):
			var named := header.trim_prefix("X-AfterYou-Known-Room: ")
			_acknowledge(player, int(named.get_slice(".", 0)))
	return _ok(view(player))

## The member who did not play the closing turn names a revision at or past it: it goes to its fingerprint.
func _acknowledge(player: String, known: int) -> void:
	if closing.is_empty() or player != closing.reader or known < int(closing.revision): return
	_stub(closing.hash)
	closing = {}

func _turn(player: String, body: Dictionary) -> Dictionary:
	if receipts.has(body.idempotency_key): return _ok({"receipt": receipts[body.idempotency_key], "room": view(player)})
	if done() or int(body.base_revision) != revision: return _fail(409, "stale_revision")
	var turn := stage.size() + 1
	if player != _player_of(turn): return _fail(403, "not_your_turn")
	var recording: Dictionary = body.recording
	if not recording.has("packed") or not OpenTurnStore.hash_ok(recording): return _fail(400, "invalid_recording")
	if not _hands_off(recording): return _fail(409, "source_recording_mismatch")
	_acknowledge(player, int(body.base_revision))
	var turn_id := OpenTurns.turn_id(0, stage_index, turn)
	var closes: bool = recording.role == "b" and recording.completed == true
	if closes:
		var flat: Variant = body.get("checkpoint")
		var names: Array = stage.map(func(item: Dictionary) -> String: return item.hash) + [recording.recording_hash]
		if not flat is Dictionary or flat.has("proof") or flat.previous_checkpoint_hash != checkpoint.checkpoint_hash or not Canonical.same(flat.turn_hashes, names): return _fail(400, "invalid_checkpoint")
		if (int(flat.get("schema_version", 0)) != 9 or flat.get("next_first_slot") != ("p0" if recording.player_slot == "p1" else "p1")): return _fail(422, "checkpoint_recording_mismatch")
	# Turn k goes to its fingerprint as turn k+1 is accepted.
	if not stage.is_empty(): _stub(stage[-1].hash)
	revision += 1
	rows[recording.recording_hash] = recording.duplicate(true)
	stage.append({"turn_id": turn_id, "player": player, "revision": revision, "hash": recording.recording_hash})
	var pair_id: Variant = null
	if closes:
		pair_id = "p0-%d" % stage_index
		pairs[pair_id] = {"pair_id": pair_id, "branch": 0, "stage_index": stage_index, "a": OpenTurnStore.strip(rows[stage[0].hash]), "b": OpenTurnStore.strip(recording), "checkpoint": body.checkpoint.duplicate(true)}
		completed.append(pair_id)
		checkpoint = body.checkpoint.duplicate(true)
		closing = {"hash": recording.recording_hash, "revision": revision, "reader": guest if player == host else host}
		stage = []
		stage_index += 1
	var receipt := {"schema_version": 2, "room_id": room_id, "idempotency_key": body.idempotency_key, "request_hash": Coordinator._request_hash("turns", body),
		"operation": "turns", "accepted_revision": revision, "branch": 0, "stage_index": stage_index - 1 if closes else stage_index,
		"stage_id": str(level.stages[stage_index - 1 if closes else stage_index].id), "turn_id": turn_id, "recording_hash": recording.recording_hash,
		"pair_id": pair_id, "checkpoint_hash": checkpoint.checkpoint_hash}
	receipts[body.idempotency_key] = receipt
	full_after_turn.append(rows.values().filter(func(row: Dictionary) -> bool: return OpenTurnStore.full(row)).size())
	return _ok({"receipt": receipt, "room": view(player)})

func _pair(pair_id: String) -> Dictionary:
	return _ok(pairs[pair_id].duplicate(true)) if pairs.has(pair_id) else _fail(404, "pair_not_found")

func _want(player: String, body: Dictionary) -> Dictionary:
	var asked: Array = body.recording_hashes
	var found: Array = []
	var still: Array = wanted.get(player, [])
	for named: String in asked:
		var held := _full(named)
		if OpenTurnStore.full(held): found.append(held)
		elif rows.has(named) and named not in still: still.append(named)
	wanted[player] = still
	return _ok({"schema_version": 1, "copies": found})

func _send_back(player: String, body: Dictionary) -> Dictionary:
	var other := guest if player == host else host
	var kept: Array = []
	for record: Dictionary in body.turns:
		var named := str(record.get("recording_hash", ""))
		if named in wanted.get(other, []) and rows.has(named) and OpenTurnStore.matches(record, OpenTurnStore.strip(record)) and Canonical.same(OpenTurnStore.strip(record), OpenTurnStore.strip(rows[named])):
			copies[named] = record.duplicate(true)
			kept.append(named)
	return _ok({"schema_version": 1, "kept": kept})

func _ack(player: String, body: Dictionary) -> Dictionary:
	for named: String in body.recording_hashes:
		copies.erase(named)
		wanted[player] = wanted.get(player, []).filter(func(item: String) -> bool: return item != named)
	return _ok({"schema_version": 1})
